//! MFS Profiling System
//!
//! This module provides a profiling system for tracking performance metrics
//! such as CPU time, memory allocations, and custom counters.
//!
//! ## Usage Example
//! ```zig
//! const Profiler = @import("system/profiling/profiler.zig").Profiler;
//!
//! // Start a profiling zone
//! const zone_id = Profiler.beginZone("Physics Update");
//! defer Profiler.endZone(zone_id);
//!
//! // Mark an event
//! try Profiler.markEvent("Object Spawned");
//!
//! // Track a counter
//! try Profiler.trackCounter("Active Particles", particle_count);
//! ```

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Timer = std.time.Timer;

// Conditional Tracy integration
const tracy = if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy)
    @import("tracy")
else
    struct {
        pub fn ZoneN(comptime _: []const u8) void {}
        pub fn ZoneC(_: u32) void {}
        pub fn ZoneNC(comptime _: []const u8, _: u32) void {}
        pub fn ZoneEnd() void {}
        pub fn FrameMark() void {}
        pub fn FrameMarkNamed(comptime _: []const u8) void {}
        pub fn Message(comptime _: []const u8) void {}
        pub fn MessageL(_: []const u8) void {}
        pub fn AllocationContext(_: ?*anyopaque, _: usize) void {}
        pub fn FreeContext(_: ?*anyopaque) void {}
        pub fn PlotValue(comptime _: []const u8, _: f64) void {}
    };

/// Maximum number of profiled zones that can be active at once.
pub const MAX_ZONE_STACK_DEPTH: usize = 32;

/// Maximum number of entries in the profiling history.
pub const MAX_HISTORY_ENTRIES: usize = 256;

/// Color definitions for different profile categories.
pub const Colors = struct {
    pub const Rendering: u32 = 0x2E86C1; // Blue
    pub const Physics: u32 = 0x28B463; // Green
    pub const Audio: u32 = 0x8E44AD; // Purple
    pub const IO: u32 = 0xD35400; // Orange
    pub const Logic: u32 = 0xF1C40F; // Yellow
    pub const Memory: u32 = 0xE74C3C; // Red
    pub const System: u32 = 0x7F8C8D; // Gray
    pub const Network: u32 = 0x9B59B6; // Violet
    pub const AI: u32 = 0x2ECC71; // Emerald
    pub const UI: u32 = 0x3498DB; // Light Blue
};

/// Identifies a specific profiling zone.
pub const ZoneId = u32;

/// Represents a profiling event entry.
pub const ProfileEntry = struct {
    /// Unique name of the profiled zone.
    name: []const u8,
    /// Color used for visualizing this zone.
    color: u32,
    /// Start time in nanoseconds.
    start_time: u64,
    /// End time in nanoseconds.
    end_time: u64 = 0,
    /// Parent zone ID.
    parent_id: ?ZoneId = null,
    /// Thread ID this zone was recorded on.
    thread_id: std.Thread.Id,
    /// Optional custom data associated with the zone.
    custom_data: ?[]const u8 = null,

    /// Calculate duration in nanoseconds.
    pub fn duration(self: ProfileEntry) u64 {
        return if (self.end_time > 0) self.end_time - self.start_time else 0;
    }
};

/// Represents a performance counter with a name and value.
pub const CounterEntry = struct {
    name: []const u8,
    value: f64,
    timestamp: u64,
};

/// Represents a memory allocation for tracking.
pub const MemoryAllocation = struct {
    /// Pointer to the allocated memory.
    ptr: *anyopaque,
    /// Size of the allocation in bytes.
    size: usize,
    /// Timestamp when the allocation was made.
    timestamp: u64,
    /// Thread ID that made the allocation.
    thread_id: std.Thread.Id,
    /// Source location information (if available).
    source_file: ?[]const u8 = null,
    /// Line number in source file.
    source_line: ?u32 = null,
    /// Whether this allocation has been freed.
    freed: bool = false,
    /// Timestamp when the allocation was freed (if applicable).
    free_timestamp: ?u64 = null,
    /// Allocation category/tag for grouping.
    category: []const u8 = "default",
};

