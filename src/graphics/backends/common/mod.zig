//! MFS Engine - Graphics Backends Common Module
//! Common utilities and helpers shared across all graphics backends
//! Provides memory management, error handling, profiling, and resource utilities
//! @thread-safe Most utilities are thread-safe unless noted otherwise
//! @performance Optimized for backend-agnostic operations

// Re-export the main common module
pub const common = @import("common.zig");

// Additional exports for convenience
pub const BackendError = @import("errors.zig").GraphicsError;
pub const BackendCapabilities = struct {
    supports_ray_tracing: bool = false,
    supports_mesh_shaders: bool = false,
    supports_compute_shaders: bool = true,
    supports_geometry_shaders: bool = true,
    supports_tessellation: bool = true,
    max_texture_size: u32 = 4096,
    max_render_targets: u32 = 8,
    max_vertex_attributes: u32 = 16,
    max_uniform_buffer_bindings: u32 = 16,
    max_texture_bindings: u32 = 32,

    pub fn init() BackendCapabilities {
        return BackendCapabilities{};
    }
};

pub const BackendInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    available: bool,
    capabilities: BackendCapabilities,

    pub fn unavailable(name: []const u8) BackendInfo {
        return BackendInfo{
            .name = name,
            .version = "N/A",
            .description = "Backend not available on this platform",
            .available = false,
            .capabilities = BackendCapabilities.init(),
        };
    }

    pub fn auto() BackendInfo {
        return BackendInfo{
            .name = "Auto",
            .version = "1.0",
            .description = "Automatic backend selection",
            .available = true,
            .capabilities = BackendCapabilities.init(),
        };
    }
};

// Test all common modules
test "common module" {
    @import("std").testing.refAllDecls(@This());
}
