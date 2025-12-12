const std = @import("std");
const errors = @import("errors.zig");

/// Memory allocation strategy
pub const AllocStrategy = enum {
    /// Linear allocation, good for frame-based allocations
    linear,
    /// Pool allocation for fixed-size objects
    pool,
    /// General purpose allocation
    general,
    /// Device-local allocation
    device_local,
};

/// Memory usage flags
pub const MemoryUsage = packed struct {
    /// CPU can write to this memory
    cpu_write: bool = false,
    /// CPU can read from this memory
    cpu_read: bool = false,
    /// GPU can write to this memory
    gpu_write: bool = false,
    /// GPU can read from this memory
    gpu_read: bool = false,
    /// Memory is device local (fastest for GPU access)
    device_local: bool = false,
    /// Memory is host visible (can be mapped)
    host_visible: bool = false,
    /// Memory is coherent (no explicit flush needed)
    host_coherent: bool = false,
    /// Memory is cached on host
    host_cached: bool = false,
    _padding: u24 = 0,
};

/// Memory requirements for allocation
pub const MemoryRequirements = struct {
    size: usize,
    alignment: usize,
    memory_types: u32,
};

/// Memory allocation info
pub const AllocationInfo = struct {
    size: usize,
    alignment: usize,
    strategy: AllocStrategy,
    usage: MemoryUsage,
};

/// Memory block representing an allocation
pub const MemoryBlock = struct {
    data: [*]u8,
    size: usize,
    offset: usize,
    mapped: bool,

    pub fn map(self: *MemoryBlock) !void {
        if (self.mapped) return;
        // Implementation varies by backend
        self.mapped = true;
    }

    pub fn unmap(self: *MemoryBlock) void {
        if (!self.mapped) return;
        // Implementation varies by backend
        self.mapped = false;
    }

    pub fn flush(_: MemoryBlock, _: usize, _: usize) !void {
        // Implementation varies by backend
    }
};

/// Memory allocator interface
pub const Allocator = struct {
    allocator: std.mem.Allocator,
    strategy: AllocStrategy,
    total_size: usize,
    used_size: usize,
    blocks: std.ArrayList(MemoryBlock),

    pub fn init(allocator: std.mem.Allocator, strategy: AllocStrategy, size: usize) !Allocator {
        return Allocator{
            .allocator = allocator,
            .strategy = strategy,
            .total_size = size,
            .used_size = 0,
            .blocks = std.ArrayList(MemoryBlock).init(allocator),
        };
    }

    pub fn deinit(self: *Allocator) void {
        for (self.blocks.items) |*block| {
            if (block.mapped) {
                block.unmap();
            }
            self.allocator.free(block.data[0..block.size]);
        }
        self.blocks.deinit();
    }

    pub fn allocate(self: *Allocator, info: AllocationInfo) !*MemoryBlock {
        // Check if we have enough space
        if (self.used_size + info.size > self.total_size) {
            return errors.GraphicsError.OutOfMemory;
        }

        // Allocate memory (ignore explicit alignment for this simple allocator)
        const data_slice = try self.allocator.alloc(u8, info.size);
        const data = data_slice.ptr;

        // Create block
        const block = MemoryBlock{
            .data = data,
            .size = info.size,
            .offset = self.used_size,
            .mapped = false,
        };

        try self.blocks.append(block);
        self.used_size += info.size;

        return &self.blocks.items[self.blocks.items.len - 1];
    }

    pub fn free(self: *Allocator, block: *MemoryBlock) void {
        // Find and remove block
        for (self.blocks.items, 0..) |*b, i| {
            if (b.data == block.data) {
                if (b.mapped) {
                    b.unmap();
                }
                self.allocator.free(b.data[0..b.size]);
                _ = self.blocks.orderedRemove(i);
                if (self.used_size >= b.size) {
                    self.used_size -= b.size;
                } else {
                    self.used_size = 0;
                }
                break;
            }
        }
    }
};

/// Memory pool for fixed-size allocations
pub const MemoryPool = struct {
    allocator: std.mem.Allocator,
    block_size: usize,
    capacity: usize,
    free_list: std.ArrayList(usize),
    memory: []u8,

    pub fn init(allocator: std.mem.Allocator, block_size: usize, capacity: usize) !MemoryPool {
        var pool = MemoryPool{
            .allocator = allocator,
            .block_size = block_size,
            .capacity = capacity,
            .free_list = std.ArrayList(usize).init(allocator),
            .memory = try allocator.alloc(u8, block_size * capacity),
        };

        // Initialize free list
        try pool.free_list.ensureTotalCapacity(capacity);
        var i: usize = 0;
        while (i < capacity) : (i += 1) {
            try pool.free_list.append(i);
        }

        return pool;
    }

    pub fn deinit(self: *MemoryPool) void {
        self.free_list.deinit();
        self.allocator.free(self.memory);
    }

    pub fn allocate(self: *MemoryPool) ![]u8 {
        if (self.free_list.items.len == 0) {
            return errors.GraphicsError.OutOfMemory;
        }

        const maybe_index = self.free_list.pop();
        const index: usize = maybe_index orelse return errors.GraphicsError.OutOfMemory;
        const start = index * self.block_size;
        return self.memory[start .. start + self.block_size];
    }

    pub fn free(self: *MemoryPool, data: []u8) !void {
        const start = @intFromPtr(data.ptr) - @intFromPtr(self.memory.ptr);
        const index = start / self.block_size;

        if (start % self.block_size != 0 or index >= self.capacity) {
            return errors.GraphicsError.InvalidMemoryAccess;
        }

        try self.free_list.append(index);
    }
};
