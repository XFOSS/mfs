//! MFS Engine Vulkan Backend
//! Modern Vulkan 1.3 implementation with efficient memory management
//! Features:
//! - Pool-based memory allocation
//! - Automatic resource tracking
//! - Modern synchronization primitives
//! - Validation layer support
//! - Debug utilities

const std = @import("std");
const vk = @import("vulkan");
const memory_manager = @import("../../memory/new/memory_manager.zig");
const MemoryManager = memory_manager.MemoryManager;
const MemoryBlock = memory_manager.MemoryBlock;

/// Vulkan validation layers configuration
pub const ValidationConfig = struct {
    enabled: bool = false,
    debug_callback: ?vk.PFN_vkDebugUtilsMessengerCallbackEXT = null,
    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,
};

/// Vulkan device requirements
pub const DeviceRequirements = struct {
    graphics_queue: bool = true,
    compute_queue: bool = false,
    transfer_queue: bool = true,
    present_queue: bool = true,
    ray_tracing: bool = false,
    mesh_shading: bool = false,
    descriptor_indexing: bool = false,
};

/// Vulkan backend configuration
pub const BackendConfig = struct {
    app_name: []const u8,
    engine_name: []const u8,
    validation: ValidationConfig = .{},
    device_requirements: DeviceRequirements = .{},
    pool_size: vk.DeviceSize = 64 * 1024 * 1024, // 64MB default pool size
    min_block_size: vk.DeviceSize = 256,
};

