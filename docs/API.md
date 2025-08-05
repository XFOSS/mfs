# MFS Engine API Reference

## Core API Modules

This document provides an overview of the main API modules in MFS Engine.

## Application Framework

```zig
const app = @import("mfs").app;

// Initialize the application
var myApp = try app.init(.{
    .title = "My MFS Application",
    .width = 800,
    .height = 600,
    .fullscreen = false,
});
defer myApp.deinit();

// Run the main loop
while (myApp.running()) {
    try myApp.beginFrame();
    // Application logic here
    try myApp.endFrame();
}
```

### Configuration

The application can be configured with various options:

```zig
const config = mfs.Config{
    .renderer_backend = .vulkan,
    .window_width = 1920,
    .window_height = 1080,
    .fullscreen = true,
    .vsync = true,
    .msaa_samples = 4,
    // See Config struct for all options
};
```

## Graphics System

### Resources

```zig
// Create a buffer
const vertex_buffer = try graphics.createBuffer(.{
    .size = vertices.len * @sizeOf(@TypeOf(vertices[0])),
    .usage = .{ .vertex = true, .transfer_dst = true },
    .memory = .gpu,
});

// Update buffer data
try graphics.updateBuffer(vertex_buffer, vertices);

// Create a texture
const texture = try graphics.createTexture(.{
    .width = 1024,
    .height = 1024,
    .format = .rgba8_unorm,
    .usage = .{ .sampled = true, .transfer_dst = true },
});
```

### Rendering

```zig
// Begin rendering
try renderer.beginFrame();

// Set viewport and scissor
renderer.setViewport(0, 0, width, height);
renderer.setScissor(0, 0, width, height);

// Bind pipeline
renderer.bindPipeline(pipeline);

// Bind resources
renderer.bindVertexBuffer(0, vertex_buffer);
renderer.bindIndexBuffer(index_buffer, .uint32);
renderer.bindUniformBuffer(0, camera_uniforms);
renderer.bindTexture(1, albedo_texture);

// Draw
renderer.draw(.{
    .vertex_count = vertex_count,
    .instance_count = 1,
    .first_vertex = 0,
    .first_instance = 0,
});

// End rendering
try renderer.endFrame();
```

## Asset Management

```zig
// Load a model
const model = try assets.loadModel("models/character.glb");
defer assets.releaseModel(model);

// Load a texture
const texture = try assets.loadTexture("textures/albedo.png", .{
    .generate_mipmaps = true,
    .srgb = true,
});

// Load a shader
const shader = try assets.loadShader("shaders/pbr.shader");
```

## Scene Graph

```zig
// Create a scene
var scene = try scene_system.createScene();
defer scene.deinit();

// Create an entity
const entity = scene.createEntity();

// Add components
try scene.addComponent(entity, Transform{
    .position = Vec3.new(0, 0, 0),
    .rotation = Quat.identity(),
    .scale = Vec3.new(1, 1, 1),
});

try scene.addComponent(entity, MeshRenderer{
    .mesh = mesh,
    .material = material,
});

// Query entities with specific components
var query = scene.query(.{ Transform, MeshRenderer });
while (query.next()) |entity| {
    var transform = scene.getComponent(entity, Transform);
    var renderer = scene.getComponent(entity, MeshRenderer);
    // Use components...
}
```

## Input System

```zig
// Check keyboard state
if (input.isKeyDown(.space)) {
    // Jump action
}

// Check mouse state
const mouse_pos = input.getMousePosition();
const mouse_delta = input.getMouseDelta();

// Check gamepad
if (input.isGamepadConnected(0)) {
    const left_stick = input.getGamepadAxis(0, .left_stick);
    // Use gamepad input...
}

// Register input actions
try input.mapAction("jump", .{ .key = .space });
try input.mapAction("fire", .{ .mouse_button = .left });

if (input.isActionJustPressed("jump")) {
    // Action system example
}
```

## Physics System

