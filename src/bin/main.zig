//! MFS Engine Main Module
//! Core application entry point and lifecycle management system
//! @thread-safe Component-level thread safety applies
//! @symbol PublicEngineAPI

const std = @import("std");
const builtin = @import("builtin");
const nyx = @import("../nyx_std.zig");
const build_options = @import("build_options");

// Advanced platform-specific imports with dynamic loading
const platform = @import("../platform/platform.zig");
const Window = @import("../ui/simple_window.zig").Window;

// Performance monitoring and profiling
const tracy = if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy) @import("tracy") else struct {
    pub inline fn traceNamed(comptime name: []const u8) void {
        _ = name;
    }
    pub inline fn frameMarkNamed(comptime name: []const u8) void {
        _ = name;
    }
    pub inline fn plotF64(comptime name: []const u8, value: f64) void {
        _ = name;
        _ = value;
    }
};

// Advanced logging with structured output
const log = std.log.scoped(.main);

// Plugin system architecture
/// @thread-safe Plugin interface with cross-component thread safety
/// @symbol PluginAPI
const PluginInterface = extern struct {
    name: []const u8,
    version: Version,
    init_fn: *const fn (*anyopaque, std.mem.Allocator) anyerror!void,
    deinit_fn: *const fn (*anyopaque) void,
    update_fn: *const fn (*anyopaque, f64) anyerror!void,
    context: *volatile anyopaque,

    const Version = extern struct {
        major: u32,
        minor: u32,
        patch: u32,

        pub fn format(self: Version, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        }
    };
};

// Enhanced configuration with validation and serialization
/// @thread-safe Configuration can be accessed concurrently for reading, but requires exclusive access for writing
/// @symbol Public configuration interface
const Config = struct {
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
    renderer_backend: RendererBackend = .auto,
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

    const AllocatorType = enum {
        general_purpose,
        arena,
        fixed_buffer,
        c_allocator,
        page_allocator,
        stack_fallback,
    };

    const RendererBackend = enum {
        auto,
        vulkan,
        metal,
        dx12,
        webgpu,
        opengl,
        opengles,
        software,
    };

    const QualityLevel = enum(u8) {
        potato = 0,
        low = 1,
        medium = 2,
        high = 3,
        ultra = 4,
        extreme = 5,
    };

    const AntialiasingMode = enum {
        none,
        fxaa,
        msaa_2x,
        msaa_4x,
        msaa_8x,
        taa,
        dlaa,
    };

    const LogLevel = enum {
        err,
        warn,
        info,
        debug,
    };

    /// Validates configuration parameters
    /// @thread-safe Thread-safe validation (performs no mutation)
    /// @symbol Public validation API
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

    /// Saves configuration to a file
    /// @thread-safe Not thread-safe, requires external synchronization
    /// @symbol Public serialization API
    pub fn saveToFile(self: *const Config, allocator: std.mem.Allocator, path: []const u8) !void {
        const json_string = try std.json.stringifyAlloc(allocator, self, .{ .whitespace = .indent_2 });
        defer allocator.free(json_string);

        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(json_string);
    }

    /// Loads configuration from a file
    /// @thread-safe Thread-safe for reading the file, but requires external synchronization for updating shared config
    /// @symbol Public deserialization API
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        // Check if file exists first
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            log.err("Failed to open config file '{s}': {s}", .{ path, @errorName(err) });
            return err;
        };
        defer file.close();

        const file_data = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(file_data);

        const parsed = try std.json.parseFromSlice(Config, allocator, file_data, .{});
        defer parsed.deinit();

        var config = parsed.value;
        try config.validate();
        return config;
    }
};

