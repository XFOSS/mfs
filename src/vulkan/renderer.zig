const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");
const build_options = @import("build_options");

pub const VulkanError = error{
    LoaderNotFound,
    InstanceCreationFailed,
    NoSuitableDevice,
    InitializationFailed,
    SurfaceCreationFailed,
    SwapchainCreationFailed,
    PipelineCreationFailed,
    OutOfMemory,
};

pub const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    pub fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

pub const SwapchainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,

    pub fn deinit(self: *SwapchainSupportDetails, allocator: std.mem.Allocator) void {
        allocator.free(self.formats);
        allocator.free(self.present_modes);
    }
};

pub const VulkanRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    instance: vk.Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    swapchain: vk.SwapchainKHR,
    swapchain_images: []vk.Image,
    swapchain_image_format: vk.Format,
    swapchain_extent: vk.Extent2D,
    swapchain_image_views: []vk.ImageView,
    render_pass: vk.RenderPass,
    pipeline_layout: vk.PipelineLayout,
    graphics_pipeline: vk.Pipeline,
    framebuffers: []vk.Framebuffer,
    command_pool: vk.CommandPool,
    command_buffers: []vk.CommandBuffer,
    image_available_semaphores: []vk.Semaphore,
    render_finished_semaphores: []vk.Semaphore,
    in_flight_fences: []vk.Fence,
    current_frame: usize = 0,
    framebuffer_resized: bool = false,
    width: u32,
    height: u32,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, window: *anyopaque) !*Self {
        var self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .instance = undefined,
            .debug_messenger = undefined,
            .surface = undefined,
            .physical_device = undefined,
            .device = undefined,
            .graphics_queue = undefined,
            .present_queue = undefined,
            .swapchain = undefined,
            .swapchain_images = undefined,
            .swapchain_image_format = undefined,
            .swapchain_extent = undefined,
            .swapchain_image_views = undefined,
            .render_pass = undefined,
            .pipeline_layout = undefined,
            .graphics_pipeline = undefined,
            .framebuffers = undefined,
            .command_pool = undefined,
            .command_buffers = undefined,
            .image_available_semaphores = undefined,
            .render_finished_semaphores = undefined,
            .in_flight_fences = undefined,
            .width = width,
            .height = height,
        };

        try self.createInstance();
        try self.setupDebugMessenger();
        try self.createSurface(window);
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapchain();
        try self.createImageViews();
        try self.createRenderPass();
        try self.createGraphicsPipeline();
        try self.createFramebuffers();
        try self.createCommandPool();
        try self.createCommandBuffers();
        try self.createSyncObjects();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.cleanup();
        self.allocator.destroy(self);
    }

    fn cleanup(self: *Self) void {
        vk.deviceWaitIdle(self.device);

        self.cleanupSwapchain();

        for (self.in_flight_fences) |fence| {
            vk.destroyFence(self.device, fence, null);
        }
        for (self.render_finished_semaphores) |semaphore| {
            vk.destroySemaphore(self.device, semaphore, null);
        }
        for (self.image_available_semaphores) |semaphore| {
            vk.destroySemaphore(self.device, semaphore, null);
        }

        vk.destroyCommandPool(self.device, self.command_pool, null);
        vk.destroyDevice(self.device, null);
        vk.destroySurfaceKHR(self.instance, self.surface, null);
        vk.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
        vk.destroyInstance(self.instance, null);
    }

    fn cleanupSwapchain(self: *Self) void {
        for (self.framebuffers) |framebuffer| {
            vk.destroyFramebuffer(self.device, framebuffer, null);
        }
        self.allocator.free(self.framebuffers);

        vk.freeCommandBuffers(
            self.device,
            self.command_pool,
            @intCast(self.command_buffers.len),
            self.command_buffers.ptr,
        );
        self.allocator.free(self.command_buffers);

        vk.destroyPipeline(self.device, self.graphics_pipeline, null);
        vk.destroyPipelineLayout(self.device, self.pipeline_layout, null);
        vk.destroyRenderPass(self.device, self.render_pass, null);

        for (self.swapchain_image_views) |image_view| {
            vk.destroyImageView(self.device, image_view, null);
        }
        self.allocator.free(self.swapchain_image_views);

        vk.destroySwapchainKHR(self.device, self.swapchain, null);
        self.allocator.free(self.swapchain_images);
    }

    fn createInstance(self: *Self) !void {
        if (build_options.vulkan_available) {
            const app_info = vk.ApplicationInfo{
                .p_application_name = "MFS Engine",
                .application_version = vk.makeApiVersion(0, 1, 0, 0),
                .p_engine_name = "MFS",
                .engine_version = vk.makeApiVersion(0, 1, 0, 0),
                .api_version = vk.API_VERSION_1_3,
            };

            const extensions = try self.getRequiredExtensions();
            const layers = if (build_options.enable_debug_utils) &[_][*:0]const u8{"VK_LAYER_KHRONOS_validation"} else &[_][*:0]const u8{};

            const instance_create_info = vk.InstanceCreateInfo{
                .p_application_info = &app_info,
                .enabled_layer_count = @intCast(layers.len),
                .pp_enabled_layer_names = layers.ptr,
                .enabled_extension_count = @intCast(extensions.len),
                .pp_enabled_extension_names = extensions.ptr,
            };

            self.instance = try vk.createInstance(&instance_create_info, null);
        } else {
            return VulkanError.InstanceCreationFailed;
        }
    }

    fn getRequiredExtensions(self: *Self) ![]const [*:0]const u8 {
        var glfw_extension_count: u32 = 0;
        const glfw_extensions = glfwGetRequiredInstanceExtensions(&glfw_extension_count);

        var extensions = std.ArrayList([*:0]const u8).init(self.allocator);
        defer extensions.deinit();

        var i: usize = 0;
        while (i < glfw_extension_count) : (i += 1) {
            try extensions.append(glfw_extensions[i]);
        }

        if (build_options.enable_debug_utils) {
            try extensions.append(vk.extension_info.ext_debug_utils.name);
        }

        return extensions.toOwnedSlice();
    }

    fn setupDebugMessenger(self: *Self) !void {
        if (!build_options.enable_debug_utils) return;

        const create_info = vk.DebugUtilsMessengerCreateInfoEXT{
            .message_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
                .verbose_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = vk.DebugUtilsMessageTypeFlagsEXT{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = debugCallback,
            .p_user_data = null,
        };

        self.debug_messenger = try vk.createDebugUtilsMessengerEXT(
            self.instance,
            &create_info,
            null,
        );
    }

    fn pickPhysicalDevice(self: *Self) !void {
        const device_count: u32 = blk: {
            var count: u32 = 0;
            _ = try vk.enumeratePhysicalDevices(self.instance, &count, null);
            break :blk count;
        };

        if (device_count == 0) {
            return VulkanError.NoSuitableDevice;
        }

        const devices = try self.allocator.alloc(vk.PhysicalDevice, device_count);
        defer self.allocator.free(devices);
        _ = try vk.enumeratePhysicalDevices(self.instance, &device_count, devices.ptr);

        for (devices) |device| {
            if (try self.isDeviceSuitable(device)) {
                self.physical_device = device;
                break;
            }
        } else {
            return VulkanError.NoSuitableDevice;
        }
    }

    fn isDeviceSuitable(self: *Self, device: vk.PhysicalDevice) !bool {
        const indices = try self.findQueueFamilies(device);
        const extensions_supported = try self.checkDeviceExtensionSupport(device);
        const swapchain_adequate = if (extensions_supported) blk: {
            const swapchain_support = try self.querySwapchainSupport(device);
            defer swapchain_support.deinit(self.allocator);
            break :blk swapchain_support.formats.len > 0 and
                swapchain_support.present_modes.len > 0;
        } else false;

        var features: vk.PhysicalDeviceFeatures = undefined;
        vk.getPhysicalDeviceFeatures(device, &features);

        return indices.isComplete() and extensions_supported and swapchain_adequate and
            features.sampler_anisotropy == vk.TRUE;
    }

    fn findQueueFamilies(self: *Self, device: vk.PhysicalDevice) !QueueFamilyIndices {
        var indices = QueueFamilyIndices{};
        const queue_family_count: u32 = blk: {
            var count: u32 = 0;
            vk.getPhysicalDeviceQueueFamilyProperties(device, &count, null);
            break :blk count;
        };

        const queue_families = try self.allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
        defer self.allocator.free(queue_families);
        vk.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        var i: u32 = 0;
        while (i < queue_family_count) : (i += 1) {
            if (queue_families[i].queue_flags.graphics_bit) {
                indices.graphics_family = i;
            }

            var present_support: vk.Bool32 = undefined;
            _ = try vk.getPhysicalDeviceSurfaceSupportKHR(
                device,
                i,
                self.surface,
                &present_support,
            );

            if (present_support == vk.TRUE) {
                indices.present_family = i;
            }

            if (indices.isComplete()) {
                break;
            }
        }

        return indices;
    }

    fn checkDeviceExtensionSupport(self: *Self, device: vk.PhysicalDevice) !bool {
        var extension_count: u32 = 0;
        _ = try vk.enumerateDeviceExtensionProperties(device, null, &extension_count, null);

        const available_extensions = try self.allocator.alloc(vk.ExtensionProperties, extension_count);
        defer self.allocator.free(available_extensions);
        _ = try vk.enumerateDeviceExtensionProperties(
            device,
            null,
            &extension_count,
            available_extensions.ptr,
        );

        const required_extensions = [_][*:0]const u8{
            vk.extension_info.khr_swapchain.name,
        };

        for (required_extensions) |required_extension| {
            var found = false;
            for (available_extensions) |extension| {
                if (std.mem.eql(u8, std.mem.span(required_extension), std.mem.span(extension.extension_name[0..]))) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }

        return true;
    }

    fn querySwapchainSupport(self: *Self, device: vk.PhysicalDevice) !SwapchainSupportDetails {
        const details = SwapchainSupportDetails{
            .capabilities = undefined,
            .formats = undefined,
            .present_modes = undefined,
        };

        _ = try vk.getPhysicalDeviceSurfaceCapabilitiesKHR(
            device,
            self.surface,
            &details.capabilities,
        );

        var format_count: u32 = 0;
        _ = try vk.getPhysicalDeviceSurfaceFormatsKHR(
            device,
            self.surface,
            &format_count,
            null,
        );

        if (format_count != 0) {
            details.formats = try self.allocator.alloc(vk.SurfaceFormatKHR, format_count);
            _ = try vk.getPhysicalDeviceSurfaceFormatsKHR(
                device,
                self.surface,
                &format_count,
                details.formats.ptr,
            );
        }

        var present_mode_count: u32 = 0;
        _ = try vk.getPhysicalDeviceSurfacePresentModesKHR(
            device,
            self.surface,
            &present_mode_count,
            null,
        );

        if (present_mode_count != 0) {
            details.present_modes = try self.allocator.alloc(vk.PresentModeKHR, present_mode_count);
            _ = try vk.getPhysicalDeviceSurfacePresentModesKHR(
                device,
                self.surface,
                &present_mode_count,
                details.present_modes.ptr,
            );
        }

        return details;
    }

    fn createLogicalDevice(self: *Self) !void {
        const indices = try self.findQueueFamilies(self.physical_device);

        var unique_queue_families = std.ArrayList(u32).init(self.allocator);
        defer unique_queue_families.deinit();

        if (indices.graphics_family) |family| {
            try unique_queue_families.append(family);
        }
        if (indices.present_family) |family| {
            if (family != indices.graphics_family.?) {
                try unique_queue_families.append(family);
            }
        }

        var queue_create_infos = std.ArrayList(vk.DeviceQueueCreateInfo).init(self.allocator);
        defer queue_create_infos.deinit();

        const queue_priority: f32 = 1.0;
        for (unique_queue_families.items) |queue_family| {
            try queue_create_infos.append(vk.DeviceQueueCreateInfo{
                .queue_family_index = queue_family,
                .queue_count = 1,
                .p_queue_priorities = &queue_priority,
            });
        }

        const device_features = vk.PhysicalDeviceFeatures{
            .sampler_anisotropy = vk.TRUE,
        };

        const device_extensions = [_][*:0]const u8{
            vk.extension_info.khr_swapchain.name,
        };

        const create_info = vk.DeviceCreateInfo{
            .queue_create_info_count = @intCast(queue_create_infos.items.len),
            .p_queue_create_infos = queue_create_infos.items.ptr,
            .enabled_extension_count = device_extensions.len,
            .pp_enabled_extension_names = &device_extensions,
            .p_enabled_features = &device_features,
        };

        self.device = try vk.createDevice(self.physical_device, &create_info, null);

        vk.getDeviceQueue(self.device, indices.graphics_family.?, 0, &self.graphics_queue);
        vk.getDeviceQueue(self.device, indices.present_family.?, 0, &self.present_queue);
    }

    fn createSwapchain(self: *Self) !void {
        const swapchain_support = try self.querySwapchainSupport(self.physical_device);
        defer swapchain_support.deinit(self.allocator);

        const surface_format = try self.chooseSwapSurfaceFormat(swapchain_support.formats);
        const present_mode = try self.chooseSwapPresentMode(swapchain_support.present_modes);
        const extent = try self.chooseSwapExtent(swapchain_support.capabilities);

        var image_count = swapchain_support.capabilities.min_image_count + 1;
        if (swapchain_support.capabilities.max_image_count > 0 and
            image_count > swapchain_support.capabilities.max_image_count)
        {
            image_count = swapchain_support.capabilities.max_image_count;
        }

        const indices = try self.findQueueFamilies(self.physical_device);
        const queue_family_indices = [_]u32{
            indices.graphics_family.?,
            indices.present_family.?,
        };

        const create_info = vk.SwapchainCreateInfoKHR{
            .surface = self.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = vk.ImageUsageFlags{ .color_attachment_bit = true },
            .image_sharing_mode = if (indices.graphics_family.? != indices.present_family.?)
                vk.SharingMode.concurrent
            else
                vk.SharingMode.exclusive,
            .queue_family_index_count = if (indices.graphics_family.? != indices.present_family.?)
                @intCast(queue_family_indices.len)
            else
                0,
            .p_queue_family_indices = if (indices.graphics_family.? != indices.present_family.?)
                &queue_family_indices
            else
                null,
            .pre_transform = swapchain_support.capabilities.current_transform,
            .composite_alpha = vk.CompositeAlphaFlagsKHR{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = null,
        };

        self.swapchain = try vk.createSwapchainKHR(self.device, &create_info, null);
        self.swapchain_image_format = surface_format.format;
        self.swapchain_extent = extent;

        var swapchain_image_count: u32 = 0;
        _ = try vk.getSwapchainImagesKHR(self.device, self.swapchain, &swapchain_image_count, null);

        const swapchain_images = try self.allocator.alloc(vk.Image, swapchain_image_count);
        defer self.allocator.free(swapchain_images);
        _ = try vk.getSwapchainImagesKHR(
            self.device,
            self.swapchain,
            &swapchain_image_count,
            swapchain_images.ptr,
        );

        self.swapchain_images = try self.allocator.dupe(vk.Image, swapchain_images);
    }

    fn createImageViews(self: *Self) !void {
        self.swapchain_image_views = try self.allocator.alloc(vk.ImageView, self.swapchain_images.len);
        errdefer {
            for (self.swapchain_image_views) |image_view| {
                vk.destroyImageView(self.device, image_view, null);
            }
            self.allocator.free(self.swapchain_image_views);
            self.swapchain_image_views = undefined;
        }

        for (self.swapchain_images, 0..) |image, i| {
            const create_info = vk.ImageViewCreateInfo{
                .image = image,
                .view_type = vk.ImageViewType.@"2d",
                .format = self.swapchain_image_format,
                .components = vk.ComponentMapping{
                    .r = vk.ComponentSwizzle.identity,
                    .g = vk.ComponentSwizzle.identity,
                    .b = vk.ComponentSwizzle.identity,
                    .a = vk.ComponentSwizzle.identity,
                },
                .subresource_range = vk.ImageSubresourceRange{
                    .aspect_mask = vk.ImageAspectFlags{ .color_bit = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            };

            self.swapchain_image_views[i] = try vk.createImageView(
                self.device,
                &create_info,
                null,
            );
        }
    }

    fn chooseSwapSurfaceFormat(
        _: *Self,
        available_formats: []const vk.SurfaceFormatKHR,
    ) !vk.SurfaceFormatKHR {
        for (available_formats) |format| {
            if (format.format == vk.Format.b8g8r8a8_srgb and
                format.color_space == vk.ColorSpaceKHR.srgb_nonlinear_khr)
            {
                return format;
            }
        }

        return available_formats[0];
    }

    fn chooseSwapPresentMode(
        _: *Self,
        available_present_modes: []const vk.PresentModeKHR,
    ) !vk.PresentModeKHR {
        for (available_present_modes) |present_mode| {
            if (present_mode == vk.PresentModeKHR.mailbox_khr) {
                return present_mode;
            }
        }

        return vk.PresentModeKHR.fifo_khr;
    }

    fn chooseSwapExtent(
        self: *Self,
        capabilities: vk.SurfaceCapabilitiesKHR,
    ) !vk.Extent2D {
        if (capabilities.current_extent.width != std.math.maxInt(u32)) {
            return capabilities.current_extent;
        }

        var width: i32 = undefined;
        var height: i32 = undefined;
        glfwGetFramebufferSize(self.window, &width, &height);

        const extent = vk.Extent2D{
            .width = @as(u32, @intCast(@max(
                capabilities.min_image_extent.width,
                @min(capabilities.max_image_extent.width, @as(u32, @intCast(width))),
            ))),
            .height = @as(u32, @intCast(@max(
                capabilities.min_image_extent.height,
                @min(capabilities.max_image_extent.height, @as(u32, @intCast(height))),
            ))),
        };

        return extent;
    }

    fn recreateSwapchain(self: *Self) !void {
        var width: i32 = 0;
        var height: i32 = 0;
        glfwGetFramebufferSize(self.window, &width, &height);
        while (width == 0 or height == 0) {
            glfwGetFramebufferSize(self.window, &width, &height);
            glfwWaitEvents();
        }

        _ = try vk.deviceWaitIdle(self.device);

        self.cleanupSwapchain();

        try self.createSwapchain();
        try self.createImageViews();
        try self.createRenderPass();
        try self.createGraphicsPipeline();
        try self.createFramebuffers();
        try self.createCommandBuffers();
    }

    fn createRenderPass(self: *Self) !void {
        const color_attachment = vk.AttachmentDescription{
            .format = self.swapchain_image_format,
            .samples = vk.SampleCountFlags{ .@"1_bit" = true },
            .load_op = vk.AttachmentLoadOp.clear,
            .store_op = vk.AttachmentStoreOp.store,
            .stencil_load_op = vk.AttachmentLoadOp.dont_care,
            .stencil_store_op = vk.AttachmentStoreOp.dont_care,
            .initial_layout = vk.ImageLayout.undefined,
            .final_layout = vk.ImageLayout.present_src_khr,
        };

        const color_attachment_ref = vk.AttachmentReference{
            .attachment = 0,
            .layout = vk.ImageLayout.color_attachment_optimal,
        };

        const subpass = vk.SubpassDescription{
            .pipeline_bind_point = vk.PipelineBindPoint.graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &color_attachment_ref,
        };

        const dependency = vk.SubpassDependency{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = vk.PipelineStageFlags{
                .color_attachment_output_bit = true,
            },
            .src_access_mask = vk.AccessFlags{},
            .dst_stage_mask = vk.PipelineStageFlags{
                .color_attachment_output_bit = true,
            },
            .dst_access_mask = vk.AccessFlags{
                .color_attachment_write_bit = true,
            },
        };

        const create_info = vk.RenderPassCreateInfo{
            .attachment_count = 1,
            .p_attachments = &color_attachment,
            .subpass_count = 1,
            .p_subpasses = &subpass,
            .dependency_count = 1,
            .p_dependencies = &dependency,
        };

        self.render_pass = try vk.createRenderPass(self.device, &create_info, null);
    }

    fn createGraphicsPipeline(self: *Self) !void {
        const vert_shader_code = @embedFile("shaders/triangle.vert.spv");
        const frag_shader_code = @embedFile("shaders/triangle.frag.spv");

        const vert_shader_module = try self.createShaderModule(vert_shader_code);
        defer vk.destroyShaderModule(self.device, vert_shader_module, null);

        const frag_shader_module = try self.createShaderModule(frag_shader_code);
        defer vk.destroyShaderModule(self.device, frag_shader_module, null);

        const vert_shader_stage_info = vk.PipelineShaderStageCreateInfo{
            .stage = vk.ShaderStageFlags{ .vertex_bit = true },
            .module = vert_shader_module,
            .p_name = "main",
        };

        const frag_shader_stage_info = vk.PipelineShaderStageCreateInfo{
            .stage = vk.ShaderStageFlags{ .fragment_bit = true },
            .module = frag_shader_module,
            .p_name = "main",
        };

        const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
            vert_shader_stage_info,
            frag_shader_stage_info,
        };

        const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = 0,
            .p_vertex_binding_descriptions = null,
            .vertex_attribute_description_count = 0,
            .p_vertex_attribute_descriptions = null,
        };

        const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = vk.PrimitiveTopology.triangle_list,
            .primitive_restart_enable = vk.FALSE,
        };

        const viewport = vk.Viewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.swapchain_extent.width),
            .height = @floatFromInt(self.swapchain_extent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        };

        const scissor = vk.Rect2D{
            .offset = vk.Offset2D{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        };

        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = &viewport,
            .scissor_count = 1,
            .p_scissors = &scissor,
        };

        const rasterizer = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = vk.PolygonMode.fill,
            .line_width = 1.0,
            .cull_mode = vk.CullModeFlags{ .back_bit = true },
            .front_face = vk.FrontFace.clockwise,
            .depth_bias_enable = vk.FALSE,
        };

        const multisampling = vk.PipelineMultisampleStateCreateInfo{
            .sample_shading_enable = vk.FALSE,
            .rasterization_samples = vk.SampleCountFlags{ .@"1_bit" = true },
        };

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
            .blend_enable = vk.FALSE,
            .src_color_blend_factor = vk.BlendFactor.one,
            .dst_color_blend_factor = vk.BlendFactor.zero,
            .color_blend_op = vk.BlendOp.add,
            .src_alpha_blend_factor = vk.BlendFactor.one,
            .dst_alpha_blend_factor = vk.BlendFactor.zero,
            .alpha_blend_op = vk.BlendOp.add,
            .color_write_mask = vk.ColorComponentFlags{
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
                .a_bit = true,
            },
        };

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = vk.FALSE,
            .logic_op = vk.LogicOp.copy,
            .attachment_count = 1,
            .p_attachments = &color_blend_attachment,
            .blend_constants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        };

        const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
            .set_layout_count = 0,
            .p_set_layouts = null,
            .push_constant_range_count = 0,
            .p_push_constant_ranges = null,
        };

        self.pipeline_layout = try vk.createPipelineLayout(
            self.device,
            &pipeline_layout_info,
            null,
        );

        const pipeline_info = vk.GraphicsPipelineCreateInfo{
            .stage_count = shader_stages.len,
            .p_stages = &shader_stages,
            .p_vertex_input_state = &vertex_input_info,
            .p_input_assembly_state = &input_assembly,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterizer,
            .p_multisample_state = &multisampling,
            .p_depth_stencil_state = null,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = null,
            .layout = self.pipeline_layout,
            .render_pass = self.render_pass,
            .subpass = 0,
            .base_pipeline_handle = null,
            .base_pipeline_index = -1,
        };

        var pipeline: vk.Pipeline = undefined;
        _ = try vk.createGraphicsPipelines(
            self.device,
            null,
            1,
            &pipeline_info,
            null,
            &pipeline,
        );
        self.graphics_pipeline = pipeline;
    }

    fn createShaderModule(self: *Self, code: []const u8) !vk.ShaderModule {
        const create_info = vk.ShaderModuleCreateInfo{
            .code_size = code.len,
            .p_code = @ptrCast(@alignCast(code.ptr)),
        };

        return try vk.createShaderModule(self.device, &create_info, null);
    }

    fn createFramebuffers(self: *Self) !void {
        self.framebuffers = try self.allocator.alloc(vk.Framebuffer, self.swapchain_image_views.len);
        errdefer {
            for (self.framebuffers) |framebuffer| {
                vk.destroyFramebuffer(self.device, framebuffer, null);
            }
            self.allocator.free(self.framebuffers);
            self.framebuffers = undefined;
        }

        for (self.swapchain_image_views, 0..) |image_view, i| {
            const attachments = [_]vk.ImageView{image_view};

            const framebuffer_info = vk.FramebufferCreateInfo{
                .render_pass = self.render_pass,
                .attachment_count = attachments.len,
                .p_attachments = &attachments,
                .width = self.swapchain_extent.width,
                .height = self.swapchain_extent.height,
                .layers = 1,
            };

            self.framebuffers[i] = try vk.createFramebuffer(
                self.device,
                &framebuffer_info,
                null,
            );
        }
    }

    fn createCommandPool(self: *Self) !void {
        const indices = try self.findQueueFamilies(self.physical_device);

        const pool_info = vk.CommandPoolCreateInfo{
            .flags = vk.CommandPoolCreateFlags{
                .reset_command_buffer_bit = true,
            },
            .queue_family_index = indices.graphics_family.?,
        };

        self.command_pool = try vk.createCommandPool(self.device, &pool_info, null);
    }

    fn createCommandBuffers(self: *Self) !void {
        self.command_buffers = try self.allocator.alloc(
            vk.CommandBuffer,
            self.framebuffers.len,
        );

        const alloc_info = vk.CommandBufferAllocateInfo{
            .command_pool = self.command_pool,
            .level = vk.CommandBufferLevel.primary,
            .command_buffer_count = @intCast(self.command_buffers.len),
        };

        _ = try vk.allocateCommandBuffers(self.device, &alloc_info, self.command_buffers.ptr);

        for (self.command_buffers, 0..) |command_buffer, i| {
            const begin_info = vk.CommandBufferBeginInfo{
                .flags = vk.CommandBufferUsageFlags{
                    .simultaneous_use_bit = true,
                },
            };

            try vk.beginCommandBuffer(command_buffer, &begin_info);

            const clear_color = vk.ClearValue{
                .color = vk.ClearColorValue{
                    .float_32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
                },
            };

            const render_pass_info = vk.RenderPassBeginInfo{
                .render_pass = self.render_pass,
                .framebuffer = self.framebuffers[i],
                .render_area = vk.Rect2D{
                    .offset = vk.Offset2D{ .x = 0, .y = 0 },
                    .extent = self.swapchain_extent,
                },
                .clear_value_count = 1,
                .p_clear_values = &clear_color,
            };

            vk.cmdBeginRenderPass(
                command_buffer,
                &render_pass_info,
                @intFromEnum(vk.SubpassContents.inline),
            );

            vk.cmdBindPipeline(
                command_buffer,
                vk.PipelineBindPoint.graphics,
                self.graphics_pipeline,
            );

            vk.cmdDraw(command_buffer, 3, 1, 0, 0);

            vk.cmdEndRenderPass(command_buffer);

            try vk.endCommandBuffer(command_buffer);
        }
    }

    // ... Additional implementation methods will be added in subsequent edits ...
};

// External C function declarations
extern "c" fn glfwGetRequiredInstanceExtensions(count: *u32) [*][*:0]const u8;
extern "c" fn glfwGetFramebufferSize(window: *glfw.Window, width: *i32, height: *i32) void;
extern "c" fn glfwWaitEvents() void;

fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: *const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.C) vk.Bool32 {
    const severity = if (message_severity.error_bit_ext)
        "ERROR"
    else if (message_severity.warning_bit_ext)
        "WARNING"
    else if (message_severity.info_bit_ext)
        "INFO"
    else
        "VERBOSE";

    const type_str = if (message_type.validation_bit_ext)
        "VALIDATION"
    else if (message_type.performance_bit_ext)
        "PERFORMANCE"
    else
        "GENERAL";

    std.log.err("[{s}] [{s}] {s}", .{
        severity,
        type_str,
        std.mem.span(p_callback_data.p_message),
    });

    return vk.FALSE;
}
