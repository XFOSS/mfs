const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("color.zig");
const backend = @import("backend/backend.zig");
const Vec4 = @import("../math/vec4.zig").Vec4f;

/// Convert a color from our semantic color system to backend color
pub fn toBackendColor(rgba: color.RGBA) backend.Color {
    return backend.Color{
        .r = rgba.r,
        .g = rgba.g,
        .b = rgba.b,
        .a = rgba.a,
    };
}

/// Convert a backend color to our semantic color system
pub fn fromBackendColor(backend_color: backend.Color) color.RGBA {
    return color.RGBA{
        .r = backend_color.r,
        .g = backend_color.g,
        .b = backend_color.b,
        .a = backend_color.a,
    };
}

/// Convert Vec4 to RGBA
pub fn vec4ToColor(vec: Vec4) color.RGBA {
    return color.RGBA{
        .r = vec.x,
        .g = vec.y,
        .b = vec.z,
        .a = vec.w,
    };
}

/// Convert RGBA to Vec4
pub fn colorToVec4(rgba: color.RGBA) Vec4 {
    return Vec4.init(rgba.r, rgba.g, rgba.b, rgba.a);
}

/// Create a color theme from our color registry
pub fn createBackendTheme(registry: *color.ColorRegistry) struct {
    primary: backend.Color,
    secondary: backend.Color,
    accent: backend.Color,
    background: backend.Color,
    surface: backend.Color,
    on_primary: backend.Color,
    on_secondary: backend.Color,
    on_surface: backend.Color,
    error_color: backend.Color,
    warning: backend.Color,
    success: backend.Color,
    disabled: backend.Color,
    disabled_text: backend.Color,
} {
    return .{
        .primary = toBackendColor(registry.color(.primary)),
        .secondary = toBackendColor(registry.color(.secondary)),
        .accent = toBackendColor(registry.color(.accent)),
        .background = toBackendColor(registry.color(.systemBackground)),
        .surface = toBackendColor(registry.color(.secondarySystemBackground)),
        .on_primary = toBackendColor(registry.color(.label)),
        .on_secondary = toBackendColor(registry.color(.secondaryLabel)),
        .on_surface = toBackendColor(registry.color(.label)),
        .error_color = toBackendColor(registry.color(.error_color)),
        .warning = toBackendColor(registry.color(.warning)),
        .success = toBackendColor(registry.color(.success)),
        .disabled = toBackendColor(registry.color(.systemGray4)),
        .disabled_text = toBackendColor(registry.color(.quaternaryLabel)),
    };
}

/// Apply system appearance based on dark mode setting
pub fn applyAppearance(registry: *color.ColorRegistry, dark_mode: bool) void {
    registry.setAppearance(if (dark_mode) .dark else .light);
}

/// A utility to create a dynamic color from hex values
pub fn dynamicColorFromHex(light_hex: u32, dark_hex: u32) color.DynamicColor {
    return color.DynamicColor.init(
        color.RGBA.fromHex(light_hex),
        color.RGBA.fromHex(dark_hex)
    );
}

/// Primary colors structure for convenience access
pub const PrimaryColors = struct {
    primary: color.RGBA,
    accent: color.RGBA,
    background: color.RGBA,
    text: color.RGBA,
    error_color: color.RGBA,
    warning: color.RGBA,
    success: color.RGBA,
};

/// Get the primary UI colors as a convenience function
pub fn primaryColors(registry: *color.ColorRegistry) PrimaryColors {
    return .{
        .primary = registry.color(.primary),
        .accent = registry.color(.accent),
        .background = registry.color(.systemBackground),
        .text = registry.color(.label),
        .error_color = registry.color(.error),
        .warning = registry.color(.warning),
        .success = registry.color(.success),
    };
}

/// Define a custom theme with Apple-like semantic colors
pub fn defineCustomTheme(registry: *color.ColorRegistry, accent_color: color.RGBA) !void {
    // Generate complementary colors based on the accent
    const hsv_accent = color.HSV.fromRGBA(accent_color);
    
    // Create a complementary color (opposite on color wheel)
    const complementary_h = @mod(hsv_accent.h + 180.0, 360.0);
    const complementary = color.HSV.init(complementary_h, hsv_accent.s, hsv_accent.v, hsv_accent.a).toRGBA();
    
    // Create an analogous color (30° away on color wheel)
    const analogous_h = @mod(hsv_accent.h + 30.0, 360.0);
    const analogous = color.HSV.init(analogous_h, hsv_accent.s, hsv_accent.v, hsv_accent.a).toRGBA();
    
    // Create a darker variant for dark mode
    const dark_variant = color.HSV.init(
        hsv_accent.h,
        hsv_accent.s * 0.9,
        hsv_accent.v * 1.1,
        hsv_accent.a
    ).toRGBA();
    
    // Register custom accent colors
    try registry.registerColor(.accent, color.DynamicColor.init(
        accent_color,
        dark_variant
    ));
    
    try registry.registerColor(.accentVariant, color.DynamicColor.init(
        analogous,
        color.HSV.init(
            analogous_h,
            hsv_accent.s * 0.9,
            hsv_accent.v * 1.1,
            hsv_accent.a
        ).toRGBA()
    ));
    
    // Use complementary color for certain UI elements
    try registry.registerColor(.secondary, color.DynamicColor.init(
        complementary,
        color.HSV.init(
            complementary_h,
            hsv_accent.s * 0.8,
            hsv_accent.v * 1.2,
            hsv_accent.a
        ).toRGBA()
    ));
}