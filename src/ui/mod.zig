//! MFS Engine - UI Module
//! Comprehensive user interface system with modern UI frameworks
//! Supports immediate mode GUI, retained mode GUI, and declarative UI patterns
//! @thread-safe UI operations should be performed on the main thread
//! @performance Optimized for smooth 60+ FPS UI rendering

const std = @import("std");
const builtin = @import("builtin");

// Core UI components
pub const ui = @import("ui.zig");
pub const core = @import("core.zig");
pub const framework = @import("framework.zig");
pub const unified_framework = @import("unified_framework.zig");
pub const modern = @import("modern.zig");

// UI backends
pub const backend = @import("backend/backend.zig");
pub const gpu_accelerated = @import("backend/gpu_accelerated.zig");

// Window management
pub const window = @import("window.zig");
pub const simple_window = @import("simple_window.zig");

// Color and styling
pub const color = @import("color.zig");
pub const color_bridge = @import("color_bridge.zig");

// UI frameworks
pub const swiftui = @import("swiftui.zig");
pub const swiftui_extensions = @import("swiftui_extensions.zig");
pub const view_modifiers = @import("view_modifiers.zig");
pub const ui_framework = @import("ui_framework.zig");
pub const uix = @import("uix.zig");

// Utilities
pub const utils = @import("libs/utils/utils.zig");
pub const worker = @import("worker.zig");
pub const perf_overlay = @import("perf_overlay.zig");

// Re-export main UI types
pub const UISystem = ui.UISystem;
pub const UIConfig = ui.UIConfig;
pub const Window = window.WindowManager; // WindowManager is the actual window type
pub const WindowManager = window.WindowManager;
pub const Color = color.Color;

// Window configuration for compatibility
pub const WindowConfig = struct {
    width: u32 = 800,
    height: u32 = 600,
    title: []const u8 = "MFS Engine",
    resizable: bool = true,
    fullscreen: bool = false,
    vsync: bool = true,
};

// UI rendering backends
pub const UIBackend = enum {
    software,
    opengl,
    vulkan,
    directx,
    metal,
    webgpu,

    pub fn isAvailable(self: UIBackend) bool {
        return switch (self) {
            .software => true,
            .opengl => true,
            .vulkan => true, // Will check actual availability at runtime
            .directx => builtin.os.tag == .windows,
            .metal => builtin.os.tag == .macos,
            .webgpu => builtin.os.tag == .wasi,
        };
    }

    pub fn getName(self: UIBackend) []const u8 {
        return switch (self) {
            .software => "Software",
            .opengl => "OpenGL",
            .vulkan => "Vulkan",
            .directx => "DirectX",
            .metal => "Metal",
            .webgpu => "WebGPU",
        };
    }
};

// UI system configuration
pub const UISystemConfig = struct {
    preferred_backend: ?UIBackend = null,
    enable_gpu_acceleration: bool = true,
    enable_high_dpi: bool = true,
    enable_animations: bool = true,
    enable_accessibility: bool = true,
    default_font_size: f32 = 14.0,
    ui_scale: f32 = 1.0,
    max_ui_elements: u32 = 10000,

    pub fn validate(self: UISystemConfig) !void {
        if (self.default_font_size < 6.0 or self.default_font_size > 72.0) {
            return error.InvalidParameter;
        }
        if (self.ui_scale < 0.5 or self.ui_scale > 4.0) {
            return error.InvalidParameter;
        }
        if (self.max_ui_elements == 0 or self.max_ui_elements > 100000) {
            return error.InvalidParameter;
        }
    }
};

// Initialize UI system
pub fn init(allocator: std.mem.Allocator, config: UISystemConfig) !*UISystem {
    try config.validate();
    return try UISystem.init(allocator, config);
}

// Cleanup UI system
pub fn deinit(ui_system: *UISystem) void {
    ui_system.deinit();
}

test "ui module" {
    std.testing.refAllDecls(@This());
}
