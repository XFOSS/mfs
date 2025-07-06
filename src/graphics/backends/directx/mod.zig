const std = @import("std");
const common = @import("../common.zig");
const interface = @import("../interface.zig");
const types = @import("../../types.zig");

pub const d3d11 = @import("d3d11_backend.zig");
pub const d3d12 = @import("d3d12_backend.zig");

/// Create a D3D11 backend instance
pub fn createD3D11(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    _ = config; // Config not used yet but may be in the future
    return d3d11.createBackend(allocator);
}

/// Create a D3D12 backend instance
pub fn createD3D12(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    _ = config; // Config not used yet but may be in the future
    return d3d12.D3D12Backend.createBackend(allocator);
}

test {
    _ = d3d11;
    _ = d3d12;
}

// DirectX 12 Cube Renderer for demo purposes
pub const D3D12CubeRenderer = struct {
    backend: *interface.GraphicsBackend,
    allocator: std.mem.Allocator,

    // Cube vertices and indices
    vertex_buffer: *types.Buffer,
    index_buffer: *types.Buffer,
    uniform_buffer: *types.Buffer,

    // Shader and pipeline
    vertex_shader: *types.Shader,
    fragment_shader: *types.Shader,
    pipeline: *interface.Pipeline,

    // Rotation state
    rotation: f32 = 0.0,

    const Self = @This();

    // Cube vertices (position + color)
    const vertices = [_]f32{
        // Front face
        -1.0, -1.0, 1.0, 1.0, 0.0, 0.0, 1.0, // Bottom-left  (red)
        1.0, -1.0, 1.0, 0.0, 1.0, 0.0, 1.0, // Bottom-right (green)
        1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, // Top-right    (blue)
        -1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, // Top-left     (yellow)

        // Back face
        -1.0, -1.0, -1.0, 1.0, 0.0, 1.0, 1.0, // Bottom-left  (magenta)
        1.0, -1.0, -1.0, 0.0, 1.0, 1.0, 1.0, // Bottom-right (cyan)
        1.0, 1.0, -1.0, 1.0, 1.0, 1.0, 1.0, // Top-right    (white)
        -1.0, 1.0, -1.0, 0.5, 0.5, 0.5, 1.0, // Top-left     (gray)
    };

    // Cube indices (triangles)
    const indices = [_]u32{
        // Front face
        0, 1, 2, 2, 3, 0,
        // Back face
        4, 5, 6, 6, 7, 4,
        // Left face
        7, 3, 0, 0, 4, 7,
        // Right face
        1, 5, 6, 6, 2, 1,
        // Top face
        3, 2, 6, 6, 7, 3,
        // Bottom face
        0, 1, 5, 5, 4, 0,
    };

    pub fn init(allocator: std.mem.Allocator, window_handle: ?*anyopaque, width: u32, height: u32) !Self {
        std.log.info("Initializing DirectX 12 Cube Renderer", .{});

        // Create D3D12 backend
        const backend = d3d12.D3D12Backend.createBackend(allocator) catch |err| {
            std.log.err("Failed to create DirectX 12 backend: {}", .{err});
            return err;
        };

        // Create swap chain
        const swap_chain_desc = interface.SwapChainDesc{
            .window_handle = window_handle,
            .width = width,
            .height = height,
            .buffer_count = 3,
            .format = .bgra8_unorm,
            .vsync = true,
        };

        backend.vtable.create_swap_chain(backend.impl_data, &swap_chain_desc) catch |err| {
            std.log.err("Failed to create swap chain: {}", .{err});
            return err;
        };

        // Create vertex buffer
        const vertex_buffer = try allocator.create(types.Buffer);
        vertex_buffer.* = types.Buffer.init(vertices.len * @sizeOf(f32), .vertex);

        const vertex_data = std.mem.sliceAsBytes(&vertices);
        backend.vtable.create_buffer(backend.impl_data, vertex_buffer, vertex_data) catch |err| {
            std.log.err("Failed to create vertex buffer: {}", .{err});
            return err;
        };

        // Create index buffer
        const index_buffer = try allocator.create(types.Buffer);
        index_buffer.* = types.Buffer.init(indices.len * @sizeOf(u32), .index);

        const index_data = std.mem.sliceAsBytes(&indices);
        backend.vtable.create_buffer(backend.impl_data, index_buffer, index_data) catch |err| {
            std.log.err("Failed to create index buffer: {}", .{err});
            return err;
        };

        // Create uniform buffer
        const uniform_buffer = try allocator.create(types.Buffer);
        uniform_buffer.* = types.Buffer.init(64, .uniform); // 4x4 matrix

        backend.vtable.create_buffer(backend.impl_data, uniform_buffer, null) catch |err| {
            std.log.err("Failed to create uniform buffer: {}", .{err});
            return err;
        };

        // Create shaders (HLSL for DirectX 12)
        const vertex_shader_source =
            \\cbuffer Transform : register(b0) {
            \\    float4x4 mvp;
            \\};
            \\
            \\struct VSInput {
            \\    float3 position : POSITION;
            \\    float4 color : COLOR;
            \\};
            \\
            \\struct VSOutput {
            \\    float4 position : SV_Position;
            \\    float4 color : COLOR;
            \\};
            \\
            \\VSOutput main(VSInput input) {
            \\    VSOutput output;
            \\    output.position = mul(float4(input.position, 1.0), mvp);
            \\    output.color = input.color;
            \\    return output;
            \\}
        ;

        const fragment_shader_source =
            \\struct PSInput {
            \\    float4 position : SV_Position;
            \\    float4 color : COLOR;
            \\};
            \\
            \\float4 main(PSInput input) : SV_Target {
            \\    return input.color;
            \\}
        ;

        const vertex_shader = try allocator.create(types.Shader);
        vertex_shader.* = types.Shader.init(.vertex, vertex_shader_source);

        backend.vtable.create_shader(backend.impl_data, vertex_shader) catch |err| {
            std.log.err("Failed to create vertex shader: {}", .{err});
            return err;
        };

        const fragment_shader = try allocator.create(types.Shader);
        fragment_shader.* = types.Shader.init(.fragment, fragment_shader_source);

        backend.vtable.create_shader(backend.impl_data, fragment_shader) catch |err| {
            std.log.err("Failed to create fragment shader: {}", .{err});
            return err;
        };

        // Create render pipeline
        const vertex_attributes = [_]interface.VertexAttribute{
            .{ .location = 0, .format = .float3, .offset = 0 }, // position
            .{ .location = 1, .format = .float4, .offset = 12 }, // color
        };

        const vertex_layout = interface.VertexLayout{
            .attributes = &vertex_attributes,
            .stride = 7 * @sizeOf(f32), // 3 floats for position + 4 floats for color
        };

        const pipeline_desc = interface.PipelineDesc{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .vertex_layout = vertex_layout,
            .primitive_topology = .triangles,
            .depth_stencil_state = .{
                .depth_test_enabled = true,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .rasterizer_state = .{
                .cull_mode = .back,
                .fill_mode = .solid,
            },
            .render_target_formats = &[_]types.TextureFormat{.bgra8_unorm},
            .depth_format = .depth32f,
        };

        const pipeline = backend.vtable.create_pipeline(backend.impl_data, &pipeline_desc) catch |err| {
            std.log.err("Failed to create pipeline: {}", .{err});
            return err;
        };

        std.log.info("DirectX 12 Cube Renderer initialized successfully", .{});

        return Self{
            .backend = backend,
            .allocator = allocator,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .uniform_buffer = uniform_buffer,
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: *Self) void {
        self.backend.vtable.destroy_buffer(self.backend.impl_data, self.vertex_buffer);
        self.backend.vtable.destroy_buffer(self.backend.impl_data, self.index_buffer);
        self.backend.vtable.destroy_buffer(self.backend.impl_data, self.uniform_buffer);
        self.backend.vtable.destroy_shader(self.backend.impl_data, self.vertex_shader);
        self.backend.vtable.destroy_shader(self.backend.impl_data, self.fragment_shader);

        self.allocator.destroy(self.vertex_buffer);
        self.allocator.destroy(self.index_buffer);
        self.allocator.destroy(self.uniform_buffer);
        self.allocator.destroy(self.vertex_shader);
        self.allocator.destroy(self.fragment_shader);

        self.backend.vtable.deinit(self.backend.impl_data);
        self.allocator.destroy(self.backend);
    }

    pub fn render(self: *Self, delta_time: f32) !void {
        // Update rotation
        self.rotation += delta_time * 90.0; // 90 degrees per second
        if (self.rotation > 360.0) {
            self.rotation -= 360.0;
        }

        // Create transformation matrix (Model-View-Projection)
        const cos_y = @cos(self.rotation * std.math.pi / 180.0);
        const sin_y = @sin(self.rotation * std.math.pi / 180.0);
        const cos_x = @cos(self.rotation * 0.7 * std.math.pi / 180.0);
        const sin_x = @sin(self.rotation * 0.7 * std.math.pi / 180.0);

        // Perspective projection matrix
        const fov = 45.0 * std.math.pi / 180.0;
        const aspect = 1280.0 / 720.0;
        const near = 0.1;
        const far = 100.0;
        const f = 1.0 / @tan(fov / 2.0);

        // Combined model-view-projection matrix
        const mvp_matrix = [_]f32{
            f / aspect * cos_y, f / aspect * sin_y * sin_x, f / aspect * sin_y * cos_x,   0.0,
            0.0,                f * cos_x,                  -f * sin_x,                   0.0,
            -sin_y,             cos_y * sin_x,              cos_y * cos_x,                -5.0,
            0.0,                0.0,                        -(far + near) / (far - near), -2.0 * far * near / (far - near),
        };

        // Update uniform buffer
        const mvp_data = std.mem.sliceAsBytes(&mvp_matrix);
        try self.backend.vtable.update_buffer(self.backend.impl_data, self.uniform_buffer, 0, mvp_data);

        // Get command buffer
        const cmd = try self.backend.vtable.create_command_buffer(self.backend.impl_data);
        try self.backend.vtable.begin_command_buffer(self.backend.impl_data, cmd);

        // Begin render pass
        const back_buffer = try self.backend.vtable.get_current_back_buffer(self.backend.impl_data);
        const color_attachment = types.ColorAttachment{
            .texture = back_buffer,
            .clear_color = .{ 0.1, 0.1, 0.2, 1.0 },
            .load_op = .clear,
            .store_op = .store,
        };

        const render_pass_desc = types.RenderPassDesc{
            .color_attachments = &[_]types.ColorAttachment{color_attachment},
            .depth_attachment = null,
        };

        try self.backend.vtable.begin_render_pass(self.backend.impl_data, cmd, &render_pass_desc);

        // Set viewport
        const viewport = types.Viewport{
            .x = 0,
            .y = 0,
            .width = 1280,
            .height = 720,
            .min_depth = 0.0,
            .max_depth = 1.0,
        };
        try self.backend.vtable.set_viewport(self.backend.impl_data, cmd, &viewport);

        // Set pipeline and buffers
        try self.backend.vtable.bind_pipeline(self.backend.impl_data, cmd, self.pipeline);
        try self.backend.vtable.bind_vertex_buffer(self.backend.impl_data, cmd, 0, self.vertex_buffer, 0);
        try self.backend.vtable.bind_index_buffer(self.backend.impl_data, cmd, self.index_buffer, 0, .uint32);
        try self.backend.vtable.bind_uniform_buffer(self.backend.impl_data, cmd, 0, self.uniform_buffer, 0, 64);

        // Draw the cube
        const draw_cmd = types.DrawIndexedCommand{
            .index_count = indices.len,
            .instance_count = 1,
            .first_index = 0,
            .vertex_offset = 0,
            .first_instance = 0,
        };
        try self.backend.vtable.draw_indexed(self.backend.impl_data, cmd, &draw_cmd);

        // End render pass and command buffer
        try self.backend.vtable.end_render_pass(self.backend.impl_data, cmd);
        try self.backend.vtable.end_command_buffer(self.backend.impl_data, cmd);

        // Submit and present
        try self.backend.vtable.submit_command_buffer(self.backend.impl_data, cmd);
        try self.backend.vtable.present(self.backend.impl_data);
    }

    pub fn resize(self: *Self, width: u32, height: u32) !void {
        try self.backend.vtable.resize_swap_chain(self.backend.impl_data, width, height);
    }
};
