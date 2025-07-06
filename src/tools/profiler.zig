//! Performance profiler for MFS Engine
//! Provides timing and performance measurement capabilities

const std = @import("std");

pub const ProfilerError = error{
    InvalidTimerName,
    TimerNotStarted,
    TimerAlreadyStarted,
};

pub const Timer = struct {
    name: []const u8,
    start_time: i64,
    total_time: i64,
    call_count: u64,
    running: bool,

    pub fn init(name: []const u8) Timer {
        return Timer{
            .name = name,
            .start_time = 0,
            .total_time = 0,
            .call_count = 0,
            .running = false,
        };
    }

    pub fn start(self: *Timer) ProfilerError!void {
        if (self.running) return ProfilerError.TimerAlreadyStarted;
        self.start_time = std.time.nanoTimestamp();
        self.running = true;
    }

    pub fn stop(self: *Timer) ProfilerError!void {
        if (!self.running) return ProfilerError.TimerNotStarted;
        const end_time = std.time.nanoTimestamp();
        self.total_time += end_time - self.start_time;
        self.call_count += 1;
        self.running = false;
    }

    pub fn getAverageTime(self: *const Timer) f64 {
        if (self.call_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_time)) / @as(f64, @floatFromInt(self.call_count));
    }

    pub fn getTotalTime(self: *const Timer) i64 {
        return self.total_time;
    }

    pub fn getCallCount(self: *const Timer) u64 {
        return self.call_count;
    }

    pub fn reset(self: *Timer) void {
        self.total_time = 0;
        self.call_count = 0;
        self.running = false;
    }
};

pub const Profiler = struct {
    timers: std.HashMap([]const u8, Timer, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Profiler {
        return Profiler{
            .timers = std.HashMap([]const u8, Timer, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Profiler) void {
        self.timers.deinit();
    }

    pub fn createTimer(self: *Profiler, name: []const u8) !void {
        const timer = Timer.init(name);
        try self.timers.put(name, timer);
    }

    pub fn startTimer(self: *Profiler, name: []const u8) ProfilerError!void {
        if (self.timers.getPtr(name)) |timer| {
            try timer.start();
        } else {
            return ProfilerError.InvalidTimerName;
        }
    }

    pub fn stopTimer(self: *Profiler, name: []const u8) ProfilerError!void {
        if (self.timers.getPtr(name)) |timer| {
            try timer.stop();
        } else {
            return ProfilerError.InvalidTimerName;
        }
    }

    pub fn getTimer(self: *Profiler, name: []const u8) ?*Timer {
        return self.timers.getPtr(name);
    }

    pub fn printReport(self: *Profiler) void {
        std.log.info("=== Performance Report ===", .{});

        var iterator = self.timers.iterator();
        while (iterator.next()) |entry| {
            const timer = entry.value_ptr;
            const avg_time_ms = timer.getAverageTime() / 1_000_000.0;
            const total_time_ms = @as(f64, @floatFromInt(timer.getTotalTime())) / 1_000_000.0;

            std.log.info("{s}:", .{timer.name});
            std.log.info("  Calls: {}", .{timer.getCallCount()});
            std.log.info("  Total: {d:.2}ms", .{total_time_ms});
            std.log.info("  Average: {d:.2}ms", .{avg_time_ms});
            std.log.info("", .{});
        }
    }

    pub fn resetAll(self: *Profiler) void {
        var iterator = self.timers.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.reset();
        }
    }
};
