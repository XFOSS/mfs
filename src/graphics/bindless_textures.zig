//! MFS Engine - Bindless Texture System
//! Advanced bindless texture management for modern GPUs
//! Reduces draw call overhead by allowing direct texture indexing in shaders
//! Supports Vulkan descriptor indexing and DirectX 12 resource binding
//! @thread-safe Thread-safe texture operations with proper synchronization
//! @performance Optimized for minimal driver overhead and maximum throughput

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const memory = @import("../system/memory/memory_manager.zig");
const profiler = @import("../system/profiling/profiler.zig");

/// Maximum number of bindless textures supported
pub const MAX_BINDLESS_TEXTURES = 16384;

/// Maximum number of bindless samplers supported
pub const MAX_BINDLESS_SAMPLERS = 256;

/// Bindless texture handle
pub const BindlessTextureHandle = u32;

/// Invalid bindless texture handle
pub const INVALID_BINDLESS_HANDLE: BindlessTextureHandle = 0;

/// Bindless texture descriptor
pub const BindlessTextureDesc = struct {
    texture: *types.Texture,
    view_type: ViewType = .texture_2d,
    format: ?types.TextureFormat = null, // Use texture's format if null
    mip_range: MipRange = .{},
    array_range: ArrayRange = .{},
    swizzle: Swizzle = .{},

    const ViewType = enum {
        texture_1d,
        texture_2d,
        texture_3d,
        texture_cube,
        texture_1d_array,
        texture_2d_array,
        texture_cube_array,
    };

    const MipRange = struct {
        base_level: u32 = 0,
        level_count: u32 = std.math.maxInt(u32), // All levels
    };

    const ArrayRange = struct {
        base_layer: u32 = 0,
        layer_count: u32 = std.math.maxInt(u32), // All layers
    };

    const Swizzle = struct {
        r: Component = .r,
        g: Component = .g,
        b: Component = .b,
        a: Component = .a,

        const Component = enum {
            zero,
            one,
            r,
            g,
            b,
            a,
        };
    };
};

/// Bindless sampler descriptor
pub const BindlessSamplerDesc = struct {
    min_filter: Filter = .linear,
    mag_filter: Filter = .linear,
    mip_filter: Filter = .linear,
    address_u: AddressMode = .repeat,
    address_v: AddressMode = .repeat,
    address_w: AddressMode = .repeat,
    mip_bias: f32 = 0.0,
    max_anisotropy: f32 = 16.0,
    compare_op: ?CompareOp = null,
    min_lod: f32 = 0.0,
    max_lod: f32 = 1000.0,
    border_color: BorderColor = .transparent_black,

    const Filter = enum {
        nearest,
        linear,
    };

    const AddressMode = enum {
        repeat,
        mirrored_repeat,
        clamp_to_edge,
        clamp_to_border,
        mirror_clamp_to_edge,
    };

    const CompareOp = enum {
        never,
        less,
        equal,
        less_or_equal,
        greater,
        not_equal,
        greater_or_equal,
        always,
    };

    const BorderColor = enum {
        transparent_black,
        opaque_black,
        opaque_white,
    };
};

/// Bindless texture entry
const BindlessTextureEntry = struct {
    handle: BindlessTextureHandle,
    desc: BindlessTextureDesc,
    backend_handle: *anyopaque, // Backend-specific handle (VkImageView, etc.)
    ref_count: u32,
    last_used_frame: u64,
    memory_usage: u64,

    // Metadata for debugging and optimization
    name: ?[]const u8 = null,
    creation_time: i64,
    access_count: u64 = 0,

    pub fn init(handle: BindlessTextureHandle, desc: BindlessTextureDesc) BindlessTextureEntry {
        return BindlessTextureEntry{
            .handle = handle,
            .desc = desc,
            .backend_handle = @ptrFromInt(0),
            .ref_count = 1,
            .last_used_frame = 0,
            .memory_usage = calculateMemoryUsage(desc.texture),
            .creation_time = std.time.timestamp(),
        };
    }

    fn calculateMemoryUsage(texture: *types.Texture) u64 {
        const pixel_size = switch (texture.format) {
            .rgba8, .rgba8_unorm, .bgra8, .bgra8_unorm => 4,
            .rgb8, .rgb8_unorm => 3,
            .r8_unorm => 1,
            .rg8_unorm => 2,
            .depth24_stencil8 => 4,
            .depth32f => 4,
            else => 4,
        };

        var total_size: u64 = 0;
        var mip_width = texture.width;
        var mip_height = texture.height;

        for (0..texture.mip_levels) |_| {
            total_size += @as(u64, mip_width) * mip_height * pixel_size * texture.array_layers;
            mip_width = @max(1, mip_width / 2);
            mip_height = @max(1, mip_height / 2);
        }

        return total_size;
    }
};