// Advanced performance monitoring system
/// @thread-safe Thread-safe performance monitoring with internal synchronization
/// @symbol Public performance monitoring interface
const PerformanceMonitor = struct {
    allocator: std.mem.Allocator,
    frame_times: std.RingBuffer,
    memory_usage: std.ArrayList(u64),
    cpu_usage: std.ArrayList(f32),
    gpu_usage: std.ArrayList(f32),
    draw_calls: std.ArrayList(u32),

    start_time: i128,
    last_update: i128,
    sample_interval_ns: i128 = std.time.ns_per_ms * 100, // 100ms sampling

    mutex: std.Thread.Mutex = .{},

    const SAMPLE_COUNT = 1000;

    pub fn init(allocator: std.mem.Allocator) !*PerformanceMonitor {
        const self = try allocator.create(PerformanceMonitor);

        self.* = PerformanceMonitor{
            .allocator = allocator,
            .frame_times = try std.RingBuffer.init(allocator, SAMPLE_COUNT),
            .memory_usage = std.ArrayList(u64).init(allocator),
            .cpu_usage = std.ArrayList(f32).init(allocator),
            .gpu_usage = std.ArrayList(f32).init(allocator),
            .draw_calls = std.ArrayList(u32).init(allocator),
            .start_time = std.time.nanoTimestamp(),
            .last_update = std.time.nanoTimestamp(),
        };

        try self.memory_usage.ensureTotalCapacity(SAMPLE_COUNT);
        try self.cpu_usage.ensureTotalCapacity(SAMPLE_COUNT);
        try self.gpu_usage.ensureTotalCapacity(SAMPLE_COUNT);
        try self.draw_calls.ensureTotalCapacity(SAMPLE_COUNT);

        return self;
    }

    pub fn deinit(self: *PerformanceMonitor, allocator: std.mem.Allocator) void {
        self.frame_times.deinit(allocator);
        self.memory_usage.deinit();
        self.cpu_usage.deinit();
        self.gpu_usage.deinit();
        self.draw_calls.deinit();
    }

    pub fn recordFrame(self: *PerformanceMonitor, frame_time_ns: i128) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.frame_times.writeItem(@as(f64, @floatFromInt(frame_time_ns)) / std.time.ns_per_ms) catch {};

        const current_time = std.time.nanoTimestamp();
        if (current_time - self.last_update >= self.sample_interval_ns) {
            self.updateSystemMetrics();
            self.last_update = current_time;
        }

        tracy.plotF64("Frame Time (ms)", @as(f64, @floatFromInt(frame_time_ns)) / std.time.ns_per_ms);
    }

    fn updateSystemMetrics(self: *PerformanceMonitor) void {
        // Sample memory usage
        const memory_stats = std.heap.page_allocator.queryCapacity();
        self.addSample(&self.memory_usage, memory_stats);

        // Sample CPU usage (simplified)
        const cpu_usage = self.estimateCpuUsage();
        self.addSample(&self.cpu_usage, cpu_usage);

        // GPU usage would require platform-specific APIs
        self.addSample(&self.gpu_usage, 0.0);
        self.addSample(&self.draw_calls, 0);

        tracy.plotF64("Memory (MB)", @as(f64, @floatFromInt(memory_stats)) / (1024.0 * 1024.0));
        tracy.plotF64("CPU Usage (%)", cpu_usage);
    }

    fn addSample(self: *PerformanceMonitor, list: anytype, value: anytype) void {
        _ = self;
        if (list.items.len >= SAMPLE_COUNT) {
            _ = list.orderedRemove(0);
        }
        list.append(value) catch {};
    }

    fn estimateCpuUsage(self: *PerformanceMonitor) f32 {
        _ = self;
        // Simplified CPU usage estimation
        // In a real implementation, this would use platform-specific APIs
        return 0.0;
    }

    pub fn getStats(self: *PerformanceMonitor) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const uptime_ns = std.time.nanoTimestamp() - self.start_time;

        return Stats{
            .uptime_seconds = @as(f64, @floatFromInt(uptime_ns)) / std.time.ns_per_s,
            .average_fps = self.calculateAverageFps(),
            .min_fps = self.calculateMinFps(),
            .max_fps = self.calculateMaxFps(),
            .memory_usage_mb = self.getLatestMemoryUsageMb(),
            .cpu_usage_percent = self.getLatestCpuUsage(),
            .gpu_usage_percent = self.getLatestGpuUsage(),
        };
    }

    const Stats = struct {
        uptime_seconds: f64,
        average_fps: f32,
        min_fps: f32,
        max_fps: f32,
        memory_usage_mb: f64,
        cpu_usage_percent: f32,
        gpu_usage_percent: f32,
    };

    fn calculateAverageFps(self: *PerformanceMonitor) f32 {
        if (self.frame_times.len() == 0) return 0.0;

        var total: f64 = 0.0;
        var it = self.frame_times.iterator();
        while (it.next()) |frame_time| {
            total += frame_time;
        }

        const avg_frame_time = total / @as(f64, @floatFromInt(self.frame_times.len()));
        return if (avg_frame_time > 0) @as(f32, @floatCast(1000.0 / avg_frame_time)) else 0.0;
    }

    fn calculateMinFps(self: *PerformanceMonitor) f32 {
        if (self.frame_times.len() == 0) return 0.0;

        var max_frame_time: f64 = 0.0;
        var it = self.frame_times.iterator();
        while (it.next()) |frame_time| {
            max_frame_time = @max(max_frame_time, frame_time);
        }

        return if (max_frame_time > 0) @as(f32, @floatCast(1000.0 / max_frame_time)) else 0.0;
    }

    fn calculateMaxFps(self: *PerformanceMonitor) f32 {
        if (self.frame_times.len() == 0) return 0.0;

        var min_frame_time: f64 = std.math.inf(f64);
        var it = self.frame_times.iterator();
        while (it.next()) |frame_time| {
            min_frame_time = @min(min_frame_time, frame_time);
        }

        return if (min_frame_time > 0 and min_frame_time != std.math.inf(f64))
            @as(f32, @floatCast(1000.0 / min_frame_time))
        else
            0.0;
    }

    fn getLatestMemoryUsageMb(self: *PerformanceMonitor) f64 {
        if (self.memory_usage.items.len == 0) return 0.0;
        return @as(f64, @floatFromInt(self.memory_usage.items[self.memory_usage.items.len - 1])) / (1024.0 * 1024.0);
    }

    fn getLatestCpuUsage(self: *PerformanceMonitor) f32 {
        if (self.cpu_usage.items.len == 0) return 0.0;
        return self.cpu_usage.items[self.cpu_usage.items.len - 1];
    }

    fn getLatestGpuUsage(self: *PerformanceMonitor) f32 {
        if (self.gpu_usage.items.len == 0) return 0.0;
        return self.gpu_usage.items[self.gpu_usage.items.len - 1];
    }
};

