const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;

// Import framework components
const backend = @import("backend/backend.zig");
const gpu_accelerated = @import("backend/gpu_accelerated.zig");
const color = @import("color.zig");
const color_bridge = @import("color_bridge.zig");
const window = @import("window.zig");
const worker = @import("worker.zig");
const utils = @import("../utils/utils.zig");
const math = @import("math");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

// Re-export core types for convenience
pub const Color = backend.Color;
pub const Rect = backend.Rect;
pub const TextAlign = backend.TextAlign;
pub const FontStyle = backend.FontStyle;
pub const FontInfo = backend.FontInfo;
pub const Image = backend.Image;
pub const DrawCommand = backend.DrawCommand;

///////////////////////////////////////////////////////////////////////////////
// UNIFIED CONFIGURATION
///////////////////////////////////////////////////////////////////////////////

/// Unified configuration for the UI framework
pub const UIConfig = struct {
    // Backend configuration
    backend_type: BackendType = .gdi,
    hardware_accelerated: bool = true,
    vsync: bool = true,
    enable_threading: bool = true,
    worker_count: u32 = 4,

    // Visual configuration
    default_font_size: f32 = 14.0,
    default_font_family: []const u8 = "Segoe UI",
    default_spacing: f32 = 8.0,
    default_padding: f32 = 10.0,
    theme: Theme = .dark,

    // Feature configuration
    enable_animations: bool = true,
    animation_speed: f32 = 0.3,
    enable_transitions: bool = true,
    enable_gestures: bool = true,
    enable_immediate_mode: bool = true,
    enable_retained_mode: bool = true,

    // Debug options
    debug_rendering: bool = false,
};

/// Backend options for rendering
pub const BackendType = enum {
    // Standard backends
    gdi,
    vulkan,
    opengl,
    software,

    // GPU accelerated backends
    vulkan_gpu,
    metal,
    directx,
    webgpu,

    // Get the corresponding interface backend type
    pub fn toInterfaceBackendType(self: BackendType) backend.UIBackendType {
        return switch (self) {
            .gdi => .gdi,
            .vulkan, .vulkan_gpu => .vulkan,
            .opengl => .opengl,
            .software => .software,
            .metal, .directx, .webgpu => .software, // Fallback for unsupported types
        };
    }

    // Check if this backend uses GPU acceleration
    pub fn isGpuAccelerated(self: BackendType) bool {
        return switch (self) {
            .gdi, .software => false,
            else => true,
        };
    }
};

///////////////////////////////////////////////////////////////////////////////
// UNIFIED THEME SYSTEM
///////////////////////////////////////////////////////////////////////////////

/// Visual theme options
pub const Theme = enum {
    dark,
    light,
    custom,

    /// Get colors for this theme
    pub fn getColors(self: Theme) ThemeColors {
        return switch (self) {
            .dark => darkTheme(),
            .light => lightTheme(),
            .custom => customTheme(),
        };
    }

    /// Get background color
    pub fn getBackgroundColor(self: Theme) Color {
        return switch (self) {
            .dark => Color.fromRgba(0.12, 0.12, 0.12, 1.0),
            .light => Color.fromRgba(0.95, 0.95, 0.95, 1.0),
            .custom => Color.fromRgba(0.2, 0.3, 0.4, 1.0),
        };
    }

    /// Get text color
    pub fn getTextColor(self: Theme) Color {
        return switch (self) {
            .dark => Color.fromRgba(0.9, 0.9, 0.9, 1.0),
            .light => Color.fromRgba(0.1, 0.1, 0.1, 1.0),
            .custom => Color.fromRgba(0.9, 0.9, 0.9, 1.0),
        };
    }

    /// Get accent color
    pub fn getAccentColor(self: Theme) Color {
        return switch (self) {
            .dark => Color.fromRgba(0.0, 0.5, 1.0, 1.0),
            .light => Color.fromRgba(0.0, 0.4, 0.9, 1.0),
            .custom => Color.fromRgba(0.8, 0.2, 0.3, 1.0),
        };
    }
};

