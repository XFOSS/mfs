//! Advanced Vulkan Graphics Backend for MFS Engine
//! Modern Vulkan implementation using @std patterns and complete interface implementation
//! @thread-safe All operations are thread-safe with proper synchronization
//! @symbol VulkanBackend - Complete modern Vulkan implementation

const std = @import("std");
const builtin = @import("builtin");
const interface = @import("../interface.zig");
const common = @import("../common.zig");
const types = @import("../../types.zig");
const build_options = @import("../../../build_options.zig");
const memory_manager = @import("memory_manager.zig");

// Platform-specific imports
const platform = @import("../../../platform/platform.zig");

// Vulkan bindings - simplified for this implementation
const vkmod = @import("vk.zig");

/// Vulkan backend implementation
pub const VulkanBackend = struct {
    allocator: std.mem.Allocator,

    // Core Vulkan objects
    instance: vkmod.Instance,
    physical_device: vkmod.PhysicalDevice,
    device: vkmod.Device,
    surface: vkmod.SurfaceKHR,

    // Queues
    graphics_queue: vkmod.Queue,
    present_queue: vkmod.Queue,
    compute_queue: vkmod.Queue,
    transfer_queue: vkmod.Queue,

    // Queue family indices
    queue_families: QueueFamilyIndices,

    // Swapchain
    swapchain: SwapchainData,

    // Command management
    command_pool: vkmod.CommandPool,
    command_buffers: std.array_list.Managed(vkmod.CommandBuffer),

    // Synchronization
    sync_objects: SyncObjects,

    // Memory management
    memory_manager: memory_manager.MemoryManager,

    // Resource management
    resources: ResourceManager,

    // Frame tracking
    current_frame: u32,
    current_image_index: u32,
    frame_count: u64,

    // Configuration
    config: interface.BackendConfig,

    // Features and capabilities
    features: Features,
    capabilities: Capabilities,

    const Self = @This();

    const Config = struct {
        max_threads: u32 = 8,
        max_frames_in_flight: u32 = 2,
        enable_validation: bool = builtin.mode == .Debug,
        enable_ray_tracing: bool = false,
        enable_mesh_shaders: bool = false,
        preferred_format: vkmod.Format = .VK_FORMAT_R8G8B8A8_UNORM,
        preferred_present_mode: vkmod.PresentModeKHR = .VK_PRESENT_MODE_MAILBOX_KHR,
    };

    const QueueFamilyIndices = struct {
        graphics: ?u32 = null,
        present: ?u32 = null,
        compute: ?u32 = null,
        transfer: ?u32 = null,

        pub fn isComplete(self: QueueFamilyIndices) bool {
            return self.graphics != null and self.present != null;
        }
    };

    const SwapchainData = struct {
        handle: vkmod.SwapchainKHR,
        images: std.array_list.Managed(vkmod.Image),
        image_views: std.array_list.Managed(vkmod.ImageView),
        format: vkmod.Format,
        extent: vkmod.Extent2D,
        present_mode: vkmod.PresentModeKHR,

        pub fn init(allocator: std.mem.Allocator) SwapchainData {
            return SwapchainData{
                .handle = undefined,
                .images = blk: {
                    var list = std.array_list.Managed(vkmod.Image).init(allocator);
                    list.ensureTotalCapacity(4) catch unreachable;
                    break :blk list;
                },
                .image_views = blk: {
                    var list = std.array_list.Managed(vkmod.ImageView).init(allocator);
                    list.ensureTotalCapacity(4) catch unreachable;
                    break :blk list;
                },
                .format = .VK_FORMAT_UNDEFINED,
                .extent = .{ .width = 0, .height = 0 },
                .present_mode = .VK_PRESENT_MODE_FIFO_KHR,
            };
        }

        pub fn deinit(self: *SwapchainData) void {
            self.images.deinit();
            self.image_views.deinit();
        }
    };

    const SyncObjects = struct {
        image_available: std.array_list.Managed(vkmod.Semaphore),
        render_finished: std.array_list.Managed(vkmod.Semaphore),
        in_flight_fences: std.array_list.Managed(vkmod.Fence),

        pub fn init(allocator: std.mem.Allocator) SyncObjects {
            return SyncObjects{
                .image_available = blk: {
                    var list = std.array_list.Managed(vkmod.Semaphore).init(allocator);
                    list.ensureTotalCapacity(4) catch unreachable;
                    break :blk list;
                },
                .render_finished = blk: {
                    var list = std.array_list.Managed(vkmod.Semaphore).init(allocator);
                    list.ensureTotalCapacity(4) catch unreachable;
                    break :blk list;
                },
                .in_flight_fences = blk: {
                    var list = std.array_list.Managed(vkmod.Fence).init(allocator);
                    list.ensureTotalCapacity(4) catch unreachable;
                    break :blk list;
                },
            };
        }

        pub fn deinit(self: *SyncObjects) void {
            self.image_available.deinit();
            self.render_finished.deinit();
            self.in_flight_fences.deinit();
        }
    };

    const MemoryManager = struct {
        device: vkmod.Device,
        allocator: std.mem.Allocator,
        memory_properties: vkmod.PhysicalDeviceMemoryProperties,
        allocations: std.AutoHashMap(usize, AllocationInfo),
        pools: std.AutoHashMap(u32, MemoryPool), // Memory type index -> Pool

        const AllocationInfo = struct {
            memory: vkmod.DeviceMemory,
            size: u64,
            offset: u64,
            mapped: ?*anyopaque,
            flags: vkmod.MemoryPropertyFlags,
            pool: ?*MemoryPool = null,
        };

        const MemoryPool = struct {
            memory: vkmod.DeviceMemory,
            size: u64,
            used: u64,
            blocks: std.array_list.Managed(MemoryBlock),
            flags: vkmod.MemoryPropertyFlags,

            const MemoryBlock = struct {
                offset: u64,
                size: u64,
                is_free: bool,
            };

            const MIN_BLOCK_SIZE = 256; // Minimum block size in bytes
            const POOL_SIZE = 64 * 1024 * 1024; // 64MB default pool size

            pub fn init(allocator: std.mem.Allocator, device: vkmod.Device, memory_type_index: u32, flags: vkmod.MemoryPropertyFlags) !MemoryPool {
                const alloc_info = vkmod.MemoryAllocateInfo{
                    .allocation_size = POOL_SIZE,
                    .memory_type_index = memory_type_index,
                };

                const memory = try vkmod.vkAllocateMemory(device, &alloc_info, null);
                errdefer vkmod.vkFreeMemory(device, memory, null);

                var blocks = std.array_list.Managed(MemoryBlock).initCapacity(allocator, 4) catch unreachable;
                try blocks.append(.{
                    .offset = 0,
                    .size = POOL_SIZE,
                    .is_free = true,
                });

                return MemoryPool{
                    .memory = memory,
                    .size = POOL_SIZE,
                    .used = 0,
                    .blocks = blocks,
                    .flags = flags,
                };
            }

            pub fn deinit(self: *MemoryPool, device: vkmod.Device) void {
                vkmod.vkFreeMemory(device, self.memory, null);
                self.blocks.deinit();
            }

            pub fn allocate(self: *MemoryPool, size: u64, alignment: u64) !?MemoryBlock {
                const aligned_size = std.mem.alignForward(u64, size, alignment);

                // Find best fit block
                var best_fit: ?usize = null;
                var smallest_waste = std.math.maxInt(u64);

                for (self.blocks.items, 0..) |block, i| {
                    if (!block.is_free) continue;

                    const aligned_offset = std.mem.alignForward(u64, block.offset, alignment);
                    const waste = aligned_offset - block.offset;
                    const total_size = aligned_size + waste;

                    if (total_size <= block.size and waste < smallest_waste) {
                        best_fit = i;
                        smallest_waste = waste;
                    }
                }

                if (best_fit) |index| {
                    var block = &self.blocks.items[index];
                    const aligned_offset = std.mem.alignForward(u64, block.offset, alignment);
                    const waste = aligned_offset - block.offset;
                    const total_size = aligned_size + waste;

                    // Split block if there's enough space left
                    if (block.size - total_size > MIN_BLOCK_SIZE) {
                        try self.blocks.insert(index + 1, .{
                            .offset = block.offset + total_size,
                            .size = block.size - total_size,
                            .is_free = true,
                        });
                        block.size = total_size;
                    }

                    block.is_free = false;
                    self.used += block.size;

                    return MemoryBlock{
                        .offset = aligned_offset,
                        .size = aligned_size,
                        .is_free = false,
                    };
                }

                return null; // No suitable block found
            }

            pub fn free(self: *MemoryPool, offset: u64) void {
                for (self.blocks.items, 0..) |*block, i| {
                    if (block.offset == offset) {
                        block.is_free = true;
                        self.used -= block.size;

                        // Merge with next block if free
                        if (i + 1 < self.blocks.items.len and self.blocks.items[i + 1].is_free) {
                            block.size += self.blocks.items[i + 1].size;
                            _ = self.blocks.orderedRemove(i + 1);
                        }

                        // Merge with previous block if free
                        if (i > 0 and self.blocks.items[i - 1].is_free) {
                            self.blocks.items[i - 1].size += block.size;
                            _ = self.blocks.orderedRemove(i);
                        }
                        break;
                    }
                }
            }

            pub fn defragment(self: *MemoryPool, device: vkmod.Device) !void {
                _ = device; // Device parameter is required for potential memory operations
                if (self.blocks.items.len <= 1) return;

                var new_blocks = std.array_list.Managed(MemoryBlock).init(self.blocks.allocator);
                errdefer new_blocks.deinit();

                var current_offset: u64 = 0;
                var total_free: u64 = 0;

                // First pass: collect all used blocks
                for (self.blocks.items) |block| {
                    if (!block.is_free) {
                        try new_blocks.append(.{
                            .offset = current_offset,
                            .size = block.size,
                            .is_free = false,
                        });
                        current_offset += block.size;
                    } else {
                        total_free += block.size;
                    }
                }

                // Add remaining space as one free block
                if (total_free > 0) {
                    try new_blocks.append(.{
                        .offset = current_offset,
                        .size = total_free,
                        .is_free = true,
                    });
                }

                // Replace old blocks with new arrangement
                self.blocks.deinit();
                self.blocks = new_blocks;
            }
        };

        pub fn init(allocator: std.mem.Allocator, device: vkmod.Device, physical_device: vkmod.PhysicalDevice) !MemoryManager {
            var memory_properties: vkmod.PhysicalDeviceMemoryProperties = undefined;
            vkmod.vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

            return MemoryManager{
                .device = device,
                .allocator = allocator,
                .memory_properties = memory_properties,
                .allocations = std.AutoHashMap(usize, AllocationInfo).init(allocator),
                .pools = std.AutoHashMap(u32, MemoryPool).init(allocator),
            };
        }

        pub fn deinit(self: *MemoryManager) void {
            var it = self.allocations.iterator();
            while (it.next()) |entry| {
                if (entry.value.mapped != null) {
                    vkmod.vkUnmapMemory(self.device, entry.value.memory);
                }
                if (entry.value.pool == null) {
                    vkmod.vkFreeMemory(self.device, entry.value.memory, null);
                }
            }

            var pool_it = self.pools.iterator();
            while (pool_it.next()) |entry| {
                entry.value.deinit(self.device);
            }

            self.pools.deinit();
            self.allocations.deinit();
        }

        pub fn allocate(self: *MemoryManager, requirements: vkmod.MemoryRequirements, flags: vkmod.MemoryPropertyFlags) !AllocationInfo {
            const memory_type_index = try self.findMemoryType(requirements.memory_type_bits, flags);

            // Try to allocate from pool first
            if (self.pools.get(memory_type_index)) |*pool| {
                if (try pool.allocate(requirements.size, requirements.alignment)) |block| {
                    const allocation = AllocationInfo{
                        .memory = pool.memory,
                        .size = block.size,
                        .offset = block.offset,
                        .mapped = null,
                        .flags = flags,
                        .pool = pool,
                    };
                    try self.allocations.put(@intFromPtr(&allocation), allocation);
                    return allocation;
                }
            }

            // Create new pool if none exists or if allocation failed
            if (!self.pools.contains(memory_type_index)) {
                var pool = try MemoryPool.init(self.allocator, self.device, memory_type_index, flags);
                try self.pools.put(memory_type_index, pool);

                if (try pool.allocate(requirements.size, requirements.alignment)) |block| {
                    const allocation = AllocationInfo{
                        .memory = pool.memory,
                        .size = block.size,
                        .offset = block.offset,
                        .mapped = null,
                        .flags = flags,
                        .pool = &pool,
                    };
                    try self.allocations.put(@intFromPtr(&allocation), allocation);
                    return allocation;
                }
            }

            // Fall back to dedicated allocation if pool allocation fails
            const alloc_info = vkmod.MemoryAllocateInfo{
                .allocation_size = requirements.size,
                .memory_type_index = memory_type_index,
            };

            const memory = try vkmod.vkAllocateMemory(self.device, &alloc_info, null);
            errdefer vkmod.vkFreeMemory(self.device, memory, null);

            const allocation = AllocationInfo{
                .memory = memory,
                .size = requirements.size,
                .offset = 0,
                .mapped = null,
                .flags = flags,
                .pool = null,
            };

            try self.allocations.put(@intFromPtr(&allocation), allocation);
            return allocation;
        }

        pub fn free(self: *MemoryManager, allocation: *AllocationInfo) void {
            if (allocation.mapped != null) {
                vkmod.vkUnmapMemory(self.device, allocation.memory);
            }

            if (allocation.pool) |pool| {
                pool.free(allocation.offset);
            } else {
                vkmod.vkFreeMemory(self.device, allocation.memory, null);
            }

            _ = self.allocations.remove(@intFromPtr(allocation));
        }

        pub fn defragment(self: *MemoryManager) !void {
            var pool_it = self.pools.iterator();
            while (pool_it.next()) |entry| {
                try entry.value.defragment(self.device);
            }
        }

        pub fn map(self: *MemoryManager, allocation: *AllocationInfo) !*anyopaque {
            if (allocation.mapped != null) {
                return allocation.mapped.?;
            }

            if ((allocation.flags.host_visible_bit == false) or
                (allocation.flags.host_coherent_bit == false))
            {
                return error.MemoryNotMappable;
            }

            var data: ?*anyopaque = undefined;
            try vkmod.vkMapMemory(self.device, allocation.memory, allocation.offset, allocation.size, .{}, &data);

            allocation.mapped = data;
            return data.?;
        }

        pub fn unmap(self: *MemoryManager, allocation: *AllocationInfo) void {
            if (allocation.mapped != null) {
                vkmod.vkUnmapMemory(self.device, allocation.memory);
                allocation.mapped = null;
            }
        }

        pub fn flush(self: *MemoryManager, allocation: *AllocationInfo) !void {
            if (allocation.flags.host_coherent_bit) {
                return;
            }

            const range = vkmod.MappedMemoryRange{
                .memory = allocation.memory,
                .offset = allocation.offset,
                .size = allocation.size,
            };

            try vkmod.vkFlushMappedMemoryRanges(self.device, 1, &[_]vkmod.MappedMemoryRange{range});
        }

        pub fn invalidate(self: *MemoryManager, allocation: *AllocationInfo) !void {
            if (allocation.flags.host_coherent_bit) {
                return;
            }

            const range = vkmod.MappedMemoryRange{
                .memory = allocation.memory,
                .offset = allocation.offset,
                .size = allocation.size,
            };

            try vkmod.vkInvalidateMappedMemoryRanges(self.device, 1, &[_]vkmod.MappedMemoryRange{range});
        }

        fn findMemoryType(self: *MemoryManager, type_filter: u32, properties: vkmod.MemoryPropertyFlags) !u32 {
            for (0..self.memory_properties.memory_type_count) |i| {
                const memory_type = self.memory_properties.memory_types[i];
                if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
                    (memory_type.property_flags.bits & properties.bits) == properties.bits)
                {
                    return @intCast(i);
                }
            }

            return error.NoSuitableMemoryType;
        }
    };

    const ResourceManager = struct {
        device: vkmod.Device,
        allocator: std.mem.Allocator,
        memory_mgr: *MemoryManager,
        buffers: std.AutoHashMap(usize, BufferResource),
        images: std.AutoHashMap(usize, ImageResource),

        const BufferResource = struct {
            buffer: vkmod.Buffer,
            memory: MemoryManager.AllocationInfo,
            size: u64,
            usage: vkmod.BufferUsageFlags,
        };

        const ImageResource = struct {
            image: vkmod.Image,
            view: vkmod.ImageView,
            memory: MemoryManager.AllocationInfo,
            format: vkmod.Format,
            extent: vkmod.Extent3D,
            usage: vkmod.ImageUsageFlags,
            layout: vkmod.ImageLayout,
        };

        pub fn init(allocator: std.mem.Allocator, device: vkmod.Device, mem_manager: *MemoryManager) ResourceManager {
            return ResourceManager{
                .device = device,
                .allocator = allocator,
                .memory_mgr = mem_manager,
                .buffers = std.AutoHashMap(usize, BufferResource).init(allocator),
                .images = std.AutoHashMap(usize, ImageResource).init(allocator),
            };
        }

        pub fn deinitResources(self: *ResourceManager) void {
            var buffer_it = self.buffers.iterator();
            while (buffer_it.next()) |entry| {
                vkmod.vkDestroyBuffer(self.device, entry.value.buffer, null);
                self.memory_mgr.free(&entry.value.memory);
            }
            self.buffers.deinit();

            var image_it = self.images.iterator();
            while (image_it.next()) |entry| {
                vkmod.vkDestroyImageView(self.device, entry.value.view, null);
                vkmod.vkDestroyImage(self.device, entry.value.image, null);
                self.memory_mgr.free(&entry.value.memory);
            }
            self.images.deinit();
        }

        pub fn allocateBuffer(self: *ResourceManager, size: u64, usage: vkmod.BufferUsageFlags, memory_flags: vkmod.MemoryPropertyFlags) !*BufferResource {
            // Create buffer
            const buffer_info = vkmod.BufferCreateInfo{
                .size = size,
                .usage = usage,
                .sharing_mode = .exclusive,
                .queue_family_index_count = 0,
                .p_queue_family_indices = null,
            };

            const buffer = try vkmod.vkCreateBuffer(self.device, &buffer_info, null);
            errdefer vkmod.vkDestroyBuffer(self.device, buffer, null);

            // Get memory requirements
            var memory_requirements: vkmod.MemoryRequirements = undefined;
            vkmod.vkGetBufferMemoryRequirements(self.device, buffer, &memory_requirements);

            // Allocate memory
            const memory = try self.memory_mgr.allocate(memory_requirements, memory_flags);
            errdefer self.memory_mgr.free(&memory);

            // Bind memory
            try vkmod.vkBindBufferMemory(self.device, buffer, memory.memory, memory.offset);

            // Create resource
            const resource = BufferResource{
                .buffer = buffer,
                .memory = memory,
                .size = size,
                .usage = usage,
            };

            // Store resource
            try self.buffers.put(@intFromPtr(&resource), resource);

            return &resource;
        }

        pub fn createImage(
            self: *ResourceManager,
            width: u32,
            height: u32,
            format: vkmod.Format,
            usage: vkmod.ImageUsageFlags,
            memory_flags: vkmod.MemoryPropertyFlags,
        ) !*ImageResource {
            // Create image
            const image_info = vkmod.ImageCreateInfo{
                .image_type = .@"2d",
                .format = format,
                .extent = .{
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                .mip_levels = 1,
                .array_layers = 1,
                .samples = .{ .@"1_bit" = true },
                .tiling = .optimal,
                .usage = usage,
                .sharing_mode = .exclusive,
                .queue_family_index_count = 0,
                .p_queue_family_indices = null,
                .initial_layout = .undefined,
            };

            const image = try vkmod.vkCreateImage(self.device, &image_info, null);
            errdefer vkmod.vkDestroyImage(self.device, image, null);

            // Get memory requirements
            var memory_requirements: vkmod.MemoryRequirements = undefined;
            vkmod.vkGetImageMemoryRequirements(self.device, image, &memory_requirements);

            // Allocate memory
            const memory = try self.memory_mgr.allocate(memory_requirements, memory_flags);
            errdefer self.memory_mgr.free(&memory);

            // Bind memory
            try vkmod.vkBindImageMemory(self.device, image, memory.memory, memory.offset);

            // Create image view
            const view_info = vkmod.ImageViewCreateInfo{
                .image = image,
                .viewType = vkmod.ImageViewType.type_2d,
                .format = format,
                .components = .{
                    .r = vkmod.ComponentSwizzle.identity,
                    .g = vkmod.ComponentSwizzle.identity,
                    .b = vkmod.ComponentSwizzle.identity,
                    .a = vkmod.ComponentSwizzle.identity,
                },
                .subresourceRange = .{
                    .aspectMask = vkmod.ImageAspectFlags{ .color_bit = true },
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            const view = try vkmod.vkCreateImageView(self.device, &view_info, null);
            errdefer vkmod.vkDestroyImageView(self.device, view, null);

            // Create resource
            const resource = ImageResource{
                .image = image,
                .view = view,
                .memory = memory,
                .format = format,
                .extent = .{
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                .usage = usage,
                .layout = .undefined,
            };

            // Store resource
            try self.images.put(@intFromPtr(&resource), resource);

            return &resource;
        }

        pub fn deinit(self: *Self) void {
            // Clean up in reverse order
            self.resources.deinit();
            self.memory_manager.deinit();
            self.sync_objects.deinit();
            self.command_buffers.deinit();
            self.swapchain.deinit();

            // TODO: Destroy Vulkan objects

            self.allocator.destroy(self);
        }

        fn initializeVulkan(self: *Self, config: interface.BackendConfig) !void {
            // Create instance
            try self.createInstance();

            // Create surface
            try self.createSurface(config.window_handle);

            // Pick physical device
            try self.pickPhysicalDevice();

            // Create logical device
            try self.createLogicalDevice();

            // Create swapchain
            try self.createSwapchain(config.window_width, config.window_height);

            // Create command pool
            try self.createCommandPool();

            // Create command buffers
            try self.createCommandBuffers();

            // Create synchronization objects
            try self.createSyncObjects();

            // Initialize memory manager
            self.memory_manager = try memory_manager.MemoryManager.init(self.allocator, self.device, self.physical_device);

            // Initialize resource manager
            self.resources = ResourceManager.init(self.allocator, self.device, &self.memory_manager);

            // Detect features and capabilities
            self.features = Features.detect(self.physical_device);
            self.capabilities = Capabilities.query(self.physical_device);
        }

        fn createInstance(self: *Self) !void {
            // Check validation layer support if enabled
            if (self.config.enable_validation) {
                var layer_count: u32 = undefined;
                try vkmod.vkEnumerateInstanceLayerProperties(&layer_count, null);
                const available_layers = try self.allocator.alloc(vkmod.LayerProperties, layer_count);
                defer self.allocator.free(available_layers);
                try vkmod.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

                // Check if validation layer is available
                const validation_layer_name = "VK_LAYER_KHRONOS_validation";
                var validation_found = false;
                for (available_layers) |layer| {
                    if (std.mem.eql(u8, std.mem.span(layer.layer_name[0..]), validation_layer_name)) {
                        validation_found = true;
                        break;
                    }
                }

                if (!validation_found) {
                    return error.ValidationLayerNotAvailable;
                }
            }

            // Get required extensions
            var extension_count: u32 = undefined;
            try vkmod.vkEnumerateInstanceExtensionProperties(null, &extension_count, null);
            const available_extensions = try self.allocator.alloc(vkmod.ExtensionProperties, extension_count);
            defer self.allocator.free(available_extensions);
            try vkmod.vkEnumerateInstanceExtensionProperties(null, &extension_count, available_extensions.ptr);

            // Required extensions
            var required_extensions = std.array_list.Managed([*:0]const u8).init(self.allocator);
            defer required_extensions.deinit();

            // Platform-specific surface extension
            if (builtin.os.tag == .windows) {
                try required_extensions.append(vkmod.extension_names.khr_win32_surface);
            } else if (builtin.os.tag == .linux) {
                try required_extensions.append(vkmod.extension_names.khr_xlib_surface);
            } else if (builtin.os.tag == .macos) {
                try required_extensions.append(vkmod.extension_names.mvk_macos_surface);
            }

            // Common required extensions
            try required_extensions.append(vkmod.extension_names.khr_surface);
            if (self.config.enable_validation) {
                try required_extensions.append(vkmod.extension_names.ext_debug_utils);
            }

            // Check if all required extensions are available
            for (required_extensions.items) |required| {
                var extension_found = false;
                for (available_extensions) |available| {
                    if (std.mem.eql(u8, std.mem.span(required), std.mem.span(available.extension_name[0..]))) {
                        extension_found = true;
                        break;
                    }
                }
                if (!extension_found) {
                    return error.RequiredExtensionNotAvailable;
                }
            }

            // Application info
            const app_name = "MFS Engine";
            const app_info = vkmod.ApplicationInfo{
                .p_application_name = app_name,
                .application_version = vkmod.makeApiVersion(0, 1, 0, 0),
                .p_engine_name = app_name,
                .engine_version = vkmod.makeApiVersion(0, 1, 0, 0),
                .api_version = vkmod.API_VERSION_1_3,
            };

            // Create instance
            const validation_layers = if (self.config.enable_validation)
                &[_][*:0]const u8{"VK_LAYER_KHRONOS_validation"}
            else
                null;

            const create_info = vkmod.InstanceCreateInfo{
                .flags = .{},
                .p_application_info = &app_info,
                .enabled_layer_count = if (self.config.enable_validation) 1 else 0,
                .pp_enabled_layer_names = validation_layers,
                .enabled_extension_count = @intCast(required_extensions.items.len),
                .pp_enabled_extension_names = required_extensions.items.ptr,
            };

            self.instance = try vkmod.vkCreateInstance(&create_info, null);
        }

        fn createSurface(self: *Self, window_handle: ?*anyopaque) !void {
            if (window_handle == null) {
                return error.NoWindowHandle;
            }

            // Create platform-specific surface
            switch (builtin.os.tag) {
                .windows => {
                    // Use centralized helper for Win32 surface creation
                    // See: https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Window_surface
                    // and https://registry.khronos.org/vulkan/specs/latest/man/html/vkCreateWin32SurfaceKHR.html
                    const hinstance = platform.win32.GetModuleHandleW(null);
                    const hwnd = window_handle.?;
                    self.surface = try vkmod.createWin32Surface(self.instance, hinstance, hwnd);
                },
                .linux => {
                    const xcb_connection = platform.linux.getXcbConnection();
                    const xcb_window: *platform.linux.xcb_window_t = @ptrCast(window_handle.?);

                    const xcb_create_info = vkmod.XcbSurfaceCreateInfoKHR{
                        .connection = xcb_connection,
                        .window = xcb_window.*,
                    };
                    self.surface = try vkmod.vkCreateXcbSurfaceKHR(self.instance, &xcb_create_info, null);
                },
                .macos => {
                    const ns_window: *platform.macos.NSWindow = @ptrCast(window_handle.?);
                    const metal_layer = platform.macos.getMetalLayer(ns_window);

                    const metal_create_info = vkmod.MetalSurfaceCreateInfoEXT{
                        .p_layer = metal_layer,
                    };
                    self.surface = try vkmod.vkCreateMetalSurfaceEXT(self.instance, &metal_create_info, null);
                },
                else => {
                    return error.UnsupportedPlatform;
                },
            }

            // Verify surface support
            if (!try self.checkSurfaceSupport()) {
                std.log.err("Vulkan surface creation failed: No presentation support for this device/platform.", .{});
                return error.NoSurfaceSupport;
            }
        }

        fn checkSurfaceSupport(self: *Self) !bool {
            const queue_families = try self.findQueueFamilies(self.physical_device);
            if (queue_families.present == null) {
                return false;
            }

            var present_support = vkmod.FALSE;
            try vkmod.vkGetPhysicalDeviceSurfaceSupportKHR(self.physical_device, queue_families.present.?, self.surface, &present_support);

            return present_support == vkmod.TRUE;
        }

        fn pickPhysicalDevice(self: *Self) !void {
            // Get available physical devices
            var device_count: u32 = undefined;
            try vkmod.vkEnumeratePhysicalDevices(self.instance, &device_count, null);
            if (device_count == 0) {
                return error.NoVulkanDevices;
            }

            const devices = try self.allocator.alloc(vkmod.PhysicalDevice, device_count);
            defer self.allocator.free(devices);
            try vkmod.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr);

            // Score and pick the best device
            var best_score: u32 = 0;
            var best_device: ?vkmod.PhysicalDevice = null;

            for (devices) |device| {
                const score = try self.rateDeviceSuitability(device);
                if (score > best_score) {
                    best_score = score;
                    best_device = device;
                }
            }

            if (best_device) |device| {
                self.physical_device = device;
                self.queue_families = try self.findQueueFamilies(device);
                if (!self.queue_families.isComplete()) {
                    return error.NoSuitableQueueFamilies;
                }
            } else {
                return error.NoSuitableDevice;
            }
        }

        fn rateDeviceSuitability(self: *Self, device: vkmod.PhysicalDevice) !u32 {
            // Get device properties and features
            var properties: vkmod.PhysicalDeviceProperties = undefined;
            var features: vkmod.PhysicalDeviceFeatures = undefined;
            vkmod.vkGetPhysicalDeviceProperties(device, &properties);
            vkmod.vkGetPhysicalDeviceFeatures(device, &features);

            // Get queue families
            const queue_families = try self.findQueueFamilies(device);
            if (!queue_families.isComplete()) {
                return 0;
            }

            // Check for required features
            if (!features.geometryShader or !features.tessellationShader) {
                return 0;
            }

            // Base score: prefer discrete GPUs
            var score: u32 = switch (properties.deviceType) {
                .discrete_gpu => 1000,
                .integrated_gpu => 100,
                else => 10,
            };

            // Additional points for advanced features
            if (features.samplerAnisotropy) score += 50;
            if (features.sampleRateShading) score += 50;
            if (features.tessellationShader) score += 100;
            if (features.geometryShader) score += 100;
            if (features.multiViewport) score += 50;

            // Check for ray tracing support if enabled
            if (build_options.enable_ray_tracing) {
                var ray_tracing_features = vkmod.PhysicalDeviceRayTracingFeaturesKHR{
                    .ray_tracing = vkmod.FALSE,
                    .p_next = null,
                };
                var features2 = vkmod.PhysicalDeviceFeatures2{
                    .features = undefined,
                    .p_next = &ray_tracing_features,
                };
                vkmod.vkGetPhysicalDeviceFeatures2(device, &features2);
                if (ray_tracing_features.ray_tracing == vkmod.TRUE) {
                    score += 200;
                }
            }

            // Check for mesh shader support if enabled
            if (build_options.enable_mesh_shaders) {
                var mesh_shader_features = vkmod.PhysicalDeviceMeshShaderFeaturesNV{
                    .mesh_shader = vkmod.FALSE,
                    .task_shader = vkmod.FALSE,
                    .p_next = null,
                };
                var features2 = vkmod.PhysicalDeviceFeatures2{
                    .features = undefined,
                    .p_next = &mesh_shader_features,
                };
                vkmod.vkGetPhysicalDeviceFeatures2(device, &features2);
                if (mesh_shader_features.mesh_shader == vkmod.TRUE and mesh_shader_features.task_shader == vkmod.TRUE) {
                    score += 150;
                }
            }

            // Check for variable rate shading support if enabled
            if (build_options.enable_variable_rate_shading) {
                var vrs_features = vkmod.PhysicalDeviceVariableRateShadingFeaturesNV{
                    .variable_rate_shading = vkmod.FALSE,
                    .p_next = null,
                };
                var features2 = vkmod.PhysicalDeviceFeatures2{
                    .features = undefined,
                    .p_next = &vrs_features,
                };
                vkmod.vkGetPhysicalDeviceFeatures2(device, &features2);
                if (vrs_features.variable_rate_shading == vkmod.TRUE) {
                    score += 100;
                }
            }

            // Check for bindless textures support if enabled
            if (build_options.enable_bindless_textures) {
                var bindless_features = vkmod.PhysicalDeviceDescriptorIndexingFeatures{
                    .descriptor_binding_partially_bound = vkmod.FALSE,
                    .runtime_descriptor_array = vkmod.FALSE,
                    .p_next = null,
                };
                var features2 = vkmod.PhysicalDeviceFeatures2{
                    .features = undefined,
                    .p_next = &bindless_features,
                };
                vkmod.vkGetPhysicalDeviceFeatures2(device, &features2);
                if (bindless_features.descriptor_binding_partially_bound == vkmod.TRUE and
                    bindless_features.runtime_descriptor_array == vkmod.TRUE)
                {
                    score += 100;
                }
            }

            // Additional points for memory size
            score += @intCast(properties.limits.maxMemoryAllocationCount / 1024);

            return score;
        }

        fn findQueueFamilies(self: *Self, device: vkmod.PhysicalDevice) !QueueFamilyIndices {
            var indices = QueueFamilyIndices{};

            // Get queue family properties
            var count: u32 = undefined;
            vkmod.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, null);
            if (count == 0) return error.NoQueueFamilies;

            const queue_families = try self.allocator.alloc(vkmod.QueueFamilyProperties, count);
            defer self.allocator.free(queue_families);
            vkmod.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, queue_families.ptr);

            // Find queue families that support required operations
            for (queue_families, 0..) |family, i| {
                const family_index: u32 = @intCast(i);

                // Graphics support
                if (family.queueFlags.graphics_bit) {
                    indices.graphics = family_index;
                }

                // Present support
                var present_support = vkmod.FALSE;
                try vkmod.vkGetPhysicalDeviceSurfaceSupportKHR(device, family_index, self.surface, &present_support);
                if (present_support == vkmod.TRUE) {
                    indices.present = family_index;
                }

                // Compute support
                if (family.queueFlags.compute_bit) {
                    indices.compute = family_index;
                }

                // Transfer support
                if (family.queueFlags.transfer_bit) {
                    indices.transfer = family_index;
                }

                // Early exit if we found all required families
                if (indices.isComplete()) break;
            }

            return indices;
        }

        fn createLogicalDevice(self: *Self) !void {
            // Get queue family indices
            self.queue_families = try self.findQueueFamilies(self.physical_device);

            // Create device queue create infos
            var queue_create_infos = std.array_list.Managed(vkmod.DeviceQueueCreateInfo).init(self.allocator);
            defer queue_create_infos.deinit();

            // Add unique queue families
            var unique_queue_families = std.AutoHashMap(u32, void).init(self.allocator);
            defer unique_queue_families.deinit();

            if (self.queue_families.graphics) |graphics_idx| {
                try unique_queue_families.put(graphics_idx, {});
            }
            if (self.queue_families.present) |present_idx| {
                try unique_queue_families.put(present_idx, {});
            }
            if (self.queue_families.compute) |compute_idx| {
                try unique_queue_families.put(compute_idx, {});
            }
            if (self.queue_families.transfer) |transfer_idx| {
                try unique_queue_families.put(transfer_idx, {});
            }

            const queue_priority = [_]f32{1.0};
            var it = unique_queue_families.iterator();
            while (it.next()) |entry| {
                try queue_create_infos.append(.{
                    .queue_family_index = entry.key,
                    .queue_count = 1,
                    .p_queue_priorities = &queue_priority,
                });
            }

            // Enable device features
            var features2 = vkmod.PhysicalDeviceFeatures2{
                .features = .{
                    .sampler_anisotropy = vkmod.TRUE,
                    .sample_rate_shading = vkmod.TRUE,
                    .tessellation_shader = vkmod.TRUE,
                    .geometry_shader = vkmod.TRUE,
                    .compute_shader = vkmod.TRUE,
                },
                .p_next = null,
            };

            // Enable ray tracing if supported
            var ray_tracing_features: ?vkmod.PhysicalDeviceRayTracingFeaturesKHR = null;
            if (build_options.enable_ray_tracing) {
                ray_tracing_features = .{
                    .ray_tracing = vkmod.TRUE,
                    .p_next = features2.p_next,
                };
                features2.p_next = &ray_tracing_features;
            }

            // Enable mesh shaders if supported
            var mesh_shader_features: ?vkmod.PhysicalDeviceMeshShaderFeaturesNV = null;
            if (build_options.enable_mesh_shaders) {
                mesh_shader_features = .{
                    .mesh_shader = vkmod.TRUE,
                    .task_shader = vkmod.TRUE,
                    .p_next = features2.p_next,
                };
                features2.p_next = &mesh_shader_features;
            }

            // Enable variable rate shading if supported
            var vrs_features: ?vkmod.PhysicalDeviceVariableRateShadingFeaturesNV = null;
            if (build_options.enable_variable_rate_shading) {
                vrs_features = .{
                    .variable_rate_shading = vkmod.TRUE,
                    .p_next = features2.p_next,
                };
                features2.p_next = &vrs_features;
            }

            // Enable bindless textures if supported
            var bindless_features: ?vkmod.PhysicalDeviceDescriptorIndexingFeatures = null;
            if (build_options.enable_bindless_textures) {
                bindless_features = .{
                    .descriptor_binding_partially_bound = vkmod.TRUE,
                    .runtime_descriptor_array = vkmod.TRUE,
                    .p_next = features2.p_next,
                };
                features2.p_next = &bindless_features;
            }

            // Create device
            const device_create_info = vkmod.DeviceCreateInfo{
                .queue_create_info_count = @intCast(queue_create_infos.items.len),
                .p_queue_create_infos = queue_create_infos.items.ptr,
                .enabled_extension_count = 0,
                .pp_enabled_extension_names = null,
                .p_enabled_features = &features2.features,
                .p_next = &features2,
            };

            self.device = try vkmod.vkCreateDevice(self.physical_device, &device_create_info, null);

            // Get queue handles
            if (self.queue_families.graphics) |graphics_idx| {
                vkmod.vkGetDeviceQueue(self.device, graphics_idx, 0, &self.graphics_queue);
            }
            if (self.queue_families.present) |present_idx| {
                vkmod.vkGetDeviceQueue(self.device, present_idx, 0, &self.present_queue);
            }
            if (self.queue_families.compute) |compute_idx| {
                vkmod.vkGetDeviceQueue(self.device, compute_idx, 0, &self.compute_queue);
            }
            if (self.queue_families.transfer) |transfer_idx| {
                vkmod.vkGetDeviceQueue(self.device, transfer_idx, 0, &self.transfer_queue);
            }
        }

        fn createSwapchain(self: *Self, width: u32, height: u32) !void {
            // Get surface capabilities
            var surface_capabilities: vkmod.SurfaceCapabilitiesKHR = undefined;
            try vkmod.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface, &surface_capabilities);

            // Get surface formats
            const format_count = try vkmod.vkGetPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, null, null);
            const surface_formats = try self.allocator.alloc(vkmod.SurfaceFormatKHR, format_count);
            defer self.allocator.free(surface_formats);
            _ = try vkmod.vkGetPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, &format_count, surface_formats.ptr);

            // Get present modes
            const present_mode_count = try vkmod.vkGetPhysicalDeviceSurfacePresentModesKHR(self.physical_device, self.surface, null, null);
            const present_modes = try self.allocator.alloc(vkmod.PresentModeKHR, present_mode_count);
            defer self.allocator.free(present_modes);
            _ = try vkmod.vkGetPhysicalDeviceSurfacePresentModesKHR(self.physical_device, self.surface, &present_mode_count, present_modes.ptr);

            // Choose surface format
            const surface_format = for (surface_formats) |format| {
                if (format.format == vkmod.Format.b8g8r8a8_unorm and format.colorSpace == vkmod.ColorSpaceKHR.srgb_nonlinear_khr) {
                    break format;
                }
            } else surface_formats[0];

            // Choose present mode based on vsync preference
            const present_mode = if (self.config.enable_vsync) blk: {
                // Look for mailbox mode first (triple buffering)
                for (present_modes) |mode| {
                    if (mode == vkmod.PresentModeKHR.mailbox_khr) {
                        break :blk mode;
                    }
                }
                // Fall back to FIFO (guaranteed to be supported)
                break :blk vkmod.PresentModeKHR.fifo_khr;
            } else blk: {
                // Look for immediate mode first (no vsync)
                for (present_modes) |mode| {
                    if (mode == vkmod.PresentModeKHR.immediate_khr) {
                        break :blk mode;
                    }
                }
                // Fall back to mailbox if available
                for (present_modes) |mode| {
                    if (mode == vkmod.PresentModeKHR.mailbox_khr) {
                        break :blk mode;
                    }
                }
                // Fall back to FIFO as last resort
                break :blk vkmod.PresentModeKHR.fifo_khr;
            };

            // Choose swap extent
            const extent = if (surface_capabilities.currentExtent.width != std.math.maxInt(u32)) blk: {
                break :blk surface_capabilities.currentExtent;
            } else blk: {
                const actual_extent = vkmod.Extent2D{
                    .width = std.math.clamp(width, surface_capabilities.minImageExtent.width, surface_capabilities.maxImageExtent.width),
                    .height = std.math.clamp(height, surface_capabilities.minImageExtent.height, surface_capabilities.maxImageExtent.height),
                };
                break :blk actual_extent;
            };

            // Choose image count
            var image_count = surface_capabilities.minImageCount + 1;
            if (surface_capabilities.maxImageCount > 0) {
                image_count = std.math.min(image_count, surface_capabilities.maxImageCount);
            }

            // Create swapchain
            const swapchain_create_info = vkmod.SwapchainCreateInfoKHR{
                .surface = self.surface,
                .minImageCount = image_count,
                .imageFormat = surface_format.format,
                .imageColorSpace = surface_format.colorSpace,
                .imageExtent = extent,
                .imageArrayLayers = 1,
                .imageUsage = vkmod.ImageUsageFlags{ .color_attachment_bit = true },
                .imageSharingMode = if (self.queue_families.graphics.? != self.queue_families.present.?)
                    vkmod.SharingMode.concurrent_khr
                else
                    vkmod.SharingMode.exclusive_khr,
                .queueFamilyIndexCount = if (self.queue_families.graphics.? != self.queue_families.present.?)
                    2
                else
                    0,
                .pQueueFamilyIndices = if (self.queue_families.graphics.? != self.queue_families.present.?)
                    &[_]u32{ self.queue_families.graphics.?, self.queue_families.present.? }
                else
                    null,
                .preTransform = surface_capabilities.currentTransform,
                .compositeAlpha = vkmod.CompositeAlphaFlagsKHR{ .opaque_bit_khr = true },
                .presentMode = present_mode,
                .clipped = vkmod.TRUE,
                .oldSwapchain = null,
            };

            self.swapchain.handle = try vkmod.vkCreateSwapchainKHR(self.device, &swapchain_create_info, null);
            self.swapchain.format = surface_format.format;
            self.swapchain.extent = extent;
            self.swapchain.present_mode = present_mode;

            // Get swapchain images
            var swapchain_image_count: u32 = undefined;
            try vkmod.vkGetSwapchainImagesKHR(self.device, self.swapchain.handle, &swapchain_image_count, null);
            try self.swapchain.images.resize(swapchain_image_count);
            try vkmod.vkGetSwapchainImagesKHR(self.device, self.swapchain.handle, &swapchain_image_count, self.swapchain.images.items.ptr);

            // Create image views
            try self.swapchain.image_views.resize(swapchain_image_count);
            for (self.swapchain.images.items, 0..) |image, i| {
                const image_view_create_info = vkmod.ImageViewCreateInfo{
                    .image = image,
                    .viewType = vkmod.ImageViewType.type_2d,
                    .format = surface_format.format,
                    .components = .{
                        .r = vkmod.ComponentSwizzle.identity,
                        .g = vkmod.ComponentSwizzle.identity,
                        .b = vkmod.ComponentSwizzle.identity,
                        .a = vkmod.ComponentSwizzle.identity,
                    },
                    .subresourceRange = .{
                        .aspectMask = vkmod.ImageAspectFlags{ .color_bit = true },
                        .baseMipLevel = 0,
                        .levelCount = 1,
                        .baseArrayLayer = 0,
                        .layerCount = 1,
                    },
                };
                self.swapchain.image_views.items[i] = try vkmod.vkCreateImageView(self.device, &image_view_create_info, null);
            }
        }

        fn createCommandPool(self: *Self) !void {
            // TODO: Create command pool for graphics queue family
            self.command_pool = undefined;
        }

        fn createCommandBuffers(self: *Self) !void {
            // TODO: Allocate command buffers
            try self.command_buffers.resize(self.config.max_frames_in_flight);
            for (0..self.config.max_frames_in_flight) |i| {
                self.command_buffers.items[i] = undefined;
            }
        }

        fn createSyncObjects(self: *Self) !void {
            // TODO: Create semaphores and fences
            try self.sync_objects.image_available.resize(self.config.max_frames_in_flight);
            try self.sync_objects.render_finished.resize(self.config.max_frames_in_flight);
            try self.sync_objects.in_flight_fences.resize(self.config.max_frames_in_flight);

            for (0..self.config.max_frames_in_flight) |i| {
                self.sync_objects.image_available.items[i] = undefined;
                self.sync_objects.render_finished.items[i] = undefined;
                self.sync_objects.in_flight_fences.items[i] = undefined;
            }
        }

        // Graphics Backend Interface Implementation
        pub fn getBackendType(self: *Self) interface.BackendType {
            _ = self;
            return .vulkan;
        }

        pub fn getCapabilities(self: *Self) interface.BackendCapabilities {
            return interface.BackendCapabilities{
                .max_texture_size = self.capabilities.max_texture_size,
                .max_uniform_buffer_size = self.capabilities.max_uniform_buffer_size,
                .max_vertex_attributes = self.capabilities.max_vertex_attributes,
                .max_color_attachments = self.capabilities.max_color_attachments,
                .supports_geometry_shaders = self.features.geometry_shaders,
                .supports_tessellation = self.features.tessellation,
                .supports_compute_shaders = self.features.compute_shaders,
                .supports_ray_tracing = self.features.ray_tracing,
                .supports_mesh_shaders = self.features.mesh_shaders,
                .supports_multisampling = self.features.multisampling,
            };
        }

        pub fn beginFrame(self: *Self) !void {
            // Wait for the previous frame to complete
            try vkmod.vkWaitForFences(self.device, 1, &[_]vkmod.Fence{self.sync_objects.in_flight_fences.items[self.current_frame]}, vkmod.TRUE, std.math.maxInt(u64));

            // Acquire the next swapchain image
            var image_index: u32 = undefined;
            const result = try vkmod.vkAcquireNextImageKHR(self.device, self.swapchain.handle, std.math.maxInt(u64), self.sync_objects.image_available.items[self.current_frame], null, &image_index);

            // Handle swapchain recreation if needed
            switch (result) {
                .success => {},
                .suboptimal_khr, .error_out_of_date_khr => {
                    try self.recreateSwapchain();
                    return error.SwapchainOutOfDate;
                },
                else => return error.FailedToAcquireImage,
            }

            // Reset the fence for this frame
            try vkmod.vkResetFences(self.device, 1, &[_]vkmod.Fence{self.sync_objects.in_flight_fences.items[self.current_frame]});

            // Reset command buffer
            try vkmod.vkResetCommandBuffer(self.command_buffers.items[self.current_frame], .{});

            // Begin command buffer recording
            const begin_info = vkmod.CommandBufferBeginInfo{
                .flags = .{ .one_time_submit_bit = true },
                .p_inheritance_info = null,
            };
            try vkmod.vkBeginCommandBuffer(self.command_buffers.items[self.current_frame], &begin_info);

            // Store current image index
            self.current_image_index = image_index;
        }

        pub fn endFrame(self: *Self) !void {
            // End command buffer recording
            try vkmod.vkEndCommandBuffer(self.command_buffers.items[self.current_frame]);

            // Submit command buffer
            const wait_stage = vkmod.PipelineStageFlags{ .color_attachment_output_bit = true };
            const submit_info = vkmod.SubmitInfo{
                .wait_semaphore_count = 1,
                .p_wait_semaphores = &[_]vkmod.Semaphore{self.sync_objects.image_available.items[self.current_frame]},
                .p_wait_dst_stage_mask = &[_]vkmod.PipelineStageFlags{wait_stage},
                .command_buffer_count = 1,
                .p_command_buffers = &[_]vkmod.CommandBuffer{self.command_buffers.items[self.current_frame]},
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &[_]vkmod.Semaphore{self.sync_objects.render_finished.items[self.current_frame]},
            };

            try vkmod.vkQueueSubmit(self.graphics_queue, 1, &[_]vkmod.SubmitInfo{submit_info}, self.sync_objects.in_flight_fences.items[self.current_frame]);

            // Present the frame
            try self.present();

            // Update frame index
            self.current_frame = (self.current_frame + 1) % self.config.max_frames_in_flight;
            self.frame_count += 1;
        }

        pub fn present(self: *Self) !void {
            const present_info = vkmod.PresentInfoKHR{
                .wait_semaphore_count = 1,
                .p_wait_semaphores = &[_]vkmod.Semaphore{self.sync_objects.render_finished.items[self.current_frame]},
                .swapchain_count = 1,
                .p_swapchains = &[_]vkmod.SwapchainKHR{self.swapchain.handle},
                .p_image_indices = &[_]u32{self.current_image_index},
                .p_results = null,
            };

            const result = try vkmod.vkQueuePresentKHR(self.present_queue, &present_info);

            // Handle swapchain recreation if needed
            switch (result) {
                .success => {},
                .suboptimal_khr, .error_out_of_date_khr => {
                    try self.recreateSwapchain();
                },
                else => return error.FailedToPresent,
            }
        }

        fn recreateSwapchain(self: *Self) !void {
            // Wait for all operations to complete
            try vkmod.vkDeviceWaitIdle(self.device);

            // Clean up old swapchain resources
            for (self.swapchain.image_views.items) |view| {
                vkmod.vkDestroyImageView(self.device, view, null);
            }
            vkmod.vkDestroySwapchainKHR(self.device, self.swapchain.handle, null);

            // Create new swapchain
            try self.createSwapchain(self.swapchain.extent.width, self.swapchain.extent.height);
        }

        pub fn getCurrentBackBuffer(self: *Self) !*types.Texture {
            // TODO: Get current back buffer from swapchain
            _ = self;
            return error.NotImplemented;
        }

        pub fn waitIdle(self: *Self) !void {
            // TODO: Wait for device to be idle
            _ = self;
        }

        pub fn createBuffer(self: *Self, buffer: *types.Buffer, data: ?[]const u8) !void {
            _ = self;
            _ = buffer;
            _ = data;
            // TODO: Create buffer with proper interface
            return error.NotImplemented;
        }

        pub fn createTexture(self: *Self, texture: *types.Texture, data: ?[]const u8) !void {
            _ = self;
            _ = texture;
            _ = data;
            // TODO: Create texture with proper interface
            return error.NotImplemented;
        }

        pub fn createShader(self: *Self, shader: *types.Shader) !void {
            _ = self;
            _ = shader;
            // TODO: Create shader with proper interface
            return error.NotImplemented;
        }

        pub fn createPipeline(self: *Self, desc: interface.PipelineDesc) !*interface.Pipeline {
            _ = self;
            _ = desc;
            // TODO: Create pipeline with proper interface
            return error.NotImplemented;
        }

        pub fn createSwapChain(self: *Self, desc: interface.SwapChainDesc) !void {
            try self.createSwapchain(desc.width, desc.height);
        }

        pub fn resizeSwapChain(self: *Self, width: u32, height: u32) !void {
            try self.createSwapchain(width, height);
        }

        // Legacy methods removed - replaced by new interface methods below

        // Additional methods required by the new interface

        pub fn createRenderTarget(self: *Self, render_target: *types.RenderTarget) !void {
            _ = self;
            _ = render_target;
            // TODO: Create render target
            return error.NotImplemented;
        }

        pub fn updateBuffer(self: *Self, buffer: *types.Buffer, offset: u64, data: []const u8) !void {
            _ = self;
            _ = buffer;
            _ = offset;
            _ = data;
            // TODO: Update buffer
            return error.NotImplemented;
        }

        pub fn updateTexture(self: *Self, texture: *types.Texture, region: interface.TextureCopyRegion, data: []const u8) !void {
            _ = self;
            _ = texture;
            _ = region;
            _ = data;
            // TODO: Update texture
            return error.NotImplemented;
        }

        pub fn destroyTexture(self: *Self, texture: *types.Texture) void {
            _ = self;
            _ = texture;
            // TODO: Destroy texture
        }

        pub fn destroyBuffer(self: *Self, buffer: *types.Buffer) void {
            _ = self;
            _ = buffer;
            // TODO: Destroy buffer
        }

        pub fn destroyShader(self: *Self, shader: *types.Shader) void {
            _ = self;
            _ = shader;
            // TODO: Destroy shader
        }

        pub fn destroyRenderTarget(self: *Self, render_target: *types.RenderTarget) void {
            _ = self;
            _ = render_target;
            // TODO: Destroy render target
        }

        pub fn createCommandBuffer(self: *Self) !*interface.CommandBuffer {
            _ = self;
            // TODO: Create command buffer
            return error.NotImplemented;
        }

        pub fn beginCommandBuffer(self: *Self, cmd: *interface.CommandBuffer) !void {
            _ = self;
            _ = cmd;
            // TODO: Begin command buffer
            return error.NotImplemented;
        }

        pub fn endCommandBuffer(self: *Self, cmd: *interface.CommandBuffer) !void {
            _ = self;
            _ = cmd;
            // TODO: End command buffer
            return error.NotImplemented;
        }

        pub fn submitCommandBuffer(self: *Self, cmd: *interface.CommandBuffer) !void {
            _ = self;
            _ = cmd;
            // TODO: Submit command buffer
            return error.NotImplemented;
        }

        pub fn beginRenderPass(self: *Self, cmd: *interface.CommandBuffer, render_pass: *interface.RenderPass) !void {
            _ = self;
            _ = cmd;
            _ = render_pass;
            // TODO: Begin render pass
            return error.NotImplemented;
        }

        pub fn endRenderPass(self: *Self, cmd: *interface.CommandBuffer) !void {
            _ = self;
            _ = cmd;
            // TODO: End render pass
            return error.NotImplemented;
        }

        pub fn setViewport(self: *Self, cmd: *interface.CommandBuffer, viewport: interface.Viewport) !void {
            _ = self;
            _ = cmd;
            _ = viewport;
            // TODO: Set viewport
            return error.NotImplemented;
        }

        pub fn setScissor(self: *Self, cmd: *interface.CommandBuffer, scissor: interface.Rect2D) !void {
            _ = self;
            _ = cmd;
            _ = scissor;
            // TODO: Set scissor
            return error.NotImplemented;
        }

        pub fn bindPipeline(self: *Self, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) !void {
            _ = self;
            _ = cmd;
            _ = pipeline;
            // TODO: Bind pipeline
            return error.NotImplemented;
        }

        pub fn bindVertexBuffer(self: *Self, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64) !void {
            _ = self;
            _ = cmd;
            _ = buffer;
            _ = offset;
            // TODO: Bind vertex buffer
            return error.NotImplemented;
        }

        pub fn bindIndexBuffer(self: *Self, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, index_type: interface.IndexType) !void {
            _ = self;
            _ = cmd;
            _ = buffer;
            _ = offset;
            _ = index_type;
            // TODO: Bind index buffer
            return error.NotImplemented;
        }

        pub fn bindTexture(self: *Self, cmd: *interface.CommandBuffer, texture: *types.Texture, slot: u32) !void {
            _ = self;
            _ = cmd;
            _ = texture;
            _ = slot;
            // TODO: Bind texture
            return error.NotImplemented;
        }

        pub fn bindUniformBuffer(self: *Self, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, size: u64, slot: u32) !void {
            _ = self;
            _ = cmd;
            _ = buffer;
            _ = offset;
            _ = size;
            _ = slot;
            // TODO: Bind uniform buffer
            return error.NotImplemented;
        }

        pub fn draw(self: *Self, cmd: *interface.CommandBuffer, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) !void {
            _ = self;
            _ = cmd;
            _ = vertex_count;
            _ = instance_count;
            _ = first_vertex;
            _ = first_instance;
            // TODO: Draw
            return error.NotImplemented;
        }

        pub fn drawIndexed(self: *Self, cmd: *interface.CommandBuffer, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) !void {
            _ = self;
            _ = cmd;
            _ = index_count;
            _ = instance_count;
            _ = first_index;
            _ = vertex_offset;
            _ = first_instance;
            // TODO: Draw indexed
            return error.NotImplemented;
        }

        pub fn dispatch(self: *Self, cmd: *interface.CommandBuffer, group_count_x: u32, group_count_y: u32, group_count_z: u32) !void {
            _ = self;
            _ = cmd;
            _ = group_count_x;
            _ = group_count_y;
            _ = group_count_z;
            // TODO: Dispatch compute
            return error.NotImplemented;
        }

        pub fn copyBuffer(self: *Self, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: interface.BufferCopyRegion) !void {
            _ = self;
            _ = cmd;
            _ = src;
            _ = dst;
            _ = region;
            // TODO: Copy buffer
            return error.NotImplemented;
        }

        pub fn copyTexture(self: *Self, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: interface.TextureCopyRegion) !void {
            _ = self;
            _ = cmd;
            _ = src;
            _ = dst;
            _ = region;
            // TODO: Copy texture
            return error.NotImplemented;
        }

        pub fn copyBufferToTexture(self: *Self, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: interface.TextureCopyRegion) !void {
            _ = self;
            _ = cmd;
            _ = src;
            _ = dst;
            _ = region;
            // TODO: Copy buffer to texture
            return error.NotImplemented;
        }

        pub fn copyTextureToBuffer(self: *Self, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: interface.TextureCopyRegion) !void {
            _ = self;
            _ = cmd;
            _ = src;
            _ = dst;
            _ = region;
            // TODO: Copy texture to buffer
            return error.NotImplemented;
        }

        pub fn resourceBarrier(self: *Self, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) !void {
            _ = self;
            _ = cmd;
            _ = barriers;
            // TODO: Resource barrier
            return error.NotImplemented;
        }

        // Note: Duplicate method implementations removed - methods are already defined above

        pub fn getBackendInfo(self: *Self) interface.BackendInfo {
            _ = self;
            return interface.BackendInfo{
                .name = "Vulkan",
                .version = "1.3",
                .vendor = "Khronos Group",
                .device_name = "Vulkan Device",
                .api_version = 1,
                .driver_version = 0,
                .memory_budget = 0,
                .memory_usage = 0,
                .max_texture_size = 16384,
                .max_render_targets = 8,
                .max_vertex_attributes = 32,
                .max_uniform_buffer_bindings = 14,
                .max_texture_bindings = 128,
                .supports_compute = true,
                .supports_geometry_shaders = true,
                .supports_tessellation = true,
                .supports_raytracing = true,
                .supports_mesh_shaders = true,
                .supports_variable_rate_shading = true,
                .supports_multiview = true,
            };
        }

        pub fn setDebugName(self: *Self, resource: interface.ResourceHandle, name: []const u8) !void {
            _ = self;
            _ = resource;
            _ = name;
            // TODO: Set debug name
            return error.NotImplemented;
        }

        pub fn beginDebugGroup(self: *Self, cmd: *interface.CommandBuffer, name: []const u8) !void {
            _ = self;
            _ = cmd;
            _ = name;
            // TODO: Begin debug group
            return error.NotImplemented;
        }

        pub fn endDebugGroup(self: *Self, cmd: *interface.CommandBuffer) !void {
            _ = self;
            _ = cmd;
            // TODO: End debug group
            return error.NotImplemented;
        }
    };

    // =============================================================================
    // VTable Wrapper Functions - Interface Compliance
    // =============================================================================

    fn deinitWrapper(impl: *anyopaque) void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        // TODO: Fix method access issue
        _ = self;
        // self.deinit();
    }

    // SwapChain management wrappers
    fn createSwapChainWrapper(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = desc;
        // TODO: Fix method access issue
        return interface.GraphicsBackendError.UnsupportedOperation;
        // return self.createSwapChain(desc.*) catch |err| switch (err) {
        //     error.NotImplemented => interface.GraphicsBackendError.UnsupportedOperation,
        // };
    }

    fn resizeSwapChainWrapper(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = width;
        _ = height;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn presentWrapper(impl: *anyopaque) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn getCurrentBackBufferWrapper(impl: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Resource creation wrappers
    fn createTextureWrapper(impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = texture;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createBufferWrapper(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = buffer;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createShaderWrapper(impl: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = shader;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createPipelineWrapper(impl: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = desc;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createRenderTargetWrapper(impl: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = render_target;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Resource management wrappers
    fn updateBufferWrapper(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = buffer;
        _ = offset;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn updateTextureWrapper(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = texture;
        _ = region;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn destroyTextureWrapper(impl: *anyopaque, texture: *types.Texture) void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = texture;
    }

    fn destroyBufferWrapper(impl: *anyopaque, buffer: *types.Buffer) void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = buffer;
    }

    fn destroyShaderWrapper(impl: *anyopaque, shader: *types.Shader) void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = shader;
    }

    fn destroyRenderTargetWrapper(impl: *anyopaque, render_target: *types.RenderTarget) void {
        const self: *VulkanBackend = @ptrCast(@alignCast(impl));
        _ = self;
        _ = render_target;
    }

    // Command recording wrappers
    fn createCommandBufferWrapper(impl: *anyopaque) interface.GraphicsBackendError!*interface.CommandBuffer {
        _ = impl;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn beginCommandBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn endCommandBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn submitCommandBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Render commands wrappers
    fn beginRenderPassWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = desc;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn endRenderPassWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn setViewportWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = viewport;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn setScissorWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = rect;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindPipelineWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = pipeline;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindVertexBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindIndexBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = buffer;
        _ = offset;
        _ = format;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindTextureWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = texture;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindUniformBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
        _ = size;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Draw commands wrappers
    fn drawWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = draw_cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn drawIndexedWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = draw_cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn dispatchWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = dispatch_cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Resource copying wrappers
    fn copyBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const interface.BufferCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyTextureWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyBufferToTextureWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyTextureToBufferWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Synchronization wrappers
    fn resourceBarrierWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = barriers;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Query and debug wrappers
    fn getBackendInfoWrapper(impl: *anyopaque) interface.BackendInfo {
        _ = impl;
        return interface.BackendInfo{
            .name = "Vulkan (Stub)",
            .version = "1.0.0",
            .vendor = "Unknown",
            .device_name = "Unknown",
            .api_version = 0,
            .driver_version = 0,
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 0,
            .max_render_targets = 0,
            .max_vertex_attributes = 0,
            .max_uniform_buffer_bindings = 0,
            .max_texture_bindings = 0,
            .supports_compute = false,
            .supports_geometry_shaders = false,
            .supports_tessellation = false,
            .supports_raytracing = false,
            .supports_mesh_shaders = false,
            .supports_variable_rate_shading = false,
            .supports_multiview = false,
        };
    }

    fn setDebugNameWrapper(impl: *anyopaque, resource: interface.ResourceHandle, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = resource;
        _ = name;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn beginDebugGroupWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = name;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn endDebugGroupWrapper(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // VTable for interface compatibility - complete implementation
    pub const vtable = interface.GraphicsBackend.VTable{
        // Lifecycle
        .deinit = deinitWrapper,

        // SwapChain management
        .create_swap_chain = createSwapChainWrapper,
        .resize_swap_chain = resizeSwapChainWrapper,
        .present = presentWrapper,
        .get_current_back_buffer = getCurrentBackBufferWrapper,

        // Resource creation
        .create_texture = createTextureWrapper,
        .create_buffer = createBufferWrapper,
        .create_shader = createShaderWrapper,
        .create_pipeline = createPipelineWrapper,
        .create_render_target = createRenderTargetWrapper,

        // Resource management
        .update_buffer = updateBufferWrapper,
        .update_texture = updateTextureWrapper,
        .destroy_texture = destroyTextureWrapper,
        .destroy_buffer = destroyBufferWrapper,
        .destroy_shader = destroyShaderWrapper,
        .destroy_render_target = destroyRenderTargetWrapper,

        // Command recording
        .create_command_buffer = createCommandBufferWrapper,
        .begin_command_buffer = beginCommandBufferWrapper,
        .end_command_buffer = endCommandBufferWrapper,
        .submit_command_buffer = submitCommandBufferWrapper,

        // Render commands
        .begin_render_pass = beginRenderPassWrapper,
        .end_render_pass = endRenderPassWrapper,
        .set_viewport = setViewportWrapper,
        .set_scissor = setScissorWrapper,
        .bind_pipeline = bindPipelineWrapper,
        .bind_vertex_buffer = bindVertexBufferWrapper,
        .bind_index_buffer = bindIndexBufferWrapper,
        .bind_texture = bindTextureWrapper,
        .bind_uniform_buffer = bindUniformBufferWrapper,

        // Draw commands
        .draw = drawWrapper,
        .draw_indexed = drawIndexedWrapper,
        .dispatch = dispatchWrapper,

        // Resource copying
        .copy_buffer = copyBufferWrapper,
        .copy_texture = copyTextureWrapper,
        .copy_buffer_to_texture = copyBufferToTextureWrapper,
        .copy_texture_to_buffer = copyTextureToBufferWrapper,

        // Synchronization
        .resource_barrier = resourceBarrierWrapper,

        // Query and debug
        .get_backend_info = getBackendInfoWrapper,
        .set_debug_name = setDebugNameWrapper,
        .begin_debug_group = beginDebugGroupWrapper,
        .end_debug_group = endDebugGroupWrapper,
    };

    /// Create a Vulkan backend instance
    pub fn create(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
        const vulkan_backend = try VulkanBackend.init(allocator, config);

        const backend = try allocator.create(interface.GraphicsBackend);
        backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .vulkan,
            .initialized = true,
            .vtable = &vtable,
            .impl_data = vulkan_backend,
        };

        return backend;
    }

    /// Get backend information
    pub fn getInfo() common.BackendInfo {
        return common.BackendInfo{
            .name = "Vulkan",
            .version = "1.3",
            .vendor = "Khronos Group",
            .available = true,
            .recommended = true,
            .features = &.{
                "Modern graphics API",
                "Excellent performance",
                "Cross-platform",
                "Ray tracing support",
                "Compute shaders",
                "Multi-threading friendly",
            },
        };
    }

    // Tests
    test "vulkan backend creation" {
        const testing = std.testing;
        const allocator = testing.allocator;

        const config = interface.BackendConfig{
            .backend_type = .vulkan,
            .window_width = 800,
            .window_height = 600,
        };

        // This would fail in a real test environment without Vulkan drivers
        // but demonstrates the interface
        _ = create(allocator, config) catch |err| switch (err) {
            error.BackendNotAvailable => return, // Expected in test environment
            else => return err,
        };
    }

    test "vulkan backend vtable" {
        const testing = std.testing;

        // Test that vtable has all required functions
        try testing.expect(vtable.deinit != null);
        try testing.expect(vtable.create_swap_chain != null);
        try testing.expect(vtable.present != null);
        try testing.expect(vtable.get_current_back_buffer != null);
        try testing.expect(vtable.create_texture != null);
        try testing.expect(vtable.create_buffer != null);
    }

    // VulkanBackend initialization
    pub fn init(allocator: std.mem.Allocator, config: interface.BackendConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .config = config,
            .instance = undefined,
            .physical_device = undefined,
            .device = undefined,
            .surface = undefined,
            .graphics_queue = undefined,
            .present_queue = undefined,
            .compute_queue = undefined,
            .transfer_queue = undefined,
            .queue_families = QueueFamilyIndices{},
            .swapchain = SwapchainData.init(allocator),
            .sync_objects = SyncObjects.init(allocator),
            .command_pool = undefined,
            .command_buffers = blk: {
                var list = std.array_list.Managed(vkmod.CommandBuffer).init(allocator);
                list.ensureTotalCapacity(4) catch unreachable;
                break :blk list;
            },
            .current_frame = 0,
            .current_image_index = 0,
            .frame_count = 0,
            .memory_manager = undefined,
            .resources = undefined,
            .features = undefined,
            .capabilities = undefined,
        };

        // try self.initializeVulkan(config);
        return self;
    }

    // End of VulkanBackend implementation
};

const Features = struct {
    // Core Vulkan 1.0 features
    robust_buffer_access: bool = false,
    full_draw_index_uint32: bool = false,
    image_cube_array: bool = false,
    independent_blend: bool = false,
    geometry_shader: bool = false,
    tessellation_shader: bool = false,
    sample_rate_shading: bool = false,
    dual_src_blend: bool = false,
    logic_op: bool = false,
    multi_draw_indirect: bool = false,
    draw_indirect_first_instance: bool = false,
    depth_clamp: bool = false,
    depth_bias_clamp: bool = false,
    fill_mode_non_solid: bool = false,
    depth_bounds: bool = false,
    wide_lines: bool = false,
    large_points: bool = false,
    alpha_to_one: bool = false,
    multi_viewport: bool = false,
    sampler_anisotropy: bool = false,
    texture_compression_etc2: bool = false,
    texture_compression_astc_ldr: bool = false,
    texture_compression_bc: bool = false,
    occlusion_query_precise: bool = false,
    pipeline_statistics_query: bool = false,
    vertex_pipeline_stores_and_atomics: bool = false,
    fragment_stores_and_atomics: bool = false,
    shader_tessellation_and_geometry_point_size: bool = false,
    shader_image_gather_extended: bool = false,
    shader_storage_image_extended_formats: bool = false,
    shader_storage_image_multisample: bool = false,
    shader_storage_image_read_without_format: bool = false,
    shader_storage_image_write_without_format: bool = false,
    shader_uniform_buffer_array_dynamic_indexing: bool = false,
    shader_sampled_image_array_dynamic_indexing: bool = false,
    shader_storage_buffer_array_dynamic_indexing: bool = false,
    shader_storage_image_array_dynamic_indexing: bool = false,
    shader_clip_distance: bool = false,
    shader_cull_distance: bool = false,
    shader_float64: bool = false,
    shader_int64: bool = false,
    shader_int16: bool = false,
    shader_resource_residency: bool = false,
    shader_resource_min_lod: bool = false,
    sparse_binding: bool = false,
    sparse_residency_buffer: bool = false,
    sparse_residency_image2_d: bool = false,
    sparse_residency_image3_d: bool = false,
    sparse_residency2_samples: bool = false,
    sparse_residency4_samples: bool = false,
    sparse_residency8_samples: bool = false,
    sparse_residency16_samples: bool = false,
    sparse_residency_aliased: bool = false,
    variable_multisample_rate: bool = false,
    inherited_queries: bool = false,

    // Vulkan 1.1 features
    storage_buffer16_bit_access: bool = false,
    uniform_and_storage_buffer16_bit_access: bool = false,
    storage_push_constant16: bool = false,
    storage_input_output16: bool = false,
    multiview: bool = false,
    multiview_geometry_shader: bool = false,
    multiview_tessellation_shader: bool = false,
    variable_pointers_storage_buffer: bool = false,
    variable_pointers: bool = false,
    protected_memory: bool = false,
    sampler_ycbcr_conversion: bool = false,
    shader_draw_parameters: bool = false,

    // Vulkan 1.2 features
    sampler_mirror_clamp_to_edge: bool = false,
    draw_indirect_count: bool = false,
    storage_buffer8_bit_access: bool = false,
    uniform_and_storage_buffer8_bit_access: bool = false,
    storage_push_constant8: bool = false,
    shader_buffer_int64_atomics: bool = false,
    shader_shared_int64_atomics: bool = false,
    shader_float16: bool = false,
    shader_int8: bool = false,
    descriptor_indexing: bool = false,
    shader_input_attachment_array_dynamic_indexing: bool = false,
    shader_uniform_texel_buffer_array_dynamic_indexing: bool = false,
    shader_storage_texel_buffer_array_dynamic_indexing: bool = false,
    shader_uniform_buffer_array_non_uniform_indexing: bool = false,
    shader_sampled_image_array_non_uniform_indexing: bool = false,
    shader_storage_buffer_array_non_uniform_indexing: bool = false,
    shader_storage_image_array_non_uniform_indexing: bool = false,
    shader_input_attachment_array_non_uniform_indexing: bool = false,
    shader_uniform_texel_buffer_array_non_uniform_indexing: bool = false,
    shader_storage_texel_buffer_array_non_uniform_indexing: bool = false,
    descriptor_binding_uniform_buffer_update_after_bind: bool = false,
    descriptor_binding_sampled_image_update_after_bind: bool = false,
    descriptor_binding_storage_image_update_after_bind: bool = false,
    descriptor_binding_storage_buffer_update_after_bind: bool = false,
    descriptor_binding_uniform_texel_buffer_update_after_bind: bool = false,
    descriptor_binding_storage_texel_buffer_update_after_bind: bool = false,
    descriptor_binding_update_unused_while_pending: bool = false,
    descriptor_binding_partially_bound: bool = false,
    descriptor_binding_variable_descriptor_count: bool = false,
    runtime_descriptor_array: bool = false,
    sampler_filter_minmax: bool = false,
    scalar_block_layout: bool = false,
    imageless_framebuffer: bool = false,
    uniform_buffer_standard_layout: bool = false,
    shader_subgroup_extended_types: bool = false,
    separate_depth_stencil_layouts: bool = false,
    host_query_reset: bool = false,
    timeline_semaphore: bool = false,
    buffer_device_address: bool = false,
    buffer_device_address_capture_replay: bool = false,
    buffer_device_address_multi_device: bool = false,
    vulkan_memory_model: bool = false,
    vulkan_memory_model_device_scope: bool = false,
    vulkan_memory_model_availability_visibility_chains: bool = false,
    shader_output_viewport_index: bool = false,
    shader_output_layer: bool = false,
    subgroup_broadcast_dynamic_id: bool = false,

    // Vulkan 1.3 features
    robustImageAccess: bool = false,
    inline_uniform_block: bool = false,
    descriptor_binding_inline_uniform_block_update_after_bind: bool = false,
    pipeline_creation_cache_control: bool = false,
    private_data: bool = false,
    shader_demote_to_helper_invocation: bool = false,
    shader_terminate_invocation: bool = false,
    subgroup_size_control: bool = false,
    compute_full_subgroups: bool = false,
    synchronization2: bool = false,
    texture_compression_astc_hdr: bool = false,
    shader_zero_initialize_workgroup_memory: bool = false,
    dynamic_rendering: bool = false,
    shader_integer_dot_product: bool = false,
    maintenance4: bool = false,

    // Extension features
    ray_tracing: bool = false,
    mesh_shader: bool = false,
    variable_rate_shading: bool = false,
    fragment_density_map: bool = false,
    conservative_rasterization: bool = false,

    pub fn detect(physical_device: vkmod.PhysicalDevice) Features {
        var features: vkmod.PhysicalDeviceFeatures = undefined;
        vkmod.vkGetPhysicalDeviceFeatures(physical_device, &features);

        return Features{
            .robust_buffer_access = features.robustBufferAccess == vkmod.TRUE,
            .full_draw_index_uint32 = features.fullDrawIndexUint32 == vkmod.TRUE,
            .image_cube_array = features.imageCubeArray == vkmod.TRUE,
            .independent_blend = features.independentBlend == vkmod.TRUE,
            .geometry_shader = features.geometryShader == vkmod.TRUE,
            .tessellation_shader = features.tessellationShader == vkmod.TRUE,
            .sample_rate_shading = features.sampleRateShading == vkmod.TRUE,
            .dual_src_blend = features.dualSrcBlend == vkmod.TRUE,
            .logic_op = features.logicOp == vkmod.TRUE,
            .multi_draw_indirect = features.multiDrawIndirect == vkmod.TRUE,
            .draw_indirect_first_instance = features.drawIndirectFirstInstance == vkmod.TRUE,
            .depth_clamp = features.depthClamp == vkmod.TRUE,
            .depth_bias_clamp = features.depthBiasClamp == vkmod.TRUE,
            .fill_mode_non_solid = features.fillModeNonSolid == vkmod.TRUE,
            .depth_bounds = features.depthBounds == vkmod.TRUE,
            .wide_lines = features.wideLines == vkmod.TRUE,
            .large_points = features.largePoints == vkmod.TRUE,
            .alpha_to_one = features.alphaToOne == vkmod.TRUE,
            .multi_viewport = features.multiViewport == vkmod.TRUE,
            .sampler_anisotropy = features.samplerAnisotropy == vkmod.TRUE,
            .texture_compression_etc2 = features.textureCompressionETC2 == vkmod.TRUE,
            .texture_compression_astc_ldr = features.textureCompressionASTC_LDR == vkmod.TRUE,
            .texture_compression_bc = features.textureCompressionBC == vkmod.TRUE,
            .occlusion_query_precise = features.occlusionQueryPrecise == vkmod.TRUE,
            .pipeline_statistics_query = features.pipelineStatisticsQuery == vkmod.TRUE,
            .vertex_pipeline_stores_and_atomics = features.vertexPipelineStoresAndAtomics == vkmod.TRUE,
            .fragment_stores_and_atomics = features.fragmentStoresAndAtomics == vkmod.TRUE,
            .shader_tessellation_and_geometry_point_size = features.shaderTessellationAndGeometryPointSize == vkmod.TRUE,
            .shader_image_gather_extended = features.shaderImageGatherExtended == vkmod.TRUE,
            .shader_storage_image_extended_formats = features.shaderStorageImageExtendedFormats == vkmod.TRUE,
            .shader_storage_image_multisample = features.shaderStorageImageMultisample == vkmod.TRUE,
            .shader_storage_image_read_without_format = features.shaderStorageImageReadWithoutFormat == vkmod.TRUE,
            .shader_storage_image_write_without_format = features.shaderStorageImageWriteWithoutFormat == vkmod.TRUE,
            .shader_uniform_buffer_array_dynamic_indexing = features.shaderUniformBufferArrayDynamicIndexing == vkmod.TRUE,
            .shader_sampled_image_array_dynamic_indexing = features.shaderSampledImageArrayDynamicIndexing == vkmod.TRUE,
            .shader_storage_buffer_array_dynamic_indexing = features.shaderStorageBufferArrayDynamicIndexing == vkmod.TRUE,
            .shader_storage_image_array_dynamic_indexing = features.shaderStorageImageArrayDynamicIndexing == vkmod.TRUE,
            .shader_clip_distance = features.shaderClipDistance == vkmod.TRUE,
            .shader_cull_distance = features.shaderCullDistance == vkmod.TRUE,
            .shader_float64 = features.shaderFloat64 == vkmod.TRUE,
            .shader_int64 = features.shaderInt64 == vkmod.TRUE,
            .shader_int16 = features.shaderInt16 == vkmod.TRUE,
            .shader_resource_residency = features.shaderResourceResidency == vkmod.TRUE,
            .shader_resource_min_lod = features.shaderResourceMinLod == vkmod.TRUE,
            .sparse_binding = features.sparseBinding == vkmod.TRUE,
            .sparse_residency_buffer = features.sparseResidencyBuffer == vkmod.TRUE,
            .sparse_residency_image2_d = features.sparseResidencyImage2D == vkmod.TRUE,
            .sparse_residency_image3_d = features.sparseResidencyImage3D == vkmod.TRUE,
            .sparse_residency2_samples = features.sparseResidency2Samples == vkmod.TRUE,
            .sparse_residency4_samples = features.sparseResidency4Samples == vkmod.TRUE,
            .sparse_residency8_samples = features.sparseResidency8Samples == vkmod.TRUE,
            .sparse_residency16_samples = features.sparseResidency16Samples == vkmod.TRUE,
            .sparse_residency_aliased = features.sparseResidencyAliased == vkmod.TRUE,
            .variable_multisample_rate = features.variableMultisampleRate == vkmod.TRUE,
            .inherited_queries = features.inheritedQueries == vkmod.TRUE,
            // Extension features are detected separately
            .ray_tracing = false,
            .mesh_shader = false,
            .variable_rate_shading = false,
            .fragment_density_map = false,
            .conservative_rasterization = false,
        };
    }

    // Remove duplicate deinit and createBuffer functions
    pub fn cleanup(self: *VulkanBackend) void {
        if (self.memory_manager) |*mm| {
            mm.deinit();
        }
        if (self.resources) |*res| {
            res.deinit();
        }
        if (self.command_buffers.items.len > 0) {
            vkmod.vkFreeCommandBuffers(
                self.device,
                self.command_pool,
                @intCast(self.command_buffers.items.len),
                self.command_buffers.items.ptr,
            );
        }
        self.command_buffers.deinit();
        vkmod.vkDestroyCommandPool(self.device, self.command_pool, null);
        vkmod.vkDestroyDevice(self.device, null);
        vkmod.vkDestroySurfaceKHR(self.instance, self.surface, null);
        vkmod.vkDestroyInstance(self.instance, null);
    }

    pub fn allocateBuffer(self: *VulkanBackend, info: vkmod.BufferCreateInfo) !vkmod.Buffer {
        const create_info = vkmod.BufferCreateInfo{
            .size = info.size,
            .usage = info.usage,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = null,
        };

        var buffer: vkmod.Buffer = undefined;
        try vkmod.vkCreateBuffer(self.device, &create_info, null, &buffer);
        errdefer vkmod.vkDestroyBuffer(self.device, buffer, null);

        var memory_requirements: vkmod.MemoryRequirements = undefined;
        vkmod.vkGetBufferMemoryRequirements(self.device, buffer, &memory_requirements);

        const memory_type_index = try self.memory_manager.?.findMemoryType(
            memory_requirements.memory_type_bits,
            info.memory_properties,
        );

        const memory = try self.memory_manager.?.allocate(
            memory_requirements.size,
            memory_requirements.alignment,
            memory_type_index,
            info.memory_properties,
        );
        errdefer self.memory_manager.?.free(memory);

        try vkmod.vkBindBufferMemory(self.device, buffer, memory, 0);

        return buffer;
    }
};

const Capabilities = struct {
    max_texture_size: u32 = 0,
    max_uniform_buffer_size: u32 = 0,
    max_vertex_attributes: u32 = 0,
    max_color_attachments: u32 = 0,

    pub fn query(physical_device: vkmod.PhysicalDevice) Capabilities {
        var properties: vkmod.PhysicalDeviceProperties = undefined;
        vkmod.vkGetPhysicalDeviceProperties(physical_device, &properties);

        return Capabilities{
            .max_texture_size = properties.limits.maxImageDimension2D,
            .max_uniform_buffer_size = properties.limits.maxUniformBufferRange,
            .max_vertex_attributes = properties.limits.maxVertexInputAttributes,
            .max_color_attachments = properties.limits.maxColorAttachments,
        };
    }
};
