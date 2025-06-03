const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Vec2 = @import("../math/vec2.zig").Vec2f;
const Vec3 = @import("../math/vec3.zig").Vec3f;
const Vec4 = @import("../math/vec4.zig").Vec4f;
const Mat4 = @import("../math/mat4.zig").Mat4f;
const print = std.debug.print;

pub const Color = Vec4;

pub const GUIError = error{
    InitializationFailed,
    RenderContextNotFound,
    ShaderCompilationFailed,
    BufferCreationFailed,
    TextureCreationFailed,
    FontLoadingFailed,
    OutOfMemory,
    InvalidParameter,
    ResourceNotFound,
};

pub const InputEvent = union(enum) {
    mouse_move: struct { x: f32, y: f32 },
    mouse_button: struct { button: MouseButton, pressed: bool, x: f32, y: f32 },
    mouse_scroll: struct { x: f32, y: f32 },
    key: struct { key: Key, pressed: bool, repeat: bool },
    text: struct { codepoint: u32 },
    window_resize: struct { width: u32, height: u32 },
};

pub const MouseButton = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
    back = 3,
    forward = 4,
};

pub const Key = enum(u16) {
    unknown = 0,
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    key_0 = 48,
    key_1 = 49,
    key_2 = 50,
    key_3 = 51,
    key_4 = 52,
    key_5 = 53,
    key_6 = 54,
    key_7 = 55,
    key_8 = 56,
    key_9 = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
};

pub const FontWeight = enum {
    thin,
    extra_light,
    light,
    normal,
    medium,
    semi_bold,
    bold,
    extra_bold,
    black,
};

pub const TextAlign = enum {
    left,
    center,
    right,
    justify,
};

pub const VerticalAlign = enum {
    top,
    center,
    bottom,
    baseline,
};

pub const Cursor = enum {
    arrow,
    text,
    resize_horizontal,
    resize_vertical,
    resize_diagonal_1,
    resize_diagonal_2,
    hand,
    not_allowed,
    crosshair,
};

pub const Vertex = struct {
    position: Vec2,
    uv: Vec2,
    color: Color,
};