// Advanced application state with sophisticated memory management
const AppState = struct {
    config: Config,
    allocator: std.mem.Allocator,
    tracking_allocator: ?std.heap.GeneralPurposeAllocator(.{ .safety = true }) = null,
    arena: ?std.heap.ArenaAllocator = null,
    fixed_buffer: ?std.heap.FixedBufferAllocator = null,

    window: ?Window = null,
    performance_monitor: ?*PerformanceMonitor = null,
    plugins: std.ArrayList(PluginInterface),
    engine: ?nyx.Engine = null,

    // Advanced timing and frame pacing
    start_time: i128,
    last_frame_time: i128,
    frame_count: std.atomic.Value(u64),
    target_frame_time_ns: i128,
    frame_accumulator: i128 = 0,

    // Statistics and monitoring
    delta_time: f64 = 0.0,
    fps: std.atomic.Value(f32),
    frame_time_ms: std.atomic.Value(f32),

    // Hot reload support
    asset_watcher: ?AssetWatcher = null,
    shader_hot_reload: bool = false,

    // Error handling and resilience
    error_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    last_error: ?anyerror = null,
    recovery_attempts: u32 = 0,

    const AssetWatcher = struct {
        thread: std.Thread,
        should_stop: std.atomic.Value(bool),
        file_times: std.HashMap([]const u8, i128, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
        mutex: std.Thread.Mutex,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, watch_paths: []const []const u8) !AssetWatcher {
            var watcher = AssetWatcher{
                .thread = undefined,
                .should_stop = std.atomic.Value(bool).init(false),
                .file_times = std.HashMap([]const u8, i128, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
                .mutex = std.Thread.Mutex{},
                .allocator = allocator,
            };

            // Initialize file times
            for (watch_paths) |path| {
                const stat = std.fs.cwd().statFile(path) catch continue;
                const key = try allocator.dupe(u8, path);
                try watcher.file_times.put(key, stat.mtime);
            }

            watcher.thread = try std.Thread.spawn(.{}, watchFiles, .{&watcher});
            return watcher;
        }

        pub fn deinit(self: *AssetWatcher) void {
            self.should_stop.store(true, .release);
            self.thread.join();

            var iterator = self.file_times.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.file_times.deinit();
        }

        fn watchFiles(self: *AssetWatcher) void {
            while (!self.should_stop.load(.acquire)) {
                self.checkFileChanges();
                std.time.sleep(std.time.ns_per_ms * 500); // Check every 500ms
            }
        }

        fn checkFileChanges(self: *AssetWatcher) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var iterator = self.file_times.iterator();
            while (iterator.next()) |entry| {
                const path = entry.key_ptr.*;
                const old_time = entry.value_ptr.*;

                const stat = std.fs.cwd().statFile(path) catch continue;
                if (stat.mtime != old_time) {
                    log.info("File changed: {s}", .{path});
                    entry.value_ptr.* = stat.mtime;
                    // Trigger reload event here
                }
            }
        }
    };

    fn init(base_allocator: std.mem.Allocator, config: Config) !AppState {
        var state = AppState{
            .config = config,
            .allocator = undefined,
            .start_time = std.time.nanoTimestamp(),
            .last_frame_time = std.time.nanoTimestamp(),
            .frame_count = std.atomic.Value(u64).init(0),
            .target_frame_time_ns = @divTrunc(std.time.ns_per_s, @as(i128, @intCast(config.target_fps))),
            .fps = std.atomic.Value(f32).init(0.0),
            .frame_time_ms = std.atomic.Value(f32).init(0.0),
            .plugins = std.ArrayList(PluginInterface).init(base_allocator),
        };

        // Setup advanced allocator based on configuration
        switch (config.allocator_type) {
            .general_purpose => {
                if (config.enable_memory_tracking) {
                    state.tracking_allocator = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
                    state.allocator = state.tracking_allocator.?.allocator();
                } else {
                    state.allocator = base_allocator;
                }
            },
            .arena => {
                state.arena = std.heap.ArenaAllocator.init(base_allocator);
                state.allocator = state.arena.?.allocator();
            },
            .fixed_buffer => {
                const buffer_size = config.memory_budget_mb * 1024 * 1024;
                const buffer = try base_allocator.alloc(u8, buffer_size);
                state.fixed_buffer = std.heap.FixedBufferAllocator.init(buffer);
                state.allocator = state.fixed_buffer.?.allocator();
            },
            .c_allocator => {
                state.allocator = std.heap.c_allocator;
            },
            .page_allocator => {
                state.allocator = std.heap.page_allocator;
            },
            .stack_fallback => {
                // This would require more complex setup
                state.allocator = base_allocator;
            },
        }

        // Initialize performance monitoring
        if (config.enable_profiling) {
            state.performance_monitor = try PerformanceMonitor.init(state.allocator);
        }

        // Setup hot reload if enabled
        if (config.enable_hot_reload) {
            const watch_paths = [_][]const u8{
                "src/",
                "shaders/",
                "assets/",
            };
            if (AssetWatcher.init(state.allocator, &watch_paths)) |watcher| {
                state.asset_watcher = watcher;
            } else |err| {
                log.warn("Failed to initialize asset watcher: {}", .{err});
                state.asset_watcher = null;
            }
        }

        return state;
    }

    fn deinit(self: *AppState, base_allocator: std.mem.Allocator) void {
        // Cleanup subsystems
        if (self.engine) |*engine| {
            engine.deinit();
        }

        if (self.window) |*window| {
            window.deinit();
        }

        if (self.performance_monitor) |monitor| {
            monitor.deinit(self.allocator);
        }

        if (self.asset_watcher) |*watcher| {
            watcher.deinit();
        }

        // Cleanup plugins
        for (self.plugins.items) |plugin| {
            plugin.deinit_fn(plugin.context);
        }
        self.plugins.deinit();

        // Cleanup allocators
        switch (self.config.allocator_type) {
            .arena => {
                if (self.arena) |*arena| {
                    arena.deinit();
                }
            },
            .fixed_buffer => {
                if (self.fixed_buffer) |fb| {
                    base_allocator.free(fb.buffer);
                }
            },
            .general_purpose => {
                if (self.tracking_allocator) |*tracker| {
                    const leaked = tracker.deinit();
                    if (leaked == .leak) {
                        log.err("Memory leaks detected during shutdown", .{});
                    }
                }
            },
            else => {},
        }
    }

    fn registerPlugin(self: *AppState, plugin: PluginInterface) !void {
        log.info("Registering plugin: {s} v{}", .{ plugin.name, plugin.version });

        try plugin.init_fn(plugin.context, self.allocator);
        try self.plugins.append(plugin);

        log.info("Plugin {s} registered successfully", .{plugin.name});
    }

    fn updatePlugins(self: *AppState, delta_time: f64) !void {
        for (self.plugins.items) |plugin| {
            plugin.update_fn(plugin.context, delta_time) catch |err| {
                log.err("Plugin {s} update failed: {}", .{ plugin.name, err });
                self.recordError(err);
            };
        }
    }

    fn recordError(self: *AppState, err: anyerror) void {
        _ = self.error_count.fetchAdd(1, .monotonic);
        self.last_error = err;
        log.err("Application error recorded: {}", .{err});
    }

    fn shouldAttemptRecovery(self: *AppState) bool {
        return self.recovery_attempts < 3 and self.error_count.load(.monotonic) < 10;
    }
};

