//! Linux X11 Window Implementation
//! Provides X11-based window creation for Linux platforms

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("../build_options.zig");

/// X11 Display handle
const Display = *opaque {};
/// X11 Window handle
const Window = u64;
/// X11 Visual info
const Visual = *opaque {};
/// X11 Colormap
const Colormap = u64;

/// X11 Constants
const CWBackPixel = 2;
const CWColormap = 8192;
const CWEventMask = 2048;
const ExposureMask = 32768;
const KeyPressMask = 1;
const ButtonPressMask = 4;
const StructureNotifyMask = 131072;

/// X11 Event types
const Expose = 12;
const KeyPress = 2;
const ButtonPress = 4;
const DestroyNotify = 17;
const ClientMessage = 33;

/// X11 Event structure (simplified)
const XEvent = extern struct {
    type: i32,
    data: [24]u8, // Simplified event data
};

/// X11 Window attributes
const XSetWindowAttributes = extern struct {
    background_pixmap: u64 = 0,
    background_pixel: u64 = 0,
    border_pixmap: u64 = 0,
    border_pixel: u64 = 0,
    bit_gravity: i32 = 0,
    win_gravity: i32 = 0,
    backing_store: i32 = 0,
    backing_planes: u64 = 0,
    backing_pixel: u64 = 0,
    save_under: i32 = 0,
    event_mask: i64 = 0,
    do_not_propagate_mask: i64 = 0,
    override_redirect: i32 = 0,
    colormap: Colormap = 0,
    cursor: u64 = 0,
};

/// X11 function declarations (dynamically loaded)
var x11_lib: ?std.DynLib = null;
var XOpenDisplay: ?*const fn (?[*:0]const u8) callconv(.C) ?Display = null;
var XCloseDisplay: ?*const fn (Display) callconv(.C) i32 = null;
var XCreateWindow: ?*const fn (Display, Window, i32, i32, u32, u32, u32, i32, u32, ?Visual, u64, ?*XSetWindowAttributes) callconv(.C) Window = null;
var XDestroyWindow: ?*const fn (Display, Window) callconv(.C) i32 = null;
var XMapWindow: ?*const fn (Display, Window) callconv(.C) i32 = null;
var XUnmapWindow: ?*const fn (Display, Window) callconv(.C) i32 = null;
var XNextEvent: ?*const fn (Display, *XEvent) callconv(.C) i32 = null;
var XPending: ?*const fn (Display) callconv(.C) i32 = null;
var XDefaultRootWindow: ?*const fn (Display) callconv(.C) Window = null;
var XStoreName: ?*const fn (Display, Window, [*:0]const u8) callconv(.C) i32 = null;

