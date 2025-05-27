const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Vec4 = @import("../math/vec4.zig").Vec4f;

pub const UiConfig = struct {
    enable_immediate_mode: bool = true,
    enable_retained_mode: bool = false,
    default_font_size: f32 = 14.0,
    default_spacing: f32 = 8.0,
    default_padding: f32 = 10.0,
    theme: Theme = .dark,
    animation_speed: f32 = 0.3,
    enable_transitions: bool = true,
    enable_gestures: bool = true,
};

pub const Theme = enum {
    dark,
    light,
    custom,

    pub fn getBackgroundColor(self: Theme) Vec4 {
        return switch (self) {
            .dark => Vec4.init(0.12, 0.12, 0.12, 1.0),
            .light => Vec4.init(0.95, 0.95, 0.95, 1.0),
            .custom => Vec4.init(0.2, 0.3, 0.4, 1.0),
        };
    }

    pub fn getTextColor(self: Theme) Vec4 {
        return switch (self) {
            .dark => Vec4.init(0.9, 0.9, 0.9, 1.0),
            .light => Vec4.init(0.1, 0.1, 0.1, 1.0),
            .custom => Vec4.init(0.9, 0.9, 0.9, 1.0),
        };
    }

    pub fn getAccentColor(self: Theme) Vec4 {
        return switch (self) {
            .dark => Vec4.init(0.0, 0.5, 1.0, 1.0),
            .light => Vec4.init(0.0, 0.4, 0.9, 1.0),
            .custom => Vec4.init(0.8, 0.2, 0.3, 1.0),
        };
    }
};

pub const WidgetType = enum {
    basic,
    button,
    text,
    image,
    toggle,
    slider,
    textfield,
    container,
};

pub const GestureState = enum {
    none,
    hover,
    pressed,
    dragging,
};

pub const WidgetStyle = struct {
    background_color: ?Vec4 = null,
    border_color: ?Vec4 = null,
    text_color: ?Vec4 = null,
    border_width: f32 = 0.0,
    corner_radius: f32 = 0.0,
    padding: f32 = 10.0,
    shadow_radius: f32 = 0.0,
    shadow_offset_x: f32 = 0.0,
    shadow_offset_y: f32 = 0.0,
    shadow_color: Vec4 = Vec4.init(0, 0, 0, 0.5),
};

