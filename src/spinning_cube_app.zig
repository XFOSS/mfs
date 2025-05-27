const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const print = std.debug.print;

const platform = @import("platform.zig");
const Window = @import("ui/simple_window.zig").Window;
const scene = @import("scene/scene.zig");
const graphics_types = @import("graphics/types.zig");
const backend_manager = @import("graphics/backend_manager.zig");
const interface = @import("graphics/backends/interface.zig");

const Vec3f = @import("math/vec3.zig").Vec3f;
const Mat4f = @import("math/mat4.zig").Mat4f;
const Quaternion = @import("math/math.zig").Quaternion(f32);

pub const SpinningCubeApp = struct {
    allocator: std.mem.Allocator,
    window: ?*Window,
    backend_manager: ?*backend_manager.BackendManager,
    adaptive_renderer: ?backend_manager.AdaptiveRenderer,
    scene_manager: scene.Scene,

    // Cube data
    cube_entity: scene.EntityId,
    cube_vertices: []Vertex,
    cube_indices: []u32,
    vertex_buffer: ?graphics_types.Buffer,
    index_buffer: ?graphics_types.Buffer,
    texture: ?graphics_types.Texture,
    material: ?scene.Material,

    // Uniform data
    ubo: UniformBufferObject,
    material_ubo: MaterialUBO,
    uniform_buffer: ?graphics_types.Buffer,
    material_buffer: ?graphics_types.Buffer,

    // Timing
    start_time: u64,
    last_frame_time: u64,
    frame_count: u64,
    running: bool,

    const Self = @This();

    const Vertex = struct {
        position: [3]f32,
        normal: [3]f32,
        tex_coord: [2]f32,
        color: [3]f32,
    };

    const UniformBufferObject = struct {
        model: Mat4f,
        view: Mat4f,
        proj: Mat4f,
        normal_matrix: Mat4f,
        light_pos: [3]f32,
        view_pos: [3]f32,
        time: f32,
        _padding: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 },
    };

    const MaterialUBO = struct {
        ambient: [3]f32,
        diffuse: [3]f32,
        specular: [3]f32,
        shininess: f32,
        metallic: f32,
        roughness: f32,
        emissive: [3]f32,
        _padding: f32 = 0.0,
    };

    pub fn init(allocator: std.mem.Allocator) !*Self {
        var app = try allocator.create(Self);

        app.* = Self{
            .allocator = allocator,
            .window = null,
            .backend_manager = null,
            .adaptive_renderer = null,
            .scene_manager = try scene.Scene.init(allocator, scene.SceneConfig{}),
            .cube_entity = 0,
            .cube_vertices = &[_]Vertex{},
            .cube_indices = &[_]u32{},
            .vertex_buffer = null,
            .index_buffer = null,
            .texture = null,
            .material = null,
            .ubo = std.mem.zeroes(UniformBufferObject),
            .material_ubo = std.mem.zeroes(MaterialUBO),
            .uniform_buffer = null,
            .material_buffer = null,
            .start_time = 0,
            .last_frame_time = 0,
            .frame_count = 0,
            .running = true,
        };

        try app.initGraphics();
        try app.initWindow();
        try app.initScene();
        try app.createCube();
        try app.loadTexture();
        try app.setupMaterial();

        print("Spinning Cube Application initialized successfully!\n");
        return app;
    }

    pub fn deinit(self: *Self) void {
        self.cleanup();
        self.scene_manager.deinit();

        if (self.window) |window| {
            window.deinit();
        }

        if (self.backend_manager) |manager| {
            manager.deinit();
        }

        self.allocator.free(self.cube_vertices);
        self.allocator.free(self.cube_indices);

        if (self.material) |mat| {
            mat.deinit();
        }

        self.allocator.destroy(self);
    }

    fn initGraphics(self: *Self) !void {
        const manager_options = backend_manager.BackendManager.InitOptions{
            .preferred_backend = null,
            .auto_fallback = true,
            .debug_mode = (builtin.mode == .Debug),
            .validate_backends = true,
            .enable_backend_switching = false,
        };

        self.backend_manager = try backend_manager.BackendManager.init(self.allocator, manager_options);
        self.adaptive_renderer = try self.backend_manager.?.createAdaptiveRenderer();
    }

    fn initWindow(self: *Self) !void {
        self.window = try Window.init(self.allocator, .{
            .title = "Spinning Textured Cube - MFS Engine",
            .width = 1280,
            .height = 720,
            .resizable = true,
        });

        try self.window.?.show();
        print("Window created: 1280x720\n");
    }

    fn initScene(self: *Self) !void {
        // Setup camera
        var camera = self.scene_manager.getCamera();
        camera.setPosition(0.0, 0.0, 5.0);
        camera.setTarget(0.0, 0.0, 0.0);
        camera.setPerspective(45.0, 1280.0 / 720.0, 0.1, 100.0);

        // Create cube entity
        self.cube_entity = try self.scene_manager.createEntity();
        _ = self.scene_manager.setEntityPosition(self.cube_entity, 0.0, 0.0, 0.0);
    }

    fn createCube(self: *Self) !void {
        // Define cube vertices with positions, normals, texture coordinates, and colors
        const vertices = [_]Vertex{
            // Front face
            Vertex{ .position = [3]f32{ -1.0, -1.0, 1.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .tex_coord = [2]f32{ 0.0, 0.0 }, .color = [3]f32{ 1.0, 0.0, 0.0 } },
            Vertex{ .position = [3]f32{ 1.0, -1.0, 1.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .tex_coord = [2]f32{ 1.0, 0.0 }, .color = [3]f32{ 0.0, 1.0, 0.0 } },
            Vertex{ .position = [3]f32{ 1.0, 1.0, 1.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .tex_coord = [2]f32{ 1.0, 1.0 }, .color = [3]f32{ 0.0, 0.0, 1.0 } },
            Vertex{ .position = [3]f32{ -1.0, 1.0, 1.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .tex_coord = [2]f32{ 0.0, 1.0 }, .color = [3]f32{ 1.0, 1.0, 0.0 } },

            // Back face
            Vertex{ .position = [3]f32{ -1.0, -1.0, -1.0 }, .normal = [3]f32{ 0.0, 0.0, -1.0 }, .tex_coord = [2]f32{ 1.0, 0.0 }, .color = [3]f32{ 1.0, 0.0, 1.0 } },
            Vertex{ .position = [3]f32{ -1.0, 1.0, -1.0 }, .normal = [3]f32{ 0.0, 0.0, -1.0 }, .tex_coord = [2]f32{ 1.0, 1.0 }, .color = [3]f32{ 0.0, 1.0, 1.0 } },
            Vertex{ .position = [3]f32{ 1.0, 1.0, -1.0 }, .normal = [3]f32{ 0.0, 0.0, -1.0 }, .tex_coord = [2]f32{ 0.0, 1.0 }, .color = [3]f32{ 0.5, 0.5, 0.5 } },
            Vertex{ .position = [3]f32{ 1.0, -1.0, -1.0 }, .normal = [3]f32{ 0.0, 0.0, -1.0 }, .tex_coord = [2]f32{ 0.0, 0.0 }, .color = [3]f32{ 1.0, 0.5, 0.0 } },

            // Left face
            Vertex{ .position = [3]f32{ -1.0, -1.0, -1.0 }, .normal = [3]f32{ -1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 0.0 }, .color = [3]f32{ 0.5, 0.0, 0.5 } },
            Vertex{ .position = [3]f32{ -1.0, -1.0, 1.0 }, .normal = [3]f32{ -1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 0.0 }, .color = [3]f32{ 0.0, 0.5, 0.5 } },
            Vertex{ .position = [3]f32{ -1.0, 1.0, 1.0 }, .normal = [3]f32{ -1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 1.0 }, .color = [3]f32{ 0.7, 0.3, 0.1 } },
            Vertex{ .position = [3]f32{ -1.0, 1.0, -1.0 }, .normal = [3]f32{ -1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 1.0 }, .color = [3]f32{ 0.2, 0.8, 0.4 } },

            // Right face
            Vertex{ .position = [3]f32{ 1.0, -1.0, -1.0 }, .normal = [3]f32{ 1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 0.0 }, .color = [3]f32{ 0.9, 0.1, 0.6 } },
            Vertex{ .position = [3]f32{ 1.0, 1.0, -1.0 }, .normal = [3]f32{ 1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 1.0 }, .color = [3]f32{ 0.3, 0.9, 0.2 } },
            Vertex{ .position = [3]f32{ 1.0, 1.0, 1.0 }, .normal = [3]f32{ 1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 1.0 }, .color = [3]f32{ 0.8, 0.2, 0.9 } },
            Vertex{ .position = [3]f32{ 1.0, -1.0, 1.0 }, .normal = [3]f32{ 1.0, 0.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 0.0 }, .color = [3]f32{ 0.1, 0.7, 0.8 } },

            // Top face
            Vertex{ .position = [3]f32{ -1.0, 1.0, -1.0 }, .normal = [3]f32{ 0.0, 1.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 1.0 }, .color = [3]f32{ 0.6, 0.4, 0.7 } },
            Vertex{ .position = [3]f32{ -1.0, 1.0, 1.0 }, .normal = [3]f32{ 0.0, 1.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 0.0 }, .color = [3]f32{ 0.4, 0.6, 0.3 } },
            Vertex{ .position = [3]f32{ 1.0, 1.0, 1.0 }, .normal = [3]f32{ 0.0, 1.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 0.0 }, .color = [3]f32{ 0.8, 0.8, 0.1 } },
            Vertex{ .position = [3]f32{ 1.0, 1.0, -1.0 }, .normal = [3]f32{ 0.0, 1.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 1.0 }, .color = [3]f32{ 0.2, 0.2, 0.9 } },

            // Bottom face
            Vertex{ .position = [3]f32{ -1.0, -1.0, -1.0 }, .normal = [3]f32{ 0.0, -1.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 1.0 }, .color = [3]f32{ 0.7, 0.7, 0.7 } },
            Vertex{ .position = [3]f32{ 1.0, -1.0, -1.0 }, .normal = [3]f32{ 0.0, -1.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 1.0 }, .color = [3]f32{ 0.5, 0.8, 0.6 } },
            Vertex{ .position = [3]f32{ 1.0, -1.0, 1.0 }, .normal = [3]f32{ 0.0, -1.0, 0.0 }, .tex_coord = [2]f32{ 0.0, 0.0 }, .color = [3]f32{ 0.9, 0.3, 0.7 } },
            Vertex{ .position = [3]f32{ -1.0, -1.0, 1.0 }, .normal = [3]f32{ 0.0, -1.0, 0.0 }, .tex_coord = [2]f32{ 1.0, 0.0 }, .color = [3]f32{ 0.1, 0.9, 0.5 } },
        };

        // Define indices for the cube faces
        const indices = [_]u32{
            // Front face
            0,  1,  2,  2,  3,  0,
            // Back face
            4,  5,  6,  6,  7,  4,
            // Left face
            8,  9,  10, 10, 11, 8,
            // Right face
            12, 13, 14, 14, 15, 12,
            // Top face
            16, 17, 18, 18, 19, 16,
            // Bottom face
            20, 21, 22, 22, 23, 20,
        };

        // Allocate and copy vertex data
        self.cube_vertices = try self.allocator.dupe(Vertex, &vertices);
        self.cube_indices = try self.allocator.dupe(u32, &indices);

        // Create vertex buffer
        self.vertex_buffer = try graphics_types.Buffer.init(self.allocator, @sizeOf(Vertex) * vertices.len, .vertex);

        // Create index buffer
        self.index_buffer = try graphics_types.Buffer.init(self.allocator, @sizeOf(u32) * indices.len, .index);

        print("Cube geometry created with {} vertices and {} indices\n", .{ vertices.len, indices.len });
    }

    fn loadTexture(self: *Self) !void {
        // Create a procedural texture (checkered pattern)
        const texture_size = 256;
        const texture_data = try self.allocator.alloc(u8, texture_size * texture_size * 4);
        defer self.allocator.free(texture_data);

        // Generate checkered pattern
        for (0..texture_size) |y| {
            for (0..texture_size) |x| {
                const offset = (y * texture_size + x) * 4;
                const checker = ((x / 32) + (y / 32)) % 2;

                if (checker == 0) {
                    // White squares
                    texture_data[offset + 0] = 255; // R
                    texture_data[offset + 1] = 255; // G
                    texture_data[offset + 2] = 255; // B
                    texture_data[offset + 3] = 255; // A
                } else {
                    // Blue squares
                    texture_data[offset + 0] = 64; // R
                    texture_data[offset + 1] = 128; // G
                    texture_data[offset + 2] = 255; // B
                    texture_data[offset + 3] = 255; // A
                }
            }
        }

        // Create texture
        self.texture = try graphics_types.Texture.init(self.allocator, texture_size, texture_size, .rgba8);

        print("Procedural checkered texture created ({}x{})\n", .{ texture_size, texture_size });
    }

    fn setupMaterial(self: *Self) !void {
        // Create material
        self.material = try scene.Material.init(self.allocator, "CubeMaterial");

        // Set material properties
        self.material.?.setDiffuseColor(0.8, 0.8, 0.8, 1.0);
        self.material.?.setSpecularColor(1.0, 1.0, 1.0);
        self.material.?.setShininess(64.0);

        // Setup material UBO data
        self.material_ubo = MaterialUBO{
            .ambient = [3]f32{ 0.2, 0.2, 0.2 },
            .diffuse = [3]f32{ 0.8, 0.8, 0.8 },
            .specular = [3]f32{ 1.0, 1.0, 1.0 },
            .shininess = 64.0,
            .metallic = 0.3,
            .roughness = 0.4,
            .emissive = [3]f32{ 0.0, 0.0, 0.0 },
        };

        // Create material buffer
        self.material_buffer = try graphics_types.Buffer.init(self.allocator, @sizeOf(MaterialUBO), .uniform);

        print("Material setup complete with PBR properties\n");
    }

    fn setupUniformBuffers(self: *Self) !void {
        // Create uniform buffer
        self.uniform_buffer = try graphics_types.Buffer.init(self.allocator, @sizeOf(UniformBufferObject), .uniform);
    }

    fn updateUniforms(self: *Self, delta_time: f32) void {
        const current_time = @as(f32, @floatFromInt(std.time.milliTimestamp() - self.start_time)) / 1000.0;

        // Update time for animation
        self.ubo.time = current_time;

        // Setup matrices
        const camera = self.scene_manager.getCamera();

        // Model matrix (identity, rotation handled in shader)
        self.ubo.model = Mat4f.identity();

        // View matrix
        const camera_pos = Vec3f.init(camera.position[0], camera.position[1], camera.position[2]);
        const camera_target = Vec3f.init(camera.target[0], camera.target[1], camera.target[2]);
        const camera_up = Vec3f.init(camera.up[0], camera.up[1], camera.up[2]);
        self.ubo.view = Mat4f.lookAt(camera_pos, camera_target, camera_up);

        // Projection matrix
        self.ubo.proj = Mat4f.perspective(math.degreesToRadians(camera.fov), camera.aspect, camera.near, camera.far);

        // Normal matrix (for lighting calculations)
        self.ubo.normal_matrix = self.ubo.model.transpose().inverse();

        // Light position (orbiting around the cube)
        const light_orbit_radius = 4.0;
        const light_orbit_speed = 0.5;
        self.ubo.light_pos = [3]f32{
            math.cos(current_time * light_orbit_speed) * light_orbit_radius,
            2.0,
            math.sin(current_time * light_orbit_speed) * light_orbit_radius,
        };

        // View position
        self.ubo.view_pos = [3]f32{ camera.position[0], camera.position[1], camera.position[2] };

        _ = delta_time; // Currently unused but available for frame-rate independent updates
    }

    fn cleanup(self: *Self) void {
        if (self.vertex_buffer) |*buffer| {
            buffer.deinit();
        }
        if (self.index_buffer) |*buffer| {
            buffer.deinit();
        }
        if (self.uniform_buffer) |*buffer| {
            buffer.deinit();
        }
        if (self.material_buffer) |*buffer| {
            buffer.deinit();
        }
        if (self.texture) |*texture| {
            texture.deinit();
        }
    }

    pub fn run(self: *Self) !void {
        print("=== Starting Spinning Cube Application ===\n");

        self.start_time = @intCast(std.time.milliTimestamp());
        self.last_frame_time = self.start_time;

        try self.setupUniformBuffers();

        print("Entering main render loop...\n");
        print("Controls: Close window to exit\n");
        print("Features: Textured spinning cube with PBR material and dynamic lighting\n");

        while (self.running) {
            const current_time = @as(u64, @intCast(std.time.milliTimestamp()));
            const delta_time = @as(f32, @floatFromInt(current_time - self.last_frame_time)) / 1000.0;

            try self.update(delta_time);
            try self.render();

            self.last_frame_time = current_time;
            self.frame_count += 1;

            // Print status every 300 frames
            if (self.frame_count % 300 == 0) {
                const fps = 1.0 / delta_time;
                const runtime = @as(f32, @floatFromInt(current_time - self.start_time)) / 1000.0;
                print("Frame: {} | FPS: {d:.1} | Runtime: {d:.1}s | Cube spinning with texture and materials\n", .{ self.frame_count, fps, runtime });
            }

            // Check if window should close
            if (self.window) |window| {
                if (window.shouldClose()) {
                    self.running = false;
                }
            }

            // Limit to ~60 FPS
            std.time.sleep(16_000_000);
        }

        print("Spinning cube application completed after {} frames\n", .{self.frame_count});
    }

    fn update(self: *Self, delta_time: f32) !void {
        // Update scene
        self.scene_manager.update(delta_time);

        // Update uniforms with current time and matrices
        self.updateUniforms(delta_time);

        // Handle window events
        if (self.window) |window| {
            try window.pollEvents();
        }
    }

    fn render(self: *Self) !void {
        if (self.adaptive_renderer) |*renderer| {
            // Prepare frame data
            const frame_data = struct {
                frame_number: u64,
                time: f32,
                delta_time: f32,
                vertices: []const Vertex,
                indices: []const u32,
                ubo: UniformBufferObject,
                material_ubo: MaterialUBO,
            }{
                .frame_number = self.frame_count,
                .time = self.ubo.time,
                .delta_time = @as(f32, @floatFromInt(std.time.milliTimestamp() - self.last_frame_time)) / 1000.0,
                .vertices = self.cube_vertices,
                .indices = self.cube_indices,
                .ubo = self.ubo,
                .material_ubo = self.material_ubo,
            };

            // Render the frame
            try renderer.render(frame_data);
        } else if (self.backend_manager) |manager| {
            if (manager.getPrimaryBackend()) |backend| {
                try self.performBasicRendering(backend);
            }
        }
    }

    fn performBasicRendering(self: *Self, backend: *interface.GraphicsBackend) !void {
        // Create command buffer
        var cmd_buffer = backend.createCommandBuffer() catch return;
        defer cmd_buffer.deinit();

        // Begin command recording
        try backend.beginCommandBuffer(cmd_buffer);

        // Begin render pass with clear color
        const render_pass_desc = interface.RenderPassDesc{
            .clear_color = graphics_types.ClearColor{
                .r = 0.1,
                .g = 0.1,
                .b = 0.2,
                .a = 1.0,
            },
            .clear_depth = 1.0,
            .clear_stencil = 0,
        };

        backend.beginRenderPass(cmd_buffer, &render_pass_desc) catch {};

        // Set viewport
        const viewport = graphics_types.Viewport{
            .x = 0,
            .y = 0,
            .width = 1280,
            .height = 720,
        };
        backend.setViewport(cmd_buffer, &viewport) catch {};

        // Draw the cube
        const draw_cmd = interface.DrawCommand{
            .vertex_count = @intCast(self.cube_indices.len),
            .instance_count = 1,
            .first_vertex = 0,
            .first_instance = 0,
        };
        backend.draw(cmd_buffer, &draw_cmd) catch {};

        // End render pass
        backend.endRenderPass(cmd_buffer) catch {};

        // End command recording
        try backend.endCommandBuffer(cmd_buffer);

        // Submit commands
        try backend.submitCommandBuffer(cmd_buffer);

        // Present
        backend.present() catch {};
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("=== MFS Spinning Textured Cube Demo ===\n");
    print("Initializing application...\n");

    var app = SpinningCubeApp.init(allocator) catch |err| {
        print("Failed to initialize application: {}\n", .{err});
        return;
    };
    defer app.deinit();

    print("Application initialized successfully!\n");

    // Run the application
    app.run() catch |err| {
        print("Application error: {}\n", .{err});
    };

    print("=== Spinning Cube Demo Complete ===\n");
}
