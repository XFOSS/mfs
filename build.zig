const std = @import("std");

const build_helpers = @import("build/build_helpers.zig");

/// Build configuration for the MFS Engine
const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    enable_vulkan: bool = false,
    enable_ray_tracing: bool = false,
    enable_tracy: bool = false,
    enable_hot_reload: bool = false,

    pub fn init(b: *std.Build) BuildConfig {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        return .{
            .target = target,
            .optimize = optimize,
            .enable_vulkan = b.option(bool, "vulkan", "Enable Vulkan support") orelse false,
            .enable_ray_tracing = b.option(bool, "ray-tracing", "Enable ray tracing") orelse false,
            .enable_tracy = b.option(bool, "tracy", "Enable Tracy profiler") orelse false,
            .enable_hot_reload = b.option(bool, "hot-reload", "Enable hot reload") orelse false,
        };
    }
};

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
        .root_source_file = b.path(config.root_source_file),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Add common dependencies
    try build_helpers.addSourceModules(b, exe);
    if (config.opts) |opts| {
        exe.addOptions("build_options", opts);
    }

    // Add platform-specific dependencies
    addPlatformDependencies(exe, config.target.result.os.tag);

    // Install the executable
    b.installArtifact(exe);

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

/// Main build function
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create build options
    const options = b.addOptions();
    addBuildOptions(options, target.result);

    // Create main library
    const lib = b.addModule("mfs", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add memory manager tests
    const memory_manager_tests = b.addTest(.{
        .name = "memory-manager-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/graphics/test_memory_manager.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    memory_manager_tests.root_module.addImport("mfs", lib);
    memory_manager_tests.root_module.addOptions("build_options", options);
    addPlatformDependencies(memory_manager_tests, target.result.os.tag);
    // Add Vulkan system library to tests (include path handled by Vulkan SDK environment)
    addOptionalLibrary(memory_manager_tests, "vulkan-1");

    const vulkan_backend_tests = b.addTest(.{
        .name = "vulkan-backend-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/graphics/test_vulkan_backend_new.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vulkan_backend_tests.root_module.addImport("mfs", lib);
    vulkan_backend_tests.root_module.addOptions("build_options", options);
    addPlatformDependencies(vulkan_backend_tests, target.result.os.tag);
    addOptionalLibrary(vulkan_backend_tests, "vulkan-1");

    const test_step = b.step("test-graphics", "Run graphics backend tests");
    test_step.dependOn(&memory_manager_tests.step);
    test_step.dependOn(&vulkan_backend_tests.step);

    // const examples = [_][]const u8{
    //     "vulkan_spinning_cube_simple",
    //     "vulkan_spinning_cube_real",
    //     "vulkan_rt_spinning_cube",
    // };

    // for (examples) |example| {
    //     const exe = b.addExecutable(.{
    //         .name = example,
    //         .root_module = b.createModule(.{
    //             .root_source_file = b.path(b.fmt("examples/{s}/main.zig", .{example})),
    //             .target = target,
    //             .optimize = optimize,
    //         }),
    //     });

    //     // Optionally link Vulkan system library for examples
    //     addOptionalLibrary(exe, "vulkan-1");

    //     // Link with main library
    //     exe.linkLibrary(lib);

    //     b.installArtifact(exe);

    //     const run_cmd = b.addRunArtifact(exe);
    //     run_cmd.step.dependOn(b.getInstallStep());

    //     const run_step = b.step(b.fmt("run-{s}", .{example}), b.fmt("Run the {s} example", .{example}));
    //     run_step.dependOn(&run_cmd.step);
    // }
}

fn addBuildOptions(options: *std.Build.Step.Options, target: std.Target) void {
    // Platform detection
    options.addOption(bool, "is_windows", target.os.tag == .windows);
    options.addOption(bool, "is_linux", target.os.tag == .linux);
    options.addOption(bool, "is_macos", target.os.tag == .macos);
    options.addOption(bool, "is_web", target.os.tag == .emscripten or target.os.tag == .wasi);
    options.addOption(bool, "is_mobile", false);

    // Graphics backend availability
    options.addOption(bool, "vulkan_available", target.os.tag == .windows or target.os.tag == .linux);
    options.addOption(bool, "d3d11_available", target.os.tag == .windows);
    options.addOption(bool, "d3d12_available", target.os.tag == .windows);
    options.addOption(bool, "metal_available", target.os.tag == .macos);
    options.addOption(bool, "opengl_available", false); // Disabled due to missing GL headers
    options.addOption(bool, "webgpu_available", target.os.tag == .emscripten or target.os.tag == .wasi);

    // Feature flags
    options.addOption(bool, "enable_validation", @import("builtin").mode == .Debug);
    options.addOption(bool, "enable_tracy", false);
    options.addOption(bool, "enable_hot_reload", @import("builtin").mode == .Debug);
}

fn buildTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mfs: *std.Build.Module,
    options: *std.Build.Step.Options,
) void {
    // Main test runner that includes all modules
    const test_exe = b.addTest(.{
        .name = "mfs-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_exe.root_module.addImport("mfs", mfs);
    test_exe.root_module.addOptions("build_options", options);
    addPlatformDependencies(test_exe, target.result.os.tag);

    const test_run = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_run.step);

    // Individual test suites with proper module access
    const test_files = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "math-tests", .path = "src/tests/test_math.zig" },
        .{ .name = "physics-tests", .path = "src/tests/physics_test.zig" },
        .{ .name = "comprehensive-tests", .path = "src/tests/comprehensive_tests.zig" },
        .{ .name = "benchmark-tests", .path = "src/tests/benchmarks/render_bench.zig" },
    };

    for (test_files) |test_file| {
        const individual_test = b.addTest(.{
            .name = test_file.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file.path),
                .target = target,
                .optimize = optimize,
            }),
        });
        individual_test.root_module.addImport("mfs", mfs);
        individual_test.root_module.addOptions("build_options", options);
        addPlatformDependencies(individual_test, target.result.os.tag);

        const individual_test_run = b.addRunArtifact(individual_test);
        const individual_test_step = b.step(
            b.fmt("test-{s}", .{test_file.name}),
            b.fmt("Run {s}", .{test_file.name}),
        );
        individual_test_step.dependOn(&individual_test_run.step);
    }
}