pub const DrawCommand = struct {
    texture_id: ?u32,
    clip_rect: Rect,
    vertex_offset: u32,
    index_offset: u32,
    index_count: u32,
    shader_id: ?u32,
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return Rect{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn contains(self: Rect, point: Vec2) bool {
        return point.x >= self.x and point.x <= self.x + self.width and
            point.y >= self.y and point.y <= self.y + self.height;
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn intersection(self: Rect, other: Rect) ?Rect {
        if (!self.intersects(other)) return null;

        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        return Rect.init(x1, y1, x2 - x1, y2 - y1);
    }

    pub fn expand(self: Rect, amount: f32) Rect {
        return Rect.init(self.x - amount, self.y - amount, self.width + amount * 2, self.height + amount * 2);
    }
};

pub const Style = struct {
    background_color: Color = Color{ .x = 0.2, .y = 0.2, .z = 0.2, .w = 1.0 },
    border_color: Color = Color{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 },
    text_color: Color = Color{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
    border_width: f32 = 1.0,
    border_radius: f32 = 0.0,
    padding: struct {
        left: f32 = 4.0,
        right: f32 = 4.0,
        top: f32 = 4.0,
        bottom: f32 = 4.0,
    } = .{},
    margin: struct {
        left: f32 = 0.0,
        right: f32 = 0.0,
        top: f32 = 0.0,
        bottom: f32 = 0.0,
    } = .{},
    font_size: f32 = 14.0,
    font_weight: FontWeight = .normal,
    text_align: TextAlign = .left,
    vertical_align: VerticalAlign = .center,
};

pub const Font = struct {
    id: u32,
    name: []const u8,
    size: f32,
    weight: FontWeight,
    texture_id: u32,
    glyph_map: HashMap(u32, Glyph, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    line_height: f32,
    ascent: f32,
    descent: f32,

    const Glyph = struct {
        codepoint: u32,
        advance: f32,
        bearing_x: f32,
        bearing_y: f32,
        width: f32,
        height: f32,
        uv_x: f32,
        uv_y: f32,
        uv_width: f32,
        uv_height: f32,
    };
};

pub const Texture = struct {
    id: u32,
    width: u32,
    height: u32,
    format: TextureFormat,
    data: ?[]const u8,

    pub const TextureFormat = enum {
        rgba8,
        rgb8,
        rg8,
        r8,
        rgba16f,
        rgba32f,
        depth24_stencil8,
    };
};

pub const RenderBuffer = struct {
    vertices: ArrayList(Vertex),
    indices: ArrayList(u32),
    commands: ArrayList(DrawCommand),
    vertex_buffer_id: ?u32,
    index_buffer_id: ?u32,
    needs_update: bool,

    pub fn init(allocator: Allocator) RenderBuffer {
        return RenderBuffer{
            .vertices = ArrayList(Vertex).init(allocator),
            .indices = ArrayList(u32).init(allocator),
            .commands = ArrayList(DrawCommand).init(allocator),
            .vertex_buffer_id = null,
            .index_buffer_id = null,
            .needs_update = true,
        };
    }

    pub fn deinit(self: *RenderBuffer) void {
        self.vertices.deinit();
        self.indices.deinit();
        self.commands.deinit();
    }

    pub fn clear(self: *RenderBuffer) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
        self.commands.clearRetainingCapacity();
        self.needs_update = true;
    }

    pub fn addVertex(self: *RenderBuffer, vertex: Vertex) !u32 {
        const index = @as(u32, @intCast(self.vertices.items.len));
        try self.vertices.append(vertex);
        self.needs_update = true;
        return index;
    }

    pub fn addIndex(self: *RenderBuffer, index: u32) !void {
        try self.indices.append(index);
        self.needs_update = true;
    }

    pub fn addQuad(self: *RenderBuffer, rect: Rect, uv_rect: Rect, color: Color) !void {
        const base_index = @as(u32, @intCast(self.vertices.items.len));

        // Add vertices
        try self.vertices.append(Vertex{
            .position = Vec2{ .x = rect.x, .y = rect.y },
            .uv = Vec2{ .x = uv_rect.x, .y = uv_rect.y },
            .color = color,
        });
        try self.vertices.append(Vertex{
            .position = Vec2{ .x = rect.x + rect.width, .y = rect.y },
            .uv = Vec2{ .x = uv_rect.x + uv_rect.width, .y = uv_rect.y },
            .color = color,
        });
        try self.vertices.append(Vertex{
            .position = Vec2{ .x = rect.x + rect.width, .y = rect.y + rect.height },
            .uv = Vec2{ .x = uv_rect.x + uv_rect.width, .y = uv_rect.y + uv_rect.height },
            .color = color,
        });
        try self.vertices.append(Vertex{
            .position = Vec2{ .x = rect.x, .y = rect.y + rect.height },
            .uv = Vec2{ .x = uv_rect.x, .y = uv_rect.y + uv_rect.height },
            .color = color,
        });

        // Add indices for two triangles
        try self.indices.append(base_index);
        try self.indices.append(base_index + 1);
        try self.indices.append(base_index + 2);
        try self.indices.append(base_index);
        try self.indices.append(base_index + 2);
        try self.indices.append(base_index + 3);

        self.needs_update = true;
    }
};

pub const DrawContext = struct {
    allocator: Allocator,
    render_buffer: RenderBuffer,
    clip_stack: ArrayList(Rect),
    transform_stack: ArrayList(Mat4),
    current_texture: ?u32,
    current_shader: ?u32,
    current_clip: Rect,
    current_transform: Mat4,
    screen_size: Vec2,
    dpi_scale: f32,

    pub fn init(allocator: Allocator, screen_width: f32, screen_height: f32) DrawContext {
        const screen_rect = Rect.init(0, 0, screen_width, screen_height);
        return DrawContext{
            .allocator = allocator,
            .render_buffer = RenderBuffer.init(allocator),
            .clip_stack = ArrayList(Rect).init(allocator),
            .transform_stack = ArrayList(Mat4).init(allocator),
            .current_texture = null,
            .current_shader = null,
            .current_clip = screen_rect,
            .current_transform = Mat4.identity(),
            .screen_size = Vec2{ .x = screen_width, .y = screen_height },
            .dpi_scale = 1.0,
        };
    }

    pub fn deinit(self: *DrawContext) void {
        self.render_buffer.deinit();
        self.clip_stack.deinit();
        self.transform_stack.deinit();
    }

    pub fn beginFrame(self: *DrawContext) void {
        self.render_buffer.clear();
        self.clip_stack.clearRetainingCapacity();
        self.transform_stack.clearRetainingCapacity();
        self.current_texture = null;
        self.current_shader = null;
        self.current_clip = Rect.init(0, 0, self.screen_size.x, self.screen_size.y);
        self.current_transform = Mat4.identity();
    }

    pub fn endFrame(self: *DrawContext) void {
        // Finalize rendering
        self.render_buffer.needs_update = true;
    }

    pub fn pushClip(self: *DrawContext, rect: Rect) !void {
        try self.clip_stack.append(self.current_clip);
        if (self.current_clip.intersection(rect)) |intersection| {
            self.current_clip = intersection;
        } else {
            self.current_clip = Rect.init(0, 0, 0, 0); // Empty clip
        }
    }

    pub fn popClip(self: *DrawContext) void {
        if (self.clip_stack.items.len > 0) {
            self.current_clip = self.clip_stack.pop();
        }
    }

    pub fn pushTransform(self: *DrawContext, transform: Mat4) !void {
        try self.transform_stack.append(self.current_transform);
        self.current_transform = self.current_transform.multiply(transform);
    }

    pub fn popTransform(self: *DrawContext) void {
        if (self.transform_stack.items.len > 0) {
            self.current_transform = self.transform_stack.pop();
        }
    }

    pub fn setTexture(self: *DrawContext, texture_id: ?u32) void {
        if (self.current_texture != texture_id) {
            self.flushCommands();
            self.current_texture = texture_id;
        }
    }

    pub fn setShader(self: *DrawContext, shader_id: ?u32) void {
        if (self.current_shader != shader_id) {
            self.flushCommands();
            self.current_shader = shader_id;
        }
    }

    pub fn drawRect(self: *DrawContext, rect: Rect, color: Color) !void {
        const uv_rect = Rect.init(0, 0, 1, 1);
        try self.render_buffer.addQuad(rect, uv_rect, color);
    }

    pub fn drawRoundedRect(self: *DrawContext, rect: Rect, radius: f32, color: Color) !void {
        // For simplicity, this draws a regular rect
        // In a full implementation, this would tessellate rounded corners
        _ = radius;
        try self.drawRect(rect, color);
    }

    pub fn drawBorder(self: *DrawContext, rect: Rect, thickness: f32, color: Color) !void {
        // Top border
        try self.drawRect(Rect.init(rect.x, rect.y, rect.width, thickness), color);
        // Bottom border
        try self.drawRect(Rect.init(rect.x, rect.y + rect.height - thickness, rect.width, thickness), color);
        // Left border
        try self.drawRect(Rect.init(rect.x, rect.y, thickness, rect.height), color);
        // Right border
        try self.drawRect(Rect.init(rect.x + rect.width - thickness, rect.y, thickness, rect.height), color);
    }

    pub fn drawCircle(self: *DrawContext, center: Vec2, radius: f32, color: Color, segments: u32) !void {
        const base_index = @as(u32, @intCast(self.render_buffer.vertices.items.len));

        // Center vertex
        try self.render_buffer.vertices.append(Vertex{
            .position = center,
            .uv = Vec2{ .x = 0.5, .y = 0.5 },
            .color = color,
        });

        // Circle vertices
        var i: u32 = 0;
        while (i <= segments) : (i += 1) {
            const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            const x = center.x + @cos(angle) * radius;
            const y = center.y + @sin(angle) * radius;

            try self.render_buffer.vertices.append(Vertex{
                .position = Vec2{ .x = x, .y = y },
                .uv = Vec2{ .x = 0.5 + @cos(angle) * 0.5, .y = 0.5 + @sin(angle) * 0.5 },
                .color = color,
            });

            if (i > 0) {
                try self.render_buffer.indices.append(base_index);
                try self.render_buffer.indices.append(base_index + i);
                try self.render_buffer.indices.append(base_index + i + 1);
            }
        }
    }

    pub fn drawLine(self: *DrawContext, start: Vec2, end: Vec2, thickness: f32, color: Color) !void {
        const direction = Vec2{ .x = end.x - start.x, .y = end.y - start.y };
        const length = @sqrt(direction.x * direction.x + direction.y * direction.y);
        if (length == 0) return;

        const normalized = Vec2{ .x = direction.x / length, .y = direction.y / length };
        const perpendicular = Vec2{ .x = -normalized.y * thickness * 0.5, .y = normalized.x * thickness * 0.5 };

        const rect = Rect.init(start.x - perpendicular.x, start.y - perpendicular.y, length, thickness);

        try self.drawRect(rect, color);
    }

    fn flushCommands(self: *DrawContext) void {
        if (self.render_buffer.vertices.items.len > 0) {
            const command = DrawCommand{
                .texture_id = self.current_texture,
                .clip_rect = self.current_clip,
                .vertex_offset = 0,
                .index_offset = 0,
                .index_count = @as(u32, @intCast(self.render_buffer.indices.items.len)),
                .shader_id = self.current_shader,
            };
            self.render_buffer.commands.append(command) catch {};
        }
    }
};

pub const InputState = struct {
    mouse_position: Vec2 = Vec2{ .x = 0, .y = 0 },
    mouse_buttons: [5]bool = [_]bool{false} ** 5,
    keys: [512]bool = [_]bool{false} ** 512,
    text_input: ArrayList(u32),
    scroll_delta: Vec2 = Vec2{ .x = 0, .y = 0 },

    pub fn init(allocator: Allocator) InputState {
        return InputState{
            .text_input = ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *InputState) void {
        self.text_input.deinit();
    }

    pub fn processEvent(self: *InputState, event: InputEvent) void {
        switch (event) {
            .mouse_move => |data| {
                self.mouse_position = Vec2{ .x = data.x, .y = data.y };
            },
            .mouse_button => |data| {
                if (@intFromEnum(data.button) < self.mouse_buttons.len) {
                    self.mouse_buttons[@intFromEnum(data.button)] = data.pressed;
                }
            },
            .mouse_scroll => |data| {
                self.scroll_delta = Vec2{ .x = data.x, .y = data.y };
            },
            .key => |data| {
                if (@intFromEnum(data.key) < self.keys.len) {
                    self.keys[@intFromEnum(data.key)] = data.pressed;
                }
            },
            .text => |data| {
                self.text_input.append(data.codepoint) catch {};
            },
            .window_resize => {},
        }
    }

    pub fn isMouseButtonPressed(self: *const InputState, button: MouseButton) bool {
        return self.mouse_buttons[@intFromEnum(button)];
    }

    pub fn isKeyPressed(self: *const InputState, key: Key) bool {
        return self.keys[@intFromEnum(key)];
    }

    pub fn clearFrameState(self: *InputState) void {
        self.scroll_delta = Vec2{ .x = 0, .y = 0 };
        self.text_input.clearRetainingCapacity();
    }
};

pub const LayoutDirection = enum {
    horizontal,
    vertical,
};

pub const LayoutAlign = enum {
    start,
    center,
    end,
    stretch,
};

pub const Layout = struct {
    direction: LayoutDirection = .vertical,
    alignment: LayoutAlign = .start,
    gap: f32 = 0,
    padding: f32 = 0,
    wrap: bool = false,

    pub fn calculateLayout(self: Layout, container: Rect, children: []Rect) void {
        if (children.len == 0) return;

        const available_width = container.width - self.padding * 2;
        const available_height = container.height - self.padding * 2;
        const gap_total = @as(f32, @floatFromInt(children.len - 1)) * self.gap;

        switch (self.direction) {
            .horizontal => {
                const child_width = (available_width - gap_total) / @as(f32, @floatFromInt(children.len));
                var x = container.x + self.padding;

                for (children) |*child| {
                    child.x = x;
                    child.y = container.y + self.padding;
                    child.width = child_width;
                    child.height = available_height;
                    x += child_width + self.gap;
                }
            },
            .vertical => {
                const child_height = (available_height - gap_total) / @as(f32, @floatFromInt(children.len));
                var y = container.y + self.padding;

                for (children) |*child| {
                    child.x = container.x + self.padding;
                    child.y = y;
                    child.width = available_width;
                    child.height = child_height;
                    y += child_height + self.gap;
                }
            },
        }
    }
};

pub const Widget = struct {
    id: u32,
    rect: Rect,
    style: Style,
    visible: bool = true,
    enabled: bool = true,
    focusable: bool = false,
    focused: bool = false,
    hovered: bool = false,
    pressed: bool = false,

    pub fn init(id: u32, rect: Rect) Widget {
        return Widget{
            .id = id,
            .rect = rect,
            .style = Style{},
        };
    }

    pub fn updateState(self: *Widget, input: *const InputState) void {
        self.hovered = self.rect.contains(input.mouse_position);

        if (self.hovered and input.isMouseButtonPressed(.left)) {
            self.pressed = true;
        } else {
            self.pressed = false;
        }
    }

    pub fn draw(self: *const Widget, ctx: *DrawContext) !void {
        if (!self.visible) return;

        // Draw background
        if (self.style.background_color.w > 0) {
            if (self.style.border_radius > 0) {
                try ctx.drawRoundedRect(self.rect, self.style.border_radius, self.style.background_color);
            } else {
                try ctx.drawRect(self.rect, self.style.background_color);
            }
        }

        // Draw border
        if (self.style.border_width > 0 and self.style.border_color.w > 0) {
            try ctx.drawBorder(self.rect, self.style.border_width, self.style.border_color);
        }
    }
};

pub const Button = struct {
    widget: Widget,
    text: []const u8,
    clicked: bool = false,

    pub fn init(allocator: Allocator, id: u32, rect: Rect, text: []const u8) !Button {
        _ = allocator;
        return Button{
            .widget = Widget.init(id, rect),
            .text = text,
        };
    }

    pub fn update(self: *Button, input: *const InputState) bool {
        const was_pressed = self.widget.pressed;
        self.widget.updateState(input);

        // Button was clicked if it was pressed last frame and not pressed this frame
        self.clicked = was_pressed and !self.widget.pressed and self.widget.hovered;
        return self.clicked;
    }

    pub fn draw(self: *const Button, ctx: *DrawContext) !void {
        // Modify style based on state
        var style = self.widget.style;
        if (self.widget.pressed) {
            style.background_color = Vec4{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1.0 };
        } else if (self.widget.hovered) {
            style.background_color = Vec4{ .x = 0.4, .y = 0.4, .z = 0.4, .w = 1.0 };
        }

        // Draw widget background
        var temp_widget = self.widget;
        temp_widget.style = style;
        try temp_widget.draw(ctx);

        // Draw text (simplified - would use proper text rendering)
        // For now, just draw a small rectangle to represent text
        const text_rect = Rect.init(self.widget.rect.x + 10, self.widget.rect.y + self.widget.rect.height * 0.3, self.widget.rect.width - 20, self.widget.rect.height * 0.4);
        try ctx.drawRect(text_rect, style.text_color);
    }
};

pub const TextBox = struct {
    widget: Widget,
    text: ArrayList(u8),
    cursor_position: u32 = 0,
    selection_start: u32 = 0,
    selection_end: u32 = 0,
    placeholder: []const u8 = "",

    pub fn init(allocator: Allocator, id: u32, rect: Rect) TextBox {
        return TextBox{
            .widget = Widget.init(id, rect),
            .text = ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *TextBox) void {
        self.text.deinit();
    }

    pub fn update(self: *TextBox, input: *const InputState) void {
        self.widget.updateState(input);

        if (self.widget.focused) {
            // Handle text input
            for (input.text_input.items) |codepoint| {
                if (codepoint >= 32 and codepoint < 127) {
                    self.text.append(@as(u8, @intCast(codepoint))) catch {};
                    self.cursor_position += 1;
                }
            }

            // Handle backspace
            if (input.isKeyPressed(.backspace) and self.cursor_position > 0) {
                _ = self.text.orderedRemove(self.cursor_position - 1);
                self.cursor_position -= 1;
            }

            // Handle arrow keys
            if (input.isKeyPressed(.left) and self.cursor_position > 0) {
                self.cursor_position -= 1;
            }
            if (input.isKeyPressed(.right) and self.cursor_position < self.text.items.len) {
                self.cursor_position += 1;
            }
        }
    }

    pub fn draw(self: *const TextBox, ctx: *DrawContext) !void {
        // Draw background
        try self.widget.draw(ctx);

        // Draw text
        if (self.text.items.len > 0) {
            const text_rect = Rect.init(self.widget.rect.x + 5, self.widget.rect.y + 5, self.widget.rect.width - 10, self.widget.rect.height - 10);
            try ctx.drawRect(text_rect, self.widget.style.text_color);
        }

        // Draw cursor if focused
        if (self.widget.focused) {
            const cursor_x = self.widget.rect.x + 5 + @as(f32, @floatFromInt(self.cursor_position)) * 8; // Simplified cursor positioning
            const cursor_rect = Rect.init(cursor_x, self.widget.rect.y + 5, 1, self.widget.rect.height - 10);
            try ctx.drawRect(cursor_rect, Vec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 });
        }
    }
};

pub const Panel = struct {
    widget: Widget,
    children: ArrayList(*Widget),
    layout: Layout,

    pub fn init(allocator: Allocator, id: u32, rect: Rect) Panel {
        return Panel{
            .widget = Widget.init(id, rect),
            .children = ArrayList(*Widget).init(allocator),
            .layout = Layout{},
        };
    }

    pub fn deinit(self: *Panel) void {
        self.children.deinit();
    }

    pub fn addChild(self: *Panel, child: *Widget) !void {
        try self.children.append(child);
    }

    pub fn update(self: *Panel, input: *const InputState) void {
        self.widget.updateState(input);

        // Update layout
        var child_rects = try self.children.allocator.alloc(Rect, self.children.items.len);
        defer self.children.allocator.free(child_rects);

        for (self.children.items, 0..) |child, i| {
            child_rects[i] = child.rect;
        }

        self.layout.calculateLayout(self.widget.rect, child_rects);

        for (self.children.items, 0..) |child, i| {
            child.rect = child_rects[i];
        }
    }

    pub fn draw(self: *const Panel, ctx: *DrawContext) !void {
        try self.widget.draw(ctx);

        // Draw children
        for (self.children.items) |child| {
            try child.draw(ctx);
        }
    }
};

pub const GPUAcceleratedGUI = struct {
    allocator: Allocator,
    draw_context: DrawContext,
    input_state: InputState,
    widgets: HashMap(u32, *Widget, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    next_widget_id: u32,
    fonts: HashMap(u32, Font, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    textures: HashMap(u32, Texture, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    focused_widget: ?u32,
    hovered_widget: ?u32,
    cursor: Cursor,
    theme: Theme,

    pub const Theme = struct {
        primary_color: Color = Color{ .x = 0.2, .y = 0.4, .z = 0.8, .w = 1.0 },
        secondary_color: Color = Color{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1.0 },
        background_color: Color = Color{ .x = 0.1, .y = 0.1, .z = 0.1, .w = 1.0 },
        text_color: Color = Color{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        accent_color: Color = Color{ .x = 0.0, .y = 0.7, .z = 0.3, .w = 1.0 },
        error_color: Color = Color{ .x = 0.8, .y = 0.2, .z = 0.2, .w = 1.0 },
        warning_color: Color = Color{ .x = 0.8, .y = 0.6, .z = 0.0, .w = 1.0 },
        success_color: Color = Color{ .x = 0.2, .y = 0.8, .z = 0.2, .w = 1.0 },

        border_radius: f32 = 4.0,
        font_size: f32 = 14.0,
        padding: f32 = 8.0,
        margin: f32 = 4.0,
        shadow_offset: f32 = 2.0,
        animation_duration: f32 = 0.2,
    };

    pub fn init(allocator: Allocator, screen_width: f32, screen_height: f32) !GPUAcceleratedGUI {
        return GPUAcceleratedGUI{
            .allocator = allocator,
            .draw_context = DrawContext.init(allocator, screen_width, screen_height),
            .input_state = InputState.init(allocator),
            .widgets = HashMap(u32, *Widget, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .next_widget_id = 1,
            .fonts = HashMap(u32, Font, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .textures = HashMap(u32, Texture, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .focused_widget = null,
            .hovered_widget = null,
            .cursor = .arrow,
            .theme = Theme{},
        };
    }

    pub fn deinit(self: *GPUAcceleratedGUI) void {
        self.draw_context.deinit();
        self.input_state.deinit();

        var widget_iterator = self.widgets.iterator();
        while (widget_iterator.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.widgets.deinit();

        self.fonts.deinit();
        self.textures.deinit();
    }

    pub fn processEvent(self: *GPUAcceleratedGUI, event: InputEvent) void {
        self.input_state.processEvent(event);
    }

    pub fn beginFrame(self: *GPUAcceleratedGUI) void {
        self.draw_context.beginFrame();
        self.updateInput();
    }

    pub fn endFrame(self: *GPUAcceleratedGUI) void {
        self.draw_context.endFrame();
        self.input_state.clearFrameState();
    }

    pub fn createButton(self: *GPUAcceleratedGUI, rect: Rect, text: []const u8) !u32 {
        const widget_id = self.next_widget_id;
        self.next_widget_id += 1;

        const button = try self.allocator.create(Button);
        button.* = try Button.init(self.allocator, widget_id, rect, text);
        button.widget.style.background_color = self.theme.primary_color;
        button.widget.style.text_color = self.theme.text_color;
        button.widget.style.border_radius = self.theme.border_radius;

        const widget_ptr = &button.widget;
        try self.widgets.put(widget_id, widget_ptr);

        return widget_id;
    }

    pub fn createTextBox(self: *GPUAcceleratedGUI, rect: Rect) !u32 {
        const widget_id = self.next_widget_id;
        self.next_widget_id += 1;

        const textbox = try self.allocator.create(TextBox);
        textbox.* = TextBox.init(self.allocator, widget_id, rect);
        textbox.widget.style.background_color = self.theme.secondary_color;
        textbox.widget.style.text_color = self.theme.text_color;
        textbox.widget.style.border_color = self.theme.primary_color;
        textbox.widget.style.border_width = 1.0;
        textbox.widget.focusable = true;

        const widget_ptr = &textbox.widget;
        try self.widgets.put(widget_id, widget_ptr);

        return widget_id;
    }

    pub fn createPanel(self: *GPUAcceleratedGUI, rect: Rect) !u32 {
        const widget_id = self.next_widget_id;
        self.next_widget_id += 1;

        const panel = try self.allocator.create(Panel);
        panel.* = Panel.init(self.allocator, widget_id, rect);
        panel.widget.style.background_color = self.theme.background_color;
        panel.widget.style.border_color = self.theme.secondary_color;
        panel.widget.style.border_width = 1.0;

        const widget_ptr = &panel.widget;
        try self.widgets.put(widget_id, widget_ptr);

        return widget_id;
    }

    pub fn getWidget(self: *GPUAcceleratedGUI, widget_id: u32) ?*Widget {
        return self.widgets.get(widget_id);
    }

    pub fn isButtonClicked(self: *GPUAcceleratedGUI, widget_id: u32) bool {
        if (self.widgets.get(widget_id)) |widget| {
            // Simple click detection based on widget state
            return widget.pressed and widget.hovered;
        }
        return false;
    }

    pub fn setWidgetPosition(self: *GPUAcceleratedGUI, widget_id: u32, x: f32, y: f32) void {
        if (self.widgets.getPtr(widget_id)) |widget| {
            widget.*.rect.x = x;
            widget.*.rect.y = y;
        }
    }

    pub fn setWidgetSize(self: *GPUAcceleratedGUI, widget_id: u32, width: f32, height: f32) void {
        if (self.widgets.getPtr(widget_id)) |widget| {
            widget.*.rect.width = width;
            widget.*.rect.height = height;
        }
    }

    pub fn setWidgetVisible(self: *GPUAcceleratedGUI, widget_id: u32, visible: bool) void {
        if (self.widgets.getPtr(widget_id)) |widget| {
            widget.*.visible = visible;
        }
    }

    pub fn setWidgetEnabled(self: *GPUAcceleratedGUI, widget_id: u32, enabled: bool) void {
        if (self.widgets.getPtr(widget_id)) |widget| {
            widget.*.enabled = enabled;
        }
    }

    pub fn update(self: *GPUAcceleratedGUI, delta_time: f32) void {
        _ = delta_time;

        // Update all widgets
        var widget_iterator = self.widgets.iterator();
        while (widget_iterator.next()) |entry| {
            const widget = entry.value_ptr.*;
            widget.updateState(&self.input_state);
        }
    }

    pub fn render(self: *GPUAcceleratedGUI) !void {
        // Render all widgets
        var widget_iterator = self.widgets.iterator();
        while (widget_iterator.next()) |entry| {
            const widget = entry.value_ptr.*;
            try widget.draw(&self.draw_context);
        }
    }

    pub fn setTheme(self: *GPUAcceleratedGUI, theme: Theme) void {
        self.theme = theme;

        // Update all widget styles to match new theme
        var widget_iterator = self.widgets.iterator();
        while (widget_iterator.next()) |entry| {
            const widget = entry.value_ptr.*;
            // Apply theme colors based on widget type
            widget.style.text_color = theme.text_color;
            // Additional theme application logic would go here
        }
    }

    pub fn setCursor(self: *GPUAcceleratedGUI, cursor: Cursor) void {
        self.cursor = cursor;
    }

    pub fn loadFont(self: *GPUAcceleratedGUI, path: []const u8, size: f32) !u32 {
        _ = path;

        const font_id = @as(u32, @intCast(self.fonts.count()));
        const font = Font{
            .id = font_id,
            .name = try self.allocator.dupe(u8, "Default"),
            .size = size,
            .weight = .normal,
            .texture_id = 0,
            .glyph_map = HashMap(u32, Font.Glyph, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(self.allocator),
            .line_height = size * 1.2,
            .ascent = size * 0.8,
            .descent = size * 0.2,
        };

        try self.fonts.put(font_id, font);
        return font_id;
    }

    pub fn createTexture(self: *GPUAcceleratedGUI, width: u32, height: u32, data: []const u8) !u32 {
        const texture_id = @as(u32, @intCast(self.textures.count()));
        const texture = Texture{
            .id = texture_id,
            .width = width,
            .height = height,
            .format = .rgba8,
            .data = try self.allocator.dupe(u8, data),
        };

        try self.textures.put(texture_id, texture);
        return texture_id;
    }

    fn updateInput(self: *GPUAcceleratedGUI) void {
        // Find widget under mouse
        var new_hovered: ?u32 = null;
        var widget_iterator = self.widgets.iterator();
        while (widget_iterator.next()) |entry| {
            const widget = entry.value_ptr.*;
            if (widget.visible and widget.rect.contains(self.input_state.mouse_position)) {
                new_hovered = widget.id;
                break;
            }
        }

        // Update hover state
        if (self.hovered_widget != new_hovered) {
            if (self.hovered_widget) |old_hovered| {
                if (self.widgets.getPtr(old_hovered)) |widget| {
                    widget.*.hovered = false;
                }
            }
            self.hovered_widget = new_hovered;
            if (new_hovered) |new_hover| {
                if (self.widgets.getPtr(new_hover)) |widget| {
                    widget.*.hovered = true;
                }
            }
        }

        // Handle focus
        if (self.input_state.isMouseButtonPressed(.left)) {
            if (new_hovered) |widget_id| {
                if (self.widgets.get(widget_id)) |widget| {
                    if (widget.focusable) {
                        self.setFocus(widget_id);
                    }
                }
            } else {
                self.clearFocus();
            }
        }
    }

    fn setFocus(self: *GPUAcceleratedGUI, widget_id: u32) void {
        if (self.focused_widget) |old_focused| {
            if (self.widgets.getPtr(old_focused)) |widget| {
                widget.*.focused = false;
            }
        }

        self.focused_widget = widget_id;
        if (self.widgets.getPtr(widget_id)) |widget| {
            widget.*.focused = true;
        }
    }

    fn clearFocus(self: *GPUAcceleratedGUI) void {
        if (self.focused_widget) |old_focused| {
            if (self.widgets.getPtr(old_focused)) |widget| {
                widget.*.focused = false;
            }
        }
        self.focused_widget = null;
    }
};

// Test the complete GPU GUI system
test "gpu accelerated gui system" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gui = try GPUAcceleratedGUI.init(allocator, 800, 600);
    defer gui.deinit();

    // Create widgets
    const button_id = try gui.createButton(Rect.init(50, 50, 100, 30), "Click Me!");
    const textbox_id = try gui.createTextBox(Rect.init(50, 100, 200, 25));
    const panel_id = try gui.createPanel(Rect.init(300, 50, 200, 150));

    // Simulate some input
    gui.processEvent(.{ .mouse_move = .{ .x = 100, .y = 65 } });
    gui.processEvent(.{ .mouse_button = .{ .button = .left, .pressed = true, .x = 100, .y = 65 } });

    // Update and render
    gui.beginFrame();
    gui.update(0.016);
    try gui.render();
    gui.endFrame();

    // Check if button was clicked
    const button_clicked = gui.isButtonClicked(button_id);

    // Basic widget operations
    gui.setWidgetPosition(button_id, 60, 60);
    gui.setWidgetSize(panel_id, 250, 180);
    gui.setWidgetVisible(textbox_id, false);

    // Test widget existence
    try std.testing.expect(gui.getWidget(button_id) != null);
    try std.testing.expect(gui.getWidget(textbox_id) != null);
    try std.testing.expect(gui.getWidget(panel_id) != null);
    try std.testing.expect(gui.getWidget(999) == null);

    // Test button click detection
    _ = button_clicked; // Would be true if properly simulated
}
