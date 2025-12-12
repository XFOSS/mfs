const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("math");
const Vec4 = math.Vec4;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;

/// ColorSpace represents different color spaces used in the application
pub const ColorSpace = enum {
    /// sRGB color space - standard for most displays
    sRGB,
    /// Display P3 color space - wider gamut used by modern Apple displays
    displayP3,
    /// Linear sRGB - used for computations
    linearRGB,
    /// HSV (Hue, Saturation, Value) - convenient for certain transformations
    hsv,
    /// HSL (Hue, Saturation, Lightness)
    hsl,
    /// CMYK (Cyan, Magenta, Yellow, Key)
    cmyk,
};

/// Appearance defines the interface theme appearance
pub const Appearance = enum {
    /// Light interface style
    light,
    /// Dark interface style
    dark,
    /// High contrast light interface style
    highContrastLight,
    /// High contrast dark interface style
    highContrastDark,
    /// Any interface style (used for universal colors)
    any,
};

/// ColorComponent defines the semantic component for a color
pub const ColorComponent = enum {
    label,
    secondaryLabel,
    tertiaryLabel,
    quaternaryLabel,
    systemFill,
    secondarySystemFill,
    tertiarySystemFill,
    quaternarySystemFill,
    placeholderText,
    systemBackground,
    secondarySystemBackground,
    tertiarySystemBackground,
    systemGroupedBackground,
    secondarySystemGroupedBackground,
    tertiarySystemGroupedBackground,
    separator,
    opaqueSeparator,
    link,
    systemBlue,
    systemGreen,
    systemIndigo,
    systemOrange,
    systemPink,
    systemPurple,
    systemRed,
    systemTeal,
    systemYellow,
    systemGray,
    systemGray2,
    systemGray3,
    systemGray4,
    systemGray5,
    systemGray6,
    clear,
    // Application-specific semantic colors
    accent,
    accentVariant,
    primary,
    secondary,
    error_color,
    warning,
    success,
    info,
};

