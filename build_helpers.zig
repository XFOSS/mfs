// build_helpers.zig
const std = @import("std");

/// Adds common dependencies to the build
fn addCommonDependencies(b: *std.build.Builder) void {
    _ = b.dependency("vulkan", .{
        .path = std.build.FilePath.init("external/vulkan-sdk"),
    });
}

/// Sets up build options for the project
fn setupBuildOptions(b: *std.build.Builder) void {
    b.addOptions("build_options", .{
        .enable_debug = true,
        .target = "x86_64-linux",
    });
}

/// Adds platform-specific dependencies
fn addPlatformDependencies(b: *std.build.Builder) void {
    if (b.target.isWindows()) {
        _ = b.dependency("windows", .{
            .path = std.build.FilePath.init("external/windows-sdk"),
        });
    } else if (b.target.isLinux()) {
        _ = b.dependency("linux", .{
            .path = std.build.FilePath.init("external/linux-sdk"),
        });
    }
}
