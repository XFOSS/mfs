//! MFS Engine - Input Module
//! Comprehensive input handling system for keyboard, mouse, gamepad, and touch
//! Supports input mapping, action binding, and multi-device input
//! @thread-safe Input events are processed on the main thread
//! @performance Optimized for low-latency input processing

const std = @import("std");
const builtin = @import("builtin");
const input = @import("input.zig");

// Re-export main input types
pub const InputEvent = input.InputEvent;
pub const InputState = input.InputState;
pub const InputManager = input.InputManager;
pub const InputSystem = input.InputSystem;
pub const InputConfig = InputSystemConfig;

// Input device types
pub const InputDevice = enum {
    keyboard,
    mouse,
    gamepad,
    touch,
    joystick,

    pub fn getName(self: InputDevice) []const u8 {
        return switch (self) {
            .keyboard => "Keyboard",
            .mouse => "Mouse",
            .gamepad => "Gamepad",
            .touch => "Touch",
            .joystick => "Joystick",
        };
    }
};

// Key codes (common subset)
pub const KeyCode = enum(u32) {
    unknown = 0,

    // Letters
    a = 4,
    b = 5,
    c = 6,
    d = 7,
    e = 8,
    f = 9,
    g = 10,
    h = 11,
    i = 12,
    j = 13,
    k = 14,
    l = 15,
    m = 16,
    n = 17,
    o = 18,
    p = 19,
    q = 20,
    r = 21,
    s = 22,
    t = 23,
    u = 24,
    v = 25,
    w = 26,
    x = 27,
    y = 28,
    z = 29,

    // Numbers
    @"1" = 30,
    @"2" = 31,
    @"3" = 32,
    @"4" = 33,
    @"5" = 34,
    @"6" = 35,
    @"7" = 36,
    @"8" = 37,
    @"9" = 38,
    @"0" = 39,

    // Function keys
    f1 = 58,
    f2 = 59,
    f3 = 60,
    f4 = 61,
    f5 = 62,
    f6 = 63,
    f7 = 64,
    f8 = 65,
    f9 = 66,
    f10 = 67,
    f11 = 68,
    f12 = 69,

    // Special keys
    enter = 40,
    escape = 41,
    backspace = 42,
    tab = 43,
    space = 44,

    // Arrow keys
    right = 79,
    left = 80,
    down = 81,
    up = 82,

    // Modifiers
    left_ctrl = 224,
    left_shift = 225,
    left_alt = 226,
    left_gui = 227,
    right_ctrl = 228,
    right_shift = 229,
    right_alt = 230,
    right_gui = 231,
};

// Mouse button codes
pub const MouseButton = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
    x1 = 3,
    x2 = 4,
};

// Gamepad button codes
pub const GamepadButton = enum(u8) {
    a = 0,
    b = 1,
    x = 2,
    y = 3,
    left_bumper = 4,
    right_bumper = 5,
    back = 6,
    start = 7,
    guide = 8,
    left_stick = 9,
    right_stick = 10,
    dpad_up = 11,
    dpad_down = 12,
    dpad_left = 13,
    dpad_right = 14,
};

// Gamepad axis codes
pub const GamepadAxis = enum(u8) {
    left_x = 0,
    left_y = 1,
    right_x = 2,
    right_y = 3,
    left_trigger = 4,
    right_trigger = 5,
};

// Input system configuration (re-exported from InputSystem)
pub const InputSystemConfig = input.InputSystem.InputSystemConfig;

// Initialize input system
pub fn init(allocator: std.mem.Allocator, config: InputSystemConfig) !*InputSystem {
    try config.validate();
    return try InputSystem.init(allocator, config);
}

// Cleanup input system
pub fn deinit(input_system: *InputSystem) void {
    input_system.deinit();
}

test "input module" {
    std.testing.refAllDecls(@This());
}
