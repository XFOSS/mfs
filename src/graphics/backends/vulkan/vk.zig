const std = @import("std");

// Unified Vulkan types, constants, and FFI for the codebase
// This file is the single source of truth for all Vulkan types/constants/FFI

pub const MAX_FRAMES_IN_FLIGHT = 2;

// Vulkan API version
pub const VK_API_VERSION_1_0 = (1 << 22) | (0 << 12) | 0;
pub const VK_API_VERSION_1_1 = (1 << 22) | (1 << 12) | 0;
pub const VK_API_VERSION_1_2 = (1 << 22) | (2 << 12) | 0;
pub const VK_API_VERSION_1_3 = (1 << 22) | (3 << 12) | 0;

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

// Vulkan basic types
pub const VkBool32 = u32;
pub const VkDeviceSize = u64;
pub const VkFlags = u32;
pub const VkSampleCountFlags = VkFlags;
pub const VkMemoryPropertyFlags = VkFlags;
pub const VkPipelineStageFlags = VkFlags;

// Vulkan constants
pub const VK_TRUE = 1;
pub const VK_FALSE = 0;
pub const VK_NULL_HANDLE = @as(?*anyopaque, null);

// Structure types
pub const VkStructureType = enum(i32) {
    VK_STRUCTURE_TYPE_APPLICATION_INFO = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1,
    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = 2,
    VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3,
    VK_STRUCTURE_TYPE_SUBMIT_INFO = 4,
    VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO = 5,
    VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE = 6,
    VK_STRUCTURE_TYPE_BIND_SPARSE_INFO = 7,
    VK_STRUCTURE_TYPE_FENCE_CREATE_INFO = 8,
    VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO = 9,
    VK_STRUCTURE_TYPE_EVENT_CREATE_INFO = 10,
    VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO = 11,
    VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO = 12,
    VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO = 13,
    VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO = 14,
    VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO = 15,
    VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO = 16,
    VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO = 17,
    VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO = 18,
    VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO = 19,
    VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO = 20,
    VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO = 21,
    VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO = 22,
    VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO = 23,
    VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO = 24,
    VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO = 25,
    VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO = 26,
    VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO = 27,
    VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO = 28,
    VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO = 29,
    VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO = 30,
    VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO = 31,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32,
    VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO = 33,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO = 34,
    VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET = 35,
    VK_STRUCTURE_TYPE_COPY_DESCRIPTOR_SET = 36,
    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO = 37,
    VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO = 38,
    VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO = 39,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO = 40,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO = 41,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO = 42,
    VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO = 43,
    VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER = 44,
    VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER = 45,
    VK_STRUCTURE_TYPE_MEMORY_BARRIER = 46,
    VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO = 47,
    VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO = 48,
    VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = 1000001000,
    VK_STRUCTURE_TYPE_PRESENT_INFO_KHR = 1000001001,
    VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR = 1000009000,
    _,
};

pub const VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO = VkStructureType.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
pub const VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO = VkStructureType.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO = VkStructureType.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
pub const VK_STRUCTURE_TYPE_SUBMIT_INFO = VkStructureType.VK_STRUCTURE_TYPE_SUBMIT_INFO;

// Command buffer level constants
pub const VK_COMMAND_BUFFER_LEVEL_PRIMARY = 0;
pub const VK_COMMAND_BUFFER_LEVEL_SECONDARY = 1;

// Command buffer usage flags
pub const VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT = 0x00000001;
pub const VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT = 0x00000002;
pub const VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT = 0x00000004;

// Pipeline stage flags
pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT = 0x00000001;
pub const VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT = 0x00000002;
pub const VK_PIPELINE_STAGE_VERTEX_INPUT_BIT = 0x00000004;
pub const VK_PIPELINE_STAGE_VERTEX_SHADER_BIT = 0x00000008;
pub const VK_PIPELINE_STAGE_TESSELLATION_CONTROL_SHADER_BIT = 0x00000010;
pub const VK_PIPELINE_STAGE_TESSELLATION_EVALUATION_SHADER_BIT = 0x00000020;
pub const VK_PIPELINE_STAGE_GEOMETRY_SHADER_BIT = 0x00000040;
pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT = 0x00000080;
pub const VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT = 0x00000100;
pub const VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT = 0x00000200;
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT = 0x00000400;
pub const VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT = 0x00000800;
pub const VK_PIPELINE_STAGE_TRANSFER_BIT = 0x00001000;
pub const VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT = 0x00002000;
pub const VK_PIPELINE_STAGE_HOST_BIT = 0x00004000;
pub const VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT = 0x00008000;
pub const VK_PIPELINE_STAGE_ALL_COMMANDS_BIT = 0x00010000;

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

