const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const interface = @import("../../interface.zig");
const types = @import("../../types.zig");
const common = @import("../../common.zig");
const vulkan_dispatch = @import("vulkan_dispatch.zig");
const vk = @import("vk.zig");

// Common error types for Vulkan operations
pub const VulkanError = error{
    LoaderNotFound,
    InstanceCreationFailed,
    NoSuitableDevice,
    InitializationFailed,
    SurfaceCreationFailed,
    SwapchainCreationFailed,
    PipelineCreationFailed,
    OutOfMemory,
    NoPhysicalDeviceFound,
    NoGraphicsQueueFound,
    DeviceCreationFailed,
    CommandPoolCreationFailed,
    CommandBufferAllocationFailed,
    BufferCreationFailed,
    MemoryAllocationFailed,
    MemoryBindingFailed,
    MemoryMappingFailed,
    NoSuitableMemoryType,
    ImageCreationFailed,
    ImageViewCreationFailed,
    UnsupportedLayoutTransition,
    FailedToAllocateCommandBuffers,
    FailedToBeginCommandBuffer,
    FailedToEndCommandBuffer,
    FailedToSubmitQueue,
    FailedToWaitForQueue,
};

// Queue family indices for Vulkan device queues
pub const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    pub fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

// Swapchain support details
pub const SwapchainSupportDetails = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats: []vk.VkSurfaceFormatKHR,
    present_modes: []vk.VkPresentModeKHR,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        physical_device: vk.VkPhysicalDevice,
        device: vk.VkDevice,
        surface: vk.VkSurfaceKHR,
        width: u32,
        height: u32,
        vsync: bool,
    ) !*SwapchainSupportDetails {
        _ = physical_device;
        _ = device;
        _ = surface;
        _ = width;
        _ = height;
        _ = vsync;

        // Create a new swapchain
        const self = try allocator.create(SwapchainSupportDetails);
        self.allocator = allocator;

        // TODO: Implement actual swapchain creation logic
        self.capabilities = undefined;
        self.formats = &[_]vk.VkSurfaceFormatKHR{};
        self.present_modes = &[_]vk.VkPresentModeKHR{};

        return self;
    }

    pub fn deinit(self: *SwapchainSupportDetails) void {
        self.allocator.free(self.formats);
        self.allocator.free(self.present_modes);
        self.allocator.destroy(self);
    }
};

// Vulkan device wrapper
pub const VulkanDevice = struct {
    instance: vk.VkInstance,
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    graphics_queue_family: u32,
    dispatch: *vulkan_dispatch.Dispatch,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.allocator = allocator;

        // Initialize Vulkan dispatch
        self.dispatch = try vulkan_dispatch.Dispatch.init(allocator);

        // Create instance
        const app_info = vk.VkApplicationInfo{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pNext = null,
            .pApplicationName = "MFS Engine",
            .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "MFS",
            .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = vk.VK_API_VERSION_1_3,
        };

        const instance_create_info = vk.VkInstanceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = 0,
            .ppEnabledExtensionNames = null,
        };

        const result = self.dispatch.vkCreateInstance(&instance_create_info, null, &self.instance);
        if (result != vk.VK_SUCCESS) {
            return VulkanError.InstanceCreationFailed;
        }

        // Load instance-level functions
        try self.dispatch.loadInstance(self.instance);

        // Select physical device
        var device_count: u32 = 0;
        _ = try self.dispatch.vkEnumeratePhysicalDevices(self.instance, &device_count, null);
        if (device_count == 0) {
            return VulkanError.NoPhysicalDeviceFound;
        }

        const physical_devices = try allocator.alloc(vk.VkPhysicalDevice, device_count);
        defer allocator.free(physical_devices);
        _ = try self.dispatch.vkEnumeratePhysicalDevices(self.instance, &device_count, physical_devices.ptr);

        // Just pick the first device for now
        self.physical_device = physical_devices[0];

        // Find graphics queue family
        var queue_family_count: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(self.physical_device, &queue_family_count, null);

        const queue_families = try allocator.alloc(vk.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);
        vk.vkGetPhysicalDeviceQueueFamilyProperties(self.physical_device, &queue_family_count, queue_families.ptr);

        // Find a queue family that supports graphics
        var found_graphics_queue = false;
        for (queue_families, 0..) |props, i| {
            if (props.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                self.graphics_queue_family = @intCast(i);
                found_graphics_queue = true;
                break;
            }
        }

        if (!found_graphics_queue) {
            return VulkanError.NoGraphicsQueueFound;
        }

        // Create logical device
        const priority = [_]f32{1.0};
        const queue_create_info = vk.VkDeviceQueueCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = self.graphics_queue_family,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };

        const device_create_info = vk.VkDeviceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_create_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = 0,
            .ppEnabledExtensionNames = null,
            .pEnabledFeatures = null,
        };

        const device_result = self.dispatch.vkCreateDevice(self.physical_device, &device_create_info, null, &self.device);
        if (device_result != vk.VK_SUCCESS) {
            return VulkanError.DeviceCreationFailed;
        }

        // Load device-level functions
        try self.dispatch.loadDevice(self.device);

        // Get graphics queue
        self.dispatch.vkGetDeviceQueue(self.device, self.graphics_queue_family, 0, &self.graphics_queue);

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.device != null) {
            vk.vkDestroyDevice(self.device, null);
        }
        if (self.instance != null) {
            vk.vkDestroyInstance(self.instance, null);
        }
        self.allocator.destroy(self);
    }
};

