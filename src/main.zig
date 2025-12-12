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

    // Enable all core systems for full integration demo
    config.enable_physics = true;
    config.enable_audio = true;
    // Input is automatically enabled when window is enabled

    // Enable AI system for full integration demo
    config.enable_ai = true;
    config.ai_update_rate = 60.0;

    // Networking is optional - disabled by default
    // Uncomment to enable networking:
    // config.enable_networking = true;
    // config.network_mode = .client;

    // Create and run application using the new API
    const app = mfs.initWithConfig(allocator, config) catch |err| {
        std.log.err("Failed to initialize MFS Engine: {}", .{err});
        return;
    };
    defer mfs.deinit(app);

    std.log.info("Starting {s}", .{mfs.getVersion()});
    std.log.info("Application initialized successfully", .{});
    
    // Log system status
    std.log.info("=== MFS Engine Systems Status ===", .{});
    std.log.info("Graphics: {}", .{if (app.graphics_system != null) "Enabled" else "Disabled"});
    std.log.info("Physics: {}", .{if (app.physics_system != null) "Enabled" else "Disabled"});
    std.log.info("Audio: {}", .{if (app.audio_system != null) "Enabled" else "Disabled"});
    std.log.info("Input: {}", .{if (app.input_system != null) "Enabled" else "Disabled"});
    std.log.info("Scene: {}", .{if (app.scene_system != null) "Enabled" else "Disabled"});
    std.log.info("AI: {}", .{if (app.ai_system != null) "Enabled" else "Disabled"});
    std.log.info("Networking: {}", .{if (app.network_manager != null) "Enabled" else "Disabled"});

    // Status logging variables
    var last_status_log: i64 = 0;
    const status_interval: i64 = 5_000_000_000; // 5 seconds in nanoseconds

    // Run the main loop with status updates
    while (app.is_running) {
        try app.update();
        try app.render();

        // Log status periodically
        const current_time = std.time.nanoTimestamp();
        if (current_time - last_status_log > status_interval) {
            const stats = app.getStats();
            std.log.info("=== System Status ===", .{});
            std.log.info("FPS: {d:.1}", .{stats.fps});
            std.log.info("Frame: {}", .{stats.frame_count});
            std.log.info("Elapsed: {d:.2}s", .{stats.elapsed_time});
            
            if (app.physics_system) |_| {
                std.log.info("Physics Objects: {}", .{stats.physics_objects});
            }
            if (app.audio_system) |_| {
                std.log.info("Audio Sources: {}", .{stats.audio_sources});
            }
            if (app.ai_system) |_| {
                std.log.info("AI Entities: {}", .{stats.ai_entities});
            }
            if (app.network_manager) |_| {
                std.log.info("Network Connections: {}", .{stats.network_connections});
            }
            
            last_status_log = current_time;
        }

        // Handle input for demo controls
        if (app.input_system) |in_sys| {
            if (in_sys.isKeyJustPressed(.escape)) {
                std.log.info("Escape pressed - shutting down", .{});
                app.quit();
            }
        }
    }

    const stats = app.getStats();
    std.log.info("Application shutdown. Total frames: {}", .{stats.frame_count});
    std.log.info("Average FPS: {d:.1}", .{stats.fps});
}
