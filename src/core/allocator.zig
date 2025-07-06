//! MFS Engine - Core Allocator Module
//! Memory management utilities and custom allocator implementations.
//!
//! This module provides various allocation strategies for different use cases:
//! - Tracking allocator for memory profiling
//! - Arena allocator for bulk allocations with single deallocation
//! - Fixed buffer allocator for stack-based allocation
//! - Memory pool for fixed-size object allocation
//! - Debug allocator for detecting memory issues
//! - Linear allocator for fast sequential allocations
//!
//! @thread-safe: Individual allocators document their thread-safety
//! @allocator-aware: yes - all allocators wrap a backing allocator
//! @platform: all

const std = @import("std");
const builtin = @import("builtin");
const core = @import("mod.zig");

// =============================================================================
// Memory Statistics
// =============================================================================

/// Memory allocation statistics for profiling
pub const AllocStats = struct {
    total_allocated: u64 = 0,
    total_freed: u64 = 0,
    peak_usage: u64 = 0,
    current_usage: u64 = 0,
    allocation_count: u64 = 0,
    free_count: u64 = 0,

    /// Initialize empty statistics
    pub fn init() AllocStats {
        return .{};
    }

    /// Record a new allocation
    pub fn recordAllocation(self: *AllocStats, size: usize) void {
        self.total_allocated += size;
        self.current_usage += size;
        self.allocation_count += 1;

        if (self.current_usage > self.peak_usage) {
            self.peak_usage = self.current_usage;
        }
    }

    /// Record a deallocation
    pub fn recordFree(self: *AllocStats, size: usize) void {
        self.total_freed += size;
        self.current_usage = @max(self.current_usage, size) - size;
        self.free_count += 1;
    }

    /// Calculate allocation efficiency (free_count / allocation_count)
    pub fn getEfficiency(self: *const AllocStats) f64 {
        if (self.allocation_count == 0) return 1.0;
        return @as(f64, @floatFromInt(self.free_count)) / @as(f64, @floatFromInt(self.allocation_count));
    }

    /// Check if there are memory leaks
    pub fn hasLeaks(self: *const AllocStats) bool {
        return self.current_usage > 0;
    }

    /// Format statistics as string (caller owns memory)
    pub fn format(self: *const AllocStats, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            \\AllocStats{{
            \\  total_allocated: {}
            \\  total_freed: {}
            \\  peak_usage: {}
            \\  current_usage: {}
            \\  allocation_count: {}
            \\  free_count: {}
            \\  efficiency: {d:.2}%
            \\  has_leaks: {}
            \\}}
        , .{
            self.total_allocated,
            self.total_freed,
            self.peak_usage,
            self.current_usage,
            self.allocation_count,
            self.free_count,
            self.getEfficiency() * 100.0,
            self.hasLeaks(),
        });
    }
};

// =============================================================================
// Tracking Allocator
// =============================================================================

/// Allocator wrapper that tracks memory usage statistics
///
/// **Thread Safety**: Thread-safe - uses mutex for statistics
pub const TrackingAllocator = struct {
    backing_allocator: std.mem.Allocator,
    stats: AllocStats,
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new tracking allocator
    pub fn init(backing_allocator: std.mem.Allocator) Self {
        return .{
            .backing_allocator = backing_allocator,
            .stats = AllocStats.init(),
            .mutex = .{},
        };
    }

    /// Get the allocator interface
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    /// Get a copy of current statistics
    ///
    /// **Thread Safety**: Thread-safe
    pub fn getStats(self: *Self) AllocStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats;
    }

    /// Print statistics to stderr
    pub fn printStats(self: *Self) void {
        const stats = self.getStats();
        if (stats.format(std.heap.page_allocator)) |str| {
            defer std.heap.page_allocator.free(str);
            std.debug.print("{s}\n", .{str});
        } else |_| {
            std.debug.print("Failed to format stats\n", .{});
        }
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.backing_allocator.rawAlloc(len, ptr_align, ret_addr);

        if (result) |_| {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.stats.recordAllocation(len);
        }

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const old_len = buf.len;
        const result = self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);

        if (result) {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (new_len > old_len) {
                self.stats.recordAllocation(new_len - old_len);
            } else if (new_len < old_len) {
                self.stats.recordFree(old_len - new_len);
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.backing_allocator.rawFree(buf, buf_align, ret_addr);

        self.mutex.lock();
        defer self.mutex.unlock();
        self.stats.recordFree(buf.len);
    }
};

// =============================================================================
// Debug Allocator
// =============================================================================