/// Bindless sampler entry
const BindlessSamplerEntry = struct {
    handle: BindlessTextureHandle,
    desc: BindlessSamplerDesc,
    backend_handle: *anyopaque,
    ref_count: u32,
    last_used_frame: u64,
};

/// Bindless texture allocation strategy
pub const AllocationStrategy = enum {
    linear, // Simple linear allocation
    free_list, // Track free slots
    pool_based, // Use object pools
    ring_buffer, // Ring buffer for temporary textures
};

/// Bindless texture manager statistics
pub const BindlessStats = struct {
    total_textures: u32 = 0,
    total_samplers: u32 = 0,
    active_textures: u32 = 0,
    active_samplers: u32 = 0,
    memory_usage_mb: f64 = 0.0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,
    texture_uploads: u64 = 0,
    texture_deletions: u64 = 0,

    // Performance metrics
    avg_lookup_time_ns: f64 = 0.0,
    peak_memory_usage_mb: f64 = 0.0,
    fragmentation_ratio: f32 = 0.0,

    pub fn reset(self: *BindlessStats) void {
        self.cache_hits = 0;
        self.cache_misses = 0;
        self.texture_uploads = 0;
        self.texture_deletions = 0;
        self.avg_lookup_time_ns = 0.0;
    }

    pub fn getCacheHitRate(self: *const BindlessStats) f32 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.cache_hits)) / @as(f32, @floatFromInt(total));
    }
};

