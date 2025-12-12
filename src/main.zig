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

    // Setup demo scene with all system types
    if (app.scene_system) |scene| {
        setupDemoScene(scene, app) catch |err| {
            std.log.warn("Failed to setup demo scene: {}, continuing without demo scene", .{err});
        };
    }

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

/// Setup a comprehensive demo scene demonstrating all engine systems
/// This function demonstrates the integration of all systems by creating entities
/// that use different components (physics, audio, render, etc.)
fn setupDemoScene(scene: *mfs.scene.Scene, app: *mfs.engine.Application) !void {
    std.log.info("Setting up demo scene...", .{});

    const math = @import("math");
    const Transform = mfs.scene.components.Transform;
    const CameraComponent = mfs.scene.components.camera.CameraComponent;
    const PhysicsComponent = mfs.scene.components.PhysicsComponent;
    const RenderComponent = mfs.scene.components.RenderComponent;
    const AudioComponent = mfs.scene.components.AudioComponent;
    const Component = @import("scene/core/entity.zig").Component;

    // Create a camera entity
    const camera_entity_id = try scene.createEntity("MainCamera");
    if (scene.getEntity(camera_entity_id)) |camera_entity| {
        // Update transform (already exists by default)
        if (camera_entity.getComponent(Transform)) |transform| {
            transform.position = math.Vec3.init(0, 5, 10);
        }
        // Add camera component
        try camera_entity.addComponent(Component{ .camera = CameraComponent.init() });
        std.log.info("Created camera entity", .{});
    }

    // Create ground plane (static physics object)
    const ground_entity_id = try scene.createEntity("Ground");
    if (scene.getEntity(ground_entity_id)) |ground_entity| {
        // Update transform
        if (ground_entity.getComponent(Transform)) |transform| {
            transform.position = math.Vec3.init(0, -10, 0);
            transform.scale = math.Vec3.init(50, 1, 50);
        }
        // Add physics component
        var phys_comp = PhysicsComponent.init();
        phys_comp.body_type = .Static;
        phys_comp.collision_shape = .{ .box = .{ .half_extents = math.Vec3.init(25, 0.5, 25) } };
        phys_comp.mass = 0.0;
        phys_comp.restitution = 0.3;
        phys_comp.friction = 0.5;
        try ground_entity.addComponent(Component{ .physics = phys_comp });
        // Add render component
        var render_comp = RenderComponent.init();
        render_comp.material.diffuse_color = math.Vec4.init(0.5, 0.5, 0.5, 1.0);
        render_comp.material.metallic = 0.0;
        render_comp.material.shininess = 32.0;
        try ground_entity.addComponent(Component{ .render = render_comp });
        std.log.info("Created ground entity", .{});
    }

    // Create falling boxes (dynamic physics objects)
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const box_names = [_][]const u8{ "Box0", "Box1", "Box2", "Box3", "Box4" };
        const box_entity_id = try scene.createEntity(box_names[i]);
        if (scene.getEntity(box_entity_id)) |box_entity| {
            const offset_x = @as(f32, @floatFromInt(i)) * 3.0 - 6.0;
            // Update transform
            if (box_entity.getComponent(Transform)) |transform| {
                transform.position = math.Vec3.init(offset_x, 10 + @as(f32, @floatFromInt(i)) * 2.0, 0);
            }
            // Add physics component
            var phys_comp = PhysicsComponent.init();
            phys_comp.body_type = .Dynamic;
            phys_comp.collision_shape = .{ .box = .{ .half_extents = math.Vec3.init(0.5, 0.5, 0.5) } };
            phys_comp.mass = 1.0;
            phys_comp.restitution = 0.5;
            phys_comp.friction = 0.3;
            try box_entity.addComponent(Component{ .physics = phys_comp });
            // Add render component
            var render_comp = RenderComponent.init();
            const color_r = 0.2 + @as(f32, @floatFromInt(i)) * 0.15;
            const color_g = 0.3 + @as(f32, @floatFromInt(i)) * 0.1;
            render_comp.material.diffuse_color = math.Vec4.init(color_r, color_g, 0.8, 1.0);
            render_comp.material.metallic = 0.1;
            render_comp.material.shininess = 32.0;
            try box_entity.addComponent(Component{ .render = render_comp });
        }
    }
    std.log.info("Created 5 falling box entities", .{});

    // Create audio source entity
    if (app.audio_system != null) {
        const audio_entity_id = try scene.createEntity("AudioSource");
        if (scene.getEntity(audio_entity_id)) |audio_entity| {
            // Update transform
            if (audio_entity.getComponent(Transform)) |transform| {
                transform.position = math.Vec3.init(0, 5, 0);
            }
            // Add audio component
            const audio_comp = AudioComponent.initSource(0); // buffer_id 0 for demo
            try audio_entity.addComponent(Component{ .audio = audio_comp });
            std.log.info("Created audio source entity", .{});
        }
    }

    // Create AI entity if AI system is enabled
    if (app.ai_system) |ai_sys| {
        const ai_entity_config = mfs.ai.AIEntityConfig{
            .use_neural_network = true,
            .use_behavior_tree = true,
        };
        _ = try ai_sys.createAIEntity(ai_entity_config);
        std.log.info("Created AI entity", .{});
    }

    std.log.info("Demo scene setup complete: 1 camera, 1 ground, 5 boxes, audio source, AI entity", .{});
}
