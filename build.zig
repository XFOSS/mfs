const std = @import("std");
const builtin = @import("builtin");
const build_helpers = @import("build_helpers.zig");

/// Main build function
/// @thread-safe This function initializes and coordinates the entire build process
/// @symbol This is the main entry point for the build system
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional dependencies
    const vulkan_zig_dep = try getVulkanDependency(b, target, optimize);

    // Build options for feature toggles
    const opts = createBuildOptions(b, target);
    // Build options are now created in the createBuildOptions function

    // ---- Main Engine Executable ----
    const exe = try createMainExecutable(b, target, optimize, opts, vulkan_zig_dep);

    // Create run command
    const run_step = try createRunStep(b, exe, "run", "Run the MFS engine");

    // ---- Example Applications ----
    try buildExamplesAndDemos(b, target, optimize, opts, vulkan_zig_dep);

    // ---- Tutorial Applications ----
    const run_tutorial_steps = try buildTutorials(b, target, optimize, opts);

    // Web Demo (conditionally built)
    try buildWebDemoIfTargeted(b, target, optimize, opts);

    // ---- Tests ----
    try build_helpers.createTestSteps(b);

    // Create tutorial step group
    const tutorial_step = b.step("tutorials", "Build all tutorial examples");
    try connectTutorialSteps(tutorial_step, run_tutorial_steps);

    // Create tools step group
    const tools_step = b.step("tools", "Build all tools");
    tools_step.dependOn(b.getInstallStep());
    tools_step.dependOn(b.getStepForName("assets") orelse b.getInstallStep());

    // Add benchmarking step
    const bench_step = try createBenchmarkStep(b, target, optimize, opts);

    // Add tools - asset processor and profiler visualizer
    try buildAndRegisterTools(b, target, optimize, tools_step);
}

/// Get Vulkan dependency if available
/// @thread-safe Thread-safe dependency resolution
fn getVulkanDependency(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !?*std.Build.Dependency {
    return if (build_helpers.detectVulkanSDK(target.result.os.tag == .windows))
        b.dependency("vulkan_zig", .{
            .target = target,
            .optimize = optimize,
        })
    else
        null;
}

/// Create build options for feature toggles
/// @symbol This function defines build-time feature flags
fn createBuildOptions(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Step.Options {
    const opts = b.addOptions();

    // Graphics backends availability
    opts.addOption(bool, "vulkan_available", build_helpers.detectVulkanSDK(target.result.os.tag == .windows));
    opts.addOption(bool, "d3d11_available", build_helpers.detectDirectX11() and target.result.os.tag == .windows);
    opts.addOption(bool, "d3d12_available", build_helpers.detectDirectX12() and target.result.os.tag == .windows);
    opts.addOption(bool, "metal_available", target.result.os.tag == .macos);
    opts.addOption(bool, "opengl_available", true); // OpenGL widely supported
    opts.addOption(bool, "opengles_available", target.result.os.tag == .linux or target.result.os.tag == .android);
    opts.addOption(bool, "webgpu_available", target.result.os.tag == .wasi or target.result.os.tag == .emscripten);

    // Development features
    opts.addOption(bool, "enable_tracy", b.option(bool, "tracy", "Enable Tracy profiler") orelse false);
    opts.addOption(bool, "enable_hot_reload", b.option(bool, "hot-reload", "Enable hot reloading") orelse (b.standardOptimizeOption(.{}) == .Debug));

    // Platform detection
    opts.addOption([]const u8, "target_os", @tagName(target.result.os.tag));
    opts.addOption(bool, "is_mobile", target.result.os.tag == .ios or target.result.os.tag == .android);
    opts.addOption(bool, "is_desktop", target.result.os.tag == .windows or target.result.os.tag == .macos or target.result.os.tag == .linux);

    return opts;
}

/// Create the main executable
/// @thread-safe Thread-safe executable creation
fn createMainExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
    vulkan_zig_dep: ?*std.Build.Dependency,
) !*std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "mfs",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add build options
    exe.root_module.addOptions("build_options", opts);

    // Register all source modules
    try build_helpers.addSourceModules(b, exe);

    // Add conditional dependencies
    if (vulkan_zig_dep) |vulkan_dep| {
        exe.root_module.addImport("vulkan_zig", vulkan_dep.module("vulkan-zig"));
    }

    // Add platform-specific dependencies
    addPlatformDependencies(exe, target.result.os.tag);

    // Install shaders and assets
    installShadersAndAssets(b, exe);

    // Install the executable
    b.installArtifact(exe);

    return exe;
}

