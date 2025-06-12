const std = @import("std");

/// Stub implementation of a Vulkan-based cube renderer. This placeholder allows
/// the engine to compile even on platforms where a fully-featured Vulkan sample
/// has not yet been ported. All functions are no-ops that succeed immediately.
///
/// Once a proper renderer is available this file can be replaced.
pub const VulkanCubeRenderer = struct {
    allocator: std.mem.Allocator,

    /// Create a new stub renderer that owns no GPU resources.
    pub fn init(allocator: std.mem.Allocator) VulkanCubeRenderer {
        return VulkanCubeRenderer{ .allocator = allocator };
    }

    /// Destroy resources (no-op for stub).
    pub fn deinit(self: *VulkanCubeRenderer) void {
        _ = self;
    }

    /// Draw a frame (no-op for stub).
    pub fn render(self: *VulkanCubeRenderer) !void {
        _ = self;
        return;
    }

    /// Handle window resize (no-op for stub).
    pub fn resize(self: *VulkanCubeRenderer, width: u32, height: u32) !void {
        _ = self;
        _ = width;
        _ = height;
        return;
    }
};
