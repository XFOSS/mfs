const std = @import("std");
const builtin = @import("builtin");

/// Recursively discover and register modules in a directory
pub fn discoverAndRegisterModules(b: *std.Build, exe: *std.Build.Step.Compile, dir: []const u8) !void {
    const full_path = try std.fmt.allocPrint(b.allocator, "src/{s}", .{dir});
    defer b.allocator.free(full_path);

    var src_dir = try std.fs.cwd().openDir(full_path, .{ .iterate = true });
    defer src_dir.close();

    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            // Only process .zig files
            if (std.mem.endsWith(u8, entry.name, ".zig")) {
                const module_path = try std.fs.path.join(b.allocator, &[_][]const u8{ full_path, entry.name });
                defer b.allocator.free(module_path);

                // Map module to its location
                std.log.debug("Adding module: {s}", .{module_path});

                // Register module with executable
                exe.addAnonymousModule(entry.name[0..entry.name.len-4], .{
                    .source_file = .{ .path = module_path },
                });
            }
        } else if (entry.kind == .directory) {
            // Recursively process subdirectories
            const subdir = try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ dir, entry.name });
            defer b.allocator.free(subdir);

            try discoverAndRegisterModules(b, exe, subdir);
        }
    }
}

/// Add source modules to an executable
pub fn addSourceModules(b: *std.Build, exe: *std.Build.Step.Compile) !void {
    // Core directories that should always be included
    const core_dirs = [_][]const u8{
        "app",
        "bin",
        "system",
        "graphics",
        "platform",
        "vulkan",
        "physics", 
        "math",
        "utils",
        "audio",
        "ui",
        "scene",
        "render",
    };

    for (core_dirs) |dir| {
        const full_path = try std.fmt.allocPrint(b.allocator, "src/{s}", .{dir});
        defer b.allocator.free(full_path);

        if (std.fs.cwd().access(full_path, .{})) |_| {
            try discoverAndRegisterModules(b, exe, dir);
        } else |_| {
            // Directory doesn't exist, just skip it
            std.log.debug("Skipping non-existent directory: {s}", .{full_path});
        }
    }

    // Add top-level modules
    var src_dir = try std.fs.cwd().openDir("src", .{ .iterate = true });
    defer src_dir.close();

    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const module_path = try std.fs.path.join(b.allocator, &[_][]const u8{ "src", entry.name });
            defer b.allocator.free(module_path);

            std.log.debug("Adding root module: {s}", .{module_path});

            // Skip main.zig as it's already the root
            if (!std.mem.eql(u8, entry.name, "main.zig")) {
                exe.addAnonymousModule(entry.name[0..entry.name.len-4], .{
                    .source_file = .{ .path = module_path },
                });
            }
        }
    }
}

/// Create test steps for all test modules
pub fn createTestSteps(b: *std.Build) !void {
    // Create main test step that runs all tests
    const test_step = b.step("test", "Run all tests");
    
    // Create test executable for testing the main library
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    
    // Add all source modules to the test
    try addSourceModules(b, main_tests);
    
    // Create run step for tests
    const run_main_tests = b.addRunArtifact(main_tests);
    test_step.dependOn(&run_main_tests.step);
    
    // Add specialized test categories
    try createSubsystemTestSteps(b, test_step);
    
    // Add benchmarking steps
    try createBenchmarkSteps(b);
}

/// Create subsystem-specific test steps
fn createSubsystemTestSteps(b: *std.Build, parent_step: *std.Build.Step) !void {
    const subsystems = [_][]const u8{
        "graphics",
        "platform",
        "system",
        "physics",
        "audio",
    };

    for (subsystems) |subsystem| {
        const subsys_tests = b.addTest(.{
            .root_source_file = .{ .path = b.fmt("src/{s}", .{subsystem}) },
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        });

        // Add source modules
        try addSourceModules(b, subsys_tests);

        // Create the subsystem test step
        const run_subsys_tests = b.addRunArtifact(subsys_tests);
        const subsys_step = b.step(b.fmt("test-{s}", .{subsystem}),
                                   b.fmt("Run {s} subsystem tests", .{subsystem}));
        subsys_step.dependOn(&run_subsys_tests.step);
        parent_step.dependOn(subsys_step);
    }

    // Add renderer-specific test steps
    try createRendererTestSteps(b, parent_step);
}

