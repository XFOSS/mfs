const std = @import("std");
const perf_monitor_mod = @import("../system/perf_monitor.zig");

/// Simple text-based heads-up display that prints high-level performance
/// numbers every time `draw()` is invoked. A proper implementation would hook
/// into the renderer and submit vertices/textures – for now logging is enough
/// to validate the API surface.
pub const PerfOverlay = struct {
    allocator: std.mem.Allocator,
    monitor: *perf_monitor_mod.PerformanceMonitor,

    pub fn init(allocator: std.mem.Allocator, monitor: *perf_monitor_mod.PerformanceMonitor) PerfOverlay {
        return .{ .allocator = allocator, .monitor = monitor };
    }

    pub fn deinit(self: *PerfOverlay) void {
        _ = self; // Nothing to free – placeholder for future GPU buffers
    }

    pub fn draw(self: *PerfOverlay) void {
        const stats = self.monitor.getStats();
        std.log.info("[HUD] FPS {d:.1} | Mem {d} MB | CPU {d:.1}% | GPU {d:.1}%", .{
            stats.average_fps,
            stats.memory_usage_mb,
            stats.cpu_usage_percent,
            stats.gpu_usage_percent,
        });
    }
};
