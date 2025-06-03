const std = @import("std");
const memory_profiler = @import("system/profiling/memory_profiler.zig");
const Profiler = @import("system/profiling/profiler.zig").Profiler;

pub fn main() !void {
    // Initialize the profiler
    try Profiler.init(std.heap.page_allocator);
    defer Profiler.deinit();

    // Start memory profiling
    try memory_profiler.startMemoryProfiling();

    std.debug.print("Memory Profiling Example\n", .{});
    std.debug.print("-------------------------\n", .{});

    // Create a tracked allocator
    var tracked_gpa = try memory_profiler.createTrackedGPA();
    defer {
        const leaked = tracked_gpa.deinit();
        if (leaked) {
            std.debug.print("Memory leaks detected in GPA!\n", .{});
        }
    }

    const allocator = tracked_gpa.allocator();

    // Simulate different allocation patterns
    simulateNormalAllocations(allocator);
    simulateTemporaryAllocations(allocator);
    simulateLeakingAllocations(allocator);

    // Print stats after our allocations
    std.debug.print("\nMemory usage after allocations:\n", .{});
    memory_profiler.printMemoryStats();

    // Save profiling data
    try memory_profiler.saveMemoryProfile("memory_profile.csv");
    std.debug.print("\nMemory profile saved to 'memory_profile.csv'\n", .{});
    std.debug.print("Run the profiler visualizer to analyze the data:\n", .{});
    std.debug.print("  ./profiler_visualizer memory_profile.csv\n", .{});
}

// Allocate and free memory properly
fn simulateNormalAllocations(allocator: std.mem.Allocator) void {
    std.debug.print("\nSimulating normal allocations...\n", .{});

    // Track this section
    const zone = Profiler.beginZoneWithColor("Normal Allocations", 0x00FF00);
    defer Profiler.endZone(zone);

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    // Perform some allocations
    for (0..5) |i| {
        // Allocate some memory
        const size = 1024 * (i + 1);
        const data = allocator.alloc(u8, size) catch {
            std.debug.print("Failed to allocate memory\n", .{});
            return;
        };
        defer allocator.free(data);

        // Do something with the data
        @memset(data, @intCast(i % 256));

        // Add to our list
        list.appendSlice(data[0..10]) catch {};

        std.time.sleep(50 * std.time.ns_per_ms); // Pause for visualization
    }

    std.debug.print("  Created and freed {} allocations\n", .{5});
}

// Allocate and free temporary objects
fn simulateTemporaryAllocations(allocator: std.mem.Allocator) void {
    std.debug.print("\nSimulating temporary allocations...\n", .{});

    // Track this section
    const zone = Profiler.beginZoneWithColor("Temporary Allocations", 0x0000FF);
    defer Profiler.endZone(zone);

    var peak_memory: usize = 0;

    // Create a temporary arena for short-lived allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Track arena operations with specific category
    var tracked_arena = memory_profiler.createTrackedAllocator(arena_allocator, .Resources);
    const tracked_alloc = tracked_arena.allocator();

    // Create many short-lived objects
    for (0..10) |i| {
        // Create a temporary string
        const temp_str = std.fmt.allocPrint(tracked_alloc, "Temporary string {d}", .{i}) catch continue;
        // Normally we would free this, but the arena will handle it
        _ = temp_str;

        // Allocate a larger block
        const temp_block = tracked_alloc.alloc(u8, 10 * 1024) catch continue;
        _ = temp_block;

        // Update peak memory - in a real app, you might use the profiler APIs for this
        const stats = memory_profiler.getMemoryStats();
        peak_memory = @max(peak_memory, stats.total_bytes);

        std.time.sleep(20 * std.time.ns_per_ms); // Pause for visualization
    }

    std.debug.print("  Created temporary allocations, peak memory: {d:.2} KB\n", .{@as(f64, @floatFromInt(peak_memory)) / 1024.0});
}

// Deliberately leak some memory to demonstrate detection
fn simulateLeakingAllocations(allocator: std.mem.Allocator) void {
    std.debug.print("\nSimulating memory leaks...\n", .{});

    // Track this section
    const zone = Profiler.beginZoneWithColor("Leaking Allocations", 0xFF0000);
    defer Profiler.endZone(zone);

    // Allocate some memory but don't free it (leak)
    _ = allocator.alloc(u64, 100) catch {
        std.debug.print("Failed to allocate memory for leak\n", .{});
        return;
    };

    // Allocate another block that we leak
    _ = allocator.alloc(u8, 2048) catch {
        std.debug.print("Failed to allocate memory for leak\n", .{});
        return;
    };

    std.debug.print("  Created 2 leaks deliberately\n", .{});
    std.time.sleep(100 * std.time.ns_per_ms); // Pause for visualization
}
