const std = @import("std");
const Allocator = std.mem.Allocator;
const interface = @import("interface.zig");
const ArrayList = std.array_list.Managed;

// Vulkan types and constants
const vk = struct {
    const Instance = *opaque {};
    const PhysicalDevice = *opaque {};
    const Device = *opaque {};
    const Queue = *opaque {};
    const Buffer = u64;
    const Image = u64;
    const ImageView = u64;
    const RenderPass = u64;
    const Pipeline = u64;
    const PipelineLayout = u64;
    const ShaderModule = u64;
    const Framebuffer = u64;
    const CommandPool = u64;
    const CommandBuffer = *opaque {};
    const Semaphore = u64;
    const Fence = u64;
    const SurfaceKHR = u64;
    const SwapchainKHR = u64;
    const DescriptorPool = u64;
    const DescriptorSet = *opaque {};
    const DescriptorSetLayout = u64;
    const Sampler = u64;

    const Bool32 = u32;
    const DeviceSize = u64;

    // Basic structs
    const Extent2D = extern struct {
        width: u32,
        height: u32,
    };

    const Extent3D = extern struct {
        width: u32,
        height: u32,
        depth: u32,
    };

    const Offset2D = extern struct {
        x: i32,
        y: i32,
    };

    const Rect2D = extern struct {
        offset: Offset2D,
        extent: Extent2D,
    };

    const ClearValue = extern union {
        color: [4]f32,
        depthStencil: extern struct {
            depth: f32,
            stencil: u32,
        },
    };

    // Common enums
    const Format = enum(i32) {
        UNDEFINED = 0,
        R8G8B8A8_UNORM = 37,
        B8G8R8A8_UNORM = 44,
        D24_UNORM_S8_UINT = 125,
        _,
    };

    const ImageLayout = enum(i32) {
        UNDEFINED = 0,
        COLOR_ATTACHMENT_OPTIMAL = 2,
        PRESENT_SRC_KHR = 1000001002,
        _,
    };

    const ColorComponentFlags = packed struct(u32) {
        r: bool = false,
        g: bool = false,
        b: bool = false,
        a: bool = false,
        _padding: u28 = 0,
    };

    const ShaderStageFlags = packed struct(u32) {
        vertex: bool = false,
        fragment: bool = false,
        compute: bool = false,
        _padding: u29 = 0,
    };

    const PipelineStageFlags = packed struct(u32) {
        top_of_pipe: bool = false,
        draw_indirect: bool = false,
        vertex_input: bool = false,
        vertex_shader: bool = false,
        fragment_shader: bool = false,
        early_fragment_tests: bool = false,
        late_fragment_tests: bool = false,
        color_attachment_output: bool = false,
        compute_shader: bool = false,
        transfer: bool = false,
        bottom_of_pipe: bool = false,
        host: bool = false,
        all_graphics: bool = false,
        all_commands: bool = false,
        _padding: u18 = 0,
    };

    const AccessFlags = packed struct(u32) {
        indirect_command_read: bool = false,
        index_read: bool = false,
        vertex_attribute_read: bool = false,
        uniform_read: bool = false,
        input_attachment_read: bool = false,
        shader_read: bool = false,
        shader_write: bool = false,
        color_attachment_read: bool = false,
        color_attachment_write: bool = false,
        depth_stencil_attachment_read: bool = false,
        depth_stencil_attachment_write: bool = false,
        transfer_read: bool = false,
        transfer_write: bool = false,
        host_read: bool = false,
        host_write: bool = false,
        memory_read: bool = false,
        memory_write: bool = false,
        _padding: u15 = 0,
    };
};

// Simple wrapper for Windows HWND
const HWND = *opaque {};

// Vulkan-Win32 function imports
extern "vulkan-1" fn vkCreateWin32SurfaceKHR(
    instance: vk.Instance,
    pCreateInfo: *const Win32SurfaceCreateInfoKHR,
    pAllocator: ?*const anyopaque,
    pSurface: *vk.SurfaceKHR,
) i32;

