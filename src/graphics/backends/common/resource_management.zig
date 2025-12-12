const std = @import("std");
const interface = @import("../interface.zig");

/// Advanced GPU Memory Pool for efficient resource allocation
pub const GPUMemoryPool = struct {
    const MemoryBlock = struct {
        ptr: ?*anyopaque,
        size: u64,
        offset: u64,
        in_use: bool,
        alignment: u64,
    };

    allocator: std.mem.Allocator,
    blocks: std.ArrayList(MemoryBlock),
    total_size: u64,
    used_size: u64,
    alignment: u64,

    pub fn init(allocator: std.mem.Allocator, total_size: u64, alignment: u64) !GPUMemoryPool {
        return GPUMemoryPool{
            .allocator = allocator,
            .blocks = std.ArrayList(MemoryBlock).init(allocator),
            .total_size = total_size,
            .used_size = 0,
            .alignment = alignment,
        };
    }

    pub fn deinit(self: *GPUMemoryPool) void {
        self.blocks.deinit();
    }

    pub fn allocate(self: *GPUMemoryPool, size: u64, alignment: u64) ?MemoryBlock {
        const aligned_size = alignUp(size, alignment);

        // First-fit allocation strategy
        for (self.blocks.items, 0..) |*block, i| {
            if (!block.in_use and block.size >= aligned_size) {
                // Split block if necessary
                if (block.size > aligned_size + self.alignment) {
                    const new_block = MemoryBlock{
                        .ptr = null,
                        .size = block.size - aligned_size,
                        .offset = block.offset + aligned_size,
                        .in_use = false,
                        .alignment = alignment,
                    };
                    self.blocks.insert(i + 1, new_block) catch return null;
                }

                block.size = aligned_size;
                block.in_use = true;
                block.alignment = alignment;
                self.used_size += aligned_size;
                return block.*;
            }
        }

        // No suitable block found
        return null;
    }

    pub fn deallocate(self: *GPUMemoryPool, block: MemoryBlock) void {
        for (self.blocks.items) |*b| {
            if (b.offset == block.offset) {
                b.in_use = false;
                self.used_size -= b.size;
                // TODO: Implement block merging for better fragmentation management
                break;
            }
        }
    }

    fn alignUp(value: u64, alignment: u64) u64 {
        return (value + alignment - 1) & ~(alignment - 1);
    }
};

/// Advanced Descriptor Heap Manager with performance optimizations
pub const DescriptorHeapManager = struct {
    const DescriptorSet = struct {
        heap_ptr: *anyopaque,
        offset: u32,
        count: u32,
        in_use: bool,
    };

    allocator: std.mem.Allocator,
    descriptor_sets: std.ArrayList(DescriptorSet),
    heap_size: u32,
    descriptor_size: u32,
    used_descriptors: u32,

    pub fn init(allocator: std.mem.Allocator, heap_size: u32, descriptor_size: u32) !DescriptorHeapManager {
        return DescriptorHeapManager{
            .allocator = allocator,
            .descriptor_sets = std.ArrayList(DescriptorSet).init(allocator),
            .heap_size = heap_size,
            .descriptor_size = descriptor_size,
            .used_descriptors = 0,
        };
    }

    pub fn deinit(self: *DescriptorHeapManager) void {
        self.descriptor_sets.deinit();
    }

    pub fn allocateDescriptors(self: *DescriptorHeapManager, count: u32) ?DescriptorSet {
        if (self.used_descriptors + count > self.heap_size) {
            return null; // Not enough space
        }

        // Simple linear allocation - could be improved with free list
        const offset = self.used_descriptors;
        self.used_descriptors += count;

        const descriptor_set = DescriptorSet{
            .heap_ptr = undefined, // Will be set by backend
            .offset = offset,
            .count = count,
            .in_use = true,
        };

        self.descriptor_sets.append(descriptor_set) catch return null;
        return descriptor_set;
    }

    pub fn freeDescriptors(self: *DescriptorHeapManager, set: DescriptorSet) void {
        for (self.descriptor_sets.items, 0..) |*s, i| {
            if (s.offset == set.offset) {
                s.in_use = false;
                self.descriptor_sets.swapRemove(i);
                break;
            }
        }
    }
};

