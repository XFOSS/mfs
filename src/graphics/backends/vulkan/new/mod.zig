//! MFS Engine - New Vulkan Backend Module
//! Modern Vulkan 1.3 implementation with improved memory management and features

const std = @import("std");
const common = @import("../../common.zig");
const interface = @import("../../interface.zig");

// Main Vulkan backend implementation
pub const VulkanBackend = @import("vulkan_backend.zig").VulkanBackend;

// Re-export key types and functions for compatibility
pub const create = VulkanBackend.create;
pub const getInfo = VulkanBackend.getInfo;

/// Create a Vulkan backend instance
pub fn createBackend(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    return VulkanBackend.create(allocator, config);
}

/// Check if Vulkan is available on this system
pub fn isAvailable() bool {
    // TODO: Implement proper availability check
    // For now, assume available if Vulkan package is present
    return @import("builtin").zig_version.minor >= 12; // Rough approximation
}

test "vulkan backend" {
    _ = VulkanBackend;
}
