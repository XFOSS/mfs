//! MFS Engine - Window Module
//! Cross-platform window management system

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("../build_options.zig");

pub const window = @import("window.zig");

/// Re-export main window types
pub const Window = window.Window;
pub const WindowConfig = window.WindowConfig;
pub const WindowSystem = WindowSystemImpl;

/// Window configuration
pub const Config = struct {
    width: u32 = 1280,
    height: u32 = 720,
    title: []const u8 = "MFS Engine Application",
    resizable: bool = true,
    fullscreen: bool = false,
    vsync: bool = true,
    decorated: bool = true,
    always_on_top: bool = false,
    transparent: bool = false,
    min_width: u32 = 320,
    min_height: u32 = 240,
    max_width: u32 = 0, // 0 means no limit
    max_height: u32 = 0, // 0 means no limit
};

/// Window events
pub const WindowEvent = union(enum) {
    close,
    resize: struct { width: u32, height: u32 },
    move: struct { x: i32, y: i32 },
    focus: bool,
    minimize,
    maximize,
    restore,
    key_press: struct { key: u32, scancode: u32, mods: u32 },
    key_release: struct { key: u32, scancode: u32, mods: u32 },
    mouse_button: struct { button: u32, action: u32, mods: u32 },
    mouse_move: struct { x: f64, y: f64 },
    mouse_scroll: struct { x: f64, y: f64 },
    char_input: struct { codepoint: u32 },
};

/// Window system implementation
pub const WindowSystemImpl = struct {
    allocator: std.mem.Allocator,
    config: Config,
    window: ?*Window,
    should_close: bool,
    events: std.ArrayList(WindowEvent),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Self {
        const system = try allocator.create(Self);
        system.* = Self{
            .allocator = allocator,
            .config = config,
            .window = null,
            .should_close = false,
            .events = try std.ArrayList(WindowEvent).initCapacity(allocator, 16),
        };

        // Create the actual window
        const window_config = WindowConfig{
            .width = config.width,
            .height = config.height,
            .title = config.title,
            .resizable = config.resizable,
            .fullscreen = config.fullscreen,
            .vsync = config.vsync,
            .decorated = config.decorated,
            .always_on_top = config.always_on_top,
            .transparent = config.transparent,
            .min_width = config.min_width,
            .min_height = config.min_height,
            .max_width = config.max_width,
            .max_height = config.max_height,
        };
        system.window = try Window.init(allocator, window_config);

        std.log.info("Window system initialized: {}x{} '{s}'", .{ config.width, config.height, config.title });
        return system;
    }

    pub fn deinit(self: *Self) void {
        if (self.window) |win| {
            win.deinit();
            self.allocator.destroy(win);
        }
        self.events.deinit();
        // Note: Don't destroy self here - that's the responsibility of the caller
    }

    pub fn update(self: *Self) !void {
        if (self.window) |win| {
            try win.pollEvents();

            // Process window events and convert to our event system
            // This is a simplified implementation
            if (win.shouldClose()) {
                self.should_close = true;
                try self.events.append(.close);
            }
        }
    }

    pub fn shouldQuit(self: *const Self) bool {
        return self.should_close;
    }

    pub fn getWindow(self: *const Self) ?*Window {
        return self.window;
    }

    pub fn getEvents(self: *const Self) []const WindowEvent {
        return self.events.items;
    }

    pub fn clearEvents(self: *Self) void {
        self.events.clearRetainingCapacity();
    }

    pub fn setTitle(self: *Self, title: []const u8) void {
        if (self.window) |win| {
            win.setTitle(title);
        }
    }

    pub fn setSize(self: *Self, width: u32, height: u32) void {
        if (self.window) |win| {
            win.setSize(width, height);
        }
        self.config.width = width;
        self.config.height = height;
    }

    pub fn getSize(self: *const Self) struct { width: u32, height: u32 } {
        if (self.window) |win| {
            return win.getSize();
        }
        return .{ .width = self.config.width, .height = self.config.height };
    }

    pub fn setFullscreen(self: *Self, fullscreen: bool) void {
        if (self.window) |win| {
            win.setFullscreen(fullscreen);
        }
        self.config.fullscreen = fullscreen;
    }

    pub fn isFullscreen(self: *const Self) bool {
        if (self.window) |win| {
            return win.isFullscreen();
        }
        return self.config.fullscreen;
    }

    pub fn show(self: *Self) void {
        if (self.window) |win| {
            win.show();
        }
    }

    pub fn hide(self: *Self) void {
        if (self.window) |win| {
            win.hide();
        }
    }

    pub fn focus(self: *Self) void {
        if (self.window) |win| {
            win.focus();
        }
    }

    pub fn minimize(self: *Self) void {
        if (self.window) |win| {
            win.minimize();
        }
    }

    pub fn maximize(self: *Self) void {
        if (self.window) |win| {
            win.maximize();
        }
    }

    pub fn restore(self: *Self) void {
        if (self.window) |win| {
            win.restore();
        }
    }

    pub fn getWindowHandle(self: *const Self) ?*anyopaque {
        if (self.window) |win| {
            return win.getHandle();
        }
        return null;
    }
};

test "window system" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = Config{
        .width = 640,
        .height = 480,
        .title = "Test Window",
    };

    var system = try WindowSystemImpl.init(allocator, config);
    defer system.deinit();

    try testing.expect(!system.shouldQuit());

    const size = system.getSize();
    try testing.expect(size.width == 640);
    try testing.expect(size.height == 480);
}
