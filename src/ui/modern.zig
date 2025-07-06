const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Windows API types for modern UI
const HWND = *opaque {};
const HDC = *opaque {};
const HBRUSH = *opaque {};
const HPEN = *opaque {};
const HFONT = *opaque {};
const COLORREF = u32;
const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

// Windows API constants
const DT_CENTER = 0x00000001;
const DT_VCENTER = 0x00000004;
const DT_SINGLELINE = 0x00000020;
const TRANSPARENT = 1;
const PS_SOLID = 0;

// External drawing functions
extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.C) HBRUSH;
extern "gdi32" fn CreatePen(style: i32, width: i32, color: COLORREF) callconv(.C) HPEN;
extern "gdi32" fn CreateFontW(height: i32, width: i32, escapement: i32, orientation: i32, weight: i32, italic: u32, underline: u32, strikeout: u32, charset: u32, out_precision: u32, clip_precision: u32, quality: u32, pitch_and_family: u32, face_name: [*:0]const u16) callconv(.C) HFONT;
extern "gdi32" fn SelectObject(hdc: HDC, obj: *opaque {}) callconv(.C) *opaque {};
extern "gdi32" fn DeleteObject(obj: *opaque {}) callconv(.C) i32;
extern "gdi32" fn Rectangle(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32) callconv(.C) i32;
extern "gdi32" fn RoundRect(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32, width: i32, height: i32) callconv(.C) i32;
extern "gdi32" fn Ellipse(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32) callconv(.C) i32;
extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.C) COLORREF;
extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.C) i32;
extern "gdi32" fn GetTextExtentPoint32W(hdc: HDC, string: [*:0]const u16, count: i32, size: *SIZE) callconv(.C) i32;
extern "user32" fn DrawTextW(hdc: HDC, text: [*:0]const u16, count: i32, rect: *RECT, format: u32) callconv(.C) i32;
extern "user32" fn FillRect(hdc: HDC, rect: *const RECT, brush: HBRUSH) callconv(.C) i32;

// Additional Windows structures
const SIZE = extern struct {
    cx: i32,
    cy: i32,
};

// Modern UI color scheme
pub const Theme = struct {
    primary: COLORREF,
    secondary: COLORREF,
    accent: COLORREF,
    background: COLORREF,
    surface: COLORREF,
    on_primary: COLORREF,
    on_secondary: COLORREF,
    on_surface: COLORREF,
    error_color: COLORREF,
    warning: COLORREF,
    success: COLORREF,
    disabled: COLORREF,
    disabled_text: COLORREF,

    pub fn dark() Theme {
        return Theme{
            .primary = 0x00BB86FC, // Purple
            .secondary = 0x0003DAC6, // Teal
            .accent = 0x00CF6679, // Pink
            .background = 0x00121212, // Dark gray
            .surface = 0x001E1E1E, // Lighter dark gray
            .on_primary = 0x00000000, // Black
            .on_secondary = 0x00000000, // Black
            .on_surface = 0x00FFFFFF, // White
            .error_color = 0x00CF6679, // Red
            .warning = 0x00FFC107, // Orange
            .success = 0x004CAF50, // Green
            .disabled = 0x00505050, // Dark gray
            .disabled_text = 0x00A0A0A0, // Light gray
        };
    }

    pub fn light() Theme {
        return Theme{
            .primary = 0x006200EE, // Purple
            .secondary = 0x0018FFFF, // Cyan
            .accent = 0x00FF4081, // Pink
            .background = 0x00FFFFFF, // White
            .surface = 0x00F5F5F5, // Light gray
            .on_primary = 0x00FFFFFF, // White
            .on_secondary = 0x00000000, // Black
            .on_surface = 0x00000000, // Black
            .error_color = 0x00B00020, // Red
            .warning = 0x00FF6F00, // Orange
            .success = 0x00388E3C, // Green
            .disabled = 0x00E0E0E0, // Light gray
            .disabled_text = 0x00909090, // Dark gray
        };
    }

    pub fn custom(primary: COLORREF, secondary: COLORREF, background: COLORREF) Theme {
        var theme = light();
        theme.primary = primary;
        theme.secondary = secondary;
        theme.background = background;
        return theme;
    }
};

