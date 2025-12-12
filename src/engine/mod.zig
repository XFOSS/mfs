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
const ai = @import("../ai/mod.zig");
const networking = @import("../networking/mod.zig");
const build_options = @import("../build_options.zig");

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

    // AI configuration
    enable_ai: bool = build_options.Features.enable_ai,
    ai_update_rate: f32 = 60.0, // Updates per second

    // Networking configuration
    enable_networking: bool = false, // Disabled by default (optional)
    network_mode: networking.NetworkMode = .client,

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

// Engine errors
pub const EngineError = error{
    GraphicsRequiresWindow,
    InputRequiresWindow,
    SystemInitializationFailed,
    InvalidWindowSize,
    InvalidTargetFPS,
    InvalidAudioSampleRate,
};

/// Application statistics
pub const Stats = struct {
    frame_count: u64,
    fps: f64,
    elapsed_time: f64,
    memory_stats: core.memory.MemoryStats,
    physics_objects: u32 = 0,
    audio_sources: u32 = 0,
    ai_entities: u32 = 0,
    network_connections: u32 = 0,
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
    physics_system: ?*physics.PhysicsEngine = null,
    scene_system: ?*scene.Scene = null,
    input_system: ?*input.InputSystem = null,
    ai_system: ?*ai.AISystem = null,
    network_manager: ?*networking.NetworkManager = null,

    // State
    is_running: bool = false,
    frame_count: u64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Self {
        // Validate configuration
        try config.validate();

        // Validate dependencies
        if (config.enable_graphics and !config.enable_window) {
            return error.GraphicsRequiresWindow;
        }
        if (config.enable_input and !config.enable_window) {
            return error.InputRequiresWindow;
        }

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
        if (self.network_manager) |sys| {
            sys.deinit();
            self.allocator.destroy(sys);
            self.network_manager = null;
        }

        if (self.ai_system) |sys| {
            sys.deinit();
            self.allocator.destroy(sys);
            self.ai_system = null;
        }

        if (self.input_system) |sys| {
            input.deinit(sys);
            self.allocator.destroy(sys);
            self.input_system = null;
        }

        if (self.scene_system) |sys| {
            scene.deinit(sys);
            self.scene_system = null;
        }

        if (self.physics_system) |sys| {
            physics.deinit(sys);
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
                    // TODO: Fix sleep API for Zig 0.16
                    // const sleep_time = target_frame_time - current_frame_time;
                    // std.time.sleep(@intFromFloat(sleep_time * std.time.ns_per_s));
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
            sys.update();
        }

        // Update game systems
        if (self.physics_system) |sys| {
            sys.update(@floatCast(delta_time));
        }

        if (self.audio_system) |sys| {
            try sys.update(delta_time);
        }

        if (self.scene_system) |sys| {
            sys.update(@floatCast(delta_time));
        }

        // Update AI system
        if (self.ai_system) |sys| {
            try sys.update(@floatCast(delta_time));
        }

        // Update networking system
        if (self.network_manager) |net| {
            try net.update(@floatCast(delta_time));
        }

        self.frame_count += 1;
    }

    /// Render frame
    pub fn render(self: *Self) !void {
        if (self.graphics_system) |graphics_sys| {
            try graphics_sys.beginFrame();

            if (self.scene_system) |scene_sys| {
                // Render system is part of scene update order; any per-frame render happens via scene systems.
                _ = scene_sys;
            }

            try graphics_sys.endFrame();
        }
    }

    /// Get application statistics
    pub fn getStats(self: *const Self) Stats {
        var stats = Stats{
            .frame_count = self.frame_count,
            .fps = self.time_system.getFPS(),
            .elapsed_time = self.time_system.getElapsedTime(),
            .memory_stats = self.memory_manager.getStats(),
            .physics_objects = 0,
            .audio_sources = 0,
            .ai_entities = 0,
            .network_connections = 0,
        };

        // Get physics object count
        if (self.physics_system) |phys| {
            stats.physics_objects = @intCast(phys.objects.items.len);
        }

        // Get audio source count (if available)
        if (self.audio_system) |_| {
            // Note: AudioSystem may not have a direct count method
            // This is a placeholder - actual implementation depends on AudioSystem API
            stats.audio_sources = 0;
        }

        // Get AI entity count
        if (self.ai_system) |ai_sys| {
            const metrics = ai_sys.getMetrics();
            stats.ai_entities = metrics.active_entities;
        }

        // Get network connection count
        if (self.network_manager) |net_mgr| {
            const net_stats = net_mgr.getStats();
            stats.network_connections = net_stats.connections_active;
        }

        return stats;
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
            std.log.info("Window system initialized", .{});
        }

        // Initialize graphics system
        if (self.config.enable_graphics and self.window_system != null) {
            std.log.info("Initializing graphics system...", .{});
            const graphics_config = graphics.Config{
                .backend_type = self.config.graphics_backend,
                .enable_validation = self.config.enable_validation,
                .vsync = self.config.enable_vsync,
            };

            const gfx_sys = graphics.GraphicsSystem.init(self.allocator, graphics_config) catch |err| {
                std.log.warn("Failed to initialize graphics system: {}, continuing without graphics", .{err});
                self.graphics_system = null;
                return;
            };
            self.graphics_system = try self.allocator.create(graphics.GraphicsSystem);
            self.graphics_system.?.* = gfx_sys;
            std.log.info("Graphics system initialized successfully", .{});
        }

        // Initialize audio system
        if (self.config.enable_audio) {
            const audio_config = audio.Config{
                .sample_rate = self.config.audio_sample_rate,
                .buffer_size = self.config.audio_buffer_size,
                .enable_3d_audio = self.config.enable_3d_audio,
            };

            self.audio_system = try audio.init(self.allocator, audio_config);
            std.log.info("Audio system initialized", .{});
        }

        // Initialize scene system (always initialized)
        self.scene_system = try scene.init(self.allocator, .{});
        std.log.info("Scene system initialized", .{});

        // Initialize physics system
        if (self.config.enable_physics) {
            const physics_config = physics.Config{}; // Default config
            self.physics_system = try physics.init(self.allocator, physics_config);
            std.log.info("Physics system initialized", .{});
        }

        // Initialize input system
        if (self.config.enable_input) {
            std.log.info("Initializing input system...", .{});
            const input_config = self.config.input_config;
            const input_result = input.init(self.allocator, input_config);
            if (input_result) |in_sys| {
                self.input_system = in_sys;
                std.log.info("Input system initialized successfully", .{});
            } else |err| {
                std.log.warn("Failed to initialize input system: {}, continuing without input", .{err});
                self.input_system = null;
            }
        }

        // Initialize AI system
        if (self.config.enable_ai) {
            std.log.info("Initializing AI system...", .{});
            const ai_sys_result = ai.AISystem.init(self.allocator);
            if (ai_sys_result) |ai_sys_val| {
                self.ai_system = self.allocator.create(ai.AISystem) catch |err| {
                    std.log.warn("Failed to allocate AI system: {}", .{err});
                    self.ai_system = null;
                } else |ai_ptr| {
                    ai_ptr.* = ai_sys_val;
                    self.ai_system = ai_ptr;
                    std.log.info("AI system initialized successfully", .{});
                };
            } else |err| {
                std.log.warn("Failed to initialize AI system: {}, continuing without AI", .{err});
                self.ai_system = null;
            }
        }

        // Initialize networking system (optional)
        if (self.config.enable_networking) {
            std.log.info("Initializing networking system...", .{});
            const network_result = networking.NetworkManager.init(self.allocator, self.config.network_mode);
            if (network_result) |net_mgr| {
                self.network_manager = self.allocator.create(networking.NetworkManager) catch |err| {
                    std.log.warn("Failed to allocate networking system: {}", .{err});
                    self.network_manager = null;
                } else |net_ptr| {
                    net_ptr.* = net_mgr;
                    self.network_manager = net_ptr;

                    // Start networking if configured
                    self.network_manager.?.start(self.config.network_config) catch |err| {
                        std.log.warn("Failed to start networking: {}, continuing without networking", .{err});
                        self.allocator.destroy(self.network_manager.?);
                        self.network_manager = null;
                    } else {
                        std.log.info("Networking system initialized and started in {} mode", .{self.config.network_mode});
                    };
                };
            } else |err| {
                std.log.warn("Failed to initialize networking system: {}, continuing without networking", .{err});
                self.network_manager = null;
            }
        }
    }

    /// Convert window event to input event
    fn convertWindowEventToInputEvent(win_event: window.WindowEvent) ?input.InputEvent {
        return switch (win_event) {
            .key_press => |data| {
                // Convert key code to input KeyCode
                const key_code = @as(input.KeyCode, @enumFromInt(data.key));
                return input.InputEvent{ .key_pressed = key_code };
            },
            .key_release => |data| {
                const key_code = @as(input.KeyCode, @enumFromInt(data.key));
                return input.InputEvent{ .key_released = key_code };
            },
            .mouse_move => |data| {
                return input.InputEvent{ .mouse_moved = .{ .x = @floatCast(data.x), .y = @floatCast(data.y) } };
            },
            .mouse_button => |data| {
                const button = @as(input.MouseButton, @enumFromInt(data.button));
                if (data.action == 1) { // Press
                    return input.InputEvent{ .mouse_pressed = button };
                } else { // Release
                    return input.InputEvent{ .mouse_released = button };
                }
            },
            .mouse_scroll => |data| {
                return input.InputEvent{ .mouse_wheel = .{ .delta_x = @floatCast(data.x), .delta_y = @floatCast(data.y) } };
            },
            else => null, // Ignore other events
        };
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
