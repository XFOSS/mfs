const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Vec4 = @import("../math/vec4.zig").Vec4f;
const color = @import("color.zig");
const color_bridge = @import("color_bridge.zig");
const ui_framework = @import("ui_framework.zig");
const view_modifiers = @import("view_modifiers.zig");

// MARK: - State Management

/// State wrapper for reactive UI updates
pub fn State(comptime T: type) type {
    return struct {
        value: T,
        observers: ArrayList(*const fn (T) void),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator, initial_value: T) Self {
            return Self{
                .value = initial_value,
                .observers = ArrayList(*const fn (T) void).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.observers.deinit();
        }

        pub fn get(self: *const Self) T {
            return self.value;
        }

        pub fn set(self: *Self, new_value: T) void {
            self.value = new_value;
            self.notifyObservers();
        }

        pub fn addObserver(self: *Self, observer: *const fn (T) void) !void {
            try self.observers.append(observer);
        }

        fn notifyObservers(self: *Self) void {
            for (self.observers.items) |observer| {
                observer(self.value);
            }
        }

        pub fn wrappedValue(self: *Self) *T {
            return &self.value;
        }

        pub fn projectedValue(self: *Self) Binding(T) {
            return Binding(T).init(self);
        }
    };
}

/// Binding wrapper for two-way data flow
pub fn Binding(comptime T: type) type {
    return struct {
        get_fn: *const fn () T,
        set_fn: *const fn (T) void,

        const Self = @This();

        pub fn init(state: *State(T)) Self {
            return Self{
                .get_fn = &state.get,
                .set_fn = &state.set,
            };
        }

        pub fn get(self: *const Self) T {
            return self.get_fn();
        }

        pub fn set(self: *const Self, value: T) void {
            self.set_fn(value);
        }

        pub fn wrappedValue(self: *const Self) T {
            return self.get();
        }
    };
}

// MARK: - View Protocol

/// Core View protocol that all SwiftUI-like views must implement
pub const ViewProtocol = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        body: *const fn (ptr: *anyopaque, allocator: Allocator) anyerror!ViewProtocol,
        render: *const fn (ptr: *anyopaque, context: *RenderContext) anyerror!void,
        layout: *const fn (ptr: *anyopaque, proposed_size: Size) Size,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn body(self: ViewProtocol, allocator: Allocator) !ViewProtocol {
        return self.vtable.body(self.ptr, allocator);
    }

    pub fn render(self: ViewProtocol, context: *RenderContext) !void {
        return self.vtable.render(self.ptr, context);
    }

    pub fn layout(self: ViewProtocol, proposed_size: Size) Size {
        return self.vtable.layout(self.ptr, proposed_size);
    }

    pub fn deinit(self: ViewProtocol) void {
        self.vtable.deinit(self.ptr);
    }
};

// MARK: - Core Types

pub const Size = struct {
    width: f32,
    height: f32,

    pub const zero = Size{ .width = 0, .height = 0 };
    pub const infinity = Size{ .width = std.math.inf(f32), .height = std.math.inf(f32) };

    pub fn init(width: f32, height: f32) Size {
        return Size{ .width = width, .height = height };
    }

    pub fn isFinite(self: Size) bool {
        return std.math.isFinite(self.width) and std.math.isFinite(self.height);
    }
};

pub const Point = struct {
    x: f32,
    y: f32,

    pub const zero = Point{ .x = 0, .y = 0 };

    pub fn init(x: f32, y: f32) Point {
        return Point{ .x = x, .y = y };
    }
};

pub const Rect = struct {
    origin: Point,
    size: Size,

    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return Rect{
            .origin = Point.init(x, y),
            .size = Size.init(width, height),
        };
    }

    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.origin.x and
            point.x <= self.origin.x + self.size.width and
            point.y >= self.origin.y and
            point.y <= self.origin.y + self.size.height;
    }
};

pub const RenderContext = struct {
    allocator: Allocator,
    color_registry: *color.ColorRegistry,
    frame: Rect,
    theme: ui_framework.Theme,

    pub fn init(allocator: Allocator, color_registry: *color.ColorRegistry, frame: Rect, theme: ui_framework.Theme) RenderContext {
        return RenderContext{
            .allocator = allocator,
            .color_registry = color_registry,
            .frame = frame,
            .theme = theme,
        };
    }
};