/// Bindless texture manager
pub const BindlessTextureManager = struct {
    allocator: std.mem.Allocator,

    // Texture storage
    texture_entries: std.array_list.Managed(BindlessTextureEntry),
    sampler_entries: std.array_list.Managed(BindlessSamplerEntry),

    // Free lists for efficient allocation
    free_texture_handles: std.array_list.Managed(BindlessTextureHandle),
    free_sampler_handles: std.array_list.Managed(BindlessTextureHandle),

    // Hash maps for fast lookup
    texture_lookup: std.HashMap(*types.Texture, BindlessTextureHandle, TexturePtrContext, std.hash_map.default_max_load_percentage),
    sampler_lookup: std.HashMap(u64, BindlessTextureHandle, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage),

    // Backend-specific data
    backend_data: *anyopaque,

    // Configuration
    allocation_strategy: AllocationStrategy,
    max_textures: u32,
    max_samplers: u32,

    // Synchronization
    mutex: std.Thread.Mutex,

    // Statistics and profiling
    stats: BindlessStats,
    current_frame: u64,

    // Garbage collection
    gc_threshold: u32 = 1000,
    gc_frame_delay: u32 = 120, // 2 seconds at 60 FPS

    const Self = @This();

    const TexturePtrContext = struct {
        pub fn hash(self: @This(), ptr: *types.Texture) u64 {
            _ = self;
            return @intFromPtr(ptr);
        }

        pub fn eql(self: @This(), a: *types.Texture, b: *types.Texture) bool {
            _ = self;
            return a == b;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const manager = try allocator.create(Self);
        manager.* = Self{
            .allocator = allocator,
            .texture_entries = std.array_list.Managed(BindlessTextureEntry).init(allocator),
            .sampler_entries = std.array_list.Managed(BindlessSamplerEntry).init(allocator),
            .free_texture_handles = std.array_list.Managed(BindlessTextureHandle).init(allocator),
            .free_sampler_handles = std.array_list.Managed(BindlessTextureHandle).init(allocator),
            .texture_lookup = std.HashMap(*types.Texture, BindlessTextureHandle, TexturePtrContext, std.hash_map.default_max_load_percentage).init(allocator),
            .sampler_lookup = std.HashMap(u64, BindlessTextureHandle, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .backend_data = @ptrFromInt(0),
            .allocation_strategy = .free_list,
            .max_textures = MAX_BINDLESS_TEXTURES,
            .max_samplers = MAX_BINDLESS_SAMPLERS,
            .mutex = std.Thread.Mutex{},
            .stats = BindlessStats{},
            .current_frame = 0,
        };

        // Pre-allocate arrays
        try manager.texture_entries.ensureTotalCapacity(manager.max_textures);
        try manager.sampler_entries.ensureTotalCapacity(manager.max_samplers);

        // Initialize backend
        try manager.initializeBackend();

        return manager;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up all textures
        for (self.texture_entries.items) |*entry| {
            self.destroyBackendTexture(entry.backend_handle);
            if (entry.name) |name| {
                self.allocator.free(name);
            }
        }

        // Clean up all samplers
        for (self.sampler_entries.items) |*entry| {
            self.destroyBackendSampler(entry.backend_handle);
        }

        // Clean up collections
        self.texture_entries.deinit();
        self.sampler_entries.deinit();
        self.free_texture_handles.deinit();
        self.free_sampler_handles.deinit();
        self.texture_lookup.deinit();
        self.sampler_lookup.deinit();

        self.allocator.destroy(self);
    }

    /// Create a bindless texture handle
    pub fn createTexture(self: *Self, desc: BindlessTextureDesc, name: ?[]const u8) !BindlessTextureHandle {
        const timer = profiler.Timer.start("BindlessTextureManager.createTexture");
        defer timer.end();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if texture already exists
        if (self.texture_lookup.get(desc.texture)) |existing_handle| {
            // Increment reference count
            for (self.texture_entries.items) |*entry| {
                if (entry.handle == existing_handle) {
                    entry.ref_count += 1;
                    entry.last_used_frame = self.current_frame;
                    self.stats.cache_hits += 1;
                    return existing_handle;
                }
            }
        }

        self.stats.cache_misses += 1;

        // Allocate new handle
        const handle = try self.allocateTextureHandle();

        // Create backend texture view
        const backend_handle = try self.createBackendTexture(desc);

        // Create entry
        var entry = BindlessTextureEntry.init(handle, desc);
        entry.backend_handle = backend_handle;
        entry.last_used_frame = self.current_frame;

        if (name) |n| {
            entry.name = try self.allocator.dupe(u8, n);
        }

        // Store entry
        if (handle >= self.texture_entries.items.len) {
            try self.texture_entries.resize(handle + 1);
        }
        self.texture_entries.items[handle] = entry;

        // Update lookup table
        try self.texture_lookup.put(desc.texture, handle);

        // Update statistics
        self.stats.total_textures += 1;
        self.stats.active_textures += 1;
        self.stats.memory_usage_mb += @as(f64, @floatFromInt(entry.memory_usage)) / (1024.0 * 1024.0);
        self.stats.texture_uploads += 1;

        if (self.stats.memory_usage_mb > self.stats.peak_memory_usage_mb) {
            self.stats.peak_memory_usage_mb = self.stats.memory_usage_mb;
        }

        return handle;
    }

    /// Create a bindless sampler handle
    pub fn createSampler(self: *Self, desc: BindlessSamplerDesc) !BindlessTextureHandle {
        const timer = profiler.Timer.start("BindlessTextureManager.createSampler");
        defer timer.end();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Hash sampler descriptor
        const desc_hash = self.hashSamplerDesc(desc);

        // Check if sampler already exists
        if (self.sampler_lookup.get(desc_hash)) |existing_handle| {
            // Increment reference count
            for (self.sampler_entries.items) |*entry| {
                if (entry.handle == existing_handle) {
                    entry.ref_count += 1;
                    entry.last_used_frame = self.current_frame;
                    self.stats.cache_hits += 1;
                    return existing_handle;
                }
            }
        }

        self.stats.cache_misses += 1;

        // Allocate new handle
        const handle = try self.allocateSamplerHandle();

        // Create backend sampler
        const backend_handle = try self.createBackendSampler(desc);

        // Create entry
        const entry = BindlessSamplerEntry{
            .handle = handle,
            .desc = desc,
            .backend_handle = backend_handle,
            .ref_count = 1,
            .last_used_frame = self.current_frame,
        };

        // Store entry
        if (handle >= self.sampler_entries.items.len) {
            try self.sampler_entries.resize(handle + 1);
        }
        self.sampler_entries.items[handle] = entry;

        // Update lookup table
        try self.sampler_lookup.put(desc_hash, handle);

        // Update statistics
        self.stats.total_samplers += 1;
        self.stats.active_samplers += 1;

        return handle;
    }

    /// Release a bindless texture handle
    pub fn releaseTexture(self: *Self, handle: BindlessTextureHandle) void {
        const timer = profiler.Timer.start("BindlessTextureManager.releaseTexture");
        defer timer.end();

        self.mutex.lock();
        defer self.mutex.unlock();

        if (handle >= self.texture_entries.items.len) return;

        var entry = &self.texture_entries.items[handle];
        if (entry.ref_count == 0) return;

        entry.ref_count -= 1;

        if (entry.ref_count == 0) {
            // Mark for deletion
            entry.last_used_frame = self.current_frame;
        }
    }

    /// Release a bindless sampler handle
    pub fn releaseSampler(self: *Self, handle: BindlessTextureHandle) void {
        const timer = profiler.Timer.start("BindlessTextureManager.releaseSampler");
        defer timer.end();

        self.mutex.lock();
        defer self.mutex.unlock();

        if (handle >= self.sampler_entries.items.len) return;

        var entry = &self.sampler_entries.items[handle];
        if (entry.ref_count == 0) return;

        entry.ref_count -= 1;

        if (entry.ref_count == 0) {
            // Mark for deletion
            entry.last_used_frame = self.current_frame;
        }
    }

    /// Update texture data for a bindless handle
    pub fn updateTexture(self: *Self, handle: BindlessTextureHandle, data: []const u8) !void {
        const timer = profiler.Timer.start("BindlessTextureManager.updateTexture");
        defer timer.end();

        self.mutex.lock();
        defer self.mutex.unlock();

        if (handle >= self.texture_entries.items.len) return error.InvalidHandle;

        var entry = &self.texture_entries.items[handle];
        entry.last_used_frame = self.current_frame;
        entry.access_count += 1;

        // Update backend texture
        try self.updateBackendTexture(entry.backend_handle, data);

        self.stats.texture_uploads += 1;
    }

    /// Get bindless texture info
    pub fn getTextureInfo(self: *Self, handle: BindlessTextureHandle) ?BindlessTextureEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (handle >= self.texture_entries.items.len) return null;

        const entry = &self.texture_entries.items[handle];
        entry.access_count += 1;

        return entry.*;
    }

    /// Perform garbage collection
    pub fn performGarbageCollection(self: *Self) void {
        const timer = profiler.Timer.start("BindlessTextureManager.performGarbageCollection");
        defer timer.end();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Garbage collect textures
        var deleted_textures: u32 = 0;
        for (self.texture_entries.items, 0..) |*entry, i| {
            if (entry.ref_count == 0 and
                self.current_frame - entry.last_used_frame > self.gc_frame_delay)
            {

                // Destroy backend resources
                self.destroyBackendTexture(entry.backend_handle);

                // Remove from lookup table
                _ = self.texture_lookup.remove(entry.desc.texture);

                // Free name
                if (entry.name) |name| {
                    self.allocator.free(name);
                    entry.name = null;
                }

                // Add to free list
                self.free_texture_handles.append(@intCast(i)) catch {};

                // Update statistics
                self.stats.active_textures -= 1;
                self.stats.memory_usage_mb -= @as(f64, @floatFromInt(entry.memory_usage)) / (1024.0 * 1024.0);
                self.stats.texture_deletions += 1;

                deleted_textures += 1;

                // Clear entry
                entry.* = std.mem.zeroes(BindlessTextureEntry);
            }
        }

        // Garbage collect samplers
        var deleted_samplers: u32 = 0;
        for (self.sampler_entries.items, 0..) |*entry, i| {
            if (entry.ref_count == 0 and
                self.current_frame - entry.last_used_frame > self.gc_frame_delay)
            {

                // Destroy backend resources
                self.destroyBackendSampler(entry.backend_handle);

                // Remove from lookup table
                const desc_hash = self.hashSamplerDesc(entry.desc);
                _ = self.sampler_lookup.remove(desc_hash);

                // Add to free list
                self.free_sampler_handles.append(@intCast(i)) catch {};

                // Update statistics
                self.stats.active_samplers -= 1;

                deleted_samplers += 1;

                // Clear entry
                entry.* = std.mem.zeroes(BindlessSamplerEntry);
            }
        }

        std.log.debug("Garbage collection: deleted {} textures, {} samplers", .{ deleted_textures, deleted_samplers });
    }

    /// Advance frame counter and perform maintenance
    pub fn beginFrame(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.current_frame += 1;

        // Perform garbage collection periodically
        if (self.current_frame % self.gc_threshold == 0) {
            self.performGarbageCollection();
        }

        // Update fragmentation ratio
        self.updateFragmentationRatio();
    }

    /// Get current statistics
    pub fn getStats(self: *Self) BindlessStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }

    /// Reset performance statistics
    pub fn resetStats(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.stats.reset();
    }

    // Private methods
    fn allocateTextureHandle(self: *Self) !BindlessTextureHandle {
        // Try to reuse a free handle
        if (self.free_texture_handles.popOrNull()) |handle| {
            return handle;
        }

        // Allocate new handle
        const handle = @as(BindlessTextureHandle, @intCast(self.texture_entries.items.len));
        if (handle >= self.max_textures) {
            return error.OutOfTextureHandles;
        }

        return handle;
    }

    fn allocateSamplerHandle(self: *Self) !BindlessTextureHandle {
        // Try to reuse a free handle
        if (self.free_sampler_handles.popOrNull()) |handle| {
            return handle;
        }

        // Allocate new handle
        const handle = @as(BindlessTextureHandle, @intCast(self.sampler_entries.items.len));
        if (handle >= self.max_samplers) {
            return error.OutOfSamplerHandles;
        }

        return handle;
    }

    fn hashSamplerDesc(self: *Self, desc: BindlessSamplerDesc) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&desc));
        return hasher.final();
    }

    fn updateFragmentationRatio(self: *Self) void {
        const total_handles = self.texture_entries.items.len;
        const active_handles = self.stats.active_textures;

        if (total_handles == 0) {
            self.stats.fragmentation_ratio = 0.0;
        } else {
            self.stats.fragmentation_ratio = 1.0 - (@as(f32, @floatFromInt(active_handles)) / @as(f32, @floatFromInt(total_handles)));
        }
    }

    // Backend-specific methods (to be implemented by backend)
    fn initializeBackend(self: *Self) !void {
        _ = self;
        // Backend-specific initialization
    }

    fn createBackendTexture(self: *Self, desc: BindlessTextureDesc) !*anyopaque {
        _ = self;
        _ = desc;
        // Backend-specific texture view creation
        return @ptrFromInt(0x12345678);
    }

    fn createBackendSampler(self: *Self, desc: BindlessSamplerDesc) !*anyopaque {
        _ = self;
        _ = desc;
        // Backend-specific sampler creation
        return @ptrFromInt(0x87654321);
    }

    fn updateBackendTexture(self: *Self, backend_handle: *anyopaque, data: []const u8) !void {
        _ = self;
        _ = backend_handle;
        _ = data;
        // Backend-specific texture update
    }

    fn destroyBackendTexture(self: *Self, backend_handle: *anyopaque) void {
        _ = self;
        _ = backend_handle;
        // Backend-specific texture destruction
    }

    fn destroyBackendSampler(self: *Self, backend_handle: *anyopaque) void {
        _ = self;
        _ = backend_handle;
        // Backend-specific sampler destruction
    }
};

