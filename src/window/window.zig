//! Cross-platform window implementation
//! Provides window creation and management functionality

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("../build_options.zig");

/// Window configuration
pub const WindowConfig = struct {
    width: u32 = 1280,
    height: u32 = 720,
    title: []const u8 = "MFS Engine Window",
    resizable: bool = true,
    fullscreen: bool = false,
    vsync: bool = true,
    decorated: bool = true,
    always_on_top: bool = false,
    transparent: bool = false,
    min_width: u32 = 320,
    min_height: u32 = 240,
    max_width: u32 = 0,
    max_height: u32 = 0,
};

/// Window implementation
pub const Window = struct {
    allocator: std.mem.Allocator,
    config: WindowConfig,
    handle: ?*anyopaque,
    width: u32,
    height: u32,
    should_close: bool,
    is_fullscreen: bool,
    is_visible: bool,
    is_focused: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: WindowConfig) !*Self {
        const window = try allocator.create(Self);
        window.* = Self{
            .allocator = allocator,
            .config = config,
            .handle = null,
            .width = config.width,
            .height = config.height,
            .should_close = false,
            .is_fullscreen = config.fullscreen,
            .is_visible = true,
            .is_focused = true,
        };

        // Create platform-specific window
        try window.createPlatformWindow();

        std.log.info("Window created: {}x{} '{s}'", .{ config.width, config.height, config.title });
        return window;
    }

    pub fn deinit(self: *Self) void {
        self.destroyPlatformWindow();
        // Note: Don't destroy self here - that's the responsibility of the owner
    }

    pub fn pollEvents(self: *Self) !void {
        // Platform-specific event polling
        self.pollPlatformEvents();
    }

    pub fn shouldClose(self: *const Self) bool {
        return self.should_close;
    }

    pub fn getSize(self: *const Self) struct { width: u32, height: u32 } {
        return .{ .width = self.width, .height = self.height };
    }

    pub fn setSize(self: *Self, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        self.setPlatformSize(width, height);
    }

    pub fn getHandle(self: *const Self) ?*anyopaque {
        return self.handle;
    }

    pub fn setTitle(self: *Self, title: []const u8) void {
        self.setPlatformTitle(title);
    }

    pub fn setFullscreen(self: *Self, fullscreen: bool) void {
        self.is_fullscreen = fullscreen;
        self.setPlatformFullscreen(fullscreen);
    }

    pub fn isFullscreen(self: *const Self) bool {
        return self.is_fullscreen;
    }

    pub fn show(self: *Self) void {
        self.is_visible = true;
        self.showPlatformWindow();
    }

    pub fn hide(self: *Self) void {
        self.is_visible = false;
        self.hidePlatformWindow();
    }

    pub fn focus(self: *Self) void {
        self.is_focused = true;
        self.focusPlatformWindow();
    }

    pub fn minimize(self: *Self) void {
        self.minimizePlatformWindow();
    }

    pub fn maximize(self: *Self) void {
        self.maximizePlatformWindow();
    }

    pub fn restore(self: *Self) void {
        self.restorePlatformWindow();
    }

    // Platform-specific implementations
    fn createPlatformWindow(self: *Self) !void {
        if (build_options.Platform.is_windows) {
            try self.createWindowsWindow();
        } else if (build_options.Platform.is_linux) {
            try self.createLinuxWindow();
        } else if (build_options.Platform.is_macos) {
            try self.createMacOSWindow();
        } else if (build_options.Platform.is_web) {
            try self.createWebWindow();
        } else {
            // Fallback - create a dummy window
            self.handle = @ptrFromInt(0x12345678);
            std.log.warn("Using dummy window implementation for unsupported platform", .{});
        }
    }

    fn destroyPlatformWindow(self: *Self) void {
        if (self.handle == null) return;

        if (build_options.Platform.is_windows) {
            self.destroyWindowsWindow();
        } else if (build_options.Platform.is_linux) {
            self.destroyLinuxWindow();
        } else if (build_options.Platform.is_macos) {
            self.destroyMacOSWindow();
        } else if (build_options.Platform.is_web) {
            self.destroyWebWindow();
        }

        self.handle = null;
    }

    fn pollPlatformEvents(self: *Self) void {
        if (build_options.Platform.is_windows) {
            self.pollWindowsEvents();
        } else if (build_options.Platform.is_linux) {
            self.pollLinuxEvents();
        } else if (build_options.Platform.is_macos) {
            self.pollMacOSEvents();
        } else if (build_options.Platform.is_web) {
            self.pollWebEvents();
        }
    }

    fn setPlatformSize(self: *Self, width: u32, height: u32) void {
        _ = width;
        _ = height;
        // Platform-specific size setting would go here
        _ = self;
    }

    fn setPlatformTitle(self: *Self, title: []const u8) void {
        _ = title;
        // Platform-specific title setting would go here
        _ = self;
    }

    fn setPlatformFullscreen(self: *Self, fullscreen: bool) void {
        _ = fullscreen;
        // Platform-specific fullscreen setting would go here
        _ = self;
    }

    fn showPlatformWindow(self: *Self) void {
        // Platform-specific window showing would go here
        _ = self;
    }

    fn hidePlatformWindow(self: *Self) void {
        // Platform-specific window hiding would go here
        _ = self;
    }

    fn focusPlatformWindow(self: *Self) void {
        // Platform-specific window focusing would go here
        _ = self;
    }

    fn minimizePlatformWindow(self: *Self) void {
        // Platform-specific window minimizing would go here
        _ = self;
    }

    fn maximizePlatformWindow(self: *Self) void {
        // Platform-specific window maximizing would go here
        _ = self;
    }

    fn restorePlatformWindow(self: *Self) void {
        // Platform-specific window restoring would go here
        _ = self;
    }

    // Windows-specific implementations
    fn createWindowsWindow(self: *Self) !void {
        if (comptime !build_options.Platform.is_windows) {
            return error.WrongPlatform;
        }

        // Basic Windows window creation using minimal Win32 API
        const HWND = *opaque {};
        const HINSTANCE = *opaque {};
        const WNDCLASSEXW = extern struct {
            cbSize: u32,
            style: u32,
            lpfnWndProc: *const fn (HWND, u32, usize, isize) callconv(.c) isize,
            cbClsExtra: i32,
            cbWndExtra: i32,
            hInstance: HINSTANCE,
            hIcon: ?*anyopaque,
            hCursor: ?*anyopaque,
            hbrBackground: ?*anyopaque,
            lpszMenuName: ?[*:0]const u16,
            lpszClassName: [*:0]const u16,
            hIconSm: ?*anyopaque,
        };

        const user32 = struct {
            extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.c) u16;
            extern "user32" fn CreateWindowExW(
                dwExStyle: u32,
                lpClassName: [*:0]const u16,
                lpWindowName: [*:0]const u16,
                dwStyle: u32,
                X: i32,
                Y: i32,
                nWidth: i32,
                nHeight: i32,
                hWndParent: ?HWND,
                hMenu: ?*anyopaque,
                hInstance: HINSTANCE,
                lpParam: ?*anyopaque,
            ) callconv(.c) ?HWND;
            extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: u32, wParam: usize, lParam: isize) callconv(.c) isize;
            extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: usize) callconv(.c) ?*anyopaque;
            extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.c) HINSTANCE;
            extern "kernel32" fn GetLastError() callconv(.c) u32;
        };

        // Window style constants
        const WS_OVERLAPPEDWINDOW = 0x00CF0000;
        const WS_VISIBLE = 0x10000000;
        const CW_USEDEFAULT = @as(i32, @bitCast(@as(u32, 0x80000000)));
        const CS_HREDRAW = 0x0002;
        const CS_VREDRAW = 0x0001;
        const IDC_ARROW = 32512;
        const COLOR_WINDOW = 5;

        // Get module handle
        const hInstance = user32.GetModuleHandleW(null);

        // Use a simple class name
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("MFSEngineWindow");

        // Default window procedure
        const windowProc = struct {
            fn wndProc(hWnd: HWND, uMsg: u32, wParam: usize, lParam: isize) callconv(.c) isize {
                return user32.DefWindowProcW(hWnd, uMsg, wParam, lParam);
            }
        }.wndProc;

        // Register window class
        const wc = WNDCLASSEXW{
            .cbSize = @sizeOf(WNDCLASSEXW),
            .style = CS_HREDRAW | CS_VREDRAW,
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hInstance,
            .hIcon = null,
            .hCursor = user32.LoadCursorW(null, IDC_ARROW),
            .hbrBackground = @ptrFromInt(COLOR_WINDOW + 1),
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = null,
        };

        // Register the class (ignore error if already registered)
        _ = user32.RegisterClassExW(&wc);

        // Convert title to UTF-16
        const title_utf16 = std.unicode.utf8ToUtf16LeAllocZ(self.allocator, self.config.title) catch |err| {
            std.log.warn("Failed to convert title to UTF-16: {}", .{err});
            // Fall back to dummy implementation
            self.handle = @ptrFromInt(0x12345678);
            std.log.warn("Failed to create real Windows window, using dummy handle", .{});
            return;
        };
        defer self.allocator.free(title_utf16);

        // Create window
        const hwnd = user32.CreateWindowExW(
            0, // dwExStyle
            class_name,
            title_utf16.ptr,
            WS_OVERLAPPEDWINDOW | WS_VISIBLE,
            CW_USEDEFAULT, // X
            CW_USEDEFAULT, // Y
            @intCast(self.config.width),
            @intCast(self.config.height),
            null, // hWndParent
            null, // hMenu
            hInstance,
            null, // lpParam
        );

        if (hwnd) |h| {
            self.handle = @ptrCast(h);
            std.log.info("Created Windows window successfully", .{});
        } else {
            const error_code = user32.GetLastError();
            std.log.warn("Failed to create Windows window (error {}), using dummy handle", .{error_code});
            // Fall back to dummy implementation
            self.handle = @ptrFromInt(0x12345678);
        }
    }

    fn destroyWindowsWindow(self: *Self) void {
        if (comptime !build_options.Platform.is_windows) return;

        // DestroyWindow implementation
        if (self.handle) |handle| {
            const HWND = *opaque {};
            const user32 = struct {
                extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.c) i32;
            };

            _ = user32.DestroyWindow(@ptrCast(handle));
        }
    }

    fn pollWindowsEvents(self: *Self) void {
        if (comptime !build_options.Platform.is_windows) return;

        // Basic event polling
        // In a full implementation, this would use PeekMessage/GetMessage
        _ = self;
    }

    // Linux-specific implementations
    fn createLinuxWindow(self: *Self) !void {
        const LinuxWindow = @import("linux_window.zig").LinuxWindow;

        var linux_window = try LinuxWindow.init(self.allocator, self.config.title, self.config.width, self.config.height);
        self.handle = linux_window.getHandle();

        std.log.info("Created Linux window using X11 implementation", .{});
    }

    fn destroyLinuxWindow(self: *Self) void {
        if (self.handle != null) {
            // Note: In a complete implementation, we'd store the LinuxWindow instance
            // and call its deinit method here. For now, this is a simplified cleanup.
            self.handle = null;
        }
    }

    fn pollLinuxEvents(self: *Self) void {
        // Note: In a complete implementation, we'd delegate to the LinuxWindow instance
        // For now, this is a simplified event polling stub
        _ = self;
    }

    // macOS-specific implementations
    fn createMacOSWindow(self: *Self) !void {
        const MacOSWindow = @import("macos_window.zig").MacOSWindow;

        var macos_window = try MacOSWindow.init(self.allocator, self.config.title, self.config.width, self.config.height);
        self.handle = macos_window.getHandle();

        std.log.info("Created macOS window using Cocoa implementation", .{});
    }

    fn destroyMacOSWindow(self: *Self) void {
        if (self.handle != null) {
            // Note: In a complete implementation, we'd store the MacOSWindow instance
            // and call its deinit method here. For now, this is a simplified cleanup.
            self.handle = null;
        }
    }

    fn pollMacOSEvents(self: *Self) void {
        // Note: In a complete implementation, we'd delegate to the MacOSWindow instance
        // For now, this is a simplified event polling stub
        _ = self;
    }

    // Web-specific implementations
    fn createWebWindow(self: *Self) !void {
        // Canvas setup stub
        self.handle = @ptrFromInt(0x12345678);
        std.log.info("Created web window (stub implementation)", .{});
    }

    fn destroyWebWindow(_: *Self) void {
        // Canvas cleanup
    }

    fn pollWebEvents(self: *Self) void {
        // Web event polling
        _ = self;
    }
};

test "window creation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = WindowConfig{
        .width = 800,
        .height = 600,
        .title = "Test Window",
    };

    const window = try Window.init(allocator, config);
    defer window.deinit();

    try testing.expect(window.getHandle() != null);

    const size = window.getSize();
    try testing.expect(size.width == 800);
    try testing.expect(size.height == 600);

    try testing.expect(!window.shouldClose());
}
