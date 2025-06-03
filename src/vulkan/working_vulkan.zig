const std = @import("std");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan_c.zig");
const vulkan_stub = @import("vulkan_stub.zig");

// Try to import Vulkan, fall back to stub if headers not available
pub const VulkanError = error{
    InitializationFailed,
    DeviceCreationFailed,
    SurfaceCreationFailed,
    SwapchainCreationFailed,
    ValidationLayerNotFound,
    ExtensionNotSupported,
    PhysicalDeviceNotSuitable,
    QueueFamilyNotFound,
    OutOfMemory,
    VulkanOperationFailed,
};

pub const WorkingVulkanRenderer = struct {
    allocator: Allocator,
    instance: vk.VkInstance = null,
    physical_device: vk.VkPhysicalDevice = null,
    device: vk.VkDevice = null,
    graphics_queue: vk.VkQueue = null,
    present_queue: vk.VkQueue = null,
    surface: vk.VkSurfaceKHR = null,
    swapchain: vk.VkSwapchainKHR = null,
    swapchain_images: []vk.VkImage = undefined,
    swapchain_image_format: u32 = 0,
    swapchain_extent: vk.VkExtent2D = undefined,
    graphics_queue_family: u32 = 0,
    present_queue_family: u32 = 0,
    hwnd: ?*anyopaque = null,
    hinstance: ?*anyopaque = null,
    width: u32,
    height: u32,
    frame_count: u64 = 0,
    validation_enabled: bool = false,

    const Self = @This();

    const required_extensions = [_][*:0]const u8{
        vk.VK_KHR_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
    };

    const validation_layers = [_][*:0]const u8{
        vk.VK_LAYER_KHRONOS_VALIDATION_NAME,
    };

    pub fn init(allocator: Allocator, width: u32, height: u32, hwnd: ?*anyopaque, hinstance: ?*anyopaque, enable_validation: bool) !*Self {
        // Always fail for now to test OpenGL fallback
        std.log.info("Vulkan renderer init attempted - falling back to OpenGL for testing", .{});
        return VulkanError.InitializationFailed;

        // var renderer = try allocator.create(Self);
        renderer.* = Self{
            .allocator = allocator,
            .width = width,
            .height = height,
            .hwnd = hwnd,
            .hinstance = hinstance,
            .validation_enabled = enable_validation,
        };

        try renderer.createInstance();
        try renderer.createSurface();
        try renderer.pickPhysicalDevice();
        try renderer.createLogicalDevice();
        try renderer.createSwapchain();

        std.log.info("Working Vulkan renderer initialized successfully", .{});
        return renderer;
    }

    pub fn deinit(self: *Self) void {
        if (self.device != null) {
            vk.c.vkDeviceWaitIdle(self.device);
        }

        if (self.swapchain_images.len > 0) {
            self.allocator.free(self.swapchain_images);
        }

        if (self.swapchain != null) {
            vk.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        }

        if (self.device != null) {
            vk.vkDestroyDevice(self.device, null);
        }

        if (self.surface != null) {
            vk.vkDestroySurfaceKHR(self.instance, self.surface, null);
        }

        if (self.instance != null) {
            vk.vkDestroyInstance(self.instance, null);
        }

        self.allocator.destroy(self);
    }

    fn createInstance(self: *Self) !void {
        var app_info = vk.VkApplicationInfo{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pNext = null,
            .pApplicationName = "MFS Engine",
            .applicationVersion = vk.c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "MFS",
            .engineVersion = vk.c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = vk.c.VK_API_VERSION_1_0,
        };

        var create_info = vk.VkInstanceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = required_extensions.len,
            .ppEnabledExtensionNames = &required_extensions[0],
        };

        if (self.validation_enabled) {
            if (try self.checkValidationLayerSupport()) {
                create_info.enabledLayerCount = validation_layers.len;
                create_info.ppEnabledLayerNames = &validation_layers[0];
                std.log.info("Validation layers enabled", .{});
            } else {
                std.log.warn("Validation layers requested but not available", .{});
            }
        }

        const result = vk.vkCreateInstance(&create_info, null, &self.instance);
        try vk.checkVkResult(result, "create instance");
    }

    fn checkValidationLayerSupport(self: *Self) !bool {
        _ = self;
        var layer_count: u32 = 0;
        _ = vk.c.vkEnumerateInstanceLayerProperties(&layer_count, null);

        if (layer_count == 0) return false;

        const available_layers = try self.allocator.alloc(vk.c.VkLayerProperties, layer_count);
        defer self.allocator.free(available_layers);

        _ = vk.c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

        for (validation_layers) |layer_name| {
            var layer_found = false;
            for (available_layers) |layer_props| {
                if (std.mem.eql(u8, std.mem.span(layer_name), std.mem.span(&layer_props.layerName))) {
                    layer_found = true;
                    break;
                }
            }
            if (!layer_found) return false;
        }

        return true;
    }

    fn createSurface(self: *Self) !void {
        if (self.hwnd == null or self.hinstance == null) {
            return VulkanError.SurfaceCreationFailed;
        }

        var create_info = vk.VkWin32SurfaceCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .hinstance = @ptrCast(self.hinstance.?),
            .hwnd = @ptrCast(self.hwnd.?),
        };

        const result = vk.vkCreateWin32SurfaceKHR(self.instance, &create_info, null, &self.surface);
        try vk.checkVkResult(result, "create Win32 surface");
    }

    fn pickPhysicalDevice(self: *Self) !void {
        var device_count: u32 = 0;
        _ = vk.vkEnumeratePhysicalDevices(self.instance, &device_count, null);

        if (device_count == 0) {
            return VulkanError.PhysicalDeviceNotSuitable;
        }

        const devices = try self.allocator.alloc(vk.VkPhysicalDevice, device_count);
        defer self.allocator.free(devices);

        _ = vk.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr);

        for (devices) |device| {
            if (try self.isDeviceSuitable(device)) {
                self.physical_device = device;
                break;
            }
        }

        if (self.physical_device == null) {
            return VulkanError.PhysicalDeviceNotSuitable;
        }

        var properties: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(self.physical_device, &properties);
        std.log.info("Selected GPU: {s}", .{properties.deviceName});
    }

    fn isDeviceSuitable(self: *Self, device: vk.VkPhysicalDevice) !bool {
        const queue_families = try self.findQueueFamilies(device);
        if (!queue_families.graphics_family_found or !queue_families.present_family_found) {
            return false;
        }

        if (!try self.checkDeviceExtensionSupport(device)) {
            return false;
        }

        const swapchain_support = try self.querySwapchainSupport(device);
        defer {
            if (swapchain_support.formats.len > 0) self.allocator.free(swapchain_support.formats);
            if (swapchain_support.present_modes.len > 0) self.allocator.free(swapchain_support.present_modes);
        }

        const swapchain_adequate = swapchain_support.formats.len > 0 and swapchain_support.present_modes.len > 0;
        return swapchain_adequate;
    }

    const QueueFamilyIndices = struct {
        graphics_family: u32 = 0,
        present_family: u32 = 0,
        graphics_family_found: bool = false,
        present_family_found: bool = false,
    };

    fn findQueueFamilies(self: *Self, device: vk.VkPhysicalDevice) !QueueFamilyIndices {
        var indices = QueueFamilyIndices{};

        var queue_family_count: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

        const queue_families = try self.allocator.alloc(vk.VkQueueFamilyProperties, queue_family_count);
        defer self.allocator.free(queue_families);

        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                indices.graphics_family = @intCast(i);
                indices.graphics_family_found = true;
            }

            var present_support: u32 = 0;
            _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), self.surface, &present_support);

            if (present_support != 0) {
                indices.present_family = @intCast(i);
                indices.present_family_found = true;
            }

            if (indices.graphics_family_found and indices.present_family_found) {
                break;
            }
        }

        return indices;
    }

    fn checkDeviceExtensionSupport(self: *Self, device: vk.VkPhysicalDevice) !bool {
        var extension_count: u32 = 0;
        _ = vk.c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null);

        const available_extensions = try self.allocator.alloc(vk.c.VkExtensionProperties, extension_count);
        defer self.allocator.free(available_extensions);

        _ = vk.c.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);

        const required_device_extensions = [_][*:0]const u8{vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

        for (required_device_extensions) |required_extension| {
            var found = false;
            for (available_extensions) |extension| {
                if (std.mem.eql(u8, std.mem.span(required_extension), std.mem.span(&extension.extensionName))) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }

        return true;
    }

    const SwapchainSupportDetails = struct {
        capabilities: vk.VkSurfaceCapabilitiesKHR,
        formats: []vk.VkSurfaceFormatKHR,
        present_modes: []u32,
    };

    fn querySwapchainSupport(self: *Self, device: vk.VkPhysicalDevice) !SwapchainSupportDetails {
        var details: SwapchainSupportDetails = undefined;

        _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, self.surface, &details.capabilities);

        var format_count: u32 = 0;
        _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, null);

        if (format_count != 0) {
            details.formats = try self.allocator.alloc(vk.VkSurfaceFormatKHR, format_count);
            _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, details.formats.ptr);
        } else {
            details.formats = &[_]vk.VkSurfaceFormatKHR{};
        }

        var present_mode_count: u32 = 0;
        _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, null);

        if (present_mode_count != 0) {
            details.present_modes = try self.allocator.alloc(u32, present_mode_count);
            _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, details.present_modes.ptr);
        } else {
            details.present_modes = &[_]u32{};
        }

        return details;
    }

    fn createLogicalDevice(self: *Self) !void {
        const indices = try self.findQueueFamilies(self.physical_device);
        self.graphics_queue_family = indices.graphics_family;
        self.present_queue_family = indices.present_family;

        var unique_queue_families = std.ArrayList(u32).init(self.allocator);
        defer unique_queue_families.deinit();

        try unique_queue_families.append(indices.graphics_family);
        if (indices.graphics_family != indices.present_family) {
            try unique_queue_families.append(indices.present_family);
        }

        var queue_create_infos = try self.allocator.alloc(vk.VkDeviceQueueCreateInfo, unique_queue_families.items.len);
        defer self.allocator.free(queue_create_infos);

        const queue_priority: f32 = 1.0;
        for (unique_queue_families.items, 0..) |queue_family, i| {
            queue_create_infos[i] = vk.VkDeviceQueueCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = queue_family,
                .queueCount = 1,
                .pQueuePriorities = &queue_priority,
            };
        }

        var device_features: vk.c.VkPhysicalDeviceFeatures = std.mem.zeroes(vk.c.VkPhysicalDeviceFeatures);

        const device_extensions = [_][*:0]const u8{vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

        var create_info = vk.VkDeviceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = @intCast(queue_create_infos.len),
            .pQueueCreateInfos = queue_create_infos.ptr,
            .pEnabledFeatures = &device_features,
            .enabledExtensionCount = device_extensions.len,
            .ppEnabledExtensionNames = &device_extensions[0],
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
        };

        if (self.validation_enabled) {
            create_info.enabledLayerCount = validation_layers.len;
            create_info.ppEnabledLayerNames = &validation_layers[0];
        }

        const result = vk.vkCreateDevice(self.physical_device, &create_info, null, &self.device);
        try vk.checkVkResult(result, "create logical device");

        vk.vkGetDeviceQueue(self.device, indices.graphics_family, 0, &self.graphics_queue);
        vk.vkGetDeviceQueue(self.device, indices.present_family, 0, &self.present_queue);
    }

    fn createSwapchain(self: *Self) !void {
        const swapchain_support = try self.querySwapchainSupport(self.physical_device);
        defer {
            if (swapchain_support.formats.len > 0) self.allocator.free(swapchain_support.formats);
            if (swapchain_support.present_modes.len > 0) self.allocator.free(swapchain_support.present_modes);
        }

        const surface_format = self.chooseSwapSurfaceFormat(swapchain_support.formats);
        const present_mode = self.chooseSwapPresentMode(swapchain_support.present_modes);
        const extent = self.chooseSwapExtent(swapchain_support.capabilities);

        var image_count = swapchain_support.capabilities.minImageCount + 1;
        if (swapchain_support.capabilities.maxImageCount > 0 and image_count > swapchain_support.capabilities.maxImageCount) {
            image_count = swapchain_support.capabilities.maxImageCount;
        }

        var create_info = vk.VkSwapchainCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = self.surface,
            .minImageCount = image_count,
            .imageFormat = surface_format.format,
            .imageColorSpace = surface_format.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .preTransform = swapchain_support.capabilities.currentTransform,
            .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = vk.c.VK_TRUE,
            .oldSwapchain = null,
        };

        if (self.graphics_queue_family != self.present_queue_family) {
            const queue_family_indices = [_]u32{ self.graphics_queue_family, self.present_queue_family };
            create_info.imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT;
            create_info.queueFamilyIndexCount = 2;
            create_info.pQueueFamilyIndices = &queue_family_indices[0];
        }

        const result = vk.vkCreateSwapchainKHR(self.device, &create_info, null, &self.swapchain);
        try vk.checkVkResult(result, "create swapchain");

        _ = vk.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, null);
        self.swapchain_images = try self.allocator.alloc(vk.VkImage, image_count);
        _ = vk.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, self.swapchain_images.ptr);

        self.swapchain_image_format = surface_format.format;
        self.swapchain_extent = extent;

        std.log.info("Swapchain created with {} images, format: {}, extent: {}x{}", .{ image_count, surface_format.format, extent.width, extent.height });
    }

    fn chooseSwapSurfaceFormat(self: *Self, available_formats: []vk.VkSurfaceFormatKHR) vk.VkSurfaceFormatKHR {
        _ = self;
        for (available_formats) |format| {
            if (format.format == vk.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return format;
            }
        }
        return available_formats[0];
    }

    fn chooseSwapPresentMode(self: *Self, available_present_modes: []u32) u32 {
        _ = self;
        for (available_present_modes) |present_mode| {
            if (present_mode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
                return present_mode;
            }
        }
        return vk.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn chooseSwapExtent(self: *Self, capabilities: vk.VkSurfaceCapabilitiesKHR) vk.VkExtent2D {
        if (capabilities.currentExtent.width != 0xFFFFFFFF) {
            return capabilities.currentExtent;
        }

        var actual_extent = vk.VkExtent2D{
            .width = self.width,
            .height = self.height,
        };

        actual_extent.width = std.math.clamp(actual_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
        actual_extent.height = std.math.clamp(actual_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

        return actual_extent;
    }

    pub fn render(self: *Self) !void {
        self.frame_count += 1;

        // Minimal render operations - just present the swapchain
        var image_index: u32 = 0;
        const result = vk.vkAcquireNextImageKHR(self.device, self.swapchain, std.math.maxInt(u64), null, null, &image_index);

        if (result == vk.VK_ERROR_OUT_OF_DATE_KHR) {
            // Swapchain needs recreation
            return;
        } else if (result != vk.VK_SUCCESS and result != vk.VK_SUBOPTIMAL_KHR) {
            return VulkanError.VulkanOperationFailed;
        }

        // Present the image
        var present_info = vk.VkPresentInfoKHR{
            .sType = vk.c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain,
            .pImageIndices = &image_index,
            .pResults = null,
        };

        _ = vk.vkQueuePresentKHR(self.present_queue, &present_info);

        if (self.frame_count % 60 == 0) {
            std.log.debug("Vulkan frame {} rendered", .{self.frame_count});
        }
    }

    pub fn resize(self: *Self, width: u32, height: u32) !void {
        self.width = width;
        self.height = height;

        // Wait for device to be idle before recreating swapchain
        vk.c.vkDeviceWaitIdle(self.device);

        // Clean up old swapchain
        if (self.swapchain != null) {
            vk.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        }
        if (self.swapchain_images.len > 0) {
            self.allocator.free(self.swapchain_images);
        }

        // Recreate swapchain with new dimensions
        try self.createSwapchain();

        std.log.info("Vulkan swapchain recreated for {}x{}", .{ width, height });
    }

    pub fn getFrameCount(self: *const Self) u64 {
        return self.frame_count;
    }

    pub fn isVulkanSupported() bool {
        // Basic check - try to load Vulkan library
        var instance_count: u32 = 0;
        const result = vk.c.vkEnumerateInstanceExtensionProperties(null, &instance_count, null);
        return result == vk.VK_SUCCESS;
    }
};