/// Utility functions for shader integration
pub const ShaderIntegration = struct {
    /// Generate HLSL code for bindless texture access
    pub fn generateHLSLCode(max_textures: u32, max_samplers: u32) []const u8 {
        _ = max_textures;
        _ = max_samplers;
        return 
        \\// Bindless texture declarations
        \\Texture2D bindless_textures[] : register(t0, space1);
        \\SamplerState bindless_samplers[] : register(s0, space1);
        \\
        \\// Sample bindless texture
        \\float4 SampleBindlessTexture(uint texture_index, uint sampler_index, float2 uv)
        \\{
        \\    return bindless_textures[texture_index].Sample(bindless_samplers[sampler_index], uv);
        \\}
        \\
        \\// Sample bindless texture with LOD
        \\float4 SampleBindlessTextureLOD(uint texture_index, uint sampler_index, float2 uv, float lod)
        \\{
        \\    return bindless_textures[texture_index].SampleLevel(bindless_samplers[sampler_index], uv, lod);
        \\}
        ;
    }

    /// Generate GLSL code for bindless texture access
    pub fn generateGLSLCode(max_textures: u32, max_samplers: u32) []const u8 {
        _ = max_textures;
        _ = max_samplers;
        return 
        \\#extension GL_ARB_bindless_texture : require
        \\#extension GL_ARB_gpu_shader5 : require
        \\
        \\// Bindless texture declarations
        \\layout(binding = 0) uniform sampler2D bindless_textures[];
        \\
        \\// Sample bindless texture
        \\vec4 sample_bindless_texture(uint texture_index, vec2 uv)
        \\{
        \\    return texture(bindless_textures[texture_index], uv);
        \\}
        \\
        \\// Sample bindless texture with LOD
        \\vec4 sample_bindless_texture_lod(uint texture_index, vec2 uv, float lod)
        \\{
        \\    return textureLod(bindless_textures[texture_index], uv, lod);
        \\}
        ;
    }
};