// Command pool for allocating command buffers
pub const CommandPool = struct {
    pool: vk.VkCommandPool,
    device: vk.VkDevice,

    const Self = @This();

    pub fn init(device: vk.VkDevice, queue_family: u32) !Self {
        const pool_info = vk.VkCommandPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queue_family,
        };

        var pool: vk.VkCommandPool = undefined;
        if (vk.vkCreateCommandPool(device, &pool_info, null, &pool) != vk.VK_SUCCESS) {
            return VulkanError.CommandPoolCreationFailed;
        }

        return Self{
            .pool = pool,
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.pool != null) {
            vk.vkDestroyCommandPool(self.device, self.pool, null);
            self.pool = null;
        }
    }

    pub fn allocateCommandBuffer(self: *Self) !vk.VkCommandBuffer {
        var command_buffer: vk.VkCommandBuffer = undefined;
        if (vk.vkAllocateCommandBuffers(self.device, &vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = self.pool,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        }, &command_buffer) != vk.VK_SUCCESS) {
            return VulkanError.CommandBufferAllocationFailed;
        }

        return command_buffer;
    }
};

// Pipeline for rendering operations
pub const Pipeline = struct {
    pipeline: vk.VkPipeline,
    device: vk.VkDevice,

    const Self = @This();

    pub fn init(
        device: vk.VkDevice,
        render_pass: vk.VkRenderPass,
        vertex_bindings: []const vk.VkVertexInputBindingDescription,
        binding_count: u32,
        vertex_attrs: []const vk.VkVertexInputAttributeDescription,
        attr_count: u32,
        topology: vk.VkPrimitiveTopology,
        blend_state: bool,
        depth_test: bool,
    ) !Self {
        _ = render_pass;
        _ = vertex_bindings;
        _ = binding_count;
        _ = vertex_attrs;
        _ = attr_count;
        _ = topology;
        _ = blend_state;
        _ = depth_test;
        // TODO: Implement pipeline creation
        return Self{
            .pipeline = undefined,
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.pipeline != null) {
            vk.vkDestroyPipeline(self.device, self.pipeline, null);
        }
    }

    pub fn bind(self: *const Self, cmd: vk.VkCommandBuffer) void {
        vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
    }
};

// Buffer for memory operations
pub const Buffer = struct {
    buffer: vk.VkBuffer,
    memory: vk.VkDeviceMemory,
    device: vk.VkDevice,
    size: u64,
    mapped: bool = false,

    const Self = @This();

    pub fn init(device: vk.VkDevice, physical_device: vk.VkPhysicalDevice, size: u64, usage: vk.VkBufferUsageFlags) !Self {
        // Create the buffer
        const buffer_info = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = size,
            .usage = usage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var buffer: vk.VkBuffer = undefined;
        if (vk.vkCreateBuffer(device, &buffer_info, null, &buffer) != vk.VK_SUCCESS) {
            return VulkanError.BufferCreationFailed;
        }

        // Get memory requirements
        var mem_requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(device, buffer, &mem_requirements);

        // Find suitable memory type
        var memory_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

        const memory_type = try findMemoryType(
            mem_requirements.memoryTypeBits,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &memory_properties,
        );

        // Allocate memory
        const alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = memory_type,
        };

        var memory: vk.VkDeviceMemory = undefined;
        if (vk.vkAllocateMemory(device, &alloc_info, null, &memory) != vk.VK_SUCCESS) {
            vk.vkDestroyBuffer(device, buffer, null);
            return VulkanError.MemoryAllocationFailed;
        }

        // Bind buffer memory
        if (vk.vkBindBufferMemory(device, buffer, memory, 0) != vk.VK_SUCCESS) {
            vk.vkDestroyBuffer(device, buffer, null);
            vk.vkFreeMemory(device, memory, null);
            return VulkanError.MemoryBindingFailed;
        }

        return Self{
            .buffer = buffer,
            .memory = memory,
            .device = device,
            .size = size,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.mapped) {
            self.unmap();
        }
        if (self.buffer != null) {
            vk.vkDestroyBuffer(self.device, self.buffer, null);
            self.buffer = null;
        }
        if (self.memory != null) {
            vk.vkFreeMemory(self.device, self.memory, null);
            self.memory = null;
        }
    }

    pub fn map(self: *Self) ![]u8 {
        var data: ?*anyopaque = undefined;
        if (vk.vkMapMemory(self.device, self.memory, 0, self.size, 0, &data) != vk.VK_SUCCESS) {
            return VulkanError.MemoryMappingFailed;
        }
        self.mapped = true;
        return @as([*]u8, @ptrCast(data.?))[0..self.size];
    }

    pub fn unmap(self: *Self) void {
        if (self.mapped) {
            vk.vkUnmapMemory(self.device, self.memory);
            self.mapped = false;
        }
    }
};