/// Collection of colors used in a theme
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

/// Get dark theme colors
pub fn darkTheme() ThemeColors {
    return ThemeColors{
        .primary = Color.fromRgba(0.2, 0.2, 0.2, 1.0),
        .secondary = Color.fromRgba(0.3, 0.3, 0.3, 1.0),
        .accent = Color.fromRgba(0.0, 0.5, 1.0, 1.0),
        .background = Color.fromRgba(0.12, 0.12, 0.12, 1.0),
        .surface = Color.fromRgba(0.18, 0.18, 0.18, 1.0),
        .on_primary = Color.fromRgba(1.0, 1.0, 1.0, 1.0),
        .on_secondary = Color.fromRgba(1.0, 1.0, 1.0, 1.0),
        .on_surface = Color.fromRgba(0.9, 0.9, 0.9, 1.0),
        .error_color = Color.fromRgba(0.9, 0.3, 0.3, 1.0),
        .warning = Color.fromRgba(1.0, 0.7, 0.0, 1.0),
        .success = Color.fromRgba(0.0, 0.7, 0.3, 1.0),
        .disabled = Color.fromRgba(0.5, 0.5, 0.5, 0.5),
        .disabled_text = Color.fromRgba(0.7, 0.7, 0.7, 0.7),
    };
}

/// Get light theme colors
pub fn lightTheme() ThemeColors {
    return ThemeColors{
        .primary = Color.fromRgba(0.9, 0.9, 0.9, 1.0),
        .secondary = Color.fromRgba(0.85, 0.85, 0.85, 1.0),
        .accent = Color.fromRgba(0.0, 0.4, 0.9, 1.0),
        .background = Color.fromRgba(0.95, 0.95, 0.95, 1.0),
        .surface = Color.fromRgba(1.0, 1.0, 1.0, 1.0),
        .on_primary = Color.fromRgba(0.1, 0.1, 0.1, 1.0),
        .on_secondary = Color.fromRgba(0.1, 0.1, 0.1, 1.0),
        .on_surface = Color.fromRgba(0.1, 0.1, 0.1, 1.0),
        .error_color = Color.fromRgba(0.8, 0.2, 0.2, 1.0),
        .warning = Color.fromRgba(0.8, 0.6, 0.0, 1.0),
        .success = Color.fromRgba(0.0, 0.6, 0.2, 1.0),
        .disabled = Color.fromRgba(0.7, 0.7, 0.7, 0.5),
        .disabled_text = Color.fromRgba(0.4, 0.4, 0.4, 0.7),
    };
}

/// Get custom theme colors
pub fn customTheme() ThemeColors {
    return ThemeColors{
        .primary = Color.fromRgba(0.2, 0.3, 0.4, 1.0),
        .secondary = Color.fromRgba(0.3, 0.4, 0.5, 1.0),
        .accent = Color.fromRgba(0.8, 0.2, 0.3, 1.0),
        .background = Color.fromRgba(0.25, 0.25, 0.3, 1.0),
        .surface = Color.fromRgba(0.3, 0.3, 0.35, 1.0),
        .on_primary = Color.fromRgba(0.9, 0.9, 0.9, 1.0),
        .on_secondary = Color.fromRgba(0.9, 0.9, 0.9, 1.0),
        .on_surface = Color.fromRgba(0.9, 0.9, 0.9, 1.0),
        .error_color = Color.fromRgba(1.0, 0.3, 0.3, 1.0),
        .warning = Color.fromRgba(1.0, 0.7, 0.0, 1.0),
        .success = Color.fromRgba(0.0, 0.8, 0.4, 1.0),
        .disabled = Color.fromRgba(0.5, 0.5, 0.6, 0.5),
        .disabled_text = Color.fromRgba(0.6, 0.6, 0.7, 0.7),
    };
}

///////////////////////////////////////////////////////////////////////////////
// UNIFIED INPUT SYSTEM
///////////////////////////////////////////////////////////////////////////////

