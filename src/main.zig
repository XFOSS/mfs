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
