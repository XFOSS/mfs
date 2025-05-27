const std = @import("std");
const Allocator = std.mem.Allocator;

// Core framework components
pub const backend = @import("backend/backend.zig");
pub const color = @import("color.zig");
pub const color_bridge = @import("color_bridge.zig");
pub const simple_window = @import("simple_window.zig");
pub const window = @import("window.zig");
pub const worker = @import("worker.zig");

// UI Systems
pub const swiftui = @import("swiftui.zig");
pub const swiftui_extensions = @import("swiftui_extensions.zig");
pub const view_modifiers = @import("view_modifiers.zig");
pub const ui_framework = @import("ui_framework.zig");
pub const uix = @import("uix.zig");
pub const modern = @import("modern.zig");

// Examples
pub const swiftui_example = @import("swiftui_example.zig");

// Re-export commonly used types
pub const UIBackend = backend.UIBackend;
pub const UIBackendType = backend.UIBackendType;
pub const Color = backend.Color;
pub const Rect = backend.Rect;
pub const DrawCommand = backend.DrawCommand;
pub const TextAlign = backend.TextAlign;
pub const FontStyle = backend.FontStyle;
pub const FontInfo = backend.FontInfo;
pub const Image = backend.Image;

// Color system exports
pub const RGBA = color.RGBA;
pub const HSV = color.HSV;
pub const DynamicColor = color.DynamicColor;
pub const ColorRegistry = color.ColorRegistry;
pub const SemanticColor = color.SemanticColor;

// Window management exports
pub const Window = simple_window.Window;
pub const WindowConfig = simple_window.WindowConfig;
pub const NativeHandle = simple_window.NativeHandle;
pub const ThreadedWindowManager = window.WindowManager;

// Worker system exports
pub const ThreadPool = worker.ThreadPool;
pub const WorkItem = worker.WorkItem;
pub const WorkerType = worker.WorkerType;

// UI System configurations
pub const UIConfig = struct {
    backend_type: UIBackendType = .gdi,
    enable_threading: bool = true,
    default_theme: ThemeType = .dark,
    worker_threads: u32 = 4,
    enable_animations: bool = true,
    enable_gestures: bool = true,
    debug_rendering: bool = false,
};

pub const ThemeType = enum {
    light,
    dark,
    custom,
};

// Main UI Framework manager
pub const Framework = struct {
    allocator: Allocator,
    config: UIConfig,
    backend_instance: ?UIBackend,
    color_registry: ?ColorRegistry,
    thread_pool: ?ThreadPool,
    window_instance: ?Window,

    const Self = @This();

    pub fn init(allocator: Allocator, config: UIConfig) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .backend_instance = null,
            .color_registry = null,
            .thread_pool = null,
            .window_instance = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.thread_pool) |*pool| {
            pool.deinit();
        }

        if (self.backend_instance) |*backend_inst| {
            backend_inst.deinit();
        }

        if (self.color_registry) |*registry| {
            registry.deinit();
        }

        if (self.window_instance) |*window_inst| {
            window_inst.deinit();
        }
    }

    pub fn createWindow(self: *Self, window_config: WindowConfig) !void {
        // Create window
        self.window_instance = try Window.init(self.allocator, window_config);

        // Initialize color system
        self.color_registry = ColorRegistry.init(self.allocator);
        try self.setupTheme();

        // Create UI backend
        if (self.window_instance) |window_inst| {
            if (window_inst.getNativeHandle()) |handle| {
                self.backend_instance = try backend.createBackend(self.allocator, self.config.backend_type, @intFromPtr(handle.hwnd));
            }
        }

        // Initialize threading if enabled
        if (self.config.enable_threading) {
            self.thread_pool = try ThreadPool.init(self.allocator, self.config.worker_threads);
        }
    }

    pub fn pollEvents(self: *Self) !bool {
        if (self.window_instance) |*window_inst| {
            try window_inst.pollEvents();
            return !window_inst.shouldClose();
        }
        return false;
    }

    pub fn beginFrame(self: *Self) void {
        if (self.backend_instance) |*backend_inst| {
            if (self.window_instance) |window_inst| {
                const size = window_inst.getSize();
                backend_inst.beginFrame(size.width, size.height);
            }
        }
    }

    pub fn endFrame(self: *Self) void {
        if (self.backend_instance) |*backend_inst| {
            backend_inst.endFrame();
        }
    }

    pub fn executeDrawCommands(self: *Self, commands: []const DrawCommand) void {
        if (self.backend_instance) |*backend_inst| {
            backend_inst.executeDrawCommands(commands);
        }
    }

    pub fn getColorRegistry(self: *Self) ?*ColorRegistry {
        if (self.color_registry) |*registry| {
            return registry;
        }
        return null;
    }

    pub fn getThreadPool(self: *Self) ?*ThreadPool {
        if (self.thread_pool) |*pool| {
            return pool;
        }
        return null;
    }

    pub fn getBackend(self: *Self) ?*UIBackend {
        if (self.backend_instance) |*backend_inst| {
            return backend_inst;
        }
        return null;
    }

    fn setupTheme(self: *Self) !void {
        if (self.color_registry) |*registry| {
            switch (self.config.default_theme) {
                .light => color_bridge.applyAppearance(registry, false),
                .dark => color_bridge.applyAppearance(registry, true),
                .custom => {
                    // Setup custom theme if needed
                    const accent_color = color.RGBA.fromHex(0xFF007AFF);
                    try color_bridge.defineCustomTheme(registry, accent_color);
                },
            }
        }
    }
};