/// Types of UI events
pub const EventType = enum {
    none,
    mouse_move,
    mouse_down,
    mouse_up,
    mouse_scroll,
    key_down,
    key_up,
    text_input,
    window_resize,
    window_close,
    focus_gained,
    focus_lost,
};

/// Mouse button definitions
pub const MouseButton = enum {
    left,
    right,
    middle,
    back,
    forward,

    // Convert from integer value
    pub fn fromU8(value: u8) MouseButton {
        return switch (value) {
            0 => .left,
            1 => .right,
            2 => .middle,
            3 => .back,
            4 => .forward,
            else => .left,
        };
    }
};

/// Keyboard key definitions
pub const KeyCode = enum {
    unknown,
    space,
    enter,
    escape,
    backspace,
    tab,
    delete,

    // Arrow keys
    arrow_left,
    arrow_right,
    arrow_up,
    arrow_down,

    // Navigation keys
    home,
    end,
    page_up,
    page_down,

    // Alphabet
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

    // Numbers
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

    // Function keys
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

    // Modifiers
    shift,
    control,
    alt,
    super,
};

/// Keyboard modifier flags
pub const KeyModifiers = struct {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,

    /// Create an empty modifier set
    pub fn none() KeyModifiers {
        return KeyModifiers{};
    }

    /// Check if any modifiers are active
    pub fn hasModifiers(self: KeyModifiers) bool {
        return self.shift or self.control or self.alt or self.super;
    }
};

/// Input event with associated data
pub const InputEvent = struct {
    // Common fields
    event_type: EventType,
    timestamp: u64,

    // Mouse fields
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_button: MouseButton = .left,
    mouse_delta_x: f32 = 0,
    mouse_delta_y: f32 = 0,
    mouse_scroll_x: f32 = 0,
    mouse_scroll_y: f32 = 0,

    // Keyboard fields
    key_code: KeyCode = .unknown,
    key_modifiers: KeyModifiers = KeyModifiers{},

    // Text input
    text_input: [8]u8 = [_]u8{0} ** 8,

    // Window fields
    window_width: u32 = 0,
    window_height: u32 = 0,

    /// Initialize a new input event
    pub fn init(event_type: EventType) InputEvent {
        return InputEvent{
            .event_type = event_type,
            .timestamp = @intCast(std.time.milliTimestamp()),
        };
    }
};

///////////////////////////////////////////////////////////////////////////////
// UNIFIED DRAWING SYSTEM
///////////////////////////////////////////////////////////////////////////////

/// Unified draw command for all backends
pub const RenderCommand = union(enum) {
    // Basic commands
    clear: Color,
    rect: struct {
        rect: Rect,
        color: Color,
        border_radius: f32 = 0.0,
        border_width: f32 = 0.0,
        border_color: Color = Color.fromRgba(0, 0, 0, 0),
    },
    text: struct {
        rect: Rect,
        text: []const u8,
        color: Color,
        font_size: f32 = 14.0,
        alignment: TextAlign = .left,
    },
    image: struct {
        rect: Rect,
        image_handle: usize,
    },

    // Clipping commands
    clip_push: Rect,
    clip_pop: void,

    // Transform commands
    transform_push: struct {
        translation: Vec2 = Vec2.zero(),
        scale: Vec2 = Vec2.init(1.0, 1.0),
        rotation: f32 = 0.0,
    },
    transform_pop: void,

    // GPU-specific commands
    custom_shader: struct {
        shader_id: u32,
        uniforms: []const u8,
        vertex_buffer: u32,
        index_buffer: u32,
    },

    // Convert to backend DrawCommand
    pub fn toDrawCommand(self: RenderCommand, allocator: Allocator) !DrawCommand {
        return switch (self) {
            .clear => |clear_color| DrawCommand{ .clear = clear_color },
            .rect => |rect_data| DrawCommand{ .rect = .{
                .rect = rect_data.rect,
                .color = rect_data.color,
                .border_radius = rect_data.border_radius,
                .border_width = rect_data.border_width,
                .border_color = rect_data.border_color,
            } },
            .text => |text_data| DrawCommand{ .text = .{
                .rect = text_data.rect,
                .text = text_data.text,
                .color = text_data.color,
                .font = .{ .name = "default", .style = .{ .size = text_data.font_size } },
                .align_ = text_data.alignment,
            } },
            .image => |image_data| DrawCommand{ .image = .{
                .rect = image_data.rect,
                .image = @ptrFromInt(image_data.image_handle),
            } },
            .clip_push => |rect| DrawCommand{ .clip_push = rect },
            .clip_pop => DrawCommand{ .clip_pop = {} },
            .transform_push, .transform_pop, .custom_shader => {
                // Create a custom command for transforms and shaders
                const data = try allocator.create(RenderCommand);
                data.* = self;

                return DrawCommand{ .custom = .{
                    .data = data,
                    .callback = customCommandCallback,
                } };
            },
        };
    }

    fn customCommandCallback(data: *anyopaque, backend_data: *anyopaque) void {
        const cmd = @as(*RenderCommand, @ptrCast(@alignCast(data)));
        const ctx = @as(*backend.UIBackend, @ptrCast(@alignCast(backend_data)));

        // Handle custom commands based on the backend
        _ = cmd;
        _ = ctx;
        // Implementation depends on backend capabilities
    }
};

