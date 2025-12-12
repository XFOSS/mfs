//! Legacy stub: forward to Vulkan vk.zig
const vk_mod = @import("../../backends/vulkan/old/vk.zig");

// Re-export key types
pub const Device = vk_mod.Device;
pub const PhysicalDevice = vk_mod.PhysicalDevice;
pub const Instance = vk_mod.Instance;
pub const Buffer = vk_mod.Buffer;
pub const DeviceMemory = vk_mod.DeviceMemory;
pub const MemoryRequirements = vk_mod.MemoryRequirements;
pub const MemoryAllocateInfo = vk_mod.MemoryAllocateInfo;
pub const PhysicalDeviceMemoryProperties = vk_mod.PhysicalDeviceMemoryProperties;
pub const MemoryPropertyFlags = vk_mod.MemoryPropertyFlags;
pub const VkDeviceSize = vk_mod.VkDeviceSize;
