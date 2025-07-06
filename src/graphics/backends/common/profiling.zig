const std = @import("std");

/// Performance metrics for GPU operations
pub const GpuMetrics = struct {
    /// Time spent in draw calls (nanoseconds)
    draw_time_ns: u64 = 0,
    /// Time spent in compute dispatches (nanoseconds)
    compute_time_ns: u64 = 0,
    /// Time spent in memory transfers (nanoseconds)
    transfer_time_ns: u64 = 0,
    /// Number of draw calls
    draw_calls: u32 = 0,
    /// Number of triangles drawn
    triangle_count: u32 = 0,
    /// Number of compute dispatches
    compute_dispatches: u32 = 0,
    /// Number of vertices processed
    vertex_count: u32 = 0,
    /// Number of pipeline state changes
    pipeline_changes: u32 = 0,
    /// Number of descriptor set bindings
    descriptor_bindings: u32 = 0,
    /// Memory allocated (bytes)
    memory_allocated: usize = 0,
    /// Memory used (bytes)
    memory_used: usize = 0,
    /// Number of resource barriers
    barrier_count: u32 = 0,
};

/// Performance marker for timing sections of code
pub const PerformanceMarker = struct {
    name: []const u8,
    start_time: u64,
    parent: ?*PerformanceMarker = null,
    children: std.ArrayList(*PerformanceMarker),
    metrics: GpuMetrics = .{},

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*PerformanceMarker {
        const marker = try allocator.create(PerformanceMarker);
        marker.* = .{
            .name = name,
            .start_time = 0,
            .children = std.ArrayList(*PerformanceMarker).init(allocator),
        };
        return marker;
    }

    pub fn deinit(self: *PerformanceMarker, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit();
        allocator.destroy(self);
    }

    pub fn end(self: *PerformanceMarker) u64 {
        const end_time = std.time.nanoTimestamp();
        return @intCast(end_time - self.start_time);
    }
};

/// Performance profiler for tracking GPU operations
pub const GpuProfiler = struct {
    allocator: std.mem.Allocator,
    current_frame: u64 = 0,
    frame_metrics: std.ArrayList(GpuMetrics),
    active_markers: std.ArrayList(*PerformanceMarker),
    root_marker: ?*PerformanceMarker = null,

    pub fn init(allocator: std.mem.Allocator) !GpuProfiler {
        return GpuProfiler{
            .allocator = allocator,
            .frame_metrics = std.ArrayList(GpuMetrics).init(allocator),
            .active_markers = std.ArrayList(*PerformanceMarker).init(allocator),
        };
    }

    pub fn deinit(self: *GpuProfiler) void {
        if (self.root_marker) |root| {
            root.deinit(self.allocator);
        }
        self.frame_metrics.deinit();
        self.active_markers.deinit();
    }

    pub fn beginFrame(self: *GpuProfiler) !void {
        // Clean up previous frame
        if (self.root_marker) |root| {
            root.deinit(self.allocator);
        }

        // Create new root marker
        self.root_marker = try PerformanceMarker.init(self.allocator, "Frame");
        try self.active_markers.append(self.root_marker.?);

        self.current_frame += 1;
    }

    pub fn endFrame(self: *GpuProfiler) !void {
        if (self.root_marker) |root| {
            const frame_time = root.end();
            _ = frame_time;

            // Store frame metrics
            try self.frame_metrics.append(root.metrics);

            // Keep only last N frames
            if (self.frame_metrics.items.len > 60) {
                _ = self.frame_metrics.orderedRemove(0);
            }
        }

        self.active_markers.clearRetainingCapacity();
    }

    pub fn pushMarker(self: *GpuProfiler, name: []const u8) !void {
        const parent = if (self.active_markers.items.len > 0)
            self.active_markers.items[self.active_markers.items.len - 1]
        else
            self.root_marker.?;

        const marker = try PerformanceMarker.init(self.allocator, name);
        marker.parent = parent;
        try parent.children.append(marker);
        try self.active_markers.append(marker);
    }

    pub fn popMarker(self: *GpuProfiler) void {
        if (self.active_markers.items.len > 0) {
            const finished_opt = self.active_markers.pop();
            const finished = finished_opt orelse return;

            // Add finished marker's metrics to its parent (if any)
            const parent_metrics = self.getCurrentMetrics();
            const finished_metrics = finished.*.metrics;

            parent_metrics.*.draw_time_ns += finished_metrics.draw_time_ns;
            parent_metrics.*.compute_time_ns += finished_metrics.compute_time_ns;
            parent_metrics.*.transfer_time_ns += finished_metrics.transfer_time_ns;
            parent_metrics.*.draw_calls += finished_metrics.draw_calls;
            parent_metrics.*.triangle_count += finished_metrics.triangle_count;
            parent_metrics.*.compute_dispatches += finished_metrics.compute_dispatches;
            parent_metrics.*.vertex_count += finished_metrics.vertex_count;
            parent_metrics.*.pipeline_changes += finished_metrics.pipeline_changes;
            parent_metrics.*.descriptor_bindings += finished_metrics.descriptor_bindings;
            parent_metrics.*.memory_allocated += finished_metrics.memory_allocated;
            parent_metrics.*.memory_used += finished_metrics.memory_used;
            parent_metrics.*.barrier_count += finished_metrics.barrier_count;
        }
    }

    pub fn getCurrentMetrics(self: *GpuProfiler) *GpuMetrics {
        return &(if (self.active_markers.items.len > 0)
            self.active_markers.items[self.active_markers.items.len - 1].metrics
        else
            self.root_marker.?.metrics);
    }

    pub fn getAverageFrameTime(self: GpuProfiler) f64 {
        if (self.frame_metrics.items.len == 0) return 0;

        var total_time: u64 = 0;
        for (self.frame_metrics.items) |metrics| {
            total_time += metrics.draw_time_ns + metrics.compute_time_ns + metrics.transfer_time_ns;
        }

        return @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(self.frame_metrics.items.len));
    }
};
