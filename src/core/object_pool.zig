//! MFS Engine - Object Pool
//! High-performance object pooling system for memory management
//! @thread-safe Object pools are thread-safe with proper synchronization
//! @symbol ObjectPool

const std = @import("std");

/// Thread-safe object pool for efficient memory management
pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        const PoolNode = struct {
            data: T,
            next: ?*PoolNode,
            in_use: bool = false,
        };

        allocator: std.mem.Allocator,
        free_list: ?*PoolNode,
        all_nodes: std.array_list.Managed(*PoolNode),
        mutex: std.Thread.Mutex,
        capacity: usize,
        current_free: std.atomic.Value(usize),
        total_allocated: std.atomic.Value(usize),
        peak_usage: std.atomic.Value(usize),

        /// Initialize object pool with initial capacity
        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !Self {
            var pool = Self{
                .allocator = allocator,
                .free_list = null,
                .all_nodes = std.array_list.Managed(*PoolNode).init(allocator),
                .mutex = std.Thread.Mutex{},
                .capacity = initial_capacity,
                .current_free = std.atomic.Value(usize).init(0),
                .total_allocated = std.atomic.Value(usize).init(0),
                .peak_usage = std.atomic.Value(usize).init(0),
            };

            try pool.all_nodes.ensureTotalCapacity(initial_capacity);
            try pool.expandPool(initial_capacity);
            return pool;
        }

        /// Clean up object pool
        pub fn deinit(self: *Self) void {
            for (self.all_nodes.items) |node| {
                self.allocator.destroy(node);
            }
            self.all_nodes.deinit();
        }

        /// Acquire an object from the pool
        pub fn acquire(self: *Self) !*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.free_list) |node| {
                self.free_list = node.next;
                node.in_use = true;
                node.next = null;

                _ = self.current_free.fetchSub(1, .monotonic);

                const current_usage = self.total_allocated.load(.monotonic) - self.current_free.load(.monotonic);
                const peak = self.peak_usage.load(.monotonic);
                if (current_usage > peak) {
                    _ = self.peak_usage.compareAndSwap(peak, current_usage, .monotonic, .monotonic);
                }

                return &node.data;
            } else {
                // Expand pool if needed
                const expand_size = @max(self.capacity / 4, 1);
                try self.expandPool(expand_size);
                return self.acquire();
            }
        }

        /// Release an object back to the pool
        pub fn release(self: *Self, item: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const node: *PoolNode = @fieldParentPtr("data", item);
            if (!node.in_use) {
                // Double release protection
                return;
            }

            node.in_use = false;
            node.next = self.free_list;
            self.free_list = node;
            _ = self.current_free.fetchAdd(1, .monotonic);
        }

        /// Expand the pool by adding more nodes
        fn expandPool(self: *Self, count: usize) !void {
            for (0..count) |_| {
                const node = try self.allocator.create(PoolNode);
                node.* = PoolNode{
                    .data = undefined,
                    .next = self.free_list,
                    .in_use = false,
                };
                self.free_list = node;
                try self.all_nodes.append(node);
            }
            _ = self.current_free.fetchAdd(count, .monotonic);
            _ = self.total_allocated.fetchAdd(count, .monotonic);
        }

        /// Get number of free objects
        pub fn getFreeCount(self: *const Self) usize {
            return self.current_free.load(.monotonic);
        }

        /// Get total number of allocated objects
        pub fn getTotalCount(self: *const Self) usize {
            return self.total_allocated.load(.monotonic);
        }

        /// Get number of objects currently in use
        pub fn getUsedCount(self: *const Self) usize {
            return self.total_allocated.load(.monotonic) - self.current_free.load(.monotonic);
        }

        /// Get peak usage count
        pub fn getPeakUsage(self: *const Self) usize {
            return self.peak_usage.load(.monotonic);
        }

        /// Get pool utilization as a percentage (0.0 to 1.0)
        pub fn getUtilization(self: *const Self) f32 {
            const total = self.getTotalCount();
            if (total == 0) return 0.0;
            return @as(f32, @floatFromInt(self.getUsedCount())) / @as(f32, @floatFromInt(total));
        }

        /// Reset peak usage statistics
        pub fn resetStats(self: *Self) void {
            _ = self.peak_usage.store(0, .monotonic);
        }

        /// Pre-allocate objects to avoid allocation during runtime
        pub fn preallocate(self: *Self, count: usize) !void {
            const current_total = self.getTotalCount();
            if (count > current_total) {
                try self.expandPool(count - current_total);
            }
        }
    };
}

/// Specialized object pool for common types
pub const StringPool = ObjectPool([]u8);
pub const BufferPool = ObjectPool(std.ArrayList(u8));

test "object pool" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with u32 pool
    var pool = try ObjectPool(u32).init(allocator, 5);
    defer pool.deinit();

    // Test initial state
    try testing.expect(pool.getFreeCount() == 5);
    try testing.expect(pool.getUsedCount() == 0);

    // Test acquiring objects
    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    obj1.* = 42;
    obj2.* = 24;

    try testing.expect(pool.getFreeCount() == 3);
    try testing.expect(pool.getUsedCount() == 2);
    try testing.expect(obj1.* == 42);
    try testing.expect(obj2.* == 24);

    // Test releasing objects
    pool.release(obj1);
    try testing.expect(pool.getFreeCount() == 4);
    try testing.expect(pool.getUsedCount() == 1);

    pool.release(obj2);
    try testing.expect(pool.getFreeCount() == 5);
    try testing.expect(pool.getUsedCount() == 0);

    // Test utilization
    const obj3 = try pool.acquire();
    defer pool.release(obj3);
    const utilization = pool.getUtilization();
    try testing.expect(utilization > 0.0 and utilization <= 1.0);
}
