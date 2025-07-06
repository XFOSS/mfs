const std = @import("std");
const builtin = @import("builtin");
const capabilities = @import("../capabilities.zig");

// Web-specific platform implementation
pub const WebPlatform = struct {
    allocator: std.mem.Allocator,
    canvas_id: []const u8,
    context_type: ContextType,

    // WebGL context
    webgl_context: ?WebGLContext = null,

    // Input state
    input_state: InputState,

    // Performance monitoring
    performance_monitor: PerformanceMonitor,

    const Self = @This();

    pub const ContextType = enum {
        webgl,
        webgl2,
        webgpu,
        canvas2d,
    };

    pub const InitOptions = struct {
        canvas_id: []const u8 = "canvas",
        context_type: ContextType = .webgl2,
        enable_high_dpi: bool = true,
        enable_alpha: bool = false,
        enable_depth: bool = true,
        enable_stencil: bool = false,
        enable_antialias: bool = true,
        enable_premultiplied_alpha: bool = true,
        power_preference: enum { default, high_performance, low_power } = .high_performance,
    };

    pub fn init(allocator: std.mem.Allocator, options: InitOptions) !Self {
        // Verify we're running in a web environment
        if (builtin.target.os.tag != .freestanding) {
            return error.NotWebEnvironment;
        }

        var self = Self{
            .allocator = allocator,
            .canvas_id = try allocator.dupe(u8, options.canvas_id),
            .context_type = options.context_type,
            .input_state = InputState.init(),
            .performance_monitor = PerformanceMonitor.init(),
        };

        // Initialize graphics context
        try self.initGraphicsContext(options);

        // Set up input event listeners
        try self.setupInputHandlers();

        // Initialize performance monitoring
        self.performance_monitor.start();

        std.log.info("Web platform initialized with {s} context", .{@tagName(options.context_type)});

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.performance_monitor.stop();

        if (self.webgl_context) |*context| {
            context.deinit();
        }

        // Remove event listeners
        self.removeInputHandlers();

        self.allocator.free(self.canvas_id);
    }

    fn initGraphicsContext(self: *Self, options: InitOptions) !void {
        switch (options.context_type) {
            .webgl, .webgl2 => {
                self.webgl_context = try WebGLContext.init(
                    self.allocator,
                    self.canvas_id,
                    options.context_type == .webgl2,
                    .{
                        .alpha = options.enable_alpha,
                        .depth = options.enable_depth,
                        .stencil = options.enable_stencil,
                        .antialias = options.enable_antialias,
                        .premultiplied_alpha = options.enable_premultiplied_alpha,
                        .power_preference = options.power_preference,
                    },
                );
            },
            .webgpu => {
                // WebGPU support would be implemented here
                return error.WebGPUNotImplemented;
            },
            .canvas2d => {
                // 2D canvas support for software rendering
                return error.Canvas2DNotImplemented;
            },
        }
    }

    fn setupInputHandlers(self: *Self) !void {
        _ = self; // Will be used when input handlers are fully implemented

        // Set up JavaScript event handlers
        // This would use extern functions to communicate with JavaScript

        // Mouse events
        try addEventListener("mousedown", onMouseDown);
        try addEventListener("mouseup", onMouseUp);
        try addEventListener("mousemove", onMouseMove);
        try addEventListener("wheel", onWheel);

        // Keyboard events
        try addEventListener("keydown", onKeyDown);
        try addEventListener("keyup", onKeyUp);

        // Touch events for mobile
        try addEventListener("touchstart", onTouchStart);
        try addEventListener("touchend", onTouchEnd);
        try addEventListener("touchmove", onTouchMove);

        // Window events
        try addEventListener("resize", onResize);
        try addEventListener("beforeunload", onBeforeUnload);

        // Gamepad events
        try addEventListener("gamepadconnected", onGamepadConnected);
        try addEventListener("gamepaddisconnected", onGamepadDisconnected);
    }

    fn removeInputHandlers(self: *Self) void {
        _ = self; // Will be used when input handlers are fully implemented

        // Remove all event listeners
        removeEventListener("mousedown", onMouseDown);
        removeEventListener("mouseup", onMouseUp);
        removeEventListener("mousemove", onMouseMove);
        removeEventListener("wheel", onWheel);
        removeEventListener("keydown", onKeyDown);
        removeEventListener("keyup", onKeyUp);
        removeEventListener("touchstart", onTouchStart);
        removeEventListener("touchend", onTouchEnd);
        removeEventListener("touchmove", onTouchMove);
        removeEventListener("resize", onResize);
        removeEventListener("beforeunload", onBeforeUnload);
        removeEventListener("gamepadconnected", onGamepadConnected);
        removeEventListener("gamepaddisconnected", onGamepadDisconnected);
    }

    pub fn getCanvasSize(self: *Self) struct { width: u32, height: u32 } {
        return js_getCanvasSize(self.canvas_id.ptr, self.canvas_id.len);
    }

    pub fn setCanvasSize(self: *Self, width: u32, height: u32) !void {
        js_setCanvasSize(self.canvas_id.ptr, self.canvas_id.len, width, height);

        // Update WebGL viewport if needed
        if (self.webgl_context) |*context| {
            context.setViewport(0, 0, @intCast(width), @intCast(height));
        }
    }

    pub fn requestAnimationFrame(self: *Self, callback: *const fn () void) void {
        _ = self;
        js_requestAnimationFrame(@intFromPtr(callback));
    }

    pub fn getDevicePixelRatio(self: *Self) f32 {
        _ = self;
        return js_getDevicePixelRatio();
    }

    pub fn isFullscreen(self: *Self) bool {
        _ = self;
        return js_isFullscreen();
    }

    pub fn requestFullscreen(self: *Self) !void {
        const result = js_requestFullscreen(self.canvas_id.ptr, self.canvas_id.len);
        if (!result) {
            return error.FullscreenRequestFailed;
        }
    }

    pub fn exitFullscreen(self: *Self) void {
        _ = self;
        js_exitFullscreen();
    }

    pub fn getInputState(self: *Self) *const InputState {
        return &self.input_state;
    }

    pub fn update(self: *Self) void {
        // Update input state
        self.input_state.update();

        // Update performance monitoring
        self.performance_monitor.update();

        // Poll gamepad state
        self.updateGamepadState();
    }

    fn updateGamepadState(self: *Self) void {
        const gamepad_count = js_getGamepadCount();
        var i: u32 = 0;

        while (i < gamepad_count and i < InputState.MAX_GAMEPADS) : (i += 1) {
            if (js_isGamepadConnected(i)) {
                const gamepad_state = js_getGamepadState(i);
                self.input_state.gamepads[i] = .{
                    .connected = true,
                    .buttons = gamepad_state.buttons,
                    .axes = gamepad_state.axes,
                };
            } else {
                self.input_state.gamepads[i].connected = false;
            }
        }
    }

    // File system operations for web
    pub fn loadFile(self: *Self, path: []const u8) ![]u8 {
        const file_data = js_loadFile(path.ptr, path.len);
        if (file_data.ptr == null) {
            return error.FileNotFound;
        }

        const data = try self.allocator.alloc(u8, file_data.len);
        @memcpy(data, file_data.ptr.?[0..file_data.len]);

        js_freeFileData(file_data.ptr.?);
        return data;
    }

    pub fn saveFile(self: *Self, path: []const u8, data: []const u8) !void {
        _ = self;
        const result = js_saveFile(path.ptr, path.len, data.ptr, data.len);
        if (!result) {
            return error.FileSaveFailed;
        }
    }

    // Local storage operations
    pub fn getLocalStorage(self: *Self, key: []const u8) ?[]u8 {
        const value = js_getLocalStorage(key.ptr, key.len);
        if (value.ptr == null) return null;

        const data = self.allocator.alloc(u8, value.len) catch return null;
        @memcpy(data, value.ptr.?[0..value.len]);

        js_freeString(value.ptr.?);
        return data;
    }

    pub fn setLocalStorage(self: *Self, key: []const u8, value: []const u8) !void {
        _ = self;
        const result = js_setLocalStorage(key.ptr, key.len, value.ptr, value.len);
        if (!result) {
            return error.LocalStorageSetFailed;
        }
    }

    pub fn removeLocalStorage(self: *Self, key: []const u8) void {
        _ = self;
        js_removeLocalStorage(key.ptr, key.len);
    }

    // Audio context for web audio
    pub fn createAudioContext(self: *Self) !WebAudioContext {
        _ = self;
        const context_id = js_createAudioContext();
        if (context_id == 0) {
            return error.AudioContextCreationFailed;
        }

        return WebAudioContext{ .id = context_id };
    }

    // WebWorker support for threading
    pub fn createWorker(self: *Self, script_url: []const u8) !WebWorker {
        _ = self;
        const worker_id = js_createWorker(script_url.ptr, script_url.len);
        if (worker_id == 0) {
            return error.WorkerCreationFailed;
        }

        return WebWorker{ .id = worker_id };
    }

    // Performance monitoring
    pub fn getPerformanceStats(self: *Self) PerformanceStats {
        return self.performance_monitor.getStats();
    }
};

