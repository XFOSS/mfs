const std = @import("std");
const math = @import("../../math/math.zig");
const graphics = @import("../../graphics/graphics.zig");
const render = @import("../../render/render.zig");
const bench = @import("../benchmarks.zig");
const platform = @import("../../platform/platform.zig");
const build_options = @import("build_options");

// Constants for benchmark scene setup
const MESH_COUNT = 1000;
const LIGHT_COUNT = 50;
const TEXTURE_SIZE = 512;

// Graphics device used for benchmarks
var gfx_device: ?*graphics.GraphicsDevice = null;
var benchmark_allocator: std.mem.Allocator = undefined;
var is_setup = false;

// Benchmark resources
const Resources = struct {
    meshes: []graphics.ResourceHandle,
    textures: []graphics.ResourceHandle,
    material: graphics.ResourceHandle,
    render_targets: []graphics.ResourceHandle,
    shader: graphics.ResourceHandle,

    fn deinit(self: *@This()) void {
        if (gfx_device) |device| {
            for (self.meshes) |mesh| device.destroyBuffer(mesh);
            for (self.textures) |texture| device.destroyTexture(texture);
            for (self.render_targets) |rt| device.destroyTexture(rt);
            device.destroyShader(self.shader);
        }

        benchmark_allocator.free(self.meshes);
        benchmark_allocator.free(self.textures);
        benchmark_allocator.free(self.render_targets);
    }
};

var benchmark_resources: ?Resources = null;

/// Initialize graphics device and resources for benchmarks
fn setupBenchmarks() !void {
    if (is_setup) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    benchmark_allocator = gpa.allocator();

    // Initialize platform window in headless mode if possible
    try platform.init(.{
        .headless = true,
        .width = 1280,
        .height = 720,
    });

    // Create graphics device
    gfx_device = try graphics.createDevice(.{
        .api = determineOptimalBackend(),
        .validation = false, // Disable validation for performance
        .allocator = benchmark_allocator,
    });

    // Create benchmark resources
    var resources = Resources{
        .meshes = try benchmark_allocator.alloc(graphics.ResourceHandle, MESH_COUNT),
        .textures = try benchmark_allocator.alloc(graphics.ResourceHandle, 10),
        .render_targets = try benchmark_allocator.alloc(graphics.ResourceHandle, 5),
        .material = undefined,
        .shader = undefined,
    };

    // Generate test data
    try generateTestMeshes(&resources);
    try generateTestTextures(&resources);
    try generateTestRenderTargets(&resources);

    // Create shader
    resources.shader = try gfx_device.?.createShaderProgram(.{
        .vertex = @embedFile("benchmark_shaders/basic.vert"),
        .fragment = @embedFile("benchmark_shaders/basic.frag"),
    });

    // Create material
    resources.material = try gfx_device.?.createMaterial(.{
        .shader = resources.shader,
        .textures = &[_]graphics.TextureBinding{
            .{ .slot = 0, .texture = resources.textures[0] },
            .{ .slot = 1, .texture = resources.textures[1] },
        },
    });

    benchmark_resources = resources;
    is_setup = true;
}

/// Clean up benchmark resources
fn teardownBenchmarks() void {
    if (benchmark_resources) |*resources| {
        resources.deinit();
        benchmark_resources = null;
    }

    if (gfx_device) |device| {
        device.deinit();
        gfx_device = null;
    }

    platform.deinit();
    is_setup = false;
}

/// Determine the optimal graphics backend for the current platform
fn determineOptimalBackend() graphics.Backend {
    // Use the most performant backend for each platform
    if (build_options.vulkan_available) {
        return .vulkan;
    } else if (build_options.d3d12_available) {
        return .d3d12;
    } else if (build_options.metal_available) {
        return .metal;
    } else {
        return .opengl;
    }
}