// Vulkan enums
pub const VkFormat = enum(i32) {
    VK_FORMAT_UNDEFINED = 0,
    VK_FORMAT_R4G4_UNORM_PACK8 = 1,
    VK_FORMAT_R4G4B4A4_UNORM_PACK16 = 2,
    VK_FORMAT_B4G4R4A4_UNORM_PACK16 = 3,
    VK_FORMAT_R5G6B5_UNORM_PACK16 = 4,
    VK_FORMAT_B5G6R5_UNORM_PACK16 = 5,
    VK_FORMAT_R5G5B5A1_UNORM_PACK16 = 6,
    VK_FORMAT_B5G5R5A1_UNORM_PACK16 = 7,
    VK_FORMAT_A1R5G5B5_UNORM_PACK16 = 8,
    VK_FORMAT_R8_UNORM = 9,
    VK_FORMAT_R8_SNORM = 10,
    VK_FORMAT_R8_USCALED = 11,
    VK_FORMAT_R8_SSCALED = 12,
    VK_FORMAT_R8_UINT = 13,
    VK_FORMAT_R8_SINT = 14,
    VK_FORMAT_R8_SRGB = 15,
    VK_FORMAT_R8G8_UNORM = 16,
    VK_FORMAT_R8G8_SNORM = 17,
    VK_FORMAT_R8G8_USCALED = 18,
    VK_FORMAT_R8G8_SSCALED = 19,
    VK_FORMAT_R8G8_UINT = 20,
    VK_FORMAT_R8G8_SINT = 21,
    VK_FORMAT_R8G8_SRGB = 22,
    VK_FORMAT_R8G8B8_UNORM = 23,
    VK_FORMAT_R8G8B8_SNORM = 24,
    VK_FORMAT_R8G8B8_USCALED = 25,
    VK_FORMAT_R8G8B8_SSCALED = 26,
    VK_FORMAT_R8G8B8_UINT = 27,
    VK_FORMAT_R8G8B8_SINT = 28,
    VK_FORMAT_R8G8B8_SRGB = 29,
    VK_FORMAT_B8G8R8_UNORM = 30,
    VK_FORMAT_B8G8R8_SNORM = 31,
    VK_FORMAT_B8G8R8_USCALED = 32,
    VK_FORMAT_B8G8R8_SSCALED = 33,
    VK_FORMAT_B8G8R8_UINT = 34,
    VK_FORMAT_B8G8R8_SINT = 35,
    VK_FORMAT_B8G8R8_SRGB = 36,
    VK_FORMAT_R8G8B8A8_UNORM = 37,
    VK_FORMAT_R8G8B8A8_SNORM = 38,
    VK_FORMAT_R8G8B8A8_USCALED = 39,
    VK_FORMAT_R8G8B8A8_SSCALED = 40,
    VK_FORMAT_R8G8B8A8_UINT = 41,
    VK_FORMAT_R8G8B8A8_SINT = 42,
    VK_FORMAT_R8G8B8A8_SRGB = 43,
    VK_FORMAT_B8G8R8A8_UNORM = 44,
    VK_FORMAT_B8G8R8A8_SNORM = 45,
    VK_FORMAT_B8G8R8A8_USCALED = 46,
    VK_FORMAT_B8G8R8A8_SSCALED = 47,
    VK_FORMAT_B8G8R8A8_UINT = 48,
    VK_FORMAT_B8G8R8A8_SINT = 49,
    VK_FORMAT_B8G8R8A8_SRGB = 50,
    VK_FORMAT_D16_UNORM = 124,
    VK_FORMAT_D32_SFLOAT = 126,
    VK_FORMAT_D24_UNORM_S8_UINT = 129,
    VK_FORMAT_D32_SFLOAT_S8_UINT = 130,
    _,
};