// MARK: - Alignment

pub const Alignment = enum {
    leading,
    center,
    trailing,
    top,
    bottom,
    topLeading,
    topTrailing,
    bottomLeading,
    bottomTrailing,
};

pub const HorizontalAlignment = enum {
    leading,
    center,
    trailing,
};

pub const VerticalAlignment = enum {
    top,
    center,
    bottom,
};

// MARK: - Basic Views

pub const Text = struct {
    content: []const u8,
    font_size: f32,
    color: color.RGBA,
    alignment: Alignment,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, content: []const u8) Self {
        return Self{
            .content = content,
            .font_size = 16.0,
            .color = color.Constants.black,
            .alignment = .leading,
            .allocator = allocator,
        };
    }

    pub fn fontSize(self: Self, size: f32) Self {
        var new_self = self;
        new_self.font_size = size;
        return new_self;
    }

    pub fn foregroundColor(self: Self, text_color: color.RGBA) Self {
        var new_self = self;
        new_self.color = text_color;
        return new_self;
    }

    pub fn foregroundColorVec4(self: Self, vec: Vec4) Self {
        var new_self = self;
        new_self.color = color_bridge.vec4ToColor(vec);
        return new_self;
    }

    pub fn multilineTextAlignment(self: Self, alignment_value: Alignment) Self {
        var new_self = self;
        new_self.alignment = alignment_value;
        return new_self;
    }

    pub fn view(self: *Self) ViewProtocol {
        return ViewProtocol{
            .ptr = self,
            .vtable = &text_vtable,
        };
    }

    fn bodyImpl(ptr: *anyopaque, allocator: Allocator) anyerror!ViewProtocol {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.view();
    }

    fn renderImpl(ptr: *anyopaque, context: *RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        // Render text using the existing UI framework
        // This would integrate with your existing text rendering system
        _ = self;
        _ = context;
        // TODO: Implement actual text rendering
    }

    fn layoutImpl(ptr: *anyopaque, proposed_size: Size) Size {
        const self: *Self = @ptrCast(@alignCast(ptr));
        // Calculate text size based on content and font
        const estimated_width = @as(f32, @floatFromInt(self.content.len)) * self.font_size * 0.6;
        const estimated_height = self.font_size * 1.2;

        return Size.init(@min(estimated_width, proposed_size.width), @min(estimated_height, proposed_size.height));
    }

    fn deinitImpl(ptr: *anyopaque) void {
        _ = ptr;
        // Text doesn't own any allocated memory in this simple implementation
    }

    const text_vtable = ViewProtocol.VTable{
        .body = bodyImpl,
        .render = renderImpl,
        .layout = layoutImpl,
        .deinit = deinitImpl,
    };
};

pub const Button = struct {
    content: ViewProtocol,
    action: *const fn () void,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, content: ViewProtocol, action: *const fn () void) Self {
        return Self{
            .content = content,
            .action = action,
            .allocator = allocator,
        };
    }

    pub fn view(self: *Self) ViewProtocol {
        return ViewProtocol{
            .ptr = self,
            .vtable = &button_vtable,
        };
    }

    fn bodyImpl(ptr: *anyopaque, allocator: Allocator) anyerror!ViewProtocol {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.view();
    }

    fn renderImpl(ptr: *anyopaque, context: *RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        // Render button background
        // Then render content
        try self.content.render(context);
    }

    fn layoutImpl(ptr: *anyopaque, proposed_size: Size) Size {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const content_size = self.content.layout(proposed_size);
        // Add padding for button
        return Size.init(content_size.width + 20, // 10px padding on each side
            content_size.height + 16 // 8px padding top and bottom
        );
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.content.deinit();
    }

    const button_vtable = ViewProtocol.VTable{
        .body = bodyImpl,
        .render = renderImpl,
        .layout = layoutImpl,
        .deinit = deinitImpl,
    };
};

// MARK: - Layout Containers

