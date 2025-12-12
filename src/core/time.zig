//! Time Management System
//! High-precision timing and frame rate management

const std = @import("std");

/// High-precision time management
pub const Time = struct {
    start_time: i128,
    last_frame_time: i128,
    frame_count: u64 = 0,
    delta_accumulator: f64 = 0.0,
    fps_counter: FPSCounter,

    const Self = @This();

    pub fn init() Self {
        const now = std.time.Instant.now() catch std.time.Instant{ .timestamp = 0 };
        return Self{
            .start_time = now.timestamp,
            .last_frame_time = now.timestamp,
            .fps_counter = FPSCounter.init(),
        };
    }

    pub fn update(self: *Self) void {
        const now = (std.time.Instant.now() catch std.time.Instant{ .timestamp = 0 }).timestamp;
        const delta_ns = now - self.last_frame_time;
        self.last_frame_time = now;
        self.frame_count += 1;

        const delta_seconds = @as(f64, @floatFromInt(delta_ns)) / std.time.ns_per_s;
        self.delta_accumulator += delta_seconds;

        self.fps_counter.update(delta_seconds);
    }

    pub fn getDeltaTime(self: *const Self) f32 {
        const delta_ns = self.last_frame_time - self.start_time;
        return @as(f32, @floatCast(@as(f64, @floatFromInt(delta_ns)) / std.time.ns_per_s));
    }

    pub fn getElapsedTime(self: *const Self) f64 {
        const elapsed_ns = self.last_frame_time - self.start_time;
        return @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
    }

    pub fn getFPS(self: *const Self) f32 {
        return self.fps_counter.getFPS();
    }

    pub fn getFrameCount(self: *const Self) u64 {
        return self.frame_count;
    }

    pub fn getAverageFPS(self: *const Self) f32 {
        return self.fps_counter.getAverageFPS();
    }
};

/// Frame rate counter with smoothing
const FPSCounter = struct {
    frame_times: [60]f64 = [_]f64{0.0} ** 60,
    current_index: usize = 0,
    sample_count: usize = 0,
    total_time: f64 = 0.0,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn update(self: *Self, delta_time: f64) void {
        // Remove old sample if buffer is full
        if (self.sample_count == self.frame_times.len) {
            self.total_time -= self.frame_times[self.current_index];
        } else {
            self.sample_count += 1;
        }

        // Add new sample
        self.frame_times[self.current_index] = delta_time;
        self.total_time += delta_time;
        self.current_index = (self.current_index + 1) % self.frame_times.len;
    }

    pub fn getFPS(self: *const Self) f32 {
        if (self.sample_count == 0) return 0.0;
        const average_frame_time = self.total_time / @as(f64, @floatFromInt(self.sample_count));
        return if (average_frame_time > 0.0) @as(f32, @floatCast(1.0 / average_frame_time)) else 0.0;
    }

    pub fn getAverageFPS(self: *const Self) f32 {
        return self.getFPS(); // Same as getFPS since we already smooth over time
    }
};

/// High-precision timer for measuring intervals
pub const Timer = struct {
    start_time: i128,

    const Self = @This();

    pub fn start() Self {
        return Self{
            .start_time = std.time.nanoTimestamp(),
        };
    }

    pub fn restart(self: *Self) void {
        self.start_time = std.time.nanoTimestamp();
    }

    pub fn elapsedNanos(self: *const Self) i128 {
        return std.time.nanoTimestamp() - self.start_time;
    }

    pub fn elapsedMicros(self: *const Self) f64 {
        return @as(f64, @floatFromInt(self.elapsedNanos())) / std.time.ns_per_us;
    }

    pub fn elapsedMillis(self: *const Self) f64 {
        return @as(f64, @floatFromInt(self.elapsedNanos())) / std.time.ns_per_ms;
    }

    pub fn elapsedSeconds(self: *const Self) f64 {
        return @as(f64, @floatFromInt(self.elapsedNanos())) / std.time.ns_per_s;
    }
};

/// Frame rate limiter
pub const FrameLimiter = struct {
    target_frame_time_ns: i128,
    last_frame_time: i128,

    const Self = @This();

    pub fn init(target_fps: u32) Self {
        const target_frame_time_ns = if (target_fps > 0)
            std.time.ns_per_s / @as(i128, @intCast(target_fps))
        else
            0;

        return Self{
            .target_frame_time_ns = target_frame_time_ns,
            .last_frame_time = std.time.nanoTimestamp(),
        };
    }

    pub fn waitForNextFrame(self: *Self) void {
        if (self.target_frame_time_ns <= 0) return;

        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_frame_time;

        if (elapsed < self.target_frame_time_ns) {
            const sleep_time = self.target_frame_time_ns - elapsed;
            std.time.sleep(@intCast(sleep_time));
        }

        self.last_frame_time = std.time.nanoTimestamp();
    }

    pub fn setTargetFPS(self: *Self, fps: u32) void {
        self.target_frame_time_ns = if (fps > 0)
            std.time.ns_per_s / @as(i128, @intCast(fps))
        else
            0;
    }
};

/// Utility functions for time conversions
pub const utils = struct {
    pub fn secondsToNanos(seconds: f64) i128 {
        return @intFromFloat(seconds * std.time.ns_per_s);
    }

    pub fn millisToNanos(millis: f64) i128 {
        return @intFromFloat(millis * std.time.ns_per_ms);
    }

    pub fn nanosToSeconds(nanos: i128) f64 {
        return @as(f64, @floatFromInt(nanos)) / std.time.ns_per_s;
    }

    pub fn nanosToMillis(nanos: i128) f64 {
        return @as(f64, @floatFromInt(nanos)) / std.time.ns_per_ms;
    }
};

// Tests
test "time system" {
    var time_mgr = Time.init();

    std.time.sleep(std.time.ns_per_ms * 10); // Sleep 10ms
    time_mgr.update();

    const elapsed = time_mgr.getElapsedTime();
    try std.testing.expect(elapsed >= 0.01); // At least 10ms
    try std.testing.expect(time_mgr.getFrameCount() == 1);
}

test "timer" {
    var timer = Timer.start();

    std.time.sleep(std.time.ns_per_ms * 5); // Sleep 5ms

    const elapsed = timer.elapsedMillis();
    try std.testing.expect(elapsed >= 5.0);
}

test "fps counter" {
    var fps_counter = FPSCounter.init();

    // Simulate 60 FPS (16.67ms per frame)
    const frame_time = 1.0 / 60.0;
    for (0..60) |_| {
        fps_counter.update(frame_time);
    }

    const fps = fps_counter.getFPS();
    try std.testing.expect(fps >= 59.0 and fps <= 61.0); // Allow some tolerance
}

test "frame limiter" {
    var limiter = FrameLimiter.init(60); // 60 FPS

    const timer = Timer.start();
    limiter.waitForNextFrame();
    const elapsed = timer.elapsedMillis();

    // Should be close to 16.67ms (1000/60)
    try std.testing.expect(elapsed >= 15.0 and elapsed <= 20.0);
}
