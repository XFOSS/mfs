const std = @import("std");
const Allocator = std.mem.Allocator;
const graphics_types = @import("graphics/types.zig");

// Re-export graphics types for convenience
pub const Texture = graphics_types.Texture;
pub const Shader = graphics_types.Shader;
pub const Buffer = graphics_types.Buffer;
pub const RenderTarget = graphics_types.RenderTarget;
pub const TextureFormat = graphics_types.TextureFormat;
pub const ShaderType = graphics_types.ShaderType;
pub const BufferUsage = graphics_types.BufferUsage;
pub const GraphicsError = graphics_types.GraphicsError;

pub const GpuConfig = struct {
    enable_validation: bool = false,
    preferred_device_type: DeviceType = .discrete,
    enable_debug_layers: bool = false,
};

pub const DeviceType = enum {
    discrete,
    integrated,
    virtual,
    cpu,
};

pub const Gpu = struct {
    allocator: Allocator,
    config: GpuConfig,
    initialized: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, config: GpuConfig) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .initialized = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.initialized = false;
    }

    pub fn isSupported() bool {
        return true; // Stub implementation
    }
};
