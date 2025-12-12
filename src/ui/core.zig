const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const AutoHashMap = std.AutoHashMap;
const math = @import("math");
const Vec4 = math.Vec4;

// Re-export from other modules
pub const backend = @import("backend/backend.zig");
pub const color = @import("color.zig");
pub const color_bridge = @import("color_bridge.zig");
pub const worker = @import("worker.zig");
pub const simple_window = @import("simple_window.zig");

/// Core UI configuration options
pub const UIConfig = struct {
    backend_type: backend.UIBackendType = .gdi,
    enable_threading: bool = true,
    worker_count: u32 = 4,
    default_font_size: f32 = 14.0,
    default_spacing: f32 = 8.0,
    default_padding: f32 = 10.0,
    theme: Theme = .dark,
    enable_animations: bool = true,
    enable_gestures: bool = true,
    vsync: bool = true,
    debug_rendering: bool = false,
};

/// Visual theme options
pub const Theme = enum {
    dark,
    light,
    custom,

    pub fn getColors(self: Theme) ThemeColors {
        return switch (self) {
            .dark => backend.darkTheme(),
            .light => backend.lightTheme(),
            .custom => backend.lightTheme(), // Default fallback
        };
    }
};

/// Collection of colors used in a theme
pub const ThemeColors = struct {
    primary: backend.Color,
    secondary: backend.Color,
    accent: backend.Color,
    background: backend.Color,
    surface: backend.Color,
    on_primary: backend.Color,
    on_secondary: backend.Color,
    on_surface: backend.Color,
    error_color: backend.Color,
    warning: backend.Color,
    success: backend.Color,
    disabled: backend.Color,
    disabled_text: backend.Color,
};

/// Types of input and window events
pub const EventType = enum {
    none,
    mouse_move,
    mouse_down,
    mouse_up,
    key_down,
    key_up,
    text_input,
    window_resize,
    window_close,
    focus_gained,
    focus_lost,
};

/// Mouse button identifiers
pub const MouseButton = enum {
    left,
    right,
    middle,
    x1,
    x2,
};

/// Keyboard key identifiers
pub const KeyCode = enum {
    unknown,
    space,
    enter,
    escape,
    backspace,
    tab,
    delete,
    arrow_left,
    arrow_right,
    arrow_up,
    arrow_down,
    home,
    end,
    page_up,
    page_down,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    num_0,
    num_1,
    num_2,
    num_3,
    num_4,
    num_5,
    num_6,
    num_7,
    num_8,
    num_9,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    shift,
    control,
    alt,
    super,
};

