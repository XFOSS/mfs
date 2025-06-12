const std = @import("std");
const vk = @import("vulkan");

// Move content from fixed_vulkan.zig
pub const FixedVulkanContext = struct {
    // ... existing code from fixed_vulkan.zig ...
};

pub fn createFixedVulkanContext(allocator: std.mem.Allocator) !*FixedVulkanContext {
    const context = try allocator.create(FixedVulkanContext);
    errdefer allocator.destroy(context);

    context.* = FixedVulkanContext{
        .allocator = allocator,
        // ... initialize other fields ...
    };

    return context;
}

// ... rest of existing code ...