fn buildTools(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mfs: *std.Build.Module,
    options: *std.Build.Step.Options,
) void {
    const tools = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "asset-processor", .path = "tools/asset_processor/asset_processor.zig" },
        .{ .name = "model-viewer", .path = "tools/model_viewer.zig" },
        .{ .name = "texture-converter", .path = "tools/texture_converter.zig" },
    };

    for (tools) |tool| {
        const exe = b.addExecutable(.{
            .name = tool.name,
            .root_source_file = b.path(tool.path),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("mfs", mfs);
        exe.addOptions("build_options", options);
        addPlatformDependencies(exe, target.result.os.tag);
        b.installArtifact(exe);
    }
}

/// Build for WebAssembly target
fn buildWebTarget(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mfs: *std.Build.Module,
    options: *std.Build.Step.Options,
) void {
    _ = target;
    _ = optimize;
    _ = options;

    const web_step = b.step("web", "Build for WebAssembly");

    // Create web-specific target
    const web_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const web_exe = b.addExecutable(.{
        .name = "mfs-web",
        .root_source_file = b.path("src/main.zig"),
        .target = web_target,
        .optimize = .ReleaseSmall,
    });

    web_exe.root_module.addImport("mfs", mfs);
    web_exe.entry = .disabled;

    // Zig versions prior to 0.15 do not expose `export_symbol_names` on `std.Build.Step.Compile`.
    // Use reflection to set it only when available so the build script remains compatible with
    // older toolchains (e.g., 0.14.x).
    if (@hasField(@TypeOf(web_exe.*), "export_symbol_names")) {
        @field(web_exe, "export_symbol_names") = &[_][]const u8{
            "web_init",
            "web_frame",
            "web_deinit",
        };
    }

    b.installArtifact(web_exe);
    web_step.dependOn(&web_exe.step);
}

/// Add platform-specific dependencies with improved organization
fn addPlatformDependencies(exe: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    // Common dependencies
    exe.linkLibC();

    // Platform-specific dependencies
    switch (os_tag) {
        .windows => addWindowsDependencies(exe),
        .linux => addLinuxDependencies(exe),
        .macos => addMacosDependencies(exe),
        .ios => addIosDependencies(exe),
        .wasi, .emscripten, .freestanding => addWebDependencies(exe),
        else => {},
    }
}

/// Add Windows-specific dependencies
fn addWindowsDependencies(exe: *std.Build.Step.Compile) void {
    const required_libs = [_][]const u8{
        "user32",   "kernel32", "gdi32", "shell32",
        "opengl32", "winmm",    "ole32", "uuid",
    };

    for (required_libs) |lib| {
        exe.linkSystemLibrary(lib);
    }

    // Optional libraries
    const optional_libs = [_][]const u8{
        "glu32",  "xinput",      "dwmapi",
        "d3d11",  "d3d12",       "dxgi",
        "dxguid", "d3dcompiler",
    };

    for (optional_libs) |lib| {
        addOptionalLibrary(exe, lib);
    }
}

/// Add Linux-specific dependencies
fn addLinuxDependencies(exe: *std.Build.Step.Compile) void {
    const required_libs = [_][]const u8{ "GL", "X11", "m" };

    for (required_libs) |lib| {
        exe.linkSystemLibrary(lib);
    }

    // Optional Linux dependencies
    const optional_libs = [_][]const u8{
        "Xi",             "Xcursor",     "Xrandr",         "Xinerama",
        "wayland-client", "wayland-egl", "wayland-cursor",
    };

    for (optional_libs) |lib| {
        addOptionalLibrary(exe, lib);
    }
}

/// Add macOS-specific dependencies
fn addMacosDependencies(exe: *std.Build.Step.Compile) void {
    const frameworks = [_][]const u8{
        "Cocoa",      "OpenGL",         "Metal",        "MetalKit",
        "QuartzCore", "CoreFoundation", "CoreGraphics", "Foundation",
        "AppKit",     "IOKit",
    };

    for (frameworks) |framework| {
        exe.linkFramework(framework);
    }
}

/// Add iOS-specific dependencies
fn addIosDependencies(exe: *std.Build.Step.Compile) void {
    const frameworks = [_][]const u8{
        "UIKit",    "Foundation", "CoreGraphics", "QuartzCore",
        "OpenGLES", "Metal",      "MetalKit",
    };

    for (frameworks) |framework| {
        exe.linkFramework(framework);
    }
}

/// Add Web-specific dependencies
fn addWebDependencies(_: *std.Build.Step.Compile) void {
    // Web platform typically doesn't need explicit libraries
}

/// Helper to add optional libraries
fn addOptionalLibrary(exe: *std.Build.Step.Compile, name: []const u8) void {
    // For now, just add a debug message for optional libraries
    // In production, this would check if the library exists first
    std.log.debug("Optional library '{s}' requested", .{name});

    // Skip libraries that are commonly missing from default Windows SDK/MinGW setups.
    // They are useful when available but should not make the build fail if absent.
    const skip_libs = [_][]const u8{
        "xinput",
        "vulkan",
        "vulkan-1",
        "d3dcompiler", // Use runtime-loaded d3dcompiler_47.dll instead when present.
    };
    for (skip_libs) |lib| {
        if (std.mem.eql(u8, name, lib)) {
            return;
        }
    }

    exe.linkSystemLibrary(name);
}