/// Allocator that adds debug features like leak detection and buffer overflow protection
///
/// **Thread Safety**: Thread-safe if backing allocator is thread-safe
pub const DebugAllocator = struct {
    backing_allocator: std.mem.Allocator,
    allocations: std.AutoHashMap(usize, AllocationInfo),
    mutex: std.Thread.Mutex,
    config: Config,

    const Self = @This();
    const GUARD_PATTERN: u8 = 0xDE;
    const GUARD_SIZE: usize = 16;

    const AllocationInfo = struct {
        size: usize,
        alignment: u8,
        stack_trace: ?*std.builtin.StackTrace,
    };

    pub const Config = struct {
        /// Enable guard bytes before and after allocations
        enable_guards: bool = true,
        /// Enable stack trace capture
        enable_stack_traces: bool = builtin.mode == .Debug,
        /// Fill freed memory with pattern
        enable_free_fill: bool = true,
        /// Pattern to fill freed memory
        free_fill_pattern: u8 = 0xDD,
    };

    /// Create a new debug allocator
    pub fn init(backing_allocator: std.mem.Allocator, config: Config) !Self {
        return .{
            .backing_allocator = backing_allocator,
            .allocations = std.AutoHashMap(usize, AllocationInfo).init(backing_allocator),
            .mutex = .{},
            .config = config,
        };
    }

    /// Cleanup the debug allocator
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check for leaks
        if (self.allocations.count() > 0) {
            std.debug.print("WARNING: {} memory leaks detected!\n", .{self.allocations.count()});
            var iter = self.allocations.iterator();
            while (iter.next()) |entry| {
                std.debug.print("  Leak at 0x{x}: {} bytes\n", .{ entry.key_ptr.*, entry.value_ptr.size });
            }
        }

        self.allocations.deinit();
    }

    /// Get the allocator interface
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    /// Check if all allocations have been freed
    pub fn checkLeaks(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.allocations.count() == 0;
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        // Calculate actual size with guards
        const actual_size = if (self.config.enable_guards)
            len + (GUARD_SIZE * 2)
        else
            len;

        const ptr = self.backing_allocator.rawAlloc(actual_size, ptr_align, ret_addr) orelse return null;

        if (self.config.enable_guards) {
            // Fill guards
            @memset(ptr[0..GUARD_SIZE], GUARD_PATTERN);
            @memset(ptr[GUARD_SIZE + len ..][0..GUARD_SIZE], GUARD_PATTERN);
        }

        // Record allocation
        self.mutex.lock();
        defer self.mutex.unlock();

        const user_ptr = if (self.config.enable_guards) ptr + GUARD_SIZE else ptr;
        self.allocations.put(@intFromPtr(user_ptr), .{
            .size = len,
            .alignment = ptr_align,
            .stack_trace = null, // TODO: Capture stack trace
        }) catch |err| {
            std.debug.print("Failed to record allocation: {}\n", .{err});
            self.backing_allocator.rawFree(ptr[0..actual_size], ptr_align, ret_addr);
            return null;
        };

        return user_ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        // Debug allocator doesn't support resize for simplicity
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.mutex.lock();
        defer self.mutex.unlock();

        const ptr_addr = @intFromPtr(buf.ptr);
        const info = self.allocations.fetchRemove(ptr_addr) orelse {
            std.debug.panic("Double free or invalid free detected at 0x{x}\n", .{ptr_addr});
        };

        // Check guards
        if (self.config.enable_guards) {
            const actual_ptr = buf.ptr - GUARD_SIZE;
            const guard_before = actual_ptr[0..GUARD_SIZE];
            const guard_after = actual_ptr[GUARD_SIZE + info.value.size ..][0..GUARD_SIZE];

            for (guard_before, 0..) |byte, i| {
                if (byte != GUARD_PATTERN) {
                    std.debug.panic("Buffer underflow detected at offset -{}\n", .{GUARD_SIZE - i});
                }
            }

            for (guard_after, 0..) |byte, i| {
                if (byte != GUARD_PATTERN) {
                    std.debug.panic("Buffer overflow detected at offset +{}\n", .{info.value.size + i});
                }
            }

            // Fill freed memory
            if (self.config.enable_free_fill) {
                @memset(buf, self.config.free_fill_pattern);
            }

            // Free actual allocation
            const actual_size = info.value.size + (GUARD_SIZE * 2);
            self.backing_allocator.rawFree(actual_ptr[0..actual_size], buf_align, ret_addr);
        } else {
            if (self.config.enable_free_fill) {
                @memset(buf, self.config.free_fill_pattern);
            }
            self.backing_allocator.rawFree(buf, buf_align, ret_addr);
        }
    }
};

// =============================================================================
// Pool Allocator
// =============================================================================

