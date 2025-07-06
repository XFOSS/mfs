const std = @import("std");
const builtin = @import("builtin");
const gpu = @import("../graphics/gpu.zig");

// Build options - would typically come from build.zig flags
pub const build_options = struct {
    pub const enable_tracy = false;
    pub const enable_hot_reload = builtin.mode == .Debug;
    pub const target_os = @tagName(builtin.os.tag);
    pub const is_mobile = false;
    pub const is_desktop = true;
    pub const vulkan_available = true;
    pub const d3d11_available = true;
    pub const d3d12_available = true;
    pub const metal_available = false;
    pub const opengl_available = true;
    pub const opengles_available = false;
    pub const webgpu_available = false;
};

// Enhanced configuration with validation and serialization
pub const Config = struct {
    // Core subsystems
    enable_gpu: bool = true,
    enable_physics: bool = true,
    enable_neural: bool = false,
    enable_xr: bool = false,
    enable_audio: bool = true,
    enable_networking: bool = false,

    // Performance settings
    target_fps: u32 = 60,
    max_fps: u32 = 240,
    adaptive_vsync: bool = true,
    frame_pacing: bool = true,
    cpu_affinity_mask: ?u64 = null,

    // Memory management
    allocator_type: AllocatorType = .general_purpose,
    memory_budget_mb: u64 = 512,
    enable_memory_tracking: bool = builtin.mode == .Debug,
    gc_threshold_mb: u64 = 256,

    // Graphics settings
    renderer_backend: gpu.BackendType = .software,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    fullscreen: bool = false,
    borderless: bool = false,
    always_on_top: bool = false,
    window_title: []const u8 = "Nyx Engine",

    // Quality settings
    shadow_quality: QualityLevel = .high,
    texture_quality: QualityLevel = .high,
    effect_quality: QualityLevel = .high,
    antialiasing: AntialiasingMode = .msaa_4x,
    anisotropic_filtering: u32 = 16,

    // Debug and development
    debug_mode: bool = builtin.mode == .Debug,
    enable_validation: bool = builtin.mode == .Debug,
    enable_profiling: bool = builtin.mode == .Debug,
    enable_hot_reload: bool = build_options.enable_hot_reload,
    log_level: LogLevel = if (builtin.mode == .Debug) .debug else .info,

    // Asset management
    asset_cache_size_mb: u64 = 128,
    async_loading: bool = true,
    texture_streaming: bool = true,
    model_lod_bias: f32 = 0.0,

    // Audio settings
    audio_sample_rate: u32 = 48000,
    audio_buffer_size: u32 = 1024,
    audio_channels: u32 = 2,
    master_volume: f32 = 1.0,

    // Input settings
    mouse_sensitivity: f32 = 1.0,
    keyboard_repeat_delay: u32 = 500,
    gamepad_deadzone: f32 = 0.15,

    pub const AllocatorType = enum {
        general_purpose,
        arena,
        fixed_buffer,
        c_allocator,
        page_allocator,
        stack_fallback,
    };

    pub const QualityLevel = enum(u8) {
        potato = 0,
        low = 1,
        medium = 2,
        high = 3,
        ultra = 4,
        extreme = 5,
    };

    pub const AntialiasingMode = enum {
        none,
        fxaa,
        msaa_2x,
        msaa_4x,
        msaa_8x,
        taa,
        dlaa,
    };

    pub const LogLevel = enum {
        err,
        warn,
        info,
        debug,
    };

    pub fn validate(self: *const Config) !void {
        if (self.target_fps == 0 or self.target_fps > self.max_fps) {
            return error.InvalidFrameRate;
        }
        if (self.window_width == 0 or self.window_height == 0) {
            return error.InvalidWindowDimensions;
        }
        if (self.memory_budget_mb < 64) {
            return error.InsufficientMemoryBudget;
        }
        if (self.master_volume < 0.0 or self.master_volume > 1.0) {
            return error.InvalidAudioVolume;
        }
    }

    pub fn saveToFile(self: *const Config, allocator: std.mem.Allocator, path: []const u8) !void {
        const json_string = try std.json.stringifyAlloc(allocator, self, .{ .whitespace = .indent_2 });
        defer allocator.free(json_string);

        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = json_string });
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file_data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(file_data);

        const parsed = try std.json.parseFromSlice(Config, allocator, file_data, .{});
        defer parsed.deinit();

        const config = parsed.value;
        try config.validate();
        return config;
    }
};