pub const VkColorSpaceKHR = enum(i32) {
    VK_COLOR_SPACE_SRGB_NONLINEAR_KHR = 0,
    VK_COLORSPACE_SRGB_NONLINEAR_KHR = 0,
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
    pNext: ?*const anyopaque,
    pApplicationName: ?[*:0]const u8,
    applicationVersion: u32,
    pEngineName: ?[*:0]const u8,
    engineVersion: u32,
    apiVersion: u32,
};

pub const VkInstanceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: VkFlags,
    pApplicationInfo: ?*const VkApplicationInfo,
    enabledLayerCount: u32,
    ppEnabledLayerNames: ?[*]const [*:0]const u8,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
};

pub const VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: VkFlags,
    queueFamilyIndex: u32,
    queueCount: u32,
    pQueuePriorities: [*]const f32,
};

pub const VkDeviceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: VkFlags,
    queueCreateInfoCount: u32,
    pQueueCreateInfos: [*]const VkDeviceQueueCreateInfo,
    enabledLayerCount: u32,
    ppEnabledLayerNames: ?[*]const [*:0]const u8,
    enabledExtensionCount: u32,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8,
    pEnabledFeatures: ?*const anyopaque,
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
    pNext: ?*const anyopaque,
    flags: VkFlags,
    size: VkDeviceSize,
    usage: VkFlags,
    sharingMode: u32,
    queueFamilyIndexCount: u32,
    pQueueFamilyIndices: ?[*]const u32,
};

pub const VkMemoryAllocateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    allocationSize: VkDeviceSize,
    memoryTypeIndex: u32,
};

// Command buffer
pub const VkCommandPoolCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: VkFlags,
    queueFamilyIndex: u32,
};

pub const VkCommandBufferAllocateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    commandPool: VkCommandPool,
    level: u32,
    commandBufferCount: u32,
};

pub const VkCommandBufferBeginInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: VkFlags,
    pInheritanceInfo: ?*const anyopaque,
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
    pNext: ?*const anyopaque,
    flags: u32,
    surface: VkSurfaceKHR,
    minImageCount: u32,
    imageFormat: VkFormat,
    imageColorSpace: VkColorSpaceKHR,
    imageExtent: VkExtent2D,
    imageArrayLayers: u32,
    imageUsage: u32,
    imageSharingMode: u32,
    queueFamilyIndexCount: u32,
    pQueueFamilyIndices: ?[*]const u32,
    preTransform: u32,
    compositeAlpha: u32,
    presentMode: VkPresentModeKHR,
    clipped: VkBool32,
    oldSwapchain: VkSwapchainKHR,
};

pub const VkFenceCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
};

pub const VkSemaphoreCreateInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    flags: u32,
};

pub const VkSubmitInfo = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    waitSemaphoreCount: u32,
    pWaitSemaphores: ?[*]const VkSemaphore,
    pWaitDstStageMask: ?[*]const VkFlags,
    commandBufferCount: u32,
    pCommandBuffers: [*]const VkCommandBuffer,
    signalSemaphoreCount: u32,
    pSignalSemaphores: ?[*]const VkSemaphore,
};

pub const VkPresentInfoKHR = extern struct {
    sType: VkStructureType,
    pNext: ?*const anyopaque,
    waitSemaphoreCount: u32,
    pWaitSemaphores: [*]const VkSemaphore,
    swapchainCount: u32,
    pSwapchains: [*]const VkSwapchainKHR,
    pImageIndices: [*]const u32,
    pResults: ?[*]VkResult,
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
    pNext: ?*const anyopaque,
    flags: VkFlags,
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

extern "vulkan-1" fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pSurfaceCapabilities: *VkSurfaceCapabilitiesKHR,
) callconv(.C) VkResult;

extern "vulkan-1" fn vkGetPhysicalDeviceSurfaceFormatsKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pSurfaceFormatCount: *u32,
    pSurfaceFormats: ?[*]VkSurfaceFormatKHR,
) callconv(.C) VkResult;

