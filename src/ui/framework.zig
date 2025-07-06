const std = @import("std");
const Allocator = std.mem.Allocator;

// Core framework components
pub const backend = @import("backend/backend.zig");
pub const color = @import("color.zig");
pub const color_bridge = @import("color_bridge.zig");
pub const simple_window = @import("simple_window.zig");
pub const window = @import("window.zig");
pub const worker = @import("worker.zig");
pub const utils = @import("libs/utils/utils.zig");

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
    high_contrast: bool = false,
    vsync: bool = true,

    // Validate the configuration
    pub fn validate(self: *const UIConfig) bool {
        // Check if worker thread count is reasonable
        if (self.worker_threads > 64) {
            return false;
        }

        // Validate that if threading is disabled, worker count should be 0
        if (!self.enable_threading and self.worker_threads > 0) {
            return false;
        }

        return true;
    }
};

pub const ThemeType = enum {
    light,
    dark,
    custom,
};

// Error types specific to the UI framework
pub const FrameworkError = error{
    BackendInitFailed,
    WindowInitFailed,
    ColorRegistryInitFailed,
    ThreadPoolInitFailed,
    InvalidConfiguration,
};

// Main UI Framework manager
pub const Framework = struct {
    allocator: Allocator,
    config: UIConfig,
    backend_instance: ?UIBackend,
    color_registry: ?ColorRegistry,
    thread_pool: ?ThreadPool,
    window_instance: ?Window,
    initialized: bool,
    error_handler: utils.error_handler.ErrorHandler,
    last_error: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: Allocator, config: UIConfig) !Self {
        // Validate configuration
        if (!config.validate()) {
            return FrameworkError.InvalidConfiguration;
        }

        return Self{
            .allocator = allocator,
            .config = config,
            .backend_instance = null,
            .color_registry = null,
            .thread_pool = null,
            .window_instance = null,
            .initialized = false,
            .error_handler = utils.error_handler.ErrorHandler.init(allocator),
            .last_error = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up resources in reverse order of creation
        if (self.thread_pool) |*pool| {
            pool.deinit();
            self.thread_pool = null;
        }

        if (self.backend_instance) |*backend_inst| {
            backend_inst.deinit();
            self.backend_instance = null;
        }

        if (self.color_registry) |*registry| {
            registry.deinit();
            self.color_registry = null;
        }

        if (self.window_instance) |*window_inst| {
            window_inst.deinit();
            self.window_instance = null;
        }

        if (self.last_error) |error_msg| {
            self.allocator.free(error_msg);
            self.last_error = null;
        }

        // Clean up error handler
        self.error_handler.deinit();

        self.initialized = false;
    }

    // Set error message with proper memory management
    fn setError(self: *Self, message: []const u8) void {
        if (self.last_error) |old_msg| {
            self.allocator.free(old_msg);
        }
        self.last_error = self.allocator.dupe(u8, message) catch |err| {
            std.debug.print("Failed to allocate memory for error message: {}\n", .{err});
            return;
        };
    }

    pub fn createWindow(self: *Self, window_config: WindowConfig) !void {
        if (self.initialized) {
            self.setError("Framework already initialized");
            return FrameworkError.InvalidConfiguration;
        }

        // Create window
        self.window_instance = Window.init(self.allocator, window_config) catch {
            self.setError("Failed to create window");
            return FrameworkError.WindowInitFailed;
        };

        // Initialize color system
        const registry = ColorRegistry.init(self.allocator);
        self.color_registry = registry;

        self.setupTheme() catch {
            self.setError("Failed to setup theme");
            if (self.window_instance) |*win| {
                win.deinit();
                self.window_instance = null;
            }
            return FrameworkError.ColorRegistryInitFailed;
        };

        // Create UI backend
        if (self.window_instance) |window_inst| {
            if (window_inst.getNativeHandle()) |handle| {
                self.backend_instance = backend.createBackend(self.allocator, self.config.backend_type, @intFromPtr(handle.hwnd)) catch {
                    self.setError("Failed to create backend");

                    // Clean up previously allocated resources
                    if (self.window_instance) |*win| {
                        win.deinit();
                        self.window_instance = null;
                    }
                    if (self.color_registry) |*reg| {
                        reg.deinit();
                        self.color_registry = null;
                    }

                    return FrameworkError.BackendInitFailed;
                };
            }
        }

        // Initialize threading if enabled
        if (self.config.enable_threading) {
            self.thread_pool = ThreadPool.init(self.allocator, self.config.worker_threads) catch {
                self.setError("Failed to initialize thread pool");

                // Clean up previously allocated resources
                if (self.backend_instance) |*backend_inst| {
                    backend_inst.deinit();
                    self.backend_instance = null;
                }
                if (self.window_instance) |*win| {
                    win.deinit();
                    self.window_instance = null;
                }
                if (self.color_registry) |*reg| {
                    reg.deinit();
                    self.color_registry = null;
                }

                return FrameworkError.ThreadPoolInitFailed;
            };
        }

        self.initialized = true;
    }

    pub fn pollEvents(self: *Self) !bool {
        if (self.window_instance) |*window_inst| {
            try window_inst.pollEvents();
            return !window_inst.shouldClose();
        }
        return false;
    }

    pub fn beginFrame(self: *Self) !void {
        if (!self.initialized) {
            self.setError("Framework not initialized");
            return FrameworkError.InvalidConfiguration;
        }

        if (self.backend_instance) |*backend_inst| {
            if (self.window_instance) |window_inst| {
                const size = window_inst.getSize();
                backend_inst.beginFrame(size.width, size.height);
                return;
            }
        }

        self.setError("Backend or window not available");
        return FrameworkError.InvalidConfiguration;
    }

    pub fn endFrame(self: *Self) !void {
        if (!self.initialized) {
            self.setError("Framework not initialized");
            return FrameworkError.InvalidConfiguration;
        }

        if (self.backend_instance) |*backend_inst| {
            backend_inst.endFrame();
            return;
        }

        self.setError("Backend not available");
        return FrameworkError.InvalidConfiguration;
    }

    pub fn executeDrawCommands(self: *Self, commands: []const DrawCommand) !void {
        if (!self.initialized) {
            self.setError("Framework not initialized");
            return FrameworkError.InvalidConfiguration;
        }

        if (self.backend_instance) |*backend_inst| {
            backend_inst.executeDrawCommands(commands);
            return;
        }

        self.setError("Backend not available");
        return FrameworkError.InvalidConfiguration;
    }

    pub fn getColorRegistry(self: *Self) ?*ColorRegistry {
        if (!self.initialized) {
            self.setError("Framework not initialized");
            return null;
        }

        if (self.color_registry) |*registry| {
            return registry;
        }
        return null;
    }

    // Get the last error message
    pub fn getLastError(self: *const Self) ?[]const u8 {
        return self.last_error;
    }

    pub fn getThreadPool(self: *Self) ?*ThreadPool {
        if (!self.initialized) {
            return null;
        }

        if (self.thread_pool) |*pool| {
            return pool;
        }
        return null;
    }

    pub fn getBackend(self: *Self) ?*UIBackend {
        if (!self.initialized) {
            return null;
        }

        if (self.backend_instance) |*backend_inst| {
            return backend_inst;
        }
        return null;
    }

    fn setupTheme(self: *Self) !void {
        if (self.color_registry) |*reg| {
            switch (self.config.default_theme) {
                .light => color_bridge.applyAppearanceWithContrast(reg, false, self.config.high_contrast),
                .dark => color_bridge.applyAppearanceWithContrast(reg, true, self.config.high_contrast),
                .custom => {
                    // Setup custom theme if needed
                    const accent_color = color.RGBA.fromHex(0xFF007AFF);
                    try color_bridge.defineCustomTheme(reg, accent_color);
                },
            }
            return;
        }
        return FrameworkError.ColorRegistryInitFailed;
    }

    // Check if the framework is properly initialized
    pub fn isInitialized(self: *const Self) bool {
        return self.initialized and
            self.window_instance != null and
            self.color_registry != null and
            self.backend_instance != null;
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
    // Detect the number of available CPU cores
    const cpu_count = std.Thread.getCpuCount() catch 1;

    // Use half the available cores for worker threads (min 2, max 16)
    const worker_count = @max(2, @min(16, cpu_count / 2));

    return UIConfig{
        .backend_type = detectBestBackend(),
        .enable_threading = true,
        .default_theme = .dark,
        .worker_threads = @intCast(worker_count),
        .enable_animations = true,
        .enable_gestures = true,
        .debug_rendering = false,
        .high_contrast = false,
        .vsync = true,
    };
}

// Testing utilities
pub fn runTests() !void {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a test config with minimal resource usage
    var config = UIConfig{
        .backend_type = .gdi, // Use GDI for tests as it's more likely to work
        .enable_threading = true,
        .default_theme = .light,
        .worker_threads = 2, // Use fewer threads for testing
        .enable_animations = false, // Disable animations for testing
        .enable_gestures = false, // Disable gestures for testing
        .debug_rendering = true, // Enable debug rendering for tests
        .high_contrast = false,
        .vsync = false, // Disable vsync for testing
    };

    // Test configuration validation
    try testing.expect(config.validate());

    // Test invalid configuration
    var invalid_config = config;
    invalid_config.worker_threads = 100; // Too many worker threads
    try testing.expect(!invalid_config.validate());

    // Test framework initialization
    var framework = try Framework.init(allocator, config);
    defer framework.deinit();

    // Test window creation
    const window_config = WindowConfig{
        .title = "Test Window",
        .width = 800,
        .height = 600,
        .resizable = false, // Make non-resizable for tests
        .vsync = false,
    };

    try framework.createWindow(window_config);

    // Test that all components are initialized
    try testing.expect(framework.window_instance != null);
    try testing.expect(framework.color_registry != null);
    try testing.expect(framework.backend_instance != null);
    try testing.expect(framework.initialized);

    if (framework.config.enable_threading) {
        try testing.expect(framework.thread_pool != null);
    }

    // Test resource cleanup
    framework.deinit();
    try testing.expect(framework.window_instance == null);
    try testing.expect(framework.color_registry == null);
    try testing.expect(framework.backend_instance == null);
    try testing.expect(framework.thread_pool == null);
    try testing.expect(!framework.initialized);
}

test "framework initialization and cleanup" {
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
