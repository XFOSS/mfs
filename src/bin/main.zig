//! MFS Engine - Main Entry Point
//! Primary executable entry point for the MFS Engine
//! Handles command-line arguments and initializes the engine

const std = @import("std");

const mfs = @import("mfs");
const engine = mfs.engine;

const build_options = @import("../build_options.zig");

// =============================================================================
// Command Line Arguments
// =============================================================================

const Args = struct {
    help: bool = false,
    version: bool = false,
    backend: ?[]const u8 = null,
    width: u32 = build_options.Graphics.default_width,
    height: u32 = build_options.Graphics.default_height,
    fullscreen: bool = false,
    vsync: bool = build_options.Graphics.default_vsync,
    validation: bool = build_options.Features.enable_validation,

    pub fn parse(allocator: std.mem.Allocator) !Args {
        var args = Args{};
        var arg_iter = try std.process.argsWithAllocator(allocator);
        defer arg_iter.deinit();

        // Skip program name
        _ = arg_iter.skip();

        while (arg_iter.next()) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                args.help = true;
            } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
                args.version = true;
            } else if (std.mem.startsWith(u8, arg, "--backend=")) {
                args.backend = arg[10..];
            } else if (std.mem.startsWith(u8, arg, "--width=")) {
                args.width = try std.fmt.parseInt(u32, arg[8..], 10);
            } else if (std.mem.startsWith(u8, arg, "--height=")) {
                args.height = try std.fmt.parseInt(u32, arg[9..], 10);
            } else if (std.mem.eql(u8, arg, "--fullscreen")) {
                args.fullscreen = true;
            } else if (std.mem.eql(u8, arg, "--no-vsync")) {
                args.vsync = false;
            } else if (std.mem.eql(u8, arg, "--no-validation")) {
                args.validation = false;
            } else {
                std.log.warn("Unknown argument: {s}", .{arg});
            }
        }

        return args;
    }

    pub fn printHelp() void {
        std.log.info(
            \\MFS Engine v{s}
            \\
            \\Usage: mfs-engine [options]
            \\
            \\Options:
            \\  --help, -h            Show this help message
            \\  --version, -v         Show version information
            \\  --backend=BACKEND     Graphics backend (vulkan, d3d12, opengl, auto)
            \\  --width=WIDTH         Window width (default: {d})
            \\  --height=HEIGHT       Window height (default: {d})
            \\  --fullscreen          Start in fullscreen mode
            \\  --no-vsync            Disable vertical sync
            \\  --no-validation       Disable graphics validation layers
            \\
            \\Available backends:
        , .{ build_options.Version.engine_version, build_options.Graphics.default_width, build_options.Graphics.default_height });

        inline for (@typeInfo(mfs.graphics.BackendType).Enum.fields) |field| {
            const backend = @field(mfs.graphics.BackendType, field.name);
            if (backend.isAvailable()) {
                std.log.info("  {s} (available)", .{field.name});
            } else {
                std.log.info("  {s} (not available)", .{field.name});
            }
        }
    }

    pub fn printVersion() void {
        const platform_info = mfs.getPlatformInfo();
        std.log.info(
            \\{s}
            \\Platform: {s} {s}
            \\Build: {s}
            \\Features: Graphics={}, Audio={}, Physics={}
        , .{
            build_options.Version.getFullVersionString(),
            platform_info.os,
            platform_info.arch,
            build_options.Version.build_type,
            build_options.Features.enable_graphics,
            build_options.Features.enable_audio,
            build_options.Features.enable_physics,
        });
    }
};

// =============================================================================
// Main Function
// =============================================================================

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = Args.parse(allocator) catch |err| {
        std.log.err("Failed to parse arguments: {}", .{err});
        return;
    };

    // Handle special arguments
    if (args.help) {
        Args.printHelp();
        return;
    }

    if (args.version) {
        Args.printVersion();
        return;
    }

    // Create engine configuration
    var config = engine.createDefaultConfig();
    config.window_width = args.width;
    config.window_height = args.height;
    config.window_fullscreen = args.fullscreen;
    config.enable_vsync = args.vsync;
    config.enable_validation = args.validation;

    // Set graphics backend if specified
    if (args.backend) |backend_name| {
        if (std.mem.eql(u8, backend_name, "vulkan")) {
            config.graphics_backend = .vulkan;
        } else if (std.mem.eql(u8, backend_name, "d3d12")) {
            config.graphics_backend = .d3d12;
        } else if (std.mem.eql(u8, backend_name, "d3d11")) {
            config.graphics_backend = .d3d11;
        } else if (std.mem.eql(u8, backend_name, "opengl")) {
            config.graphics_backend = .opengl;
        } else if (std.mem.eql(u8, backend_name, "metal")) {
            config.graphics_backend = .metal;
        } else if (std.mem.eql(u8, backend_name, "software")) {
            config.graphics_backend = .software;
        } else if (std.mem.eql(u8, backend_name, "auto")) {
            config.graphics_backend = .auto;
        } else {
            std.log.err("Unknown graphics backend: {s}", .{backend_name});
            Args.printHelp();
            return;
        }
    }

    // Initialize and run the engine
    std.log.info("Starting {s}...", .{build_options.Version.getFullVersionString()});
    std.log.info("Platform: {s}", .{mfs.getPlatformInfo().os});

    const app = mfs.initWithConfig(allocator, config) catch |err| {
        std.log.err("Failed to initialize engine: {}", .{err});
        return;
    };
    defer mfs.deinit(app);

    std.log.info("Engine initialized successfully");

    // Run the main loop
    app.run() catch |err| {
        std.log.err("Engine runtime error: {}", .{err});
        return;
    };

    std.log.info("Engine shutdown complete");
}