// Enhanced main application entry point
pub fn main() !void {
    tracy.frameMarkNamed("main_start");
    defer tracy.frameMarkNamed("main_end");

    // Initialize high-performance allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = builtin.mode == .Debug,
        .thread_safe = true,
        .enable_memory_limit = true,
    }){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    // Parse enhanced configuration
    const config = parseAdvancedConfig(base_allocator) catch |err| {
        log.err("Failed to parse configuration: {}", .{err});
        return err;
    };

    // Validate configuration
    config.validate() catch |err| {
        log.err("Invalid configuration: {}", .{err});
        return err;
    };

    // Initialize application state with error recovery
    var app_state = AppState.init(base_allocator, config) catch |err| {
        log.err("Failed to initialize application state: {}", .{err});
        return err;
    };
    defer app_state.deinit(base_allocator);

    // Print enhanced startup banner
    try printEnhancedBanner(config);

    // Setup CPU affinity if specified
    if (config.cpu_affinity_mask) |mask| {
        setCpuAffinity(mask) catch |err| {
            log.warn("Failed to set CPU affinity: {}", .{err});
        };
    }

    // Initialize platform with advanced features
    try platform.init(app_state.allocator);
    defer platform.deinit();

    // Create window with enhanced options
    if (!isHeadless()) {
        app_state.window = Window.init(app_state.allocator, .{
            .title = config.window_title,
            .width = config.window_width,
            .height = config.window_height,
            .resizable = true,
            .fullscreen = config.fullscreen,
            .borderless = config.borderless,
            .always_on_top = config.always_on_top,
            .vsync = config.adaptive_vsync,
        }) catch |err| {
            log.err("Failed to create window: {}", .{err});
            if (app_state.shouldAttemptRecovery()) {
                log.info("Attempting recovery with fallback window settings...", .{});
                app_state.recovery_attempts += 1;
                // Try with basic settings
                app_state.window = Window.init(app_state.allocator, .{
                    .title = "Nyx Engine (Safe Mode)",
                    .width = 800,
                    .height = 600,
                    .resizable = true,
                }) catch {
                    return err;
                };
            } else {
                return err;
            }
        };
    }

    // Initialize Nyx engine with comprehensive configuration
    app_state.engine = nyx.Engine.init(app_state.allocator, .{
        .enable_gpu = config.enable_gpu,
        .enable_physics = config.enable_physics,
        .enable_neural = config.enable_neural,
        .enable_xr = config.enable_xr,
        .enable_audio = config.enable_audio,
        .enable_networking = config.enable_networking,
        .backend = @intFromEnum(config.renderer_backend),
        .window_handle = if (app_state.window) |w| w.getNativeHandle() else null,
        .window_width = config.window_width,
        .window_height = config.window_height,
        .enable_validation = config.enable_validation,
        .enable_debug_allocator = config.enable_memory_tracking,
        .max_memory_budget_mb = config.memory_budget_mb,
        .target_fps = config.target_fps,
        .enable_frame_pacing = config.frame_pacing,
        .shadow_quality = @intFromEnum(config.shadow_quality),
        .texture_quality = @intFromEnum(config.texture_quality),
        .antialiasing = @intFromEnum(config.antialiasing),
    }) catch |err| {
        log.err("Failed to initialize Nyx engine: {}", .{err});
        app_state.recordError(err);
        if (app_state.shouldAttemptRecovery()) {
            log.info("Attempting engine recovery with safe settings...");
            app_state.recovery_attempts += 1;
            // Try with minimal settings
            app_state.engine = nyx.Engine.init(app_state.allocator, .{
                .enable_gpu = false,
                .enable_physics = false,
                .enable_neural = false,
                .enable_xr = false,
                .backend = @intFromEnum(Config.RendererBackend.software),
            }) catch return err;
        } else {
            return err;
        }
    };

    // Load and register plugins
    try loadPlugins(&app_state);

    log.info("Nyx Engine initialized successfully", .{});
    log.info("Configuration: {s} allocator, {d} FPS target", .{ @tagName(config.allocator_type), config.target_fps });
    log.info("Features: GPU={}, Physics={}, Neural={}, XR={}", .{ config.enable_gpu, config.enable_physics, config.enable_neural, config.enable_xr });

    // Save current configuration
    config.saveToFile(app_state.allocator, "config.json") catch |err| {
        log.warn("Failed to save configuration: {}", .{err});
    };

    // Main execution loop with enhanced error handling
    mainLoop(&app_state) catch |err| {
        log.err("Main loop error: {}", .{err});
        app_state.recordError(err);

        // Attempt graceful recovery
        if (app_state.shouldAttemptRecovery()) {
            log.info("Attempting main loop recovery...");
            app_state.recovery_attempts += 1;
            safeMainLoop(&app_state) catch return err;
        } else {
            return err;
        }
    };

    // Print comprehensive shutdown statistics
    printShutdownStats(&app_state);
}