const Win32SurfaceCreateInfoKHR = extern struct {
    sType: i32 = 1000009000, // VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    hinstance: *anyopaque,
    hwnd: HWND,
};

// Other Vulkan function imports - most would be loaded dynamically in a real implementation
extern "vulkan-1" fn vkCreateInstance(
    pCreateInfo: *const InstanceCreateInfo,
    pAllocator: ?*const anyopaque,
    pInstance: *vk.Instance,
) i32;

extern "vulkan-1" fn vkDestroyInstance(
    instance: vk.Instance,
    pAllocator: ?*const anyopaque,
) void;

const InstanceCreateInfo = extern struct {
    sType: i32 = 1, // VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pApplicationInfo: ?*const ApplicationInfo,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

const ApplicationInfo = extern struct {
    sType: i32 = 0, // VK_STRUCTURE_TYPE_APPLICATION_INFO
    pNext: ?*const anyopaque = null,
    pApplicationName: [*:0]const u8,
    applicationVersion: u32,
    pEngineName: [*:0]const u8,
    engineVersion: u32,
    apiVersion: u32,
};

// Simplified Vulkan context
const VulkanContext = struct {
    allocator: Allocator,
    instance: vk.Instance = undefined,
    physical_device: vk.PhysicalDevice = undefined,
    device: vk.Device = undefined,
    graphics_queue: vk.Queue = undefined,
    present_queue: vk.Queue = undefined,
    surface: vk.SurfaceKHR = undefined,
    swapchain: vk.SwapchainKHR = undefined,
    swapchain_images: []vk.Image = undefined,
    swapchain_image_views: []vk.ImageView = undefined,
    render_pass: vk.RenderPass = undefined,
    pipeline_layout: vk.PipelineLayout = undefined,
    graphics_pipeline: vk.Pipeline = undefined,
    framebuffers: []vk.Framebuffer = undefined,
    command_pool: vk.CommandPool = undefined,
    command_buffers: []vk.CommandBuffer = undefined,
    image_available_semaphores: []vk.Semaphore = undefined,
    render_finished_semaphores: []vk.Semaphore = undefined,
    in_flight_fences: []vk.Fence = undefined,
    current_frame: usize = 0,
    width: u32 = 0,
    height: u32 = 0,
    hwnd: HWND = undefined,

    const Self = @This();

    pub fn init(allocator: Allocator, window_handle: HWND) !Self {
        var self = Self{
            .allocator = allocator,
            .hwnd = window_handle,
        };

        // In a real implementation, we would:
        // 1. Create Vulkan instance
        // 2. Select physical device
        // 3. Create logical device
        // 4. Create surface
        // 5. Create swapchain
        // 6. Create render pass, graphics pipeline, etc.

        // For this demonstration, we'll initialize with dummy values
        self.width = 800;
        self.height = 600;

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Clean up Vulkan resources
        // (In a real implementation, we would destroy all Vulkan objects)

        // Free allocated memory
        if (self.swapchain_images.len > 0) {
            self.allocator.free(self.swapchain_images);
            self.allocator.free(self.swapchain_image_views);
            self.allocator.free(self.framebuffers);
            self.allocator.free(self.command_buffers);
            self.allocator.free(self.image_available_semaphores);
            self.allocator.free(self.render_finished_semaphores);
            self.allocator.free(self.in_flight_fences);
        }
    }

    pub fn beginFrame(self: *Self, width: u32, height: u32) !void {
        if (width != self.width or height != self.height) {
            try self.resize(width, height);
        }

        // Wait for previous frame to finish
        // Acquire next image from swapchain
        // Begin command buffer recording
    }

    pub fn endFrame(self: *Self) !void {
        // End command buffer recording
        // Submit command buffer to queue
        // Present image to surface
        self.current_frame = (self.current_frame + 1) % self.swapchain_images.len;
    }

    pub fn resize(self: *Self, width: u32, height: u32) !void {
        self.width = width;
        self.height = height;

        // Recreate swapchain and dependent resources
    }

    pub fn executeDrawCommands(self: *Self, commands: []const interface.DrawCommand) !void {
        // Process draw commands and convert to Vulkan commands
        for (commands) |cmd| {
            switch (cmd) {
                .clear => |color| {
                    // Set clear color and clear framebuffer
                    _ = color;
                },
                .rect => |rect_data| {
                    // Draw rectangle
                    _ = rect_data;
                },
                .text => |text_data| {
                    // Draw text (would require texture atlas in real implementation)
                    _ = text_data;
                },
                .image => |image_data| {
                    // Draw image
                    _ = image_data;
                },
                .clip_push => |rect| {
                    // Push scissor rectangle
                    _ = rect;
                },
                .clip_pop => {
                    // Pop scissor rectangle
                },
                .custom => |custom_data| {
                    // Execute custom rendering function
                    custom_data.callback(custom_data.data, self);
                },
            }
        }
    }

    pub fn createImage(self: *Self, width: u32, height: u32, pixels: [*]const u8, format: interface.Image.ImageFormat) !interface.Image {
        _ = pixels;
        _ = format;

        // Create Vulkan image, memory, and image view
        // Upload pixel data to image

        return interface.Image{
            .handle = @intFromPtr(self) + width + height, // Dummy handle
            .width = width,
            .height = height,
            .format = .rgba8,
        };
    }

    pub fn destroyImage(self: *Self, image: *interface.Image) void {
        _ = self;
        _ = image;
        // Destroy Vulkan image, memory, and image view
    }

    pub fn getTextSize(self: *Self, text: []const u8, font: interface.FontInfo) struct { width: f32, height: f32 } {
        _ = self;

        // In a real implementation, this would measure text using a font atlas
        // For now, return a simple approximation
        const char_width = font.style.size * 0.6;
        return .{
            .width = @as(f32, @floatFromInt(text.len)) * char_width,
            .height = font.style.size * 1.2,
        };
    }
};

// Vulkan backend implementation for our UI system
pub const VulkanBackend = struct {
    allocator: Allocator,
    context: VulkanContext,

    const Self = @This();

    pub fn init(allocator: Allocator, window_handle: usize) !Self {
        return Self{
            .allocator = allocator,
            .context = try VulkanContext.init(allocator, @ptrFromInt(window_handle)),
        };
    }

    pub fn deinit(self: *Self) void {
        self.context.deinit();
    }

    pub fn beginFrame(self: *Self, width: u32, height: u32) !void {
        try self.context.beginFrame(width, height);
    }

    pub fn endFrame(self: *Self) !void {
        try self.context.endFrame();
    }

    pub fn executeDrawCommands(self: *Self, commands: []const interface.DrawCommand) !void {
        try self.context.executeDrawCommands(commands);
    }

    pub fn createImage(self: *Self, width: u32, height: u32, pixels: [*]const u8, format: interface.Image.ImageFormat) !interface.Image {
        return try self.context.createImage(width, height, pixels, format);
    }

    pub fn destroyImage(self: *Self, image: *interface.Image) void {
        self.context.destroyImage(image);
    }

    pub fn getTextSize(self: *Self, text: []const u8, font: interface.FontInfo) struct { width: f32, height: f32 } {
        _ = self;
        _ = text;
        _ = font;
        // Placeholder implementation - would measure text using font metrics
        return .{ .width = 100.0, .height = 20.0 };
    }
};

// Vulkan type definitions
const VkPhysicalDevice = *opaque {};
const VkDevice = *opaque {};
const VkQueue = *opaque {};
const VkSurfaceKHR = *opaque {};
const VkSwapchainKHR = *opaque {};
const VkImage = *opaque {};
const VkImageView = *opaque {};
const VkRenderPass = *opaque {};
const VkFramebuffer = *opaque {};
const VkCommandPool = *opaque {};
const VkCommandBuffer = *opaque {};
const VkSemaphore = *opaque {};
const VkFence = *opaque {};
const VkPipeline = *opaque {};
const VkPipelineLayout = *opaque {};
const VkDescriptorSetLayout = *opaque {};
const VkBuffer = *opaque {};
const VkDeviceMemory = *opaque {};
const VkSampler = *opaque {};
const VkShaderModule = *opaque {};

// Vulkan constants
const VK_SUCCESS = 0;
const VK_FORMAT_B8G8R8A8_UNORM = 44;
const VK_COLOR_SPACE_SRGB_NONLINEAR_KHR = 0;
const VK_PRESENT_MODE_FIFO_KHR = 2;
const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = 0x00000010;
const VK_SHARING_MODE_EXCLUSIVE = 0;
const VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR = 0x00000001;
const VK_SUBPASS_EXTERNAL = 0xFFFFFFFF;
const VK_PIPELINE_BIND_POINT_GRAPHICS = 0;
extern fn vkEnumeratePhysicalDevices(VkInstance, *u32, ?[*]VkPhysicalDevice) i32;
extern fn vkCreateDevice(VkPhysicalDevice, *const VkDeviceCreateInfo, ?*anyopaque, *VkDevice) i32;

fn vulkanInit(allocator: Allocator, window_handle: usize) !*anyopaque {
    const ctx = try allocator.create(VulkanContext);
    ctx.* = try VulkanContext.init(allocator, @ptrFromInt(window_handle));
    return @ptrCast(ctx);
}

fn vulkanDeinit(ctx: *anyopaque) void {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    vulkan_ctx.deinit();
}

fn vulkanBeginFrame(ctx: *anyopaque, width: u32, height: u32) void {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    vulkan_ctx.beginFrame(width, height) catch {};
}

fn vulkanEndFrame(ctx: *anyopaque) void {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    vulkan_ctx.endFrame() catch {};
}

fn vulkanExecuteDrawCommands(ctx: *anyopaque, commands: []const interface.DrawCommand) void {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    vulkan_ctx.executeDrawCommands(commands) catch {};
}

fn vulkanCreateImage(ctx: *anyopaque, width: u32, height: u32, pixels: [*]const u8, format: interface.Image.ImageFormat) !interface.Image {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    return vulkan_ctx.createImage(width, height, pixels, format);
}

fn vulkanDestroyImage(ctx: *anyopaque, image: *interface.Image) void {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    vulkan_ctx.destroyImage(image);
}

fn vulkanGetTextSize(ctx: *anyopaque, text: []const u8, font: interface.FontInfo) struct { width: f32, height: f32 } {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    return vulkan_ctx.getTextSize(text, font);
}

fn vulkanResize(ctx: *anyopaque, width: u32, height: u32) void {
    const vulkan_ctx: *VulkanContext = @ptrCast(@alignCast(ctx));
    vulkan_ctx.resize(width, height) catch {};
}

// Backend interface implementation
pub const vulkan_backend_interface = interface.BackendInterface{
    .init_fn = vulkanInit,
    .deinit_fn = vulkanDeinit,
    .begin_frame_fn = vulkanBeginFrame,
    .end_frame_fn = vulkanEndFrame,
    .execute_draw_commands_fn = vulkanExecuteDrawCommands,
    .create_image_fn = vulkanCreateImage,
    .destroy_image_fn = vulkanDestroyImage,
    .get_text_size_fn = vulkanGetTextSize,
    .resize_fn = vulkanResize,
    .backend_type = .vulkan,
};

// Additional Vulkan type definitions
const VkInstance = *opaque {};
const VkDeviceCreateInfo = extern struct {
    sType: u32 = 3,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueCreateInfoCount: u32 = 0,
    pQueueCreateInfos: [*]const VkDeviceQueueCreateInfo = undefined,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
    pEnabledFeatures: ?*const VkPhysicalDeviceFeatures = null,
};

const VkInstanceCreateInfo = extern struct {
    sType: u32 = 1,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pApplicationInfo: ?*const VkApplicationInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

const VkApplicationInfo = extern struct {
    sType: u32 = 0,
    pNext: ?*const anyopaque = null,
    pApplicationName: ?[*:0]const u8 = null,
    applicationVersion: u32 = 0,
    pEngineName: ?[*:0]const u8 = null,
    engineVersion: u32 = 0,
    apiVersion: u32 = 0,
};

const VkDeviceQueueCreateInfo = extern struct {
    sType: u32 = 2,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueFamilyIndex: u32 = 0,
    queueCount: u32 = 0,
    pQueuePriorities: [*]const f32 = undefined,
};

const VkPhysicalDeviceFeatures = extern struct {
    robustBufferAccess: u32 = 0,
    fullDrawIndexUint32: u32 = 0,
    imageCubeArray: u32 = 0,
    independentBlend: u32 = 0,
    geometryShader: u32 = 0,
    tessellationShader: u32 = 0,
    sampleRateShading: u32 = 0,
    dualSrcBlend: u32 = 0,
    logicOp: u32 = 0,
    multiDrawIndirect: u32 = 0,
    drawIndirectFirstInstance: u32 = 0,
    depthClamp: u32 = 0,
    depthBiasClamp: u32 = 0,
    fillModeNonSolid: u32 = 0,
    depthBounds: u32 = 0,
    wideLines: u32 = 0,
    largePoints: u32 = 0,
    alphaToOne: u32 = 0,
    multiViewport: u32 = 0,
    samplerAnisotropy: u32 = 0,
    textureCompressionETC2: u32 = 0,
    textureCompressionASTC_LDR: u32 = 0,
    textureCompressionBC: u32 = 0,
    occlusionQueryPrecise: u32 = 0,
    pipelineStatisticsQuery: u32 = 0,
    vertexPipelineStoresAndAtomics: u32 = 0,
    fragmentStoresAndAtomics: u32 = 0,
    shaderTessellationAndGeometryPointSize: u32 = 0,
    shaderImageGatherExtended: u32 = 0,
    shaderStorageImageExtendedFormats: u32 = 0,
    shaderStorageImageMultisample: u32 = 0,
    shaderStorageImageReadWithoutFormat: u32 = 0,
    shaderStorageImageWriteWithoutFormat: u32 = 0,
    shaderUniformBufferArrayDynamicIndexing: u32 = 0,
    shaderSampledImageArrayDynamicIndexing: u32 = 0,
    shaderStorageBufferArrayDynamicIndexing: u32 = 0,
    shaderStorageImageArrayDynamicIndexing: u32 = 0,
    shaderClipDistance: u32 = 0,
    shaderCullDistance: u32 = 0,
    shaderFloat64: u32 = 0,
    shaderInt64: u32 = 0,
    shaderInt16: u32 = 0,
    shaderResourceResidency: u32 = 0,
    shaderResourceMinLod: u32 = 0,
    sparseBinding: u32 = 0,
    sparseResidencyBuffer: u32 = 0,
    sparseResidencyImage2D: u32 = 0,
    sparseResidencyImage3D: u32 = 0,
    sparseResidency2Samples: u32 = 0,
    sparseResidency4Samples: u32 = 0,
    sparseResidency8Samples: u32 = 0,
    sparseResidency16Samples: u32 = 0,
    sparseResidencyAliased: u32 = 0,
    variableMultisampleRate: u32 = 0,
    inheritedQueries: u32 = 0,
};

const VkCommandBufferAllocateInfo = extern struct {
    sType: u32 = 40,
    pNext: ?*const anyopaque = null,
    commandPool: VkCommandPool = undefined,
    level: u32 = 0,
    commandBufferCount: u32 = 0,
};

const VkCommandBufferBeginInfo = extern struct {
    sType: u32 = 42,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pInheritanceInfo: ?*const VkCommandBufferInheritanceInfo = null,
};

const VkCommandBufferInheritanceInfo = extern struct {
    sType: u32 = 41,
    pNext: ?*const anyopaque = null,
    renderPass: ?VkRenderPass = null,
    subpass: u32 = 0,
    framebuffer: ?VkFramebuffer = null,
    occlusionQueryEnable: u32 = 0,
    queryFlags: u32 = 0,
    pipelineStatistics: u32 = 0,
};

const VkRenderPassBeginInfo = extern struct {
    sType: u32 = 43,
    pNext: ?*const anyopaque = null,
    renderPass: VkRenderPass = undefined,
    framebuffer: VkFramebuffer = undefined,
    renderArea: VkRect2D = .{},
    clearValueCount: u32 = 0,
    pClearValues: ?[*]const VkClearValue = null,
};

const VkRect2D = extern struct {
    offset: VkOffset2D = .{},
    extent: VkExtent2D = .{},
};

const VkOffset2D = extern struct {
    x: i32 = 0,
    y: i32 = 0,
};

const VkExtent2D = extern struct {
    width: u32 = 0,
    height: u32 = 0,
};

const VkClearValue = extern union {
    color: VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

const VkClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

const VkClearDepthStencilValue = extern struct {
    depth: f32,
    stencil: u32,
};

const VkBufferCreateInfo = extern struct {
    sType: u32 = 12,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    size: u64 = 0,
    usage: u32 = 0,
    sharingMode: u32 = 0,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
};

const VkMemoryRequirements = extern struct {
    size: u64,
    alignment: u64,
    memoryTypeBits: u32,
};

const VkMemoryAllocateInfo = extern struct {
    sType: u32 = 5,
    pNext: ?*const anyopaque = null,
    allocationSize: u64 = 0,
    memoryTypeIndex: u32 = 0,
};

const VkSubmitInfo = extern struct {
    sType: u32 = 4,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    pWaitDstStageMask: ?[*]const u32 = null,
    commandBufferCount: u32 = 0,
    pCommandBuffers: [*]const VkCommandBuffer = undefined,
    signalSemaphoreCount: u32 = 0,
    pSignalSemaphores: ?[*]const VkSemaphore = null,
};

const VkPresentInfoKHR = extern struct {
    sType: u32 = 1000001001,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    swapchainCount: u32 = 0,
    pSwapchains: [*]const VkSwapchainKHR = undefined,
    pImageIndices: [*]const u32 = undefined,
    pResults: ?[*]i32 = null,
};

const VkShaderModuleCreateInfo = extern struct {
    sType: u32 = 16,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    codeSize: usize = 0,
    pCode: [*]const u32 = undefined,
};

const VkGraphicsPipelineCreateInfo = extern struct {
    sType: u32 = 28,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    stageCount: u32 = 0,
    pStages: [*]const VkPipelineShaderStageCreateInfo = undefined,
    pVertexInputState: ?*const VkPipelineVertexInputStateCreateInfo = null,
    pInputAssemblyState: ?*const VkPipelineInputAssemblyStateCreateInfo = null,
    pTessellationState: ?*const anyopaque = null,
    pViewportState: ?*const VkPipelineViewportStateCreateInfo = null,
    pRasterizationState: ?*const VkPipelineRasterizationStateCreateInfo = null,
    pMultisampleState: ?*const VkPipelineMultisampleStateCreateInfo = null,
    pDepthStencilState: ?*const anyopaque = null,
    pColorBlendState: ?*const VkPipelineColorBlendStateCreateInfo = null,
    pDynamicState: ?*const anyopaque = null,
    layout: VkPipelineLayout = undefined,
    renderPass: VkRenderPass = undefined,
    subpass: u32 = 0,
    basePipelineHandle: ?VkPipeline = null,
    basePipelineIndex: i32 = -1,
};

const VkPipelineShaderStageCreateInfo = extern struct {
    sType: u32 = 18,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    stage: u32 = 0,
    module: VkShaderModule = undefined,
    pName: [*:0]const u8 = undefined,
    pSpecializationInfo: ?*const anyopaque = null,
};

const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType: u32 = 19,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    vertexBindingDescriptionCount: u32 = 0,
    pVertexBindingDescriptions: ?[*]const VkVertexInputBindingDescription = null,
    vertexAttributeDescriptionCount: u32 = 0,
    pVertexAttributeDescriptions: ?[*]const VkVertexInputAttributeDescription = null,
};

const VkVertexInputBindingDescription = extern struct {
    binding: u32 = 0,
    stride: u32 = 0,
    inputRate: u32 = 0,
};

const VkVertexInputAttributeDescription = extern struct {
    location: u32 = 0,
    binding: u32 = 0,
    format: u32 = 0,
    offset: u32 = 0,
};

const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType: u32 = 20,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    topology: u32 = 0,
    primitiveRestartEnable: u32 = 0,
};

const VkPipelineViewportStateCreateInfo = extern struct {
    sType: u32 = 22,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    viewportCount: u32 = 0,
    pViewports: ?[*]const VkViewport = null,
    scissorCount: u32 = 0,
    pScissors: ?[*]const VkRect2D = null,
};

const VkViewport = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    minDepth: f32 = 0,
    maxDepth: f32 = 1,
};

