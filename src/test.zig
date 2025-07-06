//! MFS Engine Test Suite
//! Main test file that imports and runs all tests

const std = @import("std");

// Import all modules that contain tests
const core = @import("core/mod.zig");
const math = @import("libs/math/mod.zig");
const engine = @import("engine/mod.zig");
const graphics = @import("graphics/mod.zig");
const physics = @import("physics/mod.zig");
const scene = @import("scene/mod.zig");
const audio = @import("audio/mod.zig");
const utils = @import("libs/utils/mod.zig");

test {
    // Run all tests by referencing the imported modules
    std.testing.refAllDecls(@This());
}
