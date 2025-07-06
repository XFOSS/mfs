const std = @import("std");
const common = @import("../common.zig");
const interface = @import("../interface.zig");

pub const webgpu = @import("webgpu_backend.zig");

/// Create a WebGPU backend instance
pub fn create(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    _ = config; // Config not used yet but may be in the future
    return webgpu.createBackend(allocator);
}

/// Create a WebGPU backend instance (alternative name for compatibility)
pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
    const config = interface.BackendConfig{
        .backend_type = .webgpu,
    };
    return create(allocator, config);
}

test {
    _ = webgpu;
}
