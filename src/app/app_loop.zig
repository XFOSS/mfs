const std = @import("std");

/// Lightweight, reusable application loop with fixed or variable timesteps.
/// At this stage it is only a *scaffold* – the real engine still owns the
/// complex loop in `src/bin/main.zig`, but other tools/tests can import this
/// helper to avoid duplicating boiler-plate.
pub const AppLoop = struct {
    allocator: std.mem.Allocator,
    running: bool = true,

    pub fn init(allocator: std.mem.Allocator) AppLoop {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AppLoop) void {
        // Nothing to clean up yet – placeholder for future resources.
        _ = self;
    }

    /// Drive the loop until `stop()` is called. The caller provides an `update`
    /// callback that returns `!void`; if it errors we propagate upward.
    pub fn run(self: *AppLoop, update: fn (dt: f64) anyerror!void) !void {
        var last_ns: i128 = std.time.nanoTimestamp();
        while (self.running) {
            const now_ns = std.time.nanoTimestamp();
            const dt = @as(f64, @floatFromInt(now_ns - last_ns)) / std.time.ns_per_s;
            last_ns = now_ns;

            update(dt) catch |err| return err;

            // Simple frame pacing: ~60 FPS.
            std.time.sleep(std.time.ns_per_ms * 16);
        }
    }

    pub fn stop(self: *AppLoop) void {
        self.running = false;
    }
};