// Parse command-line arguments to create config
pub fn parseConfig(allocator: std.mem.Allocator) !Config {
    var config = Config{};

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip executable path
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--width") or std.mem.eql(u8, arg, "-w")) {
            i += 1;
            if (i < args.len) {
                config.window_width = std.fmt.parseInt(u32, args[i], 10) catch 1280;
            }
        } else if (std.mem.eql(u8, arg, "--height") or std.mem.eql(u8, arg, "-H")) {
            i += 1;
            if (i < args.len) {
                config.window_height = std.fmt.parseInt(u32, args[i], 10) catch 720;
            }
        } else if (std.mem.eql(u8, arg, "--fullscreen") or std.mem.eql(u8, arg, "-f")) {
            config.fullscreen = true;
        } else if (std.mem.eql(u8, arg, "--renderer") or std.mem.eql(u8, arg, "-r")) {
            i += 1;
            if (i < args.len) {
                config.renderer_backend = parseBackend(args[i]);
            }
        } else if (std.mem.eql(u8, arg, "--log-level")) {
            i += 1;
            if (i < args.len) {
                config.log_level = parseLogLevel(args[i]) orelse config.log_level;
            }
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i < args.len) {
                config = try Config.loadFromFile(allocator, args[i]);
            }
        } else if (std.mem.eql(u8, arg, "--vsync")) {
            config.adaptive_vsync = true;
        } else if (std.mem.eql(u8, arg, "--no-vsync")) {
            config.adaptive_vsync = false;
        } else if (std.mem.eql(u8, arg, "--fps")) {
            i += 1;
            if (i < args.len) {
                config.target_fps = std.fmt.parseInt(u32, args[i], 10) catch 60;
            }
        }
    }

    return config;
}

fn printHelp() void {
    std.debug.print(
        \\MFS Engine Usage:
        \\  --help, -h                 Show this help message
        \\  --width, -w WIDTH          Set window width
        \\  --height, -H HEIGHT        Set window height
        \\  --fullscreen, -f           Enable fullscreen mode
        \\  --renderer, -r BACKEND     Set renderer backend (vulkan, opengl, d3d11, d3d12, metal, webgpu, opengles, software)
        \\  --log-level LEVEL          Set log level (error, warn, info, debug)
        \\  --config, -c PATH          Load configuration from file
        \\  --vsync                    Enable VSync (default)
        \\  --no-vsync                 Disable VSync
        \\  --fps FPS                  Set target framerate
        \\
    , .{});
}

test "config validation" {
    var config = Config{};
    try config.validate();

    config.memory_budget_mb = 32;
    try std.testing.expectError(error.InsufficientMemoryBudget, config.validate());

    config.memory_budget_mb = 128;
    config.target_fps = 300;
    config.max_fps = 240;
    try std.testing.expectError(error.InvalidFrameRate, config.validate());
}

fn parseBackend(name: []const u8) gpu.BackendType {
    if (std.mem.eql(u8, name, "vulkan")) return .vulkan;
    if (std.mem.eql(u8, name, "opengl")) return .opengl;
    if (std.mem.eql(u8, name, "d3d11")) return .d3d11;
    if (std.mem.eql(u8, name, "d3d12")) return .d3d12;
    if (std.mem.eql(u8, name, "metal")) return .metal;
    if (std.mem.eql(u8, name, "opengles")) return .opengles;
    if (std.mem.eql(u8, name, "webgpu")) return .webgpu;
    if (std.mem.eql(u8, name, "software")) return .software;
    // Default to software renderer for "auto" or unknown backends
    return .software;
}

fn parseLogLevel(name: []const u8) ?Config.LogLevel {
    if (std.mem.eql(u8, name, "error")) return .err;
    if (std.mem.eql(u8, name, "warn")) return .warn;
    if (std.mem.eql(u8, name, "info")) return .info;
    if (std.mem.eql(u8, name, "debug")) return .debug;
    return null;
}