/// Performance monitoring and profiling utilities
pub const PerformanceProfiler = struct {
    const FrameData = struct {
        cpu_time_ms: f64,
        gpu_time_ms: f64,
        draw_calls: u32,
        triangles: u64,
        memory_used: u64,
        timestamp: u64,
    };

    allocator: std.mem.Allocator,
    frame_history: std.ArrayList(FrameData),
    history_capacity: usize,
    current_frame: FrameData,
    timer: std.time.Timer,
    frame_count: u64,

    pub fn init(allocator: std.mem.Allocator) !PerformanceProfiler {
        const ring_buffer = std.ArrayList(FrameData).init(allocator);

        return PerformanceProfiler{
            .allocator = allocator,
            .frame_history = ring_buffer,
            .history_capacity = 120,
            .current_frame = std.mem.zeroes(FrameData),
            .timer = try std.time.Timer.start(),
            .frame_count = 0,
        };
    }

    pub fn deinit(self: *PerformanceProfiler) void {
        self.frame_history.deinit();
    }

    pub fn beginFrame(self: *PerformanceProfiler) void {
        self.current_frame = std.mem.zeroes(FrameData);
        self.current_frame.timestamp = self.timer.read();
    }

    pub fn endFrame(self: *PerformanceProfiler) void {
        const frame_time = self.timer.read() - self.current_frame.timestamp;
        self.current_frame.cpu_time_ms = @as(f64, @floatFromInt(frame_time)) / 1_000_000.0;

        self.frame_history.append(self.current_frame) catch {};
        // Remove oldest entries if we exceed capacity
        while (self.frame_history.items.len > self.history_capacity) {
            _ = self.frame_history.swapRemove(0);
        }
        self.frame_count += 1;
    }

    pub fn recordDrawCall(self: *PerformanceProfiler, triangle_count: u64) void {
        self.current_frame.draw_calls += 1;
        self.current_frame.triangles += triangle_count;
    }

    pub fn recordMemoryUsage(self: *PerformanceProfiler, bytes: u64) void {
        self.current_frame.memory_used = bytes;
    }

    pub fn getAverageFrameTime(self: *PerformanceProfiler) f64 {
        if (self.frame_history.len() == 0) return 0.0;

        var total: f64 = 0.0;
        var count: u32 = 0;

        for (self.frame_history.items) |frame| {
            total += frame.cpu_time_ms;
            count += 1;
        }

        return if (count > 0) total / @as(f64, @floatFromInt(count)) else 0.0;
    }

    pub fn getFPS(self: *PerformanceProfiler) f64 {
        const avg_frame_time = self.getAverageFrameTime();
        return if (avg_frame_time > 0.0) 1000.0 / avg_frame_time else 0.0;
    }
};

/// Command buffer pooling for reduced allocation overhead
pub const CommandBufferPool = struct {
    const CommandBuffer = struct {
        handle: *anyopaque,
        in_use: bool,
        recording: bool,
    };

    allocator: std.mem.Allocator,
    buffers: std.ArrayList(CommandBuffer),
    backend_type: interface.GraphicsBackendType,

    pub fn init(allocator: std.mem.Allocator, backend_type: interface.GraphicsBackendType) CommandBufferPool {
        // Store backend_type for future use when creating backend-specific command buffers
        return CommandBufferPool{
            .allocator = allocator,
            .buffers = std.ArrayList(CommandBuffer).init(allocator),
            .backend_type = backend_type,
        };
    }

    pub fn deinit(self: *CommandBufferPool) void {
        self.buffers.deinit();
    }

    pub fn acquireCommandBuffer(self: *CommandBufferPool) ?*CommandBuffer {
        // Look for an unused buffer
        for (self.buffers.items) |*buffer| {
            if (!buffer.in_use) {
                buffer.in_use = true;
                buffer.recording = false;
                return buffer;
            }
        }

        // No available buffer found - would need to create new one
        return null;
    }

    pub fn releaseCommandBuffer(self: *CommandBufferPool, buffer: *CommandBuffer) void {
        _ = self;
        buffer.in_use = false;
        buffer.recording = false;
    }
};

