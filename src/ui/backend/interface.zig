const std = @import("std");
const Allocator = std.mem.Allocator;

/// Specifies the graphics backend to use for rendering
pub const BackendType = enum {
    gdi,
    vulkan,
    opengl,
    software,
};

/// Represents an RGBA color with floating-point components in the range [0.0, 1.0]
pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    /// Creates a color from RGBA components
    pub fn fromRgba(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Creates a color from a 32-bit hex value (0xAARRGGBB)
    pub fn fromHex(hex: u32) Color {
        const r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0;
        const g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0;
        const b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0;
        const a = @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0;
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Converts the color to a 32-bit ARGB value
    pub fn toU32(self: Color) u32 {
        const r = @as(u32, @intFromFloat(self.r * 255.0)) & 0xFF;
        const g = @as(u32, @intFromFloat(self.g * 255.0)) & 0xFF;
        const b = @as(u32, @intFromFloat(self.b * 255.0)) & 0xFF;
        const a = @as(u32, @intFromFloat(self.a * 255.0)) & 0xFF;
        return (a << 24) | (r << 16) | (g << 8) | b;
    }
};

/// Represents a rectangle with position and dimensions
pub const Rect = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// Creates a new rectangle with the specified parameters
    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    /// Checks if a point is inside the rectangle
    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.width and
            py >= self.y and py < self.y + self.height;
    }

    /// Checks if this rectangle overlaps with another rectangle
    pub fn overlaps(self: Rect, other: Rect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }
};

/// Horizontal text alignment options
pub const TextAlign = enum {
    left,
    center,
    right,
};

/// Font styling options
pub const FontStyle = struct {
    size: f32 = 14.0,
    weight: u32 = 400, // 400 = normal, 700 = bold
    italic: bool = false,
    underline: bool = false,
};

/// Information needed to identify and render a font
pub const FontInfo = struct {
    name: []const u8,
    style: FontStyle,
};

/// Represents an image in memory
pub const Image = struct {
    handle: usize,
    width: u32,
    height: u32,
    format: ImageFormat,

    /// Supported pixel formats for images
    pub const ImageFormat = enum {
        rgba8,
        bgra8,
        rgb8,
        bgr8,
    };
};

/// Represents a single drawing operation
pub const DrawCommand = union(enum) {
    clear: Color,
    rect: struct {
        rect: Rect,
        color: Color,
        border_radius: f32 = 0.0,
        border_width: f32 = 0.0,
        border_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
    },
    text: struct {
        rect: Rect,
        text: []const u8,
        color: Color,
        font: FontInfo,
        align_: TextAlign = .left, // Renamed from 'align' to 'align_' to avoid keyword conflict
    },
    image: struct {
        rect: Rect,
        image: *const Image,
    },
    clip_push: Rect,
    clip_pop: void,
    custom: struct {
        data: *anyopaque,
        callback: *const fn (data: *anyopaque, backend_data: *anyopaque) void,
    },
};

/// Interface that defines the rendering backend functionality
pub const BackendInterface = struct {
    init_fn: *const fn (allocator: Allocator, window_handle: usize) anyerror!*anyopaque,
    deinit_fn: *const fn (ctx: *anyopaque) void,
    begin_frame_fn: *const fn (ctx: *anyopaque, width: u32, height: u32) void,
    end_frame_fn: *const fn (ctx: *anyopaque) void,
    execute_draw_commands_fn: *const fn (ctx: *anyopaque, commands: []const DrawCommand) void,
    create_image_fn: *const fn (ctx: *anyopaque, width: u32, height: u32, pixels: [*]const u8, format: Image.ImageFormat) anyerror!Image,
    destroy_image_fn: *const fn (ctx: *anyopaque, image: *Image) void,
    get_text_size_fn: *const fn (ctx: *anyopaque, text: []const u8, font: FontInfo) struct { width: f32, height: f32 },
    resize_fn: *const fn (ctx: *anyopaque, width: u32, height: u32) void,
    get_last_error_fn: ?*const fn (ctx: *anyopaque) ?[]const u8,
    backend_type: BackendType,
};

/// A rendering backend implementation with a virtual table interface
pub const UIBackend = struct {
    ctx: *anyopaque,
    vtable: *const BackendInterface,
    last_error: ?[]const u8,

    /// Initialize a rendering backend with the given interface and window handle
    pub fn init(allocator: Allocator, vtable: *const BackendInterface, window_handle: usize) !UIBackend {
        const ctx = try vtable.init_fn(allocator, window_handle);
        return UIBackend{
            .ctx = ctx,
            .vtable = vtable,
            .last_error = null,
        };
    }

    /// Clean up and release resources
    pub fn deinit(self: *UIBackend) void {
        self.vtable.deinit_fn(self.ctx);
    }

    /// Begin a new frame with the specified dimensions
    pub fn beginFrame(self: *UIBackend, width: u32, height: u32) void {
        self.vtable.begin_frame_fn(self.ctx, width, height);
    }

    /// End the current frame and flush rendering commands
    pub fn endFrame(self: *UIBackend) void {
        self.vtable.end_frame_fn(self.ctx);
    }

    /// Execute a list of drawing commands
    pub fn executeDrawCommands(self: *UIBackend, commands: []const DrawCommand) void {
        self.vtable.execute_draw_commands_fn(self.ctx, commands);
    }

    /// Create a new image from pixel data
    pub fn createImage(self: *UIBackend, width: u32, height: u32, pixels: [*]const u8, format: Image.ImageFormat) !Image {
        return self.vtable.create_image_fn(self.ctx, width, height, pixels, format);
    }

    /// Release an image's resources
    pub fn destroyImage(self: *UIBackend, image: *Image) void {
        self.vtable.destroy_image_fn(self.ctx, image);
    }

    /// Calculate the size of text with the given font
    pub fn getTextSize(self: *UIBackend, text: []const u8, font: FontInfo) struct { width: f32, height: f32 } {
        return self.vtable.get_text_size_fn(self.ctx, text, font);
    }

    /// Handle window resize events
    pub fn resize(self: *UIBackend, width: u32, height: u32) void {
        self.vtable.resize_fn(self.ctx, width, height);
    }

    /// Get the type of this backend
    pub fn getBackendType(self: *const UIBackend) BackendType {
        return self.vtable.backend_type;
    }

    /// Get the last error message if any
    pub fn getLastError(self: *const UIBackend) ?[]const u8 {
        if (self.vtable.get_last_error_fn) |get_error| {
            return get_error(self.ctx);
        }
        return null;
    }
};
