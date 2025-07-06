const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options for feature flags
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_vulkan", true);
    build_options.addOption(bool, "enable_directx", std.Target.current.os.tag == .windows);
    build_options.addOption(bool, "enable_metal", std.Target.current.os.tag == .macos);
    build_options.addOption(bool, "enable_opengl", true);
    build_options.addOption(bool, "enable_physics", true);
    build_options.addOption(bool, "enable_audio", true);
    build_options.addOption(bool, "enable_networking", true);
    build_options.addOption(bool, "enable_vr", false);
    build_options.addOption(bool, "enable_ai", true);
    build_options.addOption(bool, "enable_scripting", true);
    build_options.addOption(bool, "enable_profiling", optimize == .Debug);
    build_options.addOption(bool, "enable_hot_reload", optimize == .Debug);
    build_options.addOption(bool, "enable_node_editor", true);
    build_options.addOption(bool, "enable_voxels", true);
    build_options.addOption(bool, "enable_ml_mesh_conversion", true);

    // Core engine library
    const engine_lib = b.addStaticLibrary(.{
        .name = "mfs_engine",
        .root_source_file = b.path("src/engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add build options to engine
    engine_lib.root_module.addOptions("build_options", build_options);

    // Math library
    const math_lib = b.addStaticLibrary(.{
        .name = "mfs_math",
        .root_source_file = b.path("src/libs/math/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Graphics library with all backends
    const graphics_lib = b.addStaticLibrary(.{
        .name = "mfs_graphics",
        .root_source_file = b.path("src/graphics/graphics.zig"),
        .target = target,
        .optimize = optimize,
    });
    graphics_lib.root_module.addOptions("build_options", build_options);

    // Shader system with dynamic compilation
    const shaders_lib = b.addStaticLibrary(.{
        .name = "mfs_shaders",
        .root_source_file = b.path("src/shaders/dynamic_shader_compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    shaders_lib.root_module.addOptions("build_options", build_options);

    // Node-based shader editor
    const node_editor_lib = b.addStaticLibrary(.{
        .name = "mfs_node_editor",
        .root_source_file = b.path("src/shaders/node_shader_editor.zig"),
        .target = target,
        .optimize = optimize,
    });

    // GPU-accelerated GUI system
    const gui_lib = b.addStaticLibrary(.{
        .name = "mfs_gui",
        .root_source_file = b.path("src/gui/gpu_accelerated_gui.zig"),
        .target = target,
        .optimize = optimize,
    });
    gui_lib.root_module.addOptions("build_options", build_options);

    // Scene system with ECS
    const scene_lib = b.addStaticLibrary(.{
        .name = "mfs_scene",
        .root_source_file = b.path("src/scene_system/interactive_scene.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Voxel engine
    const voxel_lib = b.addStaticLibrary(.{
        .name = "mfs_voxels",
        .root_source_file = b.path("src/voxels/voxel_engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ML mesh converter
    const ml_lib = b.addStaticLibrary(.{
        .name = "mfs_ml",
        .root_source_file = b.path("src/voxels/ml_mesh_converter.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Physics engine
    const physics_lib = b.addStaticLibrary(.{
        .name = "mfs_physics",
        .root_source_file = b.path("src/physics/physics.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Audio engine
    const audio_lib = b.addStaticLibrary(.{
        .name = "mfs_audio",
        .root_source_file = b.path("src/audio/audio.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Networking
    const network_lib = b.addStaticLibrary(.{
        .name = "mfs_network",
        .root_source_file = b.path("src/network/network.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Platform abstraction
    const platform_lib = b.addStaticLibrary(.{
        .name = "mfs_platform",
        .root_source_file = b.path("src/platform.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link system libraries based on platform
    switch (target.result.os.tag) {
        .windows => {
            graphics_lib.linkSystemLibrary("user32");
            graphics_lib.linkSystemLibrary("kernel32");
            graphics_lib.linkSystemLibrary("gdi32");
            graphics_lib.linkSystemLibrary("opengl32");
            graphics_lib.linkSystemLibrary("glu32");
            graphics_lib.linkSystemLibrary("d3d11");
            graphics_lib.linkSystemLibrary("d3d12");
            graphics_lib.linkSystemLibrary("dxgi");
            graphics_lib.linkSystemLibrary("dxguid");
            platform_lib.linkSystemLibrary("user32");
            platform_lib.linkSystemLibrary("kernel32");
            audio_lib.linkSystemLibrary("winmm");
            audio_lib.linkSystemLibrary("dsound");
        },
        .linux => {
            graphics_lib.linkSystemLibrary("X11");
            graphics_lib.linkSystemLibrary("GL");
            graphics_lib.linkSystemLibrary("vulkan");
            graphics_lib.linkSystemLibrary("wayland-client");
            audio_lib.linkSystemLibrary("asound");
            audio_lib.linkSystemLibrary("pulse");
            network_lib.linkSystemLibrary("pthread");
        },
        .macos => {
            graphics_lib.linkFramework("Cocoa");
            graphics_lib.linkFramework("Metal");
            graphics_lib.linkFramework("MetalKit");
            graphics_lib.linkFramework("OpenGL");
            graphics_lib.linkFramework("QuartzCore");
            graphics_lib.linkFramework("IOKit");
            audio_lib.linkFramework("AudioToolbox");
            audio_lib.linkFramework("CoreAudio");
            platform_lib.linkFramework("Cocoa");
            platform_lib.linkFramework("Foundation");
        },
        else => {},
    }

    // Link C library for all components
    engine_lib.linkLibC();
    math_lib.linkLibC();
    graphics_lib.linkLibC();
    shaders_lib.linkLibC();
    node_editor_lib.linkLibC();
    gui_lib.linkLibC();
    scene_lib.linkLibC();
    voxel_lib.linkLibC();
    ml_lib.linkLibC();
    physics_lib.linkLibC();
    audio_lib.linkLibC();
    network_lib.linkLibC();
    platform_lib.linkLibC();

    // Install all libraries
    b.installArtifact(engine_lib);
    b.installArtifact(math_lib);
    b.installArtifact(graphics_lib);
    b.installArtifact(shaders_lib);
    b.installArtifact(node_editor_lib);
    b.installArtifact(gui_lib);
    b.installArtifact(scene_lib);
    b.installArtifact(voxel_lib);
    b.installArtifact(ml_lib);
    b.installArtifact(physics_lib);
    b.installArtifact(audio_lib);
    b.installArtifact(network_lib);
    b.installArtifact(platform_lib);

    // Main engine executable
    const engine_exe = b.addExecutable(.{
        .name = "mfs_engine",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    engine_exe.root_module.addOptions("build_options", build_options);
    engine_exe.linkLibrary(engine_lib);
    engine_exe.linkLibrary(math_lib);
    engine_exe.linkLibrary(graphics_lib);
    engine_exe.linkLibrary(shaders_lib);
    engine_exe.linkLibrary(node_editor_lib);
    engine_exe.linkLibrary(gui_lib);
    engine_exe.linkLibrary(scene_lib);
    engine_exe.linkLibrary(voxel_lib);
    engine_exe.linkLibrary(ml_lib);
    engine_exe.linkLibrary(physics_lib);
    engine_exe.linkLibrary(audio_lib);
    engine_exe.linkLibrary(network_lib);
    engine_exe.linkLibrary(platform_lib);

    b.installArtifact(engine_exe);

    // Simple spinning cube demo
    const simple_cube = b.addExecutable(.{
        .name = "simple_cube",
        .root_source_file = b.path("src/simple_spinning_cube.zig"),
        .target = target,
        .optimize = optimize,
    });

    switch (target.result.os.tag) {
        .windows => {
            simple_cube.linkSystemLibrary("user32");
            simple_cube.linkSystemLibrary("kernel32");
            simple_cube.linkSystemLibrary("gdi32");
            simple_cube.linkSystemLibrary("opengl32");
            simple_cube.linkSystemLibrary("glu32");
        },
        else => {},
    }
    simple_cube.linkLibC();
    b.installArtifact(simple_cube);

    // Advanced demo with full engine features
    const advanced_demo = b.addExecutable(.{
        .name = "advanced_demo",
        .root_source_file = b.path("src/demo_app.zig"),
        .target = target,
        .optimize = optimize,
    });

    advanced_demo.root_module.addOptions("build_options", build_options);
    advanced_demo.linkLibrary(engine_lib);
    advanced_demo.linkLibrary(math_lib);
    advanced_demo.linkLibrary(graphics_lib);
    advanced_demo.linkLibrary(shaders_lib);
    advanced_demo.linkLibrary(gui_lib);
    advanced_demo.linkLibrary(scene_lib);
    b.installArtifact(advanced_demo);

    // Voxel demo
    const voxel_demo = b.addExecutable(.{
        .name = "voxel_demo",
        .root_source_file = b.path("src/voxel_demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    voxel_demo.root_module.addOptions("build_options", build_options);
    voxel_demo.linkLibrary(voxel_lib);
    voxel_demo.linkLibrary(ml_lib);
    voxel_demo.linkLibrary(graphics_lib);
    voxel_demo.linkLibrary(math_lib);
    b.installArtifact(voxel_demo);

    // Node editor demo
    const node_editor_demo = b.addExecutable(.{
        .name = "node_editor_demo",
        .root_source_file = b.path("src/node_editor_demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    node_editor_demo.root_module.addOptions("build_options", build_options);
    node_editor_demo.linkLibrary(node_editor_lib);
    node_editor_demo.linkLibrary(shaders_lib);
    node_editor_demo.linkLibrary(gui_lib);
    node_editor_demo.linkLibrary(graphics_lib);
    node_editor_demo.linkLibrary(math_lib);
    b.installArtifact(node_editor_demo);

    // Run commands
    const run_engine = b.addRunArtifact(engine_exe);
    run_engine.step.dependOn(b.getInstallStep());
    const run_engine_step = b.step("run", "Run the main engine");
    run_engine_step.dependOn(&run_engine.step);

    const run_simple_cube = b.addRunArtifact(simple_cube);
    run_simple_cube.step.dependOn(b.getInstallStep());
    const run_simple_step = b.step("run-simple", "Run the simple spinning cube");
    run_simple_step.dependOn(&run_simple_cube.step);

    const run_advanced = b.addRunArtifact(advanced_demo);
    run_advanced.step.dependOn(b.getInstallStep());
    const run_advanced_step = b.step("run-advanced", "Run the advanced demo");
    run_advanced_step.dependOn(&run_advanced.step);

    const run_voxel = b.addRunArtifact(voxel_demo);
    run_voxel.step.dependOn(b.getInstallStep());
    const run_voxel_step = b.step("run-voxel", "Run the voxel demo");
    run_voxel_step.dependOn(&run_voxel.step);

    const run_node_editor = b.addRunArtifact(node_editor_demo);
    run_node_editor.step.dependOn(b.getInstallStep());
    const run_node_step = b.step("run-nodes", "Run the node editor demo");
    run_node_step.dependOn(&run_node_editor.step);

    // Tests
    const engine_tests = b.addTest(.{
        .root_source_file = b.path("src/engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_tests.root_module.addOptions("build_options", build_options);

    const math_tests = b.addTest(.{
        .root_source_file = b.path("src/libs/math/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const graphics_tests = b.addTest(.{
        .root_source_file = b.path("src/graphics/graphics.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shader_tests = b.addTest(.{
        .root_source_file = b.path("src/shaders/dynamic_shader_compiler.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gui_tests = b.addTest(.{
        .root_source_file = b.path("src/gui/gpu_accelerated_gui.zig"),
        .target = target,
        .optimize = optimize,
    });

    const scene_tests = b.addTest(.{
        .root_source_file = b.path("src/scene_system/interactive_scene.zig"),
        .target = target,
        .optimize = optimize,
    });

    const voxel_tests = b.addTest(.{
        .root_source_file = b.path("src/voxels/voxel_engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(engine_tests).step);
    test_step.dependOn(&b.addRunArtifact(math_tests).step);
    test_step.dependOn(&b.addRunArtifact(graphics_tests).step);
    test_step.dependOn(&b.addRunArtifact(shader_tests).step);
    test_step.dependOn(&b.addRunArtifact(gui_tests).step);
    test_step.dependOn(&b.addRunArtifact(scene_tests).step);
    test_step.dependOn(&b.addRunArtifact(voxel_tests).step);

    // Documentation generation
    const docs = b.addInstallDirectory(.{
        .source_dir = b.path("docs"),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    // Shader compilation
    const compile_shaders = b.addSystemCommand(&[_][]const u8{ "python", "tools/compile_shaders.py" });
    const shader_step = b.step("shaders", "Compile all shaders");
    shader_step.dependOn(&compile_shaders.step);

    // Asset processing
    const process_assets = b.addSystemCommand(&[_][]const u8{ "python", "tools/process_assets.py" });
    const assets_step = b.step("assets", "Process all assets");
    assets_step.dependOn(&process_assets.step);

    // Full build with all components
    const full_build_step = b.step("full", "Build everything including assets and shaders");
    full_build_step.dependOn(&shader_step.step);
    full_build_step.dependOn(&assets_step.step);
    full_build_step.dependOn(b.getInstallStep());
    full_build_step.dependOn(&test_step.step);

    // Clean build
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&[_][]const u8{ "rm", "-rf", "zig-out", "zig-cache", ".zig-cache" });
    clean_step.dependOn(&clean_cmd.step);

    // Benchmark suite
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("benchmark/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    benchmark.root_module.addOptions("build_options", build_options);
    benchmark.linkLibrary(engine_lib);
    benchmark.linkLibrary(math_lib);
    benchmark.linkLibrary(graphics_lib);
    benchmark.linkLibrary(voxel_lib);
    benchmark.linkLibrary(ml_lib);

    const run_benchmark = b.addRunArtifact(benchmark);
    const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);

    // Code coverage
    const coverage = b.addTest(.{
        .root_source_file = b.path("src/engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (optimize == .Debug) {
        coverage.setExecCmd(&[_]?[]const u8{
            "kcov",
            "--exclude-pattern=/usr,/home/.zig",
            "kcov-output",
            null,
        });
    }

    const coverage_step = b.step("coverage", "Generate code coverage report");
    coverage_step.dependOn(&b.addRunArtifact(coverage).step);

    // Memory profiling
    const memory_profile_step = b.step("profile-memory", "Profile memory usage");
    const memory_profile_cmd = b.addSystemCommand(&[_][]const u8{ "valgrind", "--tool=massif", "zig-out/bin/mfs_engine" });
    memory_profile_step.dependOn(&memory_profile_cmd.step);

    // Performance profiling
    const perf_profile_step = b.step("profile-perf", "Profile performance");
    const perf_profile_cmd = b.addSystemCommand(&[_][]const u8{ "perf", "record", "zig-out/bin/mfs_engine" });
    perf_profile_step.dependOn(&perf_profile_cmd.step);

    // Static analysis
    const static_analysis_step = b.step("analyze", "Run static analysis");
    const clang_tidy_cmd = b.addSystemCommand(&[_][]const u8{ "clang-tidy", "src/**/*.zig" });
    static_analysis_step.dependOn(&clang_tidy_cmd.step);

    // Package creation
    const package_step = b.step("package", "Create release package");
    const tar_cmd = b.addSystemCommand(&[_][]const u8{ "tar", "-czf", "mfs-engine.tar.gz", "zig-out/" });
    package_step.dependOn(b.getInstallStep());
    package_step.dependOn(&tar_cmd.step);

    // Help command
    const help_step = b.step("help", "Show available build commands");
    const help_cmd = b.addSystemCommand(&[_][]const u8{
        "echo",
        \\MFS Game Engine Build System
        \\
        \\Available commands:
        \\  zig build                    - Build all libraries and executables
        \\  zig build run                - Run the main engine
        \\  zig build run-simple         - Run simple spinning cube demo
        \\  zig build run-advanced       - Run advanced demo
        \\  zig build run-voxel          - Run voxel demo
        \\  zig build run-nodes          - Run node editor demo
        \\  zig build test               - Run all tests
        \\  zig build benchmark          - Run performance benchmarks
        \\  zig build docs               - Generate documentation
        \\  zig build shaders            - Compile all shaders
        \\  zig build assets             - Process all assets
        \\  zig build full               - Full build with assets and tests
        \\  zig build clean              - Clean build artifacts
        \\  zig build coverage           - Generate code coverage
        \\  zig build profile-memory     - Profile memory usage
        \\  zig build profile-perf       - Profile performance
        \\  zig build analyze            - Run static analysis
        \\  zig build package            - Create release package
        \\
        \\Build options:
        \\  -Doptimize=Debug|ReleaseSafe|ReleaseFast|ReleaseSmall
        \\  -Dtarget=<target>            - Cross-compilation target
        \\
        \\Examples:
        \\  zig build -Doptimize=ReleaseFast run
        \\  zig build -Dtarget=x86_64-windows test
    });
    help_step.dependOn(&help_cmd.step);
}