// WebGL context wrapper
const WebGLContext = struct {
    context_id: u32,
    is_webgl2: bool,

    const Self = @This();

    pub const ContextOptions = struct {
        alpha: bool = false,
        depth: bool = true,
        stencil: bool = false,
        antialias: bool = true,
        premultiplied_alpha: bool = true,
        power_preference: WebPlatform.InitOptions.power_preference = .high_performance,
    };

    pub fn init(allocator: std.mem.Allocator, canvas_id: []const u8, webgl2: bool, options: ContextOptions) !Self {
        _ = allocator;

        const context_id = js_createWebGLContext(
            canvas_id.ptr,
            canvas_id.len,
            webgl2,
            options.alpha,
            options.depth,
            options.stencil,
            options.antialias,
            options.premultiplied_alpha,
            @intFromEnum(options.power_preference),
        );

        if (context_id == 0) {
            return error.WebGLContextCreationFailed;
        }

        return Self{
            .context_id = context_id,
            .is_webgl2 = webgl2,
        };
    }

    pub fn deinit(self: *Self) void {
        js_destroyWebGLContext(self.context_id);
    }

    pub fn makeCurrent(self: *Self) void {
        js_makeWebGLContextCurrent(self.context_id);
    }

    pub fn swapBuffers(self: *Self) void {
        js_swapWebGLBuffers(self.context_id);
    }

    pub fn setViewport(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        js_webglViewport(self.context_id, x, y, width, height);
    }

    pub fn clear(self: *Self, mask: u32) void {
        js_webglClear(self.context_id, mask);
    }

    pub fn getExtensions(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        const extensions_count = js_getWebGLExtensionCount(self.context_id);
        var extensions = try allocator.alloc([]const u8, extensions_count);

        var i: u32 = 0;
        while (i < extensions_count) : (i += 1) {
            const ext_name = js_getWebGLExtensionName(self.context_id, i);
            extensions[i] = try allocator.dupe(u8, ext_name.ptr[0..ext_name.len]);
            js_freeString(ext_name.ptr);
        }

        return extensions;
    }
};

