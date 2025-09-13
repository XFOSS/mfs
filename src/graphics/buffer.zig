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

/// A region of a buffer with offset and size
pub const BufferRegion = struct {
    offset: usize,
    size: usize,
};

/// A handle to a suballocated buffer region
pub const BufferAllocation = struct {
    buffer: *Buffer,
    id: usize,
    offset: usize,
    size: usize,

    /// Update data in this allocation
    pub fn update(self: *const BufferAllocation, data: []const u8) !void {
        if (data.len > self.size) return BufferError.Overflow;
        return self.buffer.update(self.offset, data);
    }

    /// Update typed data in this allocation
    pub fn updateTyped(self: *const BufferAllocation, value: anytype) !void {
        const bytes = std.mem.asBytes(&value);
        return self.update(bytes);
    }

    /// Map this allocation for CPU access
    pub fn map(self: *const BufferAllocation) ![]u8 {
        const full_map = try self.buffer.map();
        return full_map[self.offset .. self.offset + self.size];
    }

    /// Release this allocation back to the pool
    pub fn free(self: *const BufferAllocation) void {
        self.buffer.free(self.id);
    }
};

/// A buffer that uses a ring allocation strategy for frequent updates
pub const RingBuffer = struct {
    allocator: Allocator,
    buffer: *Buffer,
    head: usize = 0,
    frame_allocations: std.AutoHashMap(u64, std.array_list.Managed(BufferRegion)),
    current_frame: u64 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, size: usize) !*Self {
        var buffer = try Buffer.init(allocator, size, .ring_buffer, .cpu_to_gpu);
        try buffer.initBuffer();

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .buffer = buffer,
            .frame_allocations = std.AutoHashMap(u64, std.array_list.Managed(BufferRegion)).init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        var it = self.frame_allocations.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.frame_allocations.deinit();
        self.buffer.deinit();
        self.allocator.destroy(self);
    }

    /// Begin a new frame
    pub fn beginFrame(self: *Self, frame_number: u64) void {
        self.current_frame = frame_number;

        // Clean up old allocations (typically from 2-3 frames ago to allow for GPU to finish)
        if (frame_number > 2) {
            _ = self.frame_allocations.remove(frame_number - 3);
        }
    }

    /// Allocate a region in the ring buffer
    pub fn allocate(self: *Self, size: usize, alignment: usize) !BufferAllocation {
        // Align the head pointer
        const aligned_head = (self.head + alignment - 1) & ~(alignment - 1);

        // Align the size
        const aligned_size = (size + alignment - 1) & ~(alignment - 1);

        // Check if we need to wrap around
        if (aligned_head + aligned_size > self.buffer.size) {
            // Wrap around - mark the rest of the buffer as used for this frame
            try self.recordAllocation(aligned_head, self.buffer.size - aligned_head);
            self.head = 0; // Reset to start of buffer
        }

        // Allocate from the current position
        const allocation = BufferAllocation{
            .buffer = self.buffer,
            .id = 0, // Ring buffer doesn't use IDs
            .offset = self.head,
            .size = aligned_size,
        };

        // Record this allocation
        try self.recordAllocation(self.head, aligned_size);

        // Update head pointer
        self.head = self.head + aligned_size;

        return allocation;
    }

    /// Record an allocation for the current frame
    fn recordAllocation(self: *Self, offset: usize, size: usize) !void {
        var frame_list = if (self.frame_allocations.get(self.current_frame)) |list|
            list
        else
            std.ArrayList(BufferRegion).init(self.allocator);

        try frame_list.append(BufferRegion{ .offset = offset, .size = size });
        try self.frame_allocations.put(self.current_frame, frame_list);
    }
};

