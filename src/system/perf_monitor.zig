const std = @import("std");
const Allocator = std.mem.Allocator;
const time = std.time;

pub const PerformanceMonitor = struct {
    allocator: Allocator,
    frame_times: std.RingBuffer(f64),
    memory_usage: std.ArrayList(u64),
    cpu_usage: std.ArrayList(f32),
    gpu_usage: std.ArrayList(f32),
    draw_calls: std.ArrayList(u32),
    start_time: i64,
    last_update: i64,
    sample_interval_ns: i64,
    mutex: std.Thread.Mutex,

    pub const SAMPLE_COUNT: usize = 1000;

    pub fn init(allocator: Allocator) !*PerformanceMonitor {
        const monitor = try allocator.create(PerformanceMonitor);
        errdefer allocator.destroy(monitor);

        monitor.* = PerformanceMonitor{
            .allocator = allocator,
            .frame_times = try std.RingBuffer(f64).init(allocator, SAMPLE_COUNT),
            .memory_usage = try std.ArrayList(u64).initCapacity(allocator, SAMPLE_COUNT),
            .cpu_usage = try std.ArrayList(f32).initCapacity(allocator, SAMPLE_COUNT),
            .gpu_usage = try std.ArrayList(f32).initCapacity(allocator, SAMPLE_COUNT),
            .draw_calls = try std.ArrayList(u32).initCapacity(allocator, SAMPLE_COUNT),
            .start_time = time.timestamp(),
            .last_update = time.timestamp(),
            .sample_interval_ns = time.ns_per_s / 10, // Sample every 100ms by default
            .mutex = std.Thread.Mutex{},
        };

        // Initialize with starting values
        try monitor.memory_usage.append(0);
        try monitor.cpu_usage.append(0);
        try monitor.gpu_usage.append(0);
        try monitor.draw_calls.append(0);

        return monitor;
    }

    pub fn deinit(self: *PerformanceMonitor) void {
        self.frame_times.deinit();
        self.memory_usage.deinit();
        self.cpu_usage.deinit();
        self.gpu_usage.deinit();
        self.draw_calls.deinit();
        self.allocator.destroy(self);
    }

    pub fn recordFrame(self: *PerformanceMonitor, frame_time_ms: f64, draw_call_count: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.frame_times.write(frame_time_ms);
        try self.addSample(self.draw_calls, draw_call_count);

        const current_time = time.timestamp();
        if (current_time - self.last_update >= self.sample_interval_ns) {
            try self.updateSystemMetrics();
            self.last_update = current_time;
        }
    }

    fn updateSystemMetrics(self: *PerformanceMonitor) !void {
        // Sample current memory usage
        const memory_info = std.heap.page_allocator.getStats() catch |err| blk: {
            std.log.warn("Failed to get memory stats: {s}", .{@errorName(err)});
            break :blk .{ .total_bytes = 0, .resident_bytes = 0 };
        };

        const memory_mb = @as(u64, @intCast(memory_info.resident_bytes)) / (1024 * 1024);
        try self.addSample(self.memory_usage, memory_mb);

        // Estimate CPU usage
        const cpu_percent = self.estimateCpuUsage();
        try self.addSample(self.cpu_usage, cpu_percent);

        // GPU usage would typically come from a graphics API
        // This is just a placeholder
        const gpu_percent: f32 = 0.0;
        try self.addSample(self.gpu_usage, gpu_percent);
    }

    fn addSample(self: *PerformanceMonitor, list: anytype, value: @typeInfo(@TypeOf(list)).Pointer.child.Child) !void {
        if (list.items.len >= SAMPLE_COUNT) {
            _ = list.orderedRemove(0);
        }
        try list.append(value);
    }

    fn estimateCpuUsage(self: *PerformanceMonitor) f32 {
        const avg_frame_time = self.calculateAverageFps();
        _ = self;

        // Rough estimate based on frame time
        const frame_budget_ms = 16.67; // ~60 FPS
        return @min(100.0, avg_frame_time * 100.0 / frame_budget_ms);
    }

    pub fn getStats(self: *const PerformanceMonitor) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = time.timestamp();
        return Stats{
            .uptime_seconds = @as(f64, @floatFromInt(current_time - self.start_time)) / @as(f64, @floatFromInt(time.ns_per_s)),
            .average_fps = 1000.0 / self.calculateAverageFps(),
            .min_fps = 1000.0 / self.calculateMaxFps(), // Inverted because higher frame time = lower FPS
            .max_fps = 1000.0 / self.calculateMinFps(), // Inverted because lower frame time = higher FPS
            .memory_usage_mb = self.getLatestMemoryUsageMb(),
            .cpu_usage_percent = self.getLatestCpuUsage(),
            .gpu_usage_percent = self.getLatestGpuUsage(),
        };
    }

    pub const Stats = struct {
        uptime_seconds: f64,
        average_fps: f32,
        min_fps: f32,
        max_fps: f32,
        memory_usage_mb: u64,
        cpu_usage_percent: f32,
        gpu_usage_percent: f32,
    };

    fn calculateAverageFps(self: *const PerformanceMonitor) f32 {
        if (self.frame_times.isEmpty()) {
            return 0.0;
        }

        var sum: f64 = 0.0;
        var count: usize = 0;

        var iter = self.frame_times.constIterator();
        while (iter.next()) |frame_time| {
            sum += frame_time.*;
            count += 1;
        }

        return @floatCast(sum / @as(f64, @floatFromInt(count)));
    }

    fn calculateMinFps(self: *const PerformanceMonitor) f32 {
        if (self.frame_times.isEmpty()) {
            return 0.0;
        }

        var min_time: f64 = std.math.floatMax(f64);

        var iter = self.frame_times.constIterator();
        while (iter.next()) |frame_time| {
            min_time = @min(min_time, frame_time.*);
        }

        return @floatCast(min_time);
    }

    fn calculateMaxFps(self: *const PerformanceMonitor) f32 {
        if (self.frame_times.isEmpty()) {
            return 0.0;
        }

        var max_time: f64 = 0.0;

        var iter = self.frame_times.constIterator();
        while (iter.next()) |frame_time| {
            max_time = @max(max_time, frame_time.*);
        }

        return @floatCast(max_time);
    }

    fn getLatestMemoryUsageMb(self: *const PerformanceMonitor) u64 {
        return if (self.memory_usage.items.len > 0)
            self.memory_usage.items[self.memory_usage.items.len - 1]
        else
            0;
    }

    fn getLatestCpuUsage(self: *const PerformanceMonitor) f32 {
        return if (self.cpu_usage.items.len > 0)
            self.cpu_usage.items[self.cpu_usage.items.len - 1]
        else
            0.0;
    }

    fn getLatestGpuUsage(self: *const PerformanceMonitor) f32 {
        return if (self.gpu_usage.items.len > 0)
            self.gpu_usage.items[self.gpu_usage.items.len - 1]
        else
            0.0;
    }
};