// Image for texture operations
pub const Image = struct {
    image: vk.VkImage,
    view: vk.VkImageView,
    memory: vk.VkDeviceMemory,
    device: vk.VkDevice,
    width: u32,
    height: u32,
    format: vk.VkFormat,
    mip_levels: u32,
    array_layers: u32,

    const Self = @This();

    pub fn init(
        device: vk.VkDevice,
        physical_device: vk.VkPhysicalDevice,
        width: u32,
        height: u32,
        format: vk.VkFormat,
        usage: vk.VkImageUsageFlags,
        mip_levels: u32,
        array_layers: u32,
    ) !Self {
        // Create image
        const image_create_info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = format,
            .extent = vk.VkExtent3D{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .mipLevels = mip_levels,
            .arrayLayers = array_layers,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
            .usage = usage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        };

        var image: vk.VkImage = undefined;
        if (vk.vkCreateImage(device, &image_create_info, null, &image) != vk.VK_SUCCESS) {
            return VulkanError.ImageCreationFailed;
        }

        // Get memory requirements
        var mem_requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(device, image, &mem_requirements);

        // Find suitable memory type
        var memory_properties: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

        const memory_type = try findMemoryType(
            mem_requirements.memoryTypeBits,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &memory_properties,
        );

        // Allocate memory
        const alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = memory_type,
        };

        var memory: vk.VkDeviceMemory = undefined;
        if (vk.vkAllocateMemory(device, &alloc_info, null, &memory) != vk.VK_SUCCESS) {
            vk.vkDestroyImage(device, image, null);
            return VulkanError.MemoryAllocationFailed;
        }

        // Bind image memory
        if (vk.vkBindImageMemory(device, image, memory, 0) != vk.VK_SUCCESS) {
            vk.vkDestroyImage(device, image, null);
            vk.vkFreeMemory(device, memory, null);
            return VulkanError.MemoryBindingFailed;
        }

        // Create image view
        const components = vk.VkComponentMapping{
            .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        };

        const subresource_range = vk.VkImageSubresourceRange{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = mip_levels,
            .baseArrayLayer = 0,
            .layerCount = array_layers,
        };

        const view_create_info = vk.VkImageViewCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = image,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .components = components,
            .subresourceRange = subresource_range,
        };

        var view: vk.VkImageView = undefined;
        if (vk.vkCreateImageView(device, &view_create_info, null, &view) != vk.VK_SUCCESS) {
            vk.vkDestroyImage(device, image, null);
            vk.vkFreeMemory(device, memory, null);
            return VulkanError.ImageViewCreationFailed;
        }

        return Self{
            .image = image,
            .view = view,
            .memory = memory,
            .device = device,
            .width = width,
            .height = height,
            .format = format,
            .mip_levels = mip_levels,
            .array_layers = array_layers,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.view != vk.VK_NULL_HANDLE) {
            vk.vkDestroyImageView(self.device, self.view, null);
            self.view = vk.VK_NULL_HANDLE;
        }
        if (self.image != vk.VK_NULL_HANDLE) {
            vk.vkDestroyImage(self.device, self.image, null);
            self.image = vk.VK_NULL_HANDLE;
        }
        if (self.memory != vk.VK_NULL_HANDLE) {
            vk.vkFreeMemory(self.device, self.memory, null);
            self.memory = vk.VK_NULL_HANDLE;
        }
    }
};

// VulkanRenderer wrapper
pub const VulkanRenderer = struct {
    allocator: std.mem.Allocator,
    device: *VulkanDevice,
    swapchain: *SwapchainSupportDetails,
    command_pool: CommandPool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        device: *VulkanDevice,
        swapchain: *SwapchainSupportDetails,
        command_pool: CommandPool,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .device = device,
            .swapchain = swapchain,
            .command_pool = command_pool,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};

// Helper function to find a suitable memory type
fn findMemoryType(type_filter: u32, properties: vk.VkMemoryPropertyFlags, memory_properties: *const vk.VkPhysicalDeviceMemoryProperties) !u32 {
    var i: u32 = 0;
    while (i < memory_properties.memoryTypeCount) : (i += 1) {
        const memory_type_flags = memory_properties.memoryTypes[i].propertyFlags;
        const type_bit_set = (type_filter & (@as(u32, 1) << i)) != 0;
        const properties_match = (memory_type_flags & properties) == properties;

        if (type_bit_set and properties_match) {
            return i;
        }
    }
    return VulkanError.NoSuitableMemoryType;
}