/// The main profiling system.
pub const Profiler = struct {
    /// Maximum number of memory allocations to track.
    pub const MAX_MEMORY_ALLOCATIONS: usize = 10000;

    /// Atomic counter for stack depth.
    const AtomicCounter = if (builtin.single_threaded)
        struct {
            value: usize = 0,
            pub fn fetchAdd(self: *@This(), operand: usize) usize {
                const result = self.value;
                self.value += operand;
                return result;
            }
        }
    else
        std.atomic.Value(usize);

    /// Profiler global state.
    var is_initialized: bool = false;
    var allocator: ?std.mem.Allocator = null;
    var global_timer: ?Timer = null;
    var zone_stack: [MAX_ZONE_STACK_DEPTH]ZoneId = undefined;
    var zone_stack_depth: AtomicCounter = if (builtin.single_threaded) .{} else .{ .value = 0 };

    /// Collected data.
    var entries: std.array_list.Managed(ProfileEntry) = undefined;
    var counters: std.array_list.Managed(CounterEntry) = undefined;
    var mutexes: struct {
        entries: std.Thread.Mutex = .{},
        counters: std.Thread.Mutex = .{},
        memory: std.Thread.Mutex = .{},
    } = .{};

    /// Memory tracking.
    var memory_allocations: std.AutoHashMap(*anyopaque, MemoryAllocation) = undefined;
    var total_allocated: usize = 0;

    var frame_start_time: u64 = 0;
    var frame_count: usize = 0;
    var enabled: bool = true;

    /// Initialize the profiler.
    pub fn init(alloc: std.mem.Allocator) !void {
        if (is_initialized) return;

        allocator = alloc;
        entries = std.array_list.Managed(ProfileEntry).init(alloc);
        counters = std.array_list.Managed(CounterEntry).init(alloc);
        memory_allocations = std.AutoHashMap(*anyopaque, MemoryAllocation).init(alloc);
        total_allocated = 0;
        global_timer = try Timer.start();
        is_initialized = true;

        try trackCounter("Memory Used", 0);
        try markEvent("Profiler Initialized");
    }

    /// Clean up profiler resources.
    pub fn deinit() void {
        if (!is_initialized) return;

        {
            mutexes.memory.lock();
            defer mutexes.memory.unlock();

            var it = memory_allocations.valueIterator();
            while (it.next()) |alloc| {
                if (alloc.source_file) |src_file| {
                    allocator.?.free(src_file);
                }
                if (!std.mem.eql(u8, alloc.category, "default")) {
                    allocator.?.free(alloc.category);
                }
            }

            memory_allocations.deinit();
        }

        entries.deinit();
        counters.deinit();
        allocator = null;
        global_timer = null;
        is_initialized = false;
    }

    /// Enable or disable profiling.
    pub fn setEnabled(enable: bool) void {
        enabled = enable;
    }

    /// Begin a new profiling zone.
    pub fn beginZone(name: []const u8) ZoneId {
        return beginZoneWithColor(name, Colors.System);
    }

    /// Begin a new profiling zone with a specific color.
    pub fn beginZoneWithColor(name: []const u8, color: u32) ZoneId {
        if (!enabled or !is_initialized) return 0;

        if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) {
            tracy.ZoneNC(name, color);
        }

        const now = getTime();

        const stack_pos = zone_stack_depth.fetchAdd(1);
        if (stack_pos >= MAX_ZONE_STACK_DEPTH) {
            std.log.warn("Profiler zone stack overflow. Too many nested zones!", .{});
            return 0;
        }

        const zone_id = @as(ZoneId, @intCast(entries.items.len + 1));
        zone_stack[stack_pos] = zone_id;

        const parent_id = if (stack_pos > 0) zone_stack[stack_pos - 1] else null;

        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        entries.append(.{
            .name = name,
            .color = color,
            .start_time = now,
            .parent_id = parent_id,
            .thread_id = std.Thread.getCurrentId(),
        }) catch {
            std.log.err("Failed to add profile entry", .{});
            return 0;
        };

        return zone_id;
    }

    /// End the current profiling zone.
    pub fn endZone(zone_id: ZoneId) void {
        if (!enabled or !is_initialized or zone_id == 0) return;

        if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) {
            tracy.ZoneEnd();
        }

        const now = getTime();

        if (zone_stack_depth.value == 0) {
            std.log.warn("Profiler zone stack underflow. Too many endZone calls!", .{});
            return;
        }

        _ = zone_stack_depth.fetchAdd(@as(usize, @bitCast(@as(isize, -1))));

        const entry_index = zone_id - 1;

        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        if (entry_index < entries.items.len) {
            entries.items[entry_index].end_time = now;
        }
    }

    /// Record an instantaneous event.
    pub fn markEvent(name: []const u8) !void {
        if (!enabled or !is_initialized) return;

        if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) {
            tracy.Message(name);
        }

        const now = getTime();

        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        try entries.append(.{
            .name = name,
            .color = Colors.System,
            .start_time = now,
            .end_time = now,
            .thread_id = std.Thread.getCurrentId(),
        });
    }

    /// Track a named counter value.
    pub fn trackCounter(name: []const u8, value: f64) !void {
        if (!enabled or !is_initialized) return;

        if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) {
            tracy.PlotValue(name, value);
        }

        mutexes.counters.lock();
        defer mutexes.counters.unlock();

        try counters.append(.{
            .name = name,
            .value = value,
            .timestamp = getTime(),
        });
    }

    /// Begin a new frame.
    pub fn beginFrame() void {
        if (!enabled or !is_initialized) return;

        if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) {
            tracy.FrameMark();
        }

        frame_start_time = getTime();
        markEvent("Frame Start") catch {};
    }

    /// End the current frame.
    pub fn endFrame() !void {
        if (!enabled or !is_initialized) return;

        const frame_end_time = getTime();
        const frame_time = frame_end_time - frame_start_time;

        frame_count += 1;
        try trackCounter("Frame Time (ms)", @as(f64, @floatFromInt(frame_time)) / 1_000_000.0);
        try markEvent("Frame End");

        if (entries.items.len > MAX_HISTORY_ENTRIES) {
            mutexes.entries.lock();
            defer mutexes.entries.unlock();

            const to_remove = entries.items.len - MAX_HISTORY_ENTRIES;
            if (to_remove > 0) {
                @memcpy(entries.items[0 .. entries.items.len - to_remove], entries.items[to_remove..]);
                entries.shrinkRetainingCapacity(entries.items.len - to_remove);
            }
        }

        if (counters.items.len > MAX_HISTORY_ENTRIES) {
            mutexes.counters.lock();
            defer mutexes.counters.unlock();

            const to_remove = counters.items.len - MAX_HISTORY_ENTRIES;
            if (to_remove > 0) {
                @memcpy(counters.items[0 .. counters.items.len - to_remove], counters.items[to_remove..]);
                counters.shrinkRetainingCapacity(counters.items.len - to_remove);
            }
        }
    }

    /// Remember memory allocation for profiling.
    pub fn trackAllocation(ptr: ?*anyopaque, size: usize, category: ?[]const u8, file: ?[]const u8, line: ?u32) void {
        if (!enabled or !is_initialized or ptr == null) return;

        if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) {
            tracy.AllocationContext(ptr, size);
        }

        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        total_allocated += size;

        const alloc = MemoryAllocation{
            .ptr = ptr.?,
            .size = size,
            .timestamp = getTime(),
            .thread_id = std.Thread.getCurrentId(),
            .source_file = if (file) |f| allocator.?.dupe(u8, f) catch null else null,
            .source_line = line,
            .category = if (category) |c| allocator.?.dupe(u8, c) catch "default" else "default",
        };

        if (memory_allocations.count() < MAX_MEMORY_ALLOCATIONS) {
            memory_allocations.put(ptr.?, alloc) catch {};
        }

        _ = trackCounter("Memory Used", @as(f64, @floatFromInt(total_allocated))) catch {};

        if (category) |cat| {
            const counter_name = std.fmt.allocPrint(allocator.?, "Memory: {s}", .{cat}) catch "Memory: unknown";
            defer if (std.mem.eql(u8, counter_name, "Memory: unknown")) {} else allocator.?.free(counter_name);

            _ = trackCounter(counter_name, @as(f64, @floatFromInt(size))) catch {};
        }
    }

    /// Remember memory deallocation for profiling.
    pub fn trackDeallocation(ptr: ?*anyopaque) void {
        if (!enabled or !is_initialized or ptr == null) return;

        if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) {
            tracy.FreeContext(ptr);
        }

        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        if (memory_allocations.getPtr(ptr.?)) |alloc| {
            total_allocated -= alloc.size;
            alloc.freed = true;
            alloc.free_timestamp = getTime();

            _ = trackCounter("Memory Used", @as(f64, @floatFromInt(total_allocated))) catch {};

            if (alloc.category.len > 0) {
                const counter_name = std.fmt.allocPrint(allocator.?, "Memory: {s}", .{alloc.category}) catch "Memory: unknown";
                defer if (std.mem.eql(u8, counter_name, "Memory: unknown")) {} else allocator.?.free(counter_name);

                _ = trackCounter(counter_name, -@as(f64, @floatFromInt(alloc.size))) catch {};
            }
        }
    }

    /// Get all current memory allocations.
    pub fn getMemoryAllocations() []MemoryAllocation {
        var result = std.array_list.Managed(MemoryAllocation).init(std.heap.page_allocator);
        defer result.deinit();

        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        var it = memory_allocations.valueIterator();
        while (it.next()) |alloc| {
            result.append(alloc.*) catch continue;
        }

        return result.toOwnedSlice() catch &[_]MemoryAllocation{};
    }

    /// Get memory statistics.
    pub fn getMemoryStats() struct {
        total_bytes: usize,
        allocation_count: usize,
        live_allocation_count: usize,
    } {
        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        var live_count: usize = 0;
        var it = memory_allocations.valueIterator();
        while (it.next()) |alloc| {
            if (!alloc.freed) live_count += 1;
        }

        return .{
            .total_bytes = total_allocated,
            .allocation_count = memory_allocations.count(),
            .live_allocation_count = live_count,
        };
    }

    /// Get all profile entries for analysis.
    pub fn getEntries() []const ProfileEntry {
        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        return entries.items;
    }

    /// Get all counter entries for analysis.
    pub fn getCounters() []const CounterEntry {
        mutexes.counters.lock();
        defer mutexes.counters.unlock();

        return counters.items;
    }

    /// Save profiling data to a file.
    pub fn saveToFile(path: []const u8) !void {
        if (!is_initialized) return error.ProfilerNotInitialized;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll("# MFS Profiler Data\n");
        try writer.print("# Frames: {d}\n", .{frame_count});
        try writer.writeAll("# Timestamp,Type,Name,Duration,ThreadId,ParentId,Color\n");
        try writer.writeAll("# Memory allocations have Type='alloc' or 'free'\n");

        mutexes.entries.lock();
        for (entries.items) |entry| {
            const duration = entry.duration();
            try writer.print("{d},zone,\"{s}\",{d},{d},{d},{x}\n", .{
                entry.start_time,
                entry.name,
                duration,
                entry.thread_id,
                entry.parent_id orelse 0,
                entry.color,
            });
        }
        mutexes.entries.unlock();

        mutexes.counters.lock();
        for (counters.items) |counter| {
            try writer.print("{d},counter,\"{s}\",{d},0,0,0\n", .{
                counter.timestamp,
                counter.name,
                @as(u64, @intFromFloat(counter.value * 1000)),
            });
        }
        mutexes.counters.unlock();

        mutexes.memory.lock();
        var it = memory_allocations.valueIterator();
        while (it.next()) |alloc| {
            try writer.print("{d},alloc,\"{s}\",{d},{d},0,{s}\n", .{
                alloc.timestamp,
                alloc.category,
                alloc.size,
                alloc.thread_id,
                if (alloc.source_file) |f| f else "unknown",
            });

            if (alloc.freed and alloc.free_timestamp != null) {
                try writer.print("{d},free,\"{s}\",{d},{d},0,{s}\n", .{
                    alloc.free_timestamp.?,
                    alloc.category,
                    alloc.size,
                    alloc.thread_id,
                    if (alloc.source_file) |f| f else "unknown",
                });
            }
        }
        mutexes.memory.unlock();
    }

    /// Get current time in nanoseconds.
    fn getTime() u64 {
        if (global_timer) |timer| {
            return timer.read();
        }
        return 0;
    }
};