/// Common resource cleanup utilities shared across backends
pub fn cleanupSwapChainResources(allocator: std.mem.Allocator, render_targets: []?*anyopaque) void {
    for (render_targets) |rt| {
        if (rt) |resource| {
            allocator.destroy(resource);
        }
    }
}

/// Enhanced descriptor heap management
pub const DescriptorHeapDesc = struct {
    type: enum {
        rtv,
        dsv,
        cbv_srv_uav,
        sampler,
    },
    num_descriptors: u32,
    flags: u32 = 0,
    shader_visible: bool = false,
};

pub const ResourceState = interface.ResourceState;
pub const SubresourceRange = interface.SubresourceRange;

pub const ResourceBarrierDesc = struct {
    resource: *anyopaque,
    old_state: ResourceState,
    new_state: ResourceState,
    subresource: SubresourceRange = .{},
};

/// GPU-based occlusion culling system
pub const OcclusionCullingSystem = struct {
    allocator: std.mem.Allocator,
    query_heap: ?*anyopaque,
    query_results: std.ArrayList(bool),
    pending_queries: u32,

    pub fn init(allocator: std.mem.Allocator) OcclusionCullingSystem {
        return OcclusionCullingSystem{
            .allocator = allocator,
            .query_heap = null,
            .query_results = std.ArrayList(bool).init(allocator),
            .pending_queries = 0,
        };
    }

    pub fn deinit(self: *OcclusionCullingSystem) void {
        self.query_results.deinit();
    }

    pub fn beginOcclusionQuery(self: *OcclusionCullingSystem, query_id: u32) void {
        _ = self;
        _ = query_id;
        // Implementation would depend on specific backend
    }

    pub fn endOcclusionQuery(self: *OcclusionCullingSystem, query_id: u32) void {
        _ = self;
        _ = query_id;
        // Implementation would depend on specific backend
    }

    pub fn isVisible(self: *OcclusionCullingSystem, query_id: u32) bool {
        return if (query_id < self.query_results.items.len) self.query_results.items[query_id] else true;
    }
};

/// Level-of-Detail (LOD) management system
pub const LODManager = struct {
    const LODLevel = struct {
        distance_threshold: f32,
        vertex_count: u32,
        index_count: u32,
        mesh_data: ?*anyopaque,
    };

    allocator: std.mem.Allocator,
    lod_levels: std.HashMap(u32, std.ArrayList(LODLevel), std.hash_map.DefaultHashMap(u32, std.ArrayList(LODLevel)).Context, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) LODManager {
        return LODManager{
            .allocator = allocator,
            .lod_levels = std.HashMap(u32, std.ArrayList(LODLevel), std.hash_map.DefaultHashMap(u32, std.ArrayList(LODLevel)).Context, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *LODManager) void {
        var iterator = self.lod_levels.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.lod_levels.deinit();
    }

    pub fn selectLOD(self: *LODManager, mesh_id: u32, distance: f32) ?LODLevel {
        if (self.lod_levels.get(mesh_id)) |levels| {
            for (levels.items) |level| {
                if (distance <= level.distance_threshold) {
                    return level;
                }
            }
            // Return highest LOD if no threshold met
            if (levels.items.len > 0) {
                return levels.items[levels.items.len - 1];
            }
        }
        return null;
    }
};

/// Common debug utilities
pub fn setDebugName(resource: *anyopaque, name: []const u8) void {
    _ = resource;
    _ = name;
    // Implementation varies by backend
}

pub fn beginDebugGroup(cmd: *anyopaque, name: []const u8) void {
    _ = cmd;
    _ = name;
    // Implementation varies by backend
}

pub fn endDebugGroup(cmd: *anyopaque) void {
    _ = cmd;
    // Implementation varies by backend
}
