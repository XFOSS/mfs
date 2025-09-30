const std = @import("std");

// Script to update all std.ArrayList usages to std.array_list.Managed for Zig 0.15 compatibility
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // List of files to update (from our grep results)
    const files_to_update = [_][]const u8{
        "src/graphics/resource_manager.zig",
        "src/graphics/backends/common/resource_management.zig",
        "src/system/profiling/profiler.zig",
        "src/graphics/buffer.zig",
        "src/graphics/buffer_fixed.zig",
        "src/core/object_pool.zig",
        "src/engine/ecs.zig",
        "scripts/test_all_backends.zig",
        "src/app/plugin_loader.zig",
        "scripts/run_tests.zig",
        // Add more files as needed...
    };

    for (files_to_update) |file_path| {
        std.log.info("Updating {s}", .{file_path});
        try updateFile(file_path, allocator);
    }

    std.log.info("ArrayList update script completed!", .{});
}

fn updateFile(file_path: []const u8, allocator: std.mem.Allocator) !void {
    const file = try std.fs.cwd().openFile(file_path, .{ .read = true });
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024 * 10); // 10MB max

    // Replace std.ArrayList with std.array_list.Managed
    var updated_content = try std.mem.replaceOwned(u8, allocator, content, "std.ArrayList", "std.array_list.Managed");

    // Write back the updated content
    const out_file = try std.fs.cwd().createFile(file_path, .{});
    defer out_file.close();

    try out_file.writeAll(updated_content);
}