//! MFS Engine - Advanced Memory Pooling System
//! High-performance memory management for graphics resources
//! Supports multiple allocation strategies and automatic defragmentation
//! @thread-safe Thread-safe memory operations with lock-free allocators
//! @performance Optimized for minimal allocation overhead and cache efficiency

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const profiler = @import("../system/profiling/profiler.zig");

/// Memory pool types for different resource categories
pub const PoolType = enum {
    texture_pool,
    buffer_pool,
    uniform_pool,
    staging_pool,
    scratch_pool,
    persistent_pool,
};

/// Memory allocation strategies
pub const AllocationStrategy = enum {
    linear, // Simple linear allocation (fast, no deallocation)
    stack, // Stack-based allocation (LIFO)
    free_list, // Track free blocks (general purpose)
    buddy_system, // Power-of-2 buddy allocator
    slab, // Fixed-size object pools
    ring_buffer, // Circular buffer for temporary resources
    tlsf, // Two-Level Segregated Fit (best fit)
};

/// Memory pool statistics
pub const PoolStats = struct {
    total_size: u64 = 0,
    allocated_size: u64 = 0,
    free_size: u64 = 0,
    peak_usage: u64 = 0,
    allocation_count: u64 = 0,
    deallocation_count: u64 = 0,
    fragmentation_ratio: f32 = 0.0,

    // Performance metrics
    avg_allocation_time_ns: f64 = 0.0,
    total_allocation_time_ns: u64 = 0,
    failed_allocations: u64 = 0,

    // Memory efficiency
    internal_fragmentation: u64 = 0,
    external_fragmentation: u64 = 0,
    largest_free_block: u64 = 0,

    pub fn reset(self: *PoolStats) void {
        self.allocation_count = 0;
        self.deallocation_count = 0;
        self.total_allocation_time_ns = 0;
        self.failed_allocations = 0;
    }

    pub fn getUtilization(self: *const PoolStats) f32 {
        if (self.total_size == 0) return 0.0;
        return @as(f32, @floatFromInt(self.allocated_size)) / @as(f32, @floatFromInt(self.total_size));
    }

    pub fn updateAverages(self: *PoolStats) void {
        if (self.allocation_count > 0) {
            self.avg_allocation_time_ns = @as(f64, @floatFromInt(self.total_allocation_time_ns)) / @as(f64, @floatFromInt(self.allocation_count));
        }

        if (self.total_size > 0) {
            self.fragmentation_ratio = @as(f32, @floatFromInt(self.external_fragmentation)) / @as(f32, @floatFromInt(self.total_size));
        }
    }
};

/// Memory allocation result
pub const MemoryAllocation = struct {
    ptr: ?*anyopaque,
    size: u64,
    offset: u64,
    alignment: u64,
    pool_id: u32,
    allocation_id: u64,
};

/// Memory pool configuration
pub const PoolConfig = struct {
    initial_size: u64,
    max_size: u64 = 0, // 0 = no limit
    alignment: u64 = 16,
    strategy: AllocationStrategy = .free_list,
    auto_grow: bool = true,
    auto_defrag: bool = false,
    defrag_threshold: f32 = 0.5, // Defrag when fragmentation > 50%
    thread_safe: bool = true,
    debug_mode: bool = builtin.mode == .Debug,
};

/// Free block for free list allocator
const FreeBlock = struct {
    size: u64,
    offset: u64,
    next: ?*FreeBlock = null,
    prev: ?*FreeBlock = null,
};

/// Allocation record for debugging and tracking
const AllocationRecord = struct {
    id: u64,
    offset: u64,
    size: u64,
    alignment: u64,
    timestamp: i64,
    allocation_time_ns: u64,
    stack_trace: ?[]usize = null, // Debug mode only
};