/// Vulkan backend implementation that uses the full Vulkan API
/// to provide high-performance graphics capabilities.
pub const VulkanBackend = struct {
    allocator: std.mem.Allocator,
    dispatch: *vulkan_dispatch.Dispatch,
    initialized: bool = false,

    // Core Vulkan objects
    device: ?VulkanDevice = null,
    renderer: ?VulkanRenderer = null,
    swapchain: ?SwapchainSupportDetails = null,

    // Resource management
    command_pool: ?CommandPool = null,
    current_command_buffer: ?vk.VkCommandBuffer = null,

    // Resource caches
    pipelines: std.AutoHashMap(u64, Pipeline),
    buffers: std.AutoHashMap(u64, Buffer),
    textures: std.AutoHashMap(u64, Image),

    // Performance tracking
    frame_count: u64 = 0,
    last_frame_time_ns: u64 = 0,

    const Self = @This();

    const vtable = interface.GraphicsBackend.VTable{
        .deinit = deinitImpl,
        .create_swap_chain = createSwapChainImpl,
        .resize_swap_chain = resizeSwapChainImpl,
        .present = presentImpl,
        .get_current_back_buffer = getCurrentBackBufferImpl,
        .create_texture = createTextureImpl,
        .create_buffer = createBufferImpl,
        .create_shader = createShaderImpl,
        .create_pipeline = createPipelineImpl,
        .create_render_target = createRenderTargetImpl,
        .update_buffer = updateBufferImpl,
        .update_texture = updateTextureImpl,
        .destroy_texture = destroyTextureImpl,
        .destroy_buffer = destroyBufferImpl,
        .destroy_shader = destroyShaderImpl,
        .destroy_render_target = destroyRenderTargetImpl,
        .create_command_buffer = createCommandBufferImpl,
        .begin_command_buffer = beginCommandBufferImpl,
        .end_command_buffer = endCommandBufferImpl,
        .submit_command_buffer = submitCommandBufferImpl,
        .begin_render_pass = beginRenderPassImpl,
        .end_render_pass = endRenderPassImpl,
        .set_viewport = setViewportImpl,
        .set_scissor = setScissorImpl,
        .bind_pipeline = bindPipelineImpl,
        .bind_vertex_buffer = bindVertexBufferImpl,
        .bind_index_buffer = bindIndexBufferImpl,
        .bind_texture = bindTextureImpl,
        .bind_uniform_buffer = bindUniformBufferImpl,
        .draw = drawImpl,
        .draw_indexed = drawIndexedImpl,
        .dispatch = dispatchImpl,
        .copy_buffer = copyBufferImpl,
        .copy_texture = copyTextureImpl,
        .copy_buffer_to_texture = copyBufferToTextureImpl,
        .copy_texture_to_buffer = copyTextureToBufferImpl,
        .resource_barrier = resourceBarrierImpl,
        .get_backend_info = getBackendInfoImpl,
        .set_debug_name = setDebugNameImpl,
        .begin_debug_group = beginDebugGroupImpl,
        .end_debug_group = endDebugGroupImpl,
    };

    /// Create and initialize a Vulkan backend, returning a pointer to interface.GraphicsBackend.
    /// Returns BackendNotSupported if Vulkan is unavailable.
    pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        if (!build_options.vulkan_available) {
            return interface.GraphicsBackendError.BackendNotSupported;
        }
        // Create the backend instance
        const backend = try allocator.create(VulkanBackend);

        // Initialize Vulkan function dispatch
        backend.dispatch = try vulkan_dispatch.Dispatch.init(allocator);

        // Initialize Vulkan state
        backend.* = VulkanBackend{
            .allocator = allocator,
            .dispatch = backend.dispatch,
            .initialized = false,
            .pipelines = std.AutoHashMap(u64, Pipeline).init(allocator),
            .buffers = std.AutoHashMap(u64, Buffer).init(allocator),
            .textures = std.AutoHashMap(u64, Image).init(allocator),
        };

        // Create core Vulkan objects
        backend.device = try VulkanDevice.init(allocator);
        backend.command_pool = try CommandPool.init(backend.device.?.device, backend.device.?.graphics_queue_family);

        // Create the interface object
        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .vulkan,
            .vtable = &VulkanBackend.vtable,
            .impl_data = backend,
            .initialized = true,
        };

        backend.initialized = true;
        std.log.info("Enhanced Vulkan backend initialized", .{});
        return graphics_backend;
    }

    // Implementation of backend interface
    fn deinitImpl(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Clean up resources
        self.pipelines.deinit();
        self.buffers.deinit();
        self.textures.deinit();

        // Clean up core Vulkan objects
        if (self.command_pool) |*cmd_pool| {
            cmd_pool.deinit();
        }

        if (self.renderer) |*renderer| {
            renderer.deinit();
        }

        if (self.swapchain) |*swapchain| {
            swapchain.deinit();
        }

        if (self.device) |*device| {
            device.deinit();
        }

        self.allocator.destroy(self);
    }

    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.swapchain != null) {
            // Clean up existing swapchain
            self.swapchain.?.deinit();
            self.swapchain = null;
        }

        if (self.renderer != null) {
            // Clean up existing renderer
            self.renderer.?.deinit();
            self.renderer = null;
        }

        // Create new swapchain
        if (self.device) |device| {
            // Convert window handle to platform-specific surface
            const surface = try vk.createSurfaceFromHandle(
                device.instance,
                desc.window_handle,
            );

            // Create swapchain
            self.swapchain = try SwapchainSupportDetails.init(
                self.allocator,
                device.physical_device,
                device.device,
                surface,
                desc.width,
                desc.height,
                desc.vsync,
            );

            // Create renderer
            self.renderer = try VulkanRenderer.init(
                self.allocator,
                device,
                self.swapchain.?,
                self.command_pool.?,
            );

            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.renderer) |*renderer| {
            try renderer.resize(width, height);
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn presentImpl(impl: *anyopaque) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.renderer) |*renderer| {
            try renderer.render();
            self.frame_count += 1;
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn getCurrentBackBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.swapchain) |swapchain| {
            // Get current swapchain image index
            const image_index = try swapchain.acquireNextImage();

            // Create a temporary texture to represent the backbuffer
            const texture = try self.allocator.create(types.Texture);
            texture.* = types.Texture{
                .id = @intCast(self.frame_count),
                .width = swapchain.extent.width,
                .height = swapchain.extent.height,
                .depth = 1,
                .format = .rgba8_unorm,
                .mip_levels = 1,
                .array_layers = 1,
                .sample_count = 1,
                .usage = .{ .render_target = true, .shader_resource = false },
                .type = .texture2d,
                .backend_handle = @intFromPtr(swapchain.images[image_index]),
            };

            return texture;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn createTextureImpl(impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |device| {
            // Determine image usage flags
            const usage_flags = common.mapTextureUsage(texture.usage);
            const usage_flags_with_transfer = usage_flags | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT; // Always allow transfer operations

            // Create Vulkan image
            const image = try Image.init(
                device.device,
                device.physical_device,
                texture.width,
                texture.height,
                common.convertTextureFormat(texture.format),
                usage_flags_with_transfer,
                texture.mip_levels,
                texture.array_layers,
            );

            // Upload initial data if provided
            if (data) |pixels| {
                try image.uploadData(
                    self.allocator,
                    self.command_pool.?.pool,
                    device.graphics_queue,
                    pixels,
                );
                std.log.debug("Uploaded texture data ({d} bytes)", .{pixels.len});
            }

            // Store in cache
            try self.textures.put(texture.id, image);

            // Set backend handle
            texture.backend_handle = @intFromPtr(&self.textures.get(texture.id).?);

            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn createBufferImpl(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |device| {
            // Create Vulkan buffer
            const vk_buffer = try Buffer.init(
                device.device,
                device.physical_device,
                buffer.size,
                common.mapBufferUsage(buffer.usage),
            );

            // Upload initial data if provided
            if (data) |bytes| {
                const mapped_data = try vk_buffer.map();
                @memcpy(mapped_data[0..bytes.len], bytes);
                vk_buffer.unmap();
            }

            // Store in cache
            try self.buffers.put(buffer.id, vk_buffer);

            // Set backend handle
            buffer.backend_handle = @intFromPtr(&self.buffers.get(buffer.id).?);

            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn createShaderImpl(impl: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |_| {
            // TODO: Implement shader module creation
            std.log.debug("Creating shader: stage={}, entry={s}", .{ shader.stage, shader.entry_point });

            // Set backend handle to a non-null value to indicate success
            shader.backend_handle = shader.id;
            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |_| {
            // Create a pipeline hash for caching
            const pipeline_hash = generatePipelineHash(desc);

            // Check if we already have this pipeline
            if (self.pipelines.get(pipeline_hash)) |existing_pipeline| {
                // Return a pipeline object for this existing pipeline
                const pipeline = try self.allocator.create(interface.Pipeline);
                pipeline.* = interface.Pipeline{
                    .id = pipeline_hash,
                    .backend_handle = @intFromPtr(&existing_pipeline),
                    .allocator = self.allocator,
                };
                return pipeline;
            }

            // Create vertex input state
            const vertex_bindings: [16]vk.VkVertexInputBindingDescription = undefined;
            const vertex_attrs: [16]vk.VkVertexInputAttributeDescription = undefined;

            var binding_count: u32 = 0;
            var attr_count: u32 = 0;

            if (desc.vertex_layout) |vertex_layout| {
                // Add the vertex binding
                vertex_bindings[binding_count] = .{
                    .binding = 0,
                    .stride = vertex_layout.stride,
                    .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
                };
                binding_count += 1;

                // Add each vertex attribute
                for (vertex_layout.attributes) |attr| {
                    vertex_attrs[attr_count] = .{
                        .location = attr.location,
                        .binding = 0,
                        .format = common.mapVertexFormat(attr.format),
                        .offset = attr.offset,
                    };
                    attr_count += 1;
                }
            }

            // Create a new pipeline
            const new_pipeline = try Pipeline.init(
                self.device.?.device,
                self.getDefaultRenderPass(),
                &vertex_bindings,
                binding_count,
                &vertex_attrs,
                attr_count,
                common.mapPrimitiveTopology(desc.primitive_topology),
                common.mapBlendState(desc.blend_state),
                common.mapDepthStencilState(desc.depth_stencil_state),
            );

            // Store pipeline in cache
            try self.pipelines.put(pipeline_hash, new_pipeline);

            // Return a pipeline object
            const pipeline = try self.allocator.create(interface.Pipeline);
            pipeline.* = interface.Pipeline{
                .id = pipeline_hash,
                .backend_handle = @intFromPtr(&self.pipelines.get(pipeline_hash).?),
                .allocator = self.allocator,
            };

            return pipeline;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    // Get default renderpass (need to implement proper renderpass handling)
    fn getDefaultRenderPass(self: *Self) vk.VkRenderPass {
        if (self.renderer) |renderer| {
            return renderer.render_pass.render_pass;
        }
        return undefined;
    }

    // Generate a hash for pipeline caching
    fn generatePipelineHash(desc: *const interface.PipelineDesc) u64 {
        var hasher = std.hash.Wyhash.init(0);

        // Hash vertex shader
        if (desc.vertex_shader) |shader| {
            std.hash.autoHash(&hasher, shader.id);
        }

        // Hash fragment shader
        if (desc.fragment_shader) |shader| {
            std.hash.autoHash(&hasher, shader.id);
        }

        // Hash primitive topology
        std.hash.autoHash(&hasher, @intFromEnum(desc.primitive_topology));

        // Return the hash
        return hasher.final();
    }

    fn createRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |_| {
            std.log.debug("Creating render target: {}x{} format={}", .{ render_target.width, render_target.height, @intFromEnum(render_target.format) });

            // For now, just mark the render target as valid
            render_target.backend_handle = render_target.id;
            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn updateBufferImpl(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = buffer;
        _ = offset;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn updateTextureImpl(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |device| {
            // Get the texture from cache
            if (self.textures.getPtr(texture.id)) |img_ptr| {
                // Create a staging buffer for the update region
                const region_size = region.width * region.height * @sizeOf(u32); // Assuming RGBA8 format

                // Create staging buffer
                const staging_buffer = try Buffer.init(
                    device.device,
                    device.physical_device,
                    region_size,
                    vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                );
                defer staging_buffer.deinit();

                // Copy data to staging buffer
                const mapped_data = try staging_buffer.map();
                @memcpy(mapped_data[0..data.len], data);
                staging_buffer.unmap();

                // Transition image to transfer dst
                try img_ptr.transitionLayout(
                    self.command_pool.?.pool,
                    device.graphics_queue,
                    vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                );

                // Begin command buffer for copy
                const command_buffer = try img_ptr.beginSingleTimeCommands(self.command_pool.?.pool);

                // Define the region to update
                const buffer_image_copy = vk.VkBufferImageCopy{
                    .bufferOffset = 0,
                    .bufferRowLength = 0, // Tightly packed
                    .bufferImageHeight = 0, // Tightly packed
                    .imageSubresource = vk.VkImageSubresourceLayers{
                        .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                        .mipLevel = region.mip_level,
                        .baseArrayLayer = region.array_layer,
                        .layerCount = 1,
                    },
                    .imageOffset = vk.VkOffset3D{
                        .x = @intCast(region.x),
                        .y = @intCast(region.y),
                        .z = 0,
                    },
                    .imageExtent = vk.VkExtent3D{
                        .width = region.width,
                        .height = region.height,
                        .depth = 1,
                    },
                };

                // Copy buffer to image
                vk.vkCmdCopyBufferToImage(
                    command_buffer,
                    staging_buffer.buffer,
                    img_ptr.image,
                    vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    1,
                    &buffer_image_copy,
                );

                // End and submit command buffer
                try img_ptr.endSingleTimeCommands(command_buffer, self.command_pool.?.pool, device.graphics_queue);

                // Transition image back to shader read
                try img_ptr.transitionLayout(
                    self.command_pool.?.pool,
                    device.graphics_queue,
                    vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                );

                return;
            }

            return interface.GraphicsBackendError.InvalidResource;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn destroyTextureImpl(impl: *anyopaque, texture: *types.Texture) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Check if this is a swapchain image (which we don't own)
        if (self.swapchain) |swapchain| {
            for (swapchain.images) |img| {
                if (texture.backend_handle == @intFromPtr(img)) {
                    // This is a swapchain image, just free the texture object
                    self.allocator.destroy(texture);
                    return;
                }
            }
        }

        // Get texture from cache by ID
        if (self.textures.getPtr(texture.id)) |img_ptr| {
            // Clean up Vulkan resources
            img_ptr.deinit();
            _ = self.textures.remove(texture.id);
        }
    }

    fn destroyBufferImpl(impl: *anyopaque, buffer: *types.Buffer) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Get buffer from cache
        if (self.buffers.getPtr(buffer.id)) |buf_ptr| {
            // Clean up Vulkan resources
            buf_ptr.deinit();
            _ = self.buffers.remove(buffer.id);
        }
    }

    fn destroyShaderImpl(impl: *anyopaque, shader: *types.Shader) void {
        _ = impl;
        _ = shader;
        // No cleanup needed for now as we're not creating actual shader modules yet
    }

    fn destroyRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) void {
        _ = impl;
        _ = render_target;
    }

    fn createCommandBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*interface.CommandBuffer {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.command_pool == null) {
            return interface.GraphicsBackendError.MissingResource;
        }

        // Allocate a command buffer from the pool
        const vk_cmd_buffer = try self.command_pool.?.allocateCommandBuffer();

        // Create command buffer wrapper
        const cmd = try self.allocator.create(interface.CommandBuffer);
        cmd.* = interface.CommandBuffer{
            .id = @intCast(self.frame_count),
            .backend_handle = @intFromPtr(vk_cmd_buffer),
            .allocator = self.allocator,
            .recording = false,
        };

        return cmd;
    }

    fn beginCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        const self = @as(*Self, @ptrCast(@alignCast(impl)));

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Begin the command buffer
        const begin_info = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };

        const result = vk.vkBeginCommandBuffer(vk_cmd_buffer, &begin_info);
        if (result != vk.VK_SUCCESS) {
            return interface.GraphicsBackendError.CommandBufferError;
        }

        // Store current command buffer for later use
        self.current_command_buffer = vk_cmd_buffer;
        cmd.recording = true;
    }

    fn endCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // End the command buffer
        const result = vk.vkEndCommandBuffer(vk_cmd_buffer);
        if (result != vk.VK_SUCCESS) {
            return interface.GraphicsBackendError.CommandBufferError;
        }

        self.current_command_buffer = null;
        cmd.recording = false;
    }

    fn submitCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        if (cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (self.device) |device| {
            // Get the Vulkan command buffer
            const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

            // Create submit info
            const submit_info = vk.VkSubmitInfo{
                .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .pNext = null,
                .waitSemaphoreCount = 0,
                .pWaitSemaphores = null,
                .pWaitDstStageMask = null,
                .commandBufferCount = 1,
                .pCommandBuffers = &vk_cmd_buffer,
                .signalSemaphoreCount = 0,
                .pSignalSemaphores = null,
            };

            // Submit the command buffer
            const result = vk.vkQueueSubmit(device.graphics_queue, 1, &submit_info, 0);
            if (result != vk.VK_SUCCESS) {
                return interface.GraphicsBackendError.CommandBufferError;
            }

            // Wait for the queue to complete
            _ = vk.vkQueueWaitIdle(device.graphics_queue);

            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn beginRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        if (self.renderer) |*renderer| {
            // Get the Vulkan command buffer
            const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

            // Get dimensions from color target
            var width: u32 = 1920; // Default fallback
            var height: u32 = 1080; // Default fallback

            if (desc.color_targets.len > 0 and desc.color_targets[0].texture != null) {
                width = desc.color_targets[0].texture.?.width;
                height = desc.color_targets[0].texture.?.height;
            }

            // Set up clear values
            var clear_values: [2]vk.VkClearValue = undefined;

            // Color clear value
            if (desc.clear_color) |color| {
                clear_values[0].color.float32[0] = color[0];
                clear_values[0].color.float32[1] = color[1];
                clear_values[0].color.float32[2] = color[2];
                clear_values[0].color.float32[3] = color[3];
            } else {
                clear_values[0].color.float32[0] = 0.0;
                clear_values[0].color.float32[1] = 0.0;
                clear_values[0].color.float32[2] = 0.0;
                clear_values[0].color.float32[3] = 1.0;
            }

            // Depth/stencil clear value
            clear_values[1].depthStencil.depth = desc.clear_depth;
            clear_values[1].depthStencil.stencil = desc.clear_stencil;

            // Set up render pass begin info
            const render_area = vk.VkRect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{
                    .width = width,
                    .height = height,
                },
            };

            // Begin render pass
            const begin_info = vk.VkRenderPassBeginInfo{
                .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .pNext = null,
                .renderPass = renderer.render_pass.render_pass,
                .framebuffer = renderer.framebuffers.items[0].framebuffer, // TODO: Use proper framebuffer
                .renderArea = render_area,
                .clearValueCount = 2,
                .pClearValues = &clear_values,
            };

            vk.vkCmdBeginRenderPass(vk_cmd_buffer, &begin_info, vk.VK_SUBPASS_CONTENTS_INLINE);
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn endRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // End render pass
        vk.vkCmdEndRenderPass(vk_cmd_buffer);
        return;
    }

    fn setViewportImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Create Vulkan viewport
        const vk_viewport = vk.VkViewport{
            .x = viewport.x,
            .y = viewport.y,
            .width = viewport.width,
            .height = viewport.height,
            .minDepth = viewport.min_depth,
            .maxDepth = viewport.max_depth,
        };

        // Set viewport
        vk.vkCmdSetViewport(vk_cmd_buffer, 0, 1, &vk_viewport);
        return;
    }

    fn setScissorImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Create Vulkan scissor rect
        const vk_scissor = vk.VkRect2D{
            .offset = .{
                .x = @intFromFloat(rect.x),
                .y = @intFromFloat(rect.y),
            },
            .extent = .{
                .width = @intFromFloat(rect.width),
                .height = @intFromFloat(rect.height),
            },
        };

        // Set scissor
        vk.vkCmdSetScissor(vk_cmd_buffer, 0, 1, &vk_scissor);
        return;
    }

    fn bindPipelineImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Get the pipeline from backend handle
        if (pipeline.backend_handle != 0) {
            const pipeline_ptr = @as(*Pipeline, @ptrFromInt(pipeline.backend_handle));
            pipeline_ptr.bind(vk_cmd_buffer);
            return;
        }

        return interface.GraphicsBackendError.InvalidResource;
    }

    fn bindVertexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0 or buffer.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Get buffer from handle - note we stored a pointer to the cache entry
        if (buffer.backend_handle != 0) {
            const buffer_ptr = @as(*Buffer, @ptrFromInt(buffer.backend_handle));
            const vk_buffer = buffer_ptr.buffer;
            const vk_offset: vk.VkDeviceSize = offset;

            // Bind vertex buffer
            vk.vkCmdBindVertexBuffers(vk_cmd_buffer, slot, 1, &vk_buffer, &vk_offset);
            return;
        }

        return interface.GraphicsBackendError.InvalidResource;
    }

    fn bindIndexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0 or buffer.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Map index format to Vulkan
        const vk_format = switch (format) {
            .uint16 => vk.VK_INDEX_TYPE_UINT16,
            .uint32 => vk.VK_INDEX_TYPE_UINT32,
        };

        // Get buffer from handle
        const buffer_ptr = @as(*Buffer, @ptrFromInt(buffer.backend_handle));
        const vk_buffer = buffer_ptr.buffer;

        // Bind index buffer
        vk.vkCmdBindIndexBuffer(vk_cmd_buffer, vk_buffer, offset, vk_format);
        return;
    }

    fn bindTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0 or texture.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Get the texture from cache or from swapchain
        if (self.textures.getPtr(texture.id)) |img_ptr| {
            // TODO: Implement descriptor set binding for textures
            // For now, just log that we're binding a texture
            std.log.debug("Binding texture to slot {d}", .{slot});

            _ = vk_cmd_buffer;
            _ = img_ptr;
            return;
        }

        return interface.GraphicsBackendError.InvalidResource;
    }

    fn bindUniformBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0 or buffer.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Get buffer from handle
        if (self.buffers.getPtr(buffer.id)) |buf_ptr| {
            std.log.debug("Binding uniform buffer to slot {d} (offset: {d}, size: {d})", .{ slot, offset, size });

            // TODO: Implement descriptor set binding for uniform buffers
            // For now, just log the binding operation
            _ = vk_cmd_buffer;
            _ = buf_ptr;

            return;
        }

        return interface.GraphicsBackendError.InvalidResource;
    }

    fn drawImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Draw command
        vk.vkCmdDraw(vk_cmd_buffer, draw_cmd.vertex_count, draw_cmd.instance_count, draw_cmd.first_vertex, draw_cmd.first_instance);

        return;
    }

    fn drawIndexedImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Draw indexed command
        vk.vkCmdDrawIndexed(vk_cmd_buffer, draw_cmd.index_count, draw_cmd.instance_count, draw_cmd.first_index, draw_cmd.vertex_offset, draw_cmd.first_instance);

        return;
    }

    fn dispatchImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = dispatch_cmd;
    }

    fn copyBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const interface.BufferCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyBufferToTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyTextureToBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn resourceBarrierImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = barriers;
    }

    fn getBackendInfoImpl(impl: *anyopaque) interface.BackendInfo {
        const self: *Self = @ptrCast(@alignCast(impl));

        var info = interface.BackendInfo{
            .name = "Vulkan",
            .version = "1.3",
            .vendor = "Khronos Group",
            .device_name = "Unknown Vulkan Device",
            .api_version = 13,
            .driver_version = 0,
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 16384,
            .max_render_targets = 8,
            .max_vertex_attributes = 16,
            .max_uniform_buffer_bindings = 16,
            .max_texture_bindings = 32,
            .supports_compute = true,
            .supports_geometry_shaders = true,
            .supports_tessellation = true,
            .supports_raytracing = false,
            .supports_mesh_shaders = false,
            .supports_variable_rate_shading = false,
            .supports_multiview = true,
        };

        if (self.device) |device| {
            // Retrieve device properties
            var props: vk.VkPhysicalDeviceProperties = undefined;
            vk.vkGetPhysicalDeviceProperties(device.physical_device, &props);

            // Update info with actual device data
            info.device_name = std.mem.sliceTo(&props.deviceName, 0);
            info.api_version = props.apiVersion;
            info.driver_version = props.driverVersion;
            info.max_texture_size = props.limits.maxImageDimension2D;

            // Fetch memory information
            var memory_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
            vk.vkGetPhysicalDeviceMemoryProperties(device.physical_device, &memory_props);

            var total_memory: u64 = 0;
            for (0..memory_props.memoryHeapCount) |i| {
                if (memory_props.memoryHeaps[i].flags & vk.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT != 0) {
                    total_memory += memory_props.memoryHeaps[i].size;
                }
            }

            info.memory_budget = @intCast(total_memory / (1024 * 1024)); // Convert to MB

            // Check feature support
            var features2: vk.VkPhysicalDeviceFeatures2 = .{
                .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                .pNext = null,
                .features = undefined,
            };

            vk.vkGetPhysicalDeviceFeatures2(device.physical_device, &features2);

            info.supports_geometry_shaders = features2.features.geometryShader == vk.VK_TRUE;
            info.supports_tessellation = features2.features.tessellationShader == vk.VK_TRUE;
        }

        return info;
    }

    fn setDebugNameImpl(impl: *anyopaque, resource: interface.ResourceHandle, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = resource;
        _ = name;
    }

    fn beginDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = name;
    }

    fn endDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
    }
};