/// Scope-based profiling zone.
pub const ScopedZone = struct {
    zone_id: ZoneId,

    pub fn init(name: []const u8) ScopedZone {
        return .{ .zone_id = Profiler.beginZone(name) };
    }

    pub fn initWithColor(name: []const u8, color: u32) ScopedZone {
        return .{ .zone_id = Profiler.beginZoneWithColor(name, color) };
    }

    pub fn deinit(self: *ScopedZone) void {
        Profiler.endZone(self.zone_id);
        self.zone_id = 0;
    }
};

/// TrackedAllocator wraps an allocator and reports allocations to the profiler.
pub const TrackedAllocator = struct {
    parent_allocator: std.mem.Allocator,
    category: ?[]const u8,

    pub fn init(parent_allocator: std.mem.Allocator, category: ?[]const u8) TrackedAllocator {
        return .{
            .parent_allocator = parent_allocator,
            .category = category,
        };
    }

    pub fn allocator(self: *TrackedAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(
        ctx: *anyopaque,
        len: usize,
        log2_ptr_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *TrackedAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent_allocator.vtable.alloc(self.parent_allocator.ptr, len, log2_ptr_align, ret_addr);

        if (result != null) {
            Profiler.trackAllocation(result, len, self.category, null, null);
        }

        return result;
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *TrackedAllocator = @ptrCast(@alignCast(ctx));

        if (new_len > buf.len) {
            Profiler.trackDeallocation(buf.ptr);
            const result = self.parent_allocator.vtable.resize(self.parent_allocator.ptr, buf, log2_buf_align, new_len, ret_addr);

            if (result) {
                Profiler.trackAllocation(buf.ptr, new_len, self.category, null, null);
            }

            return result;
        } else {
            return self.parent_allocator.vtable.resize(self.parent_allocator.ptr, buf, log2_buf_align, new_len, ret_addr);
        }
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        ret_addr: usize,
    ) void {
        const self: *TrackedAllocator = @ptrCast(@alignCast(ctx));
        Profiler.trackDeallocation(buf.ptr);
        self.parent_allocator.vtable.free(self.parent_allocator.ptr, buf, log2_buf_align, ret_addr);
    }
};

test "basic profiling" {
    try Profiler.init(std.testing.allocator);
    defer Profiler.deinit();

    const zone = Profiler.beginZone("Test Zone");
    std.time.sleep(1 * std.time.ns_per_ms);
    Profiler.endZone(zone);

    try Profiler.trackCounter("Test Counter", 42.0);

    Profiler.beginFrame();
    std.time.sleep(1 * std.time.ns_per_ms);
    try Profiler.endFrame();

    const entries = Profiler.getEntries();
    const counters = Profiler.getCounters();

    try std.testing.expect(entries.len >= 3);
    try std.testing.expect(counters.len >= 2);

    const zone_entry = entries[0];
    try std.testing.expectEqualStrings("Test Zone", zone_entry.name);
    try std.testing.expect(zone_entry.duration() >= 1 * std.time.ns_per_ms);

    const counter_entry = counters[0];
    try std.testing.expectEqualStrings("Test Counter", counter_entry.name);
    try std.testing.expectEqual(42.0, counter_entry.value);
}

/// Advanced Performance Profiler with bottleneck detection
/// Based on Intel's Unreal Engine optimization guidelines
/// Provides real-time performance analysis, bottleneck detection, and optimization recommendations
pub const AdvancedProfiler = struct {
    const FrameMetrics = struct {
        frame_number: u64,
        cpu_time_ms: f64,
        gpu_time_ms: f64,
        present_time_ms: f64,
        draw_calls: u32,
        triangles: u64,
        texture_switches: u32,
        shader_switches: u32,
        render_targets_switches: u32,
        memory_used_mb: f64,
        gpu_memory_used_mb: f64,
        timestamp: u64,

        // Performance ratios for bottleneck detection
        cpu_gpu_ratio: f64,
        fillrate_pressure: f64,
        vertex_pressure: f64,
        memory_bandwidth_usage: f64,
    };

    const PerformanceState = enum {
        optimal,
        cpu_bound,
        gpu_bound,
        memory_bound,
        fillrate_bound,
        vertex_bound,
        driver_overhead_bound,
    };

    const OptimizationSuggestion = struct {
        priority: enum { low, medium, high, critical },
        category: enum { rendering, memory, cpu, gpu, driver },
        message: []const u8,
        estimated_improvement_percent: f32,
    };

    allocator: std.mem.Allocator,
    frame_history: std.array_list.Managed(FrameMetrics),
    history_capacity: usize,
    current_frame: FrameMetrics,
    timer: std.time.Timer,
    frame_count: u64,

    // Performance thresholds
    target_fps: f64,
    target_frame_time_ms: f64,
    cpu_warning_threshold_ms: f64,
    gpu_warning_threshold_ms: f64,

    // Bottleneck detection
    current_state: PerformanceState,
    state_stability_frames: u32,
    optimization_suggestions: std.array_list.Managed(OptimizationSuggestion),

    // Frame pacing analysis
    frame_time_variance: f64,
    frame_drops: u32,
    micro_stutters: u32,

    // Hardware capabilities estimation
    estimated_gpu_compute_units: u32,
    estimated_memory_bandwidth_gb_s: f32,
    estimated_pixel_fillrate: u64,

    pub fn init(allocator: std.mem.Allocator, target_fps: f64) !AdvancedProfiler {
        const history_size = @as(usize, @intFromFloat(target_fps * 5.0)); // 5 seconds of history
        const ring_buffer = std.array_list.Managed(FrameMetrics).init(allocator);

        return AdvancedProfiler{
            .allocator = allocator,
            .frame_history = ring_buffer,
            .history_capacity = history_size,
            .current_frame = std.mem.zeroes(FrameMetrics),
            .timer = try std.time.Timer.start(),
            .frame_count = 0,
            .target_fps = target_fps,
            .target_frame_time_ms = 1000.0 / target_fps,
            .cpu_warning_threshold_ms = (1000.0 / target_fps) * 0.8,
            .gpu_warning_threshold_ms = (1000.0 / target_fps) * 0.9,
            .current_state = .optimal,
            .state_stability_frames = 0,
            .optimization_suggestions = std.array_list.Managed(OptimizationSuggestion).init(allocator),
            .frame_time_variance = 0.0,
            .frame_drops = 0,
            .micro_stutters = 0,
            .estimated_gpu_compute_units = 0,
            .estimated_memory_bandwidth_gb_s = 0.0,
            .estimated_pixel_fillrate = 0,
        };
    }

    pub fn deinit(self: *AdvancedProfiler) void {
        self.frame_history.deinit();
        self.optimization_suggestions.deinit();
    }

    pub fn beginFrame(self: *AdvancedProfiler) void {
        self.current_frame = std.mem.zeroes(FrameMetrics);
        self.current_frame.frame_number = self.frame_count;
        self.current_frame.timestamp = self.timer.read();
    }

    pub fn endFrame(self: *AdvancedProfiler) void {
        const frame_time_ns = self.timer.read() - self.current_frame.timestamp;
        self.current_frame.cpu_time_ms = @as(f64, @floatFromInt(frame_time_ns)) / 1_000_000.0;

        // Calculate performance ratios
        self.calculatePerformanceRatios();

        // Detect frame drops and micro-stutters
        self.analyzeFramePacing();

        // Store frame data (implement ring buffer behavior)
        self.frame_history.append(self.current_frame) catch {};
        // Remove oldest entries if we exceed capacity
        while (self.frame_history.items.len > self.history_capacity) {
            _ = self.frame_history.swapRemove(0);
        }
        self.frame_count += 1;

        // Analyze performance every 60 frames (1 second at 60fps)
        if (self.frame_count % 60 == 0) {
            self.analyzePerformanceState();
            self.generateOptimizationSuggestions();
        }
    }

    pub fn recordGPUTime(self: *AdvancedProfiler, gpu_time_ms: f64) void {
        self.current_frame.gpu_time_ms = gpu_time_ms;
    }

    pub fn recordDrawCall(self: *AdvancedProfiler, triangle_count: u64) void {
        self.current_frame.draw_calls += 1;
        self.current_frame.triangles += triangle_count;
    }

    pub fn recordTextureSwitch(self: *AdvancedProfiler) void {
        self.current_frame.texture_switches += 1;
    }

    pub fn recordShaderSwitch(self: *AdvancedProfiler) void {
        self.current_frame.shader_switches += 1;
    }

    pub fn recordRenderTargetSwitch(self: *AdvancedProfiler) void {
        self.current_frame.render_targets_switches += 1;
    }

    pub fn recordMemoryUsage(self: *AdvancedProfiler, cpu_mb: f64, gpu_mb: f64) void {
        self.current_frame.memory_used_mb = cpu_mb;
        self.current_frame.gpu_memory_used_mb = gpu_mb;
    }

    fn calculatePerformanceRatios(self: *AdvancedProfiler) void {
        const total_time = self.current_frame.cpu_time_ms + self.current_frame.gpu_time_ms;
        if (total_time > 0) {
            self.current_frame.cpu_gpu_ratio = self.current_frame.cpu_time_ms / self.current_frame.gpu_time_ms;
        }

        // Estimate fillrate pressure (triangles per millisecond)
        if (self.current_frame.gpu_time_ms > 0) {
            self.current_frame.fillrate_pressure = @as(f64, @floatFromInt(self.current_frame.triangles)) / self.current_frame.gpu_time_ms;
        }

        // Estimate vertex processing pressure (draw calls per millisecond)
        if (self.current_frame.gpu_time_ms > 0) {
            self.current_frame.vertex_pressure = @as(f64, @floatFromInt(self.current_frame.draw_calls)) / self.current_frame.gpu_time_ms;
        }

        // Estimate memory bandwidth usage
        const estimated_memory_transfers = @as(f64, @floatFromInt(self.current_frame.texture_switches + self.current_frame.render_targets_switches));
        if (self.current_frame.gpu_time_ms > 0 and estimated_memory_transfers > 0) {
            self.current_frame.memory_bandwidth_usage = estimated_memory_transfers / self.current_frame.gpu_time_ms;
        }
    }

    fn analyzeFramePacing(self: *AdvancedProfiler) void {
        if (self.frame_history.len() < 2) return;

        const current_frame_time = self.current_frame.cpu_time_ms;
        if (current_frame_time > self.target_frame_time_ms * 1.5) {
            self.frame_drops += 1;
        }

        // Detect micro-stutters (frame time variance)
        if (self.frame_history.len() >= 10) {
            var recent_times: [10]f64 = undefined;
            for (0..10) |i| {
                if (i < self.frame_history.items.len) {
                    const frame = self.frame_history.items[self.frame_history.items.len - 1 - i];
                    recent_times[i] = frame.cpu_time_ms;
                }
            }

            const variance = calculateVariance(recent_times[0..]);
            self.frame_time_variance = variance;

            if (variance > self.target_frame_time_ms * 0.1) {
                self.micro_stutters += 1;
            }
        }
    }

    fn analyzePerformanceState(self: *AdvancedProfiler) void {
        const new_state = self.detectBottleneck();

        if (new_state == self.current_state) {
            self.state_stability_frames += 1;
        } else {
            self.current_state = new_state;
            self.state_stability_frames = 0;
        }
    }

    fn detectBottleneck(self: *AdvancedProfiler) PerformanceState {
        if (self.frame_history.len() < 30) return .optimal;

        var avg_cpu_time: f64 = 0;
        var avg_gpu_time: f64 = 0;
        var avg_cpu_gpu_ratio: f64 = 0;
        var avg_draw_calls: f64 = 0;
        var count: u32 = 0;

        // Analyze last 30 frames
        for (0..@min(30, self.frame_history.len())) |i| {
            if (i < self.frame_history.items.len) {
                const frame = self.frame_history.items[self.frame_history.items.len - 1 - i];
                avg_cpu_time += frame.cpu_time_ms;
                avg_gpu_time += frame.gpu_time_ms;
                avg_cpu_gpu_ratio += frame.cpu_gpu_ratio;
                avg_draw_calls += @as(f64, @floatFromInt(frame.draw_calls));
                count += 1;
            }
        }

        if (count == 0) return .optimal;

        avg_cpu_time /= @as(f64, @floatFromInt(count));
        avg_gpu_time /= @as(f64, @floatFromInt(count));
        avg_cpu_gpu_ratio /= @as(f64, @floatFromInt(count));
        avg_draw_calls /= @as(f64, @floatFromInt(count));

        // Bottleneck detection logic based on Intel guidelines
        if (avg_cpu_time > self.cpu_warning_threshold_ms) {
            if (avg_draw_calls > 2000) {
                return .driver_overhead_bound;
            }
            return .cpu_bound;
        }

        if (avg_gpu_time > self.gpu_warning_threshold_ms) {
            if (avg_cpu_gpu_ratio < 0.5) { // GPU is much slower than CPU
                // Determine if it's fillrate or vertex bound
                const avg_fillrate_pressure = self.getAverageFillratePressure();
                const avg_vertex_pressure = self.getAverageVertexPressure();

                if (avg_fillrate_pressure > 1000000) { // High triangle throughput
                    return .fillrate_bound;
                } else if (avg_vertex_pressure > 100) { // High draw call frequency
                    return .vertex_bound;
                } else {
                    return .gpu_bound;
                }
            }
        }

        // Check memory bandwidth issues
        const avg_memory_usage = self.getAverageMemoryUsage();
        if (avg_memory_usage > 0.8) { // Using >80% of estimated memory bandwidth
            return .memory_bound;
        }

        return .optimal;
    }

    fn generateOptimizationSuggestions(self: *AdvancedProfiler) void {
        self.optimization_suggestions.clearRetainingCapacity();

        switch (self.current_state) {
            .cpu_bound => {
                self.addSuggestion(.high, .cpu, "Consider reducing CPU-intensive operations or using multithreading", 15.0);
                self.addSuggestion(.medium, .rendering, "Implement frustum culling to reduce objects processed per frame", 10.0);
            },
            .gpu_bound => {
                self.addSuggestion(.high, .gpu, "Reduce shader complexity or optimize GPU-intensive operations", 20.0);
                self.addSuggestion(.medium, .rendering, "Consider reducing texture resolution or using LOD systems", 12.0);
            },
            .fillrate_bound => {
                self.addSuggestion(.critical, .rendering, "Reduce overdraw by optimizing geometry or depth testing", 25.0);
                self.addSuggestion(.high, .rendering, "Implement occlusion culling to reduce hidden geometry", 18.0);
            },
            .vertex_bound => {
                self.addSuggestion(.high, .rendering, "Reduce polygon count with LOD systems", 15.0);
                self.addSuggestion(.medium, .rendering, "Optimize vertex shader complexity", 10.0);
            },
            .driver_overhead_bound => {
                self.addSuggestion(.critical, .driver, "Reduce draw calls through instancing or batching", 30.0);
                self.addSuggestion(.high, .rendering, "Combine small meshes into single draw calls", 20.0);
            },
            .memory_bound => {
                self.addSuggestion(.high, .memory, "Optimize texture streaming and compression", 15.0);
                self.addSuggestion(.medium, .memory, "Implement memory pooling for frequent allocations", 8.0);
            },
            .optimal => {
                // No suggestions needed
            },
        }

        // Frame pacing suggestions
        if (self.micro_stutters > 5) {
            self.addSuggestion(.medium, .cpu, "Frame pacing issues detected - consider frame rate limiting", 5.0);
        }
    }

    fn addSuggestion(self: *AdvancedProfiler, priority: OptimizationSuggestion.priority, category: OptimizationSuggestion.category, message: []const u8, improvement: f32) void {
        const suggestion = OptimizationSuggestion{
            .priority = priority,
            .category = category,
            .message = message,
            .estimated_improvement_percent = improvement,
        };
        self.optimization_suggestions.append(suggestion) catch {};
    }

    fn getAverageFillratePressure(self: *AdvancedProfiler) f64 {
        if (self.frame_history.len() == 0) return 0.0;

        var total: f64 = 0.0;
        var count: u32 = 0;

        for (0..@min(30, self.frame_history.len())) |i| {
            if (i < self.frame_history.items.len) {
                const frame = self.frame_history.items[self.frame_history.items.len - 1 - i];
                total += frame.fillrate_pressure;
                count += 1;
            }
        }

        return if (count > 0) total / @as(f64, @floatFromInt(count)) else 0.0;
    }

    fn getAverageVertexPressure(self: *AdvancedProfiler) f64 {
        if (self.frame_history.len() == 0) return 0.0;

        var total: f64 = 0.0;
        var count: u32 = 0;

        for (0..@min(30, self.frame_history.len())) |i| {
            if (i < self.frame_history.items.len) {
                const frame = self.frame_history.items[self.frame_history.items.len - 1 - i];
                total += frame.vertex_pressure;
                count += 1;
            }
        }

        return if (count > 0) total / @as(f64, @floatFromInt(count)) else 0.0;
    }

    fn getAverageMemoryUsage(self: *AdvancedProfiler) f64 {
        if (self.frame_history.len() == 0) return 0.0;

        var total: f64 = 0.0;
        var count: u32 = 0;

        for (0..@min(30, self.frame_history.len())) |i| {
            if (i < self.frame_history.items.len) {
                const frame = self.frame_history.items[self.frame_history.items.len - 1 - i];
                total += frame.memory_bandwidth_usage;
                count += 1;
            }
        }

        return if (count > 0) total / @as(f64, @floatFromInt(count)) else 0.0;
    }

    fn calculateVariance(values: []const f64) f64 {
        if (values.len < 2) return 0.0;

        var mean: f64 = 0.0;
        for (values) |value| {
            mean += value;
        }
        mean /= @as(f64, @floatFromInt(values.len));

        var variance: f64 = 0.0;
        for (values) |value| {
            const diff = value - mean;
            variance += diff * diff;
        }
        variance /= @as(f64, @floatFromInt(values.len - 1));

        return variance;
    }

    // Public API for retrieving performance data
    pub fn getCurrentFPS(self: *AdvancedProfiler) f64 {
        const avg_frame_time = self.getAverageFrameTime();
        return if (avg_frame_time > 0.0) 1000.0 / avg_frame_time else 0.0;
    }

    pub fn getAverageFrameTime(self: *AdvancedProfiler) f64 {
        if (self.frame_history.len() == 0) return 0.0;

        var total: f64 = 0.0;
        var count: u32 = 0;

        for (0..@min(60, self.frame_history.len())) |i| {
            if (i < self.frame_history.items.len) {
                const frame = self.frame_history.items[self.frame_history.items.len - 1 - i];
                total += frame.cpu_time_ms;
                count += 1;
            }
        }

        return if (count > 0) total / @as(f64, @floatFromInt(count)) else 0.0;
    }

    pub fn getPerformanceState(self: *AdvancedProfiler) PerformanceState {
        return self.current_state;
    }

    pub fn getOptimizationSuggestions(self: *AdvancedProfiler) []const OptimizationSuggestion {
        return self.optimization_suggestions.items;
    }

    pub fn getFrameDropCount(self: *AdvancedProfiler) u32 {
        return self.frame_drops;
    }

    pub fn getMicroStutterCount(self: *AdvancedProfiler) u32 {
        return self.micro_stutters;
    }

    pub fn getFrameTimeVariance(self: *AdvancedProfiler) f64 {
        return self.frame_time_variance;
    }

    /// Generate a comprehensive performance report
    pub fn generateReport(self: *AdvancedProfiler, writer: anytype) !void {
        try writer.writeAll("=== MFS Engine Performance Report ===\n");
        try writer.print("Frame Count: {}\n", .{self.frame_count});
        try writer.print("Current FPS: {d:.1}\n", .{self.getCurrentFPS()});
        try writer.print("Average Frame Time: {d:.2}ms\n", .{self.getAverageFrameTime()});
        try writer.print("Performance State: {s}\n", .{@tagName(self.current_state)});
        try writer.print("Frame Drops: {}\n", .{self.frame_drops});
        try writer.print("Micro Stutters: {}\n", .{self.micro_stutters});
        try writer.print("Frame Time Variance: {d:.3}\n", .{self.frame_time_variance});

        try writer.writeAll("\n=== Optimization Suggestions ===\n");
        for (self.optimization_suggestions.items) |suggestion| {
            try writer.print("[{s}] {s}: {s} (Est. {d:.1}% improvement)\n", .{
                @tagName(suggestion.priority),
                @tagName(suggestion.category),
                suggestion.message,
                suggestion.estimated_improvement_percent,
            });
        }
    }
};
