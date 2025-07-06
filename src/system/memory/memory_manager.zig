//! Advanced Memory Management System for MFS Engine
//! Provides comprehensive memory tracking, allocation pools, and leak detection
//! @thread-safe All operations are thread-safe with proper synchronization
//! @symbol MemoryManager - Main memory management interface

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic.Value;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;

// Core memory management components
const profiler = @import("../profiling/profiler.zig");

/// Memory allocation categories for tracking and debugging
pub const MemoryCategory = enum {
    general,
    graphics,
    audio,
    physics,
    scripting,
    networking,
    ui,
    assets,
    temporary,
    debug,

    pub fn toString(self: MemoryCategory) []const u8 {
        return switch (self) {
            .general => "General",
            .graphics => "Graphics",
            .audio => "Audio",
            .physics => "Physics",
            .scripting => "Scripting",
            .networking => "Networking",
            .ui => "UI",
            .assets => "Assets",
            .temporary => "Temporary",
            .debug => "Debug",
        };
    }
};

/// Memory allocation information for tracking
pub const AllocationInfo = struct {
    ptr: *anyopaque,
    size: usize,
    alignment: u8,
    category: MemoryCategory,
    timestamp: i64,
    thread_id: Thread.Id,
    call_stack: ?[]const usize = null,
    source_location: ?std.builtin.SourceLocation = null,
    freed: bool = false,
    free_timestamp: ?i64 = null,

    pub fn deinit(self: *AllocationInfo, allocator: Allocator) void {
        if (self.call_stack) |stack| {
            allocator.free(stack);
        }
    }
};

/// Memory pool for efficient allocation of fixed-size objects
pub fn MemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            data: T,
            next: ?*Node,
        };

        allocator: Allocator,
        free_list: ?*Node,
        allocated_nodes: ArrayList(*Node),
        mutex: Mutex,
        capacity: usize,
        allocated_count: Atomic(usize),
        peak_usage: Atomic(usize),
        total_allocations: Atomic(usize),
        total_deallocations: Atomic(usize),

        pub fn init(allocator: Allocator, initial_capacity: usize) !Self {
            var pool = Self{
                .allocator = allocator,
                .free_list = null,
                .allocated_nodes = ArrayList(*Node).init(allocator),
                .mutex = Mutex{},
                .capacity = initial_capacity,
                .allocated_count = Atomic(usize).init(0),
                .peak_usage = Atomic(usize).init(0),
                .total_allocations = Atomic(usize).init(0),
                .total_deallocations = Atomic(usize).init(0),
            };

            try pool.allocated_nodes.ensureTotalCapacity(initial_capacity);
            try pool.expandPool(initial_capacity);
            return pool;
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (self.allocated_nodes.items) |node| {
                self.allocator.destroy(node);
            }
            self.allocated_nodes.deinit();
        }

        pub fn acquire(self: *Self) !*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.free_list) |node| {
                self.free_list = node.next;
                const count = self.allocated_count.fetchAdd(1, .monotonic) + 1;
                _ = self.total_allocations.fetchAdd(1, .monotonic);

                // Update peak usage
                const current_peak = self.peak_usage.load(.monotonic);
                if (count > current_peak) {
                    _ = self.peak_usage.compareAndSwap(current_peak, count, .monotonic, .monotonic);
                }

                return &node.data;
            } else {
                // Expand pool if needed
                try self.expandPool(self.capacity / 2);
                return self.acquire();
            }
        }

        pub fn release(self: *Self, item: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const node: *Node = @fieldParentPtr("data", item);
            node.next = self.free_list;
            self.free_list = node;
            _ = self.allocated_count.fetchSub(1, .monotonic);
            _ = self.total_deallocations.fetchAdd(1, .monotonic);
        }

        fn expandPool(self: *Self, count: usize) !void {
            for (0..count) |_| {
                const node = try self.allocator.create(Node);
                node.* = Node{
                    .data = undefined,
                    .next = self.free_list,
                };
                self.free_list = node;
                try self.allocated_nodes.append(node);
            }
            self.capacity += count;
        }

        pub fn getStats(self: *const Self) PoolStats {
            return PoolStats{
                .capacity = self.capacity,
                .allocated = self.allocated_count.load(.monotonic),
                .peak_usage = self.peak_usage.load(.monotonic),
                .total_allocations = self.total_allocations.load(.monotonic),
                .total_deallocations = self.total_deallocations.load(.monotonic),
            };
        }
    };
}

