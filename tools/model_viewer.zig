//! Model Viewer Tool
//! Interactive 3D model viewer and inspector

const std = @import("std");
const mfs = @import("mfs");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.info("Usage: model-viewer <model_file>", .{});
        std.log.info("Interactive 3D model viewer and inspector", .{});
        return;
    }

    const model_file = args[1];

    // Create application configuration
    var config = mfs.engine.Config.default();
    config.window_title = "Model Viewer - MFS Engine";
    config.window_width = 1280;
    config.window_height = 720;
    config.enable_physics = false;
    config.enable_audio = false;

    try config.validate();

    // Create and run application
    const app = mfs.init(allocator, config) catch |err| {
        std.log.err("Failed to initialize MFS Engine: {}", .{err});
        return;
    };
    defer app.deinit();

    std.log.info("Loading model: {s}", .{model_file});

    // TODO: Implement model viewer
    // - Load 3D model from file
    // - Interactive camera controls (orbit, pan, zoom)
    // - Model statistics display
    // - Material and texture inspection
    // - Wireframe and normal visualization
    // - Animation playback controls
    // - Export functionality

    // Run the main loop
    app.run() catch |err| {
        std.log.err("Application error: {}", .{err});
    };

    std.log.info("Model viewer finished", .{});
}