/// Create a run step for an executable
/// @thread-safe Thread-safe run step creation
fn createRunStep(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    step_name: []const u8,
    step_description: []const u8,
) !*std.Build.Step {
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(step_name, step_description);
    run_step.dependOn(&run_cmd.step);

    return run_step;
}

/// Build all examples and demos
/// @symbol Builds example applications demonstrating engine features
fn buildExamplesAndDemos(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
    vulkan_zig_dep: ?*std.Build.Dependency,
) !void {
    // Simple Spinning Cube
    const simple_cube = b.addExecutable(.{
        .name = "simple_cube",
        .root_source_file = .{ .path = "src/examples/simple_spinning_cube.zig" },
        .target = target,
        .optimize = optimize,
    });

    addPlatformDependencies(simple_cube, target.result.os.tag);
    b.installArtifact(simple_cube);

    const run_cube_cmd = b.addRunArtifact(simple_cube);
    run_cube_cmd.step.dependOn(b.getInstallStep());
    const run_cube_step = b.step("run-cube", "Run the simple spinning cube demo");
    run_cube_step.dependOn(&run_cube_cmd.step);

    // Advanced Spinning Cube
    const spinning_cube = b.addExecutable(.{
        .name = "spinning_cube_app",
        .root_source_file = .{ .path = "src/examples/spinning_cube_app.zig" },
        .target = target,
        .optimize = optimize,
    });

    try build_helpers.addSourceModules(b, spinning_cube);

    // Add dependencies
    spinning_cube.root_module.addOptions("build_options", opts);

    addPlatformDependencies(spinning_cube, target.result.os.tag);
    b.installArtifact(spinning_cube);

    const run_advanced_cube_cmd = b.addRunArtifact(spinning_cube);
    run_advanced_cube_cmd.step.dependOn(b.getInstallStep());
    const run_advanced_cube_step = b.step("run-advanced-cube", "Run the advanced spinning cube demo");
    run_advanced_cube_step.dependOn(&run_advanced_cube_cmd.step);

    // Enhanced Renderer Demo
    const enhanced_renderer = b.addExecutable(.{
        .name = "enhanced_renderer",
        .root_source_file = .{ .path = "src/examples/simple_main.zig" },
        .target = target,
        .optimize = optimize,
    });

    try build_helpers.addSourceModules(b, enhanced_renderer);

    // Add dependencies
    enhanced_renderer.root_module.addOptions("build_options", opts);

    if (vulkan_zig_dep) |vulkan_dep| {
        enhanced_renderer.root_module.addImport("vulkan_zig", vulkan_dep.module("vulkan-zig"));
    }

    addPlatformDependencies(enhanced_renderer, target.result.os.tag);
    b.installArtifact(enhanced_renderer);

    const run_enhanced_cmd = b.addRunArtifact(enhanced_renderer);
    run_enhanced_cmd.step.dependOn(b.getInstallStep());
    const run_enhanced_step = b.step("run-enhanced", "Run the enhanced renderer demo");
    run_enhanced_step.dependOn(&run_enhanced_cmd.step);
}

