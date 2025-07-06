const swiftui = @import("swiftui.zig");
const std = @import("std");

// This file intentionally contains only a trivial example to keep compilation fast.

pub fn exampleRun(allocator: std.mem.Allocator) void {
    // Create a simple Text view and discard – placeholder for real example.
    var text_view = swiftui.text(allocator, "Hello, UI!");
    _ = text_view.view();
}
