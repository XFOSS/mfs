const std = @import("std");
const Allocator = std.mem.Allocator;

// Core UI system
pub const backend = @import("backend/backend.zig");
pub const color = @import("color.zig");
pub const window = @import("window.zig");

// Essential types
pub const Color = backend.Color;
pub const Rect = backend.Rect;
pub const UIBackend = backend.UIBackend;
pub const Window = window.Window;
pub const WindowConfig = window.WindowConfig;

// UI Configuration
pub const UIConfig = struct {
    backend_type: backend.UIBackendType = .gdi,
    theme: Theme = .dark,
    enable_animations: bool = true,
    vsync: bool = true,
    debug_rendering: bool = false,
};

// Theme system
pub const Theme = enum {
    dark,
    light,
    custom,

    pub fn getColors(self: Theme) ThemeColors {
        return switch (self) {
            .dark => darkTheme(),
            .light => lightTheme(),
            .custom => lightTheme(),
        };
    }
};

pub const ThemeColors = struct {
    primary: Color,
    secondary: Color,
    background: Color,
    surface: Color,
    text: Color,
    accent: Color,
};

// Event system
pub const EventType = enum {
    mouse_move,
    mouse_down,
    mouse_up,
    key_down,
    key_up,
    window_resize,
    window_close,
};

pub const InputEvent = struct {
    event_type: EventType,
    timestamp: u64,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    key_code: u32 = 0,
    window_width: u32 = 0,
    window_height: u32 = 0,
};

// Main UI System
pub const UISystem = struct {
    allocator: Allocator,
    config: UIConfig,
    backend_instance: ?UIBackend,
    window_instance: ?Window,
    theme_colors: ThemeColors,

    const Self = @This();

    pub fn init(allocator: Allocator, config: UIConfig) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .backend_instance = null,
            .window_instance = null,
            .theme_colors = config.theme.getColors(),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.backend_instance) |*backend_inst| {
            backend_inst.deinit();
        }
        if (self.window_instance) |*window_inst| {
            window_inst.deinit();
        }
    }

    pub fn createWindow(self: *Self, window_config: WindowConfig) !void {
        self.window_instance = try Window.init(self.allocator, window_config);

        if (self.window_instance) |window_inst| {
            self.backend_instance = try UIBackend.init(self.allocator, self.config.backend_type, window_inst.getNativeHandle());
        }
    }

    pub fn handleEvent(self: *Self, event: InputEvent) void {
        // Handle UI events
        _ = self;
        _ = event;
    }

    pub fn render(self: *Self) !void {
        if (self.backend_instance) |*backend_inst| {
            try backend_inst.beginFrame();
            try backend_inst.clear(self.theme_colors.background);
            try backend_inst.endFrame();
        }
    }
};

// Theme definitions
pub fn darkTheme() ThemeColors {
    return ThemeColors{
        .primary = rgb(0x1E, 0x88, 0xE5),
        .secondary = rgb(0x03, 0xDA, 0xC6),
        .background = rgb(0x12, 0x12, 0x12),
        .surface = rgb(0x1E, 0x1E, 0x1E),
        .text = rgb(0xFF, 0xFF, 0xFF),
        .accent = rgb(0xFF, 0x57, 0x22),
    };
}

pub fn lightTheme() ThemeColors {
    return ThemeColors{
        .primary = rgb(0x19, 0x76, 0xD2),
        .secondary = rgb(0x00, 0x96, 0x88),
        .background = rgb(0xFF, 0xFF, 0xFF),
        .surface = rgb(0xF5, 0xF5, 0xF5),
        .text = rgb(0x00, 0x00, 0x00),
        .accent = rgb(0xFF, 0x57, 0x22),
    };
}

// Utility functions
pub fn rgb(r: u8, g: u8, b: u8) Color {
    return Color.fromRgba(
        @as(f32, @floatFromInt(r)) / 255.0,
        @as(f32, @floatFromInt(g)) / 255.0,
        @as(f32, @floatFromInt(b)) / 255.0,
        1.0,
    );
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
    return Color.fromRgba(
        @as(f32, @floatFromInt(r)) / 255.0,
        @as(f32, @floatFromInt(g)) / 255.0,
        @as(f32, @floatFromInt(b)) / 255.0,
        @as(f32, @floatFromInt(a)) / 255.0,
    );
}

pub fn rect(x: f32, y: f32, width: f32, height: f32) Rect {
    return Rect.init(x, y, width, height);
}

// Factory functions
pub fn createUISystem(allocator: Allocator, config: UIConfig) !UISystem {
    return UISystem.init(allocator, config);
}

pub fn createDefaultUISystem(allocator: Allocator) !UISystem {
    return UISystem.init(allocator, UIConfig{});
}
