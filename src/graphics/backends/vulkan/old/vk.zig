const std = @import("std");

// Unified Vulkan types, constants, and FFI for the codebase
// This file is the single source of truth for all Vulkan types/constants/FFI

pub const MAX_FRAMES_IN_FLIGHT = 2;

// Vulkan API version
pub const VK_API_VERSION_1_0 = (1 << 22) | (0 << 12) | 0;
pub const VK_API_VERSION_1_1 = (1 << 22) | (1 << 12) | 0;
pub const VK_API_VERSION_1_2 = (1 << 22) | (2 << 12) | 0;
pub const VK_API_VERSION_1_3 = (1 << 22) | (3 << 12) | 0;

// API version macros
pub inline fn VK_MAKE_API_VERSION(variant: u32, major: u32, minor: u32, patch: u32) u32 {
    return (variant << 29) | (major << 22) | (minor << 12) | patch;
}

// Vulkan result codes
pub const VkResult = enum(i32) {
    VK_SUCCESS = 0,
    VK_NOT_READY = 1,
    VK_TIMEOUT = 2,
    VK_EVENT_SET = 3,
    VK_EVENT_RESET = 4,
    VK_INCOMPLETE = 5,
    VK_ERROR_OUT_OF_HOST_MEMORY = -1,
    VK_ERROR_OUT_OF_DEVICE_MEMORY = -2,
    VK_ERROR_INITIALIZATION_FAILED = -3,
    VK_ERROR_DEVICE_LOST = -4,
    VK_ERROR_MEMORY_MAP_FAILED = -5,
    VK_ERROR_LAYER_NOT_PRESENT = -6,
    VK_ERROR_EXTENSION_NOT_PRESENT = -7,
    VK_ERROR_FEATURE_NOT_PRESENT = -8,
    VK_ERROR_INCOMPATIBLE_DRIVER = -9,
    VK_ERROR_TOO_MANY_OBJECTS = -10,
    VK_ERROR_FORMAT_NOT_SUPPORTED = -11,
    VK_ERROR_FRAGMENTED_POOL = -12,
    VK_ERROR_UNKNOWN = -13,
    VK_ERROR_OUT_OF_DATE_KHR = -1000001004,
    VK_SUBOPTIMAL_KHR = 1000001003,
    _,
};

// Vulkan handles
pub const VkInstance = *opaque {};
pub const VkPhysicalDevice = *opaque {};
pub const VkDevice = *opaque {};
pub const VkQueue = *opaque {};
pub const VkCommandPool = *opaque {};
pub const VkCommandBuffer = *opaque {};
pub const VkBuffer = *opaque {};
pub const VkDeviceMemory = *opaque {};
pub const VkImage = *opaque {};
pub const VkImageView = *opaque {};
pub const VkRenderPass = *opaque {};
pub const VkFramebuffer = *opaque {};
pub const VkPipeline = *opaque {};
pub const VkPipelineLayout = *opaque {};
pub const VkDescriptorSetLayout = *opaque {};
pub const VkDescriptorPool = *opaque {};
pub const VkDescriptorSet = *opaque {};
pub const VkSemaphore = *opaque {};
pub const VkFence = *opaque {};
pub const VkSwapchainKHR = *opaque {};
pub const VkSurfaceKHR = *opaque {};
pub const VkShaderModule = *opaque {};
pub const VkDebugUtilsMessengerEXT = *opaque {};

// Type aliases for easier usage (without Vk prefix) - for compatibility
pub const Instance = VkInstance;
pub const PhysicalDevice = VkPhysicalDevice;
pub const Device = VkDevice;
pub const Queue = VkQueue;
pub const CommandPool = VkCommandPool;
pub const CommandBuffer = VkCommandBuffer;
pub const Buffer = VkBuffer;
pub const DeviceMemory = VkDeviceMemory;
pub const Image = VkImage;
pub const ImageView = VkImageView;
pub const RenderPass = VkRenderPass;
pub const Framebuffer = VkFramebuffer;
pub const Pipeline = VkPipeline;
pub const PipelineLayout = VkPipelineLayout;
pub const DescriptorSetLayout = VkDescriptorSetLayout;
pub const DescriptorPool = VkDescriptorPool;
pub const DescriptorSet = VkDescriptorSet;
pub const Semaphore = VkSemaphore;
pub const Fence = VkFence;
pub const SwapchainKHR = VkSwapchainKHR;
pub const SurfaceKHR = VkSurfaceKHR;
pub const ShaderModule = VkShaderModule;

// Common type aliases for structures and enums
pub const Format = VkFormat;
pub const Extent2D = VkExtent2D;
pub const Extent3D = VkExtent3D;
pub const PresentModeKHR = VkPresentModeKHR;
pub const MemoryRequirements = VkMemoryRequirements;
pub const MemoryAllocateInfo = VkMemoryAllocateInfo;
pub const PhysicalDeviceMemoryProperties = VkPhysicalDeviceMemoryProperties;
pub const MemoryPropertyFlags = VkMemoryPropertyFlags;
pub const BufferUsageFlags = VkBufferUsageFlags;

// Additional type aliases for structures not yet defined but used in backend
pub const MappedMemoryRange = extern struct {
    sType: VkStructureType = VkStructureType.VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
    pNext: ?*const anyopaque = null,
    memory: VkDeviceMemory,
    offset: VkDeviceSize,
    size: VkDeviceSize,
};

pub const ImageUsageFlags = VkFlags;

// Image layout enum
pub const VkImageLayout = enum(i32) {
    VK_IMAGE_LAYOUT_UNDEFINED = 0,
    VK_IMAGE_LAYOUT_GENERAL = 1,
    VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL = 2,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL = 3,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL = 4,
    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL = 5,
    VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL = 6,
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL = 7,
    VK_IMAGE_LAYOUT_PREINITIALIZED = 8,
    VK_IMAGE_LAYOUT_PRESENT_SRC_KHR = 1000001002,
    _,
};

pub const ImageLayout = VkImageLayout;

// Vulkan basic types
pub const VkBool32 = u32;
pub const VkDeviceSize = u64;
pub const VkFlags = u32;
pub const VkSampleCountFlags = VkFlags;
pub const VkMemoryPropertyFlags = VkFlags;
pub const VkPipelineStageFlags = VkFlags;
pub const VkBufferUsageFlags = VkFlags;
pub const VkMemoryHeapFlags = VkFlags;

// Vulkan constants
pub const VK_TRUE = 1;
pub const VK_FALSE = 0;
pub const VK_NULL_HANDLE = @as(?*anyopaque, null);

// Structure types (only the ones actually used)
pub const VkStructureType = enum(i32) {
    VK_STRUCTURE_TYPE_APPLICATION_INFO = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1,
    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = 2,
    VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3,
    VK_STRUCTURE_TYPE_SUBMIT_INFO = 4,
    VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO = 5,
    VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE = 6,
    VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO = 12,
    VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO = 14,
    VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO = 15,
    VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO = 16,
    VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO = 18,
    VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO = 19,
    VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO = 20,
    VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO = 22,
    VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO = 23,
    VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO = 24,
    VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO = 26,
    VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO = 27,
    VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO = 28,
    VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO = 30,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32,
    VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO = 33,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO = 34,
    VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET = 35,
    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO = 37,
    VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO = 38,
    VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO = 39,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO = 40,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO = 42,
    VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO = 43,
    VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = 1000001000,
    VK_STRUCTURE_TYPE_PRESENT_INFO_KHR = 1000001001,
    VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR = 1000009000,
    VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT = 1000128004,
    _,
};

// Structure type constants for convenience
pub const VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
pub const VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
pub const VK_STRUCTURE_TYPE_SUBMIT_INFO = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;

// Command buffer level constants
pub const VK_COMMAND_BUFFER_LEVEL_PRIMARY = 0;
pub const VK_COMMAND_BUFFER_LEVEL_SECONDARY = 1;

// Command buffer usage flags (only used ones)
pub const VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT = 0x00000001;

// Pipeline stage flags (only used ones)
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT = 0x00000400;