///////////////////////////////////////////////////////////////////////////////
// UNIFIED WIDGET SYSTEM
///////////////////////////////////////////////////////////////////////////////

/// Widget identifier type
pub const WidgetId = u32;

/// Widget state information
pub const WidgetState = struct {
    id: WidgetId,
    rect: Rect,
    visible: bool = true,
    enabled: bool = true,
    hovered: bool = false,
    focused: bool = false,
    pressed: bool = false,
    dirty: bool = true,

    /// Initialize a new widget state
    pub fn init(id: WidgetId, rect: Rect) WidgetState {
        return WidgetState{
            .id = id,
            .rect = rect,
            .visible = true,
            .enabled = true,
            .hovered = false,
            .focused = false,
            .pressed = false,
            .dirty = true,
        };
    }
};

///////////////////////////////////////////////////////////////////////////////
// GRAPHICS RENDERING INTEGRATION
///////////////////////////////////////////////////////////////////////////////

/// Information for layout and drawing
pub const LayoutRect = struct {
    origin: Vec2,
    size: Vec2,

    /// Create a new layout rectangle
    pub fn init(x: f32, y: f32, width: f32, height: f32) LayoutRect {
        return LayoutRect{
            .origin = Vec2.init(x, y),
            .size = Vec2.init(width, height),
        };
    }

    /// Convert to a backend Rect
    pub fn toRect(self: LayoutRect) Rect {
        return Rect.init(self.origin.x, self.origin.y, self.size.x, self.size.y);
    }
};

/// Error types for unified framework
pub const UIError = error{
    InitializationFailed,
    RenderContextNotFound,
    ShaderCompilationFailed,
    BufferCreationFailed,
    TextureCreationFailed,
    FontLoadingFailed,
    OutOfMemory,
    InvalidParameter,
    ResourceNotFound,
    BackendNotImplemented,
    BackendAlreadyInitialized,
    BackendInitializationFailed,
    UIAlreadyInitialized,
    UINotInitialized,
};

///////////////////////////////////////////////////////////////////////////////
// UNIFIED FRAMEWORK SYSTEM
///////////////////////////////////////////////////////////////////////////////

