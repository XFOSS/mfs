const std = @import("std");
const builtin = @import("builtin");

// Configuration structure for better organization
const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    enable_vulkan: bool,
    enable_d3d11: bool,
    enable_d3d12: bool,
    enable_metal: bool,
    enable_opengl: bool,
    enable_opengles: bool,
    enable_webgpu: bool,
    enable_tracy: bool,
    enable_hot_reload: bool,
    enable_debug_layers: bool,
    enable_validation: bool,
    enable_profiling: bool,
    enable_logging: bool,
    log_level: []const u8,

    // Platform flags
    target_os: std.Target.Os.Tag,
    target_arch: std.builtin.Cpu.Arch,
    is_windows: bool,
    is_macos: bool,
    is_ios: bool,
    is_linux: bool,
    is_android: bool,
    is_wasm: bool,
    is_mobile: bool,
    is_desktop: bool,
    is_web: bool,

    // Backend availability
    vulkan_available: bool,
    d3d11_available: bool,
    d3d12_available: bool,
    metal_available: bool,
    opengl_available: bool,
    opengles_available: bool,
    webgpu_available: bool,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Enhanced build options for feature toggles
    const enable_vulkan = b.option(bool, "vulkan", "Enable Vulkan backend") orelse true;
    const enable_d3d11 = b.option(bool, "d3d11", "Enable DirectX 11 backend") orelse true;
    const enable_d3d12 = b.option(bool, "d3d12", "Enable DirectX 12 backend") orelse true;
    const enable_metal = b.option(bool, "metal", "Enable Metal backend") orelse true;
    const enable_opengl = b.option(bool, "opengl", "Enable OpenGL backend") orelse true;
    const enable_opengles = b.option(bool, "opengles", "Enable OpenGL ES backend") orelse true;
    const enable_webgpu = b.option(bool, "webgpu", "Enable WebGPU backend") orelse false;
    const enable_tracy = b.option(bool, "tracy", "Enable Tracy profiling") orelse false;
    const enable_hot_reload = b.option(bool, "hot_reload", "Enable hot reload") orelse (optimize == .Debug);
    const enable_debug_layers = b.option(bool, "debug_layers", "Enable graphics API debug layers") orelse (optimize == .Debug);
    const enable_validation = b.option(bool, "validation", "Enable runtime validation") orelse (optimize == .Debug);
    const enable_profiling = b.option(bool, "profiling", "Enable built-in profiling") orelse false;
    const enable_logging = b.option(bool, "logging", "Enable logging system") orelse true;
    const log_level = b.option([]const u8, "log_level", "Set log level (trace, debug, info, warn, error)") orelse "info";

    // Platform detection
    const target_os = target.result.os.tag;
    const target_arch = target.result.cpu.arch;
    const is_windows = target_os == .windows;
    const is_macos = target_os == .macos;
    const is_ios = target_os == .ios;
    const is_linux = target_os == .linux;
    const is_android = target.result.os.tag == .linux and std.mem.indexOf(u8, @tagName(target.result.abi), "android") != null;
    const is_wasm = target_os == .emscripten or target_os == .wasi or target_arch == .wasm32 or target_arch == .wasm64;
    const is_mobile = is_ios or is_android;
    const is_desktop = is_windows or is_macos or (is_linux and !is_android);
    const is_web = is_wasm;

    // Graphics backend availability detection
    var vulkan_available = false;
    var d3d11_available = false;
    var d3d12_available = false;
    var metal_available = false;
    var opengl_available = false;
    var opengles_available = false;
    var webgpu_available = false;

    // Platform-specific backend availability with improved detection
    if (is_windows) {
        d3d12_available = enable_d3d12 and detectDirectX12();
        d3d11_available = enable_d3d11 and detectDirectX11();
        opengl_available = enable_opengl;
        vulkan_available = enable_vulkan and detectVulkanSDK(b);
    } else if (is_macos or is_ios) {
        metal_available = enable_metal;
        vulkan_available = enable_vulkan and detectVulkanSDK(b);
        opengl_available = enable_opengl and !is_ios;
        opengles_available = enable_opengles and is_ios;
    } else if (is_linux or is_android) {
        vulkan_available = enable_vulkan and detectVulkanSDK(b);
        opengl_available = enable_opengl and !is_android;
        opengles_available = enable_opengles and is_android;
    } else if (is_web) {
        webgpu_available = enable_webgpu;
        opengles_available = enable_opengles;
    }

    // Create build configuration
    const config = BuildConfig{
        .target = target,
        .optimize = optimize,
        .enable_vulkan = enable_vulkan,
        .enable_d3d11 = enable_d3d11,
        .enable_d3d12 = enable_d3d12,
        .enable_metal = enable_metal,
        .enable_opengl = enable_opengl,
        .enable_opengles = enable_opengles,
        .enable_webgpu = enable_webgpu,
        .enable_tracy = enable_tracy,
        .enable_hot_reload = enable_hot_reload,
        .enable_debug_layers = enable_debug_layers,
        .enable_validation = enable_validation,
        .enable_profiling = enable_profiling,
        .enable_logging = enable_logging,
        .log_level = log_level,
        .target_os = target_os,
        .target_arch = target_arch,
        .is_windows = is_windows,
        .is_macos = is_macos,
        .is_ios = is_ios,
        .is_linux = is_linux,
        .is_android = is_android,
        .is_wasm = is_wasm,
        .is_mobile = is_mobile,
        .is_desktop = is_desktop,
        .is_web = is_web,
        .vulkan_available = vulkan_available,
        .d3d11_available = d3d11_available,
        .d3d12_available = d3d12_available,
        .metal_available = metal_available,
        .opengl_available = opengl_available,
        .opengles_available = opengles_available,
        .webgpu_available = webgpu_available,
    };

    // Core modules with enhanced configuration
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("mfs_lib", lib_mod);

    // Enhanced build options
    const build_options = b.addOptions();
    build_options.addOption(bool, "vulkan_available", vulkan_available);
    build_options.addOption(bool, "d3d11_available", d3d11_available);
    build_options.addOption(bool, "d3d12_available", d3d12_available);
    build_options.addOption(bool, "metal_available", metal_available);
    build_options.addOption(bool, "opengl_available", opengl_available);
    build_options.addOption(bool, "opengles_available", opengles_available);
    build_options.addOption(bool, "webgpu_available", webgpu_available);
    build_options.addOption(bool, "enable_tracy", enable_tracy);
    build_options.addOption(bool, "enable_hot_reload", enable_hot_reload);
    build_options.addOption(bool, "enable_debug_layers", enable_debug_layers);
    build_options.addOption(bool, "enable_validation", enable_validation);
    build_options.addOption(bool, "enable_profiling", enable_profiling);
    build_options.addOption(bool, "enable_logging", enable_logging);
    build_options.addOption([]const u8, "log_level", log_level);
    build_options.addOption([]const u8, "build_mode", @tagName(optimize));
    build_options.addOption([]const u8, "target_os", @tagName(target_os));
    build_options.addOption([]const u8, "target_arch", @tagName(target_arch));
    build_options.addOption(bool, "is_mobile", is_mobile);
    build_options.addOption(bool, "is_desktop", is_desktop);
    build_options.addOption(bool, "is_web", is_web);

    // Version information
    const version = b.option([]const u8, "version", "Application version") orelse "0.1.0";
    build_options.addOption([]const u8, "version", version);

    // Library setup with enhanced configuration
    const lib = b.addStaticLibrary(.{
        .name = "mfs",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("build_options", build_options.createModule());
    setupPlatformLibraries(lib, &config);

    b.installArtifact(lib);

    // Shared library for dynamic linking
    const shared_lib = b.addSharedLibrary(.{
        .name = "mfs_shared",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    shared_lib.root_module.addImport("build_options", build_options.createModule());
    setupPlatformLibraries(shared_lib, &config);
    b.installArtifact(shared_lib);

    // Main executable with enhanced setup
    const exe = b.addExecutable(.{
        .name = "mfs",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("build_options", build_options.createModule());
    exe.root_module.addImport("mfs_lib", lib_mod);
    setupPlatformLibraries(exe, &config);
    setupGraphicsBackends(exe, b, &config);

    if (enable_tracy) {
        setupTracy(exe, b, target_os);
    }

    if (enable_profiling) {
        setupProfiling(exe, b, &config);
    }

    // Add shader compilation
    setupShaderCompilation(b, exe, &config);

    // Add asset pipeline
    setupAssetPipeline(b, exe, &config);

    b.installArtifact(exe);

    // Run command with enhanced options
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the MFS application");
    run_step.dependOn(&run_cmd.step);

    // Debug run with validation layers
    const debug_run_cmd = b.addRunArtifact(exe);
    debug_run_cmd.step.dependOn(b.getInstallStep());
    debug_run_cmd.addArg("--debug");
    debug_run_cmd.addArg("--validation");
    if (b.args) |args| {
        debug_run_cmd.addArgs(args);
    }

    const debug_run_step = b.step("run-debug", "Run with debug options enabled");
    debug_run_step.dependOn(&debug_run_cmd.step);

    // Enhanced test setup
    setupTests(b, lib_mod, exe_mod, &config);

    // Build steps for different backends
    setupBackendTestSteps(b, &config);

    // Enhanced utility steps
    setupUtilitySteps(b, &config);

    // Print build summary
    printBuildSummary(&config);
}

fn detectVulkanSDK(b: *std.Build) bool {
    if (std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK")) |sdk_path| {
        defer b.allocator.free(sdk_path);

        const include_path = std.fs.path.join(b.allocator, &[_][]const u8{ sdk_path, "Include" }) catch return false;
        defer b.allocator.free(include_path);

        const lib_path = std.fs.path.join(b.allocator, &[_][]const u8{ sdk_path, "Lib" }) catch return false;
        defer b.allocator.free(lib_path);

        var include_dir = std.fs.openDirAbsolute(include_path, .{}) catch return false;
        defer include_dir.close();

        var lib_dir = std.fs.openDirAbsolute(lib_path, .{}) catch return false;
        defer lib_dir.close();

        // Verify vulkan.h exists
        include_dir.access("vulkan/vulkan.h", .{}) catch return false;

        std.debug.print("✓ Found Vulkan SDK at: {s}\n", .{sdk_path});
        return true;
    } else |_| {
        std.debug.print("⚠ Vulkan SDK not found. Install from: https://vulkan.lunarg.com/\n", .{});
        return false;
    }
}

fn detectDirectX12() bool {
    // Check for DirectX 12 availability on Windows
    if (builtin.os.tag != .windows) return false;

    // Try to detect D3D12 headers/libraries - more robust check
    std.fs.cwd().access("C:\\Program Files (x86)\\Windows Kits\\10\\Include\\", .{}) catch {
        std.fs.cwd().access("C:\\Program Files\\Windows Kits\\10\\Include\\", .{}) catch return false;
    };

    std.debug.print("✓ DirectX 12 detected\n", .{});
    return true;
}

fn detectDirectX11() bool {
    // Check for DirectX 11 availability on Windows
    if (builtin.os.tag != .windows) return false;

    std.debug.print("✓ DirectX 11 detected\n", .{});
    return true;
}

fn setupPlatformLibraries(step: *std.Build.Step.Compile, config: *const BuildConfig) void {
    // Don't link C for WASM targets
    if (config.target_os != .emscripten and config.target_os != .wasi) {
        step.linkLibC();
    }

    switch (config.target_os) {
        .windows => {
            // Core Windows libraries
            step.linkSystemLibrary("kernel32");
            step.linkSystemLibrary("user32");
            step.linkSystemLibrary("gdi32");
            step.linkSystemLibrary("shell32");
            step.linkSystemLibrary("ole32");
            step.linkSystemLibrary("oleaut32");
            step.linkSystemLibrary("uuid");
            step.linkSystemLibrary("winmm");
            step.linkSystemLibrary("dwmapi");
            step.linkSystemLibrary("comctl32");
            step.linkSystemLibrary("comdlg32");
            step.linkSystemLibrary("advapi32");

            // Graphics libraries
            step.linkSystemLibrary("opengl32");
            if (config.d3d12_available) {
                step.linkSystemLibrary("d3d12");
                step.linkSystemLibrary("dxgi");
                step.linkSystemLibrary("dxguid");
            }
            if (config.d3d11_available) {
                step.linkSystemLibrary("d3d11");
            }
        },
        .macos => {
            // Core macOS frameworks
            step.linkFramework("Cocoa");
            step.linkFramework("QuartzCore");
            step.linkFramework("IOKit");
            step.linkFramework("CoreFoundation");
            step.linkFramework("CoreGraphics");
            step.linkFramework("AppKit");
            step.linkFramework("Foundation");

            // Graphics frameworks
            if (config.metal_available) {
                step.linkFramework("Metal");
                step.linkFramework("MetalKit");
            }
            if (config.opengl_available) {
                step.linkFramework("OpenGL");
            }
        },
        .ios => {
            // Core iOS frameworks
            step.linkFramework("UIKit");
            step.linkFramework("QuartzCore");
            step.linkFramework("Foundation");
            step.linkFramework("CoreGraphics");
            step.linkFramework("CoreFoundation");

            // Graphics frameworks
            if (config.metal_available) {
                step.linkFramework("Metal");
                step.linkFramework("MetalKit");
            }
            if (config.opengles_available) {
                step.linkFramework("OpenGLES");
            }
        },
        .linux => {
            if (!config.is_mobile) {
                // Desktop Linux libraries
                step.linkSystemLibrary("X11");
                step.linkSystemLibrary("Xrandr");
                step.linkSystemLibrary("Xinerama");
                step.linkSystemLibrary("Xcursor");
                step.linkSystemLibrary("Xi");
                step.linkSystemLibrary("Xext");
                step.linkSystemLibrary("Xfixes");
                step.linkSystemLibrary("pthread");
                step.linkSystemLibrary("dl");
                step.linkSystemLibrary("m");
                step.linkSystemLibrary("rt");

                if (config.opengl_available) {
                    step.linkSystemLibrary("GL");
                    step.linkSystemLibrary("GLX");
                }
            } else {
                // Android
                step.linkSystemLibrary("android");
                step.linkSystemLibrary("log");
                step.linkSystemLibrary("c");
                if (config.opengles_available) {
                    step.linkSystemLibrary("EGL");
                    step.linkSystemLibrary("GLESv3");
                }
            }
        },
        .emscripten, .wasi => {
            // Web targets - handled by Emscripten
        },
        else => {},
    }
}

fn setupGraphicsBackends(exe: *std.Build.Step.Compile, b: *std.Build, config: *const BuildConfig) void {
    if (config.vulkan_available) {
        if (std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK")) |sdk_path| {
            defer b.allocator.free(sdk_path);

            const include_path = std.fs.path.join(b.allocator, &[_][]const u8{ sdk_path, "Include" }) catch return;
            defer b.allocator.free(include_path);

            const lib_path = std.fs.path.join(b.allocator, &[_][]const u8{ sdk_path, "Lib" }) catch return;
            defer b.allocator.free(lib_path);

            exe.addIncludePath(.{ .cwd_relative = include_path });
            exe.addLibraryPath(.{ .cwd_relative = lib_path });
            exe.linkSystemLibrary("vulkan-1");
        } else |_| {}
    }

    switch (config.target_os) {
        .windows => {
            if (config.d3d11_available) {
                // DirectX 11 libraries already linked in setupPlatformLibraries
            }
            if (config.d3d12_available) {
                // DirectX 12 libraries already linked in setupPlatformLibraries
            }
        },
        .macos, .ios => {
            if (config.metal_available) {
                // Metal frameworks already linked in setupPlatformLibraries
            }
        },
        .emscripten, .wasi => {
            // Web targets - configure for WASM
            if (config.target_os == .emscripten) {
                const emscripten_file = b.path("src/platform/web/emscripten_setup.c");
                // Check if file exists before trying to add it
                std.fs.cwd().access(emscripten_file.getPath(b), .{}) catch {
                    std.debug.print("⚠ Emscripten setup file not found: {s}\n", .{emscripten_file.getPath(b)});
                    return;
                };
                exe.addCSourceFile(.{
                    .file = emscripten_file,
                    .flags = &[_][]const u8{
                        "-sUSE_WEBGL2=1",
                        "-sUSE_GLFW=3",
                        "-sFULL_ES3=1",
                        "-sASYNCIFY",
                        "-sEXPORTED_FUNCTIONS=['_main','_web_init','_web_update','_web_render']",
                        "-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap']",
                        "-sALLOW_MEMORY_GROWTH=1",
                        "-sMAXIMUM_MEMORY=2GB",
                    },
                });
            }
        },
        else => {},
    }
}

fn setupTracy(exe: *std.Build.Step.Compile, b: *std.Build, target_os: std.Target.Os.Tag) void {
    const tracy_dep = b.dependency("tracy", .{}) catch {
        std.debug.print("⚠ Tracy dependency not found, profiling disabled\n", .{});
        return;
    };

    exe.root_module.addImport("tracy", tracy_dep.module("tracy"));

    switch (target_os) {
        .windows => {
            exe.linkSystemLibrary("ws2_32");
            exe.linkSystemLibrary("dbghelp");
        },
        .linux => {
            exe.linkSystemLibrary("pthread");
            exe.linkSystemLibrary("dl");
        },
        else => {},
    }
}

fn setupProfiling(exe: *std.Build.Step.Compile, b: *std.Build, config: *const BuildConfig) void {
    // Add built-in profiling module
    const profiling_mod = b.createModule(.{
        .root_source_file = b.path("src/profiling/profiler.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    exe.root_module.addImport("profiler", profiling_mod);
}

fn setupShaderCompilation(b: *std.Build, exe: *std.Build.Step.Compile, config: *const BuildConfig) void {
    _ = exe;
    const shader_compile_step = b.step("shaders", "Compile shaders");

    // Add shader compilation for each backend
    if (config.vulkan_available) {
        // Check if shaders directory exists
        std.fs.cwd().access("shaders/vertex.vert", .{}) catch {
            std.debug.print("⚠ Shader file not found: shaders/vertex.vert\n", .{});
            return;
        };

        const vulkan_shaders = b.addSystemCommand(&[_][]const u8{"glslc"});
        vulkan_shaders.addArgs(&[_][]const u8{ "shaders/vertex.vert", "-o", "shaders/vertex.spv" });
        shader_compile_step.dependOn(&vulkan_shaders.step);
    }

    if (config.d3d11_available or config.d3d12_available) {
        // Check if shaders directory exists
        std.fs.cwd().access("shaders/vertex.hlsl", .{}) catch {
            std.debug.print("⚠ Shader file not found: shaders/vertex.hlsl\n", .{});
            return;
        };

        const hlsl_shaders = b.addSystemCommand(&[_][]const u8{"fxc"});
        hlsl_shaders.addArgs(&[_][]const u8{ "/T", "vs_5_0", "shaders/vertex.hlsl", "/Fo", "shaders/vertex.cso" });
        shader_compile_step.dependOn(&hlsl_shaders.step);
    }
}

fn setupAssetPipeline(b: *std.Build, exe: *std.Build.Step.Compile, config: *const BuildConfig) void {
    _ = exe;
    const asset_step = b.step("assets", "Process assets");

    // Check if asset processor exists
    const asset_processor_path = b.path("src/tools/asset_processor.zig");
    std.fs.cwd().access(asset_processor_path.getPath(b), .{}) catch {
        std.debug.print("⚠ Asset processor not found: {s}\n", .{asset_processor_path.getPath(b)});
        return;
    };

    // Add asset processing tools
    const asset_processor = b.addExecutable(.{
        .name = "asset_processor",
        .root_source_file = asset_processor_path,
        .target = config.target,
        .optimize = .ReleaseFast,
    });

    const process_assets = b.addRunArtifact(asset_processor);
    process_assets.addArg("--input");
    process_assets.addArg("assets/");
    process_assets.addArg("--output");
    process_assets.addArg("processed_assets/");

    asset_step.dependOn(&process_assets.step);
}

fn setupTests(b: *std.Build, lib_mod: *std.Build.Module, exe_mod: *std.Build.Module, config: *const BuildConfig) void {
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    lib_unit_tests.root_module.addImport("mfs_lib", lib_mod);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    exe_unit_tests.root_module.addImport("mfs_lib", lib_mod);

    const run_lib_tests = b.addRunArtifact(lib_unit_tests);
    const run_exe_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Integration tests - check if file exists first
    const integration_test_path = b.path("src/test/integration_tests.zig");
    std.fs.cwd().access(integration_test_path.getPath(b), .{}) catch {
        std.debug.print("⚠ Integration test file not found: {s}\n", .{integration_test_path.getPath(b)});
        return;
    };

    const integration_tests = b.addTest(.{
        .name = "integration_tests",
        .root_source_file = integration_test_path,
        .target = config.target,
        .optimize = config.optimize,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Performance tests - check if file exists first
    const perf_test_path = b.path("src/test/performance_tests.zig");
    std.fs.cwd().access(perf_test_path.getPath(b), .{}) catch {
        std.debug.print("⚠ Performance test file not found: {s}\n", .{perf_test_path.getPath(b)});
        return;
    };

    const perf_tests = b.addTest(.{
        .name = "performance_tests",
        .root_source_file = perf_test_path,
        .target = config.target,
        .optimize = .ReleaseFast,
    });

    const run_perf_tests = b.addRunArtifact(perf_tests);
    const perf_test_step = b.step("test-perf", "Run performance tests");
    perf_test_step.dependOn(&run_perf_tests.step);
}

fn setupBackendTestSteps(b: *std.Build, config: *const BuildConfig) void {
    if (config.vulkan_available) {
        const test_path = b.path("src/test/vulkan_test.zig");
        std.fs.cwd().access(test_path.getPath(b), .{}) catch return;

        const vulkan_test = b.addExecutable(.{
            .name = "test-vulkan",
            .root_source_file = test_path,
            .target = config.target,
            .optimize = config.optimize,
        });
        setupPlatformLibraries(vulkan_test, config);
        setupGraphicsBackends(vulkan_test, b, config);

        const vulkan_test_step = b.step("test-vulkan", "Test Vulkan backend");
        vulkan_test_step.dependOn(&b.addRunArtifact(vulkan_
