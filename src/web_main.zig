const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const engine = @import("engine/engine.zig");
const graphics = @import("graphics/backend_manager.zig");
const platform = @import("platform.zig");

// Web-specific allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Global engine instance
var engine_instance: ?*engine.Engine = null;
var initialized = false;

// Exported functions for JavaScript interface
export fn web_init(canvas_width: u32, canvas_height: u32) c_int {
    web_initialize(canvas_width, canvas_height) catch |err| {
        std.log.err("Failed to initialize web engine: {}", .{err});
        return -1;
    };
    return 0;
}

export fn web_update(delta_time: f32) void {
    if (engine_instance) |engine_inst| {
        engine_inst.update(delta_time) catch |err| {
            std.log.err("Engine update failed: {}", .{err});
        };
    }
}

export fn web_render() void {
    if (engine_instance) |engine_inst| {
        engine_inst.render() catch |err| {
            std.log.err("Engine render failed: {}", .{err});
        };
    }
}

export fn web_resize(new_width: u32, new_height: u32) void {
    if (engine_instance) |engine_inst| {
        engine_inst.resize(new_width, new_height) catch |err| {
            std.log.err("Engine resize failed: {}", .{err});
        };
    }
}

export fn web_cleanup() void {
    web_deinitialize();
}

export fn web_handle_input(input_type: u32, key_code: u32, mouse_x: f32, mouse_y: f32) void {
    if (engine_instance) |engine_inst| {
        const input_event = switch (input_type) {
            0 => engine.InputEvent{ .key_down = @intCast(key_code) },
            1 => engine.InputEvent{ .key_up = @intCast(key_code) },
            2 => engine.InputEvent{ .mouse_move = .{ .x = mouse_x, .y = mouse_y } },
            3 => engine.InputEvent{ .mouse_down = @intCast(key_code) },
            4 => engine.InputEvent{ .mouse_up = @intCast(key_code) },
            else => return,
        };

        engine_inst.handleInput(input_event) catch |err| {
            std.log.err("Input handling failed: {}", .{err});
        };
    }
}

fn web_initialize(canvas_width: u32, canvas_height: u32) !void {
    if (initialized) return;

    std.log.info("Initializing MFS Engine for Web (WASM)", .{});
    std.log.info("Canvas size: {}x{}", .{ canvas_width, canvas_height });

    // Initialize graphics backend manager with WebGPU preference
    const backend_manager = try graphics.BackendManager.init(allocator, .{
        .preferred_backend = .webgpu,
        .auto_fallback = true,
        .debug_mode = build_options.build_mode == .Debug,
        .validate_backends = true,
        .enable_backend_switching = false, // Disable for web for stability
    });

    // Create engine instance
    const engine_config = engine.EngineConfig{
        .window_width = canvas_width,
        .window_height = canvas_height,
        .window_title = "MFS Engine Web",
        .target_fps = 60,
        .vsync = true,
        .multisampling = .x4,
        .graphics_backend = .webgpu,
        .audio_backend = .webaudio,
        .enable_profiling = false,
        .enable_validation = build_options.build_mode == .Debug,
    };

    engine_instance = try engine.Engine.init(allocator, engine_config, backend_manager);

    // Load initial scene or demo
    try loadWebDemo();

    initialized = true;
    std.log.info("MFS Engine for Web initialized successfully", .{});
}

fn web_deinitialize() void {
    if (!initialized) return;

    std.log.info("Shutting down MFS Engine for Web", .{});

    if (engine_instance) |engine_inst| {
        engine_inst.deinit();
        engine_instance = null;
    }

    initialized = false;
    _ = gpa.deinit();
}

fn loadWebDemo() !void {
    if (engine_instance == null) return;

    // Load a simple demo scene optimized for web
    const demo_scene = try createWebOptimizedScene();
    try engine_instance.?.loadScene(demo_scene);
}

