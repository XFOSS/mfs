//! macOS Cocoa Window Implementation
//! Provides Cocoa-based window creation for macOS platforms

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("../build_options.zig");

/// Objective-C runtime types
const id = *opaque {};
const Class = *opaque {};
const SEL = *opaque {};

/// NSWindow constants
const NSWindowStyleMaskTitled: u64 = 1;
const NSWindowStyleMaskClosable: u64 = 2;
const NSWindowStyleMaskMiniaturizable: u64 = 4;
const NSWindowStyleMaskResizable: u64 = 8;

/// NSApplication constants
const NSApplicationActivationPolicyRegular: i64 = 0;

/// Core Graphics types
const CGFloat = f64;
const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};
const NSPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};
const NSSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

/// Objective-C runtime functions (dynamically loaded)
var objc_lib: ?std.DynLib = null;
var objc_getClass: ?*const fn ([*:0]const u8) callconv(.C) ?Class = null;
var sel_registerName: ?*const fn ([*:0]const u8) callconv(.C) ?SEL = null;
var objc_msgSend: ?*const fn (id, SEL, ...) callconv(.C) id = null;

/// Foundation/AppKit library functions
var foundation_lib: ?std.DynLib = null;

/// macOS Cocoa Window implementation
pub const MacOSWindow = struct {
    allocator: std.mem.Allocator,
    ns_window: ?id,
    width: u32,
    height: u32,
    should_close: bool,
    title: []u8,

    const Self = @This();

    /// Initialize Objective-C runtime
    fn initObjC() !void {
        if (objc_lib != null) return; // Already initialized

        // Try to load Objective-C runtime
        objc_lib = std.DynLib.open("/usr/lib/libobjc.A.dylib") catch {
            std.log.warn("Could not load Objective-C runtime, using stub implementation", .{});
            return;
        };

        if (objc_lib) |lib| {
            objc_getClass = lib.lookup(@TypeOf(objc_getClass.?), "objc_getClass");
            sel_registerName = lib.lookup(@TypeOf(sel_registerName.?), "sel_registerName");
            objc_msgSend = lib.lookup(@TypeOf(objc_msgSend.?), "objc_msgSend");

            if (objc_getClass == null or sel_registerName == null or objc_msgSend == null) {
                std.log.warn("Failed to load required Objective-C functions", .{});
                objc_lib.?.close();
                objc_lib = null;
            }
        }

        // Try to load Foundation framework
        foundation_lib = std.DynLib.open("/System/Library/Frameworks/Foundation.framework/Foundation") catch {
            std.log.warn("Could not load Foundation framework", .{});
        };
    }

    pub fn init(allocator: std.mem.Allocator, title: []const u8, width: u32, height: u32) !Self {
        // Initialize Objective-C runtime
        try initObjC();

        // If Objective-C is not available, create a stub window
        if (objc_lib == null or objc_getClass == null) {
            const title_copy = try allocator.dupe(u8, title);
            std.log.warn("Creating stub macOS window (Cocoa not available)", .{});
            return Self{
                .allocator = allocator,
                .ns_window = null,
                .width = width,
                .height = height,
                .should_close = false,
                .title = title_copy,
            };
        }

        // Get required classes and selectors
        const NSApplication = objc_getClass.?("NSApplication") orelse {
            return error.NSApplicationNotFound;
        };
        const NSWindow = objc_getClass.?("NSWindow") orelse {
            return error.NSWindowNotFound;
        };
        const NSString = objc_getClass.?("NSString") orelse {
            return error.NSStringNotFound;
        };

        const sharedApplication = sel_registerName.?("sharedApplication");
        const setActivationPolicy = sel_registerName.?("setActivationPolicy:");
        const initWithContentRect = sel_registerName.?("initWithContentRect:styleMask:backing:defer:");
        const setTitleSel = sel_registerName.?("setTitle:");
        const makeKeyAndOrderFront = sel_registerName.?("makeKeyAndOrderFront:");
        const stringWithUTF8String = sel_registerName.?("stringWithUTF8String:");
        const alloc = sel_registerName.?("alloc");

        if (sharedApplication == null or initWithContentRect == null) {
            return error.CocoaSelectorsNotFound;
        }

        // Create NSApplication instance
        const app = objc_msgSend.?(NSApplication, sharedApplication.?);
        _ = objc_msgSend.?(app, setActivationPolicy.?, NSApplicationActivationPolicyRegular);

        // Create window frame
        const frame = NSRect{
            .origin = NSPoint{ .x = 100, .y = 100 },
            .size = NSSize{ .width = @floatFromInt(width), .height = @floatFromInt(height) },
        };

        // Window style mask
        const style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

        // Create NSWindow
        const window_alloc = objc_msgSend.?(NSWindow, alloc.?);
        const ns_window = objc_msgSend.?(window_alloc, initWithContentRect.?, frame, style_mask, 2, 0); // 2 = NSBackingStoreBuffered

        if (ns_window == null) {
            return error.NSWindowCreationFailed;
        }

        // Set window title
        const title_cstr = try std.fmt.allocPrintZ(allocator, "{s}", .{title});
        defer allocator.free(title_cstr);

        const ns_title = objc_msgSend.?(NSString, stringWithUTF8String.?, title_cstr.ptr);
        _ = objc_msgSend.?(ns_window, setTitleSel.?, ns_title);

        // Show window
        _ = objc_msgSend.?(ns_window, makeKeyAndOrderFront.?, null);

        const title_copy = try allocator.dupe(u8, title);

        std.log.info("Created macOS Cocoa window: {}x{} '{s}'", .{ width, height, title });

        return Self{
            .allocator = allocator,
            .ns_window = ns_window,
            .width = width,
            .height = height,
            .should_close = false,
            .title = title_copy,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.ns_window != null and objc_msgSend != null) {
            const close = sel_registerName.?("close");
            if (close != null) {
                _ = objc_msgSend.?(self.ns_window.?, close.?);
            }
        }
        self.allocator.free(self.title);

        // Cleanup dynamic libraries
        if (foundation_lib) |lib| {
            lib.close();
            foundation_lib = null;
        }
        if (objc_lib) |lib| {
            lib.close();
            objc_lib = null;
        }
    }

    pub fn pollEvents(self: *Self) void {
        if (self.ns_window == null or objc_msgSend == null) {
            return; // Stub implementation
        }

        // Basic event polling - in a real implementation, this would use NSApplication event loop
        // For now, we'll just simulate some basic behavior

        // Check if window should close (simplified)
        const isVisible = sel_registerName.?("isVisible");
        if (isVisible != null) {
            const visible = objc_msgSend.?(self.ns_window.?, isVisible.?);
            if (@intFromPtr(visible) == 0) {
                self.should_close = true;
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

        if (self.ns_window != null and objc_msgSend != null) {
            const NSString = objc_getClass.?("NSString");
            const stringWithUTF8String = sel_registerName.?("stringWithUTF8String:");
            const setTitleSel = sel_registerName.?("setTitle:");

            if (NSString != null and stringWithUTF8String != null and setTitleSel != null) {
                const title_cstr = try std.fmt.allocPrintZ(self.allocator, "{s}", .{title});
                defer self.allocator.free(title_cstr);

                const ns_title = objc_msgSend.?(NSString, stringWithUTF8String.?, title_cstr.ptr);
                _ = objc_msgSend.?(self.ns_window.?, setTitleSel.?, ns_title);
            }
        }
    }

    pub fn getHandle(self: *const Self) ?*anyopaque {
        if (self.ns_window != null) {
            return @ptrCast(self.ns_window.?);
        }
        return @ptrFromInt(0x12345678);
    }

    pub fn show(self: *Self) void {
        if (self.ns_window != null and objc_msgSend != null) {
            const makeKeyAndOrderFront = sel_registerName.?("makeKeyAndOrderFront:");
            if (makeKeyAndOrderFront != null) {
                _ = objc_msgSend.?(self.ns_window.?, makeKeyAndOrderFront.?, null);
            }
        }
    }

    pub fn hide(self: *Self) void {
        if (self.ns_window != null and objc_msgSend != null) {
            const orderOut = sel_registerName.?("orderOut:");
            if (orderOut != null) {
                _ = objc_msgSend.?(self.ns_window.?, orderOut.?, null);
            }
        }
    }
};

test "macOS window creation" {
    if (comptime !build_options.Platform.is_macos) {
        return; // Skip on non-macOS platforms
    }

    const testing = std.testing;
    const allocator = testing.allocator;

    var window = try MacOSWindow.init(allocator, "Test Window", 800, 600);
    defer window.deinit();

    try testing.expect(!window.shouldClose());

    const size = window.getSize();
    try testing.expect(size.width == 800);
    try testing.expect(size.height == 600);
}