/// A pool of similar-sized buffers for efficient allocation and reuse
pub const BufferPool = struct {
    allocator: Allocator,
    buffers: std.ArrayList(*Buffer),
    free_buffers: std.ArrayList(*Buffer),
    in_use_buffers: std.AutoHashMap(*Buffer, usize),
    buffer_type: BufferType,
    buffer_size: usize,
    access: MemoryAccess,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator, buffer_type: BufferType, buffer_size: usize, access: MemoryAccess) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .buffers = std.ArrayList(*Buffer).init(allocator),
            .free_buffers = std.ArrayList(*Buffer).init(allocator),
            .in_use_buffers = std.AutoHashMap(*Buffer, usize).init(allocator),
            .buffer_type = buffer_type,
            .buffer_size = buffer_size,
            .access = access,
            .mutex = .{},
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.buffers.items) |buffer| {
            buffer.deinit();
        }

        self.buffers.deinit();
        self.free_buffers.deinit();
        self.in_use_buffers.deinit();
        self.allocator.destroy(self);
    }

    /// Get a buffer from the pool
    pub fn acquire(self: *Self) !*Buffer {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Try to get a free buffer
        if (self.free_buffers.items.len > 0) {
            const buffer = self.free_buffers.pop();
            try self.in_use_buffers.put(buffer, 1);
            return buffer;
        }

        // Create a new buffer
        const buffer = try Buffer.init(self.allocator, self.buffer_size, self.buffer_type, self.access);
        try buffer.initBuffer();

        try self.buffers.append(buffer);
        try self.in_use_buffers.put(buffer, 1);

        return buffer;
    }

    /// Return a buffer to the pool
    pub fn release(self: *Self, buffer: *Buffer) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.in_use_buffers.fetchSwapRemove(buffer)) |_| {
            // Return to free list
            self.free_buffers.append(buffer) catch {};
        }
    }

    /// Shrink the pool by removing excess free buffers
    pub fn shrink(self: *Self, max_free: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.free_buffers.items.len > max_free) {
            if (self.free_buffers.popOrNull()) |buffer| {
                // Find and remove from the buffers list
                for (self.buffers.items, 0..) |buf, i| {
                    if (buf == buffer) {
                        _ = self.buffers.swapRemove(i);
                        break;
                    }
                }

                // Free the buffer
                buffer.deinit();
            }
        }
    }
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
    /// Ring buffer for frequently updated data
    ring_buffer,
    /// For buffer suballocation
    allocation_pool,
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

    /// Get the optimal buffer usage flags for this access type
    /// @thread-safe Thread-safe utility function
    /// @symbol Internal memory access helper
    pub fn getOptimalFlags(self: MemoryAccess) BufferUsageFlags {
        return switch (self) {
            .gpu_only => .{ .transfer_dst = true },
            .cpu_to_gpu => .{ .transfer_dst = true },
            .gpu_to_cpu => .{ .transfer_src = true },
            .cpu_and_gpu => .{ .transfer_src = true, .transfer_dst = true },
        };
    }
};

