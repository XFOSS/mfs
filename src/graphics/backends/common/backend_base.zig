const std = @import("std");
const interface = @import("../interface.zig");
const types = @import("../../types.zig");
const memory = @import("memory.zig");
const profiling = @import("profiling.zig");
const errors = @import("errors.zig");

/// Base implementation for graphics backends with common functionality
/// This helps reduce code duplication across different backend implementations
pub const BackendBase = struct {
    allocator: std.mem.Allocator,
    profiler: profiling.GpuProfiler,
    error_logger: errors.ErrorLogger,
    initialized: bool = false,
    debug_mode: bool = false,

    // Common backend properties
    width: u32 = 0,
    height: u32 = 0,
    vsync: bool = true,

    // Resource tracking
    active_textures: std.AutoHashMap(u64, *types.Texture),
    active_buffers: std.AutoHashMap(u64, *types.Buffer),
    active_shaders: std.AutoHashMap(u64, *types.Shader),
    active_pipelines: std.AutoHashMap(u64, *types.Pipeline),

    // Memory management
    memory_allocator: memory.Allocator,

    // Debug information
    debug_groups: std.array_list.Managed([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, debug_mode: bool) !Self {
        return Self{
            .allocator = allocator,
            .profiler = try profiling.GpuProfiler.init(allocator),
            .error_logger = errors.ErrorLogger.init(allocator),
            .debug_mode = debug_mode,
            .active_textures = std.AutoHashMap(u64, *types.Texture).init(allocator),
            .active_buffers = std.AutoHashMap(u64, *types.Buffer).init(allocator),
            .active_shaders = std.AutoHashMap(u64, *types.Shader).init(allocator),
            .active_pipelines = std.AutoHashMap(u64, *types.Pipeline).init(allocator),
            .memory_allocator = try memory.Allocator.init(allocator, .general, 1024 * 1024 * 64), // 64MB default
            .debug_groups = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.profiler.deinit();
        self.error_logger.deinit();
        self.active_textures.deinit();
        self.active_buffers.deinit();
        self.active_shaders.deinit();
        self.active_pipelines.deinit();
        self.memory_allocator.deinit();

        for (self.debug_groups.items) |group| {
            self.allocator.free(group);
        }
        self.debug_groups.deinit();
    }

    pub fn beginFrame(self: *Self) !void {
        try self.profiler.beginFrame();
    }

    pub fn endFrame(self: *Self) !void {
        try self.profiler.endFrame();
    }

    pub fn beginDebugGroup(self: *Self, name: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.debug_groups.append(name_copy);
        try self.profiler.pushMarker(name);
    }

    pub fn endDebugGroup(self: *Self) void {
        if (self.debug_groups.items.len > 0) {
            const name = self.debug_groups.pop();
            self.allocator.free(name);
        }
        self.profiler.popMarker();
    }

    pub fn logError(self: *Self, err: anyerror, message: []const u8, severity: errors.ErrorSeverity, backend_name: []const u8) void {
        const ctx = errors.makeError(err, message, backend_name, @src().file, @src().line, null, severity);
        _ = self.error_logger.logError(ctx, severity) catch {};
    }

    pub fn registerTexture(self: *Self, texture: *types.Texture) !void {
        try self.active_textures.put(@intFromPtr(texture), texture);
    }

    pub fn unregisterTexture(self: *Self, texture: *types.Texture) void {
        _ = self.active_textures.remove(@intFromPtr(texture));
    }

    pub fn registerBuffer(self: *Self, buffer: *types.Buffer) !void {
        try self.active_buffers.put(@intFromPtr(buffer), buffer);
    }

    pub fn unregisterBuffer(self: *Self, buffer: *types.Buffer) void {
        _ = self.active_buffers.remove(@intFromPtr(buffer));
    }

    pub fn registerShader(self: *Self, shader: *types.Shader) !void {
        try self.active_shaders.put(@intFromPtr(shader), shader);
    }

    pub fn unregisterShader(self: *Self, shader: *types.Shader) void {
        _ = self.active_shaders.remove(@intFromPtr(shader));
    }

    pub fn registerPipeline(self: *Self, pipeline: *types.Pipeline) !void {
        try self.active_pipelines.put(@intFromPtr(pipeline), pipeline);
    }

    pub fn unregisterPipeline(self: *Self, pipeline: *types.Pipeline) void {
        _ = self.active_pipelines.remove(@intFromPtr(pipeline));
    }

    // Common implementation for debug name setting
    pub fn setDebugName(self: *Self, object_type: enum { texture, buffer, shader, pipeline }, object_ptr: *anyopaque, name: []const u8) void {
        _ = self;
        _ = object_type;
        _ = object_ptr;
        _ = name;
        // Actual implementation depends on the backend
    }

    // Common resource tracking
    pub fn getResourceStats(self: *Self) types.ResourceStats {
        return .{
            .texture_count = @intCast(self.active_textures.count()),
            .buffer_count = @intCast(self.active_buffers.count()),
            .shader_count = @intCast(self.active_shaders.count()),
            .pipeline_count = @intCast(self.active_pipelines.count()),
            .memory_allocated = self.memory_allocator.total_size,
            .memory_used = self.memory_allocator.used_size,
        };
    }
};