// Performance reporting functions
pub fn reportPerformanceStats(monitor: *PerformanceMonitor) void {
    if (monitor == null) return;

    const stats = monitor.getStats();
    std.log.info("=== Performance Report ===", .{});
    std.log.info("Uptime: {d:.2} seconds", .{stats.uptime_seconds});
    std.log.info("FPS: {d:.1} (min: {d:.1}, max: {d:.1})", .{ stats.average_fps, stats.min_fps, stats.max_fps });
    std.log.info("Memory: {d} MB", .{stats.memory_usage_mb});
    std.log.info("CPU Usage: {d:.1}%", .{stats.cpu_usage_percent});
    std.log.info("GPU Usage: {d:.1}%", .{stats.gpu_usage_percent});
    std.log.info("========================", .{});
}

test "performance monitor" {
    const allocator = std.testing.allocator;

    var monitor = try PerformanceMonitor.init(allocator);
    defer monitor.deinit();

    // Record some sample frames
    for (0..100) |i| {
        const frame_time = 16.7 + @as(f64, @floatFromInt(i % 10));
        try monitor.recordFrame(frame_time, 1000);
    }

    const stats = monitor.getStats();
    try std.testing.expect(stats.average_fps > 0.0);
    try std.testing.expect(stats.memory_usage_mb >= 0);
}
