const std = @import("std");
const Allocator = std.mem.Allocator;
const color_pkg = @import("color.zig");

// Basic geometry types
pub const Size = struct {
    width: f32,
    height: f32,

    pub fn init(width: f32, height: f32) Size {
        return Size{ .width = width, .height = height };
    }
};

pub const Point = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Point {
        return Point{ .x = x, .y = y };
    }
};

pub const Rect = struct {
    origin: Point,
    size: Size,

    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return Rect{ .origin = Point.init(x, y), .size = Size.init(width, height) };
    }
};

// Simple alignment enum (extend later if needed)
pub const Alignment = enum {
    center,
    leading,
    trailing,
    top,
    bottom,
};

// Forward declaration of ColorRegistry so we avoid circular deps
pub const ColorRegistry = color_pkg.ColorRegistry;

// Render context used during drawing operations
pub const RenderContext = struct {
    frame: Rect,
    color_registry: *ColorRegistry,
};

// Lightweight virtualised view protocol used by existing modifiers
pub const ViewProtocol = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        body: fn (*anyopaque) ViewProtocol,
        render: fn (*anyopaque, *RenderContext) void,
        layout: fn (*anyopaque, Size) Size,
        deinit: fn (*anyopaque) void,
    };

    pub fn body(self: ViewProtocol) ViewProtocol {
        return self.vtable.body(self.ptr);
    }

    pub fn render(self: ViewProtocol, context: *RenderContext) void {
        self.vtable.render(self.ptr, context);
    }

    pub fn layout(self: ViewProtocol, proposed: Size) Size {
        return self.vtable.layout(self.ptr, proposed);
    }

    pub fn deinit(self: ViewProtocol) void {
        self.vtable.deinit(self.ptr);
    }
};

// -------------------------------------------------------------
// A very small "Text" view implementation sufficient for tests
// -------------------------------------------------------------

pub const TextView = struct {
    allocator: Allocator,
    text: []const u8,
    font_size: f32 = 12.0,

    const Self = @This();

    pub fn fontSize(self: Self, new_size: f32) Self {
        var updated = self;
        updated.font_size = new_size;
        return updated;
    }

    pub fn view(self: Self) !ViewProtocol {
        const self_ptr = try self.allocator.create(Self);
        self_ptr.* = self;
        return ViewProtocol{ .ptr = self_ptr, .vtable = &text_vtable };
    }

    fn bodyImpl(_ptr: *anyopaque) ViewProtocol {
        // Leaf views simply return themselves
        return ViewProtocol{ .ptr = _ptr, .vtable = &text_vtable };
    }

    fn renderImpl(_: *anyopaque, _: *RenderContext) void {
        // No-op for stub implementation
    }

    fn layoutImpl(_: *anyopaque, proposed: Size) Size {
        // For stub, just return proposed size so layouts succeed
        return proposed;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    const text_vtable = ViewProtocol.VTable{
        .body = bodyImpl,
        .render = renderImpl,
        .layout = layoutImpl,
        .deinit = deinitImpl,
    };
};

pub fn text(allocator: Allocator, content: []const u8) !TextView {
    return TextView{
        .allocator = allocator,
        .text = try allocator.dupe(u8, content),
        .font_size = 12.0,
    };
}

// -------------------------------------------
// Minimal App wrapper required by framework.zig
// -------------------------------------------

pub const App = struct {
    allocator: Allocator,
    color_registry: *ColorRegistry,

    pub fn init(allocator: Allocator, registry: *ColorRegistry) App {
        return App{ .allocator = allocator, .color_registry = registry };
    }

    pub fn deinit(self: *App) void {
        _ = self; // Nothing to clean in stub
    }
};