// Buffer usage flags
pub const VK_BUFFER_USAGE_TRANSFER_SRC_BIT = 0x00000001;
pub const VK_BUFFER_USAGE_TRANSFER_DST_BIT = 0x00000002;
pub const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT = 0x00000080;
pub const VK_BUFFER_USAGE_INDEX_BUFFER_BIT = 0x00000040;
pub const VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT = 0x00000010;

// Sharing mode
pub const VK_SHARING_MODE_EXCLUSIVE = 0;
pub const VK_SHARING_MODE_CONCURRENT = 1;

// Memory property flags
pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT = 0x00000001;
pub const VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT = 0x00000002;
pub const VK_MEMORY_PROPERTY_HOST_COHERENT_BIT = 0x00000004;

// Vulkan enums (only commonly used formats)
pub const VkFormat = enum(i32) {
    VK_FORMAT_UNDEFINED = 0,
    VK_FORMAT_R8G8B8A8_UNORM = 37,
    VK_FORMAT_B8G8R8A8_UNORM = 44,
    VK_FORMAT_R32G32B32_SFLOAT = 106,
    VK_FORMAT_D16_UNORM = 124,
    VK_FORMAT_D32_SFLOAT = 126,
    VK_FORMAT_D24_UNORM_S8_UINT = 129,
    VK_FORMAT_D32_SFLOAT_S8_UINT = 130,
    _,
};

pub const VkColorSpaceKHR = enum(i32) {
    VK_COLOR_SPACE_SRGB_NONLINEAR_KHR = 0,
    _,
};

pub const VkPresentModeKHR = enum(i32) {
    VK_PRESENT_MODE_IMMEDIATE_KHR = 0,
    VK_PRESENT_MODE_MAILBOX_KHR = 1,
    VK_PRESENT_MODE_FIFO_KHR = 2,
    VK_PRESENT_MODE_FIFO_RELAXED_KHR = 3,
    _,
};

// Vulkan structures
pub const VkApplicationInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    pApplicationName: ?[*:0]const u8,
    applicationVersion: u32,
    pEngineName: ?[*:0]const u8,
    engineVersion: u32,
    apiVersion: u32,
};

pub const VkInstanceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    pApplicationInfo: ?*const VkApplicationInfo,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
};

pub const VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    queueFamilyIndex: u32,
    queueCount: u32,
    pQueuePriorities: [*]const f32,
};

pub const VkDeviceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    queueCreateInfoCount: u32,
    pQueueCreateInfos: [*]const VkDeviceQueueCreateInfo,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
    pEnabledFeatures: ?*const anyopaque = null,
};

pub const VkExtent2D = extern struct {
    width: u32,
    height: u32,
};

pub const VkExtent3D = extern struct {
    width: u32,
    height: u32,
    depth: u32,
};

pub const VkOffset2D = extern struct {
    x: i32,
    y: i32,
};

pub const VkRect2D = extern struct {
    offset: VkOffset2D,
    extent: VkExtent2D,
};

pub const VkViewport = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    minDepth: f32,
    maxDepth: f32,
};

// Buffer and memory
pub const VkBufferCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    size: VkDeviceSize,
    usage: VkFlags,
    sharingMode: u32,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
};

pub const VkMemoryAllocateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    allocationSize: VkDeviceSize,
    memoryTypeIndex: u32,
};

// Command buffer
pub const VkCommandPoolCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    queueFamilyIndex: u32,
};

pub const VkCommandBufferAllocateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    commandPool: VkCommandPool,
    level: u32,
    commandBufferCount: u32,
};

pub const VkCommandBufferBeginInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    pInheritanceInfo: ?*const anyopaque = null,
};

// Swapchain
pub const VkSurfaceCapabilitiesKHR = extern struct {
    minImageCount: u32,
    maxImageCount: u32,
    currentExtent: VkExtent2D,
    minImageExtent: VkExtent2D,
    maxImageExtent: VkExtent2D,
    maxImageArrayLayers: u32,
    supportedTransforms: VkFlags,
    currentTransform: u32,
    supportedCompositeAlpha: VkFlags,
    supportedUsageFlags: VkFlags,
};

pub const VkSurfaceFormatKHR = extern struct {
    format: VkFormat,
    colorSpace: VkColorSpaceKHR,
};

pub const VkSwapchainCreateInfoKHR = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    surface: VkSurfaceKHR,
    minImageCount: u32,
    imageFormat: VkFormat,
    imageColorSpace: VkColorSpaceKHR,
    imageExtent: VkExtent2D,
    imageArrayLayers: u32,
    imageUsage: u32,
    imageSharingMode: u32,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    preTransform: u32,
    compositeAlpha: u32,
    presentMode: VkPresentModeKHR,
    clipped: VkBool32,
    oldSwapchain: VkSwapchainKHR,
};

pub const VkFenceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
};

pub const VkSemaphoreCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
};

pub const VkSubmitInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    pWaitDstStageMask: ?[*]const VkFlags = null,
    commandBufferCount: u32,
    pCommandBuffers: [*]const VkCommandBuffer,
    signalSemaphoreCount: u32 = 0,
    pSignalSemaphores: ?[*]const VkSemaphore = null,
};

pub const VkPresentInfoKHR = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32,
    pWaitSemaphores: [*]const VkSemaphore,
    swapchainCount: u32,
    pSwapchains: [*]const VkSwapchainKHR,
    pImageIndices: [*]const u32,
    pResults: ?[*]VkResult = null,
};

// Memory Requirements
pub const VkMemoryRequirements = extern struct {
    size: VkDeviceSize,
    alignment: VkDeviceSize,
    memoryTypeBits: u32,
};

pub const VkMemoryType = extern struct {
    propertyFlags: VkFlags,
    heapIndex: u32,
};

pub const VkMemoryHeap = extern struct {
    size: VkDeviceSize,
    flags: VkFlags,
};

pub const VkPhysicalDeviceMemoryProperties = extern struct {
    memoryTypeCount: u32,
    memoryTypes: [32]VkMemoryType,
    memoryHeapCount: u32,
    memoryHeaps: [16]VkMemoryHeap,
};

// Buffer Copy Region
pub const VkBufferCopy = extern struct {
    srcOffset: VkDeviceSize,
    dstOffset: VkDeviceSize,
    size: VkDeviceSize,
};

// Win32 surface
pub const VkWin32SurfaceCreateInfoKHR = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    hinstance: *anyopaque,
    hwnd: *anyopaque,
};

