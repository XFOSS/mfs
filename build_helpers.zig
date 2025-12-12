// build_helpers.zig
//! Build helpers for the MFS engine
//! This module provides utility functions for the build system
//! @thread-safe Build system utilities
//! @symbol BuildHelpers

const std = @import("std");
const builtin = @import("builtin");

/// Detect if Vulkan SDK is available
pub fn detectVulkanSDK(is_windows: bool) bool {
    if (is_windows) {
        // Check for Vulkan SDK on Windows
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "VULKAN_SDK")) |vulkan_path| {
            std.heap.page_allocator.free(vulkan_path);
            return true;
        } else |_| {
            return false;
        }
    } else {
        // Check for Vulkan on Unix systems
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "pkg-config", "--exists", "vulkan" },
        }) catch return false;

        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);

        return result.term.Exited == 0;
    }
}

/// Detect if DirectX 11 is available (Windows only)
pub fn detectDirectX11() bool {
    if (builtin.os.tag != .windows) return false;

    // Check for DirectX SDK or Windows SDK
    const dx_paths = [_][]const u8{
        "C:\\Program Files (x86)\\Microsoft DirectX SDK (June 2010)\\",
        "C:\\Program Files\\Microsoft DirectX SDK (June 2010)\\",
        "C:\\Program Files (x86)\\Windows Kits\\10\\",
        "C:\\Program Files\\Windows Kits\\10\\",
    };

    for (dx_paths) |path| {
        std.fs.cwd().access(path, .{}) catch continue;
        return true;
    }

    return false;
}

/// Detect if DirectX 12 is available (Windows only)
pub fn detectDirectX12() bool {
    if (builtin.os.tag != .windows) return false;

    // DirectX 12 is available on Windows 10 and later
    // For now, assume it's available if we can find Windows 10 SDK
    const dx12_paths = [_][]const u8{
        "C:\\Program Files (x86)\\Windows Kits\\10\\",
        "C:\\Program Files\\Windows Kits\\10\\",
    };

    for (dx12_paths) |path| {
        std.fs.cwd().access(path, .{}) catch continue;
        return true;
    }

    return false;
}

/// Add source modules to a compile step
pub fn addSourceModules(b: *std.Build, exe: *std.Build.Step.Compile) !void {
    // Add include paths for C/C++ interop
    exe.addIncludePath(b.path("src"));
    exe.addIncludePath(b.path("src/graphics"));
    exe.addIncludePath(b.path("src/platform"));

    // Add system include paths if needed
    if (builtin.os.tag == .windows) {
        // Add Windows SDK includes if available
        if (std.process.getEnvVarOwned(b.allocator, "WindowsSdkDir")) |sdk_dir| {
            defer b.allocator.free(sdk_dir);
            const include_path = try std.fs.path.join(b.allocator, &[_][]const u8{ sdk_dir, "Include" });
            defer b.allocator.free(include_path);
            exe.addIncludePath(.{ .cwd_relative = include_path });
        } else |_| {}
    }
}

/// Create build options for feature detection
pub fn createBuildOptions(b: *std.Build, target: std.Build.ResolvedTarget) !*std.Build.Step.Options {
    const opts = b.addOptions();

    // Platform detection
    opts.addOption(bool, "is_windows", target.result.os.tag == .windows);
    opts.addOption(bool, "is_linux", target.result.os.tag == .linux);
    opts.addOption(bool, "is_macos", target.result.os.tag == .macos);
    opts.addOption(bool, "is_mobile", target.result.os.tag == .ios);
    opts.addOption(bool, "is_web", target.result.os.tag == .emscripten or target.result.os.tag == .wasi);

    // Graphics API availability
    opts.addOption(bool, "vulkan_available", detectVulkanSDK(target.result.os.tag == .windows));
    opts.addOption(bool, "d3d11_available", target.result.os.tag == .windows and detectDirectX11());
    opts.addOption(bool, "d3d12_available", target.result.os.tag == .windows and detectDirectX12());
    opts.addOption(bool, "metal_available", target.result.os.tag == .macos or target.result.os.tag == .ios);
    opts.addOption(bool, "opengl_available", target.result.os.tag != .ios);
    opts.addOption(bool, "opengles_available", target.result.os.tag == .ios or target.result.os.tag == .emscripten);
    opts.addOption(bool, "webgpu_available", target.result.os.tag == .emscripten or target.result.os.tag == .wasi);

    // Feature flags
    opts.addOption(bool, "enable_tracy", false); // Profiling
    opts.addOption(bool, "enable_debug_graphics", true);
    opts.addOption(bool, "enable_hot_reload", true);
    opts.addOption(bool, "enable_memory_tracking", true);

    // Performance options
    opts.addOption(u32, "max_entities", 100000);
    opts.addOption(u32, "max_components", 64);
    opts.addOption(u32, "memory_budget_mb", 512);

    return opts;
}

/// Get Vulkan dependency if available
pub fn getVulkanDependency(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !?*std.Build.Dependency {
    if (!detectVulkanSDK(target.result.os.tag == .windows)) {
        return null;
    }

    // Try to get vulkan-zig dependency
    return b.dependency("vulkan-zig", .{
        .target = target,
        .optimize = optimize,
    }) catch |err| switch (err) {
        error.DependencyNotFound => {
            std.log.warn("vulkan-zig dependency not found, Vulkan support will be limited", .{});
            return null;
        },
        else => return err,
    };
}

/// Setup common compiler flags
pub fn setupCompilerFlags(exe: *std.Build.Step.Compile, optimize: std.builtin.OptimizeMode) void {
    // Common flags
    exe.want_lto = optimize != .Debug;
    exe.strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;
    exe.single_threaded = false;

    // Platform-specific flags
    switch (exe.root_module.resolved_target.result.os.tag) {
        .windows => {
            exe.subsystem = .Windows;
        },
        .linux => {
            exe.pie = true;
        },
        .macos => {
            exe.dead_strip_dylibs = true;
        },
        else => {},
    }
}

/// Check if a file exists
pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Check if a directory exists
pub fn dirExists(path: []const u8) bool {
    const dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}
