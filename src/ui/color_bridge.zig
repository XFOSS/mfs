const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("color.zig");
const backend = @import("backend/backend.zig");
const math = @import("math");
const Vec4 = math.Vec4;

/// Convert a color from our semantic color system to backend color
/// with optional alpha adjustment
pub fn toBackendColor(rgba: color.RGBA) backend.Color {
    return backend.Color{
        .r = rgba.r,
        .g = rgba.g,
        .b = rgba.b,
        .a = rgba.a,
    };
}

/// Convert a color from our semantic color system to backend color with specific alpha
pub fn toBackendColorWithAlpha(rgba: color.RGBA, alpha: f32) backend.Color {
    return backend.Color{
        .r = rgba.r,
        .g = rgba.g,
        .b = rgba.b,
        .a = alpha,
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

/// Apply system appearance based on dark mode setting with optional
/// high contrast mode for accessibility
pub fn applyAppearance(registry: *color.ColorRegistry, dark_mode: bool) void {
    registry.setAppearance(if (dark_mode) .dark else .light);
}

/// Apply system appearance with high contrast mode option
pub fn applyAppearanceWithContrast(registry: *color.ColorRegistry, dark_mode: bool, high_contrast: bool) void {
    if (dark_mode) {
        registry.setAppearance(if (high_contrast) .highContrastDark else .dark);
    } else {
        registry.setAppearance(if (high_contrast) .highContrastLight else .light);
    }
}

/// A utility to create a dynamic color from hex values
pub fn dynamicColorFromHex(light_hex: u32, dark_hex: u32) color.DynamicColor {
    return color.DynamicColor.init(color.RGBA.fromHex(light_hex), color.RGBA.fromHex(dark_hex));
}

/// A utility to create a complete dynamic color with high contrast variants from hex values
pub fn dynamicColorFromHexWithContrast(light_hex: u32, dark_hex: u32, high_contrast_light_hex: u32, high_contrast_dark_hex: u32) color.DynamicColor {
    return color.DynamicColor.withHighContrast(color.RGBA.fromHex(light_hex), color.RGBA.fromHex(dark_hex), color.RGBA.fromHex(high_contrast_light_hex), color.RGBA.fromHex(high_contrast_dark_hex));
}

/// Create a color that adapts to both theme and system preference for increased contrast
pub fn adaptiveAccessibilityColor(base_color: color.RGBA) color.DynamicColor {
    // Calculate HSV for easier manipulation
    const hsv = color.HSV.fromRGBA(base_color);

    // Create variants with different saturation and brightness
    // For light mode standard
    const light_standard = base_color;

    // For dark mode standard - adjust for better visibility in dark theme
    const dark_standard = color.HSV.init(hsv.h, std.math.min(hsv.s * 0.9, 1.0), std.math.min(hsv.v * 1.2, 1.0), hsv.a).toRGBA();

    // For light mode with high contrast - increase contrast
    const light_high_contrast = color.HSV.init(hsv.h, std.math.min(hsv.s * 1.2, 1.0), std.math.max(hsv.v * 0.8, 0.0), hsv.a).toRGBA();

    // For dark mode with high contrast - maximize visibility
    const dark_high_contrast = color.HSV.init(hsv.h, std.math.min(hsv.s * 0.7, 1.0), std.math.min(hsv.v * 1.4, 1.0), hsv.a).toRGBA();

    return color.DynamicColor.withHighContrast(light_standard, dark_standard, light_high_contrast, dark_high_contrast);
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
    info: color.RGBA = color.RGBA.init(0.0, 0.5, 1.0, 1.0), // Default blue
    surface: color.RGBA,
    disabled: color.RGBA,
};

/// Get the primary UI colors as a convenience function
pub fn primaryColors(registry: *color.ColorRegistry) PrimaryColors {
    return .{
        .primary = registry.color(.primary),
        .accent = registry.color(.accent),
        .background = registry.color(.systemBackground),
        .text = registry.color(.label),
        .error_color = registry.color(.error_color),
        .warning = registry.color(.warning),
        .success = registry.color(.success),
        .info = registry.color(.info),
        .surface = registry.color(.secondarySystemBackground),
        .disabled = registry.color(.systemGray4),
    };
}

/// Calculate if a color needs dark text for readability
pub fn needsDarkText(bg: color.RGBA) bool {
    // Calculate relative luminance using sRGB formula
    const luminance = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b;

    // Return true for light backgrounds (need dark text)
    return luminance > 0.5;
}

/// Get a text color that will have good contrast on the given background
pub fn getContrastingTextColor(bg: color.RGBA) color.RGBA {
    return if (needsDarkText(bg))
        color.RGBA.init(0.0, 0.0, 0.0, 1.0) // Black for light backgrounds
    else
        color.RGBA.init(1.0, 1.0, 1.0, 1.0); // White for dark backgrounds
}

/// Calculate contrast ratio between two colors (WCAG formula)
pub fn contrastRatio(c1: color.RGBA, c2: color.RGBA) f32 {
    // Calculate luminance values
    const l1 = 0.2126 * c1.r + 0.7152 * c1.g + 0.0722 * c1.b;
    const l2 = 0.2126 * c2.r + 0.7152 * c2.g + 0.0722 * c2.b;

    // Ensure l1 is the lighter color
    const lighter = if (l1 > l2) l1 else l2;
    const darker = if (l1 > l2) l2 else l1;

    // Calculate contrast ratio (WCAG formula)
    return (lighter + 0.05) / (darker + 0.05);
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

    // Create a triadic color (120° away on color wheel)
    const triadic_h = @mod(hsv_accent.h + 120.0, 360.0);
    const triadic = color.HSV.init(triadic_h, hsv_accent.s * 0.9, hsv_accent.v * 0.95, hsv_accent.a).toRGBA();

    // Create a darker variant for dark mode
    const dark_variant = color.HSV.init(hsv_accent.h, std.math.min(hsv_accent.s * 0.9, 1.0), std.math.min(hsv_accent.v * 1.1, 1.0), hsv_accent.a).toRGBA();

    // Create a high contrast variant for accessibility
    const high_contrast_light = color.HSV.init(hsv_accent.h, std.math.min(hsv_accent.s * 1.3, 1.0), std.math.min(hsv_accent.v * 0.7, 1.0), hsv_accent.a).toRGBA();

    const high_contrast_dark = color.HSV.init(hsv_accent.h, std.math.min(hsv_accent.s * 0.7, 1.0), std.math.min(hsv_accent.v * 1.3, 1.0), hsv_accent.a).toRGBA();

    // Register custom accent colors
    try registry.registerColor(.accent, color.DynamicColor.withHighContrast(accent_color, // Light mode
        dark_variant, // Dark mode
        high_contrast_light, // High contrast light
        high_contrast_dark // High contrast dark
    ));

    // Register accent variant
    try registry.registerColor(.accentVariant, color.DynamicColor.withHighContrast(analogous, color.HSV.init(analogous_h, std.math.min(hsv_accent.s * 0.9, 1.0), std.math.min(hsv_accent.v * 1.1, 1.0), hsv_accent.a).toRGBA(), color.HSV.init(analogous_h, std.math.min(hsv_accent.s * 1.2, 1.0), std.math.min(hsv_accent.v * 0.8, 1.0), hsv_accent.a).toRGBA(), color.HSV.init(analogous_h, std.math.min(hsv_accent.s * 0.8, 1.0), std.math.min(hsv_accent.v * 1.3, 1.0), hsv_accent.a).toRGBA()));

    // Use complementary color for secondary UI elements
    try registry.registerColor(.secondary, color.DynamicColor.withHighContrast(complementary, color.HSV.init(complementary_h, std.math.min(hsv_accent.s * 0.8, 1.0), std.math.min(hsv_accent.v * 1.2, 1.0), hsv_accent.a).toRGBA(), color.HSV.init(complementary_h, std.math.min(hsv_accent.s * 1.1, 1.0), std.math.min(hsv_accent.v * 0.7, 1.0), hsv_accent.a).toRGBA(), color.HSV.init(complementary_h, std.math.min(hsv_accent.s * 0.7, 1.0), std.math.min(hsv_accent.v * 1.4, 1.0), hsv_accent.a).toRGBA()));

    // Add triadic color for info/tertiary actions
    try registry.registerColor(.info, color.DynamicColor.withHighContrast(triadic, color.HSV.init(triadic_h, std.math.min(hsv_accent.s * 0.8, 1.0), std.math.min(hsv_accent.v * 1.2, 1.0), hsv_accent.a).toRGBA(), color.HSV.init(triadic_h, std.math.min(hsv_accent.s * 1.1, 1.0), std.math.min(hsv_accent.v * 0.7, 1.0), hsv_accent.a).toRGBA(), color.HSV.init(triadic_h, std.math.min(hsv_accent.s * 0.7, 1.0), std.math.min(hsv_accent.v * 1.4, 1.0), hsv_accent.a).toRGBA()));
}
