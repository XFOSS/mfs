const std = @import("std");
const Allocator = std.mem.Allocator;

// Core UI components
pub const unified_framework = @import("unified_framework.zig");
pub const core = @import("core.zig");
pub const backend = @import("backend/backend.zig");
pub const gpu_accelerated = @import("backend/gpu_accelerated.zig");
pub const color = @import("color.zig");
pub const window = @import("window.zig");

// Re-export unified framework components
pub const UISystem = unified_framework.UISystem;
pub const UIConfig = unified_framework.UIConfig;
pub const BackendType = unified_framework.BackendType;
pub const Theme = unified_framework.Theme;
pub const ThemeColors = unified_framework.ThemeColors;
pub const EventType = unified_framework.EventType;
pub const MouseButton = unified_framework.MouseButton;
pub const KeyCode = unified_framework.KeyCode;
pub const KeyModifiers = unified_framework.KeyModifiers;
pub const InputEvent = unified_framework.InputEvent;
pub const RenderCommand = unified_framework.RenderCommand;
pub const WidgetId = unified_framework.WidgetId;
pub const WidgetState = unified_framework.WidgetState;
pub const UIError = unified_framework.UIError;
pub const LayoutRect = unified_framework.LayoutRect;

// Re-export backend types
pub const Color = backend.Color;
pub const Rect = backend.Rect;
pub const TextAlign = backend.TextAlign;
pub const FontStyle = backend.FontStyle;
pub const FontInfo = backend.FontInfo;
pub const Image = backend.Image;
pub const DrawCommand = backend.DrawCommand;
pub const UIBackend = backend.UIBackend;

// Re-export gpu accelerated types
pub const GPU = gpu_accelerated.GPU;
pub const ShaderType = gpu_accelerated.ShaderType;
pub const ShaderId = gpu_accelerated.ShaderId;
pub const ShaderCompiler = gpu_accelerated.ShaderCompiler;

// Re-export core types
pub const UIFramework = core.UISystem;

// Re-export color types
pub const RGBA = color.RGBA;
pub const HSV = color.HSV;
pub const ColorRegistry = color.ColorRegistry;
pub const DynamicColor = color.DynamicColor;
pub const SemanticColor = color.SemanticColor;

// Re-export window types
pub const Window = window.Window;
pub const WindowConfig = window.WindowConfig;

// Helper functions for unified use
pub const Themes = struct {
    pub fn darkTheme() ThemeColors {
        return unified_framework.darkTheme();
    }

    pub fn lightTheme() ThemeColors {
        return unified_framework.lightTheme();
    }

    pub fn customTheme() ThemeColors {
        return unified_framework.customTheme();
    }
};

/// Create a new UI system with the specified configuration
pub fn createUISystem(allocator: Allocator, config: UIConfig) !UISystem {
    return UISystem.init(allocator, config);
}

/// Create a new UI system with default configuration
pub fn createDefaultUISystem(allocator: Allocator) !UISystem {
    return UISystem.init(allocator, UIConfig{});
}

/// Create a new UI system with GPU acceleration
pub fn createGPUAcceleratedUISystem(allocator: Allocator, backend_type: BackendType) !UISystem {
    const config = UIConfig{
        .backend_type = backend_type,
        .hardware_accelerated = true,
    };
    return UISystem.init(allocator, config);
}

/// Create a color from RGB values (0-255)
pub fn rgb(r: u8, g: u8, b: u8) Color {
    return Color.fromRgba(
        @as(f32, @floatFromInt(r)) / 255.0,
        @as(f32, @floatFromInt(g)) / 255.0,
        @as(f32, @floatFromInt(b)) / 255.0,
        1.0,
    );
}

/// Create a color from RGBA values (0-255)
pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
    return Color.fromRgba(
        @as(f32, @floatFromInt(r)) / 255.0,
        @as(f32, @floatFromInt(g)) / 255.0,
        @as(f32, @floatFromInt(b)) / 255.0,
        @as(f32, @floatFromInt(a)) / 255.0,
    );
}

/// Create a rectangle
pub fn rect(x: f32, y: f32, width: f32, height: f32) Rect {
    return Rect.init(x, y, width, height);
}

/// Create a text-aligned rectangle
pub fn textRect(x: f32, y: f32, width: f32, height: f32, text: []const u8, text_color: Color) RenderCommand {
    return RenderCommand{
        .text = .{
            .rect = Rect.init(x, y, width, height),
            .text = text,
            .color = text_color,
        },
    };
}

/// Create a colored rectangle
pub fn colorRect(x: f32, y: f32, width: f32, height: f32, rect_color: Color) RenderCommand {
    return RenderCommand{
        .rect = .{
            .rect = Rect.init(x, y, width, height),
            .color = rect_color,
        },
    };
}

/// Create a rounded rectangle
pub fn roundRect(x: f32, y: f32, width: f32, height: f32, rect_color: Color, radius: f32) RenderCommand {
    return RenderCommand{
        .rect = .{
            .rect = Rect.init(x, y, width, height),
            .color = rect_color,
            .border_radius = radius,
        },
    };
}

/// Create a clear command with specified color
pub fn clear(clear_color: Color) RenderCommand {
    return RenderCommand{ .clear = clear_color };
}

/// Helper enum for common UI element types
pub const ElementType = enum {
    button,
    label,
    checkbox,
    slider,
    textfield,
    dropdown,
    panel,
    image,
    scrollview,
    list,
    tab,
    menu,
    tooltip,
    progress,
};

/// Convert a color to a hex string
pub fn colorToHex(input_color: Color) []const u8 {
    var buffer: [10]u8 = undefined;
    const r = @as(u8, @intFromFloat(input_color.r * 255.0));
    const g = @as(u8, @intFromFloat(input_color.g * 255.0));
    const b = @as(u8, @intFromFloat(input_color.b * 255.0));
    const a = @as(u8, @intFromFloat(input_color.a * 255.0));

    _ = std.fmt.bufPrint(&buffer, "#{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ r, g, b, a }) catch "invalid";
    return buffer[0..9];
}