/// Statistics for memory pools
pub const PoolStats = struct {
    capacity: usize,
    allocated: usize,
    peak_usage: usize,
    total_allocations: usize,
    total_deallocations: usize,

    pub fn utilizationPercent(self: PoolStats) f32 {
        if (self.capacity == 0) return 0.0;
        return @as(f32, @floatFromInt(self.allocated)) / @as(f32, @floatFromInt(self.capacity)) * 100.0;
    }
};

/// Stack allocator for temporary allocations
pub const StackAllocator = struct {
    const Self = @This();
    const Marker = struct {
        offset: usize,
    };

    buffer: []u8,
    offset: usize,
    mutex: Mutex,
    high_water_mark: usize,

    pub fn init(buffer: []u8) Self {
        return Self{
            .buffer = buffer,
            .offset = 0,
            .mutex = Mutex{},
            .high_water_mark = 0,
        };
    }

    pub fn allocator(self: *Self) Allocator {
        return Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    pub fn getMarker(self: *Self) Marker {
        self.mutex.lock();
        defer self.mutex.unlock();
        return Marker{ .offset = self.offset };
    }

    pub fn freeToMarker(self: *Self, marker: Marker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.offset = marker.offset;
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.offset = 0;
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.mutex.lock();
        defer self.mutex.unlock();

        const alignment = @as(usize, 1) << @intCast(log2_align);
        const aligned_offset = std.mem.alignForward(usize, self.offset, alignment);
        const new_offset = aligned_offset + len;

        if (new_offset > self.buffer.len) {
            return null; // Out of memory
        }

        self.offset = new_offset;
        if (new_offset > self.high_water_mark) {
            self.high_water_mark = new_offset;
        }

        return self.buffer[aligned_offset..new_offset].ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = log2_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Stack allocator doesn't support resize
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = log2_align;
        _ = ret_addr;
        // Stack allocator doesn't support individual frees
    }

    pub fn getUsage(self: *const Self) f32 {
        if (self.buffer.len == 0) return 0.0;
        return @as(f32, @floatFromInt(self.offset)) / @as(f32, @floatFromInt(self.buffer.len));
    }

    pub fn getHighWaterMark(self: *const Self) f32 {
        if (self.buffer.len == 0) return 0.0;
        return @as(f32, @floatFromInt(self.high_water_mark)) / @as(f32, @floatFromInt(self.buffer.len));
    }
};

/// Tracking allocator that wraps another allocator and tracks all allocations
pub const TrackingAllocator = struct {
    const Self = @This();

    child_allocator: Allocator,
    allocations: AutoHashMap(usize, AllocationInfo),
    mutex: Mutex,
    total_allocated: Atomic(usize),
    total_freed: Atomic(usize),
    peak_usage: Atomic(usize),
    current_usage: Atomic(usize),
    allocation_count: Atomic(usize),
    category_stats: [std.meta.fields(MemoryCategory).len]Atomic(usize),

    pub fn init(child_allocator: Allocator) Self {
        var category_stats: [std.meta.fields(MemoryCategory).len]Atomic(usize) = undefined;
        for (&category_stats) |*stat| {
            stat.* = Atomic(usize).init(0);
        }

        return Self{
            .child_allocator = child_allocator,
            .allocations = AutoHashMap(usize, AllocationInfo).init(child_allocator),
            .mutex = Mutex{},
            .total_allocated = Atomic(usize).init(0),
            .total_freed = Atomic(usize).init(0),
            .peak_usage = Atomic(usize).init(0),
            .current_usage = Atomic(usize).init(0),
            .allocation_count = Atomic(usize).init(0),
            .category_stats = category_stats,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free all allocation info
        var it = self.allocations.valueIterator();
        while (it.next()) |info| {
            info.deinit(self.child_allocator);
        }
        self.allocations.deinit();
    }

    pub fn allocator(self: *Self) Allocator {
        return Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    pub fn allocWithCategory(self: *Self, len: usize, log2_align: u8, category: MemoryCategory, source_location: ?std.builtin.SourceLocation) ![]u8 {
        const ptr = self.child_allocator.rawAlloc(len, log2_align, @returnAddress()) orelse return error.OutOfMemory;

        self.trackAllocation(ptr, len, log2_align, category, source_location);
        return ptr[0..len];
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const ptr = self.child_allocator.rawAlloc(len, log2_align, ret_addr) orelse return null;

        self.trackAllocation(ptr, len, log2_align, .general, null);
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.child_allocator.rawResize(buf, log2_align, new_len, ret_addr)) {
            self.updateAllocation(buf.ptr, buf.len, new_len);
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.untrackAllocation(buf.ptr, buf.len);
        self.child_allocator.rawFree(buf, log2_align, ret_addr);
    }

    fn trackAllocation(self: *Self, ptr: [*]u8, len: usize, log2_align: u8, category: MemoryCategory, source_location: ?std.builtin.SourceLocation) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const info = AllocationInfo{
            .ptr = ptr,
            .size = len,
            .alignment = @intCast(log2_align),
            .category = category,
            .timestamp = std.time.nanoTimestamp(),
            .thread_id = Thread.getCurrentId(),
            .source_location = source_location,
        };

        self.allocations.put(@intFromPtr(ptr), info) catch {
            // If we can't track the allocation, continue anyway
        };

        // Update statistics
        _ = self.total_allocated.fetchAdd(len, .monotonic);
        const current = self.current_usage.fetchAdd(len, .monotonic) + len;
        _ = self.allocation_count.fetchAdd(1, .monotonic);
        _ = self.category_stats[@intFromEnum(category)].fetchAdd(len, .monotonic);

        // Update peak usage
        const current_peak = self.peak_usage.load(.monotonic);
        if (current > current_peak) {
            _ = self.peak_usage.compareAndSwap(current_peak, current, .monotonic, .monotonic);
        }

        // Notify profiler if available
        if (@hasDecl(profiler, "trackAllocation")) {
            profiler.trackAllocation(ptr, len, category.toString(), source_location);
        }
    }

    fn untrackAllocation(self: *Self, ptr: [*]u8, len: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ptr_int = @intFromPtr(ptr);
        if (self.allocations.getPtr(ptr_int)) |info| {
            info.freed = true;
            info.free_timestamp = std.time.nanoTimestamp();

            _ = self.total_freed.fetchAdd(len, .monotonic);
            _ = self.current_usage.fetchSub(len, .monotonic);
            _ = self.category_stats[@intFromEnum(info.category)].fetchSub(len, .monotonic);

            // Notify profiler if available
            if (@hasDecl(profiler, "trackDeallocation")) {
                profiler.trackDeallocation(ptr);
            }
        }
    }

    fn updateAllocation(self: *Self, ptr: [*]u8, old_len: usize, new_len: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const ptr_int = @intFromPtr(ptr);
        if (self.allocations.getPtr(ptr_int)) |info| {
            const size_diff = @as(i64, @intCast(new_len)) - @as(i64, @intCast(old_len));

            info.size = new_len;
            info.timestamp = std.time.nanoTimestamp();

            if (size_diff > 0) {
                _ = self.total_allocated.fetchAdd(@intCast(size_diff), .monotonic);
                _ = self.current_usage.fetchAdd(@intCast(size_diff), .monotonic);
                _ = self.category_stats[@intFromEnum(info.category)].fetchAdd(@intCast(size_diff), .monotonic);
            } else if (size_diff < 0) {
                _ = self.total_freed.fetchAdd(@intCast(-size_diff), .monotonic);
                _ = self.current_usage.fetchSub(@intCast(-size_diff), .monotonic);
                _ = self.category_stats[@intFromEnum(info.category)].fetchSub(@intCast(-size_diff), .monotonic);
            }
        }
    }

    pub fn getMemoryStats(self: *const Self) MemoryStats {
        var category_usage: [std.meta.fields(MemoryCategory).len]usize = undefined;
        for (&category_usage, &self.category_stats) |*usage, *stat| {
            usage.* = stat.load(.monotonic);
        }

        return MemoryStats{
            .total_allocated = self.total_allocated.load(.monotonic),
            .total_freed = self.total_freed.load(.monotonic),
            .current_usage = self.current_usage.load(.monotonic),
            .peak_usage = self.peak_usage.load(.monotonic),
            .allocation_count = self.allocation_count.load(.monotonic),
            .category_usage = category_usage,
        };
    }

    pub fn detectLeaks(self: *Self, leak_allocator: Allocator) ![]AllocationInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        var leaks = ArrayList(AllocationInfo).init(leak_allocator);
        var it = self.allocations.valueIterator();

        while (it.next()) |info| {
            if (!info.freed) {
                try leaks.append(info.*);
            }
        }

        return leaks.toOwnedSlice();
    }
};

/// Memory statistics structure
pub const MemoryStats = struct {
    total_allocated: usize,
    total_freed: usize,
    current_usage: usize,
    peak_usage: usize,
    allocation_count: usize,
    category_usage: [std.meta.fields(MemoryCategory).len]usize,

    pub fn getCategoryUsage(self: MemoryStats, category: MemoryCategory) usize {
        return self.category_usage[@intFromEnum(category)];
    }

    pub fn getFragmentation(self: MemoryStats) f32 {
        if (self.total_allocated == 0) return 0.0;
        return @as(f32, @floatFromInt(self.total_allocated - self.current_usage)) / @as(f32, @floatFromInt(self.total_allocated));
    }
};

/// Global memory manager instance
pub const MemoryManager = struct {
    const Self = @This();

    base_allocator: Allocator,
    tracking_allocator: TrackingAllocator,
    stack_allocator: StackAllocator,
    stack_buffer: []u8,

    // Memory pools for common types
    vec3_pool: MemoryPool([3]f32),
    mat4_pool: MemoryPool([16]f32),
    entity_pool: MemoryPool(u32),

    mutex: Mutex,
    initialized: bool,

    pub fn init(base_allocator: Allocator, stack_size: usize) !Self {
        const stack_buffer = try base_allocator.alloc(u8, stack_size);

        return Self{
            .base_allocator = base_allocator,
            .tracking_allocator = TrackingAllocator.init(base_allocator),
            .stack_allocator = StackAllocator.init(stack_buffer),
            .stack_buffer = stack_buffer,
            .vec3_pool = try MemoryPool([3]f32).init(base_allocator, 1000),
            .mat4_pool = try MemoryPool([16]f32).init(base_allocator, 500),
            .entity_pool = try MemoryPool(u32).init(base_allocator, 10000),
            .mutex = Mutex{},
            .initialized = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.initialized) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        self.vec3_pool.deinit();
        self.mat4_pool.deinit();
        self.entity_pool.deinit();
        self.tracking_allocator.deinit();
        self.base_allocator.free(self.stack_buffer);
        self.initialized = false;
    }

    pub fn getAllocator(self: *Self) Allocator {
        return self.tracking_allocator.allocator();
    }

    pub fn getStackAllocator(self: *Self) Allocator {
        return self.stack_allocator.allocator();
    }

    pub fn allocWithCategory(self: *Self, len: usize, category: MemoryCategory, source_location: ?std.builtin.SourceLocation) ![]u8 {
        return self.tracking_allocator.allocWithCategory(len, 0, category, source_location);
    }

    pub fn generateMemoryReport(self: *Self, writer: anytype) !void {
        const stats = self.tracking_allocator.getMemoryStats();

        try writer.print("=== Memory Report ===\n");
        try writer.print("Total Allocated: {} bytes\n", .{stats.total_allocated});
        try writer.print("Total Freed: {} bytes\n", .{stats.total_freed});
        try writer.print("Current Usage: {} bytes\n", .{stats.current_usage});
        try writer.print("Peak Usage: {} bytes\n", .{stats.peak_usage});
        try writer.print("Active Allocations: {}\n", .{stats.allocation_count});
        try writer.print("Fragmentation: {d:.2}%\n", .{stats.getFragmentation() * 100});

        try writer.print("\nCategory Breakdown:\n");
        inline for (std.meta.fields(MemoryCategory)) |field| {
            const category: MemoryCategory = @enumFromInt(field.value);
            const usage = stats.getCategoryUsage(category);
            try writer.print("  {s}: {} bytes\n", .{ category.toString(), usage });
        }

        try writer.print("\nPool Statistics:\n");
        const vec3_stats = self.vec3_pool.getStats();
        try writer.print("  Vec3 Pool: {}/{} ({d:.1}% utilized)\n", .{ vec3_stats.allocated, vec3_stats.capacity, vec3_stats.utilizationPercent() });

        const mat4_stats = self.mat4_pool.getStats();
        try writer.print("  Mat4 Pool: {}/{} ({d:.1}% utilized)\n", .{ mat4_stats.allocated, mat4_stats.capacity, mat4_stats.utilizationPercent() });

        const entity_stats = self.entity_pool.getStats();
        try writer.print("  Entity Pool: {}/{} ({d:.1}% utilized)\n", .{ entity_stats.allocated, entity_stats.capacity, entity_stats.utilizationPercent() });

        try writer.print("\nStack Allocator:\n");
        try writer.print("  Current Usage: {d:.1}%\n", .{self.stack_allocator.getUsage() * 100});
        try writer.print("  High Water Mark: {d:.1}%\n", .{self.stack_allocator.getHighWaterMark() * 100});
    }
};

// Global memory manager instance
var g_memory_manager: ?MemoryManager = null;
var g_memory_mutex: Mutex = Mutex{};

/// Initialize the global memory manager
pub fn initGlobalMemoryManager(base_allocator: Allocator, stack_size: usize) !void {
    g_memory_mutex.lock();
    defer g_memory_mutex.unlock();

    if (g_memory_manager != null) return error.AlreadyInitialized;

    g_memory_manager = try MemoryManager.init(base_allocator, stack_size);
}

/// Get the global memory manager
pub fn getGlobalMemoryManager() ?*MemoryManager {
    g_memory_mutex.lock();
    defer g_memory_mutex.unlock();

    return if (g_memory_manager) |*manager| manager else null;
}

/// Deinitialize the global memory manager
pub fn deinitGlobalMemoryManager() void {
    g_memory_mutex.lock();
    defer g_memory_mutex.unlock();

    if (g_memory_manager) |*manager| {
        manager.deinit();
        g_memory_manager = null;
    }
}

// Tests
test "memory pool basic operations" {
    const testing = std.testing;

    var pool = try MemoryPool(i32).init(testing.allocator, 10);
    defer pool.deinit();

    const item1 = try pool.acquire();
    const item2 = try pool.acquire();

    item1.* = 42;
    item2.* = 84;

    try testing.expect(item1.* == 42);
    try testing.expect(item2.* == 84);

    pool.release(item1);
    pool.release(item2);

    const stats = pool.getStats();
    try testing.expect(stats.total_allocations == 2);
    try testing.expect(stats.total_deallocations == 2);
}

test "tracking allocator" {
    const testing = std.testing;

    var tracking = TrackingAllocator.init(testing.allocator);
    defer tracking.deinit();

    const allocator = tracking.allocator();

    const memory = try allocator.alloc(u8, 100);
    defer allocator.free(memory);

    const stats = tracking.getMemoryStats();
    try testing.expect(stats.current_usage >= 100);
    try testing.expect(stats.total_allocated >= 100);
}

test "stack allocator" {
    const testing = std.testing;

    var buffer: [1024]u8 = undefined;
    var stack = StackAllocator.init(&buffer);
    const allocator = stack.allocator();

    const marker = stack.getMarker();

    const mem1 = try allocator.alloc(u8, 100);
    const mem2 = try allocator.alloc(u8, 200);

    try testing.expect(mem1.len == 100);
    try testing.expect(mem2.len == 200);

    stack.freeToMarker(marker);

    const mem3 = try allocator.alloc(u8, 50);
    try testing.expect(mem3.len == 50);
}
