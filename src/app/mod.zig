//! MFS Engine - Application Module
//! Application framework providing app lifecycle, plugin system, and demo applications
//! Manages application initialization, update loops, and resource management
//! @thread-safe Application operations are coordinated for thread safety
//! @performance Optimized for smooth application execution

const std = @import("std");
const builtin = @import("builtin");

// Core application components
pub const app_loop = @import("app_loop.zig");
pub const plugin_loader = @import("plugin_loader.zig");
pub const demo_app = @import("demo_app.zig");
pub const resource_demo = @import("resource_demo.zig");

// Re-export main application types
pub const AppLoop = app_loop.AppLoop;
pub const AppConfig = app_loop.AppConfig;
pub const PluginLoader = plugin_loader.PluginLoader;
pub const Plugin = plugin_loader.Plugin;
pub const DemoApp = demo_app.DemoApp;

// Application lifecycle states
pub const AppState = enum {
    initializing,
    running,
    paused,
    resuming,
    stopping,
    stopped,

    pub fn getName(self: AppState) []const u8 {
        return switch (self) {
            .initializing => "Initializing",
            .running => "Running",
            .paused => "Paused",
            .resuming => "Resuming",
            .stopping => "Stopping",
            .stopped => "Stopped",
        };
    }
};

// Application events
pub const AppEvent = union(enum) {
    start,
    stop,
    pause,
    resumed,
    focus_gained,
    focus_lost,
    memory_warning: u64, // Available memory in bytes

    pub fn getName(self: AppEvent) []const u8 {
        return switch (self) {
            .start => "Start",
            .stop => "Stop",
            .pause => "Pause",
            .resumed => "Resume",
            .focus_gained => "Focus Gained",
            .focus_lost => "Focus Lost",
            .memory_warning => "Memory Warning",
        };
    }
};

// Application configuration
pub const ApplicationConfig = struct {
    name: []const u8 = "MFS Application",
    version: []const u8 = "1.0.0",
    organization: []const u8 = "MFS Team",
    enable_plugins: bool = true,
    enable_hot_reload: bool = builtin.mode == .Debug,
    enable_crash_reporting: bool = true,
    max_frame_rate: u32 = 60,
    enable_vsync: bool = true,

    pub fn validate(self: ApplicationConfig) !void {
        if (self.name.len == 0) {
            return error.InvalidParameter;
        }
        if (self.max_frame_rate == 0 or self.max_frame_rate > 1000) {
            return error.InvalidParameter;
        }
    }
};

// Application interface
pub const Application = struct {
    allocator: std.mem.Allocator,
    config: ApplicationConfig,
    state: AppState,
    app_loop: *AppLoop,
    plugin_loader: ?*PluginLoader,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ApplicationConfig) !*Self {
        try config.validate();

        const app = try allocator.create(Self);
        app.* = Self{
            .allocator = allocator,
            .config = config,
            .state = .initializing,
            .app_loop = try AppLoop.init(allocator, .{}),
            .plugin_loader = if (config.enable_plugins) try PluginLoader.init(allocator) else null,
        };

        return app;
    }

    pub fn deinit(self: *Self) void {
        if (self.plugin_loader) |loader| {
            loader.deinit();
        }
        self.app_loop.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *Self) !void {
        self.state = .running;
        try self.app_loop.run();
    }

    pub fn stop(self: *Self) void {
        self.state = .stopping;
        self.app_loop.stop();
        self.state = .stopped;
    }

    pub fn pause(self: *Self) void {
        self.state = .paused;
        self.app_loop.pause();
    }

    pub fn resumeApp(self: *Self) void {
        self.state = .resuming;
        self.app_loop.resumeLoop();
        self.state = .running;
    }

    pub fn getState(self: *const Self) AppState {
        return self.state;
    }
};

// Initialize application system
pub fn init(allocator: std.mem.Allocator, config: ApplicationConfig) !*Application {
    return try Application.init(allocator, config);
}

// Cleanup application system
pub fn deinit(app: *Application) void {
    app.deinit();
}

// Create a demo application
pub fn createDemo(allocator: std.mem.Allocator, demo_type: DemoApp.DemoType) !*DemoApp {
    return try DemoApp.init(allocator, demo_type);
}

test "app module" {
    std.testing.refAllDecls(@This());
}