// Event types
pub const EventType = enum {
    click,
    hover,
    mouse_leave,
    mouse_down,
    mouse_up,
    focus,
    blur,
    key_press,
    key_release,
    text_input,
    value_change,
    resize,
};

pub const Event = struct {
    event_type: EventType,
    target: ?*Widget,
    data: ?*anyopaque,
    x: i32 = 0,
    y: i32 = 0,
    key_code: u32 = 0,

    pub fn init(event_type: EventType, target: ?*Widget) Event {
        return Event{
            .event_type = event_type,
            .target = target,
            .data = null,
        };
    }

    pub fn initMouse(event_type: EventType, target: ?*Widget, x: i32, y: i32) Event {
        return Event{
            .event_type = event_type,
            .target = target,
            .data = null,
            .x = x,
            .y = y,
        };
    }

    pub fn initKey(event_type: EventType, target: ?*Widget, key_code: u32) Event {
        return Event{
            .event_type = event_type,
            .target = target,
            .data = null,
            .key_code = key_code,
        };
    }
};

// Base widget interface
pub const Widget = struct {
    id: u32,
    parent: ?*Widget,
    children: ArrayList(*Widget),
    bounds: RECT,
    visible: bool,
    enabled: bool,
    theme: *const Theme,
    allocator: Allocator,

    // Virtual function table
    vtable: *const WidgetVTable,

    const Self = @This();

    pub fn init(allocator: Allocator, theme: *const Theme, vtable: *const WidgetVTable) Self {
        return Self{
            .id = 0, // TODO: implement generateWidgetId()
            .parent = null,
            .children = ArrayList(*Widget).init(allocator),
            .bounds = RECT{ .left = 0, .top = 0, .right = 100, .bottom = 30 },
            .visible = true,
            .enabled = true,
            .theme = theme,
            .allocator = allocator,
            .vtable = vtable,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn addChild(self: *Self, child: *Widget) !void {
        child.parent = self;
        try self.children.append(child);
    }

    pub fn removeChild(self: *Self, child: *Widget) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.swapRemove(i);
                child.parent = null;
                break;
            }
        }
    }

    pub fn setBounds(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        self.bounds = RECT{
            .left = x,
            .top = y,
            .right = x + width,
            .bottom = y + height,
        };
        self.vtable.on_resize(self);
    }

    pub fn getWidth(self: *const Self) i32 {
        return self.bounds.right - self.bounds.left;
    }

    pub fn getHeight(self: *const Self) i32 {
        return self.bounds.bottom - self.bounds.top;
    }

    pub fn setVisible(self: *Self, visible: bool) void {
        self.visible = visible;
    }

    pub fn setEnabled(self: *Self, enabled: bool) void {
        self.enabled = enabled;
    }

    pub fn render(self: *Self, hdc: HDC) void {
        if (!self.visible) return;

        self.vtable.render(self, hdc);

        for (self.children.items) |child| {
            child.render(hdc);
        }
    }

    pub fn handleEvent(self: *Self, event: *const Event) bool {
        if (!self.enabled) return false;

        // Try children first (reverse order for proper Z-order)
        var i = self.children.items.len;
        while (i > 0) {
            i -= 1;
            if (self.children.items[i].handleEvent(event)) {
                return true;
            }
        }

        return self.vtable.handle_event(self, event);
    }

    pub fn containsPoint(self: *const Self, x: i32, y: i32) bool {
        return x >= self.bounds.left and x < self.bounds.right and
            y >= self.bounds.top and y < self.bounds.bottom;
    }
};

pub const WidgetVTable = struct {
    render: *const fn (widget: *Widget, hdc: HDC) void,
    handle_event: *const fn (widget: *Widget, event: *const Event) bool,
    on_resize: *const fn (widget: *Widget) void,
};

