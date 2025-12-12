// Root test file for the new Vulkan backend tests.
// Placed under src/graphics/ so relative imports stay within the module path on Zig 0.16.

comptime {
    _ = @import("backends/vulkan/new/vulkan_backend_test.zig");
}