/// Memory alignment requirements
pub const BufferAlignment = struct {
    /// Minimum alignment for uniform buffers
    pub const uniform: usize = 256;
    /// Minimum alignment for storage buffers
    pub const storage: usize = 16;
    /// Minimum alignment for general data
    pub const general: usize = 4;

    /// Get alignment for a specific buffer type
    pub fn forType(buffer_type: BufferType) usize {
        return switch (buffer_type) {
            .uniform => uniform,
            .shader_storage => storage,
            else => general,
        };
    }
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
    last_used_frame: u64 = 0,
    // For allocation pools/suballocation
    is_pool: bool = false,
    free_regions: ?std.ArrayList(BufferRegion) = null,
    allocations: ?std.AutoArrayHashMap(usize, BufferRegion) = null,
    alignment: usize = 4,

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
            .alignment = BufferAlignment.forType(buffer_type),
            .last_used_frame = 0,
        };

        return self;
    }

    /// Create a buffer allocation pool for suballocations
    pub fn initPool(allocator: Allocator, size: usize, buffer_type: BufferType, access: MemoryAccess, alignment: usize) !*Self {
        if (size == 0) return BufferError.InvalidSize;

        var self = try init(allocator, size, buffer_type, access);
        self.is_pool = true;
        self.alignment = alignment;
        self.free_regions = std.ArrayList(BufferRegion).init(allocator);
        self.allocations = std.AutoArrayHashMap(usize, BufferRegion).init(allocator);

        // Initially the entire buffer is free
        try self.free_regions.?.append(BufferRegion{ .offset = 0, .size = size });

        try self.initBuffer();

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

        if (self.free_regions) |*regions| {
            regions.deinit();
        }

        if (self.allocations) |*allocs| {
            allocs.deinit();
        }

        self.allocator.destroy(self);
    }

    /// Mark this buffer as used in the current frame
    pub fn markUsed(self: *Self, frame_number: u64) void {
        self.last_used_frame = frame_number;
    }

    /// Update buffer contents
    pub fn update(self: *Self, offset: usize, data: []const u8) !void {
        if (self.buffer == null) return BufferError.InvalidOperation;
        if (offset + data.len > self.size) return BufferError.Overflow;

        try gpu.updateBuffer(self.buffer.?, @intCast(offset), data);
    }

    /// Update a typed value
    pub fn updateTyped(self: *Self, offset: usize, value: anytype) !void {
        const bytes = std.mem.asBytes(&value);
        return self.update(offset, bytes);
    }

    /// Map buffer for CPU access
    pub fn map(self: *Self) ![]u8 {
        if (self.buffer == null) return BufferError.InvalidOperation;
        if (self.mapped) return self.mapped_data.?;

        if (self.access == .gpu_only) {
            return BufferError.InvalidOperation;
        }

        // In a real implementation, this would interact with the backend to map memory
        // For now, we'll simulate mapping by allocating memory
        self.mapped_data = try self.allocator.alloc(u8, self.size);
        self.mapped = true;

        // If reading from GPU, we would fetch the latest data here
        if (self.access == .gpu_to_cpu or self.access == .cpu_and_gpu) {
            // This is a placeholder for fetching data from GPU
            // In a real implementation, this would copy from the GPU
        }

        return self.mapped_data.?;
    }

    /// Map a specific region of the buffer
    pub fn mapRange(self: *Self, offset: usize, size: usize) ![]u8 {
        if (offset + size > self.size) return BufferError.Overflow;

        const full_map = try self.map();
        return full_map[offset .. offset + size];
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

    /// Suballocate from this buffer pool
    pub fn allocate(self: *Self, size: usize) !BufferAllocation {
        if (!self.is_pool) return BufferError.InvalidOperation;

        // Align the size to the required alignment
        const aligned_size = (size + self.alignment - 1) & ~(self.alignment - 1);

        // Find a suitable free region using best-fit allocation
        var best_fit_idx: ?usize = null;
        var smallest_viable_size: usize = std.math.maxInt(usize);

        for (self.free_regions.?.items, 0..) |region, i| {
            if (region.size >= aligned_size and region.size < smallest_viable_size) {
                smallest_viable_size = region.size;
                best_fit_idx = i;
            }
        }

        if (best_fit_idx == null) {
            return BufferError.OutOfMemory;
        }

        // Get the selected region
        const region = self.free_regions.?.items[best_fit_idx.?];

        // Create the allocation
        const id = @as(usize, @truncate(@intFromPtr(self))) ^ self.allocations.?.count();
        const allocation = BufferAllocation{
            .buffer = self,
            .id = id,
            .offset = region.offset,
            .size = aligned_size,
        };

        // Store the allocation
        try self.allocations.?.put(id, BufferRegion{
            .offset = region.offset,
            .size = aligned_size,
        });

        // Update the free region
        if (region.size == aligned_size) {
            // Exact fit - remove the region entirely
            _ = self.free_regions.?.orderedRemove(best_fit_idx.?);
        } else {
            // Partial fit - shrink the region
            self.free_regions.?.items[best_fit_idx.?] = BufferRegion{
                .offset = region.offset + aligned_size,
                .size = region.size - aligned_size,
            };
        }

        return allocation;
    }

    /// Free a suballocation
    pub fn free(self: *Self, allocation_id: usize) void {
        if (!self.is_pool) return;

        if (self.allocations.?.fetchSwapRemove(allocation_id)) |kv| {
            const freed_region = kv.value;

            // Add back to free regions
            // In a real implementation, we would coalesce adjacent free regions
            self.free_regions.?.append(freed_region) catch {};
        }
    }

    /// Get total amount of free memory in the pool
    pub fn getFreeSize(self: *Self) usize {
        if (!self.is_pool) return 0;

        var total: usize = 0;
        for (self.free_regions.?.items) |region| {
            total += region.size;
        }
        return total;
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
    /// For memory tracking
    memory_type: enum { dedicated, suballocated } = .dedicated,
    allocation: ?BufferAllocation = null,

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

    /// Create a vertex buffer from a pool allocation
    pub fn initFromAllocation(allocator: Allocator, allocation: BufferAllocation, vertex_size: u32) !*Self {
        const vertex_count = @as(u32, @intCast(allocation.size / vertex_size));

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = allocation.buffer,
            .vertex_count = vertex_count,
            .vertex_size = vertex_size,
            .memory_type = .suballocated,
            .allocation = allocation,
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
        // Only free the buffer if it's dedicated
        if (self.memory_type == .dedicated) {
            self.buffer.deinit();
        } else if (self.allocation != null) {
            // Free the allocation if it's suballocated
            self.allocation.?.free();
        }

        self.buffer.allocator.destroy(self);
    }

    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer, slot: u32) !void {
        const offset = if (self.memory_type == .suballocated and self.allocation != null)
            self.allocation.?.offset
        else
            0;

        try gpu.bindVertexBuffer(cmd, slot, self.buffer.buffer.?, offset);
    }

    /// Update vertex data
    pub fn update(self: *Self, offset: u32, vertices: []const u8) !void {
        if (offset + @as(u32, @intCast(vertices.len)) > self.vertex_count * self.vertex_size) {
            return BufferError.Overflow;
        }

        const buffer_offset = if (self.memory_type == .suballocated and self.allocation != null)
            self.allocation.?.offset + offset
        else
            offset;

        return self.buffer.update(buffer_offset, vertices);
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
    /// For memory tracking
    memory_type: enum { dedicated, suballocated } = .dedicated,
    allocation: ?BufferAllocation = null,

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

    /// Create an index buffer from a pool allocation
    pub fn initFromAllocation(allocator: Allocator, allocation: BufferAllocation, format: interface.IndexFormat) !*Self {
        const element_size: usize = if (format == .uint16) 2 else 4;
        const index_count = @as(u32, @intCast(allocation.size / element_size));

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = allocation.buffer,
            .index_count = index_count,
            .index_format = format,
            .memory_type = .suballocated,
            .allocation = allocation,
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
        // Only free the buffer if it's dedicated
        if (self.memory_type == .dedicated) {
            self.buffer.deinit();
        } else if (self.allocation != null) {
            // Free the allocation if it's suballocated
            self.allocation.?.free();
        }

        self.buffer.allocator.destroy(self);
    }

    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer) !void {
        const offset = if (self.memory_type == .suballocated and self.allocation != null)
            self.allocation.?.offset
        else
            0;

        try gpu.bindIndexBuffer(cmd, self.buffer.buffer.?, offset, self.index_format);
    }

    /// Update index data
    pub fn update(self: *Self, offset_indices: u32, indices: []const u8) !void {
        const element_size: usize = if (self.index_format == .uint16) 2 else 4;
        const offset_bytes = offset_indices * element_size;

        if (offset_indices + @as(u32, @intCast(indices.len / element_size)) > self.index_count) {
            return BufferError.Overflow;
        }

        const buffer_offset = if (self.memory_type == .suballocated and self.allocation != null)
            self.allocation.?.offset + offset_bytes
        else
            offset_bytes;

        return self.buffer.update(buffer_offset, indices);
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
    /// For memory tracking
    memory_type: enum { dedicated, suballocated } = .dedicated,
    allocation: ?BufferAllocation = null,

    const Self = @This();

    pub fn init(allocator: Allocator, size: usize, binding_slot: u32) !*Self {
        // Ensure size is aligned to uniform buffer requirements
        const aligned_size = (size + BufferAlignment.uniform - 1) & ~(BufferAlignment.uniform - 1);

        var buffer = try Buffer.init(allocator, aligned_size, .uniform, .cpu_to_gpu);
        errdefer buffer.deinit();

        try buffer.initBuffer();

        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = buffer,
            .binding_slot = binding_slot,
        };

        return self;
    }

    /// Create a uniform buffer from a pool allocation
    pub fn initFromAllocation(allocator: Allocator, allocation: BufferAllocation, binding_slot: u32) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = allocation.buffer,
            .binding_slot = binding_slot,
            .memory_type = .suballocated,
            .allocation = allocation,
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
        // Only free the buffer if it's dedicated
        if (self.memory_type == .dedicated) {
            self.buffer.deinit();
        } else if (self.allocation != null) {
            // Free the allocation if it's suballocated
            self.allocation.?.free();
        }

        self.buffer.allocator.destroy(self);
    }

    pub fn update(self: *Self, data: []const u8) !void {
        const offset = if (self.memory_type == .suballocated and self.allocation != null)
            self.allocation.?.offset
        else
            0;

        try self.buffer.update(offset, data);
    }

    pub fn updateTyped(self: *Self, data: anytype) !void {
        const bytes = std.mem.asBytes(&data);
        try self.update(bytes);
    }

    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer) !void {
        const offset = if (self.memory_type == .suballocated and self.allocation != null)
            self.allocation.?.offset
        else
            0;

        const size = if (self.memory_type == .suballocated and self.allocation != null)
            self.allocation.?.size
        else
            self.buffer.size;

        try gpu.bindUniformBuffer(cmd, self.binding_slot, self.buffer.buffer.?, offset, size);
    }

    /// Map the uniform buffer for CPU writing
    pub fn map(self: *Self) ![]u8 {
        if (self.memory_type == .suballocated and self.allocation != null) {
            return self.allocation.?.map();
        } else {
            return self.buffer.map();
        }
    }

    /// Unmap the uniform buffer
    pub fn unmap(self: *Self) void {
        if (self.memory_type != .suballocated) {
            self.buffer.unmap();
        }
    }
};

