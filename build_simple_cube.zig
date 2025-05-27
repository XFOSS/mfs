const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const simple_cube = b.addExecutable(.{
        .name = "simple_cube",
        .root_source_file = b.path("src/simple_spinning_cube.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link required Windows libraries
    simple_cube.linkSystemLibrary("user32");
    simple_cube.linkSystemLibrary("kernel32");
    simple_cube.linkSystemLibrary("gdi32");
    simple_cube.linkSystemLibrary("opengl32");
    simple_cube.linkSystemLibrary("glu32");
    simple_cube.linkLibC();

    b.installArtifact(simple_cube);

    const run_cmd = b.addRunArtifact(simple_cube);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the simple spinning cube");
    run_step.dependOn(&run_cmd.step);
}
