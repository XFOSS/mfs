const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const DiagnosticLevel = enum {
    debug,
    info,
    warn,
    err,
    fatal,

    pub fn toString(self: DiagnosticLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    pub fn shouldLog(self: DiagnosticLevel, min_level: DiagnosticLevel) bool {
        return @intFromEnum(self) >= @intFromEnum(min_level);
    }
};

pub const MemoryAllocation = struct {
    ptr: usize,
    size: usize,
    timestamp: i64,
    stack_trace: ?*std.builtin.StackTrace,
    freed: bool = false,
    free_timestamp: ?i64 = null,
};

pub const ErrorRecord = struct {
    error_name: []const u8,
    location: std.builtin.SourceLocation,
    timestamp: i64,
    count: u32 = 1,
    last_occurrence: i64,
};

pub const PerformanceMetrics = struct {
    frame_count: u64 = 0,
    total_frame_time: f64 = 0.0,
    min_frame_time: f64 = std.math.inf(f64),
    max_frame_time: f64 = 0.0,
    last_frame_time: f64 = 0.0,
    fps: f32 = 0.0,

    pub fn update(self: *PerformanceMetrics, frame_time: f64) void {
        self.frame_count += 1;
        self.total_frame_time += frame_time;
        self.last_frame_time = frame_time;

        if (frame_time < self.min_frame_time) {
            self.min_frame_time = frame_time;
        }
        if (frame_time > self.max_frame_time) {
            self.max_frame_time = frame_time;
        }

        self.fps = 1.0 / @as(f32, @floatCast(frame_time));
    }

    pub fn getAverageFrameTime(self: *const PerformanceMetrics) f64 {
        if (self.frame_count == 0) return 0.0;
        return self.total_frame_time / @as(f64, @floatFromInt(self.frame_count));
    }

    pub fn getAverageFPS(self: *const PerformanceMetrics) f32 {
        const avg_frame_time = self.getAverageFrameTime();
        if (avg_frame_time == 0.0) return 0.0;
        return 1.0 / @as(f32, @floatCast(avg_frame_time));
    }
};

pub const MemoryStats = struct {
    total_allocated: usize = 0,
    total_freed: usize = 0,
    peak_usage: usize = 0,
    current_usage: usize = 0,
    allocation_count: u64 = 0,
    deallocation_count: u64 = 0,
    leak_count: u64 = 0,

    pub fn recordAllocation(self: *MemoryStats, size: usize) void {
        self.total_allocated += size;
        self.current_usage += size;
        self.allocation_count += 1;

        if (self.current_usage > self.peak_usage) {
            self.peak_usage = self.current_usage;
        }
    }

    pub fn recordDeallocation(self: *MemoryStats, size: usize) void {
        self.total_freed += size;
        if (self.current_usage >= size) {
            self.current_usage -= size;
        }
        self.deallocation_count += 1;
    }

    pub fn recordLeak(self: *MemoryStats) void {
        self.leak_count += 1;
    }

    pub fn getEfficiency(self: *const MemoryStats) f32 {
        if (self.total_allocated == 0) return 100.0;
        return (@as(f32, @floatFromInt(self.total_freed)) / @as(f32, @floatFromInt(self.total_allocated))) * 100.0;
    }
};

pub const DiagnosticSystem = struct {
    allocator: Allocator,
    min_log_level: DiagnosticLevel,
    memory_tracking_enabled: bool,
    performance_tracking_enabled: bool,
    error_tracking_enabled: bool,

    // Memory tracking
    allocations: std.HashMap(usize, MemoryAllocation, std.hash_map.DefaultContext(usize)),
    memory_stats: MemoryStats,

    // Error tracking
    errors: std.HashMap(u64, ErrorRecord, std.hash_map.DefaultContext(u64)),

    // Performance tracking
    performance: PerformanceMetrics,

    // Output
    log_file: ?std.fs.File = null,
    console_output: bool = true,

    const Self = @This();

    pub fn init(allocator: Allocator, config: Config) !Self {
        var system = Self{
            .allocator = allocator,
            .min_log_level = config.min_log_level,
            .memory_tracking_enabled = config.memory_tracking_enabled,
            .performance_tracking_enabled = config.performance_tracking_enabled,
            .error_tracking_enabled = config.error_tracking_enabled,
            .allocations = std.HashMap(usize, MemoryAllocation, std.hash_map.DefaultContext(usize)).init(allocator),
            .errors = std.HashMap(u64, ErrorRecord, std.hash_map.DefaultContext(u64)).init(allocator),
            .memory_stats = MemoryStats{},
            .performance = PerformanceMetrics{},
            .console_output = config.console_output,
        };

        if (config.log_file_path) |path| {
            system.log_file = std.fs.cwd().createFile(path, .{}) catch |err| {
                std.log.warn("Failed to create log file '{s}': {s}", .{ path, @errorName(err) });
                return err;
            };
        }

        return system;
    }

    pub fn deinit(self: *Self) void {
        if (self.log_file) |file| {
            file.close();
        }

        // Check for memory leaks before cleanup
        if (self.memory_tracking_enabled) {
            self.checkMemoryLeaks();
        }

        self.allocations.deinit();
        self.errors.deinit();
    }

    pub fn log(self: *Self, level: DiagnosticLevel, comptime format: []const u8, args: anytype) void {
        if (!level.shouldLog(self.min_log_level)) return;

        const timestamp = std.time.milliTimestamp();
        const level_str = level.toString();

        const message = std.fmt.allocPrint(self.allocator, "[{d}] {s}: " ++ format ++ "\n", .{ timestamp, level_str } ++ args) catch {
            // Fallback if allocation fails
            if (self.console_output) {
                std.debug.print("[ALLOC_FAIL] {s}: " ++ format ++ "\n", .{level_str} ++ args);
            }
            return;
        };
        defer self.allocator.free(message);

        if (self.console_output) {
            std.debug.print("{s}", .{message});
        }

        if (self.log_file) |file| {
            file.writeAll(message) catch |err| {
                std.debug.print("Failed to write to log file: {s}\n", .{@errorName(err)});
            };
        }
    }

    pub fn recordAllocation(self: *Self, ptr: usize, size: usize) void {
        if (!self.memory_tracking_enabled) return;

        const allocation = MemoryAllocation{
            .ptr = ptr,
            .size = size,
            .timestamp = std.time.milliTimestamp(),
            .stack_trace = if (builtin.mode == .Debug) std.debug.getSelfDebugInfo() catch null else null,
        };

        self.allocations.put(ptr, allocation) catch |err| {
            self.log(.warn, "Failed to track allocation: {s}", .{@errorName(err)});
            return;
        };

        self.memory_stats.recordAllocation(size);

        if (builtin.mode == .Debug) {
            self.log(.debug, "Allocated {d} bytes at 0x{X}", .{ size, ptr });
        }
    }

    pub fn recordDeallocation(self: *Self, ptr: usize) void {
        if (!self.memory_tracking_enabled) return;

        if (self.allocations.getPtr(ptr)) |allocation| {
            allocation.freed = true;
            allocation.free_timestamp = std.time.milliTimestamp();
            self.memory_stats.recordDeallocation(allocation.size);

            if (builtin.mode == .Debug) {
                const lifetime = allocation.free_timestamp.? - allocation.timestamp;
                self.log(.debug, "Freed {d} bytes at 0x{X} (lifetime: {d}ms)", .{ allocation.size, ptr, lifetime });
            }

            _ = self.allocations.remove(ptr);
        } else {
            self.log(.warn, "Attempted to free untracked pointer: 0x{X}", .{ptr});
        }
    }

    pub fn recordError(self: *Self, err: anyerror, location: std.builtin.SourceLocation) void {
        if (!self.error_tracking_enabled) return;

        const error_name = @errorName(err);
        const hash = std.hash.hashString(error_name) ^ std.hash.CityHash64.hashWithSeed(std.mem.asBytes(&location), 0);
        const timestamp = std.time.milliTimestamp();

        if (self.errors.getPtr(hash)) |existing| {
            existing.count += 1;
            existing.last_occurrence = timestamp;
        } else {
            const record = ErrorRecord{
                .error_name = error_name,
                .location = location,
                .timestamp = timestamp,
                .last_occurrence = timestamp,
            };

            self.errors.put(hash, record) catch |put_err| {
                self.log(.warn, "Failed to track error: {s}", .{@errorName(put_err)});
                return;
            };
        }

        self.log(.err, "Error '{s}' at {s}:{d}:{d}", .{ error_name, location.file, location.line, location.column });
    }

    pub fn updatePerformance(self: *Self, frame_time: f64) void {
        if (!self.performance_tracking_enabled) return;

        self.performance.update(frame_time);

        if (self.performance.frame_count % 600 == 0) { // Log every 10 seconds at 60 FPS
            self.log(.info, "Performance: FPS={d:.1}, Frame Time={d:.2}ms (avg={d:.2}ms)", .{
                self.performance.fps,
                self.performance.last_frame_time * 1000.0,
                self.performance.getAverageFrameTime() * 1000.0,
            });
        }
    }

    pub fn checkMemoryLeaks(self: *Self) void {
        if (!self.memory_tracking_enabled) return;

        var leak_count: u32 = 0;
        var leaked_bytes: usize = 0;

        var iterator = self.allocations.valueIterator();
        while (iterator.next()) |allocation| {
            if (!allocation.freed) {
                leak_count += 1;
                leaked_bytes += allocation.size;
                self.memory_stats.recordLeak();

                self.log(.err, "Memory leak: {d} bytes at 0x{X} (age: {d}ms)", .{
                    allocation.size,
                    allocation.ptr,
                    std.time.milliTimestamp() - allocation.timestamp,
                });
            }
        }

        if (leak_count > 0) {
            self.log(.err, "Total memory leaks: {d} allocations, {d} bytes", .{ leak_count, leaked_bytes });
        } else {
            self.log(.info, "No memory leaks detected", .{});
        }
    }

    pub fn generateReport(self: *Self) !void {
        self.log(.info, "=== DIAGNOSTIC REPORT ===", .{});

        // Memory statistics
        if (self.memory_tracking_enabled) {
            self.log(.info, "Memory Statistics:", .{});
            self.log(.info, "  Total Allocated: {d} bytes", .{self.memory_stats.total_allocated});
            self.log(.info, "  Total Freed: {d} bytes", .{self.memory_stats.total_freed});
            self.log(.info, "  Current Usage: {d} bytes", .{self.memory_stats.current_usage});
            self.log(.info, "  Peak Usage: {d} bytes", .{self.memory_stats.peak_usage});
            self.log(.info, "  Allocations: {d}", .{self.memory_stats.allocation_count});
            self.log(.info, "  Deallocations: {d}", .{self.memory_stats.deallocation_count});
            self.log(.info, "  Leaks: {d}", .{self.memory_stats.leak_count});
            self.log(.info, "  Efficiency: {d:.1}%", .{self.memory_stats.getEfficiency()});
        }

        // Performance statistics
        if (self.performance_tracking_enabled) {
            self.log(.info, "Performance Statistics:", .{});
            self.log(.info, "  Total Frames: {d}", .{self.performance.frame_count});
            self.log(.info, "  Average FPS: {d:.1}", .{self.performance.getAverageFPS()});
            self.log(.info, "  Average Frame Time: {d:.2}ms", .{self.performance.getAverageFrameTime() * 1000.0});
            self.log(.info, "  Min Frame Time: {d:.2}ms", .{self.performance.min_frame_time * 1000.0});
            self.log(.info, "  Max Frame Time: {d:.2}ms", .{self.performance.max_frame_time * 1000.0});
        }

        // Error statistics
        if (self.error_tracking_enabled) {
            self.log(.info, "Error Statistics:", .{});
            var total_errors: u64 = 0;
            var iterator = self.errors.valueIterator();
            while (iterator.next()) |error_record| {
                total_errors += error_record.count;
                self.log(.info, "  {s}: {d} occurrences", .{ error_record.error_name, error_record.count });
            }
            self.log(.info, "  Total Errors: {d}", .{total_errors});
        }

        self.log(.info, "=========================", .{});
    }

    pub const Config = struct {
        min_log_level: DiagnosticLevel = .info,
        memory_tracking_enabled: bool = true,
        performance_tracking_enabled: bool = true,
        error_tracking_enabled: bool = true,
        console_output: bool = true,
        log_file_path: ?[]const u8 = null,
    };
};

// Tracking allocator wrapper
pub const TrackingAllocator = struct {
    parent_allocator: Allocator,
    diagnostic_system: *DiagnosticSystem,

    const Self = @This();

    pub fn init(parent_allocator: Allocator, diagnostic_system: *DiagnosticSystem) Self {
        return Self{
            .parent_allocator = parent_allocator,
            .diagnostic_system = diagnostic_system,
        };
    }

    pub fn allocator(self: *Self) Allocator {
        return Allocator.init(self, alloc, resize, free);
    }

    fn alloc(self: *Self, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |ptr| {
            self.diagnostic_system.recordAllocation(@intFromPtr(ptr), len);
        }
        return result;
    }

    fn resize(self: *Self, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const result = self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        if (result) {
            // Handle resize as deallocation + allocation
            self.diagnostic_system.recordDeallocation(@intFromPtr(buf.ptr));
            self.diagnostic_system.recordAllocation(@intFromPtr(buf.ptr), new_len);
        }
        return result;
    }

    fn free(self: *Self, buf: []u8, buf_align: u8, ret_addr: usize) void {
        self.diagnostic_system.recordDeallocation(@intFromPtr(buf.ptr));
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }
};

// Global diagnostic instance
var global_diagnostics: ?*DiagnosticSystem = null;

pub fn init(allocator: Allocator, config: DiagnosticSystem.Config) !void {
    if (global_diagnostics != null) {
        return error.AlreadyInitialized;
    }

    const diagnostics = try allocator.create(DiagnosticSystem);
    diagnostics.* = try DiagnosticSystem.init(allocator, config);
    global_diagnostics = diagnostics;
}

pub fn deinit(allocator: Allocator) void {
    if (global_diagnostics) |diagnostics| {
        diagnostics.deinit();
        allocator.destroy(diagnostics);
        global_diagnostics = null;
    }
}

pub fn log(level: DiagnosticLevel, comptime format: []const u8, args: anytype) void {
    if (global_diagnostics) |diagnostics| {
        diagnostics.log(level, format, args);
    }
}

pub fn recordError(err: anyerror, location: std.builtin.SourceLocation) void {
    if (global_diagnostics) |diagnostics| {
        diagnostics.recordError(err, location);
    }
}

pub fn updatePerformance(frame_time: f64) void {
    if (global_diagnostics) |diagnostics| {
        diagnostics.updatePerformance(frame_time);
    }
}

pub fn generateReport() !void {
    if (global_diagnostics) |diagnostics| {
        try diagnostics.generateReport();
    }
}

// Convenience macros
pub fn debugLog(comptime format: []const u8, args: anytype) void {
    log(.debug, format, args);
}

pub fn infoLog(comptime format: []const u8, args: anytype) void {
    log(.info, format, args);
}

pub fn warnLog(comptime format: []const u8, args: anytype) void {
    log(.warn, format, args);
}

pub fn errorLog(comptime format: []const u8, args: anytype) void {
    log(.err, format, args);
}

pub fn fatalLog(comptime format: []const u8, args: anytype) void {
    log(.fatal, format, args);
}

// Test suite
test "diagnostic system initialization" {
    const allocator = std.testing.allocator;

    const config = DiagnosticSystem.Config{
        .min_log_level = .debug,
        .memory_tracking_enabled = true,
        .performance_tracking_enabled = true,
        .error_tracking_enabled = true,
    };

    var diagnostics = try DiagnosticSystem.init(allocator, config);
    defer diagnostics.deinit();

    try std.testing.expect(diagnostics.memory_tracking_enabled);
    try std.testing.expect(diagnostics.performance_tracking_enabled);
    try std.testing.expect(diagnostics.error_tracking_enabled);
}

test "memory tracking" {
    const allocator = std.testing.allocator;

    const config = DiagnosticSystem.Config{};
    var diagnostics = try DiagnosticSystem.init(allocator, config);
    defer diagnostics.deinit();

    // Simulate allocation and deallocation
    const ptr: usize = 0x1000;
    const size: usize = 256;

    diagnostics.recordAllocation(ptr, size);
    try std.testing.expectEqual(@as(usize, 256), diagnostics.memory_stats.current_usage);
    try std.testing.expectEqual(@as(u64, 1), diagnostics.memory_stats.allocation_count);

    diagnostics.recordDeallocation(ptr);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.memory_stats.current_usage);
    try std.testing.expectEqual(@as(u64, 1), diagnostics.memory_stats.deallocation_count);
}

test "performance tracking" {
    const allocator = std.testing.allocator;

    const config = DiagnosticSystem.Config{};
    var diagnostics = try DiagnosticSystem.init(allocator, config);
    defer diagnostics.deinit();

    // Simulate frame updates
    diagnostics.updatePerformance(0.016); // 60 FPS
    try std.testing.expectEqual(@as(u64, 1), diagnostics.performance.frame_count);
    try std.testing.expectApproxEqRel(@as(f32, 62.5), diagnostics.performance.fps, 0.1);

    diagnostics.updatePerformance(0.033); // 30 FPS
    try std.testing.expectEqual(@as(u64, 2), diagnostics.performance.frame_count);
}
