const std = @import("std");
const Allocator = std.mem.Allocator;
const vulkan_backend = @import("vulkan_backend.zig");

// Default vertex shader SPIR-V code (pre-compiled)
// This is a simple shader that transforms vertices and passes color to fragment shader
pub const DEFAULT_VERTEX_SHADER = [_]u32{ 0x07230203, 0x00010000, 0x000d000a, 0x0000002e, 0x00000000, 0x00020011, 0x00000001, 0x0006000b, 0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000, 0x0003000e, 0x00000000, 0x00000001, 0x000a000f, 0x00000000, 0x00000004, 0x6e69616d, 0x00000000, 0x0000000b, 0x0000000f, 0x00000015, 0x0000001b, 0x00000021, 0x00030003, 0x00000002, 0x000001c2, 0x00040005, 0x00000004, 0x6e69616d, 0x00000000, 0x00060005, 0x00000009, 0x74756f5f, 0x6f6c6f43, 0x656d7261, 0x00000000, 0x00030005, 0x0000000b, 0x006f6c67, 0x00060005, 0x0000000f, 0x505f6c67, 0x65567265, 0x78657472, 0x00000000, 0x00060005, 0x00000015, 0x505f6c67, 0x7469736f, 0x006e6f69, 0x00000000, 0x00060005, 0x0000001b, 0x6f6c6f43, 0x69740072, 0x636e6e6f, 0x00000000, 0x00050005, 0x00000021, 0x6f506e69, 0x69746973, 0x00006e6f, 0x00050048, 0x00000007, 0x00000000, 0x0000000b, 0x00000000, 0x00030047, 0x00000007, 0x00000002, 0x00040048, 0x00000009, 0x00000000, 0x00000000, 0x00050048, 0x00000009, 0x00000000, 0x00000023, 0x00000000, 0x00030047, 0x00000009, 0x00000002, 0x00040047, 0x0000000f, 0x0000000b, 0x0000000f, 0x00040047, 0x00000015, 0x0000000b, 0x00000000, 0x00040047, 0x0000001b, 0x0000001e, 0x00000000, 0x00040047, 0x00000021, 0x0000001e, 0x00000000, 0x00020013, 0x00000002, 0x00030021, 0x00000003, 0x00000002, 0x00030016, 0x00000006, 0x00000020, 0x00040017, 0x00000007, 0x00000006, 0x00000004, 0x00040020, 0x00000008, 0x00000003, 0x00000007, 0x0004003b, 0x00000008, 0x00000009, 0x00000003, 0x00040017, 0x0000000a, 0x00000006, 0x00000004, 0x00040020, 0x0000000c, 0x00000001, 0x0000000a, 0x0004003b, 0x0000000c, 0x0000000b, 0x00000001, 0x00040020, 0x0000000e, 0x00000003, 0x0000000a, 0x0004003b, 0x0000000e, 0x0000000f, 0x00000003, 0x00040020, 0x00000014, 0x00000003, 0x0000000a, 0x0004003b, 0x00000014, 0x00000015, 0x00000003, 0x00040020, 0x0000001a, 0x00000001, 0x00000007, 0x0004003b, 0x0000001a, 0x0000001b, 0x00000001, 0x00040020, 0x00000020, 0x00000001, 0x0000000a, 0x0004003b, 0x00000020, 0x00000021, 0x00000001, 0x00050036, 0x00000002, 0x00000004, 0x00000000, 0x00000003, 0x000200f8, 0x00000005, 0x0004003d, 0x00000007, 0x0000001c, 0x0000001b, 0x0003003e, 0x00000009, 0x0000001c, 0x0004003d, 0x0000000a, 0x00000022, 0x00000021, 0x0003003e, 0x0000000f, 0x00000022, 0x0004003d, 0x0000000a, 0x00000023, 0x00000021, 0x0003003e, 0x00000015, 0x00000023, 0x000100fd, 0x00010038 };

