const std = @import("std");
const builtin = @import("builtin");

const build_helpers = @import("build_helpers.zig");
const build_simple_cube = @import("build_simple_cube.zig");
const build_spinning_cube = @import("build_spinning_cube.zig");
const build_game_engine = @import("build_game_engine.zig");

/// Common configuration for creating executables
const ExecutableConfig = struct {
    name: []const u8,
    root_source_file: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dependencies: ?*std.Build.Dependency = null,
    opts: ?*std.Build.Step.Options = null,
};

/// Common configuration for creating run steps
const RunStepConfig = struct {
    name: []const u8,
    description: []const u8,
    exe: *std.Build.Step.Compile,
    install_step: ?*std.Build.Step = null,
};

/// Create an executable with common configuration
fn createExecutable(b: *std.Build, config: ExecutableConfig) !*std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = config.name,
        .root_source_file = .{ .path = config.root_source_file },
        .target = config.target,
        .optimize = config.optimize,
    });

    // Add common dependencies
    try build_helpers.addSourceModules(b, exe);
    if (config.opts) |opts| {
        exe.root_module.addOptions("build_options", opts);
    }
    if (config.dependencies) |dep| {
        exe.root_module.addImport("vulkan_zig", dep.module("vulkan-zig"));
    }

    // Add platform-specific dependencies
    addPlatformDependencies(exe, config.target.result.os.tag);

    // Install the executable
    b.installArtifact(exe);

    // Add shader compilation step
    const shader_compiler = b.addSystemCommand(&.{
        "glslc",
        "-o",
        "shaders/triangle.vert.spv",
        "shaders/triangle.vert",
    });
    shader_compiler.step.dependOn(&b.addSystemCommand(&.{
        "glslc",
        "-o",
        "shaders/triangle.frag.spv",
        "shaders/triangle.frag",
    }).step);

    // Make the shader compilation step a dependency of the main executable
    exe.step.dependOn(&shader_compiler.step);

    return exe;
}

