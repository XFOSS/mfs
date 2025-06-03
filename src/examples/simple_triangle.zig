const std = @import("std");

const interface = @import("../graphics/backends/interface.zig");
const buffer = @import("../graphics/buffer.zig");
const gpu = @import("../graphics/gpu.zig");
const shader = @import("../graphics/shader.zig");
const types = @import("../graphics/types.zig");

pub const Example = struct {
    allocator: std.mem.Allocator,
    window_width: u32,
    window_height: u32,
    shader_program: ?*shader.ShaderProgram = null,
    vertex_buffer: ?*buffer.VertexBuffer = null,
    uniform_buffer: ?*buffer.UniformBuffer = null,
    command_buffer: ?gpu.CommandBuffer = null,
    time: f32 = 0.0,

    const Vertex = struct {
        position: [2]f32,
        color: [3]f32,
    };

    const UniformData = struct {
        time: f32,
        resolution: [2]f32,
        padding: f32 = 0.0, // For alignment
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*Self {
        var example = try allocator.create(Self);
        example.* = Self{
            .allocator = allocator,
            .window_width = width,
            .window_height = height,
        };

        try example.initGpu();
        try example.createResources();

        return example;
    }

    fn initGpu(self: *Self) !void {
        // Initialize GPU with preferred backend
        const options = .{
            .preferred_backend = .vulkan,
            .auto_fallback = true,
            .debug_mode = true,
            .validate_backends = true,
            .enable_backend_switching = true,
        };

        try gpu.init(self.allocator, options);

        // Print backend information
        const info = gpu.getBackendInfo();
        std.debug.print("Using backend: {s} {s} on {s}\n", .{ info.name, info.version, info.device_name });
    }

    fn createResources(self: *Self) !void {
        // Create vertex buffer with triangle data
        const vertices = [_]Vertex{
            .{ .position = .{ -0.5, -0.5 }, .color = .{ 1.0, 0.0, 0.0 } }, // Bottom left, red
            .{ .position = .{ 0.5, -0.5 }, .color = .{ 0.0, 1.0, 0.0 } }, // Bottom right, green
            .{ .position = .{ 0.0, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } }, // Top, blue
        };

        self.vertex_buffer = try buffer.VertexBuffer.initWithData(self.allocator, std.mem.sliceAsBytes(&vertices), @sizeOf(Vertex), .gpu_only);

        // Set vertex layout
        self.vertex_buffer.?.setLayout(.{
            .attributes = &[_]interface.VertexAttribute{
                .{ .location = 0, .format = .float2, .offset = @offsetOf(Vertex, "position") },
                .{ .location = 1, .format = .float3, .offset = @offsetOf(Vertex, "color") },
            },
            .stride = @sizeOf(Vertex),
        });

        // Create uniform buffer
        self.uniform_buffer = try buffer.UniformBuffer.init(self.allocator, @sizeOf(UniformData), 0 // binding slot 0
        );

        // Create shader program
        self.shader_program = try shader.ShaderProgram.init(self.allocator);

        // Add vertex shader
        const vertex_shader_source =
            \\#version 450
            \\layout(location = 0) in vec2 inPosition;
            \\layout(location = 1) in vec3 inColor;
            \\layout(location = 0) out vec3 fragColor;
            \\layout(binding = 0) uniform UniformBlock {
            \\    float time;
            \\    vec2 resolution;
            \\} ubo;
            \\
            \\void main() {
            \\    float scale = sin(ubo.time * 0.5) * 0.5 + 0.5;
            \\    gl_Position = vec4(inPosition * scale, 0.0, 1.0);
            \\    fragColor = inColor;
            \\}
        ;

        try self.shader_program.?.addShader(.vertex, vertex_shader_source);

        // Add fragment shader
        const fragment_shader_source =
            \\#version 450
            \\layout(location = 0) in vec3 fragColor;
            \\layout(location = 0) out vec4 outColor;
            \\layout(binding = 0) uniform UniformBlock {
            \\    float time;
            \\    vec2 resolution;
            \\} ubo;
            \\
            \\void main() {
            \\    outColor = vec4(fragColor, 1.0);
            \\}
        ;

        try self.shader_program.?.addShader(.fragment, fragment_shader_source);

        // Create the pipeline
        try self.shader_program.?.createPipeline(.{
            .vertex_layout = self.vertex_buffer.?.layout,
        });

        // Create a command buffer
        const cmd = try gpu.createCommandBuffer();
        self.command_buffer = cmd;
    }

    pub fn deinit(self: *Self) void {
        if (self.shader_program) |program| {
            program.deinit();
        }

        if (self.vertex_buffer) |vb| {
            vb.deinit();
        }

        if (self.uniform_buffer) |ub| {
            ub.deinit();
        }

        gpu.deinit();

        self.allocator.destroy(self);
    }

    pub fn render(self: *Self, delta_time: f32) !void {
        // Update time
        self.time += delta_time;

        // Update uniform buffer
        const uniform_data = UniformData{
            .time = self.time,
            .resolution = .{ @floatFromInt(self.window_width), @floatFromInt(self.window_height) },
        };

        try self.uniform_buffer.?.updateTyped(uniform_data);

        // Get current back buffer
        const back_buffer = try gpu.getCurrentBackBuffer();

        // Begin command buffer
        try gpu.beginCommandBuffer(&self.command_buffer.?);

        // Begin render pass
        try gpu.beginRenderPass(&self.command_buffer.?, .{
            .color_targets = &[_]*gpu.Texture{back_buffer},
            .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.1, .a = 1.0 },
            .clear_depth = 1.0,
        });

        // Set viewport
        const viewport = gpu.Viewport{
            .x = 0,
            .y = 0,
            .width = self.window_width,
            .height = self.window_height,
        };

        try gpu.setViewport(&self.command_buffer.?, &viewport);
        try gpu.setScissor(&self.command_buffer.?, &viewport);

        // Bind pipeline
        try self.shader_program.?.bind(&self.command_buffer.?);

        // Bind vertex buffer
        try self.vertex_buffer.?.bind(&self.command_buffer.?, 0);

        // Bind uniform buffer
        try self.uniform_buffer.?.bind(&self.command_buffer.?);

        // Draw
        try self.vertex_buffer.?.draw(&self.command_buffer.?);

        // End render pass
        try gpu.endRenderPass(&self.command_buffer.?);

        // End command buffer
        try gpu.endCommandBuffer(&self.command_buffer.?);

        // Submit command buffer
        try gpu.submitCommandBuffer(&self.command_buffer.?);

        // Present
        try gpu.present();
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        if (width == self.window_width and height == self.window_height) {
            return;
        }

        self.window_width = width;
        self.window_height = height;

        gpu.resizeSwapChain(width, height) catch |err| {
            std.debug.print("Failed to resize swap chain: {}\n", .{err});
        };
    }
};

pub fn main() !void {
    // Set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create example
    const example = try Example.init(allocator, 800, 600);
    defer example.deinit();

    // In a real application, we'd integrate with a window system here
    // For demonstration, just do a few frames
    var frame: u32 = 0;
    const total_frames = 60;
    const delta_time = 1.0 / 60.0;

    while (frame < total_frames) : (frame += 1) {
        try example.render(delta_time);
    }
}