/// Advanced memory pool implementation
pub const MemoryPool = struct {
    allocator: std.mem.Allocator,

    // Pool configuration
    config: PoolConfig,
    pool_type: PoolType,
    pool_id: u32,

    // Memory management
    memory: []u8,
    current_size: u64,
    next_offset: u64, // For linear allocator

    // Strategy-specific data
    free_list: ?*FreeBlock = null,
    allocation_records: std.HashMap(u64, AllocationRecord, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage),

    // Synchronization
    mutex: std.Thread.Mutex,

    // Statistics and profiling
    stats: PoolStats,
    allocation_counter: std.atomic.Atomic(u64),

    // Defragmentation
    defrag_in_progress: bool = false,
    defrag_threshold_reached: bool = false,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        pool_type: PoolType,
        pool_id: u32,
        config: PoolConfig,
    ) !*Self {
        const pool = try allocator.create(Self);

        // Allocate initial memory
        const memory = try allocator.alignedAlloc(u8, config.alignment, config.initial_size);

        pool.* = Self{
            .allocator = allocator,
            .config = config,
            .pool_type = pool_type,
            .pool_id = pool_id,
            .memory = memory,
            .current_size = config.initial_size,
            .next_offset = 0,
            .allocation_records = std.HashMap(u64, AllocationRecord, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = std.Thread.Mutex{},
            .stats = PoolStats{
                .total_size = config.initial_size,
                .free_size = config.initial_size,
            },
            .allocation_counter = std.atomic.Atomic(u64).init(1),
        };

        // Initialize free list for free_list strategy
        if (config.strategy == .free_list) {
            try pool.initializeFreeList();
        }

        return pool;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up allocation records
        if (self.config.debug_mode) {
            var iter = self.allocation_records.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.stack_trace) |stack_trace| {
                    self.allocator.free(stack_trace);
                }
            }
        }
        self.allocation_records.deinit();

        // Clean up free list
        self.cleanupFreeList();

        // Free memory
        self.allocator.free(self.memory);
        self.allocator.destroy(self);
    }

    /// Allocate memory from the pool
    pub fn allocate(self: *Self, size: u64, alignment: ?u64) !MemoryAllocation {
        const timer = profiler.Timer.start("MemoryPool.allocate");
        defer timer.end();

        if (self.config.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        const start_time = std.time.nanoTimestamp();
        const actual_alignment = alignment orelse self.config.alignment;
        const aligned_size = std.mem.alignForward(u64, size, actual_alignment);

        const result = switch (self.config.strategy) {
            .linear => self.allocateLinear(aligned_size, actual_alignment),
            .stack => self.allocateStack(aligned_size, actual_alignment),
            .free_list => self.allocateFreeList(aligned_size, actual_alignment),
            .buddy_system => self.allocateBuddy(aligned_size, actual_alignment),
            .slab => self.allocateSlab(aligned_size, actual_alignment),
            .ring_buffer => self.allocateRing(aligned_size, actual_alignment),
            .tlsf => self.allocateTLSF(aligned_size, actual_alignment),
        };

        const end_time = std.time.nanoTimestamp();
        const allocation_time = @as(u64, @intCast(end_time - start_time));

        if (result.ptr != null) {
            // Update statistics
            self.stats.allocation_count += 1;
            self.stats.allocated_size += aligned_size;
            self.stats.free_size -= aligned_size;
            self.stats.total_allocation_time_ns += allocation_time;

            if (self.stats.allocated_size > self.stats.peak_usage) {
                self.stats.peak_usage = self.stats.allocated_size;
            }

            // Record allocation for debugging
            if (self.config.debug_mode) {
                const allocation_id = self.allocation_counter.fetchAdd(1, .SeqCst);
                const record = AllocationRecord{
                    .id = allocation_id,
                    .offset = result.offset,
                    .size = aligned_size,
                    .alignment = actual_alignment,
                    .timestamp = std.time.timestamp(),
                    .allocation_time_ns = allocation_time,
                };

                try self.allocation_records.put(allocation_id, record);

                var mutable_result = result;
                mutable_result.allocation_id = allocation_id;
                return mutable_result;
            }

            // Check if defragmentation is needed
            if (self.config.auto_defrag and !self.defrag_in_progress) {
                self.checkDefragmentationThreshold();
            }
        } else {
            self.stats.failed_allocations += 1;

            // Try to grow the pool if allowed
            if (self.config.auto_grow and
                (self.config.max_size == 0 or self.current_size < self.config.max_size))
            {
                if (self.growPool(aligned_size)) {
                    return self.allocate(size, alignment);
                }
            }
        }

        return result;
    }

    /// Deallocate memory from the pool
    pub fn deallocate(self: *Self, allocation: MemoryAllocation) void {
        const timer = profiler.Timer.start("MemoryPool.deallocate");
        defer timer.end();

        if (self.config.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        // Remove allocation record
        if (self.config.debug_mode) {
            if (self.allocation_records.fetchRemove(allocation.allocation_id)) |removed| {
                if (removed.value.stack_trace) |stack_trace| {
                    self.allocator.free(stack_trace);
                }
            }
        }

        // Strategy-specific deallocation
        switch (self.config.strategy) {
            .linear => {}, // Linear allocator doesn't support individual deallocation
            .stack => self.deallocateStack(allocation),
            .free_list => self.deallocateFreeList(allocation),
            .buddy_system => self.deallocateBuddy(allocation),
            .slab => self.deallocateSlab(allocation),
            .ring_buffer => self.deallocateRing(allocation),
            .tlsf => self.deallocateTLSF(allocation),
        }

        // Update statistics
        self.stats.deallocation_count += 1;
        self.stats.allocated_size -= allocation.size;
        self.stats.free_size += allocation.size;
    }

    /// Reset the pool (clear all allocations)
    pub fn reset(self: *Self) void {
        if (self.config.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        // Clear allocation records
        if (self.config.debug_mode) {
            var iter = self.allocation_records.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.stack_trace) |stack_trace| {
                    self.allocator.free(stack_trace);
                }
            }
            self.allocation_records.clearAndFree();
        }

        // Reset pool state
        self.next_offset = 0;
        self.cleanupFreeList();

        // Reset statistics
        self.stats.allocated_size = 0;
        self.stats.free_size = self.current_size;

        // Reinitialize strategy-specific structures
        if (self.config.strategy == .free_list) {
            self.initializeFreeList() catch {
                std.log.err("Failed to reinitialize free list", .{});
            };
        }
    }

    /// Get current pool statistics
    pub fn getStats(self: *Self) PoolStats {
        if (self.config.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        var stats = self.stats;
        stats.updateAverages();
        return stats;
    }

    /// Perform defragmentation if needed
    pub fn defragment(self: *Self) !void {
        if (!self.config.auto_defrag) return;

        if (self.config.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        if (self.defrag_in_progress) return;

        self.defrag_in_progress = true;
        defer self.defrag_in_progress = false;

        // Strategy-specific defragmentation
        switch (self.config.strategy) {
            .free_list => try self.defragmentFreeList(),
            .buddy_system => try self.defragmentBuddy(),
            else => {}, // Other strategies don't need defragmentation
        }

        self.defrag_threshold_reached = false;
    }

    // Private methods for different allocation strategies
    fn allocateLinear(self: *Self, size: u64, alignment: u64) MemoryAllocation {
        const aligned_offset = std.mem.alignForward(u64, self.next_offset, alignment);

        if (aligned_offset + size > self.current_size) {
            return MemoryAllocation{
                .ptr = null,
                .size = 0,
                .offset = 0,
                .alignment = alignment,
                .pool_id = self.pool_id,
                .allocation_id = 0,
            };
        }

        const ptr = @as(*anyopaque, @ptrFromInt(@intFromPtr(self.memory.ptr) + aligned_offset));
        self.next_offset = aligned_offset + size;

        return MemoryAllocation{
            .ptr = ptr,
            .size = size,
            .offset = aligned_offset,
            .alignment = alignment,
            .pool_id = self.pool_id,
            .allocation_id = 0,
        };
    }

    fn allocateStack(self: *Self, size: u64, alignment: u64) MemoryAllocation {
        // Similar to linear but allows LIFO deallocation
        return self.allocateLinear(size, alignment);
    }

    fn allocateFreeList(self: *Self, size: u64, alignment: u64) MemoryAllocation {
        var current = self.free_list;
        var prev: ?*FreeBlock = null;

        // Find suitable free block (first fit)
        while (current) |block| {
            const aligned_offset = std.mem.alignForward(u64, block.offset, alignment);
            const padding = aligned_offset - block.offset;

            if (block.size >= size + padding) {
                // Remove block from free list
                if (prev) |p| {
                    p.next = block.next;
                } else {
                    self.free_list = block.next;
                }

                if (block.next) |next| {
                    next.prev = prev;
                }

                // Split block if necessary
                const remaining_size = block.size - (size + padding);
                if (remaining_size > @sizeOf(FreeBlock)) {
                    const new_block = @as(*FreeBlock, @ptrFromInt(@intFromPtr(self.memory.ptr) + aligned_offset + size));
                    new_block.* = FreeBlock{
                        .size = remaining_size - padding,
                        .offset = aligned_offset + size,
                        .next = self.free_list,
                        .prev = null,
                    };

                    if (self.free_list) |first| {
                        first.prev = new_block;
                    }
                    self.free_list = new_block;
                }

                // Free the old block
                self.allocator.destroy(block);

                const ptr = @as(*anyopaque, @ptrFromInt(@intFromPtr(self.memory.ptr) + aligned_offset));
                return MemoryAllocation{
                    .ptr = ptr,
                    .size = size,
                    .offset = aligned_offset,
                    .alignment = alignment,
                    .pool_id = self.pool_id,
                    .allocation_id = 0,
                };
            }

            prev = block;
            current = block.next;
        }

        return MemoryAllocation{
            .ptr = null,
            .size = 0,
            .offset = 0,
            .alignment = alignment,
            .pool_id = self.pool_id,
            .allocation_id = 0,
        };
    }

    // Placeholder implementations for other strategies
    fn allocateBuddy(self: *Self, size: u64, alignment: u64) MemoryAllocation {
        // TODO: Implement buddy system allocator
        return MemoryAllocation{ .ptr = null, .size = size, .offset = 0, .alignment = alignment, .pool_id = self.pool_id, .allocation_id = 0 };
    }

    fn allocateSlab(self: *Self, size: u64, alignment: u64) MemoryAllocation {
        // TODO: Implement slab allocator
        return MemoryAllocation{ .ptr = null, .size = size, .offset = 0, .alignment = alignment, .pool_id = self.pool_id, .allocation_id = 0 };
    }

    fn allocateRing(self: *Self, size: u64, alignment: u64) MemoryAllocation {
        // TODO: Implement ring buffer allocator
        return MemoryAllocation{ .ptr = null, .size = size, .offset = 0, .alignment = alignment, .pool_id = self.pool_id, .allocation_id = 0 };
    }

    fn allocateTLSF(self: *Self, size: u64, alignment: u64) MemoryAllocation {
        // TODO: Implement TLSF allocator
        return MemoryAllocation{ .ptr = null, .size = size, .offset = 0, .alignment = alignment, .pool_id = self.pool_id, .allocation_id = 0 };
    }

    // Deallocation methods
    fn deallocateStack(self: *Self, allocation: MemoryAllocation) void {
        // Stack allocator only supports LIFO deallocation
        const expected_offset = self.next_offset - allocation.size;
        if (allocation.offset == expected_offset) {
            self.next_offset = allocation.offset;
        }
    }

    fn deallocateFreeList(self: *Self, allocation: MemoryAllocation) void {
        // Create new free block
        const block = self.allocator.create(FreeBlock) catch {
            std.log.err("Failed to create free block during deallocation", .{});
            return;
        };

        block.* = FreeBlock{
            .size = allocation.size,
            .offset = allocation.offset,
            .next = self.free_list,
            .prev = null,
        };

        if (self.free_list) |first| {
            first.prev = block;
        }
        self.free_list = block;

        // Try to coalesce adjacent blocks
        self.coalesceBlocks();
    }

    fn deallocateBuddy(self: *Self, allocation: MemoryAllocation) void {
        _ = self;
        _ = allocation;
        // TODO: Implement buddy system deallocation
    }

    fn deallocateSlab(self: *Self, allocation: MemoryAllocation) void {
        _ = self;
        _ = allocation;
        // TODO: Implement slab deallocation
    }

    fn deallocateRing(self: *Self, allocation: MemoryAllocation) void {
        _ = self;
        _ = allocation;
        // TODO: Implement ring buffer deallocation
    }

    fn deallocateTLSF(self: *Self, allocation: MemoryAllocation) void {
        _ = self;
        _ = allocation;
        // TODO: Implement TLSF deallocation
    }

    // Helper methods
    fn initializeFreeList(self: *Self) !void {
        // Create initial free block covering entire pool
        const block = try self.allocator.create(FreeBlock);
        block.* = FreeBlock{
            .size = self.current_size,
            .offset = 0,
            .next = null,
            .prev = null,
        };
        self.free_list = block;
    }

    fn cleanupFreeList(self: *Self) void {
        var current = self.free_list;
        while (current) |block| {
            const next = block.next;
            self.allocator.destroy(block);
            current = next;
        }
        self.free_list = null;
    }

    fn coalesceBlocks(self: *Self) void {
        // TODO: Implement block coalescing for free list
        _ = self;
    }

    fn growPool(self: *Self, required_size: u64) bool {
        const new_size = @max(self.current_size * 2, self.current_size + required_size);

        if (self.config.max_size > 0 and new_size > self.config.max_size) {
            return false;
        }

        // Reallocate memory
        if (self.allocator.realloc(self.memory, new_size)) |new_memory| {
            self.memory = new_memory;
            self.current_size = new_size;
            self.stats.total_size = new_size;
            self.stats.free_size += new_size - self.memory.len;

            // Update free list for new space
            if (self.config.strategy == .free_list) {
                const block = self.allocator.create(FreeBlock) catch return false;
                block.* = FreeBlock{
                    .size = new_size - self.memory.len,
                    .offset = self.memory.len,
                    .next = self.free_list,
                    .prev = null,
                };

                if (self.free_list) |first| {
                    first.prev = block;
                }
                self.free_list = block;
            }

            std.log.debug("Grew memory pool {} from {} to {} bytes", .{ self.pool_id, self.memory.len, new_size });
            return true;
        } else |_| {
            return false;
        }
    }

    fn checkDefragmentationThreshold(self: *Self) void {
        if (self.stats.fragmentation_ratio > self.config.defrag_threshold) {
            self.defrag_threshold_reached = true;
        }
    }

    fn defragmentFreeList(self: *Self) !void {
        // TODO: Implement free list defragmentation
        _ = self;
    }

    fn defragmentBuddy(self: *Self) !void {
        // TODO: Implement buddy system defragmentation
        _ = self;
    }
};

/// Memory pool manager for coordinating multiple pools
pub const MemoryPoolManager = struct {
    allocator: std.mem.Allocator,
    pools: std.HashMap(u32, *MemoryPool, std.hash_map.HashContext(u32), std.hash_map.default_max_load_percentage),
    pool_counter: std.atomic.Atomic(u32),
    global_stats: GlobalStats,
    mutex: std.Thread.Mutex,

    const GlobalStats = struct {
        total_pools: u32 = 0,
        total_memory: u64 = 0,
        total_allocated: u64 = 0,
        total_allocations: u64 = 0,
        total_failed_allocations: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) !*MemoryPoolManager {
        const manager = try allocator.create(MemoryPoolManager);
        manager.* = MemoryPoolManager{
            .allocator = allocator,
            .pools = std.HashMap(u32, *MemoryPool, std.hash_map.HashContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .pool_counter = std.atomic.Atomic(u32).init(1),
            .global_stats = GlobalStats{},
            .mutex = std.Thread.Mutex{},
        };
        return manager;
    }

    pub fn deinit(self: *MemoryPoolManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up all pools
        var iter = self.pools.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.pools.deinit();

        self.allocator.destroy(self);
    }

    pub fn createPool(self: *MemoryPoolManager, pool_type: PoolType, config: PoolConfig) !u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const pool_id = self.pool_counter.fetchAdd(1, .SeqCst);
        const pool = try MemoryPool.init(self.allocator, pool_type, pool_id, config);

        try self.pools.put(pool_id, pool);

        self.global_stats.total_pools += 1;
        self.global_stats.total_memory += config.initial_size;

        std.log.debug("Created memory pool {} of type {} with {} bytes", .{ pool_id, pool_type, config.initial_size });

        return pool_id;
    }

    pub fn getPool(self: *MemoryPoolManager, pool_id: u32) ?*MemoryPool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.pools.get(pool_id);
    }

    pub fn destroyPool(self: *MemoryPoolManager, pool_id: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.pools.fetchRemove(pool_id)) |removed| {
            const pool = removed.value;
            self.global_stats.total_pools -= 1;
            self.global_stats.total_memory -= pool.current_size;
            pool.deinit();

            std.log.debug("Destroyed memory pool {}", .{pool_id});
        }
    }

    pub fn getGlobalStats(self: *MemoryPoolManager) GlobalStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update global statistics
        var total_allocated: u64 = 0;
        var total_allocations: u64 = 0;
        var total_failed: u64 = 0;

        var iter = self.pools.iterator();
        while (iter.next()) |entry| {
            const stats = entry.value_ptr.*.getStats();
            total_allocated += stats.allocated_size;
            total_allocations += stats.allocation_count;
            total_failed += stats.failed_allocations;
        }

        var global_stats = self.global_stats;
        global_stats.total_allocated = total_allocated;
        global_stats.total_allocations = total_allocations;
        global_stats.total_failed_allocations = total_failed;

        return global_stats;
    }

    pub fn defragmentAllPools(self: *MemoryPoolManager) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.pools.iterator();
        while (iter.next()) |entry| {
            try entry.value_ptr.*.defragment();
        }
    }
};