// Button widget
pub const Button = struct {
    widget: Widget,
    text: []const u8,
    text_wide: []u16,
    on_click: ?*const fn (button: *Button) void,
    is_pressed: bool,
    is_hovered: bool,

    const Self = @This();

    const button_vtable = WidgetVTable{
        .render = buttonRender,
        .handle_event = buttonHandleEvent,
        .on_resize = buttonOnResize,
    };

    pub fn init(allocator: Allocator, theme: *const Theme, text: []const u8) !*Self {
        const button = try allocator.create(Self);
        button.* = Self{
            .widget = Widget.init(allocator, theme, &button_vtable),
            .text = try allocator.dupe(u8, text),
            .text_wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, text),
            .on_click = null,
            .is_pressed = false,
            .is_hovered = false,
        };
        return button;
    }

    pub fn deinit(self: *Self) void {
        self.widget.allocator.free(self.text);
        self.widget.allocator.free(self.text_wide);
        self.widget.deinit();
    }

    pub fn setOnClick(self: *Self, callback: *const fn (button: *Button) void) void {
        self.on_click = callback;
    }

    fn buttonRender(widget: *Widget, hdc: HDC) void {
        const button: *Button = @fieldParentPtr("widget", widget);
        const theme = widget.theme;

        // Choose colors based on state
        var bg_color = theme.primary;
        var text_color = theme.on_primary;

        if (!widget.enabled) {
            bg_color = 0x00808080; // Gray
            text_color = 0x00C0C0C0; // Light gray
        } else if (button.is_pressed) {
            bg_color = theme.accent;
        } else if (button.is_hovered) {
            bg_color = theme.secondary;
        }

        // Draw background
        const brush = CreateSolidBrush(bg_color);
        const old_brush = SelectObject(hdc, brush);
        _ = RoundRect(hdc, widget.bounds.left, widget.bounds.top, widget.bounds.right, widget.bounds.bottom, 8, 8);
        _ = SelectObject(hdc, old_brush);
        _ = DeleteObject(brush);

        // Draw text
        _ = SetTextColor(hdc, text_color);
        _ = SetBkMode(hdc, 1); // TRANSPARENT

        var text_rect = widget.bounds;
        text_rect.left += 8;
        text_rect.right -= 8;

        _ = DrawTextW(hdc, button.text_wide.ptr, -1, &text_rect, 0x00000001 | 0x00000004 | 0x00000020); // DT_CENTER | DT_VCENTER | DT_SINGLELINE
    }

    fn buttonHandleEvent(widget: *Widget, event: *const Event) bool {
        const button: *Button = @fieldParentPtr("widget", widget);

        switch (event.event_type) {
            .click => {
                if (button.on_click) |callback| {
                    callback(button);
                }
                return true;
            },
            .hover => {
                button.is_hovered = true;
                return true;
            },
            else => return false,
        }
    }

    fn buttonOnResize(widget: *Widget) void {
        _ = widget;
        // Button-specific resize logic
    }
};

