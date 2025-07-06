const std = @import("std");
const common = @import("../common.zig");
const interface = @import("../interface.zig");
const types = @import("../../types.zig");

// DirectX backends temporarily disabled due to C import issues
pub const d3d11 = struct {};
pub const d3d12 = struct {};

/// Create a D3D11 backend instance
pub fn createD3D11(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    _ = allocator;
    _ = config;
    return error.DirectXNotAvailable;
}

/// Create a D3D12 backend instance
pub fn createD3D12(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    _ = allocator;
    _ = config;
    return error.DirectXNotAvailable;
}

test {
    _ = d3d11;
    _ = d3d12;
}

// DirectX 12 Cube Renderer for demo purposes - temporarily disabled
pub const D3D12CubeRenderer = struct {
    pub fn init(allocator: std.mem.Allocator, window_handle: ?*anyopaque, width: u32, height: u32) !@This() {
        _ = allocator;
        _ = window_handle;
        _ = width;
        _ = height;
        return error.DirectXNotAvailable;
    }
};