/// Create renderer-specific test steps
fn createRendererTestSteps(b: *std.Build, parent_step: *std.Build.Step) !void {
    const renderers = [_][]const u8{
        "vulkan",
        "opengl",
        "d3d11",
        "d3d12",
        "metal",
        "webgpu",
    };

    for (renderers) |renderer| {
        const renderer_path = b.fmt("src/graphics/backends/{s}_backend.zig", .{renderer});

        // Check if the renderer backend exists
        if (std.fs.cwd().access(renderer_path, .{})) |_| {
            const renderer_tests = b.addTest(.{
                .root_source_file = .{ .path = renderer_path },
                .target = b.standardTargetOptions(.{}),
                .optimize = b.standardOptimizeOption(.{}),
            });

            // Add source modules
            try addSourceModules(b, renderer_tests);

            // Create the renderer test step
            const run_renderer_tests = b.addRunArtifact(renderer_tests);
            const renderer_step = b.step(b.fmt("test-{s}", .{renderer}),
                                        b.fmt("Run {s} renderer tests", .{renderer}));
            renderer_step.dependOn(&run_renderer_tests.step);

            // Also add specialized test files from tests directory if they exist
            const test_file_path = b.fmt("src/tests/test_{s}.zig", .{renderer});
            if (std.fs.cwd().access(test_file_path, .{})) |_| {
                const specific_test = b.addTest(.{
                    .root_source_file = .{ .path = test_file_path },
                    .target = b.standardTargetOptions(.{}),
                    .optimize = b.standardOptimizeOption(.{}),
                });

                try addSourceModules(b, specific_test);
                const run_specific_test = b.addRunArtifact(specific_test);
                renderer_step.dependOn(&run_specific_test.step);
            } else |_| {}

            // Register the renderer step with the parent test step
            parent_step.dependOn(renderer_step);
        } else |_| {}
    }
}

/// Create benchmark steps for performance testing
fn createBenchmarkSteps(b: *std.Build) !void {
    // Create main benchmark step
    const bench_step = b.step("bench", "Run performance benchmarks");
    
    // Add generic benchmarks if file exists
    const bench_path = "src/tests/benchmarks.zig";
    if (std.fs.cwd().access(bench_path, .{})) |_| {
        const bench_exe = b.addExecutable(.{
            .name = "engine_benchmarks",
            .root_source_file = .{ .path = bench_path },
            .target = b.standardTargetOptions(.{}),
            .optimize = .ReleaseFast, // Always use max optimization for benchmarks
        });
        
        try addSourceModules(b, bench_exe);
        const run_bench = b.addRunArtifact(bench_exe);
        bench_step.dependOn(&run_bench.step);
    } else |_| {
        // If benchmark file doesn't exist yet, log it
        std.log.debug("No benchmarks.zig file found at {s}", .{bench_path});
    }
    
    // Add renderer benchmarks
    try createRendererBenchmarks(b, bench_step);
    
    // Add physics benchmarks if they exist
    const physics_bench_path = "src/tests/physics_bench.zig";
    if (std.fs.cwd().access(physics_bench_path, .{})) |_| {
        const physics_bench = b.addExecutable(.{
            .name = "physics_benchmarks",
            .root_source_file = .{ .path = physics_bench_path },
            .target = b.standardTargetOptions(.{}),
            .optimize = .ReleaseFast,
        });
        
        try addSourceModules(b, physics_bench);
        const run_physics_bench = b.addRunArtifact(physics_bench);
        const physics_bench_step = b.step("bench-physics", "Run physics benchmarks");
        physics_bench_step.dependOn(&run_physics_bench.step);
        bench_step.dependOn(physics_bench_step);
    } else |_| {
        // Physics benchmarks not found - that's OK
    }
}

/// Create renderer-specific benchmarks
fn createRendererBenchmarks(b: *std.Build, parent_step: *std.Build.Step) !void {
    const renderers = [_][]const u8{
        "vulkan",
        "opengl",
        "d3d11",
        "d3d12",
        "metal",
        "webgpu",
        "software",  // Add software renderer for completeness
    };

    for (renderers) |renderer| {
        const renderer_bench_path = b.fmt("src/tests/bench_{s}.zig", .{renderer});
        
        if (std.fs.cwd().access(renderer_bench_path, .{})) |_| {
            const renderer_bench = b.addExecutable(.{
                .name = b.fmt("{s}_benchmarks", .{renderer}),
                .root_source_file = .{ .path = renderer_bench_path },
                .target = b.standardTargetOptions(.{}),
                .optimize = .ReleaseFast,
            });
            
            try addSourceModules(b, renderer_bench);
            const run_renderer_bench = b.addRunArtifact(renderer_bench);
            const renderer_bench_step = b.step(b.fmt("bench-{s}", .{renderer}), 
                                             b.fmt("Run {s} renderer benchmarks", .{renderer}));
            renderer_bench_step.dependOn(&run_renderer_bench.step);
            parent_step.dependOn(renderer_bench_step);
        } else |_| {
            // This renderer's benchmarks don't exist yet - that's OK
        }
    }
}

/// Detect if Vulkan SDK is available on the system
pub fn detectVulkanSDK(is_windows: bool) bool {
    const env_var = if (is_windows) "VULKAN_SDK" else "VULKAN_SDK";
    
    if (std.process.getEnvVarOwned(std.heap.page_allocator, env_var)) |sdk_path| {
        defer std.heap.page_allocator.free(sdk_path);
        return true;
    } else |_| {
        return false;
    }
}

/// Detect if DirectX 12 is available on the system
pub fn detectDirectX12() bool {
    // DirectX 12 requires Windows 10 or newer
    if (builtin.os.tag == .windows) {
        return true;
    }
    return false;
}

/// Detect if DirectX 11 is available on the system
pub fn detectDirectX11() bool {
    // DirectX 11 is available on Windows 7 and newer
    if (builtin.os.tag == .windows) {
        return true;
    }
    return false;
}