// Enhanced main execution loop with adaptive frame pacing
fn mainLoop(app_state: *AppState) !void {
    tracy.frameMarkNamed("main_loop_start");
    defer tracy.frameMarkNamed("main_loop_end");

    const target_frame_time_ns = app_state.target_frame_time_ns;
    var accumulator: i128 = 0;
    var last_performance_report = std.time.nanoTimestamp();
    const performance_report_interval = std.time.ns_per_s * 10; // 10 seconds

    while (true) {
        tracy.traceNamed("main_loop_iteration");

        const frame_start = std.time.nanoTimestamp();
        const frame_time = std.math.max(0, frame_start - app_state.last_frame_time); // Ensure non-negative frame time
        app_state.last_frame_time = frame_start;

        accumulator += frame_time;

        // Process window events with error recovery
        if (app_state.window) |*window| {
            window.pollEvents() catch |err| {
                log.err("Failed to poll window events: {}", .{err});
                app_state.recordError(err);
                if (!app_state.shouldAttemptRecovery()) return err;
                app_state.error_count = 0; // Reset error count on successful recovery
                continue; // Skip rest of frame on recovery
            };
            if (window.shouldClose()) {
                log.info("Window close requested");
                break;
            }
        }

        // Check for hot reload events
        if (app_state.asset_watcher) |*watcher| {
            _ = watcher; // Hot reload logic would go here
        }

        // Fixed timestep update with plugin support
        const fixed_dt: f64 = @as(f64, @floatFromInt(target_frame_time_ns)) / std.time.ns_per_s;
        while (accumulator >= target_frame_time_ns) {
            tracy.traceNamed("fixed_update");

            // Update engine subsystems
            if (app_state.engine) |*engine| {
                engine.update(fixed_dt) catch |err| {
                    log.err("Engine update failed: {}", .{err});
                    app_state.recordError(err);
                    if (!app_state.shouldAttemptRecovery()) return err;
                    app_state.error_count = 0; // Reset error count on successful recovery
                    break; // Exit update loop on recovery
                };
            }

            // Update plugins
            app_state.updatePlugins(fixed_dt) catch |err| {
                log.warn("Plugin update failed: {}", .{err});
                app_state.recordError(err);
            };

            accumulator = std.math.max(0, accumulator - target_frame_time_ns); // Prevent negative accumulator
        }

        // Render frame with interpolation
        if (app_state.engine) |*engine| {
            tracy.traceNamed("render");

            const alpha = if (target_frame_time_ns > 0)
                @as(f32, @floatFromInt(accumulator)) / @as(f32, @floatFromInt(target_frame_time_ns))
            else
                0.0;

            engine.render(alpha) catch |err| {
                log.err("Engine render failed: {}", .{err});
                app_state.recordError(err);
                if (!app_state.shouldAttemptRecovery()) return err;
                app_state.error_count = 0; // Reset error count on successful recovery
                continue; // Skip frame timing on recovery
            };
        }

        // Update frame statistics
        const frame_end = std.time.nanoTimestamp();
        const total_frame_time = frame_end - frame_start;

        _ = app_state.frame_count.fetchAdd(1, .monotonic);
        updateFrameStatistics(app_state, total_frame_time);

        // Record performance metrics
        if (app_state.performance_monitor) |monitor| {
            monitor.recordFrame(total_frame_time);
        }

        // Periodic performance reporting
        if (frame_start - last_performance_report >= performance_report_interval) {
            reportPerformanceStats(app_state);
            last_performance_report = frame_start;
        }

        // Adaptive frame pacing
        if (app_state.config.frame_pacing) {
            const elapsed = frame_end - frame_start;
            if (elapsed < target_frame_time_ns) {
                const sleep_time = target_frame_time_ns - elapsed;
                if (sleep_time > 0) {
                    std.time.sleep(@intCast(sleep_time));
                }
            }
        }

        tracy.frameMarkNamed("frame_end");
    }
}

