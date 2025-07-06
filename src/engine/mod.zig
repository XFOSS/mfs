//! Engine Module
//! Main application framework and engine coordination

const std = @import("std");
const core = @import("../core/mod.zig");
const graphics = @import("../graphics/mod.zig");
const audio = @import("../audio/mod.zig");
const physics = @import("../physics/mod.zig");
const scene = @import("../scene/mod.zig");
const window = @import("../window/mod.zig");
const input = @import("../input/mod.zig");
const build_options = @import("../build_options.zig");

// =============================================================================
// Stub Systems (temporary implementations)
// =============================================================================

/// Temporary physics system stub until full physics integration
const PhysicsSystemStub = struct {
    pub fn update(self: *PhysicsSystemStub, delta_time: f64) !void {
        _ = self;
        _ = delta_time;
        // TODO: Implement physics update
    }
};

/// Temporary scene system stub until full scene system integration
const SceneSystemStub = struct {
    pub fn update(self: *SceneSystemStub, delta_time: f64) !void {
        _ = self;
        _ = delta_time;
        // TODO: Implement scene update
    }

    pub fn render(self: *SceneSystemStub, graphics_system: *graphics.GraphicsSystem) !void {
        _ = self;
        _ = graphics_system;
        // TODO: Implement scene rendering
    }
};

/// Temporary input system stub until full input integration
const InputSystemStub = struct {
    pub fn update(self: *InputSystemStub) !void {
        _ = self;
        // TODO: Implement input update
    }
};

// =============================================================================
// Configuration and Statistics
// =============================================================================

/// Application configuration
pub const Config = struct {
    // Window configuration
    enable_window: bool = true,
    window_width: u32 = build_options.Graphics.default_width,
    window_height: u32 = build_options.Graphics.default_height,
    window_title: []const u8 = build_options.Version.engine_name,
    window_resizable: bool = true,
    window_fullscreen: bool = false,

    // Graphics configuration
    enable_graphics: bool = true,
    graphics_backend: graphics.BackendType = .auto,
    enable_validation: bool = build_options.Features.enable_validation,
    enable_vsync: bool = build_options.Graphics.default_vsync,

    // Audio configuration
    enable_audio: bool = build_options.Features.enable_audio,
    audio_sample_rate: u32 = 44100,
    audio_buffer_size: u32 = 1024,
    enable_3d_audio: bool = build_options.Features.enable_3d_audio,

    // Physics configuration
    enable_physics: bool = build_options.Features.enable_physics,

    // Performance configuration
    target_fps: u32 = build_options.Performance.target_frame_rate,
    enable_frame_limiting: bool = true,

    /// Backward compatibility method for creating default config
    pub fn default() Config {
        return Config{};
    }

    /// Validate configuration (backward compatibility)
    pub fn validate(self: *const Config) !void {
        if (self.window_width == 0 or self.window_height == 0) {
            return error.InvalidWindowSize;
        }
        if (self.target_fps > 500) {
            return error.InvalidTargetFPS;
        }
        if (self.audio_sample_rate < 8000 or self.audio_sample_rate > 192000) {
            return error.InvalidAudioSampleRate;
        }
    }
};

/// Application statistics
pub const Stats = struct {
    frame_count: u64,
    fps: f64,
    elapsed_time: f64,
    memory_stats: core.memory.MemoryStats,
};

// =============================================================================
// Main Application Class
// =============================================================================

