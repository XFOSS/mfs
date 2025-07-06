//! MFS Graphics - Render Module
//! High-level rendering functionality and utilities
//! @thread-safe Thread-safe rendering operations

const std = @import("std");
const types = @import("../types.zig");
const backends = @import("../backends/mod.zig");

pub const RenderSystem = struct {
    allocator: std.mem.Allocator,
    backend: *backends.GraphicsBackend,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, backend: *backends.GraphicsBackend) Self {
        return Self{
            .allocator = allocator,
            .backend = backend,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Cleanup rendering resources
    }

    pub fn beginFrame(self: *Self) !void {
        try self.backend.beginFrame();
    }

    pub fn endFrame(self: *Self) !void {
        try self.backend.endFrame();
    }

    pub fn clear(self: *Self, color: [4]f32) !void {
        // TODO: Implement clear functionality
        _ = self;
        _ = color;
    }

    pub fn drawTriangles(self: *Self, vertices: []const f32, indices: []const u32) !void {
        // TODO: Implement triangle drawing
        _ = self;
        _ = vertices;
        _ = indices;
    }
};

// Re-export commonly used rendering types
pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
};

pub const DrawCommand = struct {
    vertex_buffer: *types.Buffer,
    index_buffer: ?*types.Buffer,
    vertex_count: u32,
    index_count: u32,
    pipeline: *types.Pipeline,
};

pub const ClearOptions = struct {
    color: [4]f32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 },
    depth: f32 = 1.0,
    stencil: u8 = 0,
};

// Utility functions
pub fn createQuadVertices(allocator: std.mem.Allocator) ![]Vertex {
    const vertices = try allocator.alloc(Vertex, 4);
    vertices[0] = Vertex{ .position = [3]f32{ -1.0, -1.0, 0.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .uv = [2]f32{ 0.0, 0.0 } };
    vertices[1] = Vertex{ .position = [3]f32{ 1.0, -1.0, 0.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .uv = [2]f32{ 1.0, 0.0 } };
    vertices[2] = Vertex{ .position = [3]f32{ 1.0, 1.0, 0.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .uv = [2]f32{ 1.0, 1.0 } };
    vertices[3] = Vertex{ .position = [3]f32{ -1.0, 1.0, 0.0 }, .normal = [3]f32{ 0.0, 0.0, 1.0 }, .uv = [2]f32{ 0.0, 1.0 } };
    return vertices;
}

pub fn createQuadIndices(allocator: std.mem.Allocator) ![]u32 {
    const indices = try allocator.alloc(u32, 6);
    indices[0] = 0;
    indices[1] = 1;
    indices[2] = 2;
    indices[3] = 2;
    indices[4] = 3;
    indices[5] = 0;
    return indices;
}
