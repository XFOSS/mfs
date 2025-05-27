const std = @import("std");
const Allocator = std.mem.Allocator;
const interface = @import("interface.zig");
const gdi_backend = @import("gdi.zig");
const vulkan_backend = @import("vulkan.zig");

/// UI backend types and common interface types
pub const UIBackendType = interface.BackendType;
pub const UIBackend = interface.UIBackend;
pub const Color = interface.Color;
pub const Rect = interface.Rect;
pub const DrawCommand = interface.DrawCommand;
pub const TextAlign = interface.TextAlign;
pub const FontStyle = interface.FontStyle;
pub const FontInfo = interface.FontInfo;
pub const Image = interface.Image;

/// Theme colors structure used by all theme functions
pub const ThemeColors = struct {
    primary: Color,
    secondary: Color,
    accent: Color,
    background: Color,
    surface: Color,
    on_primary: Color,
    on_secondary: Color,
    on_surface: Color,
    error_color: Color,
    warning: Color,
    success: Color,
    disabled: Color,
    disabled_text: Color,
};

/// Create a UI backend of the specified type
pub fn createBackend(allocator: Allocator, backend_type: UIBackendType, window_handle: usize) !UIBackend {
    return switch (backend_type) {
        .gdi => UIBackend.init(allocator, &gdi_backend.gdi_backend_interface, window_handle),
        .vulkan => UIBackend.init(allocator, &vulkan_backend.vulkan_backend_interface, window_handle),
        .opengl => error.OpenGLBackendNotImplemented,
        .software => error.SoftwareBackendNotImplemented,
    };
}

/// Detect the best available backend type for the current system
pub fn detectBestBackend() UIBackendType {
    // Try to detect Vulkan support first
    if (isVulkanSupported()) {
        return .vulkan;
    }

    // On Windows, GDI is always available
    if (isWindowsPlatform()) {
        return .gdi;
    }

    // Fallback to software rendering (not implemented yet)
    return .software;
}

/// Check if Vulkan is supported
fn isVulkanSupported() bool {
    // TODO: Implement proper Vulkan detection by checking for:
    // 1. Vulkan libraries
    // 2. Attempt to create a Vulkan instance
    // 3. Query for compatible devices
    return true;
}

/// Check if running on Windows
fn isWindowsPlatform() bool {
    return @import("builtin").os.tag == .windows;
}

/// Create a dark theme color palette
pub fn darkTheme() ThemeColors {
    return .{
        .primary = Color.fromHex(0xFFBB86FC),     // Purple
        .secondary = Color.fromHex(0xFF03DAC6),   // Teal
        .accent = Color.fromHex(0xFFCF6679),      // Pink
        .background = Color.fromHex(0xFF121212),  // Dark gray
        .surface = Color.fromHex(0xFF1E1E1E),     // Lighter dark gray
        .on_primary = Color.fromHex(0xFF000000),  // Black
        .on_secondary = Color.fromHex(0xFF000000), // Black
        .on_surface = Color.fromHex(0xFFFFFFFF),  // White
        .error_color = Color.fromHex(0xFFCF6679), // Red
        .warning = Color.fromHex(0xFFFFC107),     // Orange
        .success = Color.fromHex(0xFF4CAF50),     // Green
        .disabled = Color.fromHex(0xFF505050),    // Dark gray
        .disabled_text = Color.fromHex(0xFFA0A0A0), // Light gray
    };
}

/// Create a light theme color palette
pub fn lightTheme() ThemeColors {
    return .{
        .primary = Color.fromHex(0xFF6200EE),     // Purple
        .secondary = Color.fromHex(0xFF03DAC6),   // Teal
        .accent = Color.fromHex(0xFFFF4081),      // Pink
        .background = Color.fromHex(0xFFFFFFFF),  // White
        .surface = Color.fromHex(0xFFF5F5F5),     // Light gray
        .on_primary = Color.fromHex(0xFFFFFFFF),  // White
        .on_secondary = Color.fromHex(0xFF000000), // Black
        .on_surface = Color.fromHex(0xFF000000),  // Black
        .error_color = Color.fromHex(0xFFB00020),       // Red
        .warning = Color.fromHex(0xFFFF6F00),     // Orange
        .success = Color.fromHex(0xFF388E3C),     // Green
        .disabled = Color.fromHex(0xFFE0E0E0),    // Light gray
        .disabled_text = Color.fromHex(0xFF909090), // Dark gray
    };
}

/// Create a custom theme color palette
pub fn customTheme(
    primary: Color,
    secondary: Color,
    background: Color,
) ThemeColors {
    var theme = lightTheme();
    theme.primary = primary;
    theme.secondary = secondary;
    theme.background = background;

    // Derive surface color from background
    // Slightly lighter version of background for surface
    theme.surface = background;

    // Auto-adjust text colors for contrast
    theme.on_primary = Color.fromHex(0xFFFFFFFF);
    theme.on_secondary = Color.fromHex(0xFF000000);
    theme.on_surface = Color.fromHex(0xFF000000);

    return theme;
}
