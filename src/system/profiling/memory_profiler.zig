const std = @import("std");
const Profiler = @import("profiler.zig").Profiler;
const build_options = @import("build_options");
const TrackedAllocator = @import("profiler.zig").TrackedAllocator;

/// Global flag to enable or disable memory profiling
pub var enable_memory_profiling: bool = true;

/// Memory profiling categories
pub const MemoryCategory = enum {
    General,
    Graphics,
    Audio,
    Physics,
    Resources,
    Network,
    UI,
    Scene,
    AI,

    pub fn toString(self: MemoryCategory) []const u8 {
        return switch (self) {
            .General => "General",
            .Graphics => "Graphics",
            .Audio => "Audio",
            .Physics => "Physics",
            .Resources => "Resources",
            .Network => "Network",
            .UI => "UI",
            .Scene => "Scene",
            .AI => "AI",
        };
    }
};

/// Create a tracked allocator for a specific subsystem
pub fn createTrackedAllocator(parent_allocator: std.mem.Allocator, category: MemoryCategory) TrackedAllocator {
    return TrackedAllocator.init(parent_allocator, category.toString());
}

/// Create a tracked general-purpose allocator
pub fn createTrackedGPA() !TrackedGPA {
    return TrackedGPA.init(std.heap.page_allocator, .General);
}

/// A tracked general-purpose allocator that reports memory usage to the profiler
pub const TrackedGPA = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    tracked: TrackedAllocator,

    pub fn init(backing_allocator: std.mem.Allocator, category: MemoryCategory) !TrackedGPA {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        var tracked = TrackedAllocator.init(gpa.allocator(), category.toString());

        return TrackedGPA{
            .gpa = gpa,
            .tracked = tracked,
        };
    }

    pub fn allocator(self: *TrackedGPA) std.mem.Allocator {
        return self.tracked.allocator();
    }

    pub fn deinit(self: *TrackedGPA) bool {
        // Return leak detection status
        return self.gpa.deinit();
    }
};

/// Track a memory allocation
pub fn trackAlloc(ptr: ?*anyopaque, size: usize, category: MemoryCategory) void {
    if (!enable_memory_profiling) return;

    Profiler.trackAllocation(ptr, size, category.toString(), null, null);
}

/// Track a memory deallocation
pub fn trackFree(ptr: ?*anyopaque) void {
    if (!enable_memory_profiling) return;

    Profiler.trackDeallocation(ptr);
}

/// Get current memory statistics
pub fn getMemoryStats() struct {
    total_bytes: usize,
    allocation_count: usize,
    live_allocation_count: usize,
} {
    return Profiler.getMemoryStats();
}

/// Check for memory leaks - returns true if leaks detected
pub fn checkForLeaks() bool {
    const stats = getMemoryStats();
    return stats.live_allocation_count > 0;
}

/// Save memory profile to a file
pub fn saveMemoryProfile(path: []const u8) !void {
    return Profiler.saveToFile(path);
}

/// Print memory stats to console
pub fn printMemoryStats() void {
    const stats = getMemoryStats();
    std.debug.print(
        \\Memory Stats:
        \\  Total allocated: {d:.2} MB
        \\  Allocation count: {d}
        \\  Live allocations: {d}
        \\
    , .{
        @as(f64, @floatFromInt(stats.total_bytes)) / (1024 * 1024),
        stats.allocation_count,
        stats.live_allocation_count,
    });
}

/// Enable or disable memory profiling
pub fn setEnabled(enabled: bool) void {
    enable_memory_profiling = enabled;
}

/// Start memory profiling - call at app startup
pub fn startMemoryProfiling() !void {
    enable_memory_profiling = true;
    try Profiler.trackCounter("Memory Profiling", 1);
    try Profiler.markEvent("Memory Profiling Started");
}

/// Stop memory profiling and generate report
pub fn stopMemoryProfiling(report_path: []const u8) !void {
    try Profiler.markEvent("Memory Profiling Stopped");
    try saveMemoryProfile(report_path);
    enable_memory_profiling = false;
}
