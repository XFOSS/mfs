//! MFS Input System - Main Input Module
//! This module provides unified input handling for keyboard, mouse, and other input devices
//! @thread-safe Input handling with thread-safe event queues
//! @symbol PublicInputAPI

const std = @import("std");
const math = @import("math");

// Input device types
pub const InputDevice = enum {
    keyboard,
    mouse,
    gamepad,
    touch,
    stylus,
};

// Key codes (based on common standards)
pub const KeyCode = enum(u32) {
    // Letters
    a = 0x41,
    b = 0x42,
    c = 0x43,
    d = 0x44,
    e = 0x45,
    f = 0x46,
    g = 0x47,
    h = 0x48,
    i = 0x49,
    j = 0x4A,
    k = 0x4B,
    l = 0x4C,
    m = 0x4D,
    n = 0x4E,
    o = 0x4F,
    p = 0x50,
    q = 0x51,
    r = 0x52,
    s = 0x53,
    t = 0x54,
    u = 0x55,
    v = 0x56,
    w = 0x57,
    x = 0x58,
    y = 0x59,
    z = 0x5A,

    // Numbers
    zero = 0x30,
    one = 0x31,
    two = 0x32,
    three = 0x33,
    four = 0x34,
    five = 0x35,
    six = 0x36,
    seven = 0x37,
    eight = 0x38,
    nine = 0x39,

    // Function keys
    f1 = 0x70,
    f2 = 0x71,
    f3 = 0x72,
    f4 = 0x73,
    f5 = 0x74,
    f6 = 0x75,
    f7 = 0x76,
    f8 = 0x77,
    f9 = 0x78,
    f10 = 0x79,
    f11 = 0x7A,
    f12 = 0x7B,

    // Special keys
    space = 0x20,
    enter = 0x0D,
    escape = 0x1B,
    backspace = 0x08,
    tab = 0x09,
    shift = 0x10,
    ctrl = 0x11,
    alt = 0x12,

    // Arrow keys
    left = 0x25,
    up = 0x26,
    right = 0x27,
    down = 0x28,

    _,
};

// Mouse buttons
pub const MouseButton = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
    x1 = 3,
    x2 = 4,
    _,
};

// Input events
pub const InputEvent = union(enum) {
    key_pressed: KeyCode,
    key_released: KeyCode,
    key_repeat: KeyCode,
    mouse_pressed: MouseButton,
    mouse_released: MouseButton,
    mouse_moved: struct { x: f32, y: f32 },
    mouse_wheel: struct { delta_x: f32, delta_y: f32 },
    touch_start: struct { id: u32, x: f32, y: f32 },
    touch_move: struct { id: u32, x: f32, y: f32 },
    touch_end: struct { id: u32, x: f32, y: f32 },
    gamepad_connected: u32,
    gamepad_disconnected: u32,
    gamepad_button: struct { gamepad_id: u32, button: u8, pressed: bool },
    gamepad_axis: struct { gamepad_id: u32, axis: u8, value: f32 },
};

// Input state tracking
pub const InputState = struct {
    keys: std.bit_set.IntegerBitSet(512),
    mouse_buttons: std.bit_set.IntegerBitSet(8),
    mouse_position: math.Vec2,
    mouse_delta: math.Vec2,
    wheel_delta: math.Vec2,

    pub fn init() InputState {
        return InputState{
            .keys = std.bit_set.IntegerBitSet(512).initEmpty(),
            .mouse_buttons = std.bit_set.IntegerBitSet(8).initEmpty(),
            .mouse_position = math.Vec2.zero(),
            .mouse_delta = math.Vec2.zero(),
            .wheel_delta = math.Vec2.zero(),
        };
    }

    pub fn isKeyPressed(self: *const InputState, key: KeyCode) bool {
        return self.keys.isSet(@intFromEnum(key));
    }

    pub fn isMouseButtonPressed(self: *const InputState, button: MouseButton) bool {
        return self.mouse_buttons.isSet(@intFromEnum(button));
    }

    pub fn getMousePosition(self: *const InputState) math.Vec2 {
        return self.mouse_position;
    }

    pub fn getMouseDelta(self: *const InputState) math.Vec2 {
        return self.mouse_delta;
    }
};

