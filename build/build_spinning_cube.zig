const std = @import("std");

pub fn build(b: *std.Build) void {
    // #region agent log
    const log_path = ".cursor/debug.log";
    if (std.fs.cwd().openFile(log_path, .{ .mode = .write_only })) |file| {
        defer file.close();
        _ = file.writeAll("{\"id\":\"log_build_entry\",\"location\":\"build/build_spinning_cube.zig:4\",\"message\":\"Build function entry\",\"data\":{\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}\n") catch {};
    } else |_| {}
    // #endregion

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // #region agent log
    if (std.fs.cwd().openFile(log_path, .{ .mode = .write_only })) |file| {
        defer file.close();
        _ = file.writeAll("{\"id\":\"log_target_optimize\",\"location\":\"build/build_spinning_cube.zig:13\",\"message\":\"Target and optimize set\",\"data\":{\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}\n") catch {};
    } else |_| {}
    // #endregion

    // Create the spinning cube executable
    // #region agent log
    if (std.fs.cwd().openFile(log_path, .{ .mode = .write_only })) |file| {
        defer file.close();
        _ = file.writeAll("{\"id\":\"log_before_addExecutable\",\"location\":\"build/build_spinning_cube.zig:20\",\"message\":\"Before addExecutable call\",\"data\":{\"source_file\":\"src/render/opengl_cube.zig\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}\n") catch {};
    } else |_| {}
    // #endregion

    const spinning_cube = b.addExecutable(.{
        .name = "spinning_cube",
        .root_module = b.createModule(.{
            .root_source_file = b.path("../src/render/opengl_cube.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // #region agent log
    if (std.fs.cwd().openFile(log_path, .{ .mode = .write_only })) |file| {
        defer file.close();
        _ = file.writeAll("{\"id\":\"log_after_addExecutable\",\"location\":\"build/build_spinning_cube.zig:30\",\"message\":\"After addExecutable call\",\"data\":{\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}\n") catch {};
    } else |_| {}
    // #endregion

    // Add build options
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_tracy", false);
    build_options.addOption(bool, "vulkan_available", true);
    build_options.addOption(bool, "d3d11_available", target.result.os.tag == .windows);
    build_options.addOption(bool, "d3d12_available", target.result.os.tag == .windows);
    build_options.addOption(bool, "metal_available", target.result.os.tag == .macos);
    build_options.addOption(bool, "opengl_available", true);
    build_options.addOption(bool, "opengles_available", true);
    build_options.addOption(bool, "webgpu_available", false);
    build_options.addOption(bool, "is_mobile", false);
    build_options.addOption(bool, "is_desktop", true);
    build_options.addOption([]const u8, "target_os", @tagName(target.result.os.tag));

    spinning_cube.root_module.addOptions("build_options", build_options);

    // Link system libraries based on platform
    switch (target.result.os.tag) {
        .windows => {
            spinning_cube.linkSystemLibrary("user32");
            spinning_cube.linkSystemLibrary("kernel32");
            spinning_cube.linkSystemLibrary("gdi32");
            spinning_cube.linkSystemLibrary("opengl32");
            spinning_cube.linkSystemLibrary("d3d11");
            spinning_cube.linkSystemLibrary("dxgi");
        },
        .linux => {
            spinning_cube.linkSystemLibrary("X11");
            spinning_cube.linkSystemLibrary("GL");
            spinning_cube.linkSystemLibrary("vulkan");
        },
        .macos => {
            spinning_cube.linkFramework("Cocoa");
            spinning_cube.linkFramework("Metal");
            spinning_cube.linkFramework("OpenGL");
            spinning_cube.linkFramework("QuartzCore");
        },
        else => {},
    }

    spinning_cube.linkLibC();

    // Install the executable
    b.installArtifact(spinning_cube);

    // Create run command
    const run_cmd = b.addRunArtifact(spinning_cube);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the spinning cube demo");
    run_step.dependOn(&run_cmd.step);

    // Create test step
    const spinning_cube_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../src/render/opengl_cube.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    spinning_cube_tests.root_module.addOptions("build_options", build_options);

    const test_step = b.step("test", "Run spinning cube tests");
    test_step.dependOn(&b.addRunArtifact(spinning_cube_tests).step);
}
