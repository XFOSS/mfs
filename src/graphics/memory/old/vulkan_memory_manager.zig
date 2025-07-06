const std = @import("std");
const vk = @import("vk.zig");
const math = std.math;

/// Advanced memory manager for Vulkan with pooling and defragmentation support
pub const MemoryManager = struct {
    device: vk.Device,
    allocator: std.mem.Allocator,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    allocations: std.AutoHashMap(usize, AllocationInfo),
    pools: std.AutoHashMap(u32, MemoryPool), // Memory type index -> Pool
    stats: MemoryStats,

    pub const MemoryStats = struct {
        total_allocated: u64 = 0,
        total_used: u64 = 0,
        peak_allocated: u64 = 0,
        peak_used: u64 = 0,
        allocation_count: u32 = 0,
        defragmentation_count: u32 = 0,
    };

    pub const AllocationInfo = struct {
        memory: vk.DeviceMemory,
        size: u64,
        offset: u64,
        mapped: ?*anyopaque,
        flags: vk.MemoryPropertyFlags,
        pool: ?*MemoryPool = null,
        is_dedicated: bool = false,
    };

    const POOL_SIZE = 64 * 1024 * 1024; // 64MB
    const MIN_BLOCK_SIZE = 256;

    pub fn init(allocator: std.mem.Allocator, device: vk.Device, memory_properties: vk.PhysicalDeviceMemoryProperties) !MemoryManager {
        return MemoryManager{
            .device = device,
            .allocator = allocator,
            .memory_properties = memory_properties,
            .allocations = std.AutoHashMap(usize, AllocationInfo).init(allocator),
            .pools = std.AutoHashMap(u32, MemoryPool).init(allocator),
            .stats = .{},
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        var it = self.allocations.iterator();
        while (it.next()) |entry| {
            if (entry.value.mapped != null) {
                vk.vkUnmapMemory(self.device, entry.value.memory);
            }
            if (entry.value.pool == null) {
                vk.vkFreeMemory(self.device, entry.value.memory, null);
            }
        }

        var pool_iter = self.pools.valueIterator();
        while (pool_iter.next()) |pool| {
            pool.deinit(self.device);
        }

        self.allocations.deinit();
        self.pools.deinit();
    }

    pub fn findMemoryType(self: *const MemoryManager, type_filter: u32, properties: vk.MemoryPropertyFlags) !u32 {
        for (0..self.memory_properties.memory_type_count) |i| {
            const type_match = (type_filter & (@as(u32, 1) << @intCast(i))) != 0;
            const prop_match = (self.memory_properties.memory_types[i].property_flags & properties) == properties;
            if (type_match and prop_match) return @intCast(i);
        }
        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: *MemoryManager, requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !MemoryAllocation {
        const memory_type = try self.findMemoryType(requirements.memoryTypeBits, properties);
        const pool = try self.getOrCreatePool(memory_type);
        const allocation = try pool.allocate(requirements.size, requirements.alignment);

        return MemoryAllocation{
            .memory = pool.memory,
            .offset = allocation.offset,
            .size = allocation.size,
            .mapped_ptr = null,
        };
    }

    pub fn free(self: *MemoryManager, allocation: *const MemoryAllocation) void {
        if (self.findPool(allocation.memory)) |pool| {
            pool.free(allocation.offset);
        }
    }

    pub fn map(self: *MemoryManager, allocation: *MemoryAllocation) !void {
        if (allocation.mapped_ptr != null) return;

        var data: ?*anyopaque = undefined;
        try vk.mapMemory(self.device, allocation.memory, allocation.offset, allocation.size, 0, &data);
        allocation.mapped_ptr = data;
    }

    pub fn unmap(self: *MemoryManager, allocation: *MemoryAllocation) void {
        if (allocation.mapped_ptr == null) return;
        vk.unmapMemory(self.device, allocation.memory);
        allocation.mapped_ptr = null;
    }

    fn getOrCreatePool(self: *MemoryManager, memory_type: u32) !*MemoryPool {
        if (self.pools.getPtr(memory_type)) |pool| {
            return pool;
        }

        var pool = try MemoryPool.init(self.allocator, self.device, memory_type);
        try self.pools.put(memory_type, pool);
        return self.pools.getPtr(memory_type).?;
    }

    fn findPool(self: *const MemoryManager, target_memory: vk.DeviceMemory) ?*MemoryPool {
        var pool_iter = self.pools.valueIterator();
        while (pool_iter.next()) |pool| {
            if (pool.memory == target_memory) return pool;
        }
        return null;
    }

    pub fn getStats(self: *const MemoryManager) MemoryStats {
        return self.stats;
    }
};

const MemoryPool = struct {
    memory: vk.DeviceMemory,
    size: vk.DeviceSize,
    used: vk.DeviceSize,
    blocks: std.ArrayList(Block),

    const Block = struct {
        offset: vk.DeviceSize,
        size: vk.DeviceSize,
        is_free: bool,
    };

    const Allocation = struct {
        offset: vk.DeviceSize,
        size: vk.DeviceSize,
    };

    pub fn init(allocator: std.mem.Allocator, device: vk.Device, memory_type: u32) !MemoryPool {
        const alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = MemoryManager.POOL_SIZE,
            .memory_type_index = memory_type,
        };

        const memory = try vk.allocateMemory(device, &alloc_info, null);
        errdefer vk.freeMemory(device, memory, null);

        var blocks = std.ArrayList(Block).init(allocator);
        try blocks.append(.{
            .offset = 0,
            .size = MemoryManager.POOL_SIZE,
            .is_free = true,
        });

        return MemoryPool{
            .memory = memory,
            .size = MemoryManager.POOL_SIZE,
            .used = 0,
            .blocks = blocks,
        };
    }

    pub fn deinit(self: *MemoryPool, device: vk.Device) void {
        vk.freeMemory(device, self.memory, null);
        self.blocks.deinit();
    }

    pub fn allocate(self: *MemoryPool, size: vk.DeviceSize, alignment: vk.DeviceSize) !Allocation {
        const aligned_size = std.mem.alignForward(vk.DeviceSize, size, alignment);

        for (self.blocks.items, 0..) |block, i| {
            if (block.is_free) {
                const aligned_offset = std.mem.alignForward(vk.DeviceSize, block.offset, alignment);
                const padding = aligned_offset - block.offset;

                if (block.size >= aligned_size + padding) {
                    try self.splitBlock(i, aligned_offset, aligned_size);
                    self.used += aligned_size + padding;
                    return Allocation{
                        .offset = aligned_offset,
                        .size = aligned_size,
                    };
                }
            }
        }
        return error.OutOfMemory;
    }

    pub fn free(self: *MemoryPool, offset: vk.DeviceSize) void {
        for (self.blocks.items, 0..) |*block, i| {
            if (block.offset == offset) {
                block.is_free = true;
                self.used -= block.size;
                self.mergeAdjacentBlocks(i);
                break;
            }
        }
    }

    fn splitBlock(self: *MemoryPool, index: usize, aligned_offset: vk.DeviceSize, size: vk.DeviceSize) !void {
        var block = &self.blocks.items[index];
        const original_offset = block.offset;
        const original_size = block.size;

        // Handle alignment padding if needed
        if (aligned_offset > original_offset) {
            block.size = aligned_offset - original_offset;
            try self.blocks.insert(index + 1, .{
                .offset = aligned_offset,
                .size = size,
                .is_free = false,
            });

            const remaining = original_size - (block.size + size);
            if (remaining > MemoryManager.MIN_BLOCK_SIZE) {
                try self.blocks.insert(index + 2, .{
                    .offset = aligned_offset + size,
                    .size = remaining,
                    .is_free = true,
                });
            }
        } else {
            block.size = size;
            block.is_free = false;

            const remaining = original_size - size;
            if (remaining > MemoryManager.MIN_BLOCK_SIZE) {
                try self.blocks.insert(index + 1, .{
                    .offset = original_offset + size,
                    .size = remaining,
                    .is_free = true,
                });
            }
        }
    }

    fn mergeAdjacentBlocks(self: *MemoryPool, start_index: usize) void {
        var i = start_index;
        while (i + 1 < self.blocks.items.len) {
            var current = &self.blocks.items[i];
            var next = &self.blocks.items[i + 1];

            if (current.is_free and next.is_free) {
                current.size += next.size;
                _ = self.blocks.orderedRemove(i + 1);
                continue;
            }
            i += 1;
        }

        // Also try to merge with previous block
        if (start_index > 0) {
            var prev = &self.blocks.items[start_index - 1];
            var current = &self.blocks.items[start_index];

            if (prev.is_free and current.is_free) {
                prev.size += current.size;
                _ = self.blocks.orderedRemove(start_index);
            }
        }
    }
};
