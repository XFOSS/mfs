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
    if (std.debug.runtime_safety and isVulkanSupported()) {
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
    // Try to dynamically load the Vulkan library functions
    if (!loadVulkanLibrary()) {
        return false;
    }

    // Try to create a Vulkan instance with no extensions
    if (tryCreateVulkanInstance()) {
        // If we can create an instance, check for compatible devices
        return hasVulkanCompatibleDevices();
    }

    return false;
}

/// Attempt to load the Vulkan library dynamically
fn loadVulkanLibrary() bool {
    // On Windows, try to load vulkan-1.dll
    if (@import("builtin").os.tag == .windows) {
        const kernel32 = struct {
            extern "kernel32" fn LoadLibraryA([*:0]const u8) callconv(.C) ?*anyopaque;
            extern "kernel32" fn GetProcAddress(?*anyopaque, [*:0]const u8) callconv(.C) ?*anyopaque;
        };

        // Try to load vulkan-1.dll
        const vulkan_lib = kernel32.LoadLibraryA("vulkan-1.dll");
        return vulkan_lib != null;
    }

    // On Linux, try loading libvulkan.so.1
    if (@import("builtin").os.tag == .linux) {
        const dl = struct {
            extern "c" fn dlopen([*:0]const u8, c_int) callconv(.C) ?*anyopaque;
        };

        // Try to load libvulkan.so.1 with RTLD_NOW (value 2)
        const vulkan_lib = dl.dlopen("libvulkan.so.1", 2);
        return vulkan_lib != null;
    }

    // For other platforms or if any errors occur, return false
    return false;
}

/// Try to create a basic Vulkan instance
fn tryCreateVulkanInstance() bool {
    // This is a stub that would normally try to create a Vulkan instance
    // In a real implementation, we would use the loaded library functions
    // to try to create a VkInstance with no extensions or layers

    // For now, just return false on non-Windows platforms for safety
    return @import("builtin").os.tag == .windows;
}

/// Check if there are Vulkan-compatible devices
fn hasVulkanCompatibleDevices() bool {
    // In a real implementation, we would:
    // 1. Enumerate physical devices
    // 2. Check their properties to see if any are suitable
    // 3. Return true if at least one device is suitable

    // For now, assume Windows systems are likely to have compatible devices
    // This is a safer assumption than always returning true
    return @import("builtin").os.tag == .windows;
}

/// Check if running on Windows
fn isWindowsPlatform() bool {
    return @import("builtin").os.tag == .windows;
}

/// Create a dark theme color palette
pub fn darkTheme() ThemeColors {
    return .{
        .primary = Color.fromHex(0xFFBB86FC), // Purple
        .secondary = Color.fromHex(0xFF03DAC6), // Teal
        .accent = Color.fromHex(0xFFCF6679), // Pink
        .background = Color.fromHex(0xFF121212), // Dark gray
        .surface = Color.fromHex(0xFF1E1E1E), // Lighter dark gray
        .on_primary = Color.fromHex(0xFF000000), // Black
        .on_secondary = Color.fromHex(0xFF000000), // Black
        .on_surface = Color.fromHex(0xFFFFFFFF), // White
        .error_color = Color.fromHex(0xFFCF6679), // Red
        .warning = Color.fromHex(0xFFFFC107), // Orange
        .success = Color.fromHex(0xFF4CAF50), // Green
        .disabled = Color.fromHex(0xFF505050), // Dark gray
        .disabled_text = Color.fromHex(0xFFA0A0A0), // Light gray
    };
}

/// Create a light theme color palette
pub fn lightTheme() ThemeColors {
    return .{
        .primary = Color.fromHex(0xFF6200EE), // Purple
        .secondary = Color.fromHex(0xFF03DAC6), // Teal
        .accent = Color.fromHex(0xFFFF4081), // Pink
        .background = Color.fromHex(0xFFFFFFFF), // White
        .surface = Color.fromHex(0xFFF5F5F5), // Light gray
        .on_primary = Color.fromHex(0xFFFFFFFF), // White
        .on_secondary = Color.fromHex(0xFF000000), // Black
        .on_surface = Color.fromHex(0xFF000000), // Black
        .error_color = Color.fromHex(0xFFB00020), // Red
        .warning = Color.fromHex(0xFFFF6F00), // Orange
        .success = Color.fromHex(0xFF388E3C), // Green
        .disabled = Color.fromHex(0xFFE0E0E0), // Light gray
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
    const is_dark = (background.r < 0.5 and background.g < 0.5 and background.b < 0.5);

    if (is_dark) {
        // For dark backgrounds, make surface slightly lighter
        theme.surface = Color{
            .r = std.math.min(background.r + 0.05, 1.0),
            .g = std.math.min(background.g + 0.05, 1.0),
            .b = std.math.min(background.b + 0.05, 1.0),
            .a = background.a,
        };
        theme.on_surface = Color.fromHex(0xFFFFFFFF); // White text on dark surface
    } else {
        // For light backgrounds, make surface slightly darker
        theme.surface = Color{
            .r = std.math.max(background.r - 0.05, 0.0),
            .g = std.math.max(background.g - 0.05, 0.0),
            .b = std.math.max(background.b - 0.05, 0.0),
            .a = background.a,
        };
        theme.on_surface = Color.fromHex(0xFF000000); // Black text on light surface
    }

    // Auto-adjust text colors for contrast based on luminance
    const primary_luminance = primary.r * 0.299 + primary.g * 0.587 + primary.b * 0.114;
    const secondary_luminance = secondary.r * 0.299 + secondary.g * 0.587 + secondary.b * 0.114;

    // Use white text on dark backgrounds, black text on light backgrounds
    theme.on_primary = if (primary_luminance < 0.5)
        Color.fromHex(0xFFFFFFFF)
    else
        Color.fromHex(0xFF000000);

    theme.on_secondary = if (secondary_luminance < 0.5)
        Color.fromHex(0xFFFFFFFF)
    else
        Color.fromHex(0xFF000000);

    return theme;
}