/// Helper function to create a buffer that's properly aligned for GPU use
pub fn createAlignedBuffer(comptime T: type, allocator: Allocator, binding_slot: u32) !*UniformBuffer {
    // Calculate the aligned size
    const base_size = @sizeOf(T);
    const aligned_size = (base_size + BufferAlignment.uniform - 1) & ~(BufferAlignment.uniform - 1);

    // Create the buffer with the aligned size
    return UniformBuffer.init(allocator, aligned_size, binding_slot);
}

/// Setup a global buffer memory manager for efficient memory usage
pub const BufferMemoryManager = struct {
    allocator: Allocator,
    // Pools for common buffer types
    vertex_pool: *Buffer,
    index_pool: *Buffer,
    uniform_pool: *Buffer,
    storage_pool: *Buffer,
    // Specialized buffer pools
    uniform_buffer_pools: std.AutoHashMap(usize, *BufferPool),
    mutex: std.Thread.Mutex,
    // Ring buffer for per-frame data
    frame_ring: *RingBuffer,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        // Create large allocation pools
        const vertex_pool = try Buffer.initPool(allocator, 64 * 1024 * 1024, .vertex, .cpu_to_gpu, 16);
        const index_pool = try Buffer.initPool(allocator, 32 * 1024 * 1024, .index, .cpu_to_gpu, 4);
        const uniform_pool = try Buffer.initPool(allocator, 16 * 1024 * 1024, .uniform, .cpu_to_gpu, BufferAlignment.uniform);
        const storage_pool = try Buffer.initPool(allocator, 32 * 1024 * 1024, .shader_storage, .cpu_to_gpu, BufferAlignment.storage);

        // Create frame ring buffer
        const frame_ring = try RingBuffer.init(allocator, 8 * 1024 * 1024);

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .vertex_pool = vertex_pool,
            .index_pool = index_pool,
            .uniform_pool = uniform_pool,
            .storage_pool = storage_pool,
            .uniform_buffer_pools = std.AutoHashMap(usize, *BufferPool).init(allocator),
            .mutex = .{},
            .frame_ring = frame_ring,
        };

        return self;
    }
};

