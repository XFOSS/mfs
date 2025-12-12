const std = @import("std");
const Allocator = std.mem.Allocator;
const VoxelType = @import("./types.zig").VoxelType;
const VoxelMaterial = @import("./types.zig").VoxelMaterial;
const math = @import("math");
const Vec3 = math.Vec3;
const ArrayList = std.array_list.Managed;

pub const VoxelChunk = struct {
    allocator: Allocator,
    position: ChunkPosition,
    size: u32,
    voxels: []VoxelType,
    materials: []VoxelMaterial,
    dirty: bool = true,
    generated: bool = false,
    mesh_version: u32 = 0,
    last_access: i64,
    compressed_data: ?[]u8 = null,
    lod_level: u8 = 0,

    pub fn init(allocator: Allocator, position: ChunkPosition, size: u32) !VoxelChunk {
        const voxel_count = size * size * size;
        const voxels = try allocator.alloc(VoxelType, voxel_count);
        const materials = try allocator.alloc(VoxelMaterial, voxel_count);

        // Initialize with air
        @memset(voxels, .air);
        for (materials, 0..) |*material, i| {
            _ = i;
            material.* = VoxelMaterial.init(.air);
        }

        return VoxelChunk{
            .allocator = allocator,
            .position = position,
            .size = size,
            .voxels = voxels,
            .materials = materials,
            .last_access = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *VoxelChunk) void {
        self.allocator.free(self.voxels);
        self.allocator.free(self.materials);
        if (self.compressed_data) |data| {
            self.allocator.free(data);
        }
    }

    pub fn getVoxelIndex(self: *const VoxelChunk, x: u32, y: u32, z: u32) ?usize {
        if (x >= self.size or y >= self.size or z >= self.size) return null;
        return y * self.size * self.size + z * self.size + x;
    }

    pub fn getVoxel(self: *const VoxelChunk, x: u32, y: u32, z: u32) VoxelType {
        if (self.getVoxelIndex(x, y, z)) |index| {
            return self.voxels[index];
        }
        return .air;
    }

    pub fn setVoxel(self: *VoxelChunk, x: u32, y: u32, z: u32, voxel_type: VoxelType) void {
        if (self.getVoxelIndex(x, y, z)) |index| {
            if (self.voxels[index] != voxel_type) {
                self.voxels[index] = voxel_type;
                self.materials[index] = VoxelMaterial.init(voxel_type);
                self.dirty = true;
                self.last_access = std.time.timestamp();
            }
        }
    }

    pub fn getMaterial(self: *const VoxelChunk, x: u32, y: u32, z: u32) VoxelMaterial {
        if (self.getVoxelIndex(x, y, z)) |index| {
            return self.materials[index];
        }
        return VoxelMaterial.init(.air);
    }

    pub fn setMaterial(self: *VoxelChunk, x: u32, y: u32, z: u32, material: VoxelMaterial) void {
        if (self.getVoxelIndex(x, y, z)) |index| {
            self.materials[index] = material;
            self.voxels[index] = material.voxel_type;
            self.dirty = true;
            self.last_access = std.time.timestamp();
        }
    }

    pub fn fill(self: *VoxelChunk, voxel_type: VoxelType) void {
        @memset(self.voxels, voxel_type);
        const material = VoxelMaterial.init(voxel_type);
        for (self.materials) |*mat| {
            mat.* = material;
        }
        self.dirty = true;
        self.last_access = std.time.timestamp();
    }

    pub fn fillRegion(self: *VoxelChunk, min_x: u32, min_y: u32, min_z: u32, max_x: u32, max_y: u32, max_z: u32, voxel_type: VoxelType) void {
        const end_x = @min(max_x, self.size);
        const end_y = @min(max_y, self.size);
        const end_z = @min(max_z, self.size);

        var y = min_y;
        while (y < end_y) : (y += 1) {
            var z = min_z;
            while (z < end_z) : (z += 1) {
                var x = min_x;
                while (x < end_x) : (x += 1) {
                    self.setVoxel(x, y, z, voxel_type);
                }
            }
        }
    }

    pub fn sphere(self: *VoxelChunk, center_x: f32, center_y: f32, center_z: f32, radius: f32, voxel_type: VoxelType) void {
        const center = Vec3{ .x = center_x, .y = center_y, .z = center_z };
        const radius_sq = radius * radius;

        var y: u32 = 0;
        while (y < self.size) : (y += 1) {
            var z: u32 = 0;
            while (z < self.size) : (z += 1) {
                var x: u32 = 0;
                while (x < self.size) : (x += 1) {
                    const pos = Vec3{
                        .x = @as(f32, @floatFromInt(x)),
                        .y = @as(f32, @floatFromInt(y)),
                        .z = @as(f32, @floatFromInt(z)),
                    };
                    const dist_sq = (pos.x - center.x) * (pos.x - center.x) +
                        (pos.y - center.y) * (pos.y - center.y) +
                        (pos.z - center.z) * (pos.z - center.z);

                    if (dist_sq <= radius_sq) {
                        self.setVoxel(x, y, z, voxel_type);
                    }
                }
            }
        }
    }

    pub fn isEmpty(self: *const VoxelChunk) bool {
        for (self.voxels) |voxel| {
            if (voxel != .air) return false;
        }
        return true;
    }

    pub fn isFull(self: *const VoxelChunk, voxel_type: VoxelType) bool {
        for (self.voxels) |voxel| {
            if (voxel != voxel_type) return false;
        }
        return true;
    }

    pub fn getVoxelCount(self: *const VoxelChunk, voxel_type: VoxelType) u32 {
        var count: u32 = 0;
        for (self.voxels) |voxel| {
            if (voxel == voxel_type) count += 1;
        }
        return count;
    }

    pub fn compress(self: *VoxelChunk) !void {
        if (self.compressed_data != null) return;

        // Simple RLE compression
        var compressed = ArrayList(u8).init(self.allocator);
        defer compressed.deinit();

        if (self.voxels.len == 0) return;

        var current_voxel = self.voxels[0];
        var count: u8 = 1;

        for (self.voxels[1..]) |voxel| {
            if (voxel == current_voxel and count < 255) {
                count += 1;
            } else {
                try compressed.append(@intFromEnum(current_voxel));
                try compressed.append(count);
                current_voxel = voxel;
                count = 1;
            }
        }

        // Write final run
        try compressed.append(@intFromEnum(current_voxel));
        try compressed.append(count);

        self.compressed_data = try compressed.toOwnedSlice();
    }

    pub fn decompress(self: *VoxelChunk) !void {
        const data = self.compressed_data orelse return;
        defer {
            self.allocator.free(data);
            self.compressed_data = null;
        }

        var index: usize = 0;
        var i: usize = 0;
        while (i < data.len and index < self.voxels.len) {
            const voxel_type = @as(VoxelType, @enumFromInt(data[i]));
            const count = data[i + 1];

            var j: u8 = 0;
            while (j < count and index < self.voxels.len) : (j += 1) {
                self.voxels[index] = voxel_type;
                self.materials[index] = VoxelMaterial.init(voxel_type);
                index += 1;
            }

            i += 2;
        }
    }

    pub fn calculateLOD(self: *const VoxelChunk, view_position: Vec3) u8 {
        const chunk_center = self.position.toWorldPosition(self.size);
        const chunk_center_offset = Vec3{
            .x = chunk_center.x + @as(f32, @floatFromInt(self.size)) * 0.5,
            .y = chunk_center.y + @as(f32, @floatFromInt(self.size)) * 0.5,
            .z = chunk_center.z + @as(f32, @floatFromInt(self.size)) * 0.5,
        };

        const distance_sq = (view_position.x - chunk_center_offset.x) * (view_position.x - chunk_center_offset.x) +
            (view_position.y - chunk_center_offset.y) * (view_position.y - chunk_center_offset.y) +
            (view_position.z - chunk_center_offset.z) * (view_position.z - chunk_center_offset.z);

        const distance = @sqrt(distance_sq);
        const chunk_size_f = @as(f32, @floatFromInt(self.size));

        if (distance < chunk_size_f * 2) return 0; // Full detail
        if (distance < chunk_size_f * 4) return 1; // Half detail
        if (distance < chunk_size_f * 8) return 2; // Quarter detail
        return 3; // Minimal detail
    }
};

pub const ChunkPosition = struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn init(x: i32, y: i32, z: i32) ChunkPosition {
        return ChunkPosition{ .x = x, .y = y, .z = z };
    }

    pub fn toWorldPosition(self: ChunkPosition, chunk_size: u32) Vec3 {
        const size = @as(f32, @floatFromInt(chunk_size));
        return Vec3{
            .x = @as(f32, @floatFromInt(self.x)) * size,
            .y = @as(f32, @floatFromInt(self.y)) * size,
            .z = @as(f32, @floatFromInt(self.z)) * size,
        };
    }

    pub fn fromWorldPosition(world_pos: Vec3, chunk_size: u32) ChunkPosition {
        const size = @as(f32, @floatFromInt(chunk_size));
        return ChunkPosition{
            .x = @as(i32, @intFromFloat(@floor(world_pos.x / size))),
            .y = @as(i32, @intFromFloat(@floor(world_pos.y / size))),
            .z = @as(i32, @intFromFloat(@floor(world_pos.z / size))),
        };
    }

    pub fn getNeighbors(self: ChunkPosition) [26]ChunkPosition {
        var neighbors: [26]ChunkPosition = undefined;
        var index: usize = 0;

        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                var dz: i32 = -1;
                while (dz <= 1) : (dz += 1) {
                    if (dx == 0 and dy == 0 and dz == 0) continue;
                    neighbors[index] = ChunkPosition{
                        .x = self.x + dx,
                        .y = self.y + dy,
                        .z = self.z + dz,
                    };
                    index += 1;
                }
            }
        }

        return neighbors;
    }

    pub fn hash(self: ChunkPosition) u64 {
        const x = @as(u64, @bitCast(@as(i64, self.x)));
        const y = @as(u64, @bitCast(@as(i64, self.y)));
        const z = @as(u64, @bitCast(@as(i64, self.z)));
        return x ^ (y << 20) ^ (z << 40);
    }

    pub fn eql(a: ChunkPosition, b: ChunkPosition) bool {
        return a.x == b.x and a.y == b.y and a.z == b.z;
    }

    pub const Context = struct {
        pub fn hash(self: @This(), pos: ChunkPosition) u64 {
            _ = self;
            return pos.hash();
        }

        pub fn eql(self: @This(), a: ChunkPosition, b: ChunkPosition) bool {
            _ = self;
            return ChunkPosition.eql(a, b);
        }
    };
};