// Input state management
const InputState = struct {
    // Mouse state
    mouse_x: f32 = 0.0,
    mouse_y: f32 = 0.0,
    mouse_buttons: u8 = 0,
    wheel_delta: f32 = 0.0,

    // Keyboard state
    keys: [256]bool = [_]bool{false} ** 256,

    // Touch state
    touches: [MAX_TOUCHES]Touch = [_]Touch{Touch{}} ** MAX_TOUCHES,
    touch_count: u32 = 0,

    // Gamepad state
    gamepads: [MAX_GAMEPADS]Gamepad = [_]Gamepad{Gamepad{}} ** MAX_GAMEPADS,

    const MAX_TOUCHES = 10;
    const MAX_GAMEPADS = 4;

    const Touch = struct {
        id: u32 = 0,
        x: f32 = 0.0,
        y: f32 = 0.0,
        active: bool = false,
    };

    const Gamepad = struct {
        connected: bool = false,
        buttons: u32 = 0,
        axes: [4]f32 = [_]f32{0.0} ** 4,
    };

    pub fn init() InputState {
        return InputState{};
    }

    pub fn update(self: *InputState) void {
        // Reset frame-specific state
        self.wheel_delta = 0.0;
    }

    pub fn isKeyPressed(self: *const InputState, key: u8) bool {
        return self.keys[key];
    }

    pub fn isMouseButtonPressed(self: *const InputState, button: u8) bool {
        return (self.mouse_buttons & (@as(u8, 1) << button)) != 0;
    }

    pub fn getMousePosition(self: *const InputState) struct { x: f32, y: f32 } {
        return .{ .x = self.mouse_x, .y = self.mouse_y };
    }

    pub fn getTouchCount(self: *const InputState) u32 {
        return self.touch_count;
    }

    pub fn getTouch(self: *const InputState, index: u32) ?Touch {
        if (index >= self.touch_count) return null;
        return self.touches[index];
    }

    pub fn isGamepadConnected(self: *const InputState, index: u32) bool {
        if (index >= MAX_GAMEPADS) return false;
        return self.gamepads[index].connected;
    }

    pub fn getGamepad(self: *const InputState, index: u32) ?Gamepad {
        if (index >= MAX_GAMEPADS) return null;
        if (!self.gamepads[index].connected) return null;
        return self.gamepads[index];
    }
};