pub const VStack = struct {
    children: []ViewProtocol,
    alignment: HorizontalAlignment,
    spacing: f32,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, children: []ViewProtocol) Self {
        return Self{
            .children = children,
            .alignment = .leading,
            .spacing = 8.0,
            .allocator = allocator,
        };
    }

    pub fn alignment(self: Self, alignment: HorizontalAlignment) Self {
        var new_self = self;
        new_self.alignment = alignment;
        return new_self;
    }

    pub fn spacing(self: Self, space: f32) Self {
        var new_self = self;
        new_self.spacing = space;
        return new_self;
    }

    pub fn view(self: *Self) ViewProtocol {
        return ViewProtocol{
            .ptr = self,
            .vtable = &vstack_vtable,
        };
    }

    fn bodyImpl(ptr: *anyopaque, allocator: Allocator) anyerror!ViewProtocol {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.view();
    }

    fn renderImpl(ptr: *anyopaque, context: *RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        var y_offset: f32 = 0;

        for (self.children) |child| {
            var child_context = context.*;
            child_context.frame.origin.y += y_offset;

            try child.render(&child_context);

            const child_size = child.layout(context.frame.size);
            y_offset += child_size.height + self.spacing;
        }
    }

    fn layoutImpl(ptr: *anyopaque, proposed_size: Size) Size {
        const self: *Self = @ptrCast(@alignCast(ptr));
        var total_height: f32 = 0;
        var max_width: f32 = 0;

        for (self.children, 0..) |child, i| {
            const child_size = child.layout(proposed_size);
            max_width = @max(max_width, child_size.width);
            total_height += child_size.height;

            if (i < self.children.len - 1) {
                total_height += self.spacing;
            }
        }

        return Size.init(@min(max_width, proposed_size.width), @min(total_height, proposed_size.height));
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.children) |child| {
            child.deinit();
        }
    }

    const vstack_vtable = ViewProtocol.VTable{
        .body = bodyImpl,
        .render = renderImpl,
        .layout = layoutImpl,
        .deinit = deinitImpl,
    };
};

pub const HStack = struct {
    children: []ViewProtocol,
    alignment: VerticalAlignment,
    spacing: f32,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, children: []ViewProtocol) Self {
        return Self{
            .children = children,
            .alignment = .center,
            .spacing = 8.0,
            .allocator = allocator,
        };
    }

    pub fn alignment(self: Self, alignment: VerticalAlignment) Self {
        var new_self = self;
        new_self.alignment = alignment;
        return new_self;
    }

    pub fn spacing(self: Self, space: f32) Self {
        var new_self = self;
        new_self.spacing = space;
        return new_self;
    }

    pub fn view(self: *Self) ViewProtocol {
        return ViewProtocol{
            .ptr = self,
            .vtable = &hstack_vtable,
        };
    }

    fn bodyImpl(ptr: *anyopaque, allocator: Allocator) anyerror!ViewProtocol {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.view();
    }

    fn renderImpl(ptr: *anyopaque, context: *RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        var x_offset: f32 = 0;

        for (self.children) |child| {
            var child_context = context.*;
            child_context.frame.origin.x += x_offset;

            try child.render(&child_context);

            const child_size = child.layout(context.frame.size);
            x_offset += child_size.width + self.spacing;
        }
    }

    fn layoutImpl(ptr: *anyopaque, proposed_size: Size) Size {
        const self: *Self = @ptrCast(@alignCast(ptr));
        var total_width: f32 = 0;
        var max_height: f32 = 0;

        for (self.children, 0..) |child, i| {
            const child_size = child.layout(proposed_size);
            max_height = @max(max_height, child_size.height);
            total_width += child_size.width;

            if (i < self.children.len - 1) {
                total_width += self.spacing;
            }
        }

        return Size.init(@min(total_width, proposed_size.width), @min(max_height, proposed_size.height));
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.children) |child| {
            child.deinit();
        }
    }

    const hstack_vtable = ViewProtocol.VTable{
        .body = bodyImpl,
        .render = renderImpl,
        .layout = layoutImpl,
        .deinit = deinitImpl,
    };
};