// Safe main loop for error recovery
fn safeMainLoop(app_state: *AppState) !void {
    log.info("Running in safe mode with reduced features");

    var frame_count: u64 = 0;
    const start_time = std.time.nanoTimestamp();

    while (frame_count < 1000) { // Limited iterations in safe mode
        if (app_state.window) |*window| {
            window.pollEvents() catch break;
            if (window.shouldClose()) break;
        }

        // Minimal update cycle
        std.time.sleep(std.time.ns_per_ms * 16); // ~60 FPS
        frame_count += 1;

        if (frame_count % 60 == 0) {
            log.info("Safe mode frame: {}", .{frame_count});
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / std.time.ns_per_s;
    log.info("Safe mode completed: {} frames in {d:.2}s", .{ frame_count, duration });
}

fn updateFrameStatistics(app_state: *AppState, frame_time_ns: i128) void {
    const frame_time_ms = @as(f32, @floatFromInt(frame_time_ns)) / std.time.ns_per_ms;
    const fps = if (frame_time_ns > 0) std.time.ns_per_s / @as(f32, @floatFromInt(frame_time_ns)) else 0.0;

    app_state.frame_time_ms.store(frame_time_ms, .monotonic);
    app_state.fps.store(fps, .monotonic);

    if (app_state.config.debug_mode and app_state.frame_count.load(.monotonic) % 60 == 0) {
        log.debug("Performance: {d:.1} FPS, {d:.2}ms frame time", .{ fps, frame_time_ms });
    }
}

fn reportPerformanceStats(app_state: *AppState) void {
    if (app_state.performance_monitor) |monitor| {
        const stats = monitor.getStats();
        log.info("Performance Report:", .{});
        log.info("  Uptime: {d:.1}s", .{stats.uptime_seconds});
        log.info("  Average FPS: {d:.1}", .{stats.average_fps});
        log.info("  FPS Range: {d:.1} - {d:.1}", .{ stats.min_fps, stats.max_fps });
        log.info("  Memory: {d:.1} MB", .{stats.memory_usage_mb});
        log.info("  CPU: {d:.1}%", .{stats.cpu_usage_percent});

        tracy.plotF64("Average FPS", stats.average_fps);
        tracy.plotF64("Memory Usage (MB)", stats.memory_usage_mb);
    }
}

fn parseAdvancedConfig(allocator: std.mem.Allocator) !Config {
    var config = Config{};

    // Parse command line arguments (override file settings)
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--headless")) {
            config.enable_gpu = false;
        } else if (std.mem.eql(u8, arg, "--no-physics")) {
            config.enable_physics = false;
        } else if (std.mem.eql(u8, arg, "--enable-neural")) {
            config.enable_neural = true;
        } else if (std.mem.eql(u8, arg, "--enable-xr")) {
            config.enable_xr = true;
        } else if (std.mem.eql(u8, arg, "--enable-audio")) {
            config.enable_audio = true;
        } else if (std.mem.eql(u8, arg, "--enable-networking")) {
            config.enable_networking = true;
        } else if (std.mem.startsWith(u8, arg, "--fps=")) {
            const fps_str = arg[6..];
            config.target_fps = std.fmt.parseInt(u32, fps_str, 10) catch blk: {
                log.warn("Invalid FPS value '{s}', using default", .{fps_str});
                break :blk config.target_fps;
            };
        } else if (std.mem.startsWith(u8, arg, "--memory=")) {
            const mem_str = arg[9..];
            config.memory_budget_mb = std.fmt.parseInt(u64, mem_str, 10) catch blk: {
                log.warn("Invalid memory value '{s}', using default", .{mem_str});
                break :blk config.memory_budget_mb;
            };
        } else if (std.mem.eql(u8, arg, "--allocator=arena")) {
            config.allocator_type = .arena;
        } else if (std.mem.eql(u8, arg, "--allocator=fixed")) {
            config.allocator_type = .fixed_buffer;
        } else if (std.mem.eql(u8, arg, "--allocator=c")) {
            config.allocator_type = .c_allocator;
        } else if (std.mem.eql(u8, arg, "--allocator=page")) {
            config.allocator_type = .page_allocator;
        } else if (std.mem.eql(u8, arg, "--renderer=vulkan")) {
            config.renderer_backend = .vulkan;
        } else if (std.mem.eql(u8, arg, "--renderer=opengl")) {
            config.renderer_backend = .opengl;
        } else if (std.mem.eql(u8, arg, "--renderer=software")) {
            config.renderer_backend = .software;
        } else if (std.mem.eql(u8, arg, "--fullscreen")) {
            config.fullscreen = true;
        } else if (std.mem.eql(u8, arg, "--borderless")) {
            config.borderless = true;
        } else if (std.mem.eql(u8, arg, "--no-validation")) {
            config.enable_validation = false;
        } else if (std.mem.eql(u8, arg, "--no-profiling")) {
            config.enable_profiling = false;
        } else if (std.mem.startsWith(u8, arg, "--width=")) {
            const width_str = arg[8..];
            config.window_width = std.fmt.parseInt(u32, width_str, 10) catch config.window_width;
        } else if (std.mem.startsWith(u8, arg, "--height=")) {
            const height_str = arg[9..];
            config.window_height = std.fmt.parseInt(u32, height_str, 10) catch config.window_height;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            std.process.exit(0);
        }
    }

    return config;
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Nyx Engine - Advanced Runtime Framework\n\n", .{});
    try stdout.print("Usage: nyx [OPTIONS]\n\n", .{});
    try stdout.print("OPTIONS:\n", .{});
    try stdout.print("  --headless              Disable GPU rendering\n", .{});
    try stdout.print("  --no-physics            Disable physics engine\n", .{});
    try stdout.print("  --enable-neural         Enable neural networks\n", .{});
    try stdout.print("  --enable-xr             Enable XR support\n", .{});
    try stdout.print("  --no-gui                Disable GUI system\n", .{});
    try stdout.print("  --enable-networking     Enable networking\n", .{});
    try stdout.print("  --fps=N                 Set target FPS (default: 60)\n", .{});
    try stdout.print("  --memory=N              Set memory budget in MB (default: 512)\n", .{});
    try stdout.print("  --allocator=TYPE        Set allocator type (gpa|arena|fixed|c|page)\n", .{});
    try stdout.print("  --renderer=TYPE         Set renderer backend (auto|vulkan|opengl|software)\n", .{});
    try stdout.print("  --width=N               Set window width (default: 1280)\n", .{});
    try stdout.print("  --height=N              Set window height (default: 720)\n", .{});
    try stdout.print("  --fullscreen            Start in fullscreen mode\n", .{});
    try stdout.print("  --borderless            Borderless window\n", .{});
    try stdout.print("  --no-validation         Disable debug validation\n", .{});
    try stdout.print("  --no-profiling          Disable performance profiling\n", .{});
    try stdout.print("  --help, -h              Show this help message\n", .{});
}