// Text input widget
pub const TextInput = struct {
    widget: Widget,
    text: ArrayList(u8),
    text_wide: ArrayList(u16),
    placeholder: []const u8,
    placeholder_wide: []u16,
    cursor_pos: usize,
    is_focused: bool,
    on_change: ?*const fn (input: *TextInput) void,

    const Self = @This();

    const input_vtable = WidgetVTable{
        .render = inputRender,
        .handle_event = inputHandleEvent,
        .on_resize = inputOnResize,
    };

    pub fn init(allocator: Allocator, theme: *const Theme, placeholder: []const u8) !*Self {
        const input = try allocator.create(Self);
        input.* = Self{
            .widget = Widget.init(allocator, theme, &input_vtable),
            .text = ArrayList(u8).init(allocator),
            .text_wide = ArrayList(u16).init(allocator),
            .placeholder = try allocator.dupe(u8, placeholder),
            .placeholder_wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, placeholder),
            .cursor_pos = 0,
            .is_focused = false,
            .on_change = null,
        };
        return input;
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit();
        self.text_wide.deinit();
        self.widget.allocator.free(self.placeholder);
        self.widget.allocator.free(self.placeholder_wide);
        self.widget.deinit();
    }

    pub fn setText(self: *Self, text: []const u8) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(text);

        self.text_wide.clearRetainingCapacity();
        const wide_text = try std.unicode.utf8ToUtf16LeAllocZ(self.widget.allocator, text);
        defer self.widget.allocator.free(wide_text);
        try self.text_wide.appendSlice(wide_text[0 .. wide_text.len - 1]); // Remove null terminator

        self.cursor_pos = @min(self.cursor_pos, self.text.items.len);

        if (self.on_change) |callback| {
            callback(self);
        }
    }

    pub fn getText(self: *const Self) []const u8 {
        return self.text.items;
    }
    fn inputRender(widget: *Widget, hdc: HDC) void {
        const input: *TextInput = @fieldParentPtr("widget", widget);
        const theme = widget.theme;

        // Draw background
        const bg_color = if (input.is_focused) theme.surface else theme.background;
        const border_color = if (input.is_focused) theme.primary else 0x00808080;

        const bg_brush = CreateSolidBrush(bg_color);
        const border_pen = CreatePen(0, 2, border_color);

        const old_brush = SelectObject(hdc, bg_brush);
        const old_pen = SelectObject(hdc, border_pen);

        _ = RoundRect(hdc, widget.bounds.left, widget.bounds.top, widget.bounds.right, widget.bounds.bottom, 4, 4);

        _ = SelectObject(hdc, old_brush);
        _ = SelectObject(hdc, old_pen);
        _ = DeleteObject(bg_brush);
        _ = DeleteObject(border_pen);

        // Draw text or placeholder
        var text_rect = widget.bounds;
        text_rect.left += 8;
        text_rect.right -= 8;

        _ = SetBkMode(hdc, 1); // TRANSPARENT

        if (input.text.items.len > 0) {
            // Draw actual text
            _ = SetTextColor(hdc, theme.on_surface);
            const null_terminated = input.widget.allocator.dupeZ(u16, input.text_wide.items) catch return;
            defer input.widget.allocator.free(null_terminated);
            _ = DrawTextW(hdc, null_terminated.ptr, -1, &text_rect, 0x00000020); // DT_SINGLELINE
        } else if (!input.is_focused) {
            // Draw placeholder
            _ = SetTextColor(hdc, 0x00808080); // Gray
            _ = DrawTextW(hdc, input.placeholder_wide.ptr, -1, &text_rect, 0x00000020); // DT_SINGLELINE
        }

        // Draw cursor if focused
        if (input.is_focused) {
            // Simple cursor implementation - would need proper text measurement in real code
            const cursor_x = text_rect.left + @as(i32, @intCast(input.cursor_pos * 8));
            const cursor_pen = CreatePen(0, 1, theme.on_surface);
            const old_cursor_pen = SelectObject(hdc, cursor_pen);

            // Draw cursor line (simplified)
            _ = Rectangle(hdc, cursor_x, text_rect.top + 2, cursor_x + 1, text_rect.bottom - 2);

            _ = SelectObject(hdc, old_cursor_pen);
            _ = DeleteObject(cursor_pen);
        }
    }
    fn inputHandleEvent(widget: *Widget, event: *const Event) bool {
        const input: *TextInput = @fieldParentPtr("widget", widget);

        switch (event.event_type) {
            .click => {
                input.is_focused = true;
                return true;
            },
            .blur => {
                input.is_focused = false;
                return true;
            },
            .text_input => {
                if (input.is_focused and event.data != null) {
                    const char_data: *u8 = @ptrCast(@alignCast(event.data.?));
                    input.text.append(char_data.*) catch return false;

                    // Update wide text
                    const new_text = input.widget.allocator.dupeZ(u8, input.text.items) catch return false;
                    defer input.widget.allocator.free(new_text);

                    const wide_text = std.unicode.utf8ToUtf16LeAllocZ(input.widget.allocator, new_text) catch return false;
                    defer input.widget.allocator.free(wide_text);

                    input.text_wide.clearRetainingCapacity();
                    input.text_wide.appendSlice(wide_text[0 .. wide_text.len - 1]) catch return false;

                    input.cursor_pos = input.text.items.len;

                    if (input.on_change) |callback| {
                        callback(input);
                    }
                    return true;
                }
                return false;
            },
            else => return false,
        }
    }
    fn inputOnResize(widget: *Widget) void {
        _ = widget;
        // Input-specific resize logic
    }
};

