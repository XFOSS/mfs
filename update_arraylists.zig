const std = @import("std");

// Script to update all std.ArrayList usages to std.ArrayList for Zig 0.15 compatibility
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Discovering files with std.ArrayList usage...", .{});

    // Automatically discover all .zig files containing std.ArrayList
    var files_to_update = std.ArrayList([]const u8).init(allocator);
    defer {
        for (files_to_update.items) |path| {
            allocator.free(path);
        }
        files_to_update.deinit();
    }

    try discoverFiles("src", &files_to_update, allocator);
    try discoverFiles("scripts", &files_to_update, allocator);
    try discoverFiles("tools", &files_to_update, allocator);

    std.log.info("Found {} files to update", .{files_to_update.items.len});

    var updated_count: usize = 0;
    var skipped_count: usize = 0;

    for (files_to_update.items) |file_path| {
        std.log.info("Updating {s}", .{file_path});
        const result = try updateFile(file_path, allocator);
        if (result) {
            updated_count += 1;
        } else {
            skipped_count += 1;
            std.log.warn("  Skipped (no changes needed)", .{});
        }
    }

    std.log.info("ArrayList update script completed!", .{});
    std.log.info("  Updated: {} files", .{updated_count});
    std.log.info("  Skipped: {} files", .{skipped_count});
}

fn discoverFiles(dir_path: []const u8, files: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        // Directory might not exist, that's okay
        if (err == error.FileNotFound) return;
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            const subdir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer allocator.free(subdir_path);
            try discoverFiles(subdir_path, files, allocator);
        } else if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.name, ".zig")) {
                const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });

                // Check if file contains std.ArrayList
                const full_path = try std.fs.path.join(allocator, &.{ ".", file_path });
                defer allocator.free(full_path);

                const file = std.fs.cwd().openFile(full_path, .{}) catch continue;
                defer file.close();

                const stat = file.stat() catch continue;
                const content = file.reader().readAllAlloc(allocator, stat.size + 1) catch continue;
                defer allocator.free(content);

                if (std.mem.indexOf(u8, content, "std.ArrayList") != null) {
                    try files.append(file_path);
                } else {
                    allocator.free(file_path);
                }
            }
        }
    }
}

fn updateFile(file_path: []const u8, allocator: std.mem.Allocator) !bool {
    const file = std.fs.cwd().openFile(file_path, .{ .read = true }) catch |err| {
        std.log.warn("  Could not open {s}: {}", .{ file_path, err });
        return false;
    };
    defer file.close();

    const stat = try file.stat();
    const content = try file.reader().readAllAlloc(allocator, stat.size + 1);
    defer allocator.free(content);

    // Check if file actually contains std.ArrayList (not just in comments)
    if (std.mem.indexOf(u8, content, "std.ArrayList") == null) {
        return false;
    }

    // Replace std.ArrayList with std.ArrayList
    const updated_content = try std.mem.replaceOwned(u8, allocator, content, "std.ArrayList", "std.ArrayList");
    defer allocator.free(updated_content);

    // Only update if content actually changed
    if (std.mem.eql(u8, content, updated_content)) {
        return false;
    }

    // Write back the updated content
    const out_file = try std.fs.cwd().createFile(file_path, .{});
    defer out_file.close();

    try out_file.writeAll(updated_content);
    return true;
}
