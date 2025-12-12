//! MFS Engine Memory Manager
//! Provides efficient memory allocation and management for graphics resources
//! Features:
//! - Pool-based allocation to reduce fragmentation
//! - Smart defragmentation
//! - Memory type selection
//! - Resource tracking and debugging
//! - Thread-safe operations

const std = @import("std");
const vk = @import("vulkan");
const assert = std.debug.assert;

/// Memory allocation statistics for monitoring and debugging
pub const MemoryStats = struct {
    total_allocated: usize = 0,
    total_freed: usize = 0,
    peak_usage: usize = 0,
    current_usage: usize = 0,
    allocation_count: usize = 0,
    deallocation_count: usize = 0,
};

/// Memory block representing a single allocation
pub const MemoryBlock = struct {
    memory: vk.DeviceMemory,
    offset: vk.DeviceSize,
    size: vk.DeviceSize,
    alignment: vk.DeviceSize,
    memory_type_index: u32,
    mapped_ptr: ?*anyopaque,
    in_use: bool,

    pub fn init(
        memory: vk.DeviceMemory,
        offset: vk.DeviceSize,
        size: vk.DeviceSize,
        alignment: vk.DeviceSize,
        memory_type_index: u32,
    ) MemoryBlock {
        return .{
            .memory = memory,
            .offset = offset,
            .size = size,
            .alignment = alignment,
            .memory_type_index = memory_type_index,
            .mapped_ptr = null,
            .in_use = false,
        };
    }
};

/// Memory pool for efficient allocation
pub const MemoryPool = struct {
    device: vk.Device,
    memory: vk.DeviceMemory,
    size: vk.DeviceSize,
    memory_type_index: u32,
    blocks: std.array_list.Managed(MemoryBlock),
    mutex: std.Thread.Mutex,

    pub fn init(
        allocator: std.mem.Allocator,
        device: vk.Device,
        size: vk.DeviceSize,
        memory_type_index: u32,
    ) !MemoryPool {
        const memory = try device.allocateMemory(allocator, .{
            .allocationSize = size,
            .memoryTypeIndex = memory_type_index,
        });

        return MemoryPool{
            .device = device,
            .memory = memory,
            .size = size,
            .memory_type_index = memory_type_index,
            .blocks = std.array_list.Managed(MemoryBlock).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *MemoryPool) void {
        self.device.freeMemory(self.memory, null);
        self.blocks.deinit();
    }

    pub fn allocate(
        self: *MemoryPool,
        size: vk.DeviceSize,
        alignment: vk.DeviceSize,
    ) !MemoryBlock {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find existing free block
        for (self.blocks.items) |*block| {
            if (!block.in_use and block.size >= size and block.alignment >= alignment) {
                block.in_use = true;
                return block.*;
            }
        }

        // Create new block
        var offset: vk.DeviceSize = 0;
        if (self.blocks.items.len > 0) {
            const last_block = self.blocks.items[self.blocks.items.len - 1];
            offset = last_block.offset + last_block.size;
        }

        // Align offset
        offset = (offset + alignment - 1) & ~(alignment - 1);

        // Check if enough space
        if (offset + size > self.size) {
            return error.OutOfMemory;
        }

        // Create block
        const block = MemoryBlock.init(
            self.memory,
            offset,
            size,
            alignment,
            self.memory_type_index,
        );
        block.in_use = true;

        try self.blocks.append(block);
        return block;
    }

    pub fn free(self: *MemoryPool, block: *MemoryBlock) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        block.in_use = false;
        if (block.mapped_ptr != null) {
            self.device.unmapMemory(block.memory);
            block.mapped_ptr = null;
        }
    }

    pub fn defragment(self: *MemoryPool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Sort blocks by offset
        std.sort.sort(MemoryBlock, self.blocks.items, {}, struct {
            fn lessThan(_: void, a: MemoryBlock, b: MemoryBlock) bool {
                return a.offset < b.offset;
            }
        }.lessThan);

        // Merge adjacent free blocks
        var i: usize = 0;
        while (i < self.blocks.items.len - 1) {
            const current = &self.blocks.items[i];
            const next = &self.blocks.items[i + 1];

            if (!current.in_use and !next.in_use) {
                current.size += next.size;
                _ = self.blocks.orderedRemove(i + 1);
                continue;
            }

            i += 1;
        }
    }
};