// Default fragment shader SPIR-V code (pre-compiled)
// This is a simple shader that outputs the interpolated color
pub const DEFAULT_FRAGMENT_SHADER = [_]u32{ 0x07230203, 0x00010000, 0x000d000a, 0x00000014, 0x00000000, 0x00020011, 0x00000001, 0x0006000b, 0x00000001, 0x4c534c47, 0x6474732e, 0x3035342e, 0x00000000, 0x0003000e, 0x00000000, 0x00000001, 0x0007000f, 0x00000004, 0x00000004, 0x6e69616d, 0x00000000, 0x00000009, 0x0000000c, 0x00030010, 0x00000004, 0x00000007, 0x00030003, 0x00000002, 0x000001c2, 0x00040005, 0x00000004, 0x6e69616d, 0x00000000, 0x00050005, 0x00000009, 0x4f747561, 0x6f6c6f43, 0x00000072, 0x00050005, 0x0000000c, 0x6f6c6f43, 0x69740072, 0x0000006e, 0x00040047, 0x00000009, 0x0000001e, 0x00000000, 0x00040047, 0x0000000c, 0x0000001e, 0x00000000, 0x00020013, 0x00000002, 0x00030021, 0x00000003, 0x00000002, 0x00030016, 0x00000006, 0x00000020, 0x00040017, 0x00000007, 0x00000006, 0x00000004, 0x00040020, 0x00000008, 0x00000003, 0x00000007, 0x0004003b, 0x00000008, 0x00000009, 0x00000003, 0x00040020, 0x0000000b, 0x00000001, 0x00000007, 0x0004003b, 0x0000000b, 0x0000000c, 0x00000001, 0x00050036, 0x00000002, 0x00000004, 0x00000000, 0x00000003, 0x000200f8, 0x00000005, 0x0004003d, 0x00000007, 0x0000000d, 0x0000000c, 0x0003003e, 0x00000009, 0x0000000d, 0x000100fd, 0x00010038 };

// Vertex layout structure used by the shader
pub const Vertex = struct {
    position: [2]f32, // 2D position (x, y)
    color: [4]f32, // RGBA color
    uv: [2]f32, // Texture coordinates

    pub fn getBindingDescription() vulkan_backend.VertexInputBindingDescription {
        return vulkan_backend.VertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = 0, // VK_VERTEX_INPUT_RATE_VERTEX
        };
    }

    pub fn getAttributeDescriptions() [3]vulkan_backend.VertexInputAttributeDescription {
        return [_]vulkan_backend.VertexInputAttributeDescription{
            // Position attribute
            .{
                .binding = 0,
                .location = 0,
                .format = 103, // VK_FORMAT_R32G32_SFLOAT
                .offset = @offsetOf(Vertex, "position"),
            },
            // Color attribute
            .{
                .binding = 0,
                .location = 1,
                .format = 109, // VK_FORMAT_R32G32B32A32_SFLOAT
                .offset = @offsetOf(Vertex, "color"),
            },
            // UV attribute
            .{
                .binding = 0,
                .location = 2,
                .format = 103, // VK_FORMAT_R32G32_SFLOAT
                .offset = @offsetOf(Vertex, "uv"),
            },
        };
    }
};

// Structure to hold shader data
pub const ShaderModule = struct {
    vertex_shader: u64, // VkShaderModule handle
    fragment_shader: u64,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, device: *anyopaque, vertex_code: []const u32, fragment_code: []const u32) !Self {
        _ = device; // Placeholder until Vulkan API is implemented
        _ = vertex_code;
        _ = fragment_code;

        return Self{
            .vertex_shader = 0,
            .fragment_shader = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self, device: *anyopaque) void {
        _ = device; // Placeholder until Vulkan API is implemented
        _ = self;

        // In a real implementation:
        // vkDestroyShaderModule(device, self.vertex_shader, null);
        // vkDestroyShaderModule(device, self.fragment_shader, null);
    }
};

// Utility function to create shader modules for UI rendering
pub fn createDefaultShaders(allocator: Allocator, device: *anyopaque) !ShaderModule {
    return ShaderModule.init(allocator, device, &DEFAULT_VERTEX_SHADER, &DEFAULT_FRAGMENT_SHADER);
}

// Primitive pipeline creation helper
pub fn createGraphicsPipeline(
    device: *anyopaque,
    render_pass: u64,
    pipeline_layout: u64,
    shader_modules: *const ShaderModule,
    width: u32,
    height: u32,
) !u64 {
    _ = device;
    _ = render_pass;
    _ = pipeline_layout;
    _ = shader_modules;
    _ = width;
    _ = height;

    // In real implementation, this would create the Vulkan graphics pipeline
    return 0;
}
