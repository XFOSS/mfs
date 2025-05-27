const std = @import("std");

// Vulkan C bindings for Windows - following bare-metal recipe
pub const c = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_win32.h");
});

// Re-export commonly used Vulkan types for convenience
pub const VkResult = c.VkResult;
pub const VkInstance = c.VkInstance;
pub const VkDevice = c.VkDevice;
pub const VkPhysicalDevice = c.VkPhysicalDevice;
pub const VkQueue = c.VkQueue;
pub const VkCommandPool = c.VkCommandPool;
pub const VkCommandBuffer = c.VkCommandBuffer;
pub const VkRenderPass = c.VkRenderPass;
pub const VkFramebuffer = c.VkFramebuffer;
pub const VkPipeline = c.VkPipeline;
pub const VkPipelineLayout = c.VkPipelineLayout;
pub const VkBuffer = c.VkBuffer;
pub const VkDeviceMemory = c.VkDeviceMemory;
pub const VkImage = c.VkImage;
pub const VkImageView = c.VkImageView;
pub const VkSwapchainKHR = c.VkSwapchainKHR;
pub const VkSurfaceKHR = c.VkSurfaceKHR;
pub const VkSemaphore = c.VkSemaphore;
pub const VkFence = c.VkFence;
pub const VkDescriptorSetLayout = c.VkDescriptorSetLayout;
pub const VkDescriptorPool = c.VkDescriptorPool;
pub const VkDescriptorSet = c.VkDescriptorSet;

// Function pointers
pub const vkCreateInstance = c.vkCreateInstance;
pub const vkDestroyInstance = c.vkDestroyInstance;
pub const vkEnumeratePhysicalDevices = c.vkEnumeratePhysicalDevices;
pub const vkGetPhysicalDeviceProperties = c.vkGetPhysicalDeviceProperties;
pub const vkGetPhysicalDeviceQueueFamilyProperties = c.vkGetPhysicalDeviceQueueFamilyProperties;
pub const vkCreateDevice = c.vkCreateDevice;
pub const vkDestroyDevice = c.vkDestroyDevice;
pub const vkGetDeviceQueue = c.vkGetDeviceQueue;
pub const vkCreateWin32SurfaceKHR = c.vkCreateWin32SurfaceKHR;
pub const vkDestroySurfaceKHR = c.vkDestroySurfaceKHR;
pub const vkGetPhysicalDeviceSurfaceSupportKHR = c.vkGetPhysicalDeviceSurfaceSupportKHR;
pub const vkGetPhysicalDeviceSurfaceCapabilitiesKHR = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR;
pub const vkGetPhysicalDeviceSurfaceFormatsKHR = c.vkGetPhysicalDeviceSurfaceFormatsKHR;
pub const vkGetPhysicalDeviceSurfacePresentModesKHR = c.vkGetPhysicalDeviceSurfacePresentModesKHR;
pub const vkCreateSwapchainKHR = c.vkCreateSwapchainKHR;
pub const vkDestroySwapchainKHR = c.vkDestroySwapchainKHR;
pub const vkGetSwapchainImagesKHR = c.vkGetSwapchainImagesKHR;
pub const vkAcquireNextImageKHR = c.vkAcquireNextImageKHR;
pub const vkQueuePresentKHR = c.vkQueuePresentKHR;

// Constants
pub const VK_SUCCESS = c.VK_SUCCESS;
pub const VK_ERROR_OUT_OF_HOST_MEMORY = c.VK_ERROR_OUT_OF_HOST_MEMORY;
pub const VK_ERROR_OUT_OF_DEVICE_MEMORY = c.VK_ERROR_OUT_OF_DEVICE_MEMORY;
pub const VK_ERROR_INITIALIZATION_FAILED = c.VK_ERROR_INITIALIZATION_FAILED;
pub const VK_ERROR_DEVICE_LOST = c.VK_ERROR_DEVICE_LOST;
pub const VK_ERROR_MEMORY_MAP_FAILED = c.VK_ERROR_MEMORY_MAP_FAILED;
pub const VK_ERROR_LAYER_NOT_PRESENT = c.VK_ERROR_LAYER_NOT_PRESENT;
pub const VK_ERROR_EXTENSION_NOT_PRESENT = c.VK_ERROR_EXTENSION_NOT_PRESENT;
pub const VK_ERROR_FEATURE_NOT_PRESENT = c.VK_ERROR_FEATURE_NOT_PRESENT;
pub const VK_ERROR_INCOMPATIBLE_DRIVER = c.VK_ERROR_INCOMPATIBLE_DRIVER;
pub const VK_ERROR_TOO_MANY_OBJECTS = c.VK_ERROR_TOO_MANY_OBJECTS;
pub const VK_ERROR_FORMAT_NOT_SUPPORTED = c.VK_ERROR_FORMAT_NOT_SUPPORTED;
pub const VK_ERROR_SURFACE_LOST_KHR = c.VK_ERROR_SURFACE_LOST_KHR;
pub const VK_ERROR_NATIVE_WINDOW_IN_USE_KHR = c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR;
pub const VK_SUBOPTIMAL_KHR = c.VK_SUBOPTIMAL_KHR;
pub const VK_ERROR_OUT_OF_DATE_KHR = c.VK_ERROR_OUT_OF_DATE_KHR;

