//! Platform-level Window wrapper
//! Provides convenient re-export of the cross-platform window system that lives
//! in the top-level `window` package.  Engine code can now simply
//! `@import("platform/window.zig")` to gain access without needing to know the
//! exact path.

const std = @import("std");

// We simply re-export the public API from `window.mod` so that the symbols are
// reachable through the platform namespace as well.
const win_pkg = @import("../window/mod.zig");

pub const Config = win_pkg.Config;
pub const WindowEvent = win_pkg.WindowEvent;

pub const WindowSystem = win_pkg.WindowSystem;

pub const Window = win_pkg.Window;

/// Initialize a new window system with the supplied configuration.
/// Convenience that forwards to `window.WindowSystem.init`.
pub fn init(allocator: std.mem.Allocator, cfg: Config) !*WindowSystem {
    return try WindowSystem.init(allocator, cfg);
}

/// Convenience de-initializer.
pub fn deinit(ws: *WindowSystem) void {
    ws.deinit();
}

/// Shorthand for the most common use-case – create a window using the default
/// configuration (1280×720 titled "MFS Engine Application").
pub fn createDefault(allocator: std.mem.Allocator) !*WindowSystem {
    const default_cfg = Config{};
    return try init(allocator, default_cfg);
}

test "platform window wrapper compiles" {
    std.testing.refAllDecls(@This());
}