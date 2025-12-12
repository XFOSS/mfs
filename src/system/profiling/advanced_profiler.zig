//! Advanced Profiler for MFS Engine
//! Provides detailed performance profiling with hierarchical timing, memory tracking, and statistical analysis

const std = @import("std");
const builtin = @import("builtin");

/// Advanced profiler with hierarchical timing and statistical analysis
pub const AdvancedProfiler = struct {
    allocator: std.mem.Allocator,
    enabled: bool = true,

    // Profiling data
    samples: std.array_list.Managed(ProfileSample),
    current_frame: u64 = 0,

    // Statistics
    frame_times: std.array_list.Managed(f64),
    memory_usage: std.array_list.Managed(u64),

    // Configuration
    max_samples: u32 = 10000,
    max_frame_history: u32 = 1000,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .samples = std.array_list.Managed(ProfileSample).init(allocator),
            .frame_times = std.array_list.Managed(f64).init(allocator),
            .memory_usage = std.array_list.Managed(u64).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.samples.deinit();
        self.frame_times.deinit();
        self.memory_usage.deinit();
    }

    /// Begin profiling a section
    pub fn beginSection(self: *Self, name: []const u8) !ProfileHandle {
        if (!self.enabled) return ProfileHandle{ .id = 0, .valid = false };

        const sample = ProfileSample{
            .name = name,
            .start_time = std.time.nanoTimestamp(),
            .frame = self.current_frame,
            .thread_id = std.Thread.getCurrentId(),
        };

        try self.samples.append(sample);
        const handle = ProfileHandle{
            .id = @intCast(self.samples.items.len - 1),
            .valid = true,
        };

        return handle;
    }

    /// End profiling a section
    pub fn endSection(self: *Self, handle: ProfileHandle) void {
        if (!handle.valid or !self.enabled) return;

        if (handle.id < self.samples.items.len) {
            self.samples.items[handle.id].end_time = std.time.nanoTimestamp();
        }
    }

    /// Mark the end of a frame
    pub fn endFrame(self: *Self) !void {
        if (!self.enabled) return;

        self.current_frame += 1;

        // Calculate frame time
        if (self.samples.items.len > 0) {
            const frame_start = self.getFrameStartTime();
            const frame_end = std.time.nanoTimestamp();
            const frame_time = @as(f64, @floatFromInt(frame_end - frame_start)) / std.time.ns_per_s;

            try self.frame_times.append(frame_time);

            // Limit frame history
            if (self.frame_times.items.len > self.max_frame_history) {
                _ = self.frame_times.orderedRemove(0);
            }
        }

        // Clean up old samples
        if (self.samples.items.len > self.max_samples) {
            const to_remove = self.samples.items.len - self.max_samples;
            for (0..to_remove) |i| {
                _ = self.samples.orderedRemove(i);
            }
        }
    }

    /// Get profiling statistics
    pub fn getStats(self: *const Self) ProfileStats {
        var stats = ProfileStats{};

        if (self.frame_times.items.len == 0) return stats;

        // Calculate frame time statistics
        var total: f64 = 0;
        var min_time: f64 = self.frame_times.items[0];
        var max_time: f64 = self.frame_times.items[0];

        for (self.frame_times.items) |time| {
            total += time;
            min_time = @min(min_time, time);
            max_time = @max(max_time, time);
        }

        stats.avg_frame_time = total / @as(f64, @floatFromInt(self.frame_times.items.len));
        stats.min_frame_time = min_time;
        stats.max_frame_time = max_time;
        stats.fps = if (stats.avg_frame_time > 0) 1.0 / stats.avg_frame_time else 0;
        stats.total_samples = @intCast(self.samples.items.len);

        return stats;
    }

    /// Generate a profiling report
    pub fn generateReport(self: *const Self, writer: anytype) !void {
        const stats = self.getStats();

        try writer.print("=== Advanced Profiler Report ===\n");
        try writer.print("Frame: {}\n", .{self.current_frame});
        try writer.print("Average Frame Time: {d:.3}ms ({d:.1} FPS)\n", .{ stats.avg_frame_time * 1000, stats.fps });
        try writer.print("Min Frame Time: {d:.3}ms\n", .{stats.min_frame_time * 1000});
        try writer.print("Max Frame Time: {d:.3}ms\n", .{stats.max_frame_time * 1000});
        try writer.print("Total Samples: {}\n", .{stats.total_samples});
        try writer.print("\n");

        // Show recent samples for current frame
        try writer.print("Recent Samples:\n");
        var count: u32 = 0;
        for (self.samples.items) |sample| {
            if (sample.frame == self.current_frame and sample.end_time > 0) {
                const duration = @as(f64, @floatFromInt(sample.end_time - sample.start_time)) / 1_000_000; // Convert to milliseconds
                try writer.print("  {s}: {d:.3}ms\n", .{ sample.name, duration });
                count += 1;
                if (count >= 20) break; // Limit output
            }
        }
    }

    fn getFrameStartTime(self: *const Self) i128 {
        for (self.samples.items) |sample| {
            if (sample.frame == self.current_frame) {
                return sample.start_time;
            }
        }
        return std.time.nanoTimestamp();
    }
};

/// Handle for profiling sections
pub const ProfileHandle = struct {
    id: u32,
    valid: bool,
};

/// Individual profiling sample
pub const ProfileSample = struct {
    name: []const u8,
    start_time: i128,
    end_time: i128 = 0,
    frame: u64,
    thread_id: u32,
};

/// Profiling statistics
pub const ProfileStats = struct {
    avg_frame_time: f64 = 0,
    min_frame_time: f64 = 0,
    max_frame_time: f64 = 0,
    fps: f64 = 0,
    total_samples: u32 = 0,
};

/// Convenient macro-like function for profiling a block
pub fn profileBlock(profiler: *AdvancedProfiler, name: []const u8, comptime func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
    const handle = try profiler.beginSection(name);
    defer profiler.endSection(handle);

    return @call(.auto, func, args);
}

/// Global profiler instance (optional)
var global_profiler: ?AdvancedProfiler = null;

/// Initialize global profiler
pub fn initGlobal(allocator: std.mem.Allocator) !void {
    global_profiler = try AdvancedProfiler.init(allocator);
}

/// Deinitialize global profiler
pub fn deinitGlobal() void {
    if (global_profiler) |*profiler| {
        profiler.deinit();
        global_profiler = null;
    }
}

/// Get global profiler instance
pub fn getGlobal() ?*AdvancedProfiler {
    if (global_profiler) |*profiler| {
        return profiler;
    }
    return null;
}