/// Main memory manager
pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    device: vk.Device,
    physical_device: vk.PhysicalDevice,
    pools: std.array_list.Managed(MemoryPool),
    stats: MemoryStats,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        device: vk.Device,
        physical_device: vk.PhysicalDevice,
        pool_size: vk.DeviceSize,
        _: vk.DeviceSize, // min_block_size is unused
    ) !*Self {
        var self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .physical_device = physical_device,
            .pools = std.array_list.Managed(MemoryPool).init(allocator),
            .stats = MemoryStats{},
            .mutex = std.Thread.Mutex{},
        };

        // Initialize pools for each memory type
        var memory_properties: vk.PhysicalDeviceMemoryProperties = undefined;
        self.physical_device.getMemoryProperties(&memory_properties);

        for (0..memory_properties.memoryTypeCount) |i| {
            const pool = try MemoryPool.init(
                allocator,
                device,
                pool_size,
                @intCast(i),
            );
            try self.pools.append(pool);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.pools.items) |*pool| {
            pool.deinit();
        }
        self.pools.deinit();
        self.allocator.destroy(self);
    }

    pub fn allocate(
        self: *Self,
        size: vk.DeviceSize,
        alignment: vk.DeviceSize,
        memory_type_bits: u32,
        properties: vk.MemoryPropertyFlags,
    ) !MemoryBlock {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find suitable memory type
        const memory_type_index = try self.findMemoryType(memory_type_bits, properties);

        // Allocate from pool
        const block = try self.pools.items[memory_type_index].allocate(size, alignment);

        // Update stats
        self.stats.total_allocated += size;
        self.stats.allocation_count += 1;
        self.stats.current_usage += size;
        self.stats.peak_usage = @max(self.stats.peak_usage, self.stats.current_usage);

        return block;
    }

    pub fn free(self: *Self, block: *MemoryBlock) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.pools.items[block.memory_type_index].free(block);

        // Update stats
        self.stats.total_freed += block.size;
        self.stats.deallocation_count += 1;
        self.stats.current_usage -= block.size;
    }

    pub fn map(self: *Self, block: *MemoryBlock) !*anyopaque {
        if (block.mapped_ptr) |ptr| {
            return ptr;
        }

        block.mapped_ptr = try self.device.mapMemory(
            block.memory,
            block.offset,
            block.size,
            .{},
        );

        return block.mapped_ptr.?;
    }

    pub fn unmap(self: *Self, block: *MemoryBlock) void {
        if (block.mapped_ptr) |_| {
            self.device.unmapMemory(block.memory);
            block.mapped_ptr = null;
        }
    }

    pub fn defragment(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.pools.items) |*pool| {
            try pool.defragment();
        }
    }

    pub fn getStats(self: *Self) MemoryStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats;
    }

    fn findMemoryType(
        self: *Self,
        type_filter: u32,
        properties: vk.MemoryPropertyFlags,
    ) !u32 {
        var memory_properties: vk.PhysicalDeviceMemoryProperties = undefined;
        self.physical_device.getMemoryProperties(&memory_properties);

        for (0..memory_properties.memoryTypeCount) |i| {
            const type_bit = @as(u32, 1) << @intCast(i);
            if (type_filter & type_bit != 0) {
                const memory_type = memory_properties.memoryTypes[i];
                if (memory_type.propertyFlags.contains(properties)) {
                    return @intCast(i);
                }
            }
        }

        return error.NoSuitableMemoryType;
    }
};
