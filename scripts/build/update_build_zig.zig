const std = @import("std");

///
/// Script to add profiling tools to the main build.zig file
/// 
/// Usage:
///   zig run scripts/build/update_build_zig.zig
///

pub fn main() !void {
    // Open build.zig file for reading
    const original_content = try readFile("build.zig");
    
    // Create modified content with profiling tools
    const modified_content = try addProfilingTools(original_content);
    
    // Write the modified content back to build.zig
    try writeFile("build.zig", modified_content);
    
    std.debug.print("Successfully updated build.zig with profiling tools\n", .{});
}

fn readFile(path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    const size = try file.getEndPos();
    const allocator = std.heap.page_allocator;
    const buffer = try allocator.alloc(u8, size);
    
    const bytes_read = try file.readAll(buffer);
    if (bytes_read != size) {
        return error.IncompleteRead;
    }
    
    return buffer;
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    
    try file.writeAll(content);
}

fn addProfilingTools(original: []const u8) ![]const u8 {
    var allocator = std.heap.page_allocator;
    
    // Find position to add profiler tools
    const tools_step_marker = "// Create tools step group";
    const tools_step_pos = findStringPos(original, tools_step_marker);
    
    if (tools_step_pos == null) {
        std.debug.print("Error: Could not find tools step marker in build.zig\n", .{});
        return original;
    }
    
    // Create the additions for profiler tools
    const profiler_tools = 
        \\// Add profiler visualizer tool
        \\const profiler_visualizer = b.addExecutable(.{
        \\    .name = "profiler_visualizer",
        \\    .root_source_file = .{ .path = "tools/profiler_visualizer/visualizer.zig" },
        \\    .target = target,
        \\    .optimize = optimize,
        \\});
        \\
        \\// Add SDL dependencies
        \\profiler_visualizer.linkSystemLibrary("SDL2");
        \\profiler_visualizer.linkSystemLibrary("SDL2_ttf");
        \\
        \\// Include profiler module
        \\profiler_visualizer.addModule("tracy", b.dependency("tracy", .{
        \\    .target = target,
        \\    .optimize = optimize,
        \\}).module("tracy"));
        \\
        \\b.installArtifact(profiler_visualizer);
        \\
        \\// Add profiler launch command
        \\const run_profiler_cmd = b.addRunArtifact(profiler_visualizer);
        \\run_profiler_cmd.addArg("profile_data.csv"); // Default profile data file
        \\
        \\const run_profiler_step = b.step("profiler", "Run the profiler visualizer");
        \\run_profiler_step.dependOn(&run_profiler_cmd.step);
        \\
        \\// Add profiler to tools step
        \\tools_step.dependOn(run_profiler_step);
        \\
        \\
    ;
    
    // Insert profiler tools into the original content
    return try insertString(allocator, original, profiler_tools, tools_step_pos.? + tools_step_marker.len);
}

fn findStringPos(content: []const u8, search: []const u8) ?usize {
    return std.mem.indexOf(u8, content, search);
}

fn insertString(allocator: std.mem.Allocator, original: []const u8, insertion: []const u8, position: usize) ![]const u8 {
    if (position > original.len) {
        return error.InvalidPosition;
    }
    
    const result_len = original.len + insertion.len;
    const result = try allocator.alloc(u8, result_len);
    
    std.mem.copy(u8, result, original[0..position]);
    std.mem.copy(u8, result[position..], insertion);
    std.mem.copy(u8, result[position+insertion.len..], original[position..]);
    
    return result;
}