/// Create a run step with common configuration
fn createRunStep(b: *std.Build, config: RunStepConfig) !*std.Build.Step {
    const run_cmd = b.addRunArtifact(config.exe);
    run_cmd.step.dependOn(config.install_step orelse b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(config.name, config.description);
    run_step.dependOn(&run_cmd.step);

    return run_step;
}

/// Main build function that coordinates the entire build process
/// This is the entry point for the Zig build system
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mfs",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add math module
    lib.addModule("math", b.createModule(.{
        .source_file = .{ .path = "src/math/math.zig" },
    }));

    // Add scene module
    lib.addModule("scene", b.createModule(.{
        .source_file = .{ .path = "src/scene/scene.zig" },
        .dependencies = &.{
            .{ .name = "math", .module = lib.modules.get("math").? },
        },
    }));

    // Add render module
    lib.addModule("render", b.createModule(.{
        .source_file = .{ .path = "src/render/render.zig" },
        .dependencies = &.{
            .{ .name = "math", .module = lib.modules.get("math").? },
            .{ .name = "scene", .module = lib.modules.get("scene").? },
        },
    }));

    // Add audio module
    lib.addModule("audio", b.createModule(.{
        .source_file = .{ .path = "src/audio/audio.zig" },
        .dependencies = &.{
            .{ .name = "math", .module = lib.modules.get("math").? },
            .{ .name = "scene", .module = lib.modules.get("scene").? },
        },
    }));

    // Add input module
    lib.addModule("input", b.createModule(.{
        .source_file = .{ .path = "src/input/input.zig" },
        .dependencies = &.{
            .{ .name = "math", .module = lib.modules.get("math").? },
        },
    }));

    // Add window module
    lib.addModule("window", b.createModule(.{
        .source_file = .{ .path = "src/window/window.zig" },
        .dependencies = &.{
            .{ .name = "math", .module = lib.modules.get("math").? },
            .{ .name = "input", .module = lib.modules.get("input").? },
        },
    }));

    // Add engine module
    lib.addModule("engine", b.createModule(.{
        .source_file = .{ .path = "src/engine/engine.zig" },
        .dependencies = &.{
            .{ .name = "math", .module = lib.modules.get("math").? },
            .{ .name = "scene", .module = lib.modules.get("scene").? },
            .{ .name = "render", .module = lib.modules.get("render").? },
            .{ .name = "audio", .module = lib.modules.get("audio").? },
            .{ .name = "input", .module = lib.modules.get("input").? },
            .{ .name = "window", .module = lib.modules.get("window").? },
        },
    }));

    // Add executable
    const exe = b.addExecutable(.{
        .name = "mfs",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(lib);
    b.installArtifact(exe);

    // Add run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Add test command
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
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

/// Create build options for feature toggles and platform detection
fn createBuildOptions(b: *std.Build, target: std.Build.ResolvedTarget) !*std.Build.Step.Options {
    const opts = b.addOptions();

    // Graphics backends
    const graphics_opts = .{
        .vulkan_available = build_helpers.detectVulkanSDK(target.result.os.tag == .windows),
        .d3d11_available = build_helpers.detectDirectX11() and target.result.os.tag == .windows,
        .d3d12_available = build_helpers.detectDirectX12() and target.result.os.tag == .windows,
        .metal_available = target.result.os.tag == .macos,
        .opengl_available = true,
        .opengles_available = target.result.os.tag == .linux or target.result.os.tag == .android,
        .webgpu_available = target.result.os.tag == .wasi or target.result.os.tag == .emscripten,
    };

    // Development features
    const dev_opts = .{
        .enable_tracy = b.option(bool, "tracy", "Enable Tracy profiler") orelse false,
        .enable_hot_reload = b.option(bool, "hot-reload", "Enable hot reloading") orelse
            (b.standardOptimizeOption(.{}) == .Debug),
        .enable_debug_utils = b.option(bool, "debug-utils", "Enable debug utilities") orelse
            (b.standardOptimizeOption(.{}) == .Debug),
    };

    // Platform detection
    const platform_opts = .{
        .target_os = @tagName(target.result.os.tag),
        .is_mobile = target.result.os.tag == .ios or target.result.os.tag == .android,
        .is_desktop = target.result.os.tag == .windows or target.result.os.tag == .macos or
            target.result.os.tag == .linux,
        .is_web = target.result.os.tag == .wasi or target.result.os.tag == .emscripten,
    };

    // Add all options
    inline for (std.meta.fields(@TypeOf(graphics_opts))) |field| {
        opts.addOption(bool, field.name, @field(graphics_opts, field.name));
    }
    inline for (std.meta.fields(@TypeOf(dev_opts))) |field| {
        opts.addOption(bool, field.name, @field(dev_opts, field.name));
    }
    inline for (std.meta.fields(@TypeOf(platform_opts))) |field| {
        opts.addOption(@TypeOf(@field(platform_opts, field.name)), field.name, @field(platform_opts, field.name));
    }

    return opts;
}

/// Build all examples and demos using the common executable creation pattern
fn buildExamplesAndDemos(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
    vulkan_zig_dep: ?*std.Build.Dependency,
) !void {
    // Simple Spinning Cube
    const simple_cube = try createExecutable(b, .{
        .name = "simple_cube",
        .root_source_file = "src/examples/simple_spinning_cube.zig",
        .target = target,
        .optimize = optimize,
    });

    _ = try createRunStep(b, .{
        .name = "run-cube",
        .description = "Run the simple spinning cube demo",
        .exe = simple_cube,
    });

    // Advanced Spinning Cube
    const spinning_cube = try createExecutable(b, .{
        .name = "spinning_cube_app",
        .root_source_file = "src/examples/spinning_cube_app.zig",
        .target = target,
        .optimize = optimize,
        .opts = opts,
    });

    _ = try createRunStep(b, .{
        .name = "run-advanced-cube",
        .description = "Run the advanced spinning cube demo",
        .exe = spinning_cube,
    });

    // Enhanced Renderer Demo
    const enhanced_renderer = try createExecutable(b, .{
        .name = "enhanced_renderer",
        .root_source_file = "src/examples/simple_main.zig",
        .target = target,
        .optimize = optimize,
        .dependencies = vulkan_zig_dep,
        .opts = opts,
    });

    _ = try createRunStep(b, .{
        .name = "run-enhanced",
        .description = "Run the enhanced renderer demo",
        .exe = enhanced_renderer,
    });
}

/// Build all tutorial applications using the common executable creation pattern
fn buildTutorials(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
) !struct { *std.Build.Step, *std.Build.Step } {
    // Tutorial 01
    const tutorial_01 = try createExecutable(b, .{
        .name = "tutorial_01",
        .root_source_file = "examples/tutorials/01_getting_started.zig",
        .target = target,
        .optimize = optimize,
        .opts = opts,
    });

    const run_tutorial_01_step = try createRunStep(b, .{
        .name = "run-tutorial-01",
        .description = "Run the first tutorial",
        .exe = tutorial_01,
    });

    // Memory Profiling Tutorial
    const memory_profiling = try createExecutable(b, .{
        .name = "memory_profiling",
        .root_source_file = "examples/tutorials/memory_profiling_example.zig",
        .target = target,
        .optimize = optimize,
        .opts = opts,
    });

    const run_memory_profiling_step = try createRunStep(b, .{
        .name = "run-memory-profiling",
        .description = "Run the memory profiling tutorial",
        .exe = memory_profiling,
    });

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
/// @symbol Builds WebAssembly-compatible web demos
/// @thread-safe Ensures safe conditional builds for web targets
fn buildWebDemoIfTargeted(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: *std.Build.Step.Options,
) !void {
    if (target.result.os.tag == .wasi or target.result.os.tag == .emscripten) {
        const web_demo = try createExecutable(b, .{
            .name = "web_demo",
            .root_source_file = "src/examples/web/web_main.zig",
            .target = target,
            .optimize = optimize,
            .opts = opts,
        });

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
    _: std.builtin.OptimizeMode,
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
/// @symbol Registers tools like asset processors and profilers
/// @thread-safe Ensures safe tool registration and builds
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
/// @symbol Handles shader and asset installation for applications
/// @thread-safe Ensures safe installation of assets
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

/// Add platform-specific dependencies with improved organization
fn addPlatformDependencies(exe: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    // Common dependencies
    exe.linkLibC();

    // Platform-specific dependencies
    const platform_deps = struct {
        fn add(compile_step: *std.Build.Step.Compile, target_os: std.Target.Os.Tag) void {
            switch (target_os) {
                .windows => addWindowsDependencies(compile_step),
                .linux => addLinuxDependencies(compile_step),
                .macos => addMacosDependencies(compile_step),
                .android => addAndroidDependencies(compile_step),
                .ios => addIosDependencies(compile_step),
                .wasi, .emscripten => addWebDependencies(compile_step),
                else => {},
            }
        }
    };
    platform_deps.add(exe, os_tag);

    // Graphics API dependencies
    if (build_helpers.detectVulkanSDK(os_tag == .windows)) {
        exe.linkSystemLibrary("vulkan");
        if (os_tag == .windows) {
            exe.linkSystemLibrary("vulkan-1");
        }
    }
}

/// Add Windows-specific dependencies
/// @symbol Handles linking of Windows libraries
/// @thread-safe Ensures safe addition of Windows dependencies
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
/// @symbol Handles linking of Linux libraries
/// @thread-safe Ensures safe addition of Linux dependencies
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
/// @symbol Handles linking of macOS frameworks
/// @thread-safe Ensures safe addition of macOS dependencies
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
/// @symbol Handles linking of Android libraries
/// @thread-safe Ensures safe addition of Android dependencies
fn addAndroidDependencies(exe: *std.Build.Step.Compile) void {
    exe.linkSystemLibrary("android");
    exe.linkSystemLibrary("EGL");
    exe.linkSystemLibrary("GLESv3");
    exe.linkSystemLibrary("log"); // Android logging
    exe.linkSystemLibrary("native_app_glue");
}

/// Add iOS-specific dependencies
/// @symbol Handles linking of iOS frameworks
/// @thread-safe Ensures safe addition of iOS dependencies
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
/// @symbol Handles linking of WebAssembly libraries
/// @thread-safe Ensures safe addition of web dependencies
fn addWebDependencies(_: *std.Build.Step.Compile) void {
    // Web platform typically doesn't need explicit libraries
    // as they're included in the emscripten/wasi toolchain
}

/// Helper to add optional libraries that might not be available on all systems
/// @thread-safe Thread-safe optional library addition
fn addOptionalLibrary(exe: *std.Build.Step.Compile, name: []const u8) void {
    exe.linkSystemLibrary(name) catch {};
}
