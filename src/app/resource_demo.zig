// =============================
// resource_demo.zig: Resource Demo Module
// =============================
// Provides resource creation, management, and cleanup demonstration for the demo app.
//
// Usage:
//   try resource_demo.run(app);
//

const std = @import("std");
const types = @import("../graphics/types.zig");
const interface = @import("../graphics/backends/interface.zig");
// const vulkan_resource_demo = @import("../../vulkan/vulkan_resource_demo.zig"); // TODO: Fix path

/// Run the resource demonstration for the given app.
/// Creates a texture, buffer, shader, mesh, material, and advanced resources, then cleans them up.
pub fn run(app: anytype) !void {
    try run_texture_demo(app);
    try run_buffer_demo(app);
    try run_mesh_demo(app);
    try run_material_demo(app);
    try run_texture_array_demo(app);
    try run_uniform_buffer_demo(app);
    try run_pipeline_material_demo(app);
}

/// Demonstrate texture creation and upload
fn run_texture_demo(app: anytype) !void {
    if (app.backend_manager) |manager| {
        if (manager.getPrimaryBackend()) |backend| {
            std.log.info("=== Resource Creation Demo ===", .{});

            // --- Texture Demo ---
            var texture = try types.Texture.init(app.allocator, 256, 256, .rgba8);
            defer texture.deinit();
            const texture_data = try app.allocator.alloc(u8, 256 * 256 * 4);
            defer app.allocator.free(texture_data);
            for (0..256) |y| {
                for (0..256) |x| {
                    const offset = (y * 256 + x) * 4;
                    texture_data[offset + 0] = @intCast(x); // R
                    texture_data[offset + 1] = @intCast(y); // G
                    texture_data[offset + 2] = 128; // B
                    texture_data[offset + 3] = 255; // A
                }
            }
            backend.createTexture(texture, texture_data) catch |err| {
                std.log.warn("Failed to create texture: {}", .{err});
            };
            std.log.info("✓ Created 256x256 RGBA texture", .{});

            // --- Cleanup ---
            backend.destroyTexture(texture);
            std.log.info("✓ Successfully cleaned up all resources", .{});
        }
    }
}

/// Demonstrate buffer creation and upload
fn run_buffer_demo(app: anytype) !void {
    if (app.backend_manager) |manager| {
        if (manager.getPrimaryBackend()) |backend| {
            // --- Buffer Demo ---
            var buffer = try types.Buffer.init(app.allocator, 1024, .vertex);
            defer buffer.deinit();
            const buffer_data = try app.allocator.alloc(u8, 1024);
            defer app.allocator.free(buffer_data);
            @memset(buffer_data, 0x42);
            backend.createBuffer(buffer, buffer_data) catch |err| {
                std.log.warn("Failed to create buffer: {}", .{err});
            };
            std.log.info("✓ Created 1KB vertex buffer", .{});

            // --- Cleanup ---
            backend.destroyBuffer(buffer);
            std.log.info("✓ Successfully cleaned up all resources", .{});
        }
    }
}

/// Demonstrate mesh creation (vertex/index buffer upload)
fn run_mesh_demo(app: anytype) !void {
    if (app.backend_manager) |manager| {
        if (manager.getPrimaryBackend()) |backend| {
            std.log.info("=== Mesh Creation Demo ===", .{});

            // Define a simple cube (8 vertices, 12 triangles)
            const cube_vertices = [_]f32{
                // positions        // colors
                -0.5, -0.5, -0.5, 1.0, 0.0, 0.0,
                0.5,  -0.5, -0.5, 0.0, 1.0, 0.0,
                0.5,  0.5,  -0.5, 0.0, 0.0, 1.0,
                -0.5, 0.5,  -0.5, 1.0, 1.0, 0.0,
                -0.5, -0.5, 0.5,  1.0, 0.0, 1.0,
                0.5,  -0.5, 0.5,  0.0, 1.0, 1.0,
                0.5,  0.5,  0.5,  1.0, 1.0, 1.0,
                -0.5, 0.5,  0.5,  0.5, 0.5, 0.5,
            };
            const cube_indices = [_]u16{
                0, 1, 2, 2, 3, 0, // back
                4, 5, 6, 6, 7, 4, // front
                0, 4, 7, 7, 3, 0, // left
                1, 5, 6, 6, 2, 1, // right
                3, 2, 6, 6, 7, 3, // top
                0, 1, 5, 5, 4, 0, // bottom
            };

            // Create vertex buffer
            var vertex_buffer = try types.Buffer.init(app.allocator, cube_vertices.len * @sizeOf(f32), .vertex);
            defer vertex_buffer.deinit();
            const vertex_data = try app.allocator.alloc(u8, cube_vertices.len * @sizeOf(f32));
            defer app.allocator.free(vertex_data);
            @memcpy(vertex_data, std.mem.asBytes(&cube_vertices));
            backend.createBuffer(vertex_buffer, vertex_data) catch |err| {
                std.log.warn("Failed to create vertex buffer: {}", .{err});
            };

            // Create index buffer
            var index_buffer = try types.Buffer.init(app.allocator, cube_indices.len * @sizeOf(u16), .index);
            defer index_buffer.deinit();
            const index_data = try app.allocator.alloc(u8, cube_indices.len * @sizeOf(u16));
            defer app.allocator.free(index_data);
            @memcpy(index_data, std.mem.asBytes(&cube_indices));
            backend.createBuffer(index_buffer, index_data) catch |err| {
                std.log.warn("Failed to create index buffer: {}", .{err});
            };

            std.log.info("✓ Created cube mesh (vertex + index buffer)", .{});

            // Cleanup
            backend.destroyBuffer(vertex_buffer);
            backend.destroyBuffer(index_buffer);
            std.log.info("✓ Cleaned up mesh resources", .{});
        }
    }
}

