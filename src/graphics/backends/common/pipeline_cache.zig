const std = @import("std");

const interface = @import("../interface.zig");

/// Entry in the pipeline cache
pub const PipelineEntry = struct {
    key: u64,
    pipeline: *interface.Pipeline,
};

/// Pipeline caching for reuse across backends
pub const PipelineCache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(PipelineEntry),

    /// Initialize the pipeline cache
    pub fn init(allocator: std.mem.Allocator) PipelineCache {
        return PipelineCache{
            .allocator = allocator,
            .entries = std.ArrayList(PipelineEntry).init(allocator),
        };
    }

    /// Clean up cache data (does not destroy pipelines themselves)
    pub fn deinit(self: *PipelineCache) void {
        self.entries.deinit();
    }

    /// Hash a PipelineDesc to a 64-bit key so it can be stored in the cache. This
    /// uses FNV-1a over the raw bytes of the descriptor which is good enough for
    /// a cache lookup and is extremely fast.
    fn hashDesc(desc: *const interface.PipelineDesc) u64 {
        const ptr: *const u8 = @ptrCast(desc);
        return std.hash.fnv1a(ptr, @sizeOf(interface.PipelineDesc));
    }

    /// Retrieve or create a pipeline
    pub fn getOrCreate(
        self: *PipelineCache,
        desc: *const interface.PipelineDesc,
        createFunc: fn (*const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline,
    ) interface.GraphicsBackendError!*interface.Pipeline {
        const key = hashDesc(desc);
        for (self.entries.items) |entry| {
            if (entry.key == key) return entry.pipeline;
        }
        const pipeline = try createFunc(desc);
        try self.entries.append(PipelineEntry{ .key = key, .pipeline = pipeline });
        return pipeline;
    }
};