pub const Widget = struct {
    id: u32,
    type: WidgetType,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    visible: bool = true,
    enabled: bool = true,
    parent_id: ?u32 = null,
    children: ArrayList(u32),
    style: WidgetStyle = .{},
    text: ?[]const u8 = null,
    value: f32 = 0.0, // For sliders, toggles, etc.
    gesture_state: GestureState = .none,
    on_click: ?*const fn (*Widget) void = null,
    on_hover: ?*const fn (*Widget) void = null,
    on_drag: ?*const fn (*Widget, f32, f32) void = null,

    allocator: Allocator,

    pub fn init(allocator: Allocator, id: u32, widget_type: WidgetType, x: f32, y: f32, width: f32, height: f32) !Widget {
        return Widget{
            .id = id,
            .type = widget_type,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .children = ArrayList(u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Widget) void {
        if (self.text) |t| {
            self.allocator.free(t);
        }
        self.children.deinit();
    }

    pub fn addChild(self: *Widget, child_id: u32) !void {
        try self.children.append(child_id);
    }

    pub fn removeChild(self: *Widget, child_id: u32) bool {
        for (self.children.items, 0..) |id, i| {
            if (id == child_id) {
                _ = self.children.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn setText(self: *Widget, text: []const u8) !void {
        if (self.text) |t| {
            self.allocator.free(t);
        }
        self.text = try self.allocator.dupe(u8, text);
    }

    pub fn setStyle(self: *Widget, style: WidgetStyle) void {
        self.style = style;
    }

    pub fn contains(self: Widget, point_x: f32, point_y: f32) bool {
        return point_x >= self.x and
            point_x <= self.x + self.width and
            point_y >= self.y and
            point_y <= self.y + self.height;
    }
};

pub const UiSystem = struct {
    allocator: Allocator,
    config: UiConfig,
    widgets: ArrayList(Widget),
    widget_map: AutoHashMap(u32, usize),
    next_id: u32 = 1,
    active_id: ?u32 = null,
    hovered_id: ?u32 = null,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_pressed: bool = false,
    initialized: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, config: UiConfig) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .widgets = ArrayList(Widget).init(allocator),
            .widget_map = AutoHashMap(u32, usize).init(allocator),
            .initialized = true,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.widgets.items) |*widget| {
            widget.deinit();
        }
        self.widgets.deinit();
        self.widget_map.deinit();
        self.initialized = false;
    }

    pub fn update(self: *Self, delta_time: f64) !void {
        // Update gesture states
        if (self.config.enable_gestures) {
            try self.updateGestureStates();
        }

        // Update animations if enabled
        if (self.config.enable_transitions) {
            try self.updateAnimations(delta_time);
        }

        // Process layout if needed
        try self.updateLayout();
    }

    fn updateGestureStates(self: *Self) !void {
        // Update hover states
        var new_hovered_id: ?u32 = null;
        for (self.widgets.items) |widget| {
            if (widget.visible and widget.enabled and widget.contains(self.mouse_x, self.mouse_y)) {
                new_hovered_id = widget.id;
                break;
            }
        }

        // Update the currently hovered widget
        if (self.hovered_id != new_hovered_id) {
            if (self.hovered_id) |id| {
                if (self.getWidget(id)) |widget| {
                    if (widget.gesture_state == .hover) {
                        widget.gesture_state = .none;
                    }
                }
            }

            self.hovered_id = new_hovered_id;

            if (new_hovered_id) |id| {
                if (self.getWidget(id)) |widget| {
                    widget.gesture_state = .hover;
                    if (widget.on_hover) |callback| {
                        callback(widget);
                    }
                }
            }
        }

        // Handle mouse press/release
        if (self.mouse_pressed) {
            if (self.active_id == null and self.hovered_id != null) {
                self.active_id = self.hovered_id;
                if (self.getWidget(self.active_id.?)) |widget| {
                    widget.gesture_state = .pressed;
                }
            }
        } else {
            if (self.active_id) |id| {
                if (self.getWidget(id)) |widget| {
                    if (widget.gesture_state == .pressed) {
                        // Click completed
                        if (widget.contains(self.mouse_x, self.mouse_y)) {
                            if (widget.on_click) |callback| {
                                callback(widget);
                            }
                        }
                        widget.gesture_state = if (widget.contains(self.mouse_x, self.mouse_y)) .hover else .none;
                    } else if (widget.gesture_state == .dragging) {
                        widget.gesture_state = if (widget.contains(self.mouse_x, self.mouse_y)) .hover else .none;
                    }
                }
                self.active_id = null;
            }
        }
    }

    fn updateLayout(self: *Self) !void {
        // Simple layout logic - update positions of child widgets
        for (self.widgets.items) |*widget| {
            if (widget.parent_id == null) continue;

            // Position children within parent bounds
            if (self.getWidget(widget.parent_id.?)) |parent| {
                for (parent.children.items, 0..) |child_id, i| {
                    if (self.getWidget(child_id)) |child| {
                        // Simple vertical layout
                        child.x = parent.x + parent.style.padding;
                        child.y = parent.y + parent.style.padding + @as(f32, @floatFromInt(i)) *
                            (child.height + self.config.default_spacing);

                        // Constrain width to parent
                        child.width = @min(child.width, parent.width - 2 * parent.style.padding);
                    }
                }
            }
        }
    }

    pub fn render(self: *Self) !void {
        // Render widgets in order (parents first, then children)
        for (self.widgets.items) |widget| {
            if (!widget.visible) continue;

            try self.renderWidget(&widget);
        }
    }

    fn renderWidget(self: *Self, widget: *const Widget) !void {
        _ = self;
        _ = widget;
        // Actual rendering would go here, perhaps using callbacks to a graphics API
        // Example:
        // 1. Draw background with widget.style.background_color or theme default
        // 2. Draw borders if widget.style.border_width > 0
        // 3. Draw text if widget.text != null
        // 4. Apply special rendering based on widget.type
    }

    pub fn createWidget(self: *Self, widget_type: WidgetType, x: f32, y: f32, width: f32, height: f32) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        const widget = try Widget.init(self.allocator, id, widget_type, x, y, width, height);
        try self.widgets.append(widget);
        try self.widget_map.put(id, self.widgets.items.len - 1);

        return id;
    }

    pub fn createButton(self: *Self, x: f32, y: f32, width: f32, height: f32, label: []const u8) !u32 {
        const id = try self.createWidget(.button, x, y, width, height);
        if (self.getWidget(id)) |widget| {
            try widget.setText(label);

            // Set default button style
            widget.style = .{
                .background_color = self.config.theme.getAccentColor(),
                .text_color = Vec4.init(1, 1, 1, 1),
                .corner_radius = 4.0,
                .padding = 8.0,
            };
        }
        return id;
    }

    pub fn createText(self: *Self, x: f32, y: f32, width: f32, height: f32, text: []const u8) !u32 {
        const id = try self.createWidget(.text, x, y, width, height);
        if (self.getWidget(id)) |widget| {
            try widget.setText(text);
            widget.style.text_color = self.config.theme.getTextColor();
        }
        return id;
    }

    pub fn createContainer(self: *Self, x: f32, y: f32, width: f32, height: f32) !u32 {
        const id = try self.createWidget(.container, x, y, width, height);
        if (self.getWidget(id)) |widget| {
            widget.style = .{
                .background_color = self.config.theme.getBackgroundColor(),
                .padding = self.config.default_padding,
            };
        }
        return id;
    }

    pub fn addChildToWidget(self: *Self, parent_id: u32, child_id: u32) !void {
        if (self.getWidget(parent_id)) |parent| {
            try parent.addChild(child_id);

            if (self.getWidget(child_id)) |child| {
                child.parent_id = parent_id;
            }
        }
    }

    pub fn addWidget(self: *Self, widget: Widget) !void {
        try self.widgets.append(widget);
        try self.widget_map.put(widget.id, self.widgets.items.len - 1);
    }

    pub fn removeWidget(self: *Self, widget_id: u32) bool {
        if (self.widget_map.get(widget_id)) |index| {
            // Remove from parent's children list if it has a parent
            if (self.widgets.items[index].parent_id) |parent_id| {
                if (self.getWidget(parent_id)) |parent| {
                    _ = parent.removeChild(widget_id);
                }
            }

            // Remove children recursively
            var widget = &self.widgets.items[index];
            for (widget.children.items) |child_id| {
                _ = self.removeWidget(child_id);
            }

            // Clean up widget resources
            widget.deinit();

            // Remove from widgets list and map
            _ = self.widgets.swapRemove(index);
            _ = self.widget_map.remove(widget_id);

            // Update the index in the map for the widget that was swapped
            if (index < self.widgets.items.len) {
                try self.widget_map.put(self.widgets.items[index].id, index);
            }

            return true;
        }
        return false;
    }

    pub fn getWidget(self: *Self, widget_id: u32) ?*Widget {
        if (self.widget_map.get(widget_id)) |index| {
            return &self.widgets.items[index];
        }
        return null;
    }

    pub fn setMousePosition(self: *Self, x: f32, y: f32) void {
        self.mouse_x = x;
        self.mouse_y = y;
    }

    pub fn setMouseButton(self: *Self, pressed: bool) void {
        self.mouse_pressed = pressed;
    }

    pub fn setTheme(self: *Self, theme: Theme) void {
        self.config.theme = theme;
        // Update all widgets to reflect new theme colors
        for (self.widgets.items) |*widget| {
            switch (widget.type) {
                .button => {
                    if (widget.style.background_color != null) {
                        widget.style.background_color = theme.getAccentColor();
                    }
                },
                .text => {
                    if (widget.style.text_color != null) {
                        widget.style.text_color = theme.getTextColor();
                    }
                },
                .container => {
                    if (widget.style.background_color != null) {
                        widget.style.background_color = theme.getBackgroundColor();
                    }
                },
                else => {},
            }
        }
    }
};