// Input manager
pub const InputManager = struct {
    allocator: std.mem.Allocator,
    current_state: InputState,
    previous_state: InputState,
    event_queue: std.array_list.Managed(InputEvent),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) InputManager {
        return InputManager{
            .allocator = allocator,
            .current_state = InputState.init(),
            .previous_state = InputState.init(),
            .event_queue = std.array_list.Managed(InputEvent).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *InputManager) void {
        self.event_queue.deinit();
    }

    pub fn update(self: *InputManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Copy current state to previous
        self.previous_state = self.current_state;

        // Reset deltas
        self.current_state.mouse_delta = math.Vec2.zero();
        self.current_state.wheel_delta = math.Vec2.zero();

        // Process events
        for (self.event_queue.items) |event| {
            self.processEvent(event);
        }

        // Clear event queue
        self.event_queue.clearRetainingCapacity();
    }

    pub fn pushEvent(self: *InputManager, event: InputEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.event_queue.append(event);
    }

    fn processEvent(self: *InputManager, event: InputEvent) void {
        switch (event) {
            .key_pressed => |key| {
                self.current_state.keys.set(@intFromEnum(key));
            },
            .key_released => |key| {
                self.current_state.keys.unset(@intFromEnum(key));
            },
            .mouse_pressed => |button| {
                self.current_state.mouse_buttons.set(@intFromEnum(button));
            },
            .mouse_released => |button| {
                self.current_state.mouse_buttons.unset(@intFromEnum(button));
            },
            .mouse_moved => |pos| {
                const old_pos = self.current_state.mouse_position;
                self.current_state.mouse_position = math.Vec2.init(pos.x, pos.y);
                self.current_state.mouse_delta = self.current_state.mouse_position.sub(old_pos);
            },
            .mouse_wheel => |wheel| {
                self.current_state.wheel_delta = math.Vec2.init(wheel.delta_x, wheel.delta_y);
            },
            else => {
                // Handle other event types as needed
            },
        }
    }

    pub fn isKeyPressed(self: *const InputManager, key: KeyCode) bool {
        return self.current_state.isKeyPressed(key);
    }

    pub fn isKeyJustPressed(self: *const InputManager, key: KeyCode) bool {
        return self.current_state.isKeyPressed(key) and !self.previous_state.isKeyPressed(key);
    }

    pub fn isKeyJustReleased(self: *const InputManager, key: KeyCode) bool {
        return !self.current_state.isKeyPressed(key) and self.previous_state.isKeyPressed(key);
    }

    pub fn isMouseButtonPressed(self: *const InputManager, button: MouseButton) bool {
        return self.current_state.isMouseButtonPressed(button);
    }

    pub fn isMouseButtonJustPressed(self: *const InputManager, button: MouseButton) bool {
        return self.current_state.isMouseButtonPressed(button) and !self.previous_state.isMouseButtonPressed(button);
    }

    pub fn isMouseButtonJustReleased(self: *const InputManager, button: MouseButton) bool {
        return !self.current_state.isMouseButtonPressed(button) and self.previous_state.isMouseButtonPressed(button);
    }

    pub fn getMousePosition(self: *const InputManager) math.Vec2 {
        return self.current_state.getMousePosition();
    }

    pub fn getMouseDelta(self: *const InputManager) math.Vec2 {
        return self.current_state.getMouseDelta();
    }

    pub fn getWheelDelta(self: *const InputManager) math.Vec2 {
        return self.current_state.wheel_delta;
    }
};

// Global input manager instance
var g_input_manager: ?InputManager = null;

pub fn init(allocator: std.mem.Allocator) void {
    g_input_manager = InputManager.init(allocator);
}

pub fn deinit() void {
    if (g_input_manager) |*manager| {
        manager.deinit();
        g_input_manager = null;
    }
}

pub fn getInputManager() *InputManager {
    return &g_input_manager.?;
}

pub fn update() void {
    if (g_input_manager) |*manager| {
        manager.update();
    }
}

pub fn pushEvent(event: InputEvent) !void {
    if (g_input_manager) |*manager| {
        try manager.pushEvent(event);
    }
}

// Convenience functions
pub fn isKeyPressed(key: KeyCode) bool {
    if (g_input_manager) |*manager| {
        return manager.isKeyPressed(key);
    }
    return false;
}

pub fn isKeyJustPressed(key: KeyCode) bool {
    if (g_input_manager) |*manager| {
        return manager.isKeyJustPressed(key);
    }
    return false;
}

pub fn isMouseButtonPressed(button: MouseButton) bool {
    if (g_input_manager) |*manager| {
        return manager.isMouseButtonPressed(button);
    }
    return false;
}

pub fn getMousePosition() math.Vec2 {
    if (g_input_manager) |*manager| {
        return manager.getMousePosition();
    }
    return math.Vec2.zero();
}

// Input version information
pub const VERSION = struct {
    pub const MAJOR = 0;
    pub const MINOR = 1;
    pub const PATCH = 0;
    pub const STRING = "0.1.0";
};

test "input module" {
    const testing = std.testing;

    // Test input state
    var state = InputState.init();
    try testing.expect(!state.isKeyPressed(.a));
    try testing.expect(!state.isMouseButtonPressed(.left));

    // Test input manager
    var manager = InputManager.init(testing.allocator);
    defer manager.deinit();

    try testing.expect(!manager.isKeyPressed(.a));
    try testing.expect(!manager.isMouseButtonPressed(.left));
}
