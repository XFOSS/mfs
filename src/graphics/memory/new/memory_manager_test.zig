const std = @import("std");
const testing = std.testing;
const vk = @import("../../backends/vulkan/new/vulkan_backend.zig");
const memory_manager = @import("memory_manager.zig");
const MemoryManager = memory_manager.MemoryManager;
const MemoryBlock = memory_manager.MemoryBlock;

/// Mock Vulkan device for testing
const MockDevice = struct {
    allocator: std.mem.Allocator,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    allocated_memory: std.ArrayList(vk.DeviceMemory),
    mapped_memory: std.AutoHashMap(vk.DeviceMemory, *anyopaque),

    pub fn init(allocator: std.mem.Allocator) !*MockDevice {
        const self = try allocator.create(MockDevice);
        self.* = .{
            .allocator = allocator,
            .memory_properties = .{
                .memoryTypeCount = 2,
                .memoryTypes = [_]vk.MemoryType{
                    .{
                        .propertyFlags = .{ .device_local_bit = true },
                        .heapIndex = 0,
                    },
                    .{
                        .propertyFlags = .{
                            .host_visible_bit = true,
                            .host_coherent_bit = true,
                        },
                        .heapIndex = 1,
                    },
                },
                .memoryHeapCount = 2,
                .memoryHeaps = [_]vk.MemoryHeap{
                    .{ .size = 1024 * 1024 * 1024, .flags = .{ .device_local_bit = true } },
                    .{ .size = 512 * 1024 * 1024, .flags = .{} },
                },
            },
            .allocated_memory = std.ArrayList(vk.DeviceMemory).init(allocator),
            .mapped_memory = std.AutoHashMap(vk.DeviceMemory, *anyopaque).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *MockDevice) void {
        self.allocated_memory.deinit();
        self.mapped_memory.deinit();
        self.allocator.destroy(self);
    }

    pub fn allocateMemory(
        self: *MockDevice,
        _: std.mem.Allocator,
        _: vk.MemoryAllocateInfo,
    ) !vk.DeviceMemory {
        const memory = @as(vk.DeviceMemory, @ptrFromInt(@intFromPtr(self) + self.allocated_memory.items.len + 1));
        try self.allocated_memory.append(memory);
        return memory;
    }

    pub fn freeMemory(self: *MockDevice, memory: vk.DeviceMemory, _: ?*const anyopaque) void {
        for (self.allocated_memory.items, 0..) |mem, i| {
            if (mem == memory) {
                _ = self.allocated_memory.orderedRemove(i);
                break;
            }
        }
        _ = self.mapped_memory.remove(memory);
    }

    pub fn mapMemory(
        self: *MockDevice,
        memory: vk.DeviceMemory,
        _: vk.DeviceSize,
        _: vk.DeviceSize,
        _: vk.MemoryMapFlags,
    ) !*anyopaque {
        const ptr = try self.allocator.alloc(u8, 1024);
        try self.mapped_memory.put(memory, ptr.ptr);
        return ptr.ptr;
    }

    pub fn unmapMemory(self: *MockDevice, memory: vk.DeviceMemory) void {
        if (self.mapped_memory.get(memory)) |ptr| {
            const slice = @as([*]u8, @ptrCast(ptr))[0..1024];
            self.allocator.free(slice);
            _ = self.mapped_memory.remove(memory);
        }
    }
};

test "MemoryManager basic allocation" {
    const allocator = testing.allocator;
    var device = try MockDevice.init(allocator);
    defer device.deinit();

    var manager = try MemoryManager.init(
        allocator,
        device,
        device,
        1024 * 1024, // 1MB pool size
        256, // min block size
    );
    defer manager.deinit();

    // Allocate device local memory
    const block1 = try manager.allocate(
        256,
        64,
        0b01, // First memory type
        .{ .device_local_bit = true },
    );

    try testing.expect(block1.size == 256);
    try testing.expect(block1.alignment == 64);
    try testing.expect(block1.memory_type_index == 0);
    try testing.expect(block1.in_use);

    // Allocate host visible memory
    const block2 = try manager.allocate(
        512,
        128,
        0b10, // Second memory type
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    try testing.expect(block2.size == 512);
    try testing.expect(block2.alignment == 128);
    try testing.expect(block2.memory_type_index == 1);
    try testing.expect(block2.in_use);

    // Free blocks
    manager.free(&block1);
    manager.free(&block2);

    // Check stats
    const stats = manager.getStats();
    try testing.expect(stats.total_allocated == 768);
    try testing.expect(stats.total_freed == 768);
    try testing.expect(stats.current_usage == 0);
    try testing.expect(stats.allocation_count == 2);
    try testing.expect(stats.deallocation_count == 2);
}

test "MemoryManager memory mapping" {
    const allocator = testing.allocator;
    var device = try MockDevice.init(allocator);
    defer device.deinit();

    var manager = try MemoryManager.init(
        allocator,
        device,
        device,
        1024 * 1024,
        256,
    );
    defer manager.deinit();

    // Allocate host visible memory
    var block = try manager.allocate(
        256,
        64,
        0b10,
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );

    // Map memory
    const ptr = try manager.map(&block);
    try testing.expect(ptr != null);

    // Unmap memory
    manager.unmap(&block);
    try testing.expect(block.mapped_ptr == null);

    // Free block
    manager.free(&block);
}

test "MemoryManager defragmentation" {
    const allocator = testing.allocator;
    var device = try MockDevice.init(allocator);
    defer device.deinit();

    var manager = try MemoryManager.init(
        allocator,
        device,
        device,
        1024 * 1024,
        256,
    );
    defer manager.deinit();

    // Allocate several blocks
    var blocks: [4]MemoryBlock = undefined;
    for (0..4) |i| {
        blocks[i] = try manager.allocate(
            256,
            64,
            0b01,
            .{ .device_local_bit = true },
        );
    }

    // Free alternating blocks
    manager.free(&blocks[1]);
    manager.free(&blocks[3]);

    // Defragment
    try manager.defragment();

    // Check stats
    const stats = manager.getStats();
    try testing.expect(stats.current_usage == 512); // Two blocks still in use
}

test "MemoryManager out of memory" {
    const allocator = testing.allocator;
    var device = try MockDevice.init(allocator);
    defer device.deinit();

    var manager = try MemoryManager.init(
        allocator,
        device,
        device,
        1024, // Small pool
        256,
    );
    defer manager.deinit();

    // Try to allocate more than pool size
    try testing.expectError(
        error.OutOfMemory,
        manager.allocate(
            2048,
            64,
            0b01,
            .{ .device_local_bit = true },
        ),
    );
}

test "MemoryManager thread safety" {
    const allocator = testing.allocator;
    var device = try MockDevice.init(allocator);
    defer device.deinit();

    var manager = try MemoryManager.init(
        allocator,
        device,
        device,
        1024 * 1024,
        256,
    );
    defer manager.deinit();

    const ThreadContext = struct {
        manager: *MemoryManager,
        allocations: usize,
        allocator: std.mem.Allocator,

        fn run(self: @This()) !void {
            var blocks = std.ArrayList(MemoryBlock).init(self.allocator);
            defer blocks.deinit();

            // Perform multiple allocations
            for (0..self.allocations) |_| {
                const block = try self.manager.allocate(
                    256,
                    64,
                    0b01,
                    .{ .device_local_bit = true },
                );
                try blocks.append(block);
            }

            // Free all blocks
            for (blocks.items) |*block| {
                self.manager.free(block);
            }
        }
    };

    // Create multiple threads
    var threads: [4]std.Thread = undefined;
    const context = ThreadContext{
        .manager = manager,
        .allocations = 100,
        .allocator = allocator,
    };

    // Start threads
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, ThreadContext.run, .{context});
    }

    // Wait for threads
    for (threads) |thread| {
        thread.join();
    }

    // Check final stats
    const stats = manager.getStats();
    try testing.expect(stats.allocation_count == 400); // 4 threads * 100 allocations
    try testing.expect(stats.deallocation_count == 400);
    try testing.expect(stats.current_usage == 0);
}
