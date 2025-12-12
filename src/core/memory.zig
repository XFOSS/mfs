//! Memory Management System
//! Provides memory allocators, pools, and tracking for the engine

const std = @import("std");
const builtin = @import("builtin");

/// Engine allocator wrapper with tracking and debugging
pub const Allocator = struct {
    backing_allocator: std.mem.Allocator,
    bytes_allocated: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    allocations: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    peak_memory: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    enable_tracking: bool,

    const Self = @This();

    pub fn init(backing_allocator: std.mem.Allocator, enable_tracking: bool) Self {
        return Self{
            .backing_allocator = backing_allocator,
            .enable_tracking = enable_tracking,
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn getStats(self: *const Self) MemoryStats {
        return MemoryStats{
            .bytes_allocated = self.bytes_allocated.load(.monotonic),
            .allocations = self.allocations.load(.monotonic),
            .peak_memory = self.peak_memory.load(.monotonic),
        };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.backing_allocator.rawAlloc(len, log2_ptr_align, ret_addr);

        if (result != null and self.enable_tracking) {
            _ = self.bytes_allocated.fetchAdd(len, .monotonic);
            _ = self.allocations.fetchAdd(1, .monotonic);

            const current = self.bytes_allocated.load(.monotonic);
            const peak = self.peak_memory.load(.monotonic);
            if (current > peak) {
                self.peak_memory.store(current, .monotonic);
            }
        }

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.backing_allocator.rawResize(buf, log2_buf_align, new_len, ret_addr);

        if (result and self.enable_tracking) {
            const old_size = buf.len;
            if (new_len > old_size) {
                _ = self.bytes_allocated.fetchAdd(new_len - old_size, .monotonic);
            } else {
                _ = self.bytes_allocated.fetchSub(old_size - new_len, .monotonic);
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.enable_tracking) {
            _ = self.bytes_allocated.fetchSub(buf.len, .monotonic);
            _ = self.allocations.fetchSub(1, .monotonic);
        }

        self.backing_allocator.rawFree(buf, log2_buf_align, ret_addr);
    }
};

/// Memory usage statistics
pub const MemoryStats = struct {
    bytes_allocated: usize,
    allocations: usize,
    peak_memory: usize,
};

/// Object pool for efficient allocation of same-sized objects
pub fn Pool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        available: std.array_list.Managed(*T),
        all_objects: std.array_list.Managed(*T),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !Self {
            var pool = Self{
                .allocator = allocator,
                .available = std.array_list.Managed(*T).init(allocator),
                .all_objects = std.array_list.Managed(*T).init(allocator),
            };

            // Pre-allocate objects
            for (0..initial_capacity) |_| {
                const obj = try allocator.create(T);
                try pool.available.append(obj);
                try pool.all_objects.append(obj);
            }

            return pool;
        }

        pub fn deinit(self: *Self) void {
            for (self.all_objects.items) |obj| {
                self.allocator.destroy(obj);
            }
            self.available.deinit();
            self.all_objects.deinit();
        }

        pub fn acquire(self: *Self) !*T {
            if (self.available.items.len > 0) {
                return self.available.pop() orelse unreachable;
            }

            // Create new object if pool is empty
            const obj = try self.allocator.create(T);
            try self.all_objects.append(obj);
            return obj;
        }

        pub fn release(self: *Self, obj: *T) void {
            // Reset object to default state
            obj.* = std.mem.zeroes(T);
            self.available.append(obj) catch {
                // If we can't add back to pool, just leak it
                // This is better than crashing
            };
        }

        pub fn getStats(self: *const Self) PoolStats {
            return PoolStats{
                .total_objects = self.all_objects.items.len,
                .available_objects = self.available.items.len,
                .in_use_objects = self.all_objects.items.len - self.available.items.len,
            };
        }
    };
}

pub const PoolStats = struct {
    total_objects: usize,
    available_objects: usize,
    in_use_objects: usize,
};

/// Stack allocator for temporary allocations
pub const StackAllocator = struct {
    buffer: []u8,
    pos: usize = 0,

    const Self = @This();

    pub fn init(buffer: []u8) Self {
        return Self{
            .buffer = buffer,
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn reset(self: *Self) void {
        self.pos = 0;
    }

    pub fn getUsed(self: *const Self) usize {
        return self.pos;
    }

    pub fn getRemaining(self: *const Self) usize {
        return self.buffer.len - self.pos;
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        const ptr_align = @as(usize, 1) << @intCast(log2_ptr_align);
        const start = std.mem.alignForward(usize, self.pos, ptr_align);
        const end = start + len;

        if (end > self.buffer.len) {
            return null;
        }

        self.pos = end;
        return self.buffer.ptr + start;
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = log2_buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Stack allocator doesn't support resize
    }

    fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = log2_buf_align;
        _ = ret_addr;
        // Stack allocator doesn't support individual frees
    }
};

/// Global memory manager
pub const MemoryManager = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{ .safety = builtin.mode == .Debug }),
    engine_allocator: Allocator,
    temp_arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init() !Self {
        var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = builtin.mode == .Debug }){};
        const backing = gpa.allocator();

        return Self{
            .gpa = gpa,
            .engine_allocator = Allocator.init(backing, builtin.mode == .Debug),
            .temp_arena = std.heap.ArenaAllocator.init(backing),
        };
    }

    pub fn deinit(self: *Self) void {
        self.temp_arena.deinit();
        _ = self.gpa.deinit();
    }

    pub fn getAllocator(self: *Self) std.mem.Allocator {
        return self.engine_allocator.allocator();
    }

    pub fn getTempAllocator(self: *Self) std.mem.Allocator {
        return self.temp_arena.allocator();
    }

    pub fn resetTempAllocator(self: *Self) void {
        self.temp_arena.deinit();
        self.temp_arena = std.heap.ArenaAllocator.init(self.gpa.allocator());
    }

    pub fn getStats(self: *const Self) MemoryStats {
        return self.engine_allocator.getStats();
    }
};

// Tests
test "allocator tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tracked = Allocator.init(gpa.allocator(), true);
    const allocator = tracked.allocator();

    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);

    const stats = tracked.getStats();
    try std.testing.expect(stats.bytes_allocated >= 100);
    try std.testing.expect(stats.allocations >= 1);
}

test "object pool" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const TestStruct = struct {
        value: i32 = 0,
    };

    var pool = try Pool(TestStruct).init(gpa.allocator(), 2);
    defer pool.deinit();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();

    obj1.value = 42;
    obj2.value = 84;

    pool.release(obj1);
    pool.release(obj2);

    const obj3 = try pool.acquire();
    try std.testing.expect(obj3.value == 0); // Should be reset
}

test "stack allocator" {
    var buffer: [1024]u8 = undefined;
    var stack = StackAllocator.init(&buffer);
    const allocator = stack.allocator();

    const data1 = try allocator.alloc(u8, 100);
    const data2 = try allocator.alloc(u8, 200);

    try std.testing.expect(data1.len == 100);
    try std.testing.expect(data2.len == 200);
    try std.testing.expect(stack.getUsed() >= 300);

    stack.reset();
    try std.testing.expect(stack.getUsed() == 0);
}