extern "vulkan-1" fn vkGetPhysicalDeviceSurfacePresentModesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
    pPresentModeCount: *u32,
    pPresentModes: ?[*]VkPresentModeKHR,
) callconv(.C) VkResult;

extern "vulkan-1" fn vkCreateSwapchainKHR(
    device: VkDevice,
    pCreateInfo: *const VkSwapchainCreateInfoKHR,
    pAllocator: ?*const anyopaque,
    pSwapchain: *VkSwapchainKHR,
) callconv(.C) VkResult;

extern "vulkan-1" fn vkDestroySwapchainKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    pAllocator: ?*const anyopaque,
) callconv(.C) void;

extern "vulkan-1" fn vkGetSwapchainImagesKHR(
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

pub extern "vulkan-1" fn vkGetPhysicalDeviceMemoryProperties(
    physicalDevice: VkPhysicalDevice,
    pMemoryProperties: *VkPhysicalDeviceMemoryProperties,
) callconv(.C) void;

pub extern "vulkan-1" fn vkCmdCopyBuffer(
    commandBuffer: VkCommandBuffer,
    srcBuffer: VkBuffer,
    dstBuffer: VkBuffer,
    regionCount: u32,
    pRegions: [*]const VkBufferCopy,
) callconv(.C) void;

pub extern "vulkan-1" fn vkQueueWaitIdle(
    queue: VkQueue,
) callconv(.C) VkResult;

pub extern "vulkan-1" fn vkFreeCommandBuffers(
    device: VkDevice,
    commandPool: VkCommandPool,
    commandBufferCount: u32,
    pCommandBuffers: [*]const VkCommandBuffer,
) callconv(.C) void;

// Helper functions
pub fn createInstance(app_info: *const VkApplicationInfo, extensions: []const [*:0]const u8) !VkInstance {
    const create_info = VkInstanceCreateInfo{
        .sType = VkStructureType.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = app_info,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = if (extensions.len > 0) extensions.ptr else null,
    };

    var instance: VkInstance = undefined;
    const result = vkCreateInstance(&create_info, null, &instance);

    if (result != VkResult.VK_SUCCESS) {
        return error.InstanceCreationFailed;
    }

    return instance;
}

pub fn pickPhysicalDevice(instance: VkInstance) !VkPhysicalDevice {
    var device_count: u32 = 0;
    _ = vkEnumeratePhysicalDevices(instance, &device_count, null);

    if (device_count == 0) {
        return error.NoPhysicalDevices;
    }

    const devices = std.heap.page_allocator.alloc(VkPhysicalDevice, device_count) catch return error.OutOfMemory;
    defer std.heap.page_allocator.free(devices);

    _ = vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr);

    // For simplicity, just return the first device
    return devices[0];
}

pub fn createLogicalDevice(physical_device: VkPhysicalDevice, queue_family_index: u32) !VkDevice {
    const queue_priority: f32 = 1.0;
    const queue_create_info = VkDeviceQueueCreateInfo{
        .sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = queue_family_index,
        .queueCount = 1,
        .pQueuePriorities = @ptrCast(&queue_priority),
    };

    const device_extensions = [_][*:0]const u8{
        "VK_KHR_swapchain",
    };

    const create_info = VkDeviceCreateInfo{
        .sType = VkStructureType.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = @ptrCast(&queue_create_info),
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = device_extensions.len,
        .ppEnabledExtensionNames = &device_extensions,
        .pEnabledFeatures = null,
    };

    var device: VkDevice = undefined;
    const result = vkCreateDevice(physical_device, &create_info, null, &device);

    if (result != VkResult.VK_SUCCESS) {
        return error.DeviceCreationFailed;
    }

    return device;
}

pub fn createWin32Surface(instance: VkInstance, hinstance: *anyopaque, hwnd: *anyopaque) !VkSurfaceKHR {
    const create_info = VkWin32SurfaceCreateInfoKHR{
        .sType = VkStructureType.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
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

// Subpass contents constants
pub const VK_SUBPASS_CONTENTS_INLINE = 0;
pub const VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS = 1;