/// Main Vulkan backend
pub const VulkanBackend = struct {
    allocator: std.mem.Allocator,
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    memory_manager: *MemoryManager,
    graphics_queue: vk.Queue,
    transfer_queue: vk.Queue,
    compute_queue: ?vk.Queue,
    present_queue: vk.Queue,
    surface: vk.SurfaceKHR,
    validation: ValidationConfig,

    const Self = @This();

    /// Initialize Vulkan backend
    pub fn init(
        allocator: std.mem.Allocator,
        config: BackendConfig,
        window_handle: *anyopaque,
    ) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Create instance with validation layers if enabled
        self.instance = try createInstance(allocator, config);
        errdefer vk.destroyInstance(self.instance, null);

        // Setup debug messenger if validation is enabled
        if (config.validation.enabled) {
            try setupDebugMessenger(self.instance, &config.validation);
        }

        // Create surface from window handle
        self.surface = try createSurface(self.instance, window_handle);
        errdefer vk.destroySurfaceKHR(self.instance, self.surface, null);

        // Select physical device
        self.physical_device = try selectPhysicalDevice(
            self.instance,
            self.surface,
            config.device_requirements,
        );

        // Create logical device
        const device_info = try createDeviceInfo(
            self.physical_device,
            self.surface,
            config.device_requirements,
        );
        self.device = try vk.createDevice(
            self.physical_device,
            &device_info.create_info,
            null,
        );
        errdefer vk.destroyDevice(self.device, null);

        // Get queue handles
        self.graphics_queue = vk.getDeviceQueue(
            self.device,
            device_info.graphics_family,
            0,
        );
        self.transfer_queue = vk.getDeviceQueue(
            self.device,
            device_info.transfer_family,
            0,
        );
        self.present_queue = vk.getDeviceQueue(
            self.device,
            device_info.present_family,
            0,
        );
        self.compute_queue = if (device_info.compute_family) |family|
            vk.getDeviceQueue(self.device, family, 0)
        else
            null;

        // Initialize memory manager
        self.memory_manager = try MemoryManager.init(
            allocator,
            self.device,
            self.physical_device,
            config.pool_size,
            config.min_block_size,
        );
        errdefer self.memory_manager.deinit();

        return self;
    }

    /// Clean up Vulkan resources
    pub fn deinit(self: *Self) void {
        // Wait for device to be idle
        _ = self.device.deviceWaitIdle() catch {};

        // Clean up memory manager
        self.memory_manager.deinit();

        // Destroy device and instance
        if (self.validation.debug_messenger) |messenger| {
            vk.destroyDebugUtilsMessengerEXT(self.instance, messenger, null);
        }
        vk.destroyDevice(self.device, null);
        vk.destroySurfaceKHR(self.instance, self.surface, null);
        vk.destroyInstance(self.instance, null);

        // Free memory
        self.allocator.destroy(self);
    }

    /// Create buffer with automatic memory allocation
    pub fn createBuffer(
        self: *Self,
        size: vk.DeviceSize,
        usage: vk.BufferUsageFlags,
        memory_properties: vk.MemoryPropertyFlags,
    ) !struct { buffer: vk.Buffer, memory: MemoryBlock } {
        // Create buffer
        const buffer = try self.device.createBuffer(self.allocator, .{
            .size = size,
            .usage = usage,
            .sharingMode = .exclusive,
        });
        errdefer self.device.destroyBuffer(buffer, null);

        // Get memory requirements
        const mem_reqs = self.device.getBufferMemoryRequirements(buffer);

        // Allocate memory
        const memory = try self.memory_manager.allocate(
            mem_reqs.size,
            mem_reqs.alignment,
            mem_reqs.memoryTypeBits,
            memory_properties,
        );
        errdefer self.memory_manager.free(&memory);

        // Bind memory
        try self.device.bindBufferMemory(buffer, memory.memory, memory.offset);

        return .{ .buffer = buffer, .memory = memory };
    }

    /// Create image with automatic memory allocation
    pub fn createImage(
        self: *Self,
        width: u32,
        height: u32,
        format: vk.Format,
        usage: vk.ImageUsageFlags,
        memory_properties: vk.MemoryPropertyFlags,
    ) !struct { image: vk.Image, memory: MemoryBlock } {
        // Create image
        const image = try self.device.createImage(self.allocator, .{
            .imageType = .@"2d",
            .format = format,
            .extent = .{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = usage,
            .sharingMode = .exclusive,
            .initialLayout = .undefined,
        });
        errdefer self.device.destroyImage(image, null);

        // Get memory requirements
        const mem_reqs = self.device.getImageMemoryRequirements(image);

        // Allocate memory
        const memory = try self.memory_manager.allocate(
            mem_reqs.size,
            mem_reqs.alignment,
            mem_reqs.memoryTypeBits,
            memory_properties,
        );
        errdefer self.memory_manager.free(&memory);

        // Bind memory
        try self.device.bindImageMemory(image, memory.memory, memory.offset);

        return .{ .image = image, .memory = memory };
    }

    /// Get memory statistics
    pub fn getMemoryStats(self: *Self) memory_manager.MemoryStats {
        return self.memory_manager.getStats();
    }

    /// Helper functions for instance/device creation
    fn createInstance(
        allocator: std.mem.Allocator,
        config: BackendConfig,
    ) !vk.Instance {
        const app_info = vk.ApplicationInfo{
            .pApplicationName = config.app_name.ptr,
            .applicationVersion = vk.makeApiVersion(0, 1, 0, 0),
            .pEngineName = config.engine_name.ptr,
            .engineVersion = vk.makeApiVersion(0, 1, 0, 0),
            .apiVersion = vk.API_VERSION_1_3,
        };

        var layers = std.ArrayList([*:0]const u8).init(allocator);
        defer layers.deinit();

        if (config.validation.enabled) {
            try layers.append("VK_LAYER_KHRONOS_validation");
        }

        const create_info = vk.InstanceCreateInfo{
            .pApplicationInfo = &app_info,
            .enabledLayerCount = @intCast(layers.items.len),
            .ppEnabledLayerNames = layers.items.ptr,
            .enabledExtensionCount = 0,
            .ppEnabledExtensionNames = null,
        };

        return try vk.createInstance(&create_info, null);
    }

    fn setupDebugMessenger(
        instance: vk.Instance,
        validation: *ValidationConfig,
    ) !void {
        const create_info = vk.DebugUtilsMessengerCreateInfoEXT{
            .messageSeverity = .{
                .verbose_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .messageType = .{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfnUserCallback = validation.debug_callback.?,
            .pUserData = null,
        };

        validation.debug_messenger = try vk.createDebugUtilsMessengerEXT(
            instance,
            &create_info,
            null,
        );
    }

    fn selectPhysicalDevice(
        instance: vk.Instance,
        surface: vk.SurfaceKHR,
        requirements: DeviceRequirements,
    ) !vk.PhysicalDevice {
        var device_count: u32 = undefined;
        _ = try vk.enumeratePhysicalDevices(instance, &device_count, null);

        const devices = try instance.allocator.alloc(
            vk.PhysicalDevice,
            device_count,
        );
        defer instance.allocator.free(devices);

        _ = try vk.enumeratePhysicalDevices(instance, &device_count, devices.ptr);

        // Score and select best device
        var best_score: u32 = 0;
        var best_device: ?vk.PhysicalDevice = null;

        for (devices) |device| {
            const score = try scorePhysicalDevice(device, surface, requirements);
            if (score > best_score) {
                best_score = score;
                best_device = device;
            }
        }

        return best_device orelse error.NoSuitableDevice;
    }

    fn scorePhysicalDevice(
        device: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        requirements: DeviceRequirements,
    ) !u32 {
        var score: u32 = 0;

        // Check device properties
        var properties: vk.PhysicalDeviceProperties = undefined;
        vk.getPhysicalDeviceProperties(device, &properties);

        // Discrete GPUs have a significant performance advantage
        if (properties.deviceType == .discrete_gpu) {
            score += 1000;
        }

        // Check device features
        var features: vk.PhysicalDeviceFeatures = undefined;
        vk.getPhysicalDeviceFeatures(device, &features);

        // Check queue families
        const queue_families = try getQueueFamilies(device, surface);
        if (!queue_families.isComplete(requirements)) {
            return 0;
        }

        // Check device extensions
        if (!try checkDeviceExtensionSupport(device)) {
            return 0;
        }

        // Additional scoring based on device capabilities
        score += properties.limits.maxImageDimension2D;

        return score;
    }

    /// Queue family indices
    const QueueFamilyIndices = struct {
        graphics_family: ?u32 = null,
        compute_family: ?u32 = null,
        transfer_family: ?u32 = null,
        present_family: ?u32 = null,

        fn isComplete(self: QueueFamilyIndices, requirements: DeviceRequirements) bool {
            if (requirements.graphics_queue and self.graphics_family == null) return false;
            if (requirements.compute_queue and self.compute_family == null) return false;
            if (requirements.transfer_queue and self.transfer_family == null) return false;
            if (requirements.present_queue and self.present_family == null) return false;
            return true;
        }
    };

    fn getQueueFamilies(
        device: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
    ) !QueueFamilyIndices {
        var indices = QueueFamilyIndices{};
        var queue_family_count: u32 = undefined;
        vk.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

        const queue_families = try std.heap.page_allocator.alloc(
            vk.QueueFamilyProperties,
            queue_family_count,
        );
        defer std.heap.page_allocator.free(queue_families);

        vk.getPhysicalDeviceQueueFamilyProperties(
            device,
            &queue_family_count,
            queue_families.ptr,
        );

        for (queue_families, 0..) |family, i| {
            const family_index = @as(u32, @intCast(i));

            // Check for graphics support
            if (family.queueFlags.graphics_bit and indices.graphics_family == null) {
                indices.graphics_family = family_index;
            }

            // Check for compute support
            if (family.queueFlags.compute_bit and indices.compute_family == null) {
                indices.compute_family = family_index;
            }

            // Check for transfer support
            if (family.queueFlags.transfer_bit and indices.transfer_family == null) {
                indices.transfer_family = family_index;
            }

            // Check for present support
            var present_support: vk.Bool32 = vk.FALSE;
            _ = try vk.getPhysicalDeviceSurfaceSupportKHR(
                device,
                family_index,
                surface,
                &present_support,
            );

            if (present_support == vk.TRUE and indices.present_family == null) {
                indices.present_family = family_index;
            }
        }

        return indices;
    }

    fn createSurface(
        instance: vk.Instance,
        window_handle: *anyopaque,
    ) !vk.SurfaceKHR {
        // Platform-specific surface creation
        const platform = @import("builtin").target.os.tag;
        switch (platform) {
            .windows => {
                const win32 = @import("std").os.windows;
                const hwnd = @as(win32.HWND, @ptrCast(window_handle));
                const hinstance = win32.kernel32.GetModuleHandleW(null);

                const surface_create_info = vk.Win32SurfaceCreateInfoKHR{
                    .hinstance = hinstance,
                    .hwnd = hwnd,
                };

                return try vk.createWin32SurfaceKHR(
                    instance,
                    &surface_create_info,
                    null,
                );
            },
            .linux => {
                // TODO: Add X11/Wayland surface creation
                return error.PlatformNotSupported;
            },
            else => {
                return error.PlatformNotSupported;
            },
        }
    }

    fn createDeviceInfo(
        physical_device: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        requirements: DeviceRequirements,
    ) !struct {
        create_info: vk.DeviceCreateInfo,
        graphics_family: u32,
        compute_family: ?u32,
        transfer_family: u32,
        present_family: u32,
    } {
        const queue_families = try getQueueFamilies(physical_device, surface);
        if (!queue_families.isComplete(requirements)) {
            return error.MissingQueueFamily;
        }

        var unique_queues = std.ArrayList(u32).init(std.heap.page_allocator);
        defer unique_queues.deinit();

        // Add required queue families
        try unique_queues.append(queue_families.graphics_family.?);
        try unique_queues.append(queue_families.transfer_family.?);
        try unique_queues.append(queue_families.present_family.?);

        if (queue_families.compute_family) |compute| {
            var is_unique = true;
            for (unique_queues.items) |existing| {
                if (existing == compute) {
                    is_unique = false;
                    break;
                }
            }
            if (is_unique) {
                try unique_queues.append(compute);
            }
        }

        // Create queue create infos
        var queue_create_infos = std.ArrayList(vk.DeviceQueueCreateInfo).init(
            std.heap.page_allocator,
        );
        defer queue_create_infos.deinit();

        const queue_priority: f32 = 1.0;
        for (unique_queues.items) |queue_family| {
            try queue_create_infos.append(.{
                .queueFamilyIndex = queue_family,
                .queueCount = 1,
                .pQueuePriorities = &queue_priority,
            });
        }

        // Enable required features
        const features = vk.PhysicalDeviceFeatures{
            .samplerAnisotropy = vk.TRUE,
            .fillModeNonSolid = vk.TRUE,
            .wideLines = vk.TRUE,
            .geometryShader = if (requirements.mesh_shading) vk.TRUE else vk.FALSE,
            .tessellationShader = vk.TRUE,
            .multiViewport = vk.TRUE,
        };

        // Enable required extensions
        const required_extensions = [_][]const u8{
            vk.KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        const create_info = vk.DeviceCreateInfo{
            .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
            .pQueueCreateInfos = queue_create_infos.items.ptr,
            .enabledExtensionCount = required_extensions.len,
            .ppEnabledExtensionNames = &required_extensions,
            .pEnabledFeatures = &features,
        };

        return .{
            .create_info = create_info,
            .graphics_family = queue_families.graphics_family.?,
            .compute_family = queue_families.compute_family,
            .transfer_family = queue_families.transfer_family.?,
            .present_family = queue_families.present_family.?,
        };
    }

    fn checkDeviceExtensionSupport(device: vk.PhysicalDevice) !bool {
        var extension_count: u32 = undefined;
        _ = try vk.enumerateDeviceExtensionProperties(
            device,
            null,
            &extension_count,
            null,
        );

        const available_extensions = try std.heap.page_allocator.alloc(
            vk.ExtensionProperties,
            extension_count,
        );
        defer std.heap.page_allocator.free(available_extensions);

        _ = try vk.enumerateDeviceExtensionProperties(
            device,
            null,
            &extension_count,
            available_extensions.ptr,
        );

        // Check for required extensions
        const required_extensions = [_][]const u8{
            vk.KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        for (required_extensions) |required| {
            var found = false;
            for (available_extensions) |available| {
                if (std.mem.eql(
                    u8,
                    std.mem.span(required),
                    std.mem.sliceTo(&available.extensionName, 0),
                )) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }

        return true;
    }
};
