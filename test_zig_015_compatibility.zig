//! Test script to verify Zig 0.15 compatibility of the MFS engine
//! This script tests the core components that have been updated

const std = @import("std");

// Test the core engine components
pub fn main() !void {
    std.log.info("Testing Zig 0.15 compatibility of MFS Engine...", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test 1: Engine Core
    std.log.info("Testing engine core...", .{});
    _ = @import("src/engine/core.zig");

    // Test ArrayList usage
    var test_list = std.ArrayList(u32).init(allocator);
    defer test_list.deinit();

    try test_list.append(1);
    try test_list.append(2);
    try test_list.append(3);

    std.log.info("ArrayList test passed - {} items", .{test_list.items.len});

    // Test 2: ECS System
    std.log.info("Testing ECS system...", .{});
    const ecs = @import("src/engine/ecs.zig");

    var world = ecs.World.init(allocator);
    defer world.deinit();

    const entity = try world.createEntity();
    std.log.info("ECS test passed - created entity {}", .{entity});

    // Test 3: Memory Pool
    std.log.info("Testing memory pool...", .{});
    const memory = @import("src/core/memory.zig");

    var pool = try memory.Pool(u32).init(allocator, 10);
    defer pool.deinit();

    const item = try pool.acquire();
    pool.release(item);

    std.log.info("Memory pool test passed", .{});

    // Test 4: Event System
    std.log.info("Testing event system...", .{});
    const events = @import("src/core/events.zig");

    const config = events.EventSystem.Config{};
    var event_system = events.EventSystem.init(allocator, config);
    defer event_system.deinit();

    std.log.info("Event system test passed", .{});

    std.log.info("All Zig 0.15 compatibility tests passed!", .{});
}