const VkPipelineRasterizationStateCreateInfo = extern struct {
    sType: u32 = 23,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    depthClampEnable: u32 = 0,
    rasterizerDiscardEnable: u32 = 0,
    polygonMode: u32 = 0,
    cullMode: u32 = 0,
    frontFace: u32 = 0,
    depthBiasEnable: u32 = 0,
    depthBiasConstantFactor: f32 = 0,
    depthBiasClamp: f32 = 0,
    depthBiasSlopeFactor: f32 = 0,
    lineWidth: f32 = 1,
};

const VkPipelineMultisampleStateCreateInfo = extern struct {
    sType: u32 = 24,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    rasterizationSamples: u32 = 1,
    sampleShadingEnable: u32 = 0,
    minSampleShading: f32 = 0,
    pSampleMask: ?[*]const u32 = null,
    alphaToCoverageEnable: u32 = 0,
    alphaToOneEnable: u32 = 0,
};

const VkPipelineColorBlendStateCreateInfo = extern struct {
    sType: u32 = 26,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    logicOpEnable: u32 = 0,
    logicOp: u32 = 0,
    attachmentCount: u32 = 0,
    pAttachments: [*]const VkPipelineColorBlendAttachmentState = undefined,
    blendConstants: [4]f32 = .{ 0, 0, 0, 0 },
};