/// RGBA represents a color with red, green, blue, and alpha components
pub const RGBA = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn init(r: f32, g: f32, b: f32, a: f32) RGBA {
        return RGBA{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn fromHex(hex: u32) RGBA {
        const r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0;
        const g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0;
        const b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0;
        const a = if (hex > 0xFFFFFF) @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0 else 1.0;
        return RGBA{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toHex(self: RGBA) u32 {
        const r = @as(u32, @intFromFloat(self.r * 255.0)) & 0xFF;
        const g = @as(u32, @intFromFloat(self.g * 255.0)) & 0xFF;
        const b = @as(u32, @intFromFloat(self.b * 255.0)) & 0xFF;
        const a = @as(u32, @intFromFloat(self.a * 255.0)) & 0xFF;
        return (a << 24) | (r << 16) | (g << 8) | b;
    }

    pub fn toVec4(self: RGBA) Vec4 {
        return Vec4.init(self.r, self.g, self.b, self.a);
    }

    pub fn fromVec4(vec: Vec4) RGBA {
        return RGBA{
            .r = vec.x,
            .g = vec.y,
            .b = vec.z,
            .a = vec.w,
        };
    }

    pub fn premultiplied(self: RGBA) RGBA {
        return RGBA{
            .r = self.r * self.a,
            .g = self.g * self.a,
            .b = self.b * self.a,
            .a = self.a,
        };
    }

    pub fn withAlpha(self: RGBA, alpha: f32) RGBA {
        var result = self;
        result.a = alpha;
        return result;
    }
};

/// HSV represents a color with hue, saturation, value, and alpha components
pub const HSV = struct {
    h: f32, // 0-360
    s: f32, // 0-1
    v: f32, // 0-1
    a: f32, // 0-1

    pub fn init(h: f32, s: f32, v: f32, a: f32) HSV {
        return HSV{
            .h = h,
            .s = s,
            .v = v,
            .a = a,
        };
    }

    pub fn toRGBA(self: HSV) RGBA {
        if (self.s <= 0.0) {
            return RGBA{
                .r = self.v,
                .g = self.v,
                .b = self.v,
                .a = self.a,
            };
        }

        var hh = @rem(self.h, 360.0);
        if (hh < 0) hh += 360.0;
        hh /= 60.0;

        const i: u32 = @intFromFloat(hh);
        const ff = hh - @as(f32, @floatFromInt(i));

        const p = self.v * (1.0 - self.s);
        const q = self.v * (1.0 - (self.s * ff));
        const t = self.v * (1.0 - (self.s * (1.0 - ff)));

        return switch (i) {
            0 => RGBA{ .r = self.v, .g = t, .b = p, .a = self.a },
            1 => RGBA{ .r = q, .g = self.v, .b = p, .a = self.a },
            2 => RGBA{ .r = p, .g = self.v, .b = t, .a = self.a },
            3 => RGBA{ .r = p, .g = q, .b = self.v, .a = self.a },
            4 => RGBA{ .r = t, .g = p, .b = self.v, .a = self.a },
            else => RGBA{ .r = self.v, .g = p, .b = q, .a = self.a },
        };
    }

    pub fn fromRGBA(rgba: RGBA) HSV {
        const cmax = @max(rgba.r, @max(rgba.g, rgba.b));
        const cmin = @min(rgba.r, @min(rgba.g, rgba.b));
        const delta = cmax - cmin;

        var h: f32 = 0;
        if (delta != 0) {
            if (cmax == rgba.r) {
                h = 60.0 * @rem((rgba.g - rgba.b) / delta, 6.0);
            } else if (cmax == rgba.g) {
                h = 60.0 * ((rgba.b - rgba.r) / delta + 2.0);
            } else {
                h = 60.0 * ((rgba.r - rgba.g) / delta + 4.0);
            }
        }

        if (h < 0) h += 360.0;

        const s = if (cmax == 0) 0.0 else delta / cmax;
        const v = cmax;

        return HSV{
            .h = h,
            .s = s,
            .v = v,
            .a = rgba.a,
        };
    }
};

/// DynamicColor represents a color that adapts based on appearance
pub const DynamicColor = struct {
    light: RGBA,
    dark: RGBA,
    high_contrast_light: ?RGBA = null,
    high_contrast_dark: ?RGBA = null,

    const Self = @This();

    pub fn init(light: RGBA, dark: RGBA) DynamicColor {
        return DynamicColor{
            .light = light,
            .dark = dark,
        };
    }

    pub fn withHighContrast(self: Self, high_contrast_light: RGBA, high_contrast_dark: RGBA) DynamicColor {
        var color = self;
        color.high_contrast_light = high_contrast_light;
        color.high_contrast_dark = high_contrast_dark;
        return color;
    }

    pub fn resolve(self: Self, appearance: Appearance) RGBA {
        return switch (appearance) {
            .light => self.light,
            .dark => self.dark,
            .highContrastLight => self.high_contrast_light orelse self.light,
            .highContrastDark => self.high_contrast_dark orelse self.dark,
            .any => self.light,
        };
    }
};

/// ColorRegistry stores and manages semantic colors
pub const ColorRegistry = struct {
    allocator: Allocator,
    semantic_colors: HashMap(ColorComponent, DynamicColor),
    current_appearance: Appearance,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var registry = Self{
            .allocator = allocator,
            .semantic_colors = HashMap(ColorComponent, DynamicColor).init(allocator),
            .current_appearance = .light,
        };

        try registry.initDefaultColors();
        return registry;
    }

    pub fn deinit(self: *Self) void {
        self.semantic_colors.deinit();
    }

    pub fn setAppearance(self: *Self, appearance: Appearance) void {
        self.current_appearance = appearance;
    }
    pub fn registerColor(self: *Self, component: ColorComponent, dynamic_color: DynamicColor) !void {
        try self.semantic_colors.put(component, dynamic_color);
    }

    pub fn color(self: *const Self, component: ColorComponent) RGBA {
        if (self.semantic_colors.get(component)) |dynamic_color| {
            return dynamic_color.resolve(self.current_appearance);
        } else {
            // Fallback to a default color if not found
            return RGBA.init(0.5, 0.5, 0.5, 1.0);
        }
    }

    fn initDefaultColors(self: *Self) !void {
        // System Colors
        try self.registerColor(.systemBlue, DynamicColor.init(RGBA.fromHex(0xFF0A84FF), // Light mode
            RGBA.fromHex(0xFF0A84FF) // Dark mode
        ));

        try self.registerColor(.systemGreen, DynamicColor.init(RGBA.fromHex(0xFF30D158), RGBA.fromHex(0xFF30D158)));

        try self.registerColor(.systemIndigo, DynamicColor.init(RGBA.fromHex(0xFF5E5CE6), RGBA.fromHex(0xFF5E5CE6)));

        try self.registerColor(.systemOrange, DynamicColor.init(RGBA.fromHex(0xFFFF9F0A), RGBA.fromHex(0xFFFF9F0A)));

        try self.registerColor(.systemPink, DynamicColor.init(RGBA.fromHex(0xFFFF375F), RGBA.fromHex(0xFFFF375F)));

        try self.registerColor(.systemPurple, DynamicColor.init(RGBA.fromHex(0xFFBF5AF2), RGBA.fromHex(0xFFBF5AF2)));

        try self.registerColor(.systemRed, DynamicColor.init(RGBA.fromHex(0xFFFF3B30), RGBA.fromHex(0xFFFF3B30)));

        try self.registerColor(.systemTeal, DynamicColor.init(RGBA.fromHex(0xFF64D2FF), RGBA.fromHex(0xFF64D2FF)));

        try self.registerColor(.systemYellow, DynamicColor.init(RGBA.fromHex(0xFFFFD60A), RGBA.fromHex(0xFFFFD60A)));

        // UI Elements
        try self.registerColor(.label, DynamicColor.init(RGBA.fromHex(0xFF000000), RGBA.fromHex(0xFFFFFFFF)));

        try self.registerColor(.secondaryLabel, DynamicColor.init(RGBA.fromHex(0x993C3C43), RGBA.fromHex(0x99EBEBF5)));

        try self.registerColor(.tertiaryLabel, DynamicColor.init(RGBA.fromHex(0x4D3C3C43), RGBA.fromHex(0x4DEBEBF5)));

        try self.registerColor(.quaternaryLabel, DynamicColor.init(RGBA.fromHex(0x2E3C3C43), RGBA.fromHex(0x2EEBEBF5)));

        try self.registerColor(.systemBackground, DynamicColor.init(RGBA.fromHex(0xFFFFFFFF), RGBA.fromHex(0xFF000000)));

        try self.registerColor(.secondarySystemBackground, DynamicColor.init(RGBA.fromHex(0xFFF2F2F7), RGBA.fromHex(0xFF1C1C1E)));

        try self.registerColor(.tertiarySystemBackground, DynamicColor.init(RGBA.fromHex(0xFFFFFFFF), RGBA.fromHex(0xFF2C2C2E)));

        try self.registerColor(.systemGroupedBackground, DynamicColor.init(RGBA.fromHex(0xFFF2F2F7), RGBA.fromHex(0xFF000000)));

        try self.registerColor(.secondarySystemGroupedBackground, DynamicColor.init(RGBA.fromHex(0xFFFFFFFF), RGBA.fromHex(0xFF1C1C1E)));

        try self.registerColor(.tertiarySystemGroupedBackground, DynamicColor.init(RGBA.fromHex(0xFFFFFFFF), RGBA.fromHex(0xFF2C2C2E)));

        try self.registerColor(.separator, DynamicColor.init(RGBA.fromHex(0x493C3C43), RGBA.fromHex(0x54545457)));

        try self.registerColor(.opaqueSeparator, DynamicColor.init(RGBA.fromHex(0xFFC6C6C8), RGBA.fromHex(0xFF38383A)));

        try self.registerColor(.link, DynamicColor.init(RGBA.fromHex(0xFF007AFF), RGBA.fromHex(0xFF0984FF)));

        try self.registerColor(.placeholderText, DynamicColor.init(RGBA.fromHex(0x4D3C3C43), RGBA.fromHex(0x4DEBEBF5)));

        try self.registerColor(.systemFill, DynamicColor.init(RGBA.fromHex(0x1F3C3C43), RGBA.fromHex(0x1FEBEBF5)));

        try self.registerColor(.secondarySystemFill, DynamicColor.init(RGBA.fromHex(0x143C3C43), RGBA.fromHex(0x14EBEBF5)));

        try self.registerColor(.tertiarySystemFill, DynamicColor.init(RGBA.fromHex(0x0A3C3C43), RGBA.fromHex(0x0AEBEBF5)));

        try self.registerColor(.quaternarySystemFill, DynamicColor.init(RGBA.fromHex(0x053C3C43), RGBA.fromHex(0x05EBEBF5)));

        // Grays
        try self.registerColor(.systemGray, DynamicColor.init(RGBA.fromHex(0xFF8E8E93), RGBA.fromHex(0xFF8E8E93)));

        try self.registerColor(.systemGray2, DynamicColor.init(RGBA.fromHex(0xFFAEAEB2), RGBA.fromHex(0xFF636366)));

        try self.registerColor(.systemGray3, DynamicColor.init(RGBA.fromHex(0xFFC7C7CC), RGBA.fromHex(0xFF48484A)));

        try self.registerColor(.systemGray4, DynamicColor.init(RGBA.fromHex(0xFFD1D1D6), RGBA.fromHex(0xFF3A3A3C)));

        try self.registerColor(.systemGray5, DynamicColor.init(RGBA.fromHex(0xFFE5E5EA), RGBA.fromHex(0xFF2C2C2E)));

        try self.registerColor(.systemGray6, DynamicColor.init(RGBA.fromHex(0xFFF2F2F7), RGBA.fromHex(0xFF1C1C1E)));

        // App specific
        try self.registerColor(.accent, DynamicColor.init(RGBA.fromHex(0xFF007AFF), // Blue in light mode
            RGBA.fromHex(0xFF0A84FF) // Blue in dark mode
        ));

        try self.registerColor(.accentVariant, DynamicColor.init(RGBA.fromHex(0xFF5AC8FA), // Lighter blue in light mode
            RGBA.fromHex(0xFF5AC8FA) // Same in dark mode
        ));

        try self.registerColor(.primary, DynamicColor.init(RGBA.fromHex(0xFF000000), RGBA.fromHex(0xFFFFFFFF)));

        try self.registerColor(.secondary, DynamicColor.init(RGBA.fromHex(0xFF6C6C70), RGBA.fromHex(0xFFAEAEB2)));

        try self.registerColor(.error_color, DynamicColor.init(RGBA.fromHex(0xFFFF3B30), RGBA.fromHex(0xFFFF453A)));

        try self.registerColor(.warning, DynamicColor.init(RGBA.fromHex(0xFFFF9500), RGBA.fromHex(0xFFFF9F0A)));

        try self.registerColor(.success, DynamicColor.init(RGBA.fromHex(0xFF34C759), RGBA.fromHex(0xFF30D158)));

        try self.registerColor(.info, DynamicColor.init(RGBA.fromHex(0xFF5AC8FA), RGBA.fromHex(0xFF64D2FF)));

        try self.registerColor(.clear, DynamicColor.init(RGBA.init(0, 0, 0, 0), RGBA.init(0, 0, 0, 0)));
    }
};

/// Common color constants
pub const Colors = struct {
    pub const transparent = RGBA.init(0, 0, 0, 0);
    pub const black = RGBA.init(0, 0, 0, 1);
    pub const white = RGBA.init(1, 1, 1, 1);
    pub const red = RGBA.init(1, 0, 0, 1);
    pub const green = RGBA.init(0, 1, 0, 1);
    pub const blue = RGBA.init(0, 0, 1, 1);
    pub const yellow = RGBA.init(1, 1, 0, 1);
    pub const cyan = RGBA.init(0, 1, 1, 1);
    pub const magenta = RGBA.init(1, 0, 1, 1);
    pub const orange = RGBA.init(1, 0.5, 0, 1);
    pub const purple = RGBA.init(0.5, 0, 0.5, 1);
    pub const brown = RGBA.init(0.6, 0.4, 0.2, 1);
    pub const pink = RGBA.init(1, 0.75, 0.8, 1);
    pub const gray = RGBA.init(0.5, 0.5, 0.5, 1);
    pub const lightGray = RGBA.init(0.75, 0.75, 0.75, 1);
    pub const darkGray = RGBA.init(0.25, 0.25, 0.25, 1);

    /// Create a color from hex value (0xRRGGBB or 0xAARRGGBB)
    pub fn hex(value: u32) RGBA {
        return RGBA.fromHex(value);
    }

    /// Create a color from RGB values (0-255)
    pub fn rgb(r: u8, g: u8, b: u8) RGBA {
        return RGBA.init(@as(f32, @floatFromInt(r)) / 255.0, @as(f32, @floatFromInt(g)) / 255.0, @as(f32, @floatFromInt(b)) / 255.0, 1.0);
    }

    /// Create a color from RGBA values (0-255)
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) RGBA {
        return RGBA.init(@as(f32, @floatFromInt(r)) / 255.0, @as(f32, @floatFromInt(g)) / 255.0, @as(f32, @floatFromInt(b)) / 255.0, @as(f32, @floatFromInt(a)) / 255.0);
    }

    /// Create a color from HSV values
    pub fn hsv(h: f32, s: f32, v: f32) RGBA {
        return HSV.init(h, s, v, 1.0).toRGBA();
    }

    /// Create a color from HSV values with alpha
    pub fn hsva(h: f32, s: f32, v: f32, a: f32) RGBA {
        return HSV.init(h, s, v, a).toRGBA();
    }
};

test "Color from hex" {
    const testing = std.testing;

    const red = Colors.hex(0xFF0000);
    try testing.expectApproxEqAbs(red.r, 1.0, 0.001);
    try testing.expectApproxEqAbs(red.g, 0.0, 0.001);
    try testing.expectApproxEqAbs(red.b, 0.0, 0.001);
    try testing.expectApproxEqAbs(red.a, 1.0, 0.001);

    const semi_transparent_blue = Colors.hex(0x800000FF);
    try testing.expectApproxEqAbs(semi_transparent_blue.r, 0.0, 0.001);
    try testing.expectApproxEqAbs(semi_transparent_blue.g, 0.0, 0.001);
    try testing.expectApproxEqAbs(semi_transparent_blue.b, 1.0, 0.001);
    try testing.expectApproxEqAbs(semi_transparent_blue.a, 0.5, 0.001);
}

test "HSV to RGB conversion" {
    const testing = std.testing;

    const red = HSV.init(0, 1, 1, 1).toRGBA();
    try testing.expectApproxEqAbs(red.r, 1.0, 0.001);
    try testing.expectApproxEqAbs(red.g, 0.0, 0.001);
    try testing.expectApproxEqAbs(red.b, 0.0, 0.001);

    const green = HSV.init(120, 1, 1, 1).toRGBA();
    try testing.expectApproxEqAbs(green.r, 0.0, 0.001);
    try testing.expectApproxEqAbs(green.g, 1.0, 0.001);
    try testing.expectApproxEqAbs(green.b, 0.0, 0.001);

    const blue = HSV.init(240, 1, 1, 1).toRGBA();
    try testing.expectApproxEqAbs(blue.r, 0.0, 0.001);
    try testing.expectApproxEqAbs(blue.g, 0.0, 0.001);
    try testing.expectApproxEqAbs(blue.b, 1.0, 0.001);
}

test "RGB to HSV conversion" {
    const testing = std.testing;

    const red_hsv = HSV.fromRGBA(RGBA.init(1, 0, 0, 1));
    try testing.expectApproxEqAbs(red_hsv.h, 0.0, 0.001);
    try testing.expectApproxEqAbs(red_hsv.s, 1.0, 0.001);
    try testing.expectApproxEqAbs(red_hsv.v, 1.0, 0.001);

    const green_hsv = HSV.fromRGBA(RGBA.init(0, 1, 0, 1));
    try testing.expectApproxEqAbs(green_hsv.h, 120.0, 0.001);
    try testing.expectApproxEqAbs(green_hsv.s, 1.0, 0.001);
    try testing.expectApproxEqAbs(green_hsv.v, 1.0, 0.001);

    const blue_hsv = HSV.fromRGBA(RGBA.init(0, 0, 1, 1));
    try testing.expectApproxEqAbs(blue_hsv.h, 240.0, 0.001);
    try testing.expectApproxEqAbs(blue_hsv.s, 1.0, 0.001);
    try testing.expectApproxEqAbs(blue_hsv.v, 1.0, 0.001);
}

test "Dynamic color resolving" {
    const testing = std.testing;

    const dynamic_color = DynamicColor.init(RGBA.init(1, 0, 0, 1), // Light mode: Red
        RGBA.init(0, 0, 1, 1) // Dark mode: Blue
    );

    const light_color = dynamic_color.resolve(.light);
    try testing.expectApproxEqAbs(light_color.r, 1.0, 0.001);
    try testing.expectApproxEqAbs(light_color.g, 0.0, 0.001);
    try testing.expectApproxEqAbs(light_color.b, 0.0, 0.001);

    const dark_color = dynamic_color.resolve(.dark);
    try testing.expectApproxEqAbs(dark_color.r, 0.0, 0.001);
    try testing.expectApproxEqAbs(dark_color.g, 0.0, 0.001);
    try testing.expectApproxEqAbs(dark_color.b, 1.0, 0.001);
}

test "Color registry" {
    const testing = std.testing;
    var registry = try ColorRegistry.init(testing.allocator);
    defer registry.deinit();

    // Test default color
    const accent_light = registry.color(.accent);
    try testing.expectApproxEqAbs(accent_light.r, 0.0, 0.001);
    try testing.expectApproxEqAbs(accent_light.g, 0.478, 0.001);
    try testing.expectApproxEqAbs(accent_light.b, 1.0, 0.001);

    // Change appearance
    registry.setAppearance(.dark);
    const accent_dark = registry.color(.accent);
    try testing.expectApproxEqAbs(accent_dark.r, 0.039, 0.001);
    try testing.expectApproxEqAbs(accent_dark.g, 0.518, 0.001);
    try testing.expectApproxEqAbs(accent_dark.b, 1.0, 0.001);

    // Register custom color
    try registry.registerColor(.accent, DynamicColor.init(RGBA.init(1, 0, 0, 1), // Custom light
        RGBA.init(0, 1, 0, 1) // Custom dark
    ));

    const custom_light = registry.color(.accent);
    try testing.expectApproxEqAbs(custom_light.r, 0.0, 0.001);
    try testing.expectApproxEqAbs(custom_light.g, 1.0, 0.001);
    try testing.expectApproxEqAbs(custom_light.b, 0.0, 0.001);
    registry.setAppearance(.light);
    const custom_accent_light = registry.color(.accent);
    try testing.expectApproxEqAbs(custom_accent_light.r, 1.0, 0.001);
    try testing.expectApproxEqAbs(custom_accent_light.g, 0.0, 0.001);
    try testing.expectApproxEqAbs(custom_accent_light.b, 0.0, 0.001);
}