// Performance monitoring
const PerformanceMonitor = struct {
    start_time: f64 = 0.0,
    frame_count: u64 = 0,
    last_fps_time: f64 = 0.0,
    current_fps: f32 = 0.0,

    pub fn init() PerformanceMonitor {
        return PerformanceMonitor{};
    }

    pub fn start(self: *PerformanceMonitor) void {
        self.start_time = js_getPerformanceNow();
        self.last_fps_time = self.start_time;
    }

    pub fn stop(self: *PerformanceMonitor) void {
        _ = self;
        // Cleanup if needed
    }

    pub fn update(self: *PerformanceMonitor) void {
        self.frame_count += 1;

        const current_time = js_getPerformanceNow();
        const fps_delta = current_time - self.last_fps_time;

        if (fps_delta >= 1000.0) { // Update FPS every second
            self.current_fps = @as(f32, @floatFromInt(self.frame_count)) / @as(f32, @floatCast(fps_delta / 1000.0));
            self.frame_count = 0;
            self.last_fps_time = current_time;
        }
    }

    pub fn getStats(self: *const PerformanceMonitor) PerformanceStats {
        return PerformanceStats{
            .fps = self.current_fps,
            .frame_count = self.frame_count,
            .uptime_ms = js_getPerformanceNow() - self.start_time,
            .memory_used = js_getMemoryUsage(),
        };
    }
};

const PerformanceStats = struct {
    fps: f32,
    frame_count: u64,
    uptime_ms: f64,
    memory_used: u64,
};

// Web Audio context
const WebAudioContext = struct {
    id: u32,

    pub fn createOscillator(self: *const WebAudioContext, frequency: f32) !WebAudioNode {
        const node_id = js_createOscillator(self.id, frequency);
        if (node_id == 0) return error.OscillatorCreationFailed;
        return WebAudioNode{ .id = node_id };
    }

    pub fn createGain(self: *const WebAudioContext, gain: f32) !WebAudioNode {
        const node_id = js_createGain(self.id, gain);
        if (node_id == 0) return error.GainNodeCreationFailed;
        return WebAudioNode{ .id = node_id };
    }

    pub fn deinit(self: *const WebAudioContext) void {
        js_destroyAudioContext(self.id);
    }
};

const WebAudioNode = struct {
    id: u32,

    pub fn connect(self: *const WebAudioNode, destination: WebAudioNode) void {
        js_connectAudioNodes(self.id, destination.id);
    }

    pub fn start(self: *const WebAudioNode) void {
        js_startAudioNode(self.id);
    }

    pub fn stop(self: *const WebAudioNode) void {
        js_stopAudioNode(self.id);
    }

    pub fn deinit(self: *const WebAudioNode) void {
        js_destroyAudioNode(self.id);
    }
};

// Web Worker
const WebWorker = struct {
    id: u32,

    pub fn postMessage(self: *const WebWorker, data: []const u8) void {
        js_workerPostMessage(self.id, data.ptr, data.len);
    }

    pub fn terminate(self: *const WebWorker) void {
        js_terminateWorker(self.id);
    }

    pub fn deinit(self: *const WebWorker) void {
        self.terminate();
    }
};

// Event callback implementations
fn onMouseDown() callconv(.C) void {
    // Implementation would update global input state
}

fn onMouseUp() callconv(.C) void {
    // Implementation would update global input state
}

fn onMouseMove() callconv(.C) void {
    // Implementation would update global input state
}

fn onWheel() callconv(.C) void {
    // Implementation would update global input state
}

fn onKeyDown() callconv(.C) void {
    // Implementation would update global input state
}

fn onKeyUp() callconv(.C) void {
    // Implementation would update global input state
}

fn onTouchStart() callconv(.C) void {
    // Implementation would update global input state
}

fn onTouchEnd() callconv(.C) void {
    // Implementation would update global input state
}

fn onTouchMove() callconv(.C) void {
    // Implementation would update global input state
}

fn onResize() callconv(.C) void {
    // Implementation would handle window resize
}

fn onBeforeUnload() callconv(.C) void {
    // Implementation would handle cleanup before page unload
}

fn onGamepadConnected() callconv(.C) void {
    // Implementation would handle gamepad connection
}

fn onGamepadDisconnected() callconv(.C) void {
    // Implementation would handle gamepad disconnection
}

// Event handling utilities
fn addEventListener(event_type: []const u8, callback: *const fn () callconv(.C) void) !void {
    const result = js_addEventListener(event_type.ptr, event_type.len, @intFromPtr(callback));
    if (!result) {
        return error.EventListenerAddFailed;
    }
}

fn removeEventListener(event_type: []const u8, callback: *const fn () callconv(.C) void) void {
    js_removeEventListener(event_type.ptr, event_type.len, @intFromPtr(callback));
}