pub const ZStack = struct {
    children: []ViewProtocol,
    alignment: Alignment,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, children: []ViewProtocol) Self {
        return Self{
            .children = children,
            .alignment = .center,
            .allocator = allocator,
        };
    }

    pub fn alignment(self: Self, alignment: Alignment) Self {
        var new_self = self;
        new_self.alignment = alignment;
        return new_self;
    }

    pub fn view(self: *Self) ViewProtocol {
        return ViewProtocol{
            .ptr = self,
            .vtable = &zstack_vtable,
        };
    }

    fn bodyImpl(ptr: *anyopaque, allocator: Allocator) anyerror!ViewProtocol {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.view();
    }

    fn renderImpl(ptr: *anyopaque, context: *RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        for (self.children) |child| {
            try child.render(context);
        }
    }

    fn layoutImpl(ptr: *anyopaque, proposed_size: Size) Size {
        const self: *Self = @ptrCast(@alignCast(ptr));
        var max_width: f32 = 0;
        var max_height: f32 = 0;

        for (self.children) |child| {
            const child_size = child.layout(proposed_size);
            max_width = @max(max_width, child_size.width);
            max_height = @max(max_height, child_size.height);
        }

        return Size.init(@min(max_width, proposed_size.width), @min(max_height, proposed_size.height));
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        for (self.children) |child| {
            child.deinit();
        }
    }

    const zstack_vtable = ViewProtocol.VTable{
        .body = bodyImpl,
        .render = renderImpl,
        .layout = layoutImpl,
        .deinit = deinitImpl,
    };
};

// MARK: - Environment and App

pub const EnvironmentValues = struct {
    color_scheme: color.Appearance,
    font_size: f32,
    color_registry: *color.ColorRegistry,

    pub fn init(color_registry: *color.ColorRegistry) EnvironmentValues {
        return EnvironmentValues{
            .color_scheme = .light,
            .font_size = 16.0,
            .color_registry = color_registry,
        };
    }
};

pub const App = struct {
    allocator: Allocator,
    color_registry: *color.ColorRegistry,
    environment: EnvironmentValues,
    root_view: ?ViewProtocol,

    const Self = @This();

    pub fn init(allocator: Allocator, color_registry: *color.ColorRegistry) Self {
        return Self{
            .allocator = allocator,
            .color_registry = color_registry,
            .environment = EnvironmentValues.init(color_registry),
            .root_view = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.root_view) |view| {
            view.deinit();
        }
    }

    pub fn setRootView(self: *Self, view: ViewProtocol) void {
        self.root_view = view;
    }

    pub fn render(self: *Self, frame: Rect, theme: ui_framework.Theme) !void {
        if (self.root_view) |view| {
            var context = RenderContext.init(self.allocator, self.color_registry, frame, theme);
            try view.render(&context);
        }
    }

    pub fn setColorScheme(self: *Self, scheme: color.Appearance) void {
        self.environment.color_scheme = scheme;
        self.color_registry.setAppearance(scheme);
    }
};

// MARK: - Convenience Functions

pub fn text(allocator: Allocator, content: []const u8) Text {
    return Text.init(allocator, content);
}

pub fn button(allocator: Allocator, content: ViewProtocol, action: *const fn () void) Button {
    return Button.init(allocator, content, action);
}

pub fn vstack(allocator: Allocator, children: []ViewProtocol) VStack {
    return VStack.init(allocator, children);
}

pub fn hstack(allocator: Allocator, children: []ViewProtocol) HStack {
    return HStack.init(allocator, children);
}

pub fn zstack(allocator: Allocator, children: []ViewProtocol) ZStack {
    return ZStack.init(allocator, children);
}

// MARK: - Tests

test "State management" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = State(i32).init(allocator, 42);
    defer state.deinit();

    try testing.expect(state.get() == 42);

    state.set(100);
    try testing.expect(state.get() == 100);
}

test "Text view creation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var text_view = text(allocator, "Hello World");
    text_view = text_view.fontSize(20.0);
    text_view = text_view.foregroundColor(color.Constants.blue);

    try testing.expect(text_view.font_size == 20.0);
    try testing.expect(text_view.color.r == 0.0);
    try testing.expect(text_view.color.g == 0.0);
    try testing.expect(text_view.color.b == 1.0);
}

test "Layout sizing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var text_view = text(allocator, "Test");
    const view_protocol = text_view.view();

    const size = view_protocol.layout(Size.init(200, 100));
    try testing.expect(size.width > 0);
    try testing.expect(size.height > 0);
}
