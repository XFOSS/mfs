const std = @import("std");

/// Build helper utilities for the MFS Engine
/// Provides clean, focused utilities for the build system
/// Platform detection utilities
pub const Platform = struct {
    pub fn isWindows(target: std.Target.Os.Tag) bool {
        return target == .windows;
    }

    pub fn isLinux(target: std.Target.Os.Tag) bool {
        return target == .linux;
    }

    pub fn isMacOS(target: std.Target.Os.Tag) bool {
        return target == .macos;
    }

    pub fn isWeb(target: std.Target.Os.Tag) bool {
        return target == .emscripten or target == .wasi;
    }

    pub fn isMobile(target: std.Target.Os.Tag) bool {
        return target == .ios or target == .android;
    }
};

/// Graphics backend detection
pub const Graphics = struct {
    pub fn detectVulkan() bool {
        // Check for Vulkan SDK environment variable
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "VULKAN_SDK")) |_| {
            return true;
        } else |_| {
            return false;
        }
    }

    pub fn detectDirectX11(target: std.Target.Os.Tag) bool {
        return Platform.isWindows(target);
    }

    pub fn detectDirectX12(target: std.Target.Os.Tag) bool {
        return Platform.isWindows(target);
    }

    pub fn detectMetal(target: std.Target.Os.Tag) bool {
        return Platform.isMacOS(target);
    }

    pub fn detectOpenGL(target: std.Target.Os.Tag) bool {
        // OpenGL is available on most platforms
        return !Platform.isWeb(target);
    }

    pub fn detectWebGPU(target: std.Target.Os.Tag) bool {
        return Platform.isWeb(target);
    }
};

/// Module creation utilities
pub const Modules = struct {
    /// Create a module with consistent naming and structure
    pub fn create(
        b: *std.Build,
        name: []const u8,
        path: []const u8,
        dependencies: []const std.Build.Module.Import,
    ) *std.Build.Module {
        return b.addModule(name, .{
            .root_source_file = b.path(path),
            .imports = dependencies,
        });
    }

    /// Add standard library dependencies to an executable
    pub fn addStandardLibraries(exe: *std.Build.Step.Compile, target: std.Target.Os.Tag) void {
        exe.linkLibC();

        switch (target) {
            .windows => {
                exe.linkSystemLibrary("user32");
                exe.linkSystemLibrary("gdi32");
                exe.linkSystemLibrary("opengl32");
                exe.linkSystemLibrary("winmm");
            },
            .linux => {
                exe.linkSystemLibrary("GL");
                exe.linkSystemLibrary("X11");
                exe.linkSystemLibrary("m");
                exe.linkSystemLibrary("pthread");
            },
            .macos => {
                exe.linkFramework("Cocoa");
                exe.linkFramework("OpenGL");
                exe.linkFramework("Metal");
                exe.linkFramework("MetalKit");
            },
            else => {},
        }
    }
};

/// Asset management utilities
pub const Assets = struct {
    /// Install shader directory
    pub fn installShaders(b: *std.Build, from_path: []const u8, to_subdir: []const u8) *std.Build.Step {
        const install_dir = b.addInstallDirectory(.{
            .source_dir = b.path(from_path),
            .install_dir = .bin,
            .install_subdir = to_subdir,
        });
        return &install_dir.step;
    }

    /// Install assets if they exist
    pub fn installAssetsIfExist(b: *std.Build, from_path: []const u8, to_subdir: []const u8) ?*std.Build.Step {
        std.fs.cwd().access(from_path, .{}) catch return null;

        const install_dir = b.addInstallDirectory(.{
            .source_dir = b.path(from_path),
            .install_dir = .bin,
            .install_subdir = to_subdir,
        });
        return &install_dir.step;
    }
};