// Panel container widget
pub const Panel = struct {
    widget: Widget,
    background_color: COLORREF,
    border_color: COLORREF,
    border_width: i32,
    padding: struct { left: i32, top: i32, right: i32, bottom: i32 },
    const Self = @This();
    const panel_vtable = WidgetVTable{
        .render = panelRender,
        .handle_event = panelHandleEvent,
        .on_resize = panelOnResize,
    };

    pub fn init(allocator: Allocator, theme: *const Theme) !*Self {
        const panel = try allocator.create(Self);
        panel.* = Self{
            .widget = Widget.init(allocator, theme, &panel_vtable),
            .background_color = theme.surface,
            .border_color = theme.primary,
            .border_width = 1,
            .padding = .{ .left = 8, .top = 8, .right = 8, .bottom = 8 },
        };
        return panel;
    }

    pub fn deinit(self: *Self) void {
        self.widget.deinit();
    }
    fn panelRender(widget: *Widget, hdc: HDC) void {
        const panel: *Panel = @fieldParentPtr("widget", widget);

        // Draw background
        const bg_brush = CreateSolidBrush(panel.background_color);
        const old_brush = SelectObject(hdc, bg_brush);

        if (panel.border_width > 0) {
            const border_pen = CreatePen(0, panel.border_width, panel.border_color);
            const old_pen = SelectObject(hdc, border_pen);
            _ = Rectangle(hdc, widget.bounds.left, widget.bounds.top, widget.bounds.right, widget.bounds.bottom);
            _ = SelectObject(hdc, old_pen);
            _ = DeleteObject(border_pen);
        } else {
            var fill_rect = widget.bounds;
            _ = FillRect(hdc, &fill_rect, bg_brush);
        }

        _ = SelectObject(hdc, old_brush);
        _ = DeleteObject(bg_brush);
    }
    fn panelHandleEvent(widget: *Widget, event: *const Event) bool {
        _ = widget;
        _ = event;
        return false; // Panels don't handle events by default
    }

    fn panelOnResize(widget: *Widget) void {
        const panel: *Panel = @fieldParentPtr("widget", widget);

        // Automatically layout children with padding
        const content_left = widget.bounds.left + panel.padding.left;
        const content_top = widget.bounds.top + panel.padding.top;
        const content_width = (widget.bounds.right - widget.bounds.left) - panel.padding.left - panel.padding.right;
        const content_height = (widget.bounds.bottom - widget.bounds.top) - panel.padding.top - panel.padding.bottom;

        if (widget.children.items.len > 0) {
            const child_height = @divTrunc(content_height, @as(i32, @intCast(widget.children.items.len)));

            for (widget.children.items, 0..) |child, i| {
                const y_offset = @as(i32, @intCast(i)) * child_height;
                child.setBounds(content_left, content_top + y_offset, content_width, child_height);
            }
        }
    }
};

// Layout managers
pub const LayoutType = enum {
    vertical,
    horizontal,
    grid,
    absolute,
};

