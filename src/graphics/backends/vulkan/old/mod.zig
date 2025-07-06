const std = @import("std");
const common = @import("../common.zig");
const interface = @import("../interface.zig");
pub const vk = @import("vk.zig");
const dispatch = @import("vulkan_dispatch.zig");

// Main vulkan backend implementation
pub const vulkan_backend = @import("vulkan_backend.zig");
pub const VulkanBackend = vulkan_backend.VulkanBackend;

// Core vulkan support modules
pub const shader_loader = @import("shader_loader.zig");

// Vulkan demo renderers
pub const cube = @import("cube.zig");
pub const VulkanCubeRenderer = cube.VulkanCubeRenderer;

// Ray tracing support
pub const ray_tracing = @import("ray_tracing.zig");

// Re-export key types and functions
pub const create = vulkan_backend.VulkanBackend.create;
pub const getInfo = vulkan_backend.VulkanBackend.getInfo;
pub const vtable = vulkan_backend.VulkanBackend.vtable;

/// Create a Vulkan backend instance
pub fn createBackend(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    return vulkan_backend.VulkanBackend.create(allocator, config);
}

/// Check if Vulkan is available on this system by attempting to load the Vulkan loader
/// and checking for required instance extensions
pub fn isAvailable() bool {
    // Try to load Vulkan loader
    if (dispatch.loadVulkanLibrary()) |_| {
        // Check for required instance extensions
        var extension_count: u32 = undefined;
        if (vk.vkEnumerateInstanceExtensionProperties(null, &extension_count, null) != .VK_SUCCESS) {
            return false;
        }

        // Allocate temporary arena for extension properties
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const extensions = allocator.alloc(vk.VkExtensionProperties, extension_count) catch return false;
        defer allocator.free(extensions);

        if (vk.vkEnumerateInstanceExtensionProperties(null, &extension_count, extensions.ptr) != .VK_SUCCESS) {
            return false;
        }

        // Check for required extensions (surface and platform-specific extensions)
        const required_extensions = [_][]const u8{
            "VK_KHR_surface",
            switch (@import("builtin").os.tag) {
                .windows => "VK_KHR_win32_surface",
                .linux => "VK_KHR_xlib_surface",
                .macos => "VK_MVK_macos_surface",
                else => return false,
            },
        };

        extension_check: for (required_extensions) |required| {
            for (extensions) |ext| {
                const ext_name = std.mem.sliceTo(&ext.extensionName, 0);
                if (std.mem.eql(u8, required, ext_name)) {
                    continue :extension_check;
                }
            }
            return false; // Required extension not found
        }

        return true;
    } else |_| {
        return false;
    }
}

test "vulkan backend" {
    _ = vulkan_backend;
    _ = VulkanBackend;
}