/// Global buffer memory manager singleton
/// @thread-safe All public functions are thread-safe
/// @symbol Global buffer management system
var global_buffer_manager: ?*BufferMemoryManager = null;

/// Initialize the global buffer memory manager
/// @thread-safe Thread-safe initialization with null check
/// @symbol Public global memory manager API
pub fn initGlobalBufferManager(allocator: Allocator) !void {
    if (global_buffer_manager != null) return;

    global_buffer_manager = try BufferMemoryManager.init(allocator);
}

/// Deinitialize the global buffer memory manager
/// @thread-safe Thread-safe cleanup
/// @symbol Public global memory manager API
pub fn deinitGlobalBufferManager() void {
    if (global_buffer_manager) |manager| {
        manager.deinit();
        global_buffer_manager = null;
    }
}

/// Get the global buffer manager
/// @thread-safe Thread-safe access to global instance
/// @symbol Public global accessor API
pub fn getGlobalBufferManager() !*BufferMemoryManager {
    return global_buffer_manager orelse return BufferError.InvalidOperation;
}

/// Clean up all buffer pool resources
/// @thread-safe Not thread-safe, external synchronization required
/// @symbol Public cleanup API
pub fn deinit(self: *BufferMemoryManager) void {
    self.vertex_pool.deinit();
    self.index_pool.deinit();
    self.uniform_pool.deinit();
    self.storage_pool.deinit();

    var it = self.uniform_buffer_pools.valueIterator();
    while (it.next()) |pool| {
        pool.*.deinit();
    }
    self.uniform_buffer_pools.deinit();

    self.frame_ring.deinit();
    self.allocator.destroy(self);
}

