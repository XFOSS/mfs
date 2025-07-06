//! Minimal game/application main loop stub.
//! This file is intentionally stand-alone so you can build it directly with
//! `zig run src/main_loop.zig` while the rest of the engine grows around it.
//!
//! The loop does three things:
//!   1. Creates a window via the platform-level wrapper.
//!   2. Pumps window events once per frame.
//!   3. Ticks a monotonically increasing frame counter until the user closes
//!      the window (or we hit an optional frame limit in tests).
//!
//! All heavy-weight systems (graphics, audio, etc.) will plug in later.  For
//! now this demonstrates a clean separation between platform, window, and the
//! update-step driving logic.

const std = @import("std");
const platform_window = @import("platform/window.zig");

/// Configuration for the demo loop.
pub const Config = struct {
    window: platform_window.Config = .{},
    /// Optional maximum frame count (useful in automated tests). 0 = unlimited.
    max_frames: u64 = 0,
};

/// Very small utility struct that owns the window system and frame counter.
pub const MainLoop = struct {
    allocator: std.mem.Allocator,
    window_system: *platform_window.WindowSystem,
    frame_count: u64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, cfg: Config) !Self {
        var ws = try platform_window.init(allocator, cfg.window);
        return Self{
            .allocator = allocator,
            .window_system = ws,
        };
    }

    pub fn deinit(self: *Self) void {
        platform_window.deinit(self.window_system);
        self.allocator.destroy(self.window_system);
    }

    /// Runs until the user closes the window or `cfg.max_frames` has been hit.
    pub fn run(self: *Self, cfg: Config) !void {
        const target_dt = 1.0 / 60.0; // 60 FPS cap for now.

        while (true) : (self.frame_count += 1) {
            // Pump OS/window events.
            try self.window_system.update();

            if (self.window_system.shouldQuit()) break;
            if (cfg.max_frames != 0 and self.frame_count >= cfg.max_frames) break;

            // TODO: update / render subsystems once they exist.

            // Very naive frame-limiting so our loop doesn't busy-spin.
            std.time.sleep(@as(u64, @intFromFloat(target_dt * std.time.ns_per_s)));
        }
    }
};

// -----------------------------------------------------------------------------
// Entry-point for `zig run src/main_loop.zig` convenience.
// -----------------------------------------------------------------------------

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var loop = try MainLoop.init(gpa.allocator(), Config{});
    defer loop.deinit();

    try loop.run(Config{});
}

test "main loop runs a few frames then exits" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var loop = try MainLoop.init(gpa.allocator(), Config{ .max_frames = 3 });
    defer loop.deinit();

    try loop.run(Config{ .max_frames = 3 });
}