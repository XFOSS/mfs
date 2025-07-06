# MFS Engine API Reference

## Table of Contents

1. [Core Engine](#core-engine)
2. [Graphics System](#graphics-system)
3. [Physics System](#physics-system)
4. [Audio System](#audio-system)
5. [Scene Management](#scene-management)
6. [Resource Management](#resource-management)
7. [Input System](#input-system)
8. [UI Framework](#ui-framework)
9. [Math Library](#math-library)
10. [Platform Layer](#platform-layer)
11. [Asset Processing](#asset-processing)
12. [Configuration System](#configuration-system)

---

## Core Engine

### Engine Initialization

```zig
const nyx = @import("nyx_std.zig");

// Basic engine configuration
const config = nyx.EngineConfig{
    .enable_gpu = true,
    .enable_physics = true,
    .enable_audio = true,
    .window_width = 1920,
    .window_height = 1080,
    .window_title = "My Game",
    .target_fps = 60,
    .max_memory_budget_mb = 512,
};

// Initialize engine
var engine = try nyx.Engine.init(allocator, config);
defer engine.deinit();

// Main loop
while (engine.shouldContinue()) {
    try engine.update();
    try engine.render();
}
```

### Engine Configuration Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enable_gpu` | `bool` | `true` | Enable GPU acceleration |
| `enable_physics` | `bool` | `true` | Enable physics simulation |
| `enable_neural` | `bool` | `false` | Enable neural network support |
| `enable_xr` | `bool` | `false` | Enable XR/VR support |
| `enable_audio` | `bool` | `true` | Enable audio system |
| `enable_networking` | `bool` | `false` | Enable networking |
| `window_width` | `u32` | `1280` | Window width in pixels |
| `window_height` | `u32` | `720` | Window height in pixels |
| `target_fps` | `u32` | `60` | Target frame rate |
| `max_memory_budget_mb` | `u64` | `512` | Maximum memory budget in MB |

---

## Graphics System

### Backend Selection

The MFS engine supports multiple graphics backends:

- **Vulkan** - High-performance, low-level API
- **DirectX 11** - Windows compatibility
- **DirectX 12** - Modern Windows API
- **Metal** - macOS/iOS native API
- **OpenGL** - Cross-platform compatibility
- **OpenGL ES** - Mobile/embedded devices
- **WebGPU** - Web platform support
- **Software** - CPU-based fallback

```zig
const gpu = @import("graphics/gpu.zig");

// Initialize graphics with preferred backend
const gpu_options = gpu.backend_manager.BackendManager.InitOptions{
    .preferred_backend = .vulkan,
    .debug_mode = true,
};
try gpu.init(allocator, gpu_options);
```

### Rendering Pipeline

```zig
// Create render pass
const render_pass = try gpu.createRenderPass(.{
    .color_attachments = &[_]gpu.ColorAttachment{
        .{
            .format = .rgba8_unorm,
            .load_op = .clear,
            .store_op = .store,
            .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        },
    },
    .depth_attachment = .{
        .format = .depth32_float,
        .load_op = .clear,
        .store_op = .store,
        .clear_depth = 1.0,
    },
});

// Create graphics pipeline
const pipeline = try gpu.createGraphicsPipeline(.{
    .vertex_shader = vertex_shader,
    .fragment_shader = fragment_shader,
    .vertex_layout = vertex_layout,
    .render_pass = render_pass,
});
```

### Buffer Management

```zig
// Create vertex buffer
const vertex_buffer = try gpu.createBuffer(.{
    .size = vertices.len * @sizeOf(Vertex),
    .usage = .{ .vertex = true },
    .memory_type = .device_local,
});

// Upload data
try gpu.updateBuffer(vertex_buffer, 0, std.mem.sliceAsBytes(vertices));

// Bind and draw
const cmd = try gpu.beginCommandBuffer();
try cmd.bindVertexBuffer(vertex_buffer, 0);
try cmd.draw(vertices.len, 1, 0, 0);
try gpu.submitCommandBuffer(cmd);
```

### Texture Operations

```zig
// Load texture from file
const texture = try gpu.createTextureFromFile("assets/textures/diffuse.png");

// Create texture sampler
const sampler = try gpu.createSampler(.{
    .min_filter = .linear,
    .mag_filter = .linear,
    .wrap_u = .repeat,
    .wrap_v = .repeat,
});

// Bind for rendering
try cmd.bindTexture(texture, 0);
try cmd.bindSampler(sampler, 0);
```

---

## Physics System

### Rigid Body Dynamics

```zig
const physics = @import("physics/physics_engine.zig");

// Initialize physics world
var physics_world = try physics.PhysicsEngine.init(allocator, .{
    .gravity = .{ .x = 0, .y = -9.81, .z = 0 },
    .time_step = 1.0 / 60.0,
});
defer physics_world.deinit();

// Create rigid body
const body = try physics_world.createRigidBody(.{
    .position = .{ .x = 0, .y = 10, .z = 0 },
    .mass = 1.0,
    .shape = .{ .box = .{ .width = 1, .height = 1, .depth = 1 } },
    .material = .{
        .restitution = 0.6,
        .friction = 0.4,
        .density = 1.0,
    },
});

// Step simulation
try physics_world.step();
```

### Collision Detection

```zig
// Set up collision callback
physics_world.setCollisionCallback(onCollision);

fn onCollision(contact: physics.ContactInfo) void {
    std.log.info("Collision between {} and {}", .{ contact.body_a, contact.body_b });
    // Handle collision response
}

// Query world for objects
const query_result = try physics_world.queryAABB(.{
    .min = .{ .x = -5, .y = -5, .z = -5 },
    .max = .{ .x = 5, .y = 5, .z = 5 },
});
```

### Constraints and Joints

```zig
// Create distance constraint
const constraint = try physics_world.createConstraint(.{
    .type = .distance,
    .body_a = body1,
    .body_b = body2,
    .anchor_a = .{ .x = 0, .y = 0, .z = 0 },
    .anchor_b = .{ .x = 0, .y = 0, .z = 0 },
    .distance = 2.0,
});
```

---

## Audio System

### Audio Playback

```zig
const audio = @import("audio/audio.zig");

// Initialize audio system
var audio_system = try audio.AudioSystem.init(allocator);
defer audio_system.deinit();

// Load and play sound
const sound = try audio_system.loadSound("assets/audio/explosion.wav");
const source = try audio_system.createSource();
try source.setBuffer(sound);
try source.play();

// 3D positioned audio
try source.setPosition(.{ .x = 10, .y = 0, .z = 5 });
try source.setVelocity(.{ .x = 0, .y = 0, .z = -2 });
```

### Audio Effects

```zig
// Apply reverb effect
const reverb = try audio_system.createEffect(.reverb);
try reverb.setParameter(.room_size, 0.8);
try reverb.setParameter(.damping, 0.5);
try source.addEffect(reverb);

// Volume and pitch control
try source.setVolume(0.7);
try source.setPitch(1.2);
```

---

## Scene Management

### Entity-Component System

```zig
const scene = @import("scene/scene.zig");

// Create scene
var game_scene = try scene.Scene.init(allocator);
defer game_scene.deinit();

// Create entity
const entity = try game_scene.createEntity();

// Add components
try game_scene.addComponent(entity, scene.Transform{
    .position = .{ .x = 0, .y = 0, .z = 0 },
    .rotation = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
    .scale = .{ .x = 1, .y = 1, .z = 1 },
});

try game_scene.addComponent(entity, scene.RenderComponent{
    .mesh = mesh_handle,
    .material = material_handle,
    .visible = true,
});

try game_scene.addComponent(entity, scene.PhysicsComponent{
    .body = physics_body,
    .collision_group = 1,
});
```

### Systems

```zig
// Register systems
try game_scene.registerSystem(scene.TransformSystem);
try game_scene.registerSystem(scene.RenderSystem);
try game_scene.registerSystem(scene.PhysicsSystem);

// Update all systems
try game_scene.update(delta_time);
```

### Scene Serialization

```zig
// Save scene to file
try game_scene.saveToFile("levels/level1.scene");

// Load scene from file
var loaded_scene = try scene.Scene.loadFromFile(allocator, "levels/level1.scene");
```

---

## Resource Management

### Asset Loading

```zig
const resources = @import("nyx_std.zig");

// Initialize resource manager
var resource_manager = try resources.ResourceManager.init(allocator);
defer resource_manager.deinit();

// Load assets
const texture_handle = try resource_manager.loadAsset("textures/player.png");
const model_handle = try resource_manager.loadAsset("models/character.obj");
const audio_handle = try resource_manager.loadAsset("audio/footsteps.wav");

// Get loaded asset
if (resource_manager.getAsset(texture_handle)) |texture| {
    // Use texture
}
```

### Hot Reloading

```zig
// Enable hot reloading for development
resource_manager.enableHotReload();

// Assets will automatically reload when files change
// Callback for reload events
resource_manager.setReloadCallback(onAssetReloaded);

fn onAssetReloaded(asset_path: []const u8) void {
    std.log.info("Asset reloaded: {s}", .{asset_path});
}
```

---

## Input System

### Input Handling

```zig
const input = @import("input/input.zig");

// Initialize input system
var input_system = try input.InputManager.init(allocator);
defer input_system.deinit();

// Poll input events
input_system.update();

// Check input states
if (input_system.isKeyPressed(.space)) {
    // Handle jump
}

if (input_system.isMouseButtonDown(.left)) {
    const mouse_pos = input_system.getMousePosition();
    // Handle mouse interaction
}

// Gamepad support
if (input_system.isGamepadConnected(0)) {
    const left_stick = input_system.getGamepadStick(0, .left);
    // Handle movement
}
```

### Input Mapping

```zig
// Create input map
var input_map = input.InputMap.init(allocator);
try input_map.bind("jump", .{ .key = .space });
try input_map.bind("fire", .{ .mouse = .left });
try input_map.bind("move", .{ .gamepad_stick = .left });

// Use mapped inputs
if (input_map.isActionPressed("jump")) {
    // Handle jump action
}
```

---

## UI Framework

### UI Creation

```zig
const ui = @import("ui/ui.zig");

// Initialize UI system
var ui_system = try ui.UISystem.init(allocator, .{
    .backend_type = .vulkan,
    .enable_threading = true,
});
defer ui_system.deinit();

// Create UI elements
const button = try ui_system.createButton(.{
    .text = "Start Game",
    .position = .{ .x = 100, .y = 50 },
    .size = .{ .width = 200, .height = 40 },
    .on_click = onStartButtonClick,
});

const text_field = try ui_system.createTextField(.{
    .placeholder = "Enter name...",
    .position = .{ .x = 100, .y = 100 },
    .size = .{ .width = 300, .height = 30 },
});
```

### UI Styling

```zig
// Apply styling
const style = ui.Style{
    .background_color = .{ .r = 0.2, .g = 0.3, .b = 0.8, .a = 1.0 },
    .border_color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    .border_width = 2.0,
    .corner_radius = 5.0,
    .font_size = 16,
    .font_color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
};

try ui_system.setStyle(button, style);
```

---

## Math Library

### Vector Operations

```zig
const math = @import("math/math.zig");

// Vector creation and operations
const v1 = math.Vec3.init(1.0, 2.0, 3.0);
const v2 = math.Vec3.init(4.0, 5.0, 6.0);

const sum = v1.add(v2);
const dot_product = v1.dot(v2);
const cross_product = v1.cross(v2);
const normalized = v1.normalize();
const length = v1.length();
```

### Matrix Operations

```zig
// Matrix creation and transformations
const identity = math.Mat4.identity();
const translation = math.Mat4.translation(1.0, 2.0, 3.0);
const rotation = math.Mat4.rotationY(math.toRadians(45.0));
const scale = math.Mat4.scaling(2.0, 2.0, 2.0);

// Combine transformations
const transform = translation.multiply(rotation).multiply(scale);

// Camera matrices
const view = math.Mat4.lookAt(
    .{ .x = 0, .y = 0, .z = 5 }, // eye
    .{ .x = 0, .y = 0, .z = 0 }, // target
    .{ .x = 0, .y = 1, .z = 0 }, // up
);

const projection = math.Mat4.perspective(
    math.toRadians(60.0), // fov
    16.0 / 9.0,          // aspect ratio
    0.1,                 // near
    100.0                // far
);
```

---

## Platform Layer

### Window Management

```zig
const window = @import("window/window.zig");

// Create window
const window_config = window.WindowConfig{
    .width = 1920,
    .height = 1080,
    .title = "My Game",
    .fullscreen = false,
    .resizable = true,
    .vsync = true,
};

var game_window = try window.Window.init(allocator, window_config);
defer game_window.deinit();

// Window events
while (!game_window.shouldClose()) {
    game_window.pollEvents();
    
    // Handle resize
    if (game_window.wasResized()) {
        const new_size = game_window.getSize();
        // Update viewport
    }
}
```

### Platform Capabilities

```zig
const platform = @import("platform/platform.zig");

// Query platform capabilities
const caps = platform.getCapabilities();

if (caps.supports_vulkan) {
    // Use Vulkan backend
}

if (caps.supports_compute_shaders) {
    // Enable compute shader features
}

const memory_info = platform.getMemoryInfo();
std.log.info("Available memory: {} MB", .{memory_info.available_mb});
```

---

## Asset Processing

### Command Line Usage

```bash
# Process all assets
./asset_processor input_assets/ output_assets/

# Process specific asset types
./asset_processor input_assets/ output_assets/ --type texture --type model

# Enable verbose output and force reprocessing
./asset_processor input_assets/ output_assets/ --verbose --force

# Set compression level and disable mipmaps
./asset_processor input_assets/ output_assets/ --compression 5 --no-mipmaps
```

### Programmatic Usage

```zig
const asset_processor = @import("tools/asset_processor/asset_processor.zig");

// Configure processor
const config = asset_processor.ProcessorConfig{
    .input_dir = "raw_assets/",
    .output_dir = "processed_assets/",
    .asset_types = &[_]asset_processor.AssetType{ .texture, .model },
    .compression_level = 9,
    .generate_mipmaps = true,
    .verbose = true,
};

// Run processing
var processor = try asset_processor.AssetProcessor.init(allocator, config);
defer processor.deinit();

try processor.processAllAssets();
```

---

## Configuration System

### Engine Configuration

```zig
const config = @import("system/config.zig");

// Load configuration from file
var engine_config = try config.Config.loadFromFile("config/engine.json");

// Access configuration values
const renderer_backend = engine_config.renderer_backend;
const window_width = engine_config.window_width;
const enable_debug = engine_config.debug_mode;

// Save configuration
try engine_config.saveToFile("config/engine.json");
```

### Runtime Configuration

```zig
// Create configuration with defaults
var runtime_config = config.Config{
    .renderer_backend = .vulkan,
    .window_width = 1920,
    .window_height = 1080,
    .fullscreen = false,
    .vsync = true,
    .debug_mode = false,
};

// Validate configuration
try runtime_config.validate();
```

---

## Error Handling

### Error Types

The MFS engine defines comprehensive error types for different subsystems:

```zig
// Engine errors
const EngineError = error{
    InitializationFailed,
    InvalidConfiguration,
    ResourceLoadError,
    OutOfMemory,
    GraphicsAPIError,
    AudioSystemError,
    NetworkError,
    FileSystemError,
    ThreadingError,
    ValidationError,
};

// Graphics errors
const GraphicsError = error{
    BackendNotSupported,
    ShaderCompilationFailed,
    BufferCreationFailed,
    TextureLoadFailed,
    PipelineCreationFailed,
};
```

### Error Recovery

```zig
// Graceful error handling with fallbacks
const backend = gpu.initWithFallback(&[_]gpu.BackendType{
    .vulkan,
    .d3d11,
    .opengl,
    .software,
}) catch |err| {
    std.log.err("Failed to initialize any graphics backend: {}", .{err});
    return err;
};
```

---

## Performance Monitoring

### Built-in Profiling

```zig
const profiler = @import("system/profiling/profiler.zig");

// Enable profiling
profiler.enable();

// Profile a section
{
    const profile_scope = profiler.beginScope("render_frame");
    defer profile_scope.end();
    
    // Rendering code here
}

// Get profiling results
const results = profiler.getResults();
for (results.scopes) |scope| {
    std.log.info("{s}: {d}ms", .{ scope.name, scope.duration_ms });
}
```

### Memory Tracking

```zig
const memory_profiler = @import("system/profiling/memory_profiler.zig");

// Track memory allocations
memory_profiler.trackAllocator(allocator);

// Get memory statistics
const stats = memory_profiler.getStats();
std.log.info("Memory usage: {d} MB", .{stats.current_usage_mb});
std.log.info("Peak memory: {d} MB", .{stats.peak_usage_mb});
```

---

## Threading and Concurrency

### Task System

```zig
const task_system = @import("system/task_system.zig");

// Initialize task system
var tasks = try task_system.TaskSystem.init(allocator, 4); // 4 worker threads
defer tasks.deinit();

// Submit tasks
const task = try tasks.submit(myTaskFunction, task_data);

// Wait for completion
try task.wait();

// Parallel for loop
try tasks.parallelFor(0, 1000, processItem);
```

---

This API reference provides comprehensive coverage of the MFS engine's capabilities. For more detailed examples and advanced usage patterns, refer to the individual module documentation and example projects. 