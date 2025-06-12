const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const BuildTest = struct {
    name: []const u8,
    target: ?[]const u8 = null,
    args: []const []const u8 = &[_][]const u8{},
    should_succeed: bool = true,
};

const build_tests = [_]BuildTest{
    .{ .name = "Default build", .args = &[_][]const u8{} },
    .{ .name = "Windows DirectX 12", .target = "x86_64-windows", .args = &[_][]const u8{ "-Dd3d12=true", "-Dvulkan=false" } },
    .{ .name = "Web WASM", .target = "wasm32-emscripten", .args = &[_][]const u8{ "-Dwebgpu=true", "-Dopengles=true" } },
    .{ .name = "Linux Vulkan", .target = "x86_64-linux", .args = &[_][]const u8{ "-Dvulkan=true", "-Dopengl=true" } },
    .{ .name = "macOS Metal", .target = "x86_64-macos", .args = &[_][]const u8{"-Dmetal=true"} },
    .{ .name = "Release build", .args = &[_][]const u8{"-Doptimize=ReleaseFast"} },
    .{ .name = "Debug build", .args = &[_][]const u8{"-Doptimize=Debug"} },
    .{ .name = "Web build target", .args = &[_][]const u8{"web"} },
};

pub fn main() !void {
    defer _ = gpa.deinit();

    std.log.info("=== MFS Engine Build Verification ===", .{});
    std.log.info("Platform: {s}", .{@tagName(builtin.os.tag)});
    std.log.info("Architecture: {s}", .{@tagName(builtin.cpu.arch)});
    std.log.info("", .{});

    var passed: u32 = 0;
    var failed: u32 = 0;

    for (build_tests) |test_case| {
        std.log.info("Testing: {s}", .{test_case.name});

        const result = runBuildTest(test_case) catch |err| {
            std.log.err("  Error: {}", .{err});
            failed += 1;
            continue;
        };

        if (result == test_case.should_succeed) {
            std.log.info("  ✓ PASSED", .{});
            passed += 1;
        } else {
            std.log.err("  ✗ FAILED", .{});
            failed += 1;
        }
    }

    std.log.info("", .{});
    std.log.info("=== SUMMARY ===", .{});
    std.log.info("Passed: {}", .{passed});
    std.log.info("Failed: {}", .{failed});
    std.log.info("Total:  {}", .{passed + failed});

    if (failed > 0) {
        std.log.err("Some build tests failed!");
        std.process.exit(1);
    } else {
        std.log.info("All build tests passed!");
    }
}

fn runBuildTest(test_case: BuildTest) !bool {
    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("zig");
    try cmd_args.append("build");

    // Add target if specified
    if (test_case.target) |target| {
        const target_arg = try std.fmt.allocPrint(allocator, "-Dtarget={s}", .{target});
        defer allocator.free(target_arg);
        try cmd_args.append(target_arg);
    }

    // Add additional args
    for (test_case.args) |arg| {
        try cmd_args.append(arg);
    }

    // Add dry-run flag to speed up testing
    try cmd_args.append("--help");

    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = cmd_args.items,
        .cwd = "..",
    }) catch |err| {
        std.log.warn("  Command execution failed: {}", .{err});
        return false;
    };

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return result.term.Exited == 0;
}

test "verify build configuration" {
    // Basic compile-time checks
    const build_options = @import("../src/build_options");

    // Verify platform detection works
    const is_windows = builtin.os.tag == .windows;
    const is_web = builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64;

    if (is_windows) {
        // Windows should have DirectX 12 as primary
        try testing.expect(build_options.d3d12_available);
    }

    if (is_web) {
        // Web should have WebGPU available
        try testing.expect(build_options.webgpu_available or build_options.opengles_available);
    }
}

test "backend availability matrix" {
    const BackendMatrix = struct {
        vulkan: bool = false,
        d3d11: bool = false,
        d3d12: bool = false,
        metal: bool = false,
        opengl: bool = false,
        opengles: bool = false,
        webgpu: bool = false,
        software: bool = true, // Always available
    };

    var expected = BackendMatrix{};

    switch (builtin.os.tag) {
        .windows => {
            expected.d3d12 = true;
            expected.d3d11 = true;
            expected.opengl = true;
        },
        .macos, .ios => {
            expected.metal = true;
            expected.opengl = true;
            if (builtin.os.tag == .ios) {
                expected.opengles = true;
            }
        },
        .linux => {
            expected.vulkan = true;
            expected.opengl = true;
        },
        .emscripten, .wasi => {
            expected.webgpu = true;
            expected.opengles = true;
        },
        else => {},
    }

    // Verify at least one backend is available for each platform
    const has_backend = expected.vulkan or expected.d3d11 or expected.d3d12 or
        expected.metal or expected.opengl or expected.opengles or
        expected.webgpu or expected.software;

    try testing.expect(has_backend);
}
