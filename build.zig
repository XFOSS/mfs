const std = @import("std");
const builtin = @import("builtin");
const build_helpers = @import("build_helpers.zig");

// External dependencies
const zmath = @import("zmath");
const zigimg = @import("zigimg");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Get the dependencies
    const zmath_dep = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Optional dependencies
    const vulkan_zig_dep = if (build_helpers.detectVulkanSDK(target.result.os.tag == .windows)) 
        b.dependency("vulkan_zig", .{
            .target = target,
            .optimize = optimize,
        }) 
    else 
        null;
    
    // GLFW dependency (if not web platform)
    const mach_glfw_dep = if (target.result.os.tag != .wasi and target.result.os.tag != .emscripten)
        b.dependency("mach_glfw", .{
            .target = target,
            .optimize = optimize,
        })
    else
        null;

    // Build options for feature toggles
    const opts = b.addOptions();
    opts.addOption(bool, "vulkan_available", build_helpers.detectVulkanSDK(target.result.os.tag == .windows));
    opts.addOption(bool, "d3d11_available", build_helpers.detectDirectX11() and target.result.os.tag == .windows);
    opts.addOption(bool, "d3d12_available", build_helpers.detectDirectX12() and target.result.os.tag == .windows);
    opts.addOption(bool, "metal_available", target.result.os.tag == .macos);
    opts.addOption(bool, "opengl_available", true); // OpenGL widely supported
    opts.addOption(bool, "opengles_available", target.result.os.tag == .linux or target.result.os.tag == .android);
    opts.addOption(bool, "webgpu_available", target.result.os.tag == .wasi or target.result.os.tag == .emscripten);
    opts.addOption(bool, "enable_tracy", b.option(bool, "tracy", "Enable Tracy profiler") orelse false);
    opts.addOption(bool, "enable_hot_reload", b.option(bool, "hot-reload", "Enable hot reloading") orelse (optimize == .Debug));
    opts.addOption([]const u8, "target_os", @tagName(target.result.os.tag));
    opts.addOption(bool, "is_mobile", target.result.os.tag == .ios or target.result.os.tag == .android);
    opts.addOption(bool, "is_desktop", target.result.os.tag == .windows or target.result.os.tag == .macos or target.result.os.tag == .linux);

    // ---- Main Engine Executable ----
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
    
    // Add external dependencies
    exe.root_module.addImport("zmath", zmath_dep.module("zmath"));
    exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
    
    // Add conditional dependencies
    if (vulkan_zig_dep) |vulkan_dep| {
        exe.root_module.addImport("vulkan_zig", vulkan_dep.module("vulkan-zig"));
    }
    
    if (mach_glfw_dep) |glfw_dep| {
        exe.root_module.addImport("mach_glfw", glfw_dep.module("mach-glfw"));
    }
    
    // Try to load zgui if present
    if (b.dependency("zgui", .{ .target = target, .optimize = optimize })) |zgui_dep| {
        exe.root_module.addImport("zgui", zgui_dep.module("zgui"));
    } catch |err| {
        std.log.info("zgui not loaded: {s}", .{@errorName(err)});
    }

    // Add platform-specific dependencies
    addPlatformDependencies(exe, target.result.os.tag);

    // Install shaders and assets
    installShadersAndAssets(b, exe);

    // Install the executable
    b.installArtifact(exe);

    // Create run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Add as default "run" step
    const run_step = b.step("run", "Run the MFS engine");
    run_step.dependOn(&run_cmd.step);

    // ---- Example Applications ----

    // Simple Spinning Cube
    const simple_cube = b.addExecutable(.{
        .name = "simple_cube",
        .root_source_file = .{ .path = "src/examples/simple_spinning_cube.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    // Add dependencies for example apps
    if (mach_glfw_dep) |glfw_dep| {
        simple_cube.root_module.addImport("mach_glfw", glfw_dep.module("mach-glfw"));
    }
    
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
    spinning_cube.root_module.addImport("zmath", zmath_dep.module("zmath"));
    
    if (mach_glfw_dep) |glfw_dep| {
        spinning_cube.root_module.addImport("mach_glfw", glfw_dep.module("mach-glfw"));
    }
    
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
    enhanced_renderer.root_module.addImport("zmath", zmath_dep.module("zmath"));
    enhanced_renderer.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
    
    if (vulkan_zig_dep) |vulkan_dep| {
        enhanced_renderer.root_module.addImport("vulkan_zig", vulkan_dep.module("vulkan-zig"));
    }
    
    if (mach_glfw_dep) |glfw_dep| {
        enhanced_renderer.root_module.addImport("mach_glfw", glfw_dep.module("mach-glfw"));
    }
    
    addPlatformDependencies(enhanced_renderer, target.result.os.tag);
    b.installArtifact(enhanced_renderer);

    const run_enhanced_cmd = b.addRunArtifact(enhanced_renderer);
    run_enhanced_cmd.step.dependOn(b.getInstallStep());
    const run_enhanced_step = b.step("run-enhanced", "Run the enhanced renderer demo");
    run_enhanced_step.dependOn(&run_enhanced_cmd.step);

    // Tutorial Applications
    const tutorial_01 = b.addExecutable(.{
        .name = "tutorial_01",
        .root_source_file = .{ .path = "examples/tutorials/01_getting_started.zig" },
        .target = target,
        .optimize = optimize,
    });
    try build_helpers.addSourceModules(b, tutorial_01);
    tutorial_01.root_module.addOptions("build_options", opts);
    tutorial_01.root_module.addImport("zmath", zmath_dep.module("zmath"));
    
    if (mach_glfw_dep) |glfw_dep| {
        tutorial_01.root_module.addImport("mach_glfw", glfw_dep.module("mach-glfw"));
    }
    
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

    // Web Demo (conditionally built)
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
        web_demo.root_module.addImport("zmath", zmath_dep.module("zmath"));
        web_demo.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
        
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

    // ---- Tests ----
    try build_helpers.createTestSteps(b);
    
    // Create tutorial step group
    const tutorial_step = b.step("tutorials", "Build all tutorial examples");
    tutorial_step.dependOn(&run_tutorial_01_step.step);
    tutorial_step.dependOn(&run_memory_profiling_step.step);

    // Create tools step group
    const tools_step = b.step("tools", "Build all tools");
    tools_step.dependOn(b.getInstallStep());
    tools_step.dependOn(b.getStepForName("assets") orelse b.getInstallStep());
    
    // Add benchmarking step
    const bench_exe = b.addExecutable(.{
        .name = "benchmarks",
        .root_source_file = .{ .path = "src/tests/benchmarks.zig" },
        .target = target,
        .optimize = .ReleaseFast, // Always optimize benchmarks
    });
    
    try build_helpers.addSourceModules(b, bench_exe);
    bench_exe.root_module.addImport("zmath", zmath_dep.module("zmath"));
    bench_exe.root_module.addOptions("build_options", opts);
    
    b.installArtifact(bench_exe);
    
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench.step);
    
    // Add asset processor tool
    const asset_processor = b.addExecutable(.{
        .name = "asset_processor",
        .root_source_file = .{ .path = "tools/asset_processor/asset_processor.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    asset_processor.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
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
    
    const tools_step = b.step("tools", "Build all tools");
    tools_step.dependOn(&b.addInstallArtifact(profiler_visualizer).step);
    tools_step.dependOn(&b.addInstallArtifact(asset_processor).step);
}

/// Install shader files and assets to the right location
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
fn addPlatformDependencies(exe: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    // Link C library for all platforms
    exe.linkLibC();

    // Add platform-specific libraries
    switch (os_tag) {
        .windows => {
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
        },
        .linux => {
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("X11");
            exe.linkSystemLibrary("m");
        },
        .macos => {
            exe.linkFramework("Cocoa");
            exe.linkFramework("OpenGL");
            exe.linkFramework("Metal");
            exe.linkFramework("MetalKit");
            exe.linkFramework("QuartzCore"); // For CAMetalLayer
        },
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