```zig
// Create a rigid body
const rigid_body = try physics.createRigidBody(.{
    .mass = 10.0,
    .position = Vec3.new(0, 5, 0),
    .type = .dynamic,
});

// Add a collider
try physics.addBoxCollider(rigid_body, .{
    .half_extents = Vec3.new(0.5, 0.5, 0.5),
    .material = .{
        .restitution = 0.5,
        .friction = 0.5,
    },
});

// Simulate physics
try physics.simulate(delta_time);

// Apply forces
physics.applyForce(rigid_body, Vec3.new(0, 0, 10));
```

## Audio System

```zig
// Load a sound
const sound = try audio.loadSound("sounds/explosion.wav");
defer audio.releaseSound(sound);

// Create a sound source
const source = try audio.createSource();
defer audio.releaseSource(source);

// Play a sound
try audio.playSound(
source, sound, .{
    .volume = 0.8,
    .pitch = 1.0,
    .loop = false,
    .spatial = true,
    .position = Vec3.new(10, 0, 5),
});

// Create a music stream
const music = try audio.loadMusic("music/background.ogg");
try audio.playMusic(music, .{
    .volume = 0.5,
    .fade_in = 2.0,
});
```

## UI System

```zig
// Create a UI context
var ui = try ui_system.createContext();
defer ui.deinit();

// Begin UI frame
ui.beginFrame();

// Create UI elements
if (ui.button("Click Me", .{ .x
 = 100, .y = 100 })) {
    // Button was clicked
}

ui.label("Hello World", .{ .x = 100, .y = 150 });

const value = try ui.slider("Volume", volume, 0, 1, .{ .x = 100, .y = 200 });

// End UI frame and render
ui.endFrame();
try
 ui.render();
```

## Math Library

```zig
// Vector operations
const position = Vec3.new(1, 2, 3);
const direction = Vec3.new(0, 1, 0);
const result = position.add(direction.scale(5));

// Matrix operations
const model = Mat4.translation(position)
    .mul(Mat4.rotation(angle, axis))
    .mul(Mat4.scaling(scale));

// Quaternion operations
const rotation = Quat.fromAxisAngle(Vec3.up(), std.math.pi * 0.5);
const oriented_direction = rotation.rotate(Vec3.forward());

// Utility functions
const distance = Vec3.distance(a, b);
const normalized = direction.normalize();
const dot_product = a.dot(b);
const cross_product = a.cross(b);
```

## Utility Functions

```zig
// Logging
log.info("Loading asset: {s}", .{asset_name});
log.warn("Performance warning: {d} ms frame time", .{frame_time});
log.err("Failed to load texture: {s}", .{@errorName(err)});

// Profiling
profiler.beginZone("Physics Update");
defer profiler.endZone();

// File I/O
const file = try vfs.openFile("config.json", .read);
defer file.close();
const content = try file.readAll(allocator);
defer allocator.free(content);

// Serialization
const config_json = try json.stringify(config, .{});
try file.writeAll(config_json);
```

## Error Handling

MFS uses Zig's error handling system:

```zig
fn loadResources() !void {
    const texture = assets.loadTexture("texture.png") catch |err| {
        log.err("Failed to load texture: {s}", .{@errorName(err)});
        return err;
    };

    errdefer assets.releaseTexture(texture);

    const model = try assets.loadModel("model.glb");

    // On success, both resources are loaded
}
```

## Memory Management

```zig
// Create an arena for temporary allocations
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const arena_allocator = arena.allocator();

// Use the engine's allocator system
const pool = try mfs.memory.createPool(.{
    .block_size = 1024 * 1024,
    .blocks_per_chunk = 10,
});
defer pool.
deinit();

// Allocate from pool
const data = try pool.alloc(u8, 1000);
defer pool.free(data);
```

## Event System

```zig
// Register event listener
try events.subscribe("entity_created", onEntityCreated);

// Define handler
fn onEntityCreated(event: *events.Event) void {
    const entity_id = event.getData(u64);
    log.info("Entity created: {d}", .{entity_id});
}

// Trigger event
try events.publish("entity_created", entity.id);
```

## For More Information

Refer to the following resources for more detailed information:
- [Engine Overview](ENGINE_OVERVIEW.html)
- [Getting Started](README.html)
- [API Reference](API_REFERENCE.html)
- [Backend-specific details](BACKENDS.html)