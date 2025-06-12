const std = @import("std");
const Allocator = std.mem.Allocator;
const backend = @import("backend/backend.zig");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Re-export core types from backend
pub const Color = backend.Color;
pub const Rect = backend.Rect;
pub const TextAlign = backend.TextAlign;
pub const FontStyle = backend.FontStyle;
pub const FontInfo = backend.FontInfo;
pub const Image = backend.Image;
pub const DrawCommand = backend.DrawCommand;

// UI Framework configuration
pub const UIConfig = struct {
    /// Whether to use hardware acceleration when available
    hardware_accelerated: bool = true,
    /// Default font size for text
    default_font_size: f32 = 14.0,
    /// Default font family
    default_font_family: []const u8 = "Segoe UI",
    /// Default theme to use
    theme: Theme = .dark,
    /// Default animation duration in milliseconds
    animation_duration_ms: u32 = 150,
    /// Enable debug rendering (shows bounds and other visual helpers)
    debug_rendering: bool = false,
};

// UI Framework theme types
pub const ThemeType = enum {
    dark,
    light,
    custom,
};

// UI Framework theme colors
pub const Theme = struct {
    type: ThemeType,
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

    pub fn dark() Theme {
        return Theme{
            .type = .dark,
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

    pub fn light() Theme {
        return Theme{
            .type = .light,
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

    pub fn custom(
        primary: Color,
        secondary: Color,
        accent: Color,
        background: Color,
    ) Theme {
        var theme = light();
        theme.type = .custom;
        theme.primary = primary;
        theme.secondary = secondary;
        theme.accent = accent;
        theme.background = background;
        return theme;
    }
};

// Event system types
pub const EventType = enum {
    click,
    hover,
    mouse_leave,
    mouse_down,
    mouse_up,
    mouse_move,
    focus,
    blur,
    key_press,
    key_release,
    text_input,
    value_change,
    resize,
    scroll,
};

pub const MouseButton = enum {
    left,
    right,
    middle,
    x1,
    x2,
};

pub const KeyCode = enum(u32) {
    // Standard keys
    a = 'A',
    b = 'B',
    c = 'C',
    // ... other letter keys
    z = 'Z',

    num_0 = '0',
    num_1 = '1',
    // ... other number keys
    num_9 = '9',

    escape = 0x1B,
    enter = 0x0D,
    tab = 0x09,
    space = 0x20,
    backspace = 0x08,

    // Arrow keys
    arrow_up = 0x26,
    arrow_down = 0x28,
    arrow_left = 0x25,
    arrow_right = 0x27,

    // Function keys
    f1 = 0x70,
    f2 = 0x71,
    // ... other function keys
    f12 = 0x7B,

    // Modifiers
    shift = 0x10,
    control = 0x11,
    alt = 0x12,

    // Other common keys
    insert = 0x2D,
    delete = 0x2E,
    home = 0x24,
    end = 0x23,
    page_up = 0x21,
    page_down = 0x22,

    // Add more keys as needed

    _,
};

pub const KeyModifiers = struct {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    system: bool = false,

    pub fn none() KeyModifiers {
        return KeyModifiers{};
    }

    pub fn isModified(self: KeyModifiers) bool {
        return self.shift or self.control or self.alt or self.system;
    }
};

pub const Event = struct {
    event_type: EventType,
    target_id: ?u32 = null,

    // Mouse specific data
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_button: ?MouseButton = null,

    // Keyboard specific data
    key_code: ?KeyCode = null,
    key_modifiers: KeyModifiers = KeyModifiers{},
    text_input: ?[]const u8 = null,

    // Scroll data
    scroll_delta_x: f32 = 0,
    scroll_delta_y: f32 = 0,

    // Resize data
    new_width: u32 = 0,
    new_height: u32 = 0,

    pub fn init(event_type: EventType) Event {
        return Event{ .event_type = event_type };
    }

    pub fn initMouse(event_type: EventType, x: f32, y: f32, button: ?MouseButton) Event {
        return Event{
            .event_type = event_type,
            .mouse_x = x,
            .mouse_y = y,
            .mouse_button = button,
        };
    }

    pub fn initKey(event_type: EventType, key: KeyCode, modifiers: KeyModifiers) Event {
        return Event{
            .event_type = event_type,
            .key_code = key,
            .key_modifiers = modifiers,
        };
    }

    pub fn initText(text: []const u8) Event {
        return Event{
            .event_type = .text_input,
            .text_input = text,
        };
    }

    pub fn initScroll(delta_x: f32, delta_y: f32) Event {
        return Event{
            .event_type = .scroll,
            .scroll_delta_x = delta_x,
            .scroll_delta_y = delta_y,
        };
    }

    pub fn initResize(width: u32, height: u32) Event {
        return Event{
            .event_type = .resize,
            .new_width = width,
            .new_height = height,
        };
    }
};

// UI Element base structure
pub const Element = struct {
    id: u32,
    rect: Rect,
    visible: bool = true,
    enabled: bool = true,
    parent: ?*Element = null,
    children: ArrayList(*Element),

    const Self = @This();

    pub fn init(allocator: Allocator, id: u32, x: f32, y: f32, width: f32, height: f32) Self {
        return Self{
            .id = id,
            .rect = Rect.init(x, y, width, height),
            .children = ArrayList(*Element).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn addChild(self: *Self, child: *Element) !void {
        child.parent = self;
        try self.children.append(child);
    }

    pub fn removeChild(self: *Self, child: *Element) void {
        for (self.children.items, 0..) |item, i| {
            if (item == child) {
                _ = self.children.swapRemove(i);
                child.parent = null;
                break;
            }
        }
    }

    pub fn setBounds(self: *Self, x: f32, y: f32, width: f32, height: f32) void {
        self.rect = Rect.init(x, y, width, height);
    }

    pub fn globalPosition(self: *const Self) struct { x: f32, y: f32 } {
        var x = self.rect.x;
        var y = self.rect.y;

        var current = self.parent;
        while (current) |parent| {
            x += parent.rect.x;
            y += parent.rect.y;
            current = parent.parent;
        }

        return .{ .x = x, .y = y };
    }

    pub fn contains(self: *const Self, x: f32, y: f32) bool {
        const pos = self.globalPosition();
        return x >= pos.x and x < pos.x + self.rect.width and
            y >= pos.y and y < pos.y + self.rect.height;
    }

    pub fn setVisible(self: *Self, visible: bool) void {
        self.visible = visible;
    }

    pub fn setEnabled(self: *Self, enabled: bool) void {
        self.enabled = enabled;
    }
};

// Element factory for creating UI elements
pub const ElementFactory = struct {
    allocator: Allocator,
    next_id: u32 = 1,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn createButton(self: *Self, text: []const u8, x: f32, y: f32, width: f32, height: f32) !*Button {
        const button = try self.allocator.create(Button);
        button.* = Button.init(self.allocator, self.getNextId(), text, x, y, width, height);
        return button;
    }

    pub fn createLabel(self: *Self, text: []const u8, x: f32, y: f32, width: f32, height: f32) !*Label {
        const label = try self.allocator.create(Label);
        label.* = Label.init(self.allocator, self.getNextId(), text, x, y, width, height);
        return label;
    }

    pub fn createPanel(self: *Self, x: f32, y: f32, width: f32, height: f32) !*Panel {
        const panel = try self.allocator.create(Panel);
        panel.* = Panel.init(self.allocator, self.getNextId(), x, y, width, height);
        return panel;
    }

    pub fn createTextInput(self: *Self, placeholder: []const u8, x: f32, y: f32, width: f32, height: f32) !*TextInput {
        const text_input = try self.allocator.create(TextInput);
        text_input.* = TextInput.init(self.allocator, self.getNextId(), placeholder, x, y, width, height);
        return text_input;
    }

    fn getNextId(self: *Self) u32 {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }
};

// Button component
pub const Button = struct {
    element: Element,
    text: []const u8,
    text_allocated: bool = false,
    is_pressed: bool = false,
    is_hovered: bool = false,
    on_click: ?*const fn (button: *Button) void = null,
    text_color: Color = Color.fromRgba(1.0, 1.0, 1.0, 1.0),
    background_color: Color = Color.fromRgba(0.2, 0.4, 0.8, 1.0),
    hover_color: Color = Color.fromRgba(0.3, 0.5, 0.9, 1.0),
    pressed_color: Color = Color.fromRgba(0.1, 0.3, 0.7, 1.0),
    border_radius: f32 = 4.0,

    const Self = @This();

    pub fn init(allocator: Allocator, id: u32, text: []const u8, x: f32, y: f32, width: f32, height: f32) Self {
        var text_copy = allocator.dupe(u8, text) catch unreachable;

        return Self{
            .element = Element.init(allocator, id, x, y, width, height),
            .text = text_copy,
            .text_allocated = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.text_allocated) {
            self.element.children.allocator.free(self.text);
        }
        self.element.deinit();
    }

    pub fn setText(self: *Self, allocator: Allocator, text: []const u8) !void {
        if (self.text_allocated) {
            allocator.free(self.text);
        }

        self.text = try allocator.dupe(u8, text);
        self.text_allocated = true;
    }

    pub fn setOnClick(self: *Self, callback: *const fn (button: *Button) void) void {
        self.on_click = callback;
    }

    pub fn handleEvent(self: *Self, event: Event) bool {
        if (!self.element.enabled) return false;

        switch (event.event_type) {
            .mouse_down => {
                if (self.element.contains(event.mouse_x, event.mouse_y)) {
                    self.is_pressed = true;
                    return true;
                }
            },
            .mouse_up => {
                if (self.is_pressed and self.element.contains(event.mouse_x, event.mouse_y)) {
                    self.is_pressed = false;
                    if (self.on_click) |callback| {
                        callback(self);
                    }
                    return true;
                }
                self.is_pressed = false;
            },
            .mouse_move => {
                self.is_hovered = self.element.contains(event.mouse_x, event.mouse_y);
            },
            .mouse_leave => {
                self.is_hovered = false;
                self.is_pressed = false;
            },
            else => {},
        }

        return false;
    }

    pub fn render(self: *const Self, commands: *ArrayList(DrawCommand), theme: Theme) !void {
        // Skip if not visible
        if (!self.element.visible) return;

        const pos = self.element.globalPosition();

        // Determine button color based on state
        var color = if (!self.element.enabled)
            theme.disabled
        else if (self.is_pressed)
            self.pressed_color
        else if (self.is_hovered)
            self.hover_color
        else
            self.background_color;

        // Draw button background
        try commands.append(DrawCommand{ .rect = .{
            .rect = Rect.init(pos.x, pos.y, self.element.rect.width, self.element.rect.height),
            .color = color,
            .border_radius = self.border_radius,
            .border_width = 0,
        } });

        // Draw button text
        const text_color = if (!self.element.enabled) theme.disabled_text else self.text_color;

        try commands.append(DrawCommand{ .text = .{
            .rect = Rect.init(pos.x, pos.y, self.element.rect.width, self.element.rect.height),
            .text = self.text,
            .color = text_color,
            .font = FontInfo{
                .name = "Segoe UI",
                .style = FontStyle{
                    .size = 14.0,
                    .weight = 400,
                },
            },
            .align_ = .center,
        } });
    }
};

// Label component
pub const Label = struct {
    element: Element,
    text: []const u8,
    text_allocated: bool = false,
    text_color: Color = Color.fromRgba(0.0, 0.0, 0.0, 1.0),
    text_align: TextAlign = .left,
    font_size: f32 = 14.0,
    font_weight: u32 = 400,

    const Self = @This();

    pub fn init(allocator: Allocator, id: u32, text: []const u8, x: f32, y: f32, width: f32, height: f32) Self {
        var text_copy = allocator.dupe(u8, text) catch unreachable;

        return Self{
            .element = Element.init(allocator, id, x, y, width, height),
            .text = text_copy,
            .text_allocated = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.text_allocated) {
            self.element.children.allocator.free(self.text);
        }
        self.element.deinit();
    }

    pub fn setText(self: *Self, allocator: Allocator, text: []const u8) !void {
        if (self.text_allocated) {
            allocator.free(self.text);
        }

        self.text = try allocator.dupe(u8, text);
        self.text_allocated = true;
    }

    pub fn render(self: *const Self, commands: *ArrayList(DrawCommand), theme: Theme) !void {
        if (!self.element.visible) return;

        const pos = self.element.globalPosition();
        const text_color = if (!self.element.enabled) theme.disabled_text else self.text_color;

        try commands.append(DrawCommand{ .text = .{
            .rect = Rect.init(pos.x, pos.y, self.element.rect.width, self.element.rect.height),
            .text = self.text,
            .color = text_color,
            .font = FontInfo{
                .name = "Segoe UI",
                .style = FontStyle{
                    .size = self.font_size,
                    .weight = self.font_weight,
                },
            },
            .align_ = self.text_align,
        } });
    }
};

// Panel component
pub const Panel = struct {
    element: Element,
    background_color: Color = Color.fromRgba(0.95, 0.95, 0.95, 1.0),
    border_color: Color = Color.fromRgba(0.8, 0.8, 0.8, 1.0),
    border_width: f32 = 1.0,
    border_radius: f32 = 0.0,
    padding: struct { top: f32, right: f32, bottom: f32, left: f32 } = .{
        .top = 8,
        .right = 8,
        .bottom = 8,
        .left = 8,
    },

    const Self = @This();

    pub fn init(allocator: Allocator, id: u32, x: f32, y: f32, width: f32, height: f32) Self {
        return Self{
            .element = Element.init(allocator, id, x, y, width, height),
        };
    }

    pub fn deinit(self: *Self) void {
        self.element.deinit();
    }

    pub fn render(self: *const Self, commands: *ArrayList(DrawCommand), theme: Theme) !void {
        if (!self.element.visible) return;

        const pos = self.element.globalPosition();

        // Draw panel background
        try commands.append(DrawCommand{ .rect = .{
            .rect = Rect.init(pos.x, pos.y, self.element.rect.width, self.element.rect.height),
            .color = if (!self.element.enabled) theme.disabled else self.background_color,
            .border_radius = self.border_radius,
            .border_width = self.border_width,
            .border_color = self.border_color,
        } });

        // Render all children
        for (self.element.children.items) |child| {
            // This assumes that child is one of our UI elements with a render method
            // In a real implementation, you'd use a trait system or similar
            switch (@typeInfo(@TypeOf(child.*))) {
                .Struct => |info| {
                    if (@hasDecl(info.name, "render")) {
                        try @field(child, "render")(commands, theme);
                    }
                },
                else => {},
            }
        }
    }

    pub fn layoutChildren(self: *Self) void {
        const content_x = self.element.rect.x + self.padding.left;
        const content_y = self.element.rect.y + self.padding.top;
        const content_width = self.element.rect.width - (self.padding.left + self.padding.right);
        const content_height = self.element.rect.height - (self.padding.top + self.padding.bottom);

        // Simple vertical layout
        if (self.element.children.items.len > 0) {
            const child_height = content_height / @as(f32, @floatFromInt(self.element.children.items.len));

            for (self.element.children.items, 0..) |child, i| {
                const y_offset = @as(f32, @floatFromInt(i)) * child_height;
                child.setBounds(content_x, content_y + y_offset, content_width, child_height);
            }
        }
    }
};

// Text input component
pub const TextInput = struct {
    element: Element,
    text: ArrayList(u8),
    placeholder: []const u8,
    placeholder_allocated: bool = false,
    cursor_pos: usize = 0,
    selection_start: ?usize = null,
    is_focused: bool = false,
    is_hovered: bool = false,
    background_color: Color = Color.fromRgba(1.0, 1.0, 1.0, 1.0),
    text_color: Color = Color.fromRgba(0.0, 0.0, 0.0, 1.0),
    placeholder_color: Color = Color.fromRgba(0.6, 0.6, 0.6, 1.0),
    border_color: Color = Color.fromRgba(0.8, 0.8, 0.8, 1.0),
    border_width: f32 = 1.0,
    border_radius: f32 = 4.0,
    on_change: ?*const fn (input: *TextInput) void = null,
    on_submit: ?*const fn (input: *TextInput) void = null,

    const Self = @This();

    pub fn init(allocator: Allocator, id: u32, placeholder: []const u8, x: f32, y: f32, width: f32, height: f32) Self {
        var placeholder_copy = allocator.dupe(u8, placeholder) catch unreachable;

        return Self{
            .element = Element.init(allocator, id, x, y, width, height),
            .text = ArrayList(u8).init(allocator),
            .placeholder = placeholder_copy,
            .placeholder_allocated = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit();
        if (self.placeholder_allocated) {
            self.element.children.allocator.free(self.placeholder);
        }
        self.element.deinit();
    }

    pub fn setText(self: *Self, text: []const u8) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(text);
        self.cursor_pos = self.text.items.len;
        self.selection_start = null;

        if (self.on_change) |callback| {
            callback(self);
        }
    }

    pub fn getText(self: *const Self) []const u8 {
        return self.text.items;
    }

    pub fn handleEvent(self: *Self, event: Event) bool {
        if (!self.element.enabled) return false;

        switch (event.event_type) {
            .mouse_down => {
                if (self.element.contains(event.mouse_x, event.mouse_y)) {
                    self.is_focused = true;
                    // Would set cursor position based on click position
                    self.cursor_pos = self.text.items.len;
                    self.selection_start = null;
                    return true;
                } else {
                    self.is_focused = false;
                }
            },
            .mouse_move => {
                self.is_hovered = self.element.contains(event.mouse_x, event.mouse_y);
            },
            .mouse_leave => {
                self.is_hovered = false;
            },
            .key_press => {
                if (self.is_focused and event.key_code != null) {
                    return self.handleKeyPress(event.key_code.?, event.key_modifiers);
                }
            },
            .text_input => {
                if (self.is_focused and event.text_input != null) {
                    return self.handleTextInput(event.text_input.?);
                }
            },
            else => {},
        }

        return false;
    }

    fn handleKeyPress(self: *Self, key: KeyCode, modifiers: KeyModifiers) bool {
        switch (key) {
            .backspace => {
                if (self.selection_start) |start| {
                    // Handle selection deletion
                    const min = @min(start, self.cursor_pos);
                    const max = @max(start, self.cursor_pos);
                    if (min < max and min < self.text.items.len) {
                        _ = self.text.replaceRange(min, max - min, &.{}) catch return false;
                        self.cursor_pos = min;
                        self.selection_start = null;
                        if (self.on_change) |callback| {
                            callback(self);
                        }
                    }
                } else if (self.cursor_pos > 0 and self.text.items.len > 0) {
                    self.cursor_pos -= 1;
                    _ = self.text.orderedRemove(self.cursor_pos);
                    if (self.on_change) |callback| {
                        callback(self);
                    }
                }
                return true;
            },
            .delete => {
                if (self.selection_start) |start| {
                    // Handle selection deletion (same as backspace)
                    const min = @min(start, self.cursor_pos);
                    const max = @max(start, self.cursor_pos);
                    if (min < max and min < self.text.items.len) {
                        _ = self.text.replaceRange(min, max - min, &.{}) catch return false;
                        self.cursor_pos = min;
                        self.selection_start = null;
                        if (self.on_change) |callback| {
                            callback(self);
                        }
                    }
                } else if (self.cursor_pos < self.text.items.len) {
                    _ = self.text.orderedRemove(self.cursor_pos);
                    if (self.on_change) |callback| {
                        callback(self);
                    }
                }
                return true;
            },
            .arrow_left => {
                if (modifiers.shift) {
                    // Start or extend selection
                    if (self.selection_start == null) {
                        self.selection_start = self.cursor_pos;
                    }
                } else {
                    // Clear selection
                    self.selection_start = null;
                }

                if (self.cursor_pos > 0) {
                    self.cursor_pos -= 1;
                }
                return true;
            },
            .arrow_right => {
                if (modifiers.shift) {
                    // Start or extend selection
                    if (self.selection_start == null) {
                        self.selection_start = self.cursor_pos;
                    }
                } else {
                    // Clear selection
                    self.selection_start = null;
                }

                if (self.cursor_pos < self.text.items.len) {
                    self.cursor_pos += 1;
                }
                return true;
            },
            .home => {
                if (modifiers.shift) {
                    if (self.selection_start == null) {
                        self.selection_start = self.cursor_pos;
                    }
                } else {
                    self.selection_start = null;
                }
                self.cursor_pos = 0;
                return true;
            },
            .end => {
                if (modifiers.shift) {
                    if (self.selection_start == null) {
                        self.selection_start = self.cursor_pos;
                    }
                } else {
                    self.selection_start = null;
                }
                self.cursor_pos = self.text.items.len;
                return true;
            },
            else => {},
        }
        return false;
    }

    // Additional methods would go here (render, focus handling, etc.)
};
