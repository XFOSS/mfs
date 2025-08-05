const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_model = .{ .explicit = &std.Target.wasm.cpu.baseline },
            .abi = .musl,
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    const wasm_module = b.addExecutable(.{
        .name = "mfs-spinning-cube",
        .root_source_file = .{ .path = "src/demos/spinning_cube_wasm.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add WASM-specific options
    wasm_module.rdynamic = true;
    wasm_module.import_memory = true;
    wasm_module.initial_memory = 65536;
    wasm_module.max_memory = 65536;
    wasm_module.stack_size = 14752;

    // Export functions for JavaScript
    wasm_module.export_symbol_names = &[_][]const u8{
        "initialize_spinning_cube_demo",
        "start_spinning_cube_demo",
        "pause_spinning_cube_demo",
        "reset_spinning_cube_demo",
        "web_resize",
    };

    // Install to web directory
    const install_wasm = b.addInstallArtifact(wasm_module, .{
        .dest_dir = .{ .custom = "web" },
    });

    b.getInstallStep().dependOn(&install_wasm.step);

    // Generate JavaScript glue code
    const emcc = b.addSystemCommand(&[_][]const u8{
        "emcc",
        "-s", "WASM=1",
        "-s", "EXPORTED_FUNCTIONS=['_initialize_spinning_cube_demo','_start_spinning_cube_demo','_pause_spinning_cube_demo','_reset_spinning_cube_demo','_web_resize']",
        "-s", "EXPORTED_RUNTIME_METHODS=['ccall','cwrap']",
        "-s", "ALLOW_MEMORY_GROWTH=1",
        "-s", "INITIAL_MEMORY=65536",
        "-s", "MAXIMUM_MEMORY=65536",
        "-s", "STACK_SIZE=14752",
        "-s", "USE_WEBGL2=1",
        "-s", "FULL_ES3=1",
        "-O3",
        "-o", "web/mfs-spinning-cube.js",
        "src/demos/spinning_cube_wasm.zig",
    });

    b.getInstallStep().dependOn(&emcc.step);
}