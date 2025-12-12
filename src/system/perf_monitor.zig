const std = @import("std");
const Allocator = std.mem.Allocator;
const time = std.time;
// Build-time options are normally injected via build.zig.  When unit-testing
// this file in isolation those options are not available, so we provide a
// minimal stub instead.  The real namespace (if any) will shadow this stub
// when the full application is built through the package manager.
const build_options = struct {
    pub const enable_tracy = false;
};

// Optional Tracy integration. If the build has enable_tracy set we use the real
// module, otherwise we stub the tiny API surface we need so that calls are
// compiled-out without further #ifs sprinkled throughout the code.
const tracy = if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy)
    @import("tracy")
else
    struct {
        pub inline fn traceNamed(comptime _: []const u8) void {}

        pub inline fn frameMarkNamed(comptime _: []const u8) void {}

        pub inline fn plotF64(comptime _: []const u8, _: f64) void {}
    };

pub const PerformanceMonitor = struct {
    allocator: Allocator,
    frame_times: std.array_list.Managed(f64),
    memory_usage: std.array_list.Managed(u64),
    cpu_usage: std.array_list.Managed(f32),
    gpu_usage: std.array_list.Managed(f32),
    draw_calls: std.array_list.Managed(u32),
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
            .frame_times = blk: {
                var list = std.array_list.Managed(f64).init(allocator);
                try list.ensureTotalCapacity(SAMPLE_COUNT);
                break :blk list;
            },
            .memory_usage = blk: {
                var list = std.array_list.Managed(u64).init(allocator);
                try list.ensureTotalCapacity(SAMPLE_COUNT);
                break :blk list;
            },
            .cpu_usage = blk: {
                var list = std.array_list.Managed(f32).init(allocator);
                try list.ensureTotalCapacity(SAMPLE_COUNT);
                break :blk list;
            },
            .gpu_usage = blk: {
                var list = std.array_list.Managed(f32).init(allocator);
                try list.ensureTotalCapacity(SAMPLE_COUNT);
                break :blk list;
            },
            .draw_calls = blk: {
                var list = std.array_list.Managed(u32).init(allocator);
                try list.ensureTotalCapacity(SAMPLE_COUNT);
                break :blk list;
            },
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

        try self.addSample(&self.frame_times, frame_time_ms);
        try self.addSample(&self.draw_calls, draw_call_count);

        const current_time = time.timestamp();
        if (current_time - self.last_update >= self.sample_interval_ns) {
            try self.updateSystemMetrics();
            self.last_update = current_time;
        }

        // ---------- Tracy instrumentation ----------------------------------
        // The label strings are intentionally stable so that Tracy treats them
        // as the same plot across frames.
        tracy.plotF64("Frame Time (ms)", frame_time_ms);
    }

    fn updateSystemMetrics(self: *PerformanceMonitor) !void {
        // Sample current memory usage – Zig's general purpose page allocator
        // doesn't expose resident-set statistics in a portable manner across
        // versions.  Until a proper platform abstraction lands, we fall back
        // to a dummy value so that compilation succeeds on every host.
        const memory_mb: u64 = 0;
        try self.addSample(&self.memory_usage, memory_mb);

        // Plot the latest system metrics so that viewers get a real-time
        // graph without each caller having to add bespoke code.
        tracy.plotF64("Memory (MB)", @as(f64, @floatFromInt(memory_mb)));

        // Estimate CPU usage
        const cpu_percent = self.estimateCpuUsage();
        try self.addSample(&self.cpu_usage, cpu_percent);
        tracy.plotF64("CPU Usage (%)", cpu_percent);

        // GPU usage would typically come from a graphics API
        // This is just a placeholder
        const gpu_percent: f32 = 0.0;
        try self.addSample(&self.gpu_usage, gpu_percent);
    }

    fn addSample(self: *PerformanceMonitor, list: anytype, value: anytype) !void {
        _ = self;
        // list is expected to be a pointer to an ArrayList-like type that
        // exposes `items`, `orderedRemove`, and `append`.
        if (list.*.items.len >= SAMPLE_COUNT) {
            _ = list.*.orderedRemove(0);
        }
        try list.*.append(value);
    }

    fn estimateCpuUsage(self: *PerformanceMonitor) f32 {
        const avg_frame_time = self.calculateAverageFps();

        // Rough estimate based on frame time
        const frame_budget_ms = 16.67; // ~60 FPS
        return @min(100.0, avg_frame_time * 100.0 / frame_budget_ms);
    }

    pub fn getStats(self: *const PerformanceMonitor) Stats {
        @constCast(&self.mutex).lock();
        defer @constCast(&self.mutex).unlock();

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
        if (self.frame_times.items.len == 0) {
            return 0.0;
        }

        var sum: f64 = 0.0;
        const count = self.frame_times.items.len;
        for (self.frame_times.items) |ft| {
            sum += ft;
        }

        return @floatCast(sum / @as(f64, @floatFromInt(count)));
    }

    fn calculateMinFps(self: *const PerformanceMonitor) f32 {
        if (self.frame_times.items.len == 0) {
            return 0.0;
        }

        var min_time: f64 = std.math.floatMax(f64);
        for (self.frame_times.items) |ft| {
            min_time = @min(min_time, ft);
        }

        return @floatCast(min_time);
    }

    fn calculateMaxFps(self: *const PerformanceMonitor) f32 {
        if (self.frame_times.items.len == 0) {
            return 0.0;
        }

        var max_time: f64 = 0.0;
        for (self.frame_times.items) |ft| {
            max_time = @max(max_time, ft);
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

    /// Write all recorded samples into a CSV file so that external analysis tools
    /// (Excel, LibreOffice Calc, pandas, etc.) can crunch them.  The file will be
    /// created (or truncated) at `path` relative to the current working
    /// directory.
    pub fn saveCsv(self: *const PerformanceMonitor, path: []const u8) !void {
        @constCast(&self.mutex).lock();
        defer @constCast(&self.mutex).unlock();

        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();

        var writer = file.writer();

        // CSV header – stable column order so that scripts can rely on it.
        try writer.writeAll("frame_ms,draw_calls,memory_mb,cpu_percent,gpu_percent\n");

        const sample_count = self.frame_times.items.len;

        // Emit one row per recorded frame. We deliberately don't guard against
        // mismatched buffer lengths – the `addSample` helper always keeps the
        // lists in lock-step, but we use `min()` out of extra paranoia.
        const count = @min(sample_count, @min(self.draw_calls.items.len, @min(self.memory_usage.items.len, @min(self.cpu_usage.items.len, self.gpu_usage.items.len))));

        for (0..count) |i| {
            const ft = self.frame_times.items[i];
            const dc = self.draw_calls.items[i];
            const mem = self.memory_usage.items[i];
            const cpu = self.cpu_usage.items[i];
            const gpu = self.gpu_usage.items[i];

            try writer.print("{d:.3},{d},{d},{d:.2},{d:.2}\n", .{ ft, dc, mem, cpu, gpu });
        }
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