/// Build all tutorial applications
/// @symbol Builds tutorial applications for learning the engine
fn buildTutorials(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
) !struct { *std.Build.Step, *std.Build.Step } {
    // Tutorial 01
    const tutorial_01 = b.addExecutable(.{
        .name = "tutorial_01",
        .root_source_file = .{ .path = "examples/tutorials/01_getting_started.zig" },
        .target = target,
        .optimize = optimize,
    });
    try build_helpers.addSourceModules(b, tutorial_01);
    tutorial_01.root_module.addOptions("build_options", opts);

    addPlatformDependencies(tutorial_01, target.result.os.tag);
    b.installArtifact(tutorial_01);

    const run_tutorial_01_cmd = b.addRunArtifact(tutorial_01);
    run_tutorial_01_cmd.step.dependOn(b.getInstallStep());
    const run_tutorial_01_step = b.step("run-tutorial-01", "Run the first tutorial");
    run_tutorial_01_step.dependOn(&run_tutorial_01_cmd.step);

    // Memory Profiling Tutorial
    const memory_profiling = b.addExecutable(.{
        .name = "memory_profiling",
        .root_source_file = .{ .path = "examples/tutorials/memory_profiling_example.zig" },
        .target = target,
        .optimize = optimize,
    });
    try build_helpers.addSourceModules(b, memory_profiling);
    memory_profiling.root_module.addOptions("build_options", opts);
    addPlatformDependencies(memory_profiling, target.result.os.tag);
    b.installArtifact(memory_profiling);

    const run_memory_profiling_cmd = b.addRunArtifact(memory_profiling);
    run_memory_profiling_cmd.step.dependOn(b.getInstallStep());
    const run_memory_profiling_step = b.step("run-memory-profiling", "Run the memory profiling tutorial");
    run_memory_profiling_step.dependOn(&run_memory_profiling_cmd.step);

    return .{ run_tutorial_01_step, run_memory_profiling_step };
}

/// Connect tutorial steps to the main tutorial step
/// @thread-safe Thread-safe step connection
fn connectTutorialSteps(
    tutorial_step: *std.Build.Step,
    run_tutorial_steps: struct { *std.Build.Step, *std.Build.Step },
) !void {
    tutorial_step.dependOn(&run_tutorial_steps[0].step);
    tutorial_step.dependOn(&run_tutorial_steps[1].step);
}

/// Build web demo if target is web platform
/// @symbol Conditionally builds web demo for WebAssembly targets
fn buildWebDemoIfTargeted(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
) !void {
    if (target.result.os.tag == .wasi or target.result.os.tag == .emscripten) {
        const web_demo = b.addExecutable(.{
            .name = "web_demo",
            .root_source_file = .{ .path = "src/examples/web/web_main.zig" },
            .target = target,
            .optimize = optimize,
        });

        try build_helpers.addSourceModules(b, web_demo);

        // Add dependencies
        web_demo.root_module.addOptions("build_options", opts);

        b.installArtifact(web_demo);

        // Additional web-specific build steps
        const wasm_step = b.step("web", "Build WebAssembly demo");
        wasm_step.dependOn(&b.addInstallArtifact(web_demo).step);

        // Copy web assets (JavaScript glue, HTML, etc.)
        const copy_web_files = b.addInstallDirectory(.{
            .source_dir = .{ .path = "web" },
            .install_dir = .prefix,
            .install_subdir = "",
        });
        wasm_step.dependOn(&copy_web_files.step);
    }
}

/// Create benchmark step for performance testing
/// @thread-safe Thread-safe benchmark step creation
fn createBenchmarkStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
) !*std.Build.Step {
    const bench_exe = b.addExecutable(.{
        .name = "benchmarks",
        .root_source_file = .{ .path = "src/tests/benchmarks.zig" },
        .target = target,
        .optimize = .ReleaseFast, // Always optimize benchmarks
    });

    try build_helpers.addSourceModules(b, bench_exe);
    bench_exe.root_module.addOptions("build_options", opts);

    b.installArtifact(bench_exe);

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench.step);

    return bench_step;
}

