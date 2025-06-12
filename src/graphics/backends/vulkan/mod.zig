const common = @import("../common.zig");
const interface = @import("../interface.zig");

// Main vulkan backend implementation
pub const vulkan = @import("vulkan_backend.zig");
// Core vulkan support modules
pub const dispatch = @import("vulkan_dispatch.zig");
pub const vk = @import("vk.zig");
pub const shader_loader = @import("shader_loader.zig");

// Re-export types
pub usingnamespace @import("vulkan_backend.zig");

test {
    _ = vulkan;
}