// Vulkan function declarations
pub extern "vulkan-1" fn vkCreateInstance(
    pCreateInfo: *const VkInstanceCreateInfo,
    pAllocator: ?*const anyopaque,
    pInstance: *VkInstance,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyInstance(
    instance: VkInstance,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkEnumeratePhysicalDevices(
    instance: VkInstance,
    pPhysicalDeviceCount: *u32,
    pPhysicalDevices: ?[*]VkPhysicalDevice,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkCreateDevice(
    physicalDevice: VkPhysicalDevice,
    pCreateInfo: *const VkDeviceCreateInfo,
    pAllocator: ?*const anyopaque,
    pDevice: *VkDevice,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyDevice(
    device: VkDevice,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkGetDeviceQueue(
    device: VkDevice,
    queueFamilyIndex: u32,
    queueIndex: u32,
    pQueue: *VkQueue,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCreateCommandPool(
    device: VkDevice,
    pCreateInfo: *const VkCommandPoolCreateInfo,
    pAllocator: ?*const anyopaque,
    pCommandPool: *VkCommandPool,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyCommandPool(
    device: VkDevice,
    commandPool: VkCommandPool,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkAllocateCommandBuffers(
    device: VkDevice,
    pAllocateInfo: *const VkCommandBufferAllocateInfo,
    pCommandBuffers: [*]VkCommandBuffer,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkBeginCommandBuffer(
    commandBuffer: VkCommandBuffer,
    pBeginInfo: *const VkCommandBufferBeginInfo,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkEndCommandBuffer(
    commandBuffer: VkCommandBuffer,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkCreateBuffer(
    device: VkDevice,
    pCreateInfo: *const VkBufferCreateInfo,
    pAllocator: ?*const anyopaque,
    pBuffer: *VkBuffer,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyBuffer(
    device: VkDevice,
    buffer: VkBuffer,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkAllocateMemory(
    device: VkDevice,
    pAllocateInfo: *const VkMemoryAllocateInfo,
    pAllocator: ?*const anyopaque,
    pMemory: *VkDeviceMemory,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkFreeMemory(
    device: VkDevice,
    memory: VkDeviceMemory,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkBindBufferMemory(
    device: VkDevice,
    buffer: VkBuffer,
    memory: VkDeviceMemory,
    memoryOffset: VkDeviceSize,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkMapMemory(
    device: VkDevice,
    memory: VkDeviceMemory,
    offset: VkDeviceSize,
    size: VkDeviceSize,
    flags: VkFlags,
    ppData: *?*anyopaque,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkUnmapMemory(
    device: VkDevice,
    memory: VkDeviceMemory,
) callconv(.C) void;

// Win32 surface functions
pub extern "vulkan-1" fn vkCreateWin32SurfaceKHR(
    instance: VkInstance,
    pCreateInfo: *const VkWin32SurfaceCreateInfoKHR,
    pAllocator: ?*const anyopaque,
    pSurface: *VkSurfaceKHR,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroySurfaceKHR(
    instance: VkInstance,
    surface: VkSurfaceKHR,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

// Surface query functions are already defined below

pub extern "vulkan-1" fn vkCreateSwapchainKHR(
    device: VkDevice,
    pCreateInfo: *const VkSwapchainCreateInfoKHR,
    pAllocator: ?*const anyopaque,
    pSwapchain: *VkSwapchainKHR,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroySwapchainKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkGetSwapchainImagesKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pSwapchainImageCount: *u32,
    pSwapchainImages: ?[*]VkImage,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkWaitForFences(
    device: VkDevice,
    fenceCount: u32,
    pFences: [*]const VkFence,
    waitAll: VkBool32,
    timeout: u64,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkCreateFence(
    device: VkDevice,
    pCreateInfo: *const VkFenceCreateInfo,
    pAllocator: ?*const anyopaque,
    pFence: *VkFence,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyFence(
    device: VkDevice,
    fence: VkFence,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkResetFences(
    device: VkDevice,
    fenceCount: u32,
    pFences: [*]const VkFence,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkCreateSemaphore(
    device: VkDevice,
    pCreateInfo: *const VkSemaphoreCreateInfo,
    pAllocator: ?*const anyopaque,
    pSemaphore: *VkSemaphore,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroySemaphore(
    device: VkDevice,
    semaphore: VkSemaphore,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkQueueSubmit(
    queue: VkQueue,
    submitCount: u32,
    pSubmits: [*]const VkSubmitInfo,
    fence: ?VkFence,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkQueuePresentKHR(
    queue: VkQueue,
    pPresentInfo: *const VkPresentInfoKHR,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkAcquireNextImageKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    timeout: u64,
    semaphore: ?VkSemaphore,
    fence: ?VkFence,
    pImageIndex: *u32,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkGetBufferMemoryRequirements(
    device: VkDevice,
    buffer: VkBuffer,
    pMemoryRequirements: *VkMemoryRequirements,
) callconv(.C) void;

// Memory and buffer copy functions are already defined below

pub extern "vulkan-1" fn vkQueueWaitIdle(
    queue: VkQueue,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkFreeCommandBuffers(
    device: VkDevice,
    commandPool: VkCommandPool,
    commandBufferCount: u32,
    pCommandBuffers: [*]const VkCommandBuffer,
) callconv(.C) void;

pub extern "vulkan-1" fn vkDeviceWaitIdle(
    device: VkDevice,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkCreateImage(
    device: VkDevice,
    pCreateInfo: *const anyopaque,
    pAllocator: ?*const anyopaque,
    pImage: *VkImage,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyImage(
    device: VkDevice,
    image: VkImage,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkGetImageMemoryRequirements(
    device: VkDevice,
    image: VkImage,
    pMemoryRequirements: *VkMemoryRequirements,
) callconv(.C) void;

pub extern "vulkan-1" fn vkBindImageMemory(
    device: VkDevice,
    image: VkImage,
    memory: VkDeviceMemory,
    memoryOffset: VkDeviceSize,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkCreateImageView(
    device: VkDevice,
    pCreateInfo: *const anyopaque,
    pAllocator: ?*const anyopaque,
    pView: *VkImageView,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyImageView(
    device: VkDevice,
    imageView: VkImageView,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkDestroyDebugUtilsMessengerEXT(
    instance: VkInstance,
    messenger: VkDebugUtilsMessengerEXT,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

// Helper function for Win32 surface creation
pub fn createWin32Surface(instance: VkInstance, hinstance: *anyopaque, hwnd: *anyopaque) !VkSurfaceKHR {
    const create_info = VkWin32SurfaceCreateInfoKHR{
        .sType = VkStructureType.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .hinstance = hinstance,
        .hwnd = hwnd,
    };

    var surface: VkSurfaceKHR = undefined;
    const result = vkCreateWin32SurfaceKHR(instance, &create_info, null, &surface);

    if (result != VkResult.VK_SUCCESS) {
        return error.SurfaceCreationFailed;
    }

    return surface;
}

// Missing Vulkan function declarations
pub extern "vulkan-1" fn vkFlushMappedMemoryRanges(
    device: VkDevice,
    memoryRangeCount: u32,
    pMemoryRanges: [*]const MappedMemoryRange,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkInvalidateMappedMemoryRanges(
    device: VkDevice,
    memoryRangeCount: u32,
    pMemoryRanges: [*]const MappedMemoryRange,
) callconv(.C) VkResult;

// Additional missing functions for complete implementation
pub extern "vulkan-1" fn vkGetPhysicalDeviceProperties(
    physicalDevice: VkPhysicalDevice,
    pProperties: *VkPhysicalDeviceProperties,
) callconv(.C) void;

pub extern "vulkan-1" fn vkGetPhysicalDeviceFeatures(
    physicalDevice: VkPhysicalDevice,
    pFeatures: *VkPhysicalDeviceFeatures,
) callconv(.C) void;

pub extern "vulkan-1" fn vkGetPhysicalDeviceQueueFamilyProperties(
    physicalDevice: VkPhysicalDevice,
    pQueueFamilyPropertyCount: *u32,
    pQueueFamilyProperties: ?[*]VkQueueFamilyProperties,
) callconv(.C) void;

pub extern "vulkan-1" fn vkGetPhysicalDeviceSurfaceSupportKHR(
    physicalDevice: VkPhysicalDevice,
    queueFamilyIndex: u32,
    surface: VkSurfaceKHR,
    pSupported: *VkBool32,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkCreateShaderModule(
    device: VkDevice,
    pCreateInfo: *const VkShaderModuleCreateInfo,
    pAllocator: ?*const anyopaque,
    pShaderModule: *VkShaderModule,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyShaderModule(
    device: VkDevice,
    shaderModule: VkShaderModule,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCreatePipelineLayout(
    device: VkDevice,
    pCreateInfo: *const VkPipelineLayoutCreateInfo,
    pAllocator: ?*const anyopaque,
    pPipelineLayout: *VkPipelineLayout,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyPipelineLayout(
    device: VkDevice,
    pipelineLayout: VkPipelineLayout,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCreateRenderPass(
    device: VkDevice,
    pCreateInfo: *const VkRenderPassCreateInfo,
    pAllocator: ?*const anyopaque,
    pRenderPass: *VkRenderPass,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyRenderPass(
    device: VkDevice,
    renderPass: VkRenderPass,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCreateGraphicsPipelines(
    device: VkDevice,
    pipelineCache: VkPipelineCache,
    createInfoCount: u32,
    pCreateInfos: [*]const VkGraphicsPipelineCreateInfo,
    pAllocator: ?*const anyopaque,
    pPipelines: [*]VkPipeline,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyPipeline(
    device: VkDevice,
    pipeline: VkPipeline,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCreateFramebuffer(
    device: VkDevice,
    pCreateInfo: *const VkFramebufferCreateInfo,
    pAllocator: ?*const anyopaque,
    pFramebuffer: *VkFramebuffer,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyFramebuffer(
    device: VkDevice,
    framebuffer: VkFramebuffer,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCreateDescriptorSetLayout(
    device: VkDevice,
    pCreateInfo: *const VkDescriptorSetLayoutCreateInfo,
    pAllocator: ?*const anyopaque,
    pSetLayout: *VkDescriptorSetLayout,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyDescriptorSetLayout(
    device: VkDevice,
    descriptorSetLayout: VkDescriptorSetLayout,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCreateDescriptorPool(
    device: VkDevice,
    pCreateInfo: *const VkDescriptorPoolCreateInfo,
    pAllocator: ?*const anyopaque,
    pDescriptorPool: *VkDescriptorPool,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkDestroyDescriptorPool(
    device: VkDevice,
    descriptorPool: VkDescriptorPool,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

pub extern "vulkan-1" fn vkAllocateDescriptorSets(
    device: VkDevice,
    pAllocateInfo: *const VkDescriptorSetAllocateInfo,
    pDescriptorSets: [*]VkDescriptorSet,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkUpdateDescriptorSets(
    device: VkDevice,
    descriptorWriteCount: u32,
    pDescriptorWrites: [*]const VkWriteDescriptorSet,
    descriptorCopyCount: u32,
    pDescriptorCopies: ?[*]const VkCopyDescriptorSet,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdBeginRenderPass(
    commandBuffer: VkCommandBuffer,
    pRenderPassBegin: *const VkRenderPassBeginInfo,
    contents: VkSubpassContents,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdEndRenderPass(
    commandBuffer: VkCommandBuffer,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdBindPipeline(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    pipeline: VkPipeline,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdSetViewport(
    commandBuffer: VkCommandBuffer,
    firstViewport: u32,
    viewportCount: u32,
    pViewports: [*]const VkViewport,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdSetScissor(
    commandBuffer: VkCommandBuffer,
    firstScissor: u32,
    scissorCount: u32,
    pScissors: [*]const VkRect2D,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdBindVertexBuffers(
    commandBuffer: VkCommandBuffer,
    firstBinding: u32,
    bindingCount: u32,
    pBuffers: [*]const VkBuffer,
    pOffsets: [*]const VkDeviceSize,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdBindIndexBuffer(
    commandBuffer: VkCommandBuffer,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    indexType: VkIndexType,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdBindDescriptorSets(
    commandBuffer: VkCommandBuffer,
    pipelineBindPoint: VkPipelineBindPoint,
    layout: VkPipelineLayout,
    firstSet: u32,
    descriptorSetCount: u32,
    pDescriptorSets: [*]const VkDescriptorSet,
    dynamicOffsetCount: u32,
    pDynamicOffsets: ?[*]const u32,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdDrawIndexed(
    commandBuffer: VkCommandBuffer,
    indexCount: u32,
    instanceCount: u32,
    firstIndex: u32,
    vertexOffset: i32,
    firstInstance: u32,
) callconv(.C) void;

// Additional types and constants
pub const VkPipelineCache = *opaque {};
pub const VkSampler = *opaque {};

pub const VkPhysicalDeviceProperties = extern struct {
    apiVersion: u32,
    driverVersion: u32,
    vendorID: u32,
    deviceID: u32,
    deviceType: VkPhysicalDeviceType,
    deviceName: [256]u8,
    pipelineCacheUUID: [16]u8,
    limits: VkPhysicalDeviceLimits,
    sparseProperties: VkPhysicalDeviceSparseProperties,
};

pub const VkPhysicalDeviceType = enum(i32) {
    VK_PHYSICAL_DEVICE_TYPE_OTHER = 0,
    VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU = 1,
    VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU = 2,
    VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU = 3,
    VK_PHYSICAL_DEVICE_TYPE_CPU = 4,
    _,
};

pub const VkPhysicalDeviceLimits = extern struct {
    maxImageDimension1D: u32,
    maxImageDimension2D: u32,
    maxImageDimension3D: u32,
    maxImageDimensionCube: u32,
    maxImageArrayLayers: u32,
    maxTexelBufferElements: u32,
    maxUniformBufferRange: u32,
    maxStorageBufferRange: u32,
    maxPushConstantsSize: u32,
    maxMemoryAllocationCount: u32,
    maxSamplerAllocationCount: u32,
    bufferImageGranularity: VkDeviceSize,
    sparseAddressSpaceSize: VkDeviceSize,
    maxBoundDescriptorSets: u32,
    maxPerStageDescriptorSamplers: u32,
    maxPerStageDescriptorUniformBuffers: u32,
    maxPerStageDescriptorStorageBuffers: u32,
    maxPerStageDescriptorSampledImages: u32,
    maxPerStageDescriptorStorageImages: u32,
    maxPerStageDescriptorInputAttachments: u32,
    maxPerStageResources: u32,
    maxDescriptorSetSamplers: u32,
    maxDescriptorSetUniformBuffers: u32,
    maxDescriptorSetUniformBuffersDynamic: u32,
    maxDescriptorSetStorageBuffers: u32,
    maxDescriptorSetStorageBuffersDynamic: u32,
    maxDescriptorSetSampledImages: u32,
    maxDescriptorSetStorageImages: u32,
    maxDescriptorSetInputAttachments: u32,
    maxVertexInputAttributes: u32,
    maxVertexInputBindings: u32,
    maxVertexInputAttributeOffset: u32,
    maxVertexInputBindingStride: u32,
    maxVertexOutputComponents: u32,
    maxTessellationGenerationLevel: u32,
    maxTessellationPatchSize: u32,
    maxTessellationControlPerVertexInputComponents: u32,
    maxTessellationControlPerVertexOutputComponents: u32,
    maxTessellationControlPerPatchOutputComponents: u32,
    maxTessellationControlTotalOutputComponents: u32,
    maxTessellationEvaluationInputComponents: u32,
    maxTessellationEvaluationOutputComponents: u32,
    maxGeometryShaderInvocations: u32,
    maxGeometryInputComponents: u32,
    maxGeometryOutputComponents: u32,
    maxGeometryOutputVertices: u32,
    maxGeometryTotalOutputComponents: u32,
    maxFragmentInputComponents: u32,
    maxFragmentOutputAttachments: u32,
    maxFragmentDualSrcAttachments: u32,
    maxFragmentCombinedOutputResources: u32,
    maxComputeSharedMemorySize: u32,
    maxComputeWorkGroupCount: [3]u32,
    maxComputeWorkGroupInvocations: u32,
    maxComputeWorkGroupSize: [3]u32,
    subPixelPrecisionBits: u32,
    subTexelPrecisionBits: u32,
    mipmapPrecisionBits: u32,
    maxDrawIndexedIndexValue: u32,
    maxDrawIndirectCount: u32,
    maxSamplerLodBias: f32,
    maxSamplerAnisotropy: f32,
    maxViewports: u32,
    maxViewportDimensions: [2]u32,
    viewportBoundsRange: [2]f32,
    viewportSubPixelBits: u32,
    minMemoryMapAlignment: usize,
    minTexelBufferOffsetAlignment: VkDeviceSize,
    minUniformBufferOffsetAlignment: VkDeviceSize,
    minStorageBufferOffsetAlignment: VkDeviceSize,
    minTexelOffset: i32,
    maxTexelOffset: u32,
    minTexelGatherOffset: i32,
    maxTexelGatherOffset: u32,
    minInterpolationOffset: f32,
    maxInterpolationOffset: f32,
    subPixelInterpolationOffsetBits: u32,
    maxFramebufferWidth: u32,
    maxFramebufferHeight: u32,
    maxFramebufferLayers: u32,
    framebufferColorSampleCounts: VkSampleCountFlags,
    framebufferDepthSampleCounts: VkSampleCountFlags,
    framebufferStencilSampleCounts: VkSampleCountFlags,
    framebufferNoAttachmentsSampleCounts: VkSampleCountFlags,
    maxColorAttachments: u32,
    sampledImageColorSampleCounts: VkSampleCountFlags,
    sampledImageIntegerSampleCounts: VkSampleCountFlags,
    sampledImageDepthSampleCounts: VkSampleCountFlags,
    sampledImageStencilSampleCounts: VkSampleCountFlags,
    storageImageSampleCounts: VkSampleCountFlags,
    maxSampleMaskWords: u32,
    timestampComputeAndGraphics: VkBool32,
    timestampPeriod: f32,
    maxClipDistances: u32,
    maxCullDistances: u32,
    maxCombinedClipAndCullDistances: u32,
    discreteQueuePriorities: u32,
    pointSizeRange: [2]f32,
    lineWidthRange: [2]f32,
    pointSizeGranularity: f32,
    lineWidthGranularity: f32,
    strictLines: VkBool32,
    standardSampleLocations: VkBool32,
    optimalBufferCopyOffsetAlignment: VkDeviceSize,
    optimalBufferCopyRowPitchAlignment: VkDeviceSize,
    nonCoherentAtomSize: VkDeviceSize,
};

pub const VkPhysicalDeviceSparseProperties = extern struct {
    residencyStandard2DBlockShape: VkBool32,
    residencyStandard2DMultisampleBlockShape: VkBool32,
    residencyStandard3DBlockShape: VkBool32,
    residencyAlignedMipSize: VkBool32,
    residencyNonResidentStrict: VkBool32,
};

pub const VkPhysicalDeviceFeatures = extern struct {
    robustBufferAccess: VkBool32,
    fullDrawIndexUint32: VkBool32,
    imageCubeArray: VkBool32,
    independentBlend: VkBool32,
    geometryShader: VkBool32,
    tessellationShader: VkBool32,
    sampleRateShading: VkBool32,
    dualSrcBlend: VkBool32,
    logicOp: VkBool32,
    multiDrawIndirect: VkBool32,
    drawIndirectFirstInstance: VkBool32,
    depthClamp: VkBool32,
    depthBiasClamp: VkBool32,
    fillModeNonSolid: VkBool32,
    depthBounds: VkBool32,
    wideLines: VkBool32,
    largePoints: VkBool32,
    alphaToOne: VkBool32,
    multiViewport: VkBool32,
    samplerAnisotropy: VkBool32,
    textureCompressionETC2: VkBool32,
    textureCompressionASTC_LDR: VkBool32,
    textureCompressionBC: VkBool32,
    occlusionQueryPrecise: VkBool32,
    pipelineStatisticsQuery: VkBool32,
    vertexPipelineStoresAndAtomics: VkBool32,
    fragmentStoresAndAtomics: VkBool32,
    shaderTessellationAndGeometryPointSize: VkBool32,
    shaderImageGatherExtended: VkBool32,
    shaderStorageImageExtendedFormats: VkBool32,
    shaderStorageImageMultisample: VkBool32,
    shaderStorageImageReadWithoutFormat: VkBool32,
    shaderStorageImageWriteWithoutFormat: VkBool32,
    shaderUniformBufferArrayDynamicIndexing: VkBool32,
    shaderSampledImageArrayDynamicIndexing: VkBool32,
    shaderStorageBufferArrayDynamicIndexing: VkBool32,
    shaderStorageImageArrayDynamicIndexing: VkBool32,
    shaderClipDistance: VkBool32,
    shaderCullDistance: VkBool32,
    shaderFloat64: VkBool32,
    shaderInt64: VkBool32,
    shaderInt16: VkBool32,
    shaderResourceResidency: VkBool32,
    shaderResourceMinLod: VkBool32,
    sparseBinding: VkBool32,
    sparseResidencyBuffer: VkBool32,
    sparseResidencyImage2D: VkBool32,
    sparseResidencyImage3D: VkBool32,
    sparseResidency2Samples: VkBool32,
    sparseResidency4Samples: VkBool32,
    sparseResidency8Samples: VkBool32,
    sparseResidency16Samples: VkBool32,
    sparseResidencyAliased: VkBool32,
    variableMultisampleRate: VkBool32,
    inheritedQueries: VkBool32,
};

pub const VkQueueFamilyProperties = extern struct {
    queueFlags: VkQueueFlags,
    queueCount: u32,
    timestampValidBits: u32,
    minImageTransferGranularity: VkExtent3D,
};

pub const VkQueueFlags = VkFlags;
pub const VK_QUEUE_GRAPHICS_BIT = 0x00000001;
pub const VK_QUEUE_COMPUTE_BIT = 0x00000002;
pub const VK_QUEUE_TRANSFER_BIT = 0x00000004;
pub const VK_QUEUE_SPARSE_BINDING_BIT = 0x00000008;

pub const VkShaderModuleCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    codeSize: usize,
    pCode: [*]const u32,
};

pub const VkPipelineLayoutCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    setLayoutCount: u32,
    pSetLayouts: ?[*]const VkDescriptorSetLayout,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges: ?[*]const VkPushConstantRange = null,
};

pub const VkPushConstantRange = extern struct {
    stageFlags: VkShaderStageFlags,
    offset: u32,
    size: u32,
};

pub const VkShaderStageFlags = VkFlags;
pub const VK_SHADER_STAGE_VERTEX_BIT = 0x00000001;
pub const VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT = 0x00000002;
pub const VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT = 0x00000004;
pub const VK_SHADER_STAGE_GEOMETRY_BIT = 0x00000008;
pub const VK_SHADER_STAGE_FRAGMENT_BIT = 0x00000010;
pub const VK_SHADER_STAGE_COMPUTE_BIT = 0x00000020;
pub const VK_SHADER_STAGE_ALL_GRAPHICS = 0x0000001F;
pub const VK_SHADER_STAGE_ALL = 0x7FFFFFFF;

pub const VkRenderPassCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    attachmentCount: u32,
    pAttachments: [*]const VkAttachmentDescription,
    subpassCount: u32,
    pSubpasses: [*]const VkSubpassDescription,
    dependencyCount: u32,
    pDependencies: ?[*]const VkSubpassDependency,
};

pub const VkAttachmentDescription = extern struct {
    flags: VkFlags = 0,
    format: VkFormat,
    samples: VkSampleCountFlagBits,
    loadOp: VkAttachmentLoadOp,
    storeOp: VkAttachmentStoreOp,
    stencilLoadOp: VkAttachmentLoadOp,
    stencilStoreOp: VkAttachmentStoreOp,
    initialLayout: VkImageLayout,
    finalLayout: VkImageLayout,
};

pub const VkSampleCountFlagBits = enum(u32) {
    VK_SAMPLE_COUNT_1_BIT = 0x00000001,
    VK_SAMPLE_COUNT_2_BIT = 0x00000002,
    VK_SAMPLE_COUNT_4_BIT = 0x00000004,
    VK_SAMPLE_COUNT_8_BIT = 0x00000008,
    VK_SAMPLE_COUNT_16_BIT = 0x00000010,
    VK_SAMPLE_COUNT_32_BIT = 0x00000020,
    VK_SAMPLE_COUNT_64_BIT = 0x00000040,
    _,
};

pub const VkAttachmentLoadOp = enum(i32) {
    VK_ATTACHMENT_LOAD_OP_LOAD = 0,
    VK_ATTACHMENT_LOAD_OP_CLEAR = 1,
    VK_ATTACHMENT_LOAD_OP_DONT_CARE = 2,
    _,
};

pub const VkAttachmentStoreOp = enum(i32) {
    VK_ATTACHMENT_STORE_OP_STORE = 0,
    VK_ATTACHMENT_STORE_OP_DONT_CARE = 1,
    _,
};

pub const VkSubpassDescription = extern struct {
    flags: VkFlags = 0,
    pipelineBindPoint: VkPipelineBindPoint,
    inputAttachmentCount: u32 = 0,
    pInputAttachments: ?[*]const VkAttachmentReference = null,
    colorAttachmentCount: u32,
    pColorAttachments: [*]const VkAttachmentReference,
    pResolveAttachments: ?[*]const VkAttachmentReference = null,
    pDepthStencilAttachment: ?*const VkAttachmentReference = null,
    preserveAttachmentCount: u32 = 0,
    pPreserveAttachments: ?[*]const u32 = null,
};

pub const VkPipelineBindPoint = enum(i32) {
    VK_PIPELINE_BIND_POINT_GRAPHICS = 0,
    VK_PIPELINE_BIND_POINT_COMPUTE = 1,
    _,
};

pub const VkAttachmentReference = extern struct {
    attachment: u32,
    layout: VkImageLayout,
};

pub const VkSubpassDependency = extern struct {
    srcSubpass: u32,
    dstSubpass: u32,
    srcStageMask: VkPipelineStageFlags,
    dstStageMask: VkPipelineStageFlags,
    srcAccessMask: VkAccessFlags = 0,
    dstAccessMask: VkAccessFlags = 0,
    dependencyFlags: VkDependencyFlags = 0,
};

pub const VkAccessFlags = VkFlags;
pub const VkDependencyFlags = VkFlags;

pub const VkGraphicsPipelineCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    stageCount: u32,
    pStages: [*]const VkPipelineShaderStageCreateInfo,
    pVertexInputState: *const VkPipelineVertexInputStateCreateInfo,
    pInputAssemblyState: *const VkPipelineInputAssemblyStateCreateInfo,
    pTessellationState: ?*const VkPipelineTessellationStateCreateInfo = null,
    pViewportState: *const VkPipelineViewportStateCreateInfo,
    pRasterizationState: *const VkPipelineRasterizationStateCreateInfo,
    pMultisampleState: *const VkPipelineMultisampleStateCreateInfo,
    pDepthStencilState: ?*const VkPipelineDepthStencilStateCreateInfo = null,
    pColorBlendState: *const VkPipelineColorBlendStateCreateInfo,
    pDynamicState: ?*const VkPipelineDynamicStateCreateInfo = null,
    layout: VkPipelineLayout,
    renderPass: VkRenderPass,
    subpass: u32,
    basePipelineHandle: VkPipeline = @ptrCast(VK_NULL_HANDLE),
    basePipelineIndex: i32 = -1,
};

pub const VkPipelineShaderStageCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    stage: VkShaderStageFlagBits,
    module: VkShaderModule,
    pName: [*:0]const u8,
    pSpecializationInfo: ?*const VkSpecializationInfo = null,
};

pub const VkShaderStageFlagBits = enum(u32) {
    VK_SHADER_STAGE_VERTEX_BIT = 0x00000001,
    VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT = 0x00000002,
    VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT = 0x00000004,
    VK_SHADER_STAGE_GEOMETRY_BIT = 0x00000008,
    VK_SHADER_STAGE_FRAGMENT_BIT = 0x00000010,
    VK_SHADER_STAGE_COMPUTE_BIT = 0x00000020,
    _,
};

pub const VkSpecializationInfo = extern struct {
    mapEntryCount: u32,
    pMapEntries: [*]const VkSpecializationMapEntry,
    dataSize: usize,
    pData: *const anyopaque,
};

pub const VkSpecializationMapEntry = extern struct {
    constantID: u32,
    offset: u32,
    size: usize,
};

pub const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    vertexBindingDescriptionCount: u32,
    pVertexBindingDescriptions: ?[*]const VkVertexInputBindingDescription,
    vertexAttributeDescriptionCount: u32,
    pVertexAttributeDescriptions: ?[*]const VkVertexInputAttributeDescription,
};

pub const VkVertexInputBindingDescription = extern struct {
    binding: u32,
    stride: u32,
    inputRate: VkVertexInputRate,
};

pub const VkVertexInputRate = enum(i32) {
    VK_VERTEX_INPUT_RATE_VERTEX = 0,
    VK_VERTEX_INPUT_RATE_INSTANCE = 1,
    _,
};

pub const VkVertexInputAttributeDescription = extern struct {
    location: u32,
    binding: u32,
    format: VkFormat,
    offset: u32,
};

pub const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    topology: VkPrimitiveTopology,
    primitiveRestartEnable: VkBool32,
};

pub const VkPrimitiveTopology = enum(i32) {
    VK_PRIMITIVE_TOPOLOGY_POINT_LIST = 0,
    VK_PRIMITIVE_TOPOLOGY_LINE_LIST = 1,
    VK_PRIMITIVE_TOPOLOGY_LINE_STRIP = 2,
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST = 3,
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP = 4,
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN = 5,
    _,
};

pub const VkPipelineTessellationStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    patchControlPoints: u32,
};

pub const VkPipelineViewportStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    viewportCount: u32,
    pViewports: ?[*]const VkViewport,
    scissorCount: u32,
    pScissors: ?[*]const VkRect2D,
};

pub const VkPipelineRasterizationStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    depthClampEnable: VkBool32,
    rasterizerDiscardEnable: VkBool32,
    polygonMode: VkPolygonMode,
    cullMode: VkCullModeFlags,
    frontFace: VkFrontFace,
    depthBiasEnable: VkBool32,
    depthBiasConstantFactor: f32 = 0.0,
    depthBiasClamp: f32 = 0.0,
    depthBiasSlopeFactor: f32 = 0.0,
    lineWidth: f32 = 1.0,
};

pub const VkPolygonMode = enum(i32) {
    VK_POLYGON_MODE_FILL = 0,
    VK_POLYGON_MODE_LINE = 1,
    VK_POLYGON_MODE_POINT = 2,
    _,
};

pub const VkCullModeFlags = VkFlags;
pub const VK_CULL_MODE_NONE = 0;
pub const VK_CULL_MODE_FRONT_BIT = 0x00000001;
pub const VK_CULL_MODE_BACK_BIT = 0x00000002;
pub const VK_CULL_MODE_FRONT_AND_BACK = 0x00000003;

pub const VkFrontFace = enum(i32) {
    VK_FRONT_FACE_COUNTER_CLOCKWISE = 0,
    VK_FRONT_FACE_CLOCKWISE = 1,
    _,
};

pub const VkPipelineMultisampleStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    rasterizationSamples: VkSampleCountFlagBits,
    sampleShadingEnable: VkBool32,
    minSampleShading: f32 = 1.0,
    pSampleMask: ?[*]const VkSampleMask = null,
    alphaToCoverageEnable: VkBool32,
    alphaToOneEnable: VkBool32,
};

pub const VkSampleMask = u32;

pub const VkPipelineDepthStencilStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    depthTestEnable: VkBool32,
    depthWriteEnable: VkBool32,
    depthCompareOp: VkCompareOp,
    depthBoundsTestEnable: VkBool32,
    stencilTestEnable: VkBool32,
    front: VkStencilOpState,
    back: VkStencilOpState,
    minDepthBounds: f32 = 0.0,
    maxDepthBounds: f32 = 1.0,
};

pub const VkCompareOp = enum(i32) {
    VK_COMPARE_OP_NEVER = 0,
    VK_COMPARE_OP_LESS = 1,
    VK_COMPARE_OP_EQUAL = 2,
    VK_COMPARE_OP_LESS_OR_EQUAL = 3,
    VK_COMPARE_OP_GREATER = 4,
    VK_COMPARE_OP_NOT_EQUAL = 5,
    VK_COMPARE_OP_GREATER_OR_EQUAL = 6,
    VK_COMPARE_OP_ALWAYS = 7,
    _,
};

pub const VkStencilOpState = extern struct {
    failOp: VkStencilOp,
    passOp: VkStencilOp,
    depthFailOp: VkStencilOp,
    compareOp: VkCompareOp,
    compareMask: u32,
    writeMask: u32,
    reference: u32,
};

pub const VkStencilOp = enum(i32) {
    VK_STENCIL_OP_KEEP = 0,
    VK_STENCIL_OP_ZERO = 1,
    VK_STENCIL_OP_REPLACE = 2,
    VK_STENCIL_OP_INCREMENT_AND_CLAMP = 3,
    VK_STENCIL_OP_DECREMENT_AND_CLAMP = 4,
    VK_STENCIL_OP_INVERT = 5,
    VK_STENCIL_OP_INCREMENT_AND_WRAP = 6,
    VK_STENCIL_OP_DECREMENT_AND_WRAP = 7,
    _,
};

pub const VkPipelineColorBlendStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    logicOpEnable: VkBool32,
    logicOp: VkLogicOp,
    attachmentCount: u32,
    pAttachments: [*]const VkPipelineColorBlendAttachmentState,
    blendConstants: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
};

pub const VkLogicOp = enum(i32) {
    VK_LOGIC_OP_CLEAR = 0,
    VK_LOGIC_OP_AND = 1,
    VK_LOGIC_OP_AND_REVERSE = 2,
    VK_LOGIC_OP_COPY = 3,
    VK_LOGIC_OP_AND_INVERTED = 4,
    VK_LOGIC_OP_NO_OP = 5,
    VK_LOGIC_OP_XOR = 6,
    VK_LOGIC_OP_OR = 7,
    VK_LOGIC_OP_NOR = 8,
    VK_LOGIC_OP_EQUIVALENT = 9,
    VK_LOGIC_OP_INVERT = 10,
    VK_LOGIC_OP_OR_REVERSE = 11,
    VK_LOGIC_OP_COPY_INVERTED = 12,
    VK_LOGIC_OP_OR_INVERTED = 13,
    VK_LOGIC_OP_NAND = 14,
    VK_LOGIC_OP_SET = 15,
    _,
};

pub const VkPipelineColorBlendAttachmentState = extern struct {
    blendEnable: VkBool32,
    srcColorBlendFactor: VkBlendFactor,
    dstColorBlendFactor: VkBlendFactor,
    colorBlendOp: VkBlendOp,
    srcAlphaBlendFactor: VkBlendFactor,
    dstAlphaBlendFactor: VkBlendFactor,
    alphaBlendOp: VkBlendOp,
    colorWriteMask: VkColorComponentFlags,
};

pub const VkBlendFactor = enum(i32) {
    VK_BLEND_FACTOR_ZERO = 0,
    VK_BLEND_FACTOR_ONE = 1,
    VK_BLEND_FACTOR_SRC_COLOR = 2,
    VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR = 3,
    VK_BLEND_FACTOR_DST_COLOR = 4,
    VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR = 5,
    VK_BLEND_FACTOR_SRC_ALPHA = 6,
    VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA = 7,
    VK_BLEND_FACTOR_DST_ALPHA = 8,
    VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA = 9,
    VK_BLEND_FACTOR_CONSTANT_COLOR = 10,
    VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR = 11,
    VK_BLEND_FACTOR_CONSTANT_ALPHA = 12,
    VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA = 13,
    VK_BLEND_FACTOR_SRC_ALPHA_SATURATE = 14,
    _,
};

pub const VkBlendOp = enum(i32) {
    VK_BLEND_OP_ADD = 0,
    VK_BLEND_OP_SUBTRACT = 1,
    VK_BLEND_OP_REVERSE_SUBTRACT = 2,
    VK_BLEND_OP_MIN = 3,
    VK_BLEND_OP_MAX = 4,
    _,
};

pub const VkColorComponentFlags = VkFlags;
pub const VK_COLOR_COMPONENT_R_BIT = 0x00000001;
pub const VK_COLOR_COMPONENT_G_BIT = 0x00000002;
pub const VK_COLOR_COMPONENT_B_BIT = 0x00000004;
pub const VK_COLOR_COMPONENT_A_BIT = 0x00000008;

pub const VkPipelineDynamicStateCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    dynamicStateCount: u32,
    pDynamicStates: [*]const VkDynamicState,
};

pub const VkDynamicState = enum(i32) {
    VK_DYNAMIC_STATE_VIEWPORT = 0,
    VK_DYNAMIC_STATE_SCISSOR = 1,
    VK_DYNAMIC_STATE_LINE_WIDTH = 2,
    VK_DYNAMIC_STATE_DEPTH_BIAS = 3,
    VK_DYNAMIC_STATE_BLEND_CONSTANTS = 4,
    VK_DYNAMIC_STATE_DEPTH_BOUNDS = 5,
    VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK = 6,
    VK_DYNAMIC_STATE_STENCIL_WRITE_MASK = 7,
    VK_DYNAMIC_STATE_STENCIL_REFERENCE = 8,
    _,
};

pub const VkFramebufferCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    renderPass: VkRenderPass,
    attachmentCount: u32,
    pAttachments: [*]const VkImageView,
    width: u32,
    height: u32,
    layers: u32,
};

pub const VkDescriptorSetLayoutCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    bindingCount: u32,
    pBindings: ?[*]const VkDescriptorSetLayoutBinding,
};

pub const VkDescriptorSetLayoutBinding = extern struct {
    binding: u32,
    descriptorType: VkDescriptorType,
    descriptorCount: u32,
    stageFlags: VkShaderStageFlags,
    pImmutableSamplers: ?[*]const VkSampler = null,
};

pub const VkDescriptorType = enum(i32) {
    VK_DESCRIPTOR_TYPE_SAMPLER = 0,
    VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER = 1,
    VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE = 2,
    VK_DESCRIPTOR_TYPE_STORAGE_IMAGE = 3,
    VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER = 4,
    VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER = 5,
    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER = 6,
    VK_DESCRIPTOR_TYPE_STORAGE_BUFFER = 7,
    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC = 8,
    VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC = 9,
    VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT = 10,
    _,
};

pub const VkDescriptorPoolCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    maxSets: u32,
    poolSizeCount: u32,
    pPoolSizes: [*]const VkDescriptorPoolSize,
};

pub const VkDescriptorPoolSize = extern struct {
    type: VkDescriptorType,
    descriptorCount: u32,
};

pub const VkDescriptorSetAllocateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    descriptorPool: VkDescriptorPool,
    descriptorSetCount: u32,
    pSetLayouts: [*]const VkDescriptorSetLayout,
};

pub const VkWriteDescriptorSet = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    dstSet: VkDescriptorSet,
    dstBinding: u32,
    dstArrayElement: u32,
    descriptorCount: u32,
    descriptorType: VkDescriptorType,
    pImageInfo: ?[*]const VkDescriptorImageInfo = null,
    pBufferInfo: ?[*]const VkDescriptorBufferInfo = null,
    pTexelBufferView: ?[*]const VkBufferView = null,
};

pub const VkDescriptorImageInfo = extern struct {
    sampler: VkSampler,
    imageView: VkImageView,
    imageLayout: VkImageLayout,
};

pub const VkDescriptorBufferInfo = extern struct {
    buffer: VkBuffer,
    offset: VkDeviceSize,
    range: VkDeviceSize,
};

pub const VkBufferView = *opaque {};

pub const VkCopyDescriptorSet = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    srcSet: VkDescriptorSet,
    srcBinding: u32,
    srcArrayElement: u32,
    dstSet: VkDescriptorSet,
    dstBinding: u32,
    dstArrayElement: u32,
    descriptorCount: u32,
};

pub const VkRenderPassBeginInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque = null,
    renderPass: VkRenderPass,
    framebuffer: VkFramebuffer,
    renderArea: VkRect2D,
    clearValueCount: u32,
    pClearValues: ?[*]const VkClearValue,
};

pub const VkClearValue = extern union {
    color: VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

pub const VkClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

pub const VkClearDepthStencilValue = extern struct {
    depth: f32,
    stencil: u32,
};

pub const VkSubpassContents = enum(i32) {
    VK_SUBPASS_CONTENTS_INLINE = 0,
    VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS = 1,
    _,
};

pub const VkIndexType = enum(i32) {
    VK_INDEX_TYPE_UINT16 = 0,
    VK_INDEX_TYPE_UINT32 = 1,
    _,
};

// Missing structure type constants
pub const VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO = VkStructureType.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
pub const VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO = 30;
pub const VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO = 38;
pub const VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO = 28;
pub const VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO = 37;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO = 33;
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO = 34;
pub const VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET = 35;
pub const VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO = 18;
pub const VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO = 19;
pub const VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO = 20;
pub const VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO = 22;
pub const VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO = 23;
pub const VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO = 24;
pub const VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO = 26;
pub const VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO = 27;
pub const VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO = 43;

// Image usage flags
pub const VK_IMAGE_USAGE_TRANSFER_SRC_BIT = 0x00000001;
pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT = 0x00000002;
pub const VK_IMAGE_USAGE_SAMPLED_BIT = 0x00000004;
pub const VK_IMAGE_USAGE_STORAGE_BIT = 0x00000008;
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = 0x00000010;
pub const VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT = 0x00000020;
pub const VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT = 0x00000040;
pub const VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT = 0x00000080;

// Image aspect flags
pub const VK_IMAGE_ASPECT_COLOR_BIT = 0x00000001;
pub const VK_IMAGE_ASPECT_DEPTH_BIT = 0x00000002;
pub const VK_IMAGE_ASPECT_STENCIL_BIT = 0x00000004;
pub const VK_IMAGE_ASPECT_METADATA_BIT = 0x00000008;

// Additional image types
pub const VK_IMAGE_TYPE_1D = 0;
pub const VK_IMAGE_TYPE_2D = 1;
pub const VK_IMAGE_TYPE_3D = 2;

pub const VK_IMAGE_TILING_OPTIMAL = 0;
pub const VK_IMAGE_TILING_LINEAR = 1;

pub const VK_IMAGE_VIEW_TYPE_1D = 0;
pub const VK_IMAGE_VIEW_TYPE_2D = 1;
pub const VK_IMAGE_VIEW_TYPE_3D = 2;
pub const VK_IMAGE_VIEW_TYPE_CUBE = 3;
pub const VK_IMAGE_VIEW_TYPE_1D_ARRAY = 4;
pub const VK_IMAGE_VIEW_TYPE_2D_ARRAY = 5;
pub const VK_IMAGE_VIEW_TYPE_CUBE_ARRAY = 6;

// Component swizzle
pub const VK_COMPONENT_SWIZZLE_IDENTITY = 0;
pub const VK_COMPONENT_SWIZZLE_ZERO = 1;
pub const VK_COMPONENT_SWIZZLE_ONE = 2;
pub const VK_COMPONENT_SWIZZLE_R = 3;
pub const VK_COMPONENT_SWIZZLE_G = 4;
pub const VK_COMPONENT_SWIZZLE_B = 5;
pub const VK_COMPONENT_SWIZZLE_A = 6;

// Missing constants
pub const VK_SUBPASS_EXTERNAL: u32 = 0xFFFFFFFF;
pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT = 0x00000100;

// Missing functions
pub extern "vulkan-1" fn vkCmdCopyBuffer(
    commandBuffer: VkCommandBuffer,
    srcBuffer: VkBuffer,
    dstBuffer: VkBuffer,
    regionCount: u32,
    pRegions: [*]const VkBufferCopy,
) callconv(.C) void;

pub extern "vulkan-1" fn vkGetPhysicalDeviceMemoryProperties(
    physicalDevice: VkPhysicalDevice,
    pMemoryProperties: *VkPhysicalDeviceMemoryProperties,
) callconv(.C) void;

pub extern "vulkan-1" fn vkEnumerateInstanceLayerProperties(
    pPropertyCount: *u32,
    pProperties: ?[*]VkLayerProperties,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkEnumerateDeviceExtensionProperties(
    physicalDevice: VkPhysicalDevice,
    pLayerName: ?[*:0]const u8,
    pPropertyCount: *u32,
    pProperties: ?[*]VkExtensionProperties,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pSurfaceCapabilities: *VkSurfaceCapabilitiesKHR,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkGetPhysicalDeviceSurfaceFormatsKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pSurfaceFormatCount: *u32,
    pSurfaceFormats: ?[*]VkSurfaceFormatKHR,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkGetPhysicalDeviceSurfacePresentModesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pPresentModeCount: *u32,
    pPresentModes: ?[*]VkPresentModeKHR,
) callconv(.C) VkResult;

pub const VkLayerProperties = extern struct {
    layerName: [256]u8,
    specVersion: u32,
    implementationVersion: u32,
    description: [256]u8,
};

pub const VkExtensionProperties = extern struct {
    extensionName: [256]u8,
    specVersion: u32,
};

// Surface capabilities and formats are already defined below

// Missing debug utils constants
pub const VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT = 0x00000001;
pub const VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT = 0x00000010;
pub const VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT = 0x00000100;
pub const VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT = 0x00001000;

pub const VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT = 0x00000001;
pub const VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT = 0x00000002;
pub const VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT = 0x00000004;

pub const VkDebugUtilsMessageSeverityFlagBitsEXT = VkFlags;
pub const VkDebugUtilsMessageTypeFlagsEXT = VkFlags;

pub const VkDebugUtilsMessengerCallbackDataEXT = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: VkFlags,
    pMessageIdName: ?[*:0]const u8,
    messageIdNumber: i32,
    pMessage: [*:0]const u8,
    queueLabelCount: u32,
    pQueueLabels: ?[*]const VkDebugUtilsLabelEXT,
    cmdBufLabelCount: u32,
    pCmdBufLabels: ?[*]const VkDebugUtilsLabelEXT,
    objectCount: u32,
    pObjects: ?[*]const VkDebugUtilsObjectNameInfoEXT,
};

pub const VkDebugUtilsLabelEXT = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    pLabelName: [*:0]const u8,
    color: [4]f32,
};

pub const VkDebugUtilsObjectNameInfoEXT = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    objectType: VkObjectType,
    objectHandle: u64,
    pObjectName: ?[*:0]const u8,
};

pub const VkObjectType = enum(i32) {
    VK_OBJECT_TYPE_UNKNOWN = 0,
    VK_OBJECT_TYPE_INSTANCE = 1,
    VK_OBJECT_TYPE_PHYSICAL_DEVICE = 2,
    VK_OBJECT_TYPE_DEVICE = 3,
    VK_OBJECT_TYPE_QUEUE = 4,
    VK_OBJECT_TYPE_SEMAPHORE = 5,
    VK_OBJECT_TYPE_COMMAND_BUFFER = 6,
    VK_OBJECT_TYPE_FENCE = 7,
    VK_OBJECT_TYPE_DEVICE_MEMORY = 8,
    VK_OBJECT_TYPE_BUFFER = 9,
    VK_OBJECT_TYPE_IMAGE = 10,
    VK_OBJECT_TYPE_EVENT = 11,
    VK_OBJECT_TYPE_QUERY_POOL = 12,
    VK_OBJECT_TYPE_BUFFER_VIEW = 13,
    VK_OBJECT_TYPE_IMAGE_VIEW = 14,
    VK_OBJECT_TYPE_SHADER_MODULE = 15,
    VK_OBJECT_TYPE_PIPELINE_CACHE = 16,
    VK_OBJECT_TYPE_PIPELINE_LAYOUT = 17,
    VK_OBJECT_TYPE_RENDER_PASS = 18,
    VK_OBJECT_TYPE_PIPELINE = 19,
    VK_OBJECT_TYPE_DESCRIPTOR_SET_LAYOUT = 20,
    VK_OBJECT_TYPE_SAMPLER = 21,
    VK_OBJECT_TYPE_DESCRIPTOR_POOL = 22,
    VK_OBJECT_TYPE_DESCRIPTOR_SET = 23,
    VK_OBJECT_TYPE_FRAMEBUFFER = 24,
    VK_OBJECT_TYPE_COMMAND_POOL = 25,
    VK_OBJECT_TYPE_SURFACE_KHR = 1000000000,
    VK_OBJECT_TYPE_SWAPCHAIN_KHR = 1000001000,
    VK_OBJECT_TYPE_DEBUG_UTILS_MESSENGER_EXT = 1000128000,
    _,
};

// Command buffer constants are already defined above

// Missing component swizzle enum
pub const VkComponentSwizzle = enum(i32) {
    VK_COMPONENT_SWIZZLE_IDENTITY = 0,
    VK_COMPONENT_SWIZZLE_ZERO = 1,
    VK_COMPONENT_SWIZZLE_ONE = 2,
    VK_COMPONENT_SWIZZLE_R = 3,
    VK_COMPONENT_SWIZZLE_G = 4,
    VK_COMPONENT_SWIZZLE_B = 5,
    VK_COMPONENT_SWIZZLE_A = 6,
    _,
};

pub const VkComponentMapping = extern struct {
    r: VkComponentSwizzle,
    g: VkComponentSwizzle,
    b: VkComponentSwizzle,
    a: VkComponentSwizzle,
};

pub const VkImageSubresourceRange = extern struct {
    aspectMask: VkImageAspectFlags,
    baseMipLevel: u32,
    levelCount: u32,
    baseArrayLayer: u32,
    layerCount: u32,
};

pub const VkImageAspectFlags = VkFlags;

// Missing image view type enum
pub const VkImageViewType = enum(i32) {
    VK_IMAGE_VIEW_TYPE_1D = 0,
    VK_IMAGE_VIEW_TYPE_2D = 1,
    VK_IMAGE_VIEW_TYPE_3D = 2,
    VK_IMAGE_VIEW_TYPE_CUBE = 3,
    VK_IMAGE_VIEW_TYPE_1D_ARRAY = 4,
    VK_IMAGE_VIEW_TYPE_2D_ARRAY = 5,
    VK_IMAGE_VIEW_TYPE_CUBE_ARRAY = 6,
    _,
};