// External JavaScript function declarations
extern fn js_getCanvasSize(canvas_id: [*]const u8, canvas_id_len: usize) struct { width: u32, height: u32 };
extern fn js_setCanvasSize(canvas_id: [*]const u8, canvas_id_len: usize, width: u32, height: u32) void;
extern fn js_requestAnimationFrame(callback: usize) void;
extern fn js_getDevicePixelRatio() f32;
extern fn js_isFullscreen() bool;
extern fn js_requestFullscreen(canvas_id: [*]const u8, canvas_id_len: usize) bool;
extern fn js_exitFullscreen() void;

extern fn js_createWebGLContext(canvas_id: [*]const u8, canvas_id_len: usize, webgl2: bool, alpha: bool, depth: bool, stencil: bool, antialias: bool, premultiplied_alpha: bool, power_preference: u32) u32;
extern fn js_destroyWebGLContext(context_id: u32) void;
extern fn js_makeWebGLContextCurrent(context_id: u32) void;
extern fn js_swapWebGLBuffers(context_id: u32) void;
extern fn js_webglViewport(context_id: u32, x: i32, y: i32, width: i32, height: i32) void;
extern fn js_webglClear(context_id: u32, mask: u32) void;
extern fn js_getWebGLExtensionCount(context_id: u32) u32;
extern fn js_getWebGLExtensionName(context_id: u32, index: u32) struct { ptr: [*]const u8, len: usize };

extern fn js_addEventListener(event_type: [*]const u8, event_type_len: usize, callback: usize) bool;
extern fn js_removeEventListener(event_type: [*]const u8, event_type_len: usize, callback: usize) void;

extern fn js_getGamepadCount() u32;
extern fn js_isGamepadConnected(index: u32) bool;
extern fn js_getGamepadState(index: u32) struct { buttons: u32, axes: [4]f32 };

extern fn js_loadFile(path: [*]const u8, path_len: usize) struct { ptr: ?[*]const u8, len: usize };
extern fn js_saveFile(path: [*]const u8, path_len: usize, data: [*]const u8, data_len: usize) bool;
extern fn js_freeFileData(ptr: [*]const u8) void;

extern fn js_getLocalStorage(key: [*]const u8, key_len: usize) struct { ptr: ?[*]const u8, len: usize };
extern fn js_setLocalStorage(key: [*]const u8, key_len: usize, value: [*]const u8, value_len: usize) bool;
extern fn js_removeLocalStorage(key: [*]const u8, key_len: usize) void;
extern fn js_freeString(ptr: [*]const u8) void;

extern fn js_createAudioContext() u32;
extern fn js_destroyAudioContext(context_id: u32) void;
extern fn js_createOscillator(context_id: u32, frequency: f32) u32;
extern fn js_createGain(context_id: u32, gain: f32) u32;
extern fn js_connectAudioNodes(source_id: u32, destination_id: u32) void;
extern fn js_startAudioNode(node_id: u32) void;
extern fn js_stopAudioNode(node_id: u32) void;
extern fn js_destroyAudioNode(node_id: u32) void;

extern fn js_createWorker(script_url: [*]const u8, script_url_len: usize) u32;
extern fn js_terminateWorker(worker_id: u32) void;
extern fn js_workerPostMessage(worker_id: u32, data: [*]const u8, data_len: usize) void;

extern fn js_getPerformanceNow() f64;
extern fn js_getMemoryUsage() u64;

// Export functions for JavaScript to call
export fn zig_onMouseEvent(event_type: u32, x: f32, y: f32, button: u32) void {
    // Handle mouse events from JavaScript
    _ = event_type;
    _ = x;
    _ = y;
    _ = button;
}

export fn zig_onKeyEvent(event_type: u32, key_code: u32) void {
    // Handle keyboard events from JavaScript
    _ = event_type;
    _ = key_code;
}

export fn zig_onTouchEvent(event_type: u32, touch_id: u32, x: f32, y: f32) void {
    // Handle touch events from JavaScript
    _ = event_type;
    _ = touch_id;
    _ = x;
    _ = y;
}

export fn zig_onResize(width: u32, height: u32) void {
    // Handle window resize from JavaScript
    _ = width;
    _ = height;
}

// Test functions
test "web platform initialization" {
    if (builtin.target.os.tag != .freestanding) {
        // Skip test if not in web environment
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = WebPlatform.InitOptions{
        .canvas_id = "test-canvas",
        .context_type = .webgl2,
    };

    var platform = try WebPlatform.init(allocator, options);
    defer platform.deinit();

    // Test basic functionality
    const size = platform.getCanvasSize();
    try std.testing.expect(size.width > 0);
    try std.testing.expect(size.height > 0);
}