/// Build and register all tools
/// @symbol Builds asset processor, profiler visualizer and other tools
fn buildAndRegisterTools(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tools_step: *std.Build.Step,
) !void {
    // Add asset processor tool
    const asset_processor = b.addExecutable(.{
        .name = "asset_processor",
        .root_source_file = .{ .path = "tools/asset_processor/asset_processor.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(asset_processor);

    // Create asset processing step
    const process_assets_cmd = b.addRunArtifact(asset_processor);
    process_assets_cmd.addArgs(&[_][]const u8{
        "assets",
        "zig-out/assets",
        "--verbose",
    });

    const process_assets_step = b.step("assets", "Process game assets");
    process_assets_step.dependOn(&process_assets_cmd.step);

    // Build profiler visualizer
    const profiler_visualizer = b.addExecutable(.{
        .name = "profiler_visualizer",
        .root_source_file = .{ .path = "tools/profiler_visualizer/visualizer.zig" },
        .target = target,
        .optimize = optimize,
    });
    try build_helpers.addSourceModules(b, profiler_visualizer);
    addPlatformDependencies(profiler_visualizer, target.result.os.tag);
    profiler_visualizer.linkSystemLibrary("raylib");
    b.installArtifact(profiler_visualizer);

    // Add tool artifacts to the tools step (using the already defined tools_step)
    tools_step.dependOn(&b.addInstallArtifact(profiler_visualizer).step);
    tools_step.dependOn(&b.addInstallArtifact(asset_processor).step);
}

/// Install shader files and assets to the right location
/// @thread-safe Thread-safe asset installation
/// @symbol Installs shaders and assets for the application
fn installShadersAndAssets(b: *std.Build, exe: *std.Build.Step.Compile) void {
    // Install shader files
    const shader_dir = b.addInstallDirectory(.{
        .source_dir = .{ .path = "shaders" },
        .install_dir = .bin,
        .install_subdir = "shaders",
    });
    exe.step.dependOn(&shader_dir.step);

    // Install assets if they exist
    const assets_path = "assets";
    if (std.fs.cwd().access(assets_path, .{})) |_| {
        const assets_dir = b.addInstallDirectory(.{
            .source_dir = .{ .path = assets_path },
            .install_dir = .bin,
            .install_subdir = "assets",
        });
        exe.step.dependOn(&assets_dir.step);

        // Make processed assets depend on raw assets
        const processed_assets_dir = b.addInstallDirectory(.{
            .source_dir = .{ .path = "zig-out/assets" },
            .install_dir = .bin,
            .install_subdir = "processed_assets",
        });
        processed_assets_dir.step.dependOn(b.getStepForName("assets") orelse &assets_dir.step);
        exe.step.dependOn(&processed_assets_dir.step);
    } else |_| {
        std.log.debug("No assets directory found at {s}", .{assets_path});
    }

    // Install tutorial shaders if they exist
    const tutorial_shaders_path = "examples/tutorials/shaders";
    if (std.fs.cwd().access(tutorial_shaders_path, .{})) |_| {
        const tutorial_shaders_dir = b.addInstallDirectory(.{
            .source_dir = .{ .path = tutorial_shaders_path },
            .install_dir = .bin,
            .install_subdir = "shaders/tutorials",
        });
        exe.step.dependOn(&tutorial_shaders_dir.step);
    } else |_| {
        std.log.debug("No tutorial shaders directory found at {s}", .{tutorial_shaders_path});
    }
}

/// Add platform-specific dependencies
/// @thread-safe Thread-safe dependency addition
/// @symbol Links appropriate platform-specific libraries
fn addPlatformDependencies(exe: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    // Link C library for all platforms
    exe.linkLibC();

    // Add platform-specific libraries
    switch (os_tag) {
        .windows => addWindowsDependencies(exe),
        .linux => addLinuxDependencies(exe),
        .macos => addMacosDependencies(exe),
        .android => addAndroidDependencies(exe),
        .ios => addIosDependencies(exe),
        .wasi, .emscripten => addWebDependencies(exe),
        else => {}, // Other platforms
    }

    // Add Vulkan if available
    if (build_helpers.detectVulkanSDK(os_tag == .windows)) {
        exe.linkSystemLibrary("vulkan");

        // Windows needs additional Vulkan libraries
        if (os_tag == .windows) {
            exe.linkSystemLibrary("vulkan-1");
        }
    }
}

/// Add Windows-specific dependencies
/// @symbol Links Windows-specific libraries
fn addWindowsDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("kernel32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("shell32");
    exe.linkSystemLibrary("opengl32");
    exe.linkSystemLibrary("glu32");
    exe.linkSystemLibrary("winmm");
    exe.linkSystemLibrary("ole32");
    exe.linkSystemLibrary("uuid");
    exe.linkSystemLibrary("xinput");
    exe.linkSystemLibrary("dwmapi");

    // Add DirectX libraries conditionally
    if (build_helpers.detectDirectX11()) {
        exe.linkSystemLibrary("d3d11");
        exe.linkSystemLibrary("dxgi");
        exe.linkSystemLibrary("dxguid");
    }
    if (build_helpers.detectDirectX12()) {
        exe.linkSystemLibrary("d3d12");
        exe.linkSystemLibrary("dxguid");
        exe.linkSystemLibrary("dxgi");
    }
}

/// Add Linux-specific dependencies
/// @symbol Links Linux-specific libraries
fn addLinuxDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkSystemLibrary("GL");
    exe.linkSystemLibrary("X11");
    exe.linkSystemLibrary("m");

    // Optional Linux dependencies
    addOptionalLibrary(exe, "Xi"); // X11 Input Extension
    addOptionalLibrary(exe, "Xcursor"); // Cursor handling
    addOptionalLibrary(exe, "Xrandr"); // Screen resolution/multiple displays
    addOptionalLibrary(exe, "Xinerama"); // Multi-monitor support
    addOptionalLibrary(exe, "wayland-client"); // Wayland support
    addOptionalLibrary(exe, "wayland-egl"); // Wayland EGL support
    addOptionalLibrary(exe, "wayland-cursor"); // Wayland cursor
}

/// Add macOS-specific dependencies
/// @symbol Links macOS-specific frameworks
fn addMacosDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkFramework("Cocoa");
    exe.linkFramework("OpenGL");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");
    exe.linkFramework("QuartzCore"); // For CAMetalLayer
    exe.linkFramework("CoreFoundation");
    exe.linkFramework("CoreGraphics");
    exe.linkFramework("Foundation");
    exe.linkFramework("AppKit");
    exe.linkFramework("IOKit"); // For controller support and power management
}

/// Add Android-specific dependencies
/// @symbol Links Android-specific libraries
fn addAndroidDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkSystemLibrary("android");
    exe.linkSystemLibrary("EGL");
    exe.linkSystemLibrary("GLESv3");
    exe.linkSystemLibrary("log"); // Android logging
    exe.linkSystemLibrary("native_app_glue");
}

/// Add iOS-specific dependencies
/// @symbol Links iOS-specific frameworks
fn addIosDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkFramework("UIKit");
    exe.linkFramework("Foundation");
    exe.linkFramework("CoreGraphics");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("OpenGLES");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");
}

/// Add Web-specific dependencies
/// @symbol Links web platform libraries (WebAssembly)
fn addWebDependencies(exe: *std.Build.Step.Compile) void {
    // Web platform typically doesn't need explicit libraries
    // as they're included in the emscripten/wasi toolchain
}

/// Helper to add optional libraries that might not be available on all systems
/// @thread-safe Thread-safe optional library addition
fn addOptionalLibrary(exe: *std.Build.Step.Compile, name: []const u8) void {
    exe.linkSystemLibrary(name) catch {};
}
