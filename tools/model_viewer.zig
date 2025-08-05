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

    // Load 3D model from file
    const model_data = try std.fs.cwd().readFileAlloc(allocator, model_file, 1024 * 1024);
    defer allocator.free(model_data);

    std.log.info("Model loaded: {} bytes", .{model_data.len});

    // Parse model format based on file extension
    const file_ext = std.fs.path.extension(model_file);
    if (std.mem.eql(u8, file_ext, ".obj")) {
        std.log.info("Loading OBJ model...", .{});
        // TODO: Implement OBJ parser
    } else if (std.mem.eql(u8, file_ext, ".fbx")) {
        std.log.info("Loading FBX model...", .{});
        // TODO: Implement FBX parser
    } else if (std.mem.eql(u8, file_ext, ".gltf")) {
        std.log.info("Loading glTF model...", .{});
        // TODO: Implement glTF parser
    } else {
        std.log.err("Unsupported model format: {s}", .{file_ext});
        return;
    }

    // Model statistics
    std.log.info("Model statistics:", .{});
    std.log.info("  Vertices: {}", .{0}); // TODO: Count actual vertices
    std.log.info("  Triangles: {}", .{0}); // TODO: Count actual triangles
    std.log.info("  Materials: {}", .{0}); // TODO: Count materials
    std.log.info("  Textures: {}", .{0}); // TODO: Count textures

    // Set up camera controls
    std.log.info("Camera controls:", .{});
    std.log.info("  Mouse: Orbit camera", .{});
    std.log.info("  Scroll: Zoom in/out", .{});
    std.log.info("  Shift+Mouse: Pan camera", .{});
    std.log.info("  R: Reset camera", .{});
    std.log.info("  W: Toggle wireframe", .{});
    std.log.info("  N: Toggle normals", .{});
    std.log.info("  M: Toggle materials", .{});

    // Run the main loop
    app.run() catch |err| {
        std.log.err("Application error: {}", .{err});
    };

    std.log.info("Model viewer finished", .{});
}