fn createWebOptimizedScene() !*engine.Scene {
    // Create a lightweight scene suitable for web deployment
    const scene = try allocator.create(engine.Scene);
    scene.* = try engine.Scene.init(allocator, "Web Demo Scene");

    // Add a simple spinning cube with optimized shaders
    const cube_entity = try scene.createEntity("SpinningCube");

    // Transform component
    const transform = engine.Transform{
        .position = .{ .x = 0, .y = 0, .z = -5 },
        .rotation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
    try cube_entity.addComponent(engine.TransformComponent{ .transform = transform });

    // Mesh component with optimized cube geometry
    const cube_mesh = try createOptimizedCubeMesh();
    try cube_entity.addComponent(engine.MeshComponent{ .mesh = cube_mesh });

    // Material component with web-optimized shader
    const cube_material = try createWebOptimizedMaterial();
    try cube_entity.addComponent(engine.MaterialComponent{ .material = cube_material });

    // Rotation behavior component
    try cube_entity.addComponent(engine.RotationComponent{
        .axis = .{ .x = 0.5, .y = 1.0, .z = 0.3 },
        .speed = 45.0, // degrees per second
    });

    // Add basic lighting
    const light_entity = try scene.createEntity("DirectionalLight");
    const light_transform = engine.Transform{
        .position = .{ .x = 2, .y = 4, .z = 2 },
        .rotation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
    try light_entity.addComponent(engine.TransformComponent{ .transform = light_transform });
    try light_entity.addComponent(engine.DirectionalLightComponent{
        .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        .intensity = 1.0,
        .direction = .{ .x = -0.5, .y = -0.7, .z = -0.5 },
    });

    return scene;
}

fn createOptimizedCubeMesh() !*engine.Mesh {
    // Simple cube vertices optimized for web
    const vertices = [_]engine.Vertex{
        // Front face
        .{ .position = .{ .x = -1, .y = -1, .z = 1 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 1, .y = -1, .z = 1 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 1, .y = 1, .z = 1 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = -1, .y = 1, .z = 1 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 1 } },

        // Back face
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = -1, .y = 1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = 1, .y = 1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x = 1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 0, .y = 0 } },

        // Top face
        .{ .position = .{ .x = -1, .y = 1, .z = -1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x = -1, .y = 1, .z = 1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 1, .y = 1, .z = 1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 1, .y = 1, .z = -1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 1 } },

        // Bottom face
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .uv = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = 1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x = 1, .y = -1, .z = 1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = -1, .y = -1, .z = 1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },

        // Right face
        .{ .position = .{ .x = 1, .y = -1, .z = -1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 1, .y = 1, .z = -1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .uv = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = 1, .y = 1, .z = 1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x = 1, .y = -1, .z = 1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },

        // Left face
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = -1, .y = -1, .z = 1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = -1, .y = 1, .z = 1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .uv = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = -1, .y = 1, .z = -1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
    };

    const indices = [_]u32{
        0, 1, 2, 0, 2, 3, // front
        4, 5, 6, 4, 6, 7, // back
        8, 9, 10, 8, 10, 11, // top
        12, 13, 14, 12, 14, 15, // bottom
        16, 17, 18, 16, 18, 19, // right
        20, 21, 22, 20, 22, 23, // left
    };

    const mesh = try allocator.create(engine.Mesh);
    mesh.* = try engine.Mesh.init(allocator, &vertices, &indices);
    return mesh;
}

fn createWebOptimizedMaterial() !*engine.Material {
    // Create a simple material optimized for web performance
    const material = try allocator.create(engine.Material);
    material.* = engine.Material{
        .albedo = .{ .r = 0.8, .g = 0.3, .b = 0.2, .a = 1.0 },
        .metallic = 0.1,
        .roughness = 0.8,
        .emission = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .shader_type = .standard_pbr,
        .textures = .{},
    };
    return material;
}

// Main entry point for WASM
pub fn main() !void {
    // WASM initialization is handled through exported functions
    // This main function is primarily for testing and development
    std.log.info("MFS Engine WASM module loaded", .{});
}

// Web-specific utilities
pub fn getCanvasSize() struct { width: u32, height: u32 } {
    // This would interface with JavaScript to get canvas dimensions
    return .{ .width = 800, .height = 600 };
}

pub fn requestAnimationFrame() void {
    // This would interface with JavaScript requestAnimationFrame
}

pub fn logToConsole(message: []const u8) void {
    std.log.info("Web: {s}", .{message});
}

// Performance monitoring for web
var frame_count: u32 = 0;
var last_fps_time: f64 = 0;

pub fn updatePerformanceStats(current_time: f64) void {
    frame_count += 1;

    if (current_time - last_fps_time >= 1000.0) { // Update every second
        const fps = @as(f32, @floatFromInt(frame_count));
        std.log.info("FPS: {d:.1}", .{fps});
        frame_count = 0;
        last_fps_time = current_time;
    }
}
