// Root test file for graphics memory manager tests.
// Placed under src/graphics/ so relative imports stay within the module path on Zig 0.16.

comptime {
    _ = @import("memory/new/memory_manager_test.zig");
}


