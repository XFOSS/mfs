const std = @import("std");
const builtin = @import("builtin");

const MainFile = struct {
    name: []const u8,
    path: []const u8,
    category: []const u8,
    should_run: bool = false, // Most files shouldn't be run, just compiled
};

const main_files = [_]MainFile{
    // Main entry points
    .{ .name = "main", .path = "src/main.zig", .category = "main" },
    .{ .name = "bin/main", .path = "src/bin/main.zig", .category = "main" },
    .{ .name = "main_loop", .path = "src/main_loop.zig", .category = "main" },

    // Tests
    .{ .name = "physics_test", .path = "src/tests/physics_test.zig", .category = "test" },
    .{ .name = "benchmarks", .path = "src/tests/benchmarks.zig", .category = "test" },
    .{ .name = "vulkan_working_test", .path = "src/tests/vulkan_working_test.zig", .category = "test" },
    .{ .name = "test_vulkan", .path = "src/tests/test_vulkan.zig", .category = "test" },
    .{ .name = "test_opengl", .path = "src/tests/test_opengl.zig", .category = "test" },
    .{ .name = "render_bench", .path = "src/tests/benchmarks/render_bench.zig", .category = "test" },

    // Scripts
    .{ .name = "run_tests", .path = "scripts/run_tests.zig", .category = "script" },
    .{ .name = "markdown_to_html", .path = "scripts/markdown_to_html.zig", .category = "script" },
    .{ .name = "test_all_backends", .path = "scripts/test_all_backends.zig", .category = "script" },
    .{ .name = "verify_build", .path = "scripts/verify_build.zig", .category = "script" },
    .{ .name = "code_quality_check", .path = "scripts/code_quality_check.zig", .category = "script" },
    .{ .name = "refactor_math", .path = "scripts/refactor_math.zig", .category = "script" },
    .{ .name = "update_build_zig", .path = "scripts/build/update_build_zig.zig", .category = "script" },

    // Tools
    .{ .name = "profiler_visualizer", .path = "tools/profiler_visualizer/visualizer.zig", .category = "tool" },
    .{ .name = "asset_processor", .path = "tools/asset_processor/asset_processor.zig", .category = "tool" },
    .{ .name = "capability_checker", .path = "src/tools/capability_checker.zig", .category = "tool" },
    .{ .name = "texture_converter", .path = "tools/texture_converter.zig", .category = "tool" },
    .{ .name = "model_viewer", .path = "tools/model_viewer.zig", .category = "tool" },

    // Demos/Apps
    .{ .name = "spinning_cube_wasm", .path = "src/demos/spinning_cube_wasm.zig", .category = "demo" },
    .{ .name = "demo_app", .path = "src/app/demo_app.zig", .category = "demo" },
    .{ .name = "opengl_cube", .path = "src/render/opengl_cube.zig", .category = "demo" },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Testing all Zig files with main functions...\n", .{});

    var total: usize = 0;
    var passed: usize = 0;
    var failed: usize = 0;

    var failed_files = std.array_list.Managed([]const u8).init(allocator);
    defer failed_files.deinit();

    // Group by category
    const categories = [_][]const u8{ "main", "test", "script", "tool", "demo" };

    for (categories) |category| {
        std.log.info("=== {s} ===", .{category});

        for (main_files) |file| {
            if (!std.mem.eql(u8, file.category, category)) continue;

            total += 1;
            std.debug.print("Testing {s} ({s})... ", .{ file.name, file.path });

            // Try to compile the file
            const result = try compileFile(allocator, file.path);

            if (result.success) {
                passed += 1;
                std.debug.print("✓ PASSED\n", .{});
            } else {
                failed += 1;
                const error_msg = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ file.path, result.error_message });
                try failed_files.append(error_msg);
                std.debug.print("✗ FAILED\n", .{});
                std.log.err("  Error: {s}", .{result.error_message});
            }
        }
        std.debug.print("\n", .{});
    }

    // Summary
    std.log.info("\n=== Summary ===", .{});
    std.log.info("Total: {d}", .{total});
    std.log.info("Passed: {d}", .{passed});
    std.log.info("Failed: {d}", .{failed});

    if (failed_files.items.len > 0) {
        std.log.err("\n=== Failed Files ===", .{});
        for (failed_files.items) |error_msg| {
            std.log.err("  {s}", .{error_msg});
        }
    }

    if (failed > 0) {
        std.process.exit(1);
    }
}

const CompileResult = struct {
    success: bool,
    error_message: []const u8,
};

fn compileFile(allocator: std.mem.Allocator, file_path: []const u8) !CompileResult {
    // Use zig build-exe to test compilation
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const zig_exe = try findZigExe(arena_allocator);

    var args = std.array_list.Managed([]const u8).init(arena_allocator);
    try args.append(zig_exe);
    try args.append("build-exe");
    try args.append(file_path);
    try args.append("--name");
    try args.append("test_exe");
    try args.append("--cache-dir");
    try args.append(".zig-cache/test");

    // Add common build options
    try args.append("-target");
    try args.append("native");
    try args.append("-O");
    try args.append("Debug");

    var process = std.process.Child.init(args.items, arena_allocator);
    process.stderr_behavior = .Inherit;
    process.stdout_behavior = .Inherit;

    try process.spawn();

    const result = try process.wait();

    if (result.Exited != 0) {
        const error_msg = try std.fmt.allocPrint(allocator, "Compilation failed with exit code {d}", .{result.Exited});
        return CompileResult{
            .success = false,
            .error_message = error_msg,
        };
    }

    return CompileResult{
        .success = true,
        .error_message = "",
    };
}

fn findZigExe(allocator: std.mem.Allocator) ![]const u8 {
    // Try to find zig in PATH
    const env_path = std.process.getEnvVarOwned(allocator, if (builtin.os.tag == .windows) "Path" else "PATH") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return "zig";
        }
        return err;
    };
    defer allocator.free(env_path);

    // For simplicity, just return "zig" and let the system find it
    return "zig";
}