/// Begin a new frame for ring buffer allocations
pub fn beginFrame(self: *BufferMemoryManager, frame_number: u64) void {
    self.frame_ring.beginFrame(frame_number);
}

/// Allocate per-frame data from ring buffer
pub fn allocateFrameData(self: *BufferMemoryManager, size: usize) ![]u8 {
    const allocation = try self.frame_ring.allocate(size, 16);
    return try allocation.map();
}

/// Allocate a uniform buffer from the pool
pub fn allocateUniformBuffer(self: *BufferMemoryManager, size: usize, binding_slot: u32) !*UniformBuffer {
    // Ensure size is aligned to uniform buffer requirements
    const aligned_size = (size + BufferAlignment.uniform - 1) & ~(BufferAlignment.uniform - 1);

    const allocation = try self.uniform_pool.allocate(aligned_size);

    return UniformBuffer.initFromAllocation(self.allocator, allocation, binding_slot);
}

/// Allocate an index buffer from the pool
pub fn allocateIndexBuffer(self: *BufferMemoryManager, index_count: u32, format: interface.IndexFormat) !*IndexBuffer {
    const element_size: usize = if (format == .uint16) 2 else 4;
    const size = @as(usize, index_count) * element_size;

    const allocation = try self.index_pool.allocate(size);

    return IndexBuffer.initFromAllocation(self.allocator, allocation, format);
}

/// Allocate a vertex buffer from the pool
/// @thread-safe Thread-safe allocation
/// @symbol Public vertex buffer allocation API
pub fn allocateVertexBuffer(self: *BufferMemoryManager, vertex_count: u32, vertex_size: u32) !*VertexBuffer {
    const size = @as(usize, vertex_count) * @as(usize, vertex_size);

    const allocation = try self.vertex_pool.allocate(size);

    return VertexBuffer.initFromAllocation(self.allocator, allocation, vertex_size);
}

/// Get a pool for uniform buffers of a specific size
/// @thread-safe Thread-safe with internal mutex protection
/// @symbol Internal pool management API
pub fn getUniformBufferPool(self: *BufferMemoryManager, size: usize) !*BufferPool {
    self.mutex.lock();
    defer self.mutex.unlock();

    // Round up to the nearest aligned size
    const aligned_size = (size + BufferAlignment.uniform - 1) & ~(BufferAlignment.uniform - 1);

    if (self.uniform_buffer_pools.get(aligned_size)) |pool| {
        return pool;
    }

    // Create a new pool
    const pool = try BufferPool.init(self.allocator, .uniform, aligned_size, .cpu_to_gpu);
    try self.uniform_buffer_pools.put(aligned_size, pool);

    return pool;
}