/// Generate test meshes for benchmarking
fn generateTestMeshes(resources: *Resources) !void {
    if (gfx_device) |device| {
        // Create a variety of test meshes with different complexities
        const vertex_layouts = [_]u32{ 100, 1000, 10000, 100000 };

        var i: usize = 0;
        while (i < MESH_COUNT) : (i += 1) {
            const vertex_count = vertex_layouts[i % vertex_layouts.len];
            const vertex_buffer_size = vertex_count * @sizeOf(math.Vertex);

            // Generate some procedural vertex data
            var vertices = try benchmark_allocator.alloc(math.Vertex, vertex_count);
            defer benchmark_allocator.free(vertices);

            // Fill with test data
            for (vertices, 0..) |*vertex, v| {
                const angle = @as(f32, @floatFromInt(v)) / @as(f32, @floatFromInt(vertex_count)) * std.math.tau;
                vertex.* = .{
                    .position = .{
                        .x = @cos(angle) * 5.0,
                        .y = @sin(angle) * 5.0,
                        .z = @sin(angle * 0.5) * 2.0,
                    },
                    .normal = .{ .x = 0, .y = 1, .z = 0 },
                    .texcoord = .{ .x = @cos(angle) * 0.5 + 0.5, .y = @sin(angle) * 0.5 + 0.5 },
                    .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
                };
            }

            // Create the mesh buffer
            resources.meshes[i] = try device.createBuffer(.{
                .size = vertex_buffer_size,
                .usage = .{ .vertex = true },
                .memory_flags = .{ .device_local = true },
                .initial_data = vertices,
            });
        }
    }
}

/// Generate test textures for benchmarking
fn generateTestTextures(resources: *Resources) !void {
    if (gfx_device) |device| {
        // Create a few test textures
        for (resources.textures, 0..) |*texture, i| {
            // Create texture data (simple procedural pattern)
            const texture_data = try benchmark_allocator.alloc(u32, TEXTURE_SIZE * TEXTURE_SIZE);
            defer benchmark_allocator.free(texture_data);

            // Fill with test pattern
            const pattern_type = i % 5;
            for (0..TEXTURE_SIZE) |y| {
                for (0..TEXTURE_SIZE) |x| {
                    const idx = y * TEXTURE_SIZE + x;
                    const u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(TEXTURE_SIZE));
                    const v = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(TEXTURE_SIZE));

                    var color: u32 = 0;
                    switch (pattern_type) {
                        0 => { // Checkerboard
                            const check_size = 32;
                            const cx = (x / check_size) % 2;
                            const cy = (y / check_size) % 2;
                            color = if ((cx + cy) % 2 == 0) 0xFFFFFFFF else 0xFF000000;
                        },
                        1 => { // Gradient
                            const r = @as(u8, @intFromFloat(u * 255));
                            const g = @as(u8, @intFromFloat(v * 255));
                            const b = @as(u8, @intFromFloat((1.0 - (u + v) * 0.5) * 255));
                            color = 0xFF000000 | (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
                        },
                        2 => { // Noise
                            const noise = @sin(u * 10) * @cos(v * 10);
                            const value = @as(u8, @intFromFloat((noise * 0.5 + 0.5) * 255));
                            color = 0xFF000000 | (@as(u32, value) << 16) | (@as(u32, value) << 8) | value;
                        },
                        3 => { // Concentric circles
                            const dx = u - 0.5;
                            const dy = v - 0.5;
                            const dist = @sqrt(dx * dx + dy * dy) * 20;
                            const ring = @sin(dist) * 0.5 + 0.5;
                            const value = @as(u8, @intFromFloat(ring * 255));
                            color = 0xFF000000 | (@as(u32, value) << 16) | (@as(u32, value) << 8) | value;
                        },
                        4 => { // Perlin-like pattern
                            const freq = 5.0;
                            const fx = @sin(u * freq) * @cos(v * freq * 0.5);
                            const fy = @sin(v * freq) * @cos(u * freq * 0.5);
                            const fz = @sin((u + v) * freq) * 0.5 + 0.5;
                            const r = @as(u8, @intFromFloat(fx * 127 + 128));
                            const g = @as(u8, @intFromFloat(fy * 127 + 128));
                            const b = @as(u8, @intFromFloat(fz * 255));
                            color = 0xFF000000 | (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
                        },
                        else => {},
                    }

                    texture_data[idx] = color;
                }
            }

            // Create the texture
            texture.* = try device.createTexture(.{
                .width = TEXTURE_SIZE,
                .height = TEXTURE_SIZE,
                .format = .rgba8_unorm,
                .usage = .{ .sampled = true },
                .initial_data = texture_data,
            });
        }
    }
}

