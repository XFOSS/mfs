const std = @import("std");

// Script to update ArrayList.deinit(allocator) calls to ArrayList.deinit() for Zig 0.16 compatibility
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // List of files to update based on current grep results
    const files_to_update = [_][]const u8{
        "src/xr.zig",
        "src/window/mod.zig",
        "src/voxels/ml_mesh_converter.zig",
        "src/tools/visual_editor.zig",
        "src/system/memory/memory_manager.zig",
        "src/shaders/shader_compiler.zig",
        "src/scene/systems/physics_system.zig",
        "src/scene/systems/audio_system.zig",
        "src/scene/core/scene.zig",
        "src/scene/spatial/octree.zig",
        "src/scene/core/entity.zig",
        "src/scene/components/script.zig",
        "src/resource_manager.zig",
        "src/platform/platform.zig",
        "src/physics/spatial_partition.zig",
        "src/neural/brain.zig",
        "src/libs/utils/error_utils.zig",
        "src/graphics/temporal_techniques.zig",
        "src/graphics/shader_manager.zig",
        "src/graphics/multi_threading.zig",
        "src/graphics/lod_system.zig",
        "src/graphics/backends/common/profiling.zig",
        "src/core/events.zig",
        "src/core/config.zig",
        "src/audio/audio.zig",
        "src/graphics/backends/vulkan/old/ray_tracing.zig",
        "src/graphics/asset_pipeline.zig",
        "scripts/run_tests.zig",
        "tools/asset_processor/asset_processor.zig",
    };

    for (files_to_update) |file_path| {
        std.log.info("Updating {s}", .{file_path});
        try updateFile(file_path, allocator);
    }

    std.log.info("ArrayList deinit update script completed!", .{});
    std.log.info("Updated {} files for Zig 0.16 compatibility", .{files_to_update.len});
}

fn updateFile(file_path: []const u8, allocator: std.mem.Allocator) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const stat = try file.stat();
    const content = try file.reader().readAllAlloc(allocator, stat.size + 1);
    defer allocator.free(content);

    // Replace various deinit patterns with allocator parameters
    var updated_content = try std.mem.replaceOwned(u8, allocator, content, ".deinit(self.allocator)", ".deinit()");
    updated_content = try std.mem.replaceOwned(u8, allocator, updated_content, ".deinit(self.child_allocator)", ".deinit()");
    updated_content = try std.mem.replaceOwned(u8, allocator, updated_content, ".deinit(allocator)", ".deinit()");

    // Handle more complex patterns
    updated_content = try std.mem.replaceOwned(u8, allocator, updated_content, ".deinit(self.audio_allocator)", ".deinit()");
    updated_content = try std.mem.replaceOwned(u8, allocator, updated_content, ".deinit(self.pool_allocator)", ".deinit()");
    updated_content = try std.mem.replaceOwned(u8, allocator, updated_content, ".deinit(self.temp_allocator)", ".deinit()");

    // Handle patterns with brackets/array access
    updated_content = try std.mem.replaceOwned(u8, allocator, updated_content, ".deinit(allocator)", ".deinit()");

    // Only write if content changed
    if (!std.mem.eql(u8, content, updated_content)) {
        const out_file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
        defer out_file.close();
        try out_file.writeAll(updated_content);
        std.log.info("  Updated deinit calls", .{});
    } else {
        std.log.info("  No changes needed", .{});
    }
}