/// Memory pool for fixed-size allocations
///
/// **Thread Safety**: NOT thread-safe - wrap with mutex if needed
pub fn PoolAllocator(comptime T: type, comptime pool_size: usize) type {
    return struct {
        memory: [pool_size * @sizeOf(T)]u8 align(@alignOf(T)),
        free_list: ?*Node,
        allocated_count: usize,

        const Self = @This();
        const Node = struct {
            next: ?*Node,
        };

        /// Initialize the pool
        pub fn init() Self {
            var pool = Self{
                .memory = undefined,
                .free_list = null,
                .allocated_count = 0,
            };

            // Initialize free list
            var i: usize = 0;
            while (i < pool_size) : (i += 1) {
                const node: *Node = @ptrCast(@alignCast(&pool.memory[i * @sizeOf(T)]));
                node.next = pool.free_list;
                pool.free_list = node;
            }

            return pool;
        }

        /// Allocate an object from the pool
        pub fn alloc(self: *Self) ?*T {
            if (self.free_list) |node| {
                self.free_list = node.next;
                self.allocated_count += 1;
                const ptr: *T = @ptrCast(@alignCast(node));
                ptr.* = undefined; // Clear any free list data
                return ptr;
            }
            return null;
        }

        /// Return an object to the pool
        pub fn free(self: *Self, ptr: *T) void {
            const node: *Node = @ptrCast(@alignCast(ptr));
            node.next = self.free_list;
            self.free_list = node;
            self.allocated_count -= 1;
        }

        /// Get pool usage as a percentage (0.0 - 1.0)
        pub fn getUsage(self: *const Self) f32 {
            return @as(f32, @floatFromInt(self.allocated_count)) / @as(f32, @floatFromInt(pool_size));
        }

        /// Get number of available slots
        pub fn getAvailableCount(self: *const Self) usize {
            return pool_size - self.allocated_count;
        }

        /// Get number of allocated slots
        pub fn getAllocatedCount(self: *const Self) usize {
            return self.allocated_count;
        }

        /// Check if pool is full
        pub fn isFull(self: *const Self) bool {
            return self.allocated_count >= pool_size;
        }

        /// Check if pool is empty
        pub fn isEmpty(self: *const Self) bool {
            return self.allocated_count == 0;
        }

        /// Clear all allocations (unsafe if objects are still in use!)
        pub fn reset(self: *Self) void {
            self.free_list = null;
            self.allocated_count = 0;

            // Reinitialize free list
            var i: usize = 0;
            while (i < pool_size) : (i += 1) {
                const node: *Node = @ptrCast(@alignCast(&self.memory[i * @sizeOf(T)]));
                node.next = self.free_list;
                self.free_list = node;
            }
        }
    };
}

// =============================================================================
// Linear Allocator
// =============================================================================

/// Fast allocator for sequential allocations with bulk deallocation
///
/// **Thread Safety**: NOT thread-safe - wrap with mutex if needed
pub const LinearAllocator = struct {
    buffer: []u8,
    offset: usize,
    previous_offset: usize,
    backing_allocator: ?std.mem.Allocator,

    const Self = @This();

    /// Create a linear allocator with a fixed buffer
    pub fn initFixed(buffer: []u8) Self {
        return .{
            .buffer = buffer,
            .offset = 0,
            .previous_offset = 0,
            .backing_allocator = null,
        };
    }

    /// Create a linear allocator with dynamic buffer
    pub fn initDynamic(backing_alloc: std.mem.Allocator, size: usize) !Self {
        const buffer = try backing_alloc.alloc(u8, size);
        return .{
            .buffer = buffer,
            .offset = 0,
            .previous_offset = 0,
            .backing_allocator = backing_alloc,
        };
    }

    /// Cleanup dynamic buffer if used
    pub fn deinit(self: *Self) void {
        if (self.backing_allocator) |backing| {
            backing.free(self.buffer);
        }
    }

    /// Get the allocator interface
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    /// Reset the allocator, clearing all allocations
    pub fn reset(self: *Self) void {
        self.offset = 0;
        self.previous_offset = 0;
    }

    /// Get number of bytes used
    pub fn getBytesUsed(self: *const Self) usize {
        return self.offset;
    }

    /// Get number of bytes remaining
    pub fn getBytesRemaining(self: *const Self) usize {
        return self.buffer.len - self.offset;
    }

    fn alignForward(addr: usize, alignment: usize) usize {
        return (addr + alignment - 1) & ~(alignment - 1);
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        const alignment = @as(usize, 1) << @intCast(ptr_align);
        const aligned_offset = alignForward(self.offset, alignment);
        const end_offset = aligned_offset + len;

        if (end_offset > self.buffer.len) {
            return null; // Out of memory
        }

        self.previous_offset = self.offset;
        self.offset = end_offset;

        return self.buffer.ptr + aligned_offset;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        // Linear allocator doesn't support resize
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        // Linear allocator only supports freeing the last allocation
        if (@intFromPtr(buf.ptr) == @intFromPtr(self.buffer.ptr) + self.previous_offset) {
            self.offset = self.previous_offset;
        }
        // Otherwise, do nothing (bulk deallocation only)
    }
};