/// Generate render targets for benchmarking
fn generateTestRenderTargets(resources: *Resources) !void {
    if (gfx_device) |device| {
        // Create render targets with different sizes and formats
        const rt_sizes = [_]u32{ 256, 512, 1024, 2048 };
        const rt_formats = [_]graphics.TextureFormat{
            .rgba8_unorm,
            .rgba16_float,
            .r32_float,
            .rgba32_float,
            .depth32_float,
        };

        for (resources.render_targets, 0..) |*rt, i| {
            const size = rt_sizes[i % rt_sizes.len];
            const format = rt_formats[i % rt_formats.len];

            rt.* = try device.createTexture(.{
                .width = size,
                .height = size,
                .format = format,
                .usage = .{ .render_target = true, .sampled = true },
            });
        }
    }
}

// ----- BENCHMARK FUNCTIONS -----

/// Benchmark basic drawing operations
fn benchmarkDrawing() void {
    if (!is_setup or gfx_device == null or benchmark_resources == null) return;

    const device = gfx_device.?;
    const resources = benchmark_resources.?;

    // Begin frame
    device.beginFrame() catch return;

    // Set render state
    device.setRenderTarget(resources.render_targets[0]);
    device.setViewport(0, 0, TEXTURE_SIZE, TEXTURE_SIZE);
    device.setScissor(0, 0, TEXTURE_SIZE, TEXTURE_SIZE);
    device.clear(.{ .color = true, .depth = true }, .{ 0.1, 0.2, 0.3, 1.0 }, 1.0);

    // Create a model-view-projection matrix
    const model = math.Mat4.identity()
        .rotate(math.Vec3.new(0, 1, 0), 0.1)
        .translate(math.Vec3.new(0, 0, -5));

    const view = math.Mat4.lookAt(
        math.Vec3.new(0, 0, 5),
        math.Vec3.new(0, 0, 0),
        math.Vec3.new(0, 1, 0),
    );

    const proj = math.Mat4.perspective(
        math.toRadians(60.0),
        1.0, // Aspect ratio
        0.1, // Near
        100.0, // Far
    );

    const mvp = proj.mul(view).mul(model);

    // Update uniform buffer with the MVP matrix
    device.updateUniformBuffer(0, &[_]f32{
        mvp.m[0][0], mvp.m[0][1], mvp.m[0][2], mvp.m[0][3],
        mvp.m[1][0], mvp.m[1][1], mvp.m[1][2], mvp.m[1][3],
        mvp.m[2][0], mvp.m[2][1], mvp.m[2][2], mvp.m[2][3],
        mvp.m[3][0], mvp.m[3][1], mvp.m[3][2], mvp.m[3][3],
    }) catch return;

    // Draw a subset of meshes
    device.bindMaterial(resources.material);

    const draw_count = std.math.min(100, resources.meshes.len);
    for (resources.meshes[0..draw_count], 0..) |mesh, i| {
        // Position each mesh differently
        const offset = @as(f32, @floatFromInt(i)) * 0.1;
        const model_mat = math.Mat4.identity()
            .translate(math.Vec3.new(offset, 0, 0))
            .rotate(math.Vec3.new(offset, 1, 0), offset * 2.0);

        // Update per-instance data
        device.updateUniformBuffer(1, &[_]f32{
            model_mat.m[0][0], model_mat.m[0][1], model_mat.m[0][2], model_mat.m[0][3],
            model_mat.m[1][0], model_mat.m[1][1], model_mat.m[1][2], model_mat.m[1][3],
            model_mat.m[2][0], model_mat.m[2][1], model_mat.m[2][2], model_mat.m[2][3],
            model_mat.m[3][0], model_mat.m[3][1], model_mat.m[3][2], model_mat.m[3][3],
        }) catch continue;

        // Draw the mesh
        device.bindVertexBuffer(0, mesh);
        device.draw(.{
            .vertex_count = 1000,
            .instance_count = 1,
        }) catch continue;
    }

    // End frame
    device.endFrame() catch return;
}