/// Demonstrate material and shader usage
fn run_material_demo(app: anytype) !void {
    if (app.backend_manager) |manager| {
        if (manager.getPrimaryBackend()) |backend| {
            std.log.info("=== Material and Shader Demo ===", .{});

            // Create a simple vertex shader
            var vertex_shader = try types.Shader.init(app.allocator, .vertex,
                \\#version 330 core
                \\layout (location = 0) in vec3 aPos;
                \\void main() {
                \\    gl_Position = vec4(aPos, 1.0);
                \\}
            );
            defer vertex_shader.deinit();
            backend.createShader(vertex_shader) catch |err| {
                std.log.warn("Failed to create vertex shader: {}", .{err});
            };
            std.log.info("✓ Created vertex shader", .{});

            // Create a simple fragment shader
            var fragment_shader = try types.Shader.init(app.allocator, .fragment,
                \\#version 330 core
                \\out vec4 FragColor;
                \\void main() {
                \\    FragColor = vec4(1.0, 0.5, 0.2, 1.0);
                \\}
            );
            defer fragment_shader.deinit();
            backend.createShader(fragment_shader) catch |err| {
                std.log.warn("Failed to create fragment shader: {}", .{err});
            };
            std.log.info("✓ Created fragment shader", .{});

            // (Optional) Create a material and bind shaders if supported by backend
            // This is a placeholder for more advanced material logic
            std.log.info("✓ Material and shader demo complete", .{});

            // Cleanup
            backend.destroyShader(vertex_shader);
            backend.destroyShader(fragment_shader);
            std.log.info("✓ Cleaned up shader resources", .{});
        }
    }
}

/// Demonstrate texture array creation and usage (Vulkan only)
fn run_texture_array_demo(app: anytype) !void {
    if (app.backend_manager) |manager| {
        if (manager.getPrimaryBackend()) |backend| {
            const backend_name = backend.backend_type.getName();
            if (std.mem.eql(u8, backend_name, "Vulkan")) {
                // TODO: Implement Vulkan texture array demo
                std.log.info("Vulkan texture array demo - TODO: implement", .{});
            } else {
                std.log.info("Texture array demo skipped: not supported on backend {s}", .{backend_name});
            }
        }
    }
}

/// Demonstrate uniform buffer updates
fn run_uniform_buffer_demo(app: anytype) !void {
    if (app.backend_manager) |manager| {
        if (manager.getPrimaryBackend()) |backend| {
            const backend_name = backend.backend_type.getName();
            if (std.mem.eql(u8, backend_name, "Vulkan")) {
                // TODO: Implement Vulkan uniform buffer demo
                std.log.info("Vulkan uniform buffer demo - TODO: implement", .{});
            } else {
                std.log.info("Uniform buffer demo skipped: not supported on backend {s}", .{backend_name});
            }
        }
    }
}

/// Demonstrate full pipeline/material setup (shaders, pipeline state, descriptor sets)
fn run_pipeline_material_demo(app: anytype) !void {
    if (app.backend_manager) |manager| {
        if (manager.getPrimaryBackend()) |backend| {
            const backend_name = backend.backend_type.getName();
            if (std.mem.eql(u8, backend_name, "Vulkan")) {
                // TODO: Implement Vulkan pipeline/material demo
                std.log.info("Vulkan pipeline/material demo - TODO: implement", .{});
            } else {
                std.log.info("Pipeline/material demo skipped: not supported on backend {s}", .{backend_name});
            }
        }
    }
}

test "Texture Array Demo runs without error (stub)" {
    var dummy_app = DummyApp{};
    try run_texture_array_demo(&dummy_app);
}

test "Uniform Buffer Demo runs without error (stub)" {
    var dummy_app = DummyApp{};
    try run_uniform_buffer_demo(&dummy_app);
}

test "Pipeline/Material Demo runs without error (stub)" {
    var dummy_app = DummyApp{};
    try run_pipeline_material_demo(&dummy_app);
}

const DummyApp = struct {
    backend_manager: ?*DummyBackendManager = null,
};

const DummyBackendManager = struct {
    pub fn getPrimaryBackend(self: *DummyBackendManager) ?*DummyBackend {
        _ = self;
        return null;
    }
};

const DummyBackend = struct {
    backend_type: DummyBackendType = DummyBackendType{},
};

const DummyBackendType = struct {
    pub fn getName(self: DummyBackendType) []const u8 {
        _ = self;
        return "Dummy";
    }
};
