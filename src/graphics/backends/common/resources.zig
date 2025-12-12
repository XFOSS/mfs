const std = @import("std");
const types = @import("../../types.zig");
const memory = @import("memory.zig");
const errors = @import("errors.zig");

/// Common resource management utilities shared across backends
pub const ResourceManager = struct {
    allocator: std.mem.Allocator,
    textures: std.AutoHashMap(u64, *types.Texture),
    buffers: std.AutoHashMap(u64, *types.Buffer),
    shaders: std.AutoHashMap(u64, *types.Shader),
    pipelines: std.AutoHashMap(u64, *types.Pipeline),
    render_targets: std.AutoHashMap(u64, *types.RenderTarget),

    memory_blocks: std.array_list.Managed(*memory.MemoryBlock),

    pub fn init(allocator: std.mem.Allocator) ResourceManager {
        return ResourceManager{
            .allocator = allocator,
            .textures = std.AutoHashMap(u64, *types.Texture).init(allocator),
            .buffers = std.AutoHashMap(u64, *types.Buffer).init(allocator),
            .shaders = std.AutoHashMap(u64, *types.Shader).init(allocator),
            .pipelines = std.AutoHashMap(u64, *types.Pipeline).init(allocator),
            .render_targets = std.AutoHashMap(u64, *types.RenderTarget).init(allocator),
            .memory_blocks = std.array_list.Managed(*memory.MemoryBlock).init(allocator),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        // Free all memory blocks
        for (self.memory_blocks.items) |block| {
            if (block.mapped) {
                block.unmap();
            }
        }
        self.memory_blocks.deinit();

        // Clean up resource maps
        self.textures.deinit();
        self.buffers.deinit();
        self.shaders.deinit();
        self.pipelines.deinit();
        self.render_targets.deinit();
    }

    pub fn registerTexture(self: *ResourceManager, texture: *types.Texture) !void {
        const id = @intFromPtr(texture);
        try self.textures.put(id, texture);
    }

    pub fn unregisterTexture(self: *ResourceManager, texture: *types.Texture) void {
        const id = @intFromPtr(texture);
        _ = self.textures.remove(id);
    }

    pub fn registerBuffer(self: *ResourceManager, buffer: *types.Buffer) !void {
        const id = @intFromPtr(buffer);
        try self.buffers.put(id, buffer);
    }

    pub fn unregisterBuffer(self: *ResourceManager, buffer: *types.Buffer) void {
        const id = @intFromPtr(buffer);
        _ = self.buffers.remove(id);
    }

    pub fn registerShader(self: *ResourceManager, shader: *types.Shader) !void {
        const id = @intFromPtr(shader);
        try self.shaders.put(id, shader);
    }

    pub fn unregisterShader(self: *ResourceManager, shader: *types.Shader) void {
        const id = @intFromPtr(shader);
        _ = self.shaders.remove(id);
    }

    pub fn registerPipeline(self: *ResourceManager, pipeline: *types.Pipeline) !void {
        const id = @intFromPtr(pipeline);
        try self.pipelines.put(id, pipeline);
    }

    pub fn unregisterPipeline(self: *ResourceManager, pipeline: *types.Pipeline) void {
        const id = @intFromPtr(pipeline);
        _ = self.pipelines.remove(id);
    }

    pub fn registerRenderTarget(self: *ResourceManager, render_target: *types.RenderTarget) !void {
        const id = @intFromPtr(render_target);
        try self.render_targets.put(id, render_target);
    }

    pub fn unregisterRenderTarget(self: *ResourceManager, render_target: *types.RenderTarget) void {
        const id = @intFromPtr(render_target);
        _ = self.render_targets.remove(id);
    }

    pub fn registerMemoryBlock(self: *ResourceManager, block: *memory.MemoryBlock) !void {
        try self.memory_blocks.append(block);
    }

    pub fn getResourceStats(self: ResourceManager) types.ResourceStats {
        return .{
            .texture_count = @intCast(self.textures.count()),
            .buffer_count = @intCast(self.buffers.count()),
            .shader_count = @intCast(self.shaders.count()),
            .pipeline_count = @intCast(self.pipelines.count()),
            .render_target_count = @intCast(self.render_targets.count()),
            .memory_block_count = @intCast(self.memory_blocks.items.len),
        };
    }

    pub fn findTextureById(self: ResourceManager, id: u64) ?*types.Texture {
        return self.textures.get(id);
    }

    pub fn findBufferById(self: ResourceManager, id: u64) ?*types.Buffer {
        return self.buffers.get(id);
    }

    pub fn findShaderById(self: ResourceManager, id: u64) ?*types.Shader {
        return self.shaders.get(id);
    }

    pub fn findPipelineById(self: ResourceManager, id: u64) ?*types.Pipeline {
        return self.pipelines.get(id);
    }

    pub fn findRenderTargetById(self: ResourceManager, id: u64) ?*types.RenderTarget {
        return self.render_targets.get(id);
    }

    pub fn findTextureByName(self: ResourceManager, name: []const u8) ?*types.Texture {
        var it = self.textures.valueIterator();
        while (it.next()) |texture| {
            if (std.mem.eql(u8, texture.*.name, name)) {
                return texture.*;
            }
        }
        return null;
    }

    pub fn findBufferByName(self: ResourceManager, name: []const u8) ?*types.Buffer {
        var it = self.buffers.valueIterator();
        while (it.next()) |buffer| {
            if (std.mem.eql(u8, buffer.*.name, name)) {
                return buffer.*;
            }
        }
        return null;
    }

    pub fn findShaderByName(self: ResourceManager, name: []const u8) ?*types.Shader {
        var it = self.shaders.valueIterator();
        while (it.next()) |shader| {
            if (std.mem.eql(u8, shader.*.name, name)) {
                return shader.*;
            }
        }
        return null;
    }

    pub fn findPipelineByName(self: ResourceManager, name: []const u8) ?*types.Pipeline {
        var it = self.pipelines.valueIterator();
        while (it.next()) |pipeline| {
            if (std.mem.eql(u8, pipeline.*.name, name)) {
                return pipeline.*;
            }
        }
        return null;
    }

    pub fn findRenderTargetByName(self: ResourceManager, name: []const u8) ?*types.RenderTarget {
        var it = self.render_targets.valueIterator();
        while (it.next()) |render_target| {
            if (std.mem.eql(u8, render_target.*.name, name)) {
                return render_target.*;
            }
        }
        return null;
    }

    pub fn cleanupUnusedResources(self: *ResourceManager) void {
        // Iterate over each resource map and remove unused resources
        for (self.textures.iterator()) |entry| {
            if (!entry.value.isInUse()) {
                self.textures.remove(entry.key);
            }
        }
        for (self.buffers.iterator()) |entry| {
            if (!entry.value.isInUse()) {
                self.buffers.remove(entry.key);
            }
        }
        for (self.shaders.iterator()) |entry| {
            if (!entry.value.isInUse()) {
                self.shaders.remove(entry.key);
            }
        }
        for (self.pipelines.iterator()) |entry| {
            if (!entry.value.isInUse()) {
                self.pipelines.remove(entry.key);
            }
        }
        for (self.render_targets.iterator()) |entry| {
            if (!entry.value.isInUse()) {
                self.render_targets.remove(entry.key);
            }
        }
    }
};

/// Common texture utilities
pub const TextureUtils = struct {
    /// Calculate mipmap dimensions
    pub fn calculateMipDimensions(width: u32, height: u32, depth: u32, level: u32) struct { width: u32, height: u32, depth: u32 } {
        const w = @max(1, width >> @intCast(level));
        const h = @max(1, height >> @intCast(level));
        const d = @max(1, depth >> @intCast(level));
        return .{ .width = w, .height = h, .depth = d };
    }

    /// Calculate number of mipmap levels
    pub fn calculateMipLevels(width: u32, height: u32, depth: u32) u32 {
        const max_dim = @max(width, @max(height, depth));
        return 1 + @as(u32, @intCast(@floor(@log2(@as(f32, @floatFromInt(max_dim))))));
    }

    /// Calculate texture size in bytes
    pub fn calculateTextureSize(format: types.TextureFormat, width: u32, height: u32, depth: u32, mip_levels: u32) usize {
        const bytes_per_pixel = switch (format) {
            .rgba8, .bgra8 => 4,
            .rgb8 => 3,
            .rg8 => 2,
            .r8 => 1,
            .depth24_stencil8 => 4,
            .depth32f => 4,
            else => 4, // Default to 4 bytes per pixel
        };

        var total_size: usize = 0;
        var level: u32 = 0;
        while (level < mip_levels) : (level += 1) {
            const dims = calculateMipDimensions(width, height, depth, level);
            total_size += @as(usize, @intCast(dims.width)) * @as(usize, @intCast(dims.height)) * @as(usize, @intCast(dims.depth)) * bytes_per_pixel;
        }

        return total_size;
    }
};

/// Common buffer utilities
pub const BufferUtils = struct {
    /// Calculate aligned buffer size
    pub fn alignBufferSize(size: usize, alignment: usize) usize {
        return (size + alignment - 1) & ~(alignment - 1);
    }

    /// Check if buffer usage flags are compatible
    pub fn isBufferUsageCompatible(usage: types.BufferUsage, required_usage: types.BufferUsage) bool {
        // Check if all required flags are set
        if (required_usage.vertex_buffer and !usage.vertex_buffer) return false;
        if (required_usage.index_buffer and !usage.index_buffer) return false;
        if (required_usage.uniform_buffer and !usage.uniform_buffer) return false;
        if (required_usage.storage_buffer and !usage.storage_buffer) return false;
        if (required_usage.transfer_src and !usage.transfer_src) return false;
        if (required_usage.transfer_dst and !usage.transfer_dst) return false;

        return true;
    }
};
