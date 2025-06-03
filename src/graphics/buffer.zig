const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu.zig");
const types = @import("types.zig");
const interface = @import("backends/interface.zig");

pub const BufferError = error{
    CreationFailed,
    InvalidSize,
    InvalidOffset,
    InvalidOperation,
    OutOfMemory,
    Overflow,
};

/// BufferType provides a more specific usage classification than the raw BufferUsage
pub const BufferType = enum {
    vertex,
    index,
    uniform,
    shader_storage,
    indirect,
    staging,
    readback,
};

/// BufferUsageFlags defines how a buffer can be used in combination
pub const BufferUsageFlags = packed struct {
    vertex_buffer: bool = false,
    index_buffer: bool = false,
    uniform_buffer: bool = false,
    storage_buffer: bool = false,
    indirect_buffer: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
    _padding: u25 = 0,

    /// Create usage flags from a primary buffer type
    pub fn fromType(buffer_type: BufferType) BufferUsageFlags {
        return switch (buffer_type) {
            .vertex => .{ .vertex_buffer = true, .transfer_dst = true },
            .index => .{ .index_buffer = true, .transfer_dst = true },
            .uniform => .{ .uniform_buffer = true, .transfer_dst = true },
            .shader_storage => .{ .storage_buffer = true, .transfer_dst = true },
            .indirect => .{ .indirect_buffer = true, .transfer_dst = true },
            .staging => .{ .transfer_src = true, .transfer_dst = true },
            .readback => .{ .transfer_dst = true },
        };
    }

    /// Convert to the simplified BufferUsage enum used by the backend
    pub fn toBufferUsage(self: BufferUsageFlags) gpu.BufferUsage {
        if (self.vertex_buffer) return .vertex;
        if (self.index_buffer) return .index;
        if (self.uniform_buffer) return .uniform;
        if (self.storage_buffer) return .storage;
        if (self.transfer_src) return .staging;
        return .vertex; // Default
    }
};

/// Memory access type for buffers
pub const MemoryAccess = enum {
    gpu_only, // Only accessible by GPU, fastest
    cpu_to_gpu, // CPU can write, GPU can read
    gpu_to_cpu, // GPU can write, CPU can read (slower)
    cpu_and_gpu, // Both CPU and GPU can read and write (slowest)
};

/// Generic buffer object that wraps the raw backend buffer
pub const Buffer = struct {
    allocator: Allocator,
    buffer: ?*gpu.Buffer = null,
    size: usize,
    usage: BufferUsageFlags,
    access: MemoryAccess,
    mapped: bool = false,
    mapped_data: ?[]u8 = null,

    const Self = @This();

    /// Create a buffer with the specified size and usage
    pub fn init(allocator: Allocator, size: usize, buffer_type: BufferType, access: MemoryAccess) !*Self {
        if (size == 0) return BufferError.InvalidSize;

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .size = size,
            .usage = BufferUsageFlags.fromType(buffer_type),
            .access = access,
        };

        return self;
    }

    /// Initialize the GPU buffer without data
    pub fn initBuffer(self: *Self) !void {
        if (self.buffer != null) {
            self.buffer.?.deinit();
            self.buffer = null;
        }

        const usage = self.usage.toBufferUsage();
        self.buffer = try gpu.createBuffer(self.size, usage, null);
    }

    /// Initialize the GPU buffer with initial data
    pub fn initWithData(self: *Self, data: []const u8) !void {
        if (data.len > self.size) return BufferError.InvalidSize;

        if (self.buffer != null) {
            self.buffer.?.deinit();
            self.buffer = null;
        }

        const usage = self.usage.toBufferUsage();
        self.buffer = try gpu.createBuffer(self.size, usage, data);
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.mapped) {
            self.unmap();
        }

        if (self.buffer != null) {
            self.buffer.?.deinit();
            self.buffer = null;
        }

        self.allocator.destroy(self);
    }

    /// Update buffer contents
    pub fn update(self: *Self, offset: usize, data: []const u8) !void {
        if (self.buffer == null) return BufferError.InvalidOperation;
        if (offset + data.len > self.size) return BufferError.Overflow;

        try gpu.updateBuffer(self.buffer.?, @intCast(offset), data);
    }

    /// Map buffer for CPU access
    pub fn map(self: *Self) ![]u8 {
        if (self.buffer == null) return BufferError.InvalidOperation;
        if (self.mapped) return self.mapped_data.?;

        // In a real implementation, this would interact with the backend to map memory
        // For now, we'll simulate mapping by allocating memory
        self.mapped_data = try self.allocator.alloc(u8, self.size);
        self.mapped = true;

        return self.mapped_data.?;
    }

    /// Unmap buffer
    pub fn unmap(self: *Self) void {
        if (!self.mapped) return;

        // In a real implementation, we would apply changes to the GPU buffer
        if (self.access != .gpu_to_cpu) {
            gpu.updateBuffer(self.buffer.?, 0, self.mapped_data.?) catch {};
        }

        self.allocator.free(self.mapped_data.?);
        self.mapped_data = null;
        self.mapped = false;
    }

    /// Copy from another buffer
    pub fn copyFrom(self: *Self, cmd: *gpu.CommandBuffer, source: *Buffer, src_offset: usize, dst_offset: usize, size: usize) !void {
        if (self.buffer == null or source.buffer == null) return BufferError.InvalidOperation;
        if (src_offset + size > source.size or dst_offset + size > self.size) return BufferError.Overflow;

        const region = interface.BufferCopyRegion{
            .src_offset = @intCast(src_offset),
            .dst_offset = @intCast(dst_offset),
            .size = @intCast(size),
        };

        try gpu.copyBuffer(cmd, source.buffer.?, self.buffer.?, &region);
    }
};