/// Main UI framework system that integrates all UI components
pub const UISystem = struct {
    allocator: Allocator,
    config: UIConfig,
    backend: ?backend.UIBackend,
    gpu_backend: ?gpu_accelerated.GPU,
    widgets: AutoHashMap(WidgetId, WidgetState),
    render_commands: ArrayList(RenderCommand),
    theme_colors: ThemeColors,
    next_widget_id: WidgetId = 1,

    const Self = @This();

    /// Initialize the UI system
    pub fn init(allocator: Allocator, config: UIConfig) !Self {
        const widgets = AutoHashMap(WidgetId, WidgetState).init(allocator);
        const render_commands = ArrayList(RenderCommand).init(allocator);

        return Self{
            .allocator = allocator,
            .config = config,
            .backend = null,
            .gpu_backend = null,
            .widgets = widgets,
            .render_commands = render_commands,
            .theme_colors = config.theme.getColors(),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.backend) |*b| {
            b.deinit();
        }

        if (self.gpu_backend) |*b| {
            b.deinit();
        }

        self.widgets.deinit();
        self.render_commands.deinit();
    }

    /// Initialize backend based on configuration
    pub fn initBackend(self: *Self, window_handle: usize) !void {
        if (self.backend != null) return UIError.BackendAlreadyInitialized;

        // Choose the appropriate backend based on config
        if (self.config.backend_type.isGpuAccelerated()) {
            const backend_type = switch (self.config.backend_type) {
                .vulkan_gpu => gpu_accelerated.BackendType.vulkan,
                .metal => gpu_accelerated.BackendType.metal,
                .directx => gpu_accelerated.BackendType.directx,
                .webgpu => gpu_accelerated.BackendType.vulkan, // Fallback to vulkan
                else => gpu_accelerated.BackendType.vulkan,
            };

            self.gpu_backend = try gpu_accelerated.GPU.init(self.allocator, backend_type);
        } else {
            const backend_interface = try backend.getBackendInterface(self.config.backend_type.toInterfaceBackendType());
            self.backend = try backend.UIBackend.init(self.allocator, backend_interface, window_handle);
        }
    }

    /// Begin a new frame
    pub fn beginFrame(self: *Self, width: u32, height: u32) !void {
        // Clear the render commands from the previous frame
        self.render_commands.clearRetainingCapacity();

        // Begin the frame in the appropriate backend
        if (self.backend) |*b| {
            b.beginFrame(width, height);
        } else if (self.gpu_backend) |*b| {
            try b.beginFrame(width, height);
        } else {
            return UIError.BackendNotImplemented;
        }
    }

    /// End the frame and submit render commands
    pub fn endFrame(self: *Self) !void {
        // If using standard backend, convert and submit render commands
        if (self.backend) |*b| {
            var draw_commands = try ArrayList(DrawCommand).initCapacity(self.allocator, self.render_commands.items.len);
            defer draw_commands.deinit();

            for (self.render_commands.items) |cmd| {
                const draw_cmd = try cmd.toDrawCommand(self.allocator);
                try draw_commands.append(draw_cmd);
            }

            b.executeDrawCommands(draw_commands.items);
            b.endFrame();
        }
        // If using GPU backend, use its render methods
        else if (self.gpu_backend) |*b| {
            try b.renderCommands(self.render_commands.items);
            try b.endFrame();
        } else {
            return UIError.BackendNotImplemented;
        }
    }

    /// Add a render command
    pub fn addRenderCommand(self: *Self, cmd: RenderCommand) !void {
        try self.render_commands.append(cmd);
    }

    /// Create a new widget
    pub fn createWidget(self: *Self, rect: Rect) !WidgetId {
        const id = self.next_widget_id;
        self.next_widget_id += 1;

        try self.widgets.put(id, WidgetState.init(id, rect));
        return id;
    }

    /// Get a widget state by ID
    pub fn getWidget(self: *Self, id: WidgetId) ?*WidgetState {
        return self.widgets.getPtr(id);
    }

    /// Remove a widget
    pub fn removeWidget(self: *Self, id: WidgetId) void {
        _ = self.widgets.remove(id);
    }

    /// Set the active theme
    pub fn setTheme(self: *Self, theme: Theme) void {
        self.config.theme = theme;
        self.theme_colors = theme.getColors();
    }
};

// Additional function and modifier keys for the KeyCode enum defined above