fn printEnhancedBanner(config: Config) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    try stdout.print("███╗   ██╗██╗   ██╗██╗  ██╗     ███████╗███╗   ██╗ ██████╗ ██╗███╗   ██╗███████╗\n", .{});
    try stdout.print("████╗  ██║╚██╗ ██╔╝╚██╗██╔╝     ██╔════╝████╗  ██║██╔════╝ ██║████╗  ██║██╔════╝\n", .{});
    try stdout.print("██╔██╗ ██║ ╚████╔╝  ╚███╔╝      █████╗  ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║█████╗  \n", .{});
    try stdout.print("██║╚██╗██║  ╚██╔╝   ██╔██╗      ██╔══╝  ██║╚██╗██║██║   ██║██║██║╚██╗██║██╔══╝  \n", .{});
    try stdout.print("██║ ╚████║   ██║   ██╔╝ ██╗     ███████╗██║ ╚████║╚██████╔╝██║██║ ╚████║███████╗\n", .{});
    try stdout.print("╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝\n", .{});
    try stdout.print("\n", .{});
    try stdout.print("Nyx Engine — Advanced Hyper‑Modular Runtime Framework v1.0.0\n", .{});
    try stdout.print("══════════════════════════════════════════════════════════════════════════════\n", .{});

    // Core Systems
    try stdout.print("CORE SYSTEMS:\n", .{});
    try stdout.print("  GPU Rendering:     {s:>12}\n", .{if (config.enable_gpu) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Physics Engine:    {s:>12}\n", .{if (config.enable_physics) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Neural Networks:   {s:>12}\n", .{if (config.enable_neural) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  XR Support:        {s:>12}\n", .{if (config.enable_xr) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Audio System:      {s:>12}\n", .{if (config.enable_audio) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Networking:        {s:>12}\n", .{if (config.enable_networking) "✓ Enabled" else "✗ Disabled"});

    try stdout.print("\nPERFORMANCE:\n", .{});
    try stdout.print("  Target FPS:        {d:>12}\n", .{config.target_fps});
    try stdout.print("  Max FPS:           {d:>12}\n", .{config.max_fps});
    try stdout.print("  Frame Pacing:      {s:>12}\n", .{if (config.frame_pacing) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Adaptive VSync:    {s:>12}\n", .{if (config.adaptive_vsync) "✓ Enabled" else "✗ Disabled"});

    try stdout.print("\nMEMORY:\n", .{});
    try stdout.print("  Allocator Type:    {s:>12}\n", .{@tagName(config.allocator_type)});
    try stdout.print("  Memory Budget:     {d:>9} MB\n", .{config.memory_budget_mb});
    try stdout.print("  Memory Tracking:   {s:>12}\n", .{if (config.enable_memory_tracking) "✓ Enabled" else "✗ Disabled"});

    try stdout.print("\nGRAPHICS:\n", .{});
    try stdout.print("  Renderer Backend:  {s:>12}\n", .{@tagName(config.renderer_backend)});
    try stdout.print("  Resolution:        {d}x{d:>7}\n", .{ config.window_width, config.window_height });
    try stdout.print("  Fullscreen:        {s:>12}\n", .{if (config.fullscreen) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Shadow Quality:    {s:>12}\n", .{@tagName(config.shadow_quality)});
    try stdout.print("  Antialiasing:      {s:>12}\n", .{@tagName(config.antialiasing)});

    try stdout.print("\nDEVELOPMENT:\n", .{});
    try stdout.print("  Debug Mode:        {s:>12}\n", .{if (config.debug_mode) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Validation:        {s:>12}\n", .{if (config.enable_validation) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Profiling:         {s:>12}\n", .{if (config.enable_profiling) "✓ Enabled" else "✗ Disabled"});
    try stdout.print("  Hot Reload:        {s:>12}\n", .{if (config.enable_hot_reload) "✓ Enabled" else "✗ Disabled"});

    try stdout.print("══════════════════════════════════════════════════════════════════════════════\n", .{});
    try stdout.print("Build: {s} | Vulkan: {s} | Platform: {s}\n", .{ @tagName(builtin.mode), if (build_options.vulkan_available) "Available" else "Unavailable", @tagName(builtin.target.os.tag) });
    try stdout.print("══════════════════════════════════════════════════════════════════════════════\n\n", .{});
}

fn setCpuAffinity(mask: u64) !void {
    _ = mask;
    // Platform-specific CPU affinity implementation would go here
    log.info("CPU affinity setting not implemented for this platform", .{});
}

fn loadPlugins(app_state: *AppState) !void {
    _ = app_state;
    // Example plugin loading system
    log.info("Loading plugins...");

    // In a real implementation, this would scan a plugins directory
    // and dynamically load shared libraries

    log.info("Plugin system initialized (no plugins loaded)");
}

fn printShutdownStats(app_state: *AppState) void {
    const end_time = std.time.nanoTimestamp();
    const total_time = @as(f64, @floatFromInt(end_time - app_state.start_time)) / std.time.ns_per_s;
    const total_frames = app_state.frame_count.load(.monotonic);
    const avg_fps = if (total_time > 0) @as(f64, @floatFromInt(total_frames)) / total_time else 0.0;
    const final_fps = app_state.fps.load(.monotonic);
    const errors = app_state.error_count.load(.monotonic);

    log.info("════════════════════════════════════════");
    log.info("         SHUTDOWN STATISTICS            ");
    log.info("════════════════════════════════════════");
    log.info("Total Runtime:      {d:.2} seconds", .{total_time});
    log.info("Total Frames:       {d}", .{total_frames});
    log.info("Average FPS:        {d:.2}", .{avg_fps});
    log.info("Final FPS:          {d:.1}", .{final_fps});
    log.info("Error Count:        {d}", .{errors});
    log.info("Recovery Attempts:  {d}", .{app_state.recovery_attempts});

    if (app_state.performance_monitor) |monitor| {
        const stats = monitor.getStats();
        log.info("Memory Peak:        {d:.1} MB", .{stats.memory_usage_mb});
        log.info("FPS Range:          {d:.1} - {d:.1}", .{ stats.min_fps, stats.max_fps });
    }

    if (app_state.last_error) |err| {
        log.info("Last Error:         {}", .{err});
    }

    log.info("════════════════════════════════════════");
    log.info("Shutdown completed successfully");
}

fn isHeadless() bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.argsWithAllocator(allocator) catch return false;
    defer args.deinit();
    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--headless")) {
            return true;
        }
    }
    return false;
}

// Enhanced test suite
test "enhanced configuration validation" {
    const testing = std.testing;

    // Test valid configuration
    const valid_config = Config{
        .target_fps = 60,
        .window_width = 1920,
        .window_height = 1080,
        .memory_budget_mb = 512,
        .master_volume = 0.8,
    };
    try valid_config.validate();

    // Test invalid frame rate
    const invalid_fps_config = Config{
        .target_fps = 0,
        .max_fps = 60,
    };
    try testing.expectError(error.InvalidFrameRate, invalid_fps_config.validate());

    // Test invalid dimensions
    const invalid_dims_config = Config{
        .window_width = 0,
        .window_height = 1080,
    };
    try testing.expectError(error.InvalidWindowDimensions, invalid_dims_config.validate());
}

test "performance monitor functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var monitor = try PerformanceMonitor.init(allocator);
    defer monitor.deinit();

    // Record some frames
    monitor.recordFrame(16 * std.time.ns_per_ms); // 16ms = ~60 FPS
    monitor.recordFrame(33 * std.time.ns_per_ms); // 33ms = ~30 FPS

    const stats = monitor.getStats();
    try testing.expect(stats.average_fps > 0);
    try testing.expect(stats.uptime_seconds >= 0);
}

test "application state lifecycle" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const config = Config{};

    var app_state = try AppState.init(allocator, config);
    defer app_state.deinit(allocator);

    try testing.expectEqual(@as(u64, 0), app_state.frame_count.load(.monotonic));
    try testing.expect(app_state.start_time > 0);
    try testing.expectEqual(@as(u32, 0), app_state.error_count.load(.monotonic));
}

test "plugin interface validation" {
    const testing = std.testing;

    const TestPlugin = struct {
        value: i32 = 42,

        fn init(ctx: *anyopaque, allocator: std.mem.Allocator) !void {
            _ = allocator;
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.value = 100;
        }

        fn deinit(ctx: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.value = 0;
        }

        fn update(ctx: *anyopaque, dt: f64) !void {
            _ = dt;
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.value += 1;
        }
    };

    var test_plugin = TestPlugin{};
    const plugin = PluginInterface{
        .name = "test_plugin",
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .init_fn = TestPlugin.init,
        .deinit_fn = TestPlugin.deinit,
        .update_fn = TestPlugin.update,
        .context = &test_plugin,
    };

    try plugin.init_fn(plugin.context, testing.allocator);
    try testing.expectEqual(@as(i32, 100), test_plugin.value);

    try plugin.update_fn(plugin.context, 0.016);
    try testing.expectEqual(@as(i32, 101), test_plugin.value);

    plugin.deinit_fn(plugin.context);
    try testing.expectEqual(@as(i32, 0), test_plugin.value);
}