const VkPipelineColorBlendAttachmentState = extern struct {
    colorWriteMask: u32 = 0xF,
    blendEnable: u32 = 0,
    srcColorBlendFactor: u32 = 0,
    dstColorBlendFactor: u32 = 0,
    colorBlendOp: u32 = 0,
    srcAlphaBlendFactor: u32 = 0,
    dstAlphaBlendFactor: u32 = 0,
    alphaBlendOp: u32 = 0,
};

const VkPipelineLayoutCreateInfo = extern struct {
    sType: u32 = 30,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    setLayoutCount: u32 = 0,
    pSetLayouts: ?[*]const VkDescriptorSetLayout = null,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges: ?[*]const VkPushConstantRange = null,
};

const VkPushConstantRange = extern struct {
    stageFlags: u32 = 0,
    offset: u32 = 0,
    size: u32 = 0,
};

// UI-specific Vulkan structures
const Vertex = extern struct {
    position: [2]f32,
    tex_coord: [2]f32,
    color: [4]f32,
};

const DrawCallData = struct {
    vertex_offset: u32,
    index_offset: u32,
    index_count: u32,
    texture_index: u32,
};

const VulkanBuffer = struct {
    buffer: VkBuffer,
    memory: VkDeviceMemory,
    size: u64,
};

const VulkanTexture = struct {
    image: VkImage,
    memory: VkDeviceMemory,
    view: VkImageView,
    sampler: VkSampler,
    width: u32,
    height: u32,
    format: interface.Image.ImageFormat,
};

const RenderData = struct {
    vertices: ArrayList(Vertex),
    indices: ArrayList(u32),
    draw_calls: ArrayList(DrawCallData),
    textures: ArrayList(VulkanTexture),
};