/// Specialized buffer for vertex data
pub const VertexBuffer = struct {
    buffer: *Buffer,
    vertex_count: u32,
    vertex_size: u32,
    layout: ?interface.VertexLayout = null,

    const Self = @This();

    pub fn init(allocator: Allocator, vertex_count: u32, vertex_size: u32, access: MemoryAccess) !*Self {
        const size = @as(usize, vertex_count) * @as(usize, vertex_size);
        var buffer = try Buffer.init(allocator, size, .vertex, access);
        errdefer buffer.deinit();

        try buffer.initBuffer();

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = buffer,
            .vertex_count = vertex_count,
            .vertex_size = vertex_size,
        };

        return self;
    }

    pub fn initWithData(allocator: Allocator, vertices: []const u8, vertex_size: u32, access: MemoryAccess) !*Self {
        if (vertices.len % vertex_size != 0) return BufferError.InvalidSize;

        const vertex_count = @as(u32, @intCast(vertices.len / vertex_size));
        var buffer = try Buffer.init(allocator, vertices.len, .vertex, access);
        errdefer buffer.deinit();

        try buffer.initWithData(vertices);

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = buffer,
            .vertex_count = vertex_count,
            .vertex_size = vertex_size,
        };

        return self;
    }

    pub fn setLayout(self: *Self, layout: interface.VertexLayout) void {
        self.layout = layout;
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.buffer.allocator.destroy(self);
    }

    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer, slot: u32) !void {
        try gpu.bindVertexBuffer(cmd, slot, self.buffer.buffer.?, 0);
    }

    pub fn draw(self: *Self, cmd: *gpu.CommandBuffer) !void {
        const options = gpu.DrawOptions{
            .vertex_count = self.vertex_count,
            .instance_count = 1,
            .first_vertex = 0,
            .first_instance = 0,
        };
        try gpu.draw(cmd, options);
    }
};

/// Specialized buffer for index data
pub const IndexBuffer = struct {
    buffer: *Buffer,
    index_count: u32,
    index_format: interface.IndexFormat,

    const Self = @This();

    pub fn init(allocator: Allocator, index_count: u32, format: interface.IndexFormat, access: MemoryAccess) !*Self {
        const element_size: usize = if (format == .uint16) 2 else 4;
        const size = @as(usize, index_count) * element_size;

        var buffer = try Buffer.init(allocator, size, .index, access);
        errdefer buffer.deinit();

        try buffer.initBuffer();

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = buffer,
            .index_count = index_count,
            .index_format = format,
        };

        return self;
    }

    pub fn initWithData(allocator: Allocator, indices: []const u8, format: interface.IndexFormat, access: MemoryAccess) !*Self {
        const element_size: usize = if (format == .uint16) 2 else 4;
        if (indices.len % element_size != 0) return BufferError.InvalidSize;

        const index_count = @as(u32, @intCast(indices.len / element_size));
        var buffer = try Buffer.init(allocator, indices.len, .index, access);
        errdefer buffer.deinit();

        try buffer.initWithData(indices);

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = buffer,
            .index_count = index_count,
            .index_format = format,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.buffer.allocator.destroy(self);
    }

    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer) !void {
        try gpu.bindIndexBuffer(cmd, self.buffer.buffer.?, 0, self.index_format);
    }

    pub fn draw(self: *Self, cmd: *gpu.CommandBuffer) !void {
        const options = gpu.DrawIndexedOptions{
            .index_count = self.index_count,
            .instance_count = 1,
            .first_index = 0,
            .vertex_offset = 0,
            .first_instance = 0,
        };
        try gpu.drawIndexed(cmd, options);
    }
};

/// Specialized buffer for uniform data
pub const UniformBuffer = struct {
    buffer: *Buffer,
    binding_slot: u32,

    const Self = @This();

    pub fn init(allocator: Allocator, size: usize, binding_slot: u32) !*Self {
        var buffer = try Buffer.init(allocator, size, .uniform, .cpu_to_gpu);
        errdefer buffer.deinit();

        try buffer.initBuffer();

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = buffer,
            .binding_slot = binding_slot,
        };

        return self;
    }

    pub fn initWithData(allocator: Allocator, data: []const u8, binding_slot: u32) !*Self {
        var buffer = try Buffer.init(allocator, data.len, .uniform, .cpu_to_gpu);
        errdefer buffer.deinit();

        try buffer.initWithData(data);

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = buffer,
            .binding_slot = binding_slot,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.buffer.allocator.destroy(self);
    }

    pub fn update(self: *Self, data: []const u8) !void {
        try self.buffer.update(0, data);
    }

    pub fn updateTyped(self: *Self, data: anytype) !void {
        const bytes = std.mem.asBytes(&data);
        try self.update(bytes);
    }

    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer) !void {
        try gpu.bindUniformBuffer(cmd, self.binding_slot, self.buffer.buffer.?, 0, self.buffer.size);
    }
};

/// Helper function to create a buffer that's properly aligned for GPU use
pub fn createAlignedBuffer(comptime T: type, allocator: Allocator, binding_slot: u32) !*UniformBuffer {
    // Get the required alignment for uniform buffers
    const alignment = 256; // Common alignment requirement, would be queried from GPU in actual implementation

    // Calculate the aligned size
    const base_size = @sizeOf(T);
    const aligned_size = (base_size + alignment - 1) & ~(alignment - 1);

    // Create the buffer with the aligned size
    return UniformBuffer.init(allocator, aligned_size, binding_slot);
}