/// Benchmark texture operations
fn benchmarkTextureOperations() void {
    if (!is_setup or gfx_device == null or benchmark_resources == null) return;

    const device = gfx_device.?;
    const resources = benchmark_resources.?;

    // Begin frame
    device.beginFrame() catch return;

    // Create a temporary texture and fill it with data
    const temp_texture = device.createTexture(.{
        .width = 512,
        .height = 512,
        .format = .rgba8_unorm,
        .usage = .{ .transfer_src = true, .transfer_dst = true },
    }) catch return;

    // Generate some texture data
    var texture_data: [512 * 512]u32 = undefined;
    for (0..512) |y| {
        for (0..512) |x| {
            const idx = y * 512 + x;
            texture_data[idx] = 0xFF000000 |
                (@as(u32, @intCast(x & 0xFF)) << 16) |
                (@as(u32, @intCast(y & 0xFF)) << 8) |
                @as(u32, @intCast((x + y) & 0xFF));
        }
    }

    // Upload to the texture
    device.updateTexture(temp_texture, &texture_data) catch {};

    // Copy between textures
    device.copyTexture(temp_texture, resources.textures[0]) catch {};

    // Generate mipmaps
    device.generateMipmaps(resources.textures[1]) catch {};

    // Clean up
    device.destroyTexture(temp_texture) catch {};

    // End frame
    device.endFrame() catch return;
}

/// Benchmark render passes
fn benchmarkRenderPasses() void {
    if (!is_setup or gfx_device == null or benchmark_resources == null) return;

    const device = gfx_device.?;
    const resources = benchmark_resources.?;

    // Begin frame
    device.beginFrame() catch return;

    // Multiple render passes with different render targets
    for (resources.render_targets, 0..) |rt, i| {
        // Set render target
        device.setRenderTarget(rt);
        device.setViewport(0, 0, TEXTURE_SIZE, TEXTURE_SIZE);
        device.setScissor(0, 0, TEXTURE_SIZE, TEXTURE_SIZE);
        device.clear(.{ .color = true, .depth = true }, .{ 0.1, 0.2, 0.3, 1.0 }, 1.0);

        // Bind a different texture for each pass
        device.bindTexture(0, resources.textures[i % resources.textures.len]);

        // Draw a quad that covers the screen
        device.drawQuad() catch continue;
    }

    // Final composite pass
    device.setRenderTarget(null); // Default framebuffer
    device.setViewport(0, 0, 1280, 720);
    device.setScissor(0, 0, 1280, 720);
    device.clear(.{ .color = true }, .{ 0.0, 0.0, 0.0, 1.0 }, 1.0);

    // Draw each render target as a quad on screen
    for (resources.render_targets, 0..) |rt, i| {
        const x = @as(f32, @floatFromInt(i % 2)) * 0.5;
        const y = @as(f32, @floatFromInt(i / 2)) * 0.5;

        // Use the render target as a texture
        device.bindTexture(0, rt);

        // Draw a quad at the specified position
        device.drawQuadAt(.{
            .x = x,
            .y = y,
            .width = 0.5,
            .height = 0.5,
        }) catch continue;
    }

    // End frame
    device.endFrame() catch return;
}

// ----- PUBLIC INTERFACE -----

/// Run all renderer benchmarks
pub fn runRendererBenchmarks() !void {
    try setupBenchmarks();
    defer teardownBenchmarks();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var benchmarker = try bench.Benchmarker.init(.{
        .name = "MFS Renderer Benchmarks",
        .iterations = 1000,
        .warmup_iterations = 100,
        .output = .csv,
        .output_file = "renderer_benchmarks.csv",
        .allocator = allocator,
    });
    defer benchmarker.deinit();

    // Run renderer benchmarks
    try benchmarker.benchmark("Basic Drawing Operations", benchmarkDrawing);
    try benchmarker.benchmark("Texture Operations", benchmarkTextureOperations);
    try benchmarker.benchmark("Multiple Render Passes", benchmarkRenderPasses);

    // Save results
    try benchmarker.saveResults();
}

// ----- ENTRYPOINT -----

pub fn main() !void {
    std.debug.print("Running MFS Renderer Benchmarks\n", .{});
    try runRendererBenchmarks();
    std.debug.print("Benchmarks complete\n", .{});
}