/// Linux X11 Window implementation
pub const LinuxWindow = struct {
    allocator: std.mem.Allocator,
    display: ?Display,
    window: Window,
    width: u32,
    height: u32,
    should_close: bool,
    title: []u8,

    const Self = @This();

    /// Initialize X11 library
    fn initX11() !void {
        if (x11_lib != null) return; // Already initialized

        // Try to load X11 library
        x11_lib = std.DynLib.open("libX11.so.6") catch
            std.DynLib.open("libX11.so") catch {
            std.log.warn("Could not load X11 library, using stub implementation", .{});
            return;
        };

        if (x11_lib) |lib| {
            // Load required X11 functions
            XOpenDisplay = lib.lookup(@TypeOf(XOpenDisplay.?), "XOpenDisplay");
            XCloseDisplay = lib.lookup(@TypeOf(XCloseDisplay.?), "XCloseDisplay");
            XCreateWindow = lib.lookup(@TypeOf(XCreateWindow.?), "XCreateWindow");
            XDestroyWindow = lib.lookup(@TypeOf(XDestroyWindow.?), "XDestroyWindow");
            XMapWindow = lib.lookup(@TypeOf(XMapWindow.?), "XMapWindow");
            XUnmapWindow = lib.lookup(@TypeOf(XUnmapWindow.?), "XUnmapWindow");
            XNextEvent = lib.lookup(@TypeOf(XNextEvent.?), "XNextEvent");
            XPending = lib.lookup(@TypeOf(XPending.?), "XPending");
            XDefaultRootWindow = lib.lookup(@TypeOf(XDefaultRootWindow.?), "XDefaultRootWindow");
            XStoreName = lib.lookup(@TypeOf(XStoreName.?), "XStoreName");

            if (XOpenDisplay == null or XCreateWindow == null) {
                std.log.warn("Failed to load required X11 functions", .{});
                x11_lib.?.close();
                x11_lib = null;
            }
        }
    }

    pub fn init(allocator: std.mem.Allocator, title: []const u8, width: u32, height: u32) !Self {
        // Initialize X11 library
        try initX11();

        // If X11 is not available, create a stub window
        if (x11_lib == null or XOpenDisplay == null) {
            const title_copy = try allocator.dupe(u8, title);
            std.log.warn("Creating stub Linux window (X11 not available)", .{});
            return Self{
                .allocator = allocator,
                .display = null,
                .window = 0x12345678, // Stub window ID
                .width = width,
                .height = height,
                .should_close = false,
                .title = title_copy,
            };
        }

        // Open X11 display
        const display = XOpenDisplay.?(null) orelse {
            return error.X11DisplayFailed;
        };

        // Get root window
        const root = XDefaultRootWindow.?(display);

        // Set up window attributes
        var attributes = XSetWindowAttributes{
            .background_pixel = 0x000000, // Black background
            .event_mask = ExposureMask | KeyPressMask | ButtonPressMask | StructureNotifyMask,
        };

        // Create window
        const window = XCreateWindow.?(
            display,
            root,
            100,
            100, // x, y position
            width,
            height,
            1, // border width
            24, // depth
            1, // class (InputOutput)
            null, // visual
            CWBackPixel | CWEventMask,
            &attributes,
        );

        if (window == 0) {
            _ = XCloseDisplay.?(display);
            return error.X11WindowCreationFailed;
        }

        // Set window title
        const title_cstr = try std.fmt.allocPrintZ(allocator, "{s}", .{title});
        defer allocator.free(title_cstr);
        _ = XStoreName.?(display, window, title_cstr.ptr);

        // Show window
        _ = XMapWindow.?(display, window);

        const title_copy = try allocator.dupe(u8, title);

        std.log.info("Created Linux X11 window: {}x{} '{s}'", .{ width, height, title });

        return Self{
            .allocator = allocator,
            .display = display,
            .window = window,
            .width = width,
            .height = height,
            .should_close = false,
            .title = title_copy,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.display != null and XDestroyWindow != null) {
            _ = XDestroyWindow.?(self.display.?, self.window);
            _ = XCloseDisplay.?(self.display.?);
        }
        self.allocator.free(self.title);
    }

    pub fn pollEvents(self: *Self) void {
        if (self.display == null or XPending == null or XNextEvent == null) {
            return; // Stub implementation
        }

        // Process all pending events
        while (XPending.?(self.display.?) > 0) {
            var event: XEvent = undefined;
            _ = XNextEvent.?(self.display.?, &event);

            switch (event.type) {
                DestroyNotify => {
                    self.should_close = true;
                },
                Expose => {
                    // Window needs redraw
                },
                KeyPress => {
                    // Handle key press
                    if (event.data[8] == 9) { // ESC key (approximate)
                        self.should_close = true;
                    }
                },
                ButtonPress => {
                    // Handle mouse click
                },
                else => {
                    // Ignore other events
                },
            }
        }
    }

    pub fn shouldClose(self: *const Self) bool {
        return self.should_close;
    }

    pub fn getSize(self: *const Self) struct { width: u32, height: u32 } {
        return .{ .width = self.width, .height = self.height };
    }

    pub fn setTitle(self: *Self, title: []const u8) !void {
        self.allocator.free(self.title);
        self.title = try self.allocator.dupe(u8, title);

        if (self.display != null and XStoreName != null) {
            const title_cstr = try std.fmt.allocPrintZ(self.allocator, "{s}", .{title});
            defer self.allocator.free(title_cstr);
            _ = XStoreName.?(self.display.?, self.window, title_cstr.ptr);
        }
    }

    pub fn getHandle(self: *const Self) ?*anyopaque {
        if (self.display != null) {
            return @ptrFromInt(@intFromPtr(self.display));
        }
        return @ptrFromInt(self.window);
    }
};

test "Linux window creation" {
    if (comptime !build_options.Platform.is_linux) {
        return; // Skip on non-Linux platforms
    }

    const testing = std.testing;
    const allocator = testing.allocator;

    var window = try LinuxWindow.init(allocator, "Test Window", 800, 600);
    defer window.deinit();

    try testing.expect(!window.shouldClose());

    const size = window.getSize();
    try testing.expect(size.width == 800);
    try testing.expect(size.height == 600);
}