pub const Layout = struct {
    layout_type: LayoutType,
    spacing: i32,
    const Self = @This();
    pub fn init(layout_type: LayoutType, spacing: i32) Self {
        return Self{
            .layout_type = layout_type,
            .spacing = spacing,
        };
    }

    pub fn apply(self: *const Self, container: *Widget) void {
        if (container.children.items.len == 0) return;

        switch (self.layout_type) {
            .vertical => self.applyVerticalLayout(container),
            .horizontal => self.applyHorizontalLayout(container),
            .grid => self.applyGridLayout(container),
            .absolute => {}, // No automatic layout
        }
    }

    fn applyVerticalLayout(self: *const Self, container: *Widget) void {
        const content_width = container.bounds.right - container.bounds.left;
        const total_spacing = self.spacing * @as(i32, @intCast(container.children.items.len - 1));
        const content_height = container.bounds.bottom - container.bounds.top - total_spacing;
        const child_height = @divTrunc(content_height, @as(i32, @intCast(container.children.items.len)));

        var y_offset = container.bounds.top;
        for (container.children.items) |child| {
            child.setBounds(container.bounds.left, y_offset, content_width, child_height);
            y_offset += child_height + self.spacing;
        }
    }
    fn applyHorizontalLayout(self: *const Self, container: *Widget) void {
        const content_height = container.bounds.bottom - container.bounds.top;
        const total_spacing = self.spacing * @as(i32, @intCast(container.children.items.len - 1));
        const content_width = container.bounds.right - container.bounds.left - total_spacing;
        const child_width = @divTrunc(content_width, @as(i32, @intCast(container.children.items.len)));

        var x_offset = container.bounds.left;
        for (container.children.items) |child| {
            child.setBounds(x_offset, container.bounds.top, child_width, content_height);
            x_offset += child_width + self.spacing;
        }
    }

    fn applyGridLayout(self: *const Self, container: *Widget) void {
        // Simple grid layout - square grid
        const child_count = container.children.items.len;
        if (child_count == 0) return;

        const grid_size = @as(i32, @intFromFloat(@ceil(@sqrt(@as(f64, @floatFromInt(child_count))))));
        const container_width = container.bounds.right - container.bounds.left;
        const container_height = container.bounds.bottom - container.bounds.top;

        const cell_width = @divTrunc(container_width - (grid_size - 1) * self.spacing, grid_size);
        const cell_height = @divTrunc(container_height - (grid_size - 1) * self.spacing, grid_size);

        for (container.children.items, 0..) |child, i| {
            const row = @as(i32, @intCast(i / @as(usize, @intCast(grid_size))));
            const col = @as(i32, @intCast(i % @as(usize, @intCast(grid_size))));

            const x = container.bounds.left + col * (cell_width + self.spacing);
            const y = container.bounds.top + row * (cell_height + self.spacing);

            child.setBounds(x, y, cell_width, cell_height);
        }
    }
};

// Modern UI Manager
pub const ModernUI = struct {
    allocator: Allocator,
    theme: Theme,
    root_widget: ?*Widget,
    focused_widget: ?*Widget,
    const Self = @This();

    pub fn init(allocator: Allocator, dark_theme: bool) Self {
        return Self{
            .allocator = allocator,
            .theme = if (dark_theme) Theme.dark() else Theme.light(),
            .root_widget = null,
            .focused_widget = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.root_widget) |root| {
            root.deinit();
            self.allocator.destroy(root);
        }
    }

    pub fn setRootWidget(self: *Self, widget: *Widget) void {
        if (self.root_widget) |old_root| {
            old_root.deinit();
            self.allocator.destroy(old_root);
        }
        self.root_widget = widget;
    }
    pub fn render(self: *Self, hdc: HDC) void {
        if (self.root_widget) |root| {
            root.render(hdc);
        }
    }
    pub fn handleEvent(self: *Self, event: *const Event) bool {
        if (self.root_widget) |root| {
            return root.handleEvent(event);
        }
        return false;
    }

    pub fn setFocus(self: *Self, widget: ?*Widget) void {
        if (self.focused_widget) |old_focused| {
            const blur_event = Event.init(.blur, old_focused);
            _ = old_focused.handleEvent(&blur_event);
        }

        self.focused_widget = widget;

        if (widget) |new_focused| {
            const focus_event = Event.init(.focus, new_focused);
            _ = new_focused.handleEvent(&focus_event);
        }
    }
};