// =============================================================================
// Utility Functions
// =============================================================================

/// Create a tracking allocator
pub fn createTrackedAllocator(backing_allocator: std.mem.Allocator) TrackingAllocator {
    return TrackingAllocator.init(backing_allocator);
}

/// Create a debug allocator with default configuration
pub fn createDebugAllocator(backing_allocator: std.mem.Allocator) !DebugAllocator {
    return DebugAllocator.init(backing_allocator, .{});
}

/// Format byte count as human-readable string
pub fn formatBytes(bytes: u64, allocator: std.mem.Allocator) ![]u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var size = @as(f64, @floatFromInt(bytes));
    var unit_index: usize = 0;

    while (size >= 1024.0 and unit_index < units.len - 1) {
        size /= 1024.0;
        unit_index += 1;
    }

    return try std.fmt.allocPrint(allocator, "{d:.2} {s}", .{ size, units[unit_index] });
}

// =============================================================================
// Tests
// =============================================================================

test "allocator - TrackingAllocator" {
    const testing = std.testing;

    var tracker = TrackingAllocator.init(testing.allocator);
    const tracked_alloc = tracker.allocator();

    // Test allocation tracking
    const data = try tracked_alloc.alloc(u8, 100);
    defer tracked_alloc.free(data);

    const stats = tracker.getStats();
    try testing.expect(stats.allocation_count == 1);
    try testing.expect(stats.current_usage >= 100);
    try testing.expect(stats.peak_usage >= 100);

    // Test resize tracking
    if (tracked_alloc.resize(data, 200)) {
        const stats2 = tracker.getStats();
        try testing.expect(stats2.current_usage >= 200);
    }
}

test "allocator - DebugAllocator" {
    const testing = std.testing;

    var debug_alloc = try DebugAllocator.init(testing.allocator, .{
        .enable_guards = true,
        .enable_free_fill = true,
    });
    defer debug_alloc.deinit();

    const alloc = debug_alloc.allocator();

    // Test normal allocation
    const data = try alloc.alloc(u32, 10);
    try testing.expect(data.len == 10);

    // Fill with test data
    for (data, 0..) |*item, i| {
        item.* = @intCast(i);
    }

    // Free and check no leaks
    alloc.free(data);
    try testing.expect(debug_alloc.checkLeaks());
}

test "allocator - PoolAllocator" {
    const testing = std.testing;

    var pool = PoolAllocator(u32, 10).init();

    // Test allocation
    var items: [5]*u32 = undefined;
    for (&items) |*item| {
        item.* = pool.alloc() orelse return error.PoolExhausted;
    }

    try testing.expect(pool.getAllocatedCount() == 5);
    try testing.expect(pool.getAvailableCount() == 5);
    try testing.expectApproxEqAbs(pool.getUsage(), 0.5, 0.01);

    // Test freeing
    for (items) |item| {
        pool.free(item);
    }

    try testing.expect(pool.isEmpty());
    try testing.expect(pool.getAvailableCount() == 10);
}

test "allocator - LinearAllocator" {
    const testing = std.testing;

    var buffer: [1024]u8 = undefined;
    var linear = LinearAllocator.initFixed(&buffer);
    const alloc = linear.allocator();

    // Test sequential allocations
    const data1 = try alloc.alloc(u8, 100);
    const data2 = try alloc.alloc(u32, 50);

    try testing.expect(linear.getBytesUsed() >= 100 + 50 * @sizeOf(u32));
    try testing.expect(linear.getBytesRemaining() <= buffer.len - 100 - 50 * @sizeOf(u32));

    // Test that pointers are sequential
    try testing.expect(@intFromPtr(data2.ptr) > @intFromPtr(data1.ptr));

    // Test reset
    linear.reset();
    try testing.expect(linear.getBytesUsed() == 0);
    try testing.expect(linear.getBytesRemaining() == buffer.len);
}

test "allocator - formatBytes" {
    const testing = std.testing;

    const test_cases = .{
        .{ 0, "0.00 B" },
        .{ 100, "100.00 B" },
        .{ 1024, "1.00 KB" },
        .{ 1536, "1.50 KB" },
        .{ 1048576, "1.00 MB" },
        .{ 1073741824, "1.00 GB" },
    };

    inline for (test_cases) |tc| {
        const result = try formatBytes(tc[0], testing.allocator);
        defer testing.allocator.free(result);
        try testing.expectEqualStrings(tc[1], result);
    }
}
