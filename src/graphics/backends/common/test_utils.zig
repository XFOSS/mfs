const std = @import("std");
const common = @import("common.zig");

/// Utility for setting up and tearing down graphics backend tests
pub const TestContext = struct {
    allocator: std.mem.Allocator,
    /// Shared backend base instance with profiler and error logger
    base: common.BackendBase,
    /// Resource manager for tracking graphics resources
    resource_manager: common.ResourceManager,

    /// Initialize the test context
    pub fn setUp(allocator: std.mem.Allocator, debug_mode: bool) !TestContext {
        return TestContext{
            .allocator = allocator,
            .base = try common.BackendBase.init(allocator, debug_mode),
            .resource_manager = common.ResourceManager.init(allocator),
        };
    }

    /// Tear down the test context, cleaning up all resources
    pub fn tearDown(self: *TestContext) void {
        self.resource_manager.deinit();
        self.base.deinit();
    }
};