// Convenience functions for common UI patterns
pub fn createSwiftUIApp(allocator: Allocator, config: UIConfig) !swiftui.App {
    var color_registry = ColorRegistry.init(allocator);

    switch (config.default_theme) {
        .light => color_bridge.applyAppearance(&color_registry, false),
        .dark => color_bridge.applyAppearance(&color_registry, true),
        .custom => {
            const accent_color = color.RGBA.fromHex(0xFF007AFF);
            try color_bridge.defineCustomTheme(&color_registry, accent_color);
        },
    }

    return swiftui.App.init(allocator, &color_registry);
}

pub fn createImmediateUI(allocator: Allocator, config: UIConfig) !uix.UiSystem {
    const ui_config = uix.UiConfig{
        .enable_immediate_mode = true,
        .enable_retained_mode = false,
        .theme = switch (config.default_theme) {
            .light => .light,
            .dark => .dark,
            .custom => .custom,
        },
        .enable_transitions = config.enable_animations,
        .enable_gestures = config.enable_gestures,
    };

    return try uix.UiSystem.init(allocator, ui_config);
}

// Utility functions
pub fn detectBestBackend() UIBackendType {
    return backend.detectBestBackend();
}

pub fn createDefaultConfig() UIConfig {
    return UIConfig{
        .backend_type = detectBestBackend(),
        .enable_threading = true,
        .default_theme = .dark,
        .worker_threads = 4,
        .enable_animations = true,
        .enable_gestures = true,
        .debug_rendering = false,
    };
}

// Testing utilities
pub fn runTests() !void {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test framework initialization
    var framework = try Framework.init(allocator, createDefaultConfig());
    defer framework.deinit();

    // Test window creation
    const window_config = WindowConfig{
        .title = "Test Window",
        .width = 800,
        .height = 600,
    };

    try framework.createWindow(window_config);

    // Test that all components are initialized
    try testing.expect(framework.window_instance != null);
    try testing.expect(framework.color_registry != null);
    try testing.expect(framework.backend_instance != null);

    if (framework.config.enable_threading) {
        try testing.expect(framework.thread_pool != null);
    }
}

test "framework initialization" {
    try runTests();
}

test "color system integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var color_registry = ColorRegistry.init(allocator);
    defer color_registry.deinit();

    // Test theme creation
    const theme = color_bridge.createBackendTheme(&color_registry);
    try testing.expect(theme.primary.a > 0.0);
    try testing.expect(theme.background.a > 0.0);
}

test "swiftui integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var app = try createSwiftUIApp(allocator, createDefaultConfig());
    defer app.deinit();

    // Test basic SwiftUI functionality
    var text_view = swiftui.text(allocator, "Hello, World!");
    text_view = text_view.fontSize(16.0);

    const view_protocol = text_view.view();
    const size = view_protocol.layout(swiftui.Size.init(200, 100));

    try testing.expect(size.width > 0);
    try testing.expect(size.height > 0);
}