// Structure types
pub const VK_STRUCTURE_TYPE_APPLICATION_INFO = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
pub const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
pub const VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
pub const VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
pub const VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
pub const VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;

// Queue family properties
pub const VK_QUEUE_GRAPHICS_BIT = c.VK_QUEUE_GRAPHICS_BIT;
pub const VK_QUEUE_COMPUTE_BIT = c.VK_QUEUE_COMPUTE_BIT;
pub const VK_QUEUE_TRANSFER_BIT = c.VK_QUEUE_TRANSFER_BIT;

// Present modes
pub const VK_PRESENT_MODE_IMMEDIATE_KHR = c.VK_PRESENT_MODE_IMMEDIATE_KHR;
pub const VK_PRESENT_MODE_MAILBOX_KHR = c.VK_PRESENT_MODE_MAILBOX_KHR;
pub const VK_PRESENT_MODE_FIFO_KHR = c.VK_PRESENT_MODE_FIFO_KHR;
pub const VK_PRESENT_MODE_FIFO_RELAXED_KHR = c.VK_PRESENT_MODE_FIFO_RELAXED_KHR;

// Image usage flags
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;

// Sharing modes
pub const VK_SHARING_MODE_EXCLUSIVE = c.VK_SHARING_MODE_EXCLUSIVE;
pub const VK_SHARING_MODE_CONCURRENT = c.VK_SHARING_MODE_CONCURRENT;

// Surface transform flags
pub const VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR = c.VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;

// Composite alpha flags
pub const VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;

// Color space
pub const VK_COLOR_SPACE_SRGB_NONLINEAR_KHR = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;

// Formats
pub const VK_FORMAT_B8G8R8A8_UNORM = c.VK_FORMAT_B8G8R8A8_UNORM;
pub const VK_FORMAT_R8G8B8A8_UNORM = c.VK_FORMAT_R8G8B8A8_UNORM;

// Extensions
pub const VK_KHR_SURFACE_EXTENSION_NAME = c.VK_KHR_SURFACE_EXTENSION_NAME;
pub const VK_KHR_WIN32_SURFACE_EXTENSION_NAME = c.VK_KHR_WIN32_SURFACE_EXTENSION_NAME;
pub const VK_KHR_SWAPCHAIN_EXTENSION_NAME = c.VK_KHR_SWAPCHAIN_EXTENSION_NAME;

// Validation layers
pub const VK_LAYER_KHRONOS_VALIDATION_NAME = "VK_LAYER_KHRONOS_validation";

// Structures
pub const VkApplicationInfo = c.VkApplicationInfo;
pub const VkInstanceCreateInfo = c.VkInstanceCreateInfo;
pub const VkDeviceCreateInfo = c.VkDeviceCreateInfo;
pub const VkDeviceQueueCreateInfo = c.VkDeviceQueueCreateInfo;
pub const VkPhysicalDeviceProperties = c.VkPhysicalDeviceProperties;
pub const VkQueueFamilyProperties = c.VkQueueFamilyProperties;
pub const VkWin32SurfaceCreateInfoKHR = c.VkWin32SurfaceCreateInfoKHR;
pub const VkSurfaceCapabilitiesKHR = c.VkSurfaceCapabilitiesKHR;
pub const VkSurfaceFormatKHR = c.VkSurfaceFormatKHR;
pub const VkSwapchainCreateInfoKHR = c.VkSwapchainCreateInfoKHR;
pub const VkExtent2D = c.VkExtent2D;
pub const VkPresentInfoKHR = c.VkPresentInfoKHR;

// Utility functions for checking Vulkan results
pub fn checkVkResult(result: VkResult, operation: []const u8) !void {
    if (result != VK_SUCCESS) {
        std.log.err("Vulkan operation '{s}' failed with result: {}", .{ operation, result });
        return error.VulkanOperationFailed;
    }
}

pub fn isVkSuccess(result: VkResult) bool {
    return result == VK_SUCCESS;
}
