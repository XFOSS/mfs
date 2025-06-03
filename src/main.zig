//! Main entry point for the MFS engine
//! @thread-safe Thread safety is managed by the bin_main module
//! @symbol Public application entry point

const bin_main = @import("bin/main.zig");

/// Main application entry point
/// @thread-safe Thread-safe application initialization
/// @symbol Public entry point
pub fn main() !void {
    return bin_main.main();
}

/// Test entry point - used for unit testing
/// @thread-safe Thread-safe test initialization
/// @symbol Public test entry point
test {
    // Import and run all tests
    _ = @import("bin/main.zig");
    _ = @import("graphics/backend_manager.zig");
    _ = @import("platform/platform.zig");
    _ = @import("system/memory.zig");
}