/// Represents an input event with all relevant data
pub const InputEvent = struct {
    event_type: EventType,
    timestamp: u64,

    // Mouse events
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_button: MouseButton = .left,
    mouse_delta_x: f32 = 0,
    mouse_delta_y: f32 = 0,

    // Keyboard events
    key_code: KeyCode = .unknown,
    key_modifiers: KeyModifiers = .{},

    // Text input
    text_input: []const u8 = "",

    // Window events
    window_width: u32 = 0,
    window_height: u32 = 0,

    pub fn init(event_type: EventType) InputEvent {
        return InputEvent{
            .event_type = event_type,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }
};

/// Keyboard modifier keys state
pub const KeyModifiers = struct {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,

    pub fn none() KeyModifiers {
        return .{};
    }

    pub fn hasModifiers(self: KeyModifiers) bool {
        return self.shift or self.control or self.alt or self.super;
    }
};

/// Layout algorithm types
pub const LayoutType = enum {
    absolute,
    vertical,
    horizontal,
    grid,
    stack,
    flow,
};

/// Alignment options for layout
pub const Alignment = enum {
    start,
    center,
    end,
    stretch,
};

/// Represents a size with width and height
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

/// Represents a 2D point with x and y coordinates
pub const Point = struct {
    x: f32,
    y: f32,

    pub const zero = Point{ .x = 0, .y = 0 };

    pub fn init(x: f32, y: f32) Point {
        return Point{ .x = x, .y = y };
    }

    pub fn add(self: Point, other: Point) Point {
        return Point{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn subtract(self: Point, other: Point) Point {
        return Point{ .x = self.x - other.x, .y = self.y - other.y };
    }
};

/// Represents a rectangle with position and size
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
            point.x < self.origin.x + self.size.width and
            point.y >= self.origin.y and
            point.y < self.origin.y + self.size.height;
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return self.origin.x < other.origin.x + other.size.width and
            self.origin.x + self.size.width > other.origin.x and
            self.origin.y < other.origin.y + other.size.height and
            self.origin.y + self.size.height > other.origin.y;
    }

    pub fn center(self: Rect) Point {
        return Point{
            .x = self.origin.x + self.size.width / 2,
            .y = self.origin.y + self.size.height / 2,
        };
    }
};

/// Represents padding or margins on all sides of a rectangle
pub const EdgeInsets = struct {
    top: f32 = 0,
    left: f32 = 0,
    bottom: f32 = 0,
    right: f32 = 0,

    pub const zero = EdgeInsets{};

    pub fn init(top: f32, left: f32, bottom: f32, right: f32) EdgeInsets {
        return EdgeInsets{ .top = top, .left = left, .bottom = bottom, .right = right };
    }

    pub fn all(value: f32) EdgeInsets {
        return EdgeInsets{ .top = value, .left = value, .bottom = value, .right = value };
    }

    pub fn horizontal(value: f32) EdgeInsets {
        return EdgeInsets{ .left = value, .right = value };
    }

    pub fn vertical(value: f32) EdgeInsets {
        return EdgeInsets{ .top = value, .bottom = value };
    }
};

/// Unique identifier for widgets
pub const WidgetId = u32;

/// State information for UI widgets
pub const WidgetState = struct {
    id: WidgetId,
    rect: Rect,
    visible: bool = true,
    enabled: bool = true,
    hovered: bool = false,
    focused: bool = false,
    pressed: bool = false,
    dirty: bool = true,

    pub fn init(id: WidgetId, rect: Rect) WidgetState {
        return WidgetState{
            .id = id,
            .rect = rect,
        };
    }
};

/// Commands used for rendering UI elements
pub const RenderCommand = union(enum) {
    clear: backend.Color,
    rect: struct {
        rect: Rect,
        color: backend.Color,
        border_radius: f32 = 0,
        border_width: f32 = 0,
        border_color: backend.Color = backend.Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
    },
    text: struct {
        rect: Rect,
        text: []const u8,
        color: backend.Color,
        font_size: f32 = 14,
        alignment: backend.TextAlign = .left,
    },
    image: struct {
        rect: Rect,
        image_handle: usize,
    },
    clip_push: Rect,
    clip_pop: void,
    transform_push: struct {
        translation: Point = Point.zero,
        scale: f32 = 1.0,
        rotation: f32 = 0.0,
    },
    transform_pop: void,
};

/// Main UI system that manages widgets, rendering, and input
pub const UISystem = struct {
    allocator: Allocator,
    config: UIConfig,
    backend_instance: backend.UIBackend,
    color_registry: color.ColorRegistry,
    worker_pool: ?worker.ThreadPool,

    // State management
    widgets: AutoHashMap(WidgetId, WidgetState),
    next_widget_id: WidgetId,
    focused_widget: ?WidgetId,
    hovered_widget: ?WidgetId,

    // Input state
    current_input: InputEvent,
    previous_input: InputEvent,

    // Rendering
    render_commands: ArrayList(RenderCommand),
    theme_colors: ThemeColors,

    // Window state
    window_size: Size,
    dpi_scale: f32,

    const Self = @This();

    /// Initialize a new UI system with the provided configuration
    pub fn init(allocator: Allocator, config: UIConfig, window_handle: usize) !Self {
        var backend_instance = try backend.createBackend(allocator, config.backend_type, window_handle);
        errdefer backend_instance.deinit();

        var color_registry = color.ColorRegistry.init(allocator);
        errdefer color_registry.deinit();

        var worker_pool: ?worker.ThreadPool = null;
        if (config.enable_threading) {
            worker_pool = try worker.ThreadPool.init(allocator, config.worker_count);
        }

        var system = Self{
            .allocator = allocator,
            .config = config,
            .backend_instance = backend_instance,
            .color_registry = color_registry,
            .worker_pool = worker_pool,
            .widgets = AutoHashMap(WidgetId, WidgetState).init(allocator),
            .next_widget_id = 1,
            .focused_widget = null,
            .hovered_widget = null,
            .current_input = InputEvent.init(.none),
            .previous_input = InputEvent.init(.none),
            .render_commands = ArrayList(RenderCommand).init(allocator),
            .theme_colors = config.theme.getColors(),
            .window_size = Size.init(800, 600),
            .dpi_scale = 1.0,
        };

        // Initialize color system
        color_bridge.applyAppearance(&system.color_registry, config.theme == .dark);

        return system;
    }

    /// Clean up all resources used by the UI system
    pub fn deinit(self: *Self) void {
        self.render_commands.deinit();
        self.widgets.deinit();
        if (self.worker_pool) |*pool| {
            pool.deinit();
        }
        self.color_registry.deinit();
        self.backend_instance.deinit();
    }

    /// Update the UI system state for the current frame
    pub fn update(self: *Self, delta_time: f32) !void {
        _ = delta_time;

        // Update widget states based on input
        try self.updateWidgetStates();

        // Process any background tasks
        if (self.worker_pool) |*pool| {
            // Check for completed work
            _ = pool.getQueueLength();
        }
    }

    /// Process an input event and update system state accordingly
    pub fn handleInput(self: *Self, event: InputEvent) !void {
        self.previous_input = self.current_input;
        self.current_input = event;

        switch (event.event_type) {
            .mouse_move => {
                try self.updateHoveredWidget(Point.init(event.mouse_x, event.mouse_y));
            },
            .mouse_down => {
                if (self.hovered_widget) |widget_id| {
                    if (self.widgets.getPtr(widget_id)) |widget| {
                        widget.pressed = true;
                        widget.dirty = true;
                    }
                    self.focused_widget = widget_id;
                }
            },
            .mouse_up => {
                if (self.focused_widget) |widget_id| {
                    if (self.widgets.getPtr(widget_id)) |widget| {
                        widget.pressed = false;
                        widget.dirty = true;
                    }
                }
            },
            .window_resize => {
                self.window_size = Size.init(@floatFromInt(event.window_width), @floatFromInt(event.window_height));
                self.backend_instance.resize(event.window_width, event.window_height);

                // Mark all widgets as dirty for layout recalculation
                var iterator = self.widgets.valueIterator();
                while (iterator.next()) |widget| {
                    widget.dirty = true;
                }
            },
            else => {},
        }
    }

    /// Begin a new rendering frame
    pub fn beginFrame(self: *Self) void {
        self.backend_instance.beginFrame(@intFromFloat(self.window_size.width), @intFromFloat(self.window_size.height));
        self.render_commands.clearRetainingCapacity();
    }

    /// End the current rendering frame and flush commands to the backend
    pub fn endFrame(self: *Self) void {
        // Convert render commands to backend draw commands
        var backend_commands = ArrayList(backend.DrawCommand).init(self.allocator);
        defer backend_commands.deinit();

        for (self.render_commands.items) |cmd| {
            const backend_cmd = self.convertRenderCommand(cmd);
            backend_commands.append(backend_cmd) catch continue;
        }

        self.backend_instance.executeDrawCommands(backend_commands.items);
        self.backend_instance.endFrame();
    }

    /// Add a render command to the current frame
    pub fn addRenderCommand(self: *Self, command: RenderCommand) !void {
        try self.render_commands.append(command);
    }

    /// Create a new widget with the given rectangle
    pub fn createWidget(self: *Self, rect: Rect) WidgetId {
        const id = self.next_widget_id;
        self.next_widget_id += 1;

        const widget_state = WidgetState.init(id, rect);
        self.widgets.put(id, widget_state) catch return 0;

        return id;
    }

    /// Get a widget by its ID
    pub fn getWidget(self: *Self, id: WidgetId) ?*WidgetState {
        return self.widgets.getPtr(id);
    }

    /// Remove a widget from the system
    pub fn removeWidget(self: *Self, id: WidgetId) void {
        _ = self.widgets.remove(id);

        if (self.focused_widget == id) {
            self.focused_widget = null;
        }
        if (self.hovered_widget == id) {
            self.hovered_widget = null;
        }
    }

    /// Change the current theme
    pub fn setTheme(self: *Self, theme: Theme) void {
        self.config.theme = theme;
        self.theme_colors = theme.getColors();
        color_bridge.applyAppearance(&self.color_registry, theme == .dark);

        // Mark all widgets as dirty to update colors
        var iterator = self.widgets.valueIterator();
        while (iterator.next()) |widget| {
            widget.dirty = true;
        }
    }

    pub fn getTextSize(self: *Self, text: []const u8, font_size: f32) Size {
        const font_info = backend.FontInfo{
            .name = "Arial",
            .style = backend.FontStyle{ .size = font_size },
        };

        const size = self.backend_instance.getTextSize(text, font_info);
        return Size.init(size.width, size.height);
    }

    pub fn submitBackgroundWork(self: *Self, work_type: worker.WorkerType, priority: u8, work_fn: *const fn (item: *const worker.WorkItem) void) !?u64 {
        if (self.worker_pool) |*pool| {
            return try pool.submitWork(work_type, priority, "", work_fn, null);
        }
        return null;
    }

    fn updateWidgetStates(self: *Self) !void {
        var iterator = self.widgets.valueIterator();
        while (iterator.next()) |widget| {
            // Reset transient states
            if (!widget.pressed) {
                widget.hovered = (self.hovered_widget == widget.id);
            }
            widget.focused = (self.focused_widget == widget.id);
        }
    }

    fn updateHoveredWidget(self: *Self, mouse_pos: Point) !void {
        var new_hovered: ?WidgetId = null;

        var iterator = self.widgets.iterator();
        while (iterator.next()) |entry| {
            const widget = entry.value_ptr;
            if (widget.visible and widget.enabled and widget.rect.contains(mouse_pos)) {
                new_hovered = widget.id;
                break;
            }
        }

        if (self.hovered_widget != new_hovered) {
            // Update previous hovered widget
            if (self.hovered_widget) |old_id| {
                if (self.widgets.getPtr(old_id)) |old_widget| {
                    old_widget.hovered = false;
                    old_widget.dirty = true;
                }
            }

            // Update new hovered widget
            if (new_hovered) |new_id| {
                if (self.widgets.getPtr(new_id)) |new_widget| {
                    new_widget.hovered = true;
                    new_widget.dirty = true;
                }
            }

            self.hovered_widget = new_hovered;
        }
    }

    fn convertRenderCommand(_: *Self, cmd: RenderCommand) backend.DrawCommand {
        return switch (cmd) {
            .clear => |clear_color| backend.DrawCommand{ .clear = clear_color },
            .rect => |rect_data| backend.DrawCommand{ .rect = .{
                .rect = backend.Rect.init(rect_data.rect.origin.x, rect_data.rect.origin.y, rect_data.rect.size.width, rect_data.rect.size.height),
                .color = rect_data.color,
                .border_radius = rect_data.border_radius,
                .border_width = rect_data.border_width,
                .border_color = rect_data.border_color,
            } },
            .text => |text_data| backend.DrawCommand{ .text = .{
                .rect = backend.Rect.init(text_data.rect.origin.x, text_data.rect.origin.y, text_data.rect.size.width, text_data.rect.size.height),
                .text = text_data.text,
                .color = text_data.color,
                .font = backend.FontInfo{
                    .name = "Arial",
                    .style = backend.FontStyle{ .size = text_data.font_size },
                },
                .align_ = text_data.alignment,
            } },
            .clip_push => |rect| backend.DrawCommand{ .clip_push = backend.Rect.init(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height) },
            .clip_pop => backend.DrawCommand{ .clip_pop = {} },
            else => backend.DrawCommand{ .clear = backend.Color{ .r = 0, .g = 0, .b = 0, .a = 1 } },
        };
    }
};

// Utility functions
pub fn isKeyPressed(current: InputEvent, previous: InputEvent, key: KeyCode) bool {
    return current.event_type == .key_down and current.key_code == key and
        (previous.event_type != .key_down or previous.key_code != key);
}

pub fn isMouseButtonPressed(current: InputEvent, previous: InputEvent, button: MouseButton) bool {
    return current.event_type == .mouse_down and current.mouse_button == button and
        previous.event_type != .mouse_down;
}

pub fn getMouseDelta(current: InputEvent, previous: InputEvent) Point {
    if (current.event_type == .mouse_move or previous.event_type == .mouse_move) {
        return Point{
            .x = current.mouse_x - previous.mouse_x,
            .y = current.mouse_y - previous.mouse_y,
        };
    }
    return Point.zero;
}