/// Testing utilities
pub const Testing = struct {
    /// Create a test executable with standard configuration
    pub fn createTestExecutable(
        b: *std.Build,
        name: []const u8,
        root_source: []const u8,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) *std.Build.Step.Compile {
        const test_exe = b.addTest(.{
            .name = name,
            .root_source_file = b.path(root_source),
            .target = target,
            .optimize = optimize,
        });

        return test_exe;
    }

    /// Create test run step
    pub fn createTestRunStep(
        b: *std.Build,
        test_exe: *std.Build.Step.Compile,
        step_name: []const u8,
        description: []const u8,
    ) *std.Build.Step {
        const run_test = b.addRunArtifact(test_exe);
        const test_step = b.step(step_name, description);
        test_step.dependOn(&run_test.step);
        return test_step;
    }
};

/// Development utilities
pub const Development = struct {
    /// Create hot reload watcher
    pub fn createHotReloadWatcher(b: *std.Build, watch_paths: []const []const u8) !void {
        // Create a custom step for hot reload
        const hot_reload_step = b.step("hot-reload", "Watch for file changes and rebuild");

        // For each watch path, create a file watcher
        for (watch_paths) |path| {
            const watch_step = b.addSystemCommand(&.{ "inotifywait", "-m", "-r", "-e", "modify,create,delete", path });
            hot_reload_step.dependOn(&watch_step.step);
        }

        // TODO: Implement more sophisticated hot reload with:
        // - File change detection
        // - Incremental compilation
        // - Asset hot reloading
        // - Runtime code patching
    }

    /// Setup Tracy profiler if enabled
    pub fn setupTracy(exe: *std.Build.Step.Compile, enabled: bool) void {
        if (enabled) {
            // Add Tracy profiler integration
            exe.addCSourceFile(.{
                .file = .{ .path = "third_party/tracy/TracyC.h" },
                .flags = &.{"-DTRACY_ENABLE"},
            });

            exe.linkSystemLibrary("tracy");
            exe.addIncludeDir(.{ .path = "third_party/tracy" });

            // TODO: Add Tracy dependency when available
            // This would typically involve:
            // - Adding Tracy as a git submodule
            // - Configuring Tracy for the target platform
            // - Setting up proper linking
        }
    }
};

/// Validation utilities
pub const Validation = struct {
    /// Check if a directory exists
    pub fn directoryExists(path: []const u8) bool {
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Check if a file exists
    pub fn fileExists(path: []const u8) bool {
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Validate build configuration
    pub fn validateConfiguration(config: anytype) !void {
        const config_type = @TypeOf(config);

        // Check for required fields
        if (@hasField(config_type, "target")) {
            if (config.target == null) {
                return error.InvalidConfiguration;
            }
        }

        if (@hasField(config_type, "optimize")) {
            if (config.optimize == null) {
                return error.InvalidConfiguration;
            }
        }

        // Validate paths exist
        if (@hasField(config_type, "source_dir")) {
            if (!fileExists(config.source_dir)) {
                return error.SourceDirectoryNotFound;
            }
        }

        if (@hasField(config_type, "output_dir")) {
            // Create output directory if it doesn't exist
            std.fs.cwd().makePath(config.output_dir) catch |err| {
                if (err != error.PathAlreadyExists) {
                    return error.OutputDirectoryCreationFailed;
                }
            };
        }

        // TODO: Add more comprehensive validation:
        // - Check for conflicting options
        // - Validate target compatibility
        // - Check dependency availability
        // - Validate build flags
    }
};

test "build helpers" {
    const testing = std.testing;

    // Test platform detection
    try testing.expect(Platform.isWindows(.windows));
    try testing.expect(!Platform.isWindows(.linux));
    try testing.expect(Platform.isLinux(.linux));
    try testing.expect(!Platform.isLinux(.windows));

    // Test graphics detection
    try testing.expect(Graphics.detectDirectX11(.windows));
    try testing.expect(!Graphics.detectDirectX11(.linux));
    try testing.expect(Graphics.detectMetal(.macos));
    try testing.expect(!Graphics.detectMetal(.windows));
}