/// Main application class that coordinates all engine systems
pub const Application = struct {
    allocator: std.mem.Allocator,
    config: Config,

    // Core systems
    memory_manager: core.memory.MemoryManager,
    time_system: core.time.Time,
    event_system: core.events.EventSystem,

    // Major subsystems
    window_system: ?*window.WindowSystem = null,
    graphics_system: ?*graphics.GraphicsSystem = null,
    audio_system: ?*audio.AudioSystem = null,
    physics_system: ?*PhysicsSystemStub = null,
    scene_system: ?*SceneSystemStub = null,
    input_system: ?*InputSystemStub = null,

    // State
    is_running: bool = false,
    frame_count: u64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Self {
        const app = try allocator.create(Self);
        errdefer allocator.destroy(app);

        app.* = Self{
            .allocator = allocator,
            .config = config,
            .memory_manager = try core.memory.MemoryManager.init(),
            .time_system = core.time.Time.init(),
            .event_system = core.events.EventSystem.init(allocator, core.events.EventSystem.Config{}),
        };

        // Initialize subsystems based on configuration
        try app.initializeSubsystems();

        app.is_running = true;
        return app;
    }

    pub fn deinit(self: *Self) void {
        self.is_running = false;

        // Deinitialize subsystems in reverse order
        if (self.input_system) |sys| {
            self.allocator.destroy(sys);
            self.input_system = null;
        }

        if (self.scene_system) |sys| {
            self.allocator.destroy(sys);
            self.scene_system = null;
        }

        if (self.physics_system) |sys| {
            self.allocator.destroy(sys);
            self.physics_system = null;
        }

        if (self.audio_system) |sys| {
            audio.deinit(sys);
            self.audio_system = null;
        }

        if (self.graphics_system) |sys| {
            sys.deinit();
            self.allocator.destroy(sys);
            self.graphics_system = null;
        }

        if (self.window_system) |sys| {
            sys.deinit();
            self.allocator.destroy(sys);
            self.window_system = null;
        }

        self.event_system.deinit();
        self.memory_manager.deinit();

        // Note: Don't destroy self here - that's the responsibility of the caller
    }

    /// Main application loop
    pub fn run(self: *Self) !void {
        while (self.is_running) {
            try self.update();
            try self.render();

            // Handle frame rate limiting
            if (self.config.target_fps > 0) {
                const target_frame_time = 1.0 / @as(f64, @floatFromInt(self.config.target_fps));
                const current_frame_time = self.time_system.getDeltaTime();
                if (current_frame_time < target_frame_time) {
                    const sleep_time = target_frame_time - current_frame_time;
                    std.time.sleep(@intFromFloat(sleep_time * std.time.ns_per_s));
                }
            }
        }
    }

    /// Update all systems
    pub fn update(self: *Self) !void {
        // Update time
        self.time_system.update();
        const delta_time = self.time_system.getDeltaTime();

        // Process events
        self.event_system.processQueue() catch |err| {
            std.log.warn("Event system processing failed: {}", .{err});
        };

        // Update window and input
        if (self.window_system) |sys| {
            try sys.update();

            // Check for quit request
            if (sys.shouldQuit()) {
                self.is_running = false;
                return;
            }
        }

        if (self.input_system) |sys| {
            try sys.update();
        }

        // Update game systems
        if (self.physics_system) |sys| {
            try sys.update(delta_time);
        }

        if (self.audio_system) |sys| {
            try sys.update(delta_time);
        }

        if (self.scene_system) |sys| {
            try sys.update(delta_time);
        }

        self.frame_count += 1;
    }

    /// Render frame
    pub fn render(self: *Self) !void {
        if (self.graphics_system) |graphics_sys| {
            try graphics_sys.beginFrame();

            if (self.scene_system) |scene_sys| {
                try scene_sys.render(graphics_sys);
            }

            try graphics_sys.endFrame();
        }
    }

    /// Get application statistics
    pub fn getStats(self: *const Self) Stats {
        return Stats{
            .frame_count = self.frame_count,
            .fps = self.time_system.getFPS(),
            .elapsed_time = self.time_system.getElapsedTime(),
            .memory_stats = self.memory_manager.getStats(),
        };
    }

    /// Request application shutdown
    pub fn quit(self: *Self) void {
        self.is_running = false;
    }

    fn initializeSubsystems(self: *Self) !void {
        // Initialize window system
        if (self.config.enable_window) {
            const window_config = window.Config{
                .width = self.config.window_width,
                .height = self.config.window_height,
                .title = self.config.window_title,
                .resizable = self.config.window_resizable,
                .fullscreen = self.config.window_fullscreen,
            };

            self.window_system = try window.WindowSystem.init(self.allocator, window_config);
        }

        // Initialize graphics system
        if (self.config.enable_graphics and self.window_system != null) {
            const graphics_config = graphics.Config{
                .backend_type = self.config.graphics_backend,
                .enable_validation = self.config.enable_validation,
                .vsync = self.config.enable_vsync,
            };

            self.graphics_system = try self.allocator.create(graphics.GraphicsSystem);
            self.graphics_system.?.* = try graphics.GraphicsSystem.init(self.allocator, graphics_config);
        }

        // Initialize audio system
        if (self.config.enable_audio) {
            const audio_config = audio.Config{
                .sample_rate = self.config.audio_sample_rate,
                .buffer_size = self.config.audio_buffer_size,
                .enable_3d_audio = self.config.enable_3d_audio,
            };

            self.audio_system = try audio.init(self.allocator, audio_config);
        }

        // Initialize physics system (stub for now)
        if (self.config.enable_physics) {
            self.physics_system = try self.allocator.create(PhysicsSystemStub);
            self.physics_system.?.* = PhysicsSystemStub{};
        }

        // Initialize scene system (stub for now)
        self.scene_system = try self.allocator.create(SceneSystemStub);
        self.scene_system.?.* = SceneSystemStub{};

        // Initialize input system (stub for now)
        self.input_system = try self.allocator.create(InputSystemStub);
        self.input_system.?.* = InputSystemStub{};
    }
};

// =============================================================================
// Public API
// =============================================================================

/// Create default application configuration
pub fn createDefaultConfig() Config {
    return Config{};
}

/// Initialize the engine with custom configuration
pub fn init(allocator: std.mem.Allocator, config: Config) !*Application {
    return try Application.init(allocator, config);
}

/// Initialize the engine with default configuration
pub fn initDefault(allocator: std.mem.Allocator) !*Application {
    return try Application.init(allocator, createDefaultConfig());
}

/// Cleanup the engine
pub fn deinit(app: *Application) void {
    const allocator = app.allocator;
    app.deinit();
    allocator.destroy(app);
}

// =============================================================================
// Tests
// =============================================================================

test "engine module" {
    std.testing.refAllDecls(@This());
}

test "application creation and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = createDefaultConfig();
    const app = try init(gpa.allocator(), config);
    defer deinit(app);

    try std.testing.expect(app.is_running);
    try std.testing.expect(app.frame_count == 0);
}
