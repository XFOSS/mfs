//! MFS Engine - Main Entry Point
//! Simple entry point that creates and runs the application

const std = @import("std");
const mfs = @import("mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Create application configuration using the new API
    var config = mfs.engine.createDefaultConfig();
    config.window_title = "MFS Engine Demo";
    config.window_width = 1280;
    config.window_height = 720;

    // Disable some subsystems for basic demo
    config.enable_physics = false;
    config.enable_audio = false;

    // Create and run application using the new API
    const app = mfs.initWithConfig(allocator, config) catch |err| {
        std.log.err("Failed to initialize MFS Engine: {}", .{err});
        return;
    };
    defer mfs.deinit(app);

    std.log.info("Starting {s}", .{mfs.getVersion()});
    std.log.info("Application initialized successfully", .{});

    // Run the main loop
    app.run() catch |err| {
        std.log.err("Application error: {}", .{err});
    };

    const stats = app.getStats();
    std.log.info("Application shutdown. Total frames: {}", .{stats.frame_count});
}
