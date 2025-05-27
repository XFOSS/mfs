const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Vec3 = @import("../math/vec3.zig").Vec3f;
const Vec4 = @import("../math/vec4.zig").Vec4f;
const Mat4 = @import("../math/mat4.zig").Mat4f;
const print = std.debug.print;

pub const VoxelError = error{
    InvalidChunkSize,
    ChunkNotFound,
    OutOfMemory,
    InvalidPosition,
    InvalidMaterial,
    GenerationFailed,
    MeshConversionFailed,
    SerializationFailed,
    CompressionFailed,
    NetworkError,
};

pub const VoxelType = enum(u8) {
    air = 0,
    stone = 1,
    dirt = 2,
    grass = 3,
    water = 4,
    sand = 5,
    wood = 6,
    leaves = 7,
    iron = 8,
    gold = 9,
    diamond = 10,
    coal = 11,
    copper = 12,
    bedrock = 13,
    lava = 14,
    ice = 15,
    snow = 16,
    clay = 17,
    gravel = 18,
    obsidian = 19,
    glass = 20,
    brick = 21,
    concrete = 22,
    custom_start = 128,

    pub fn isSolid(self: VoxelType) bool {
        return self != .air and self != .water;
    }

    pub fn isTransparent(self: VoxelType) bool {
        return self == .air or self == .water or self == .glass or self == .ice;
    }

    pub fn isLiquid(self: VoxelType) bool {
        return self == .water or self == .lava;
    }

    pub fn getColor(self: VoxelType) Vec4 {
        return switch (self) {
            .air => Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            .stone => Vec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1.0 },
            .dirt => Vec4{ .x = 0.4, .y = 0.2, .z = 0.1, .w = 1.0 },
            .grass => Vec4{ .x = 0.2, .y = 0.8, .z = 0.2, .w = 1.0 },
            .water => Vec4{ .x = 0.2, .y = 0.4, .z = 0.8, .w = 0.7 },
            .sand => Vec4{ .x = 0.9, .y = 0.8, .z = 0.6, .w = 1.0 },
            .wood => Vec4{ .x = 0.4, .y = 0.2, .z = 0.0, .w = 1.0 },
            .leaves => Vec4{ .x = 0.0, .y = 0.6, .z = 0.0, .w = 0.8 },
            .iron => Vec4{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1.0 },
            .gold => Vec4{ .x = 1.0, .y = 0.8, .z = 0.0, .w = 1.0 },
            .diamond => Vec4{ .x = 0.7, .y = 0.9, .z = 1.0, .w = 0.9 },
            .coal => Vec4{ .x = 0.1, .y = 0.1, .z = 0.1, .w = 1.0 },
            .copper => Vec4{ .x = 0.7, .y = 0.4, .z = 0.2, .w = 1.0 },
            .bedrock => Vec4{ .x = 0.2, .y = 0.2, .z = 0.2, .w = 1.0 },
            .lava => Vec4{ .x = 1.0, .y = 0.2, .z = 0.0, .w = 1.0 },
            .ice => Vec4{ .x = 0.8, .y = 0.9, .z = 1.0, .w = 0.8 },
            .snow => Vec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
            .clay => Vec4{ .x = 0.6, .y = 0.4, .z = 0.3, .w = 1.0 },
            .gravel => Vec4{ .x = 0.4, .y = 0.4, .z = 0.4, .w = 1.0 },
            .obsidian => Vec4{ .x = 0.1, .y = 0.0, .z = 0.2, .w = 1.0 },
            .glass => Vec4{ .x = 0.9, .y = 0.9, .z = 0.9, .w = 0.3 },
            .brick => Vec4{ .x = 0.7, .y = 0.3, .z = 0.2, .w = 1.0 },
            .concrete => Vec4{ .x = 0.6, .y = 0.6, .z = 0.6, .w = 1.0 },
            else => Vec4{ .x = 1.0, .y = 0.0, .z = 1.0, .w = 1.0 }, // Magenta for unknown
        };
    }

    pub fn getHardness(self: VoxelType) f32 {
        return switch (self) {
            .air => 0.0,
            .water, .lava => 0.1,
            .sand, .gravel => 0.5,
            .dirt, .clay => 0.6,
            .snow, .ice => 0.7,
            .grass => 0.8,
            .wood, .leaves => 1.0,
            .stone, .coal, .copper => 2.0,
            .iron => 3.0,
            .gold => 3.5,
            .glass, .brick, .concrete => 4.0,
            .obsidian => 5.0,
            .diamond => 6.0,
            .bedrock => 100.0,
            else => 1.0,
        };
    }
};

pub const VoxelMaterial = struct {
    voxel_type: VoxelType,
    color: Vec4,
    metallic: f32 = 0.0,
    roughness: f32 = 1.0,
    emission: f32 = 0.0,
    density: f32 = 1.0,
    temperature: f32 = 20.0, // Celsius
    conductivity: f32 = 0.0,

    pub fn init(voxel_type: VoxelType) VoxelMaterial {
        return VoxelMaterial{
            .voxel_type = voxel_type,
            .color = voxel_type.getColor(),
            .metallic = switch (voxel_type) {
                .iron, .gold, .copper => 0.9,
                .diamond => 0.1,
                else => 0.0,
            },
            .roughness = switch (voxel_type) {
                .water, .ice, .glass, .diamond => 0.1,
                .iron, .gold, .copper => 0.2,
                .stone, .obsidian => 0.6,
                else => 1.0,
            },
            .emission = switch (voxel_type) {
                .lava => 1.0,
                else => 0.0,
            },
        };
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

pub const NoiseGenerator = struct {
    seed: u64,
    octaves: u32,
    frequency: f32,
    amplitude: f32,
    persistence: f32,
    lacunarity: f32,

    pub fn init(seed: u64) NoiseGenerator {
        return NoiseGenerator{
            .seed = seed,
            .octaves = 4,
            .frequency = 0.01,
            .amplitude = 1.0,
            .persistence = 0.5,
            .lacunarity = 2.0,
        };
    }

    pub fn noise2D(self: *const NoiseGenerator, x: f32, y: f32) f32 {
        var value: f32 = 0.0;
        var frequency = self.frequency;
        var amplitude = self.amplitude;

        var i: u32 = 0;
        while (i < self.octaves) : (i += 1) {
            value += self.perlinNoise2D(x * frequency, y * frequency) * amplitude;
            frequency *= self.lacunarity;
            amplitude *= self.persistence;
        }

        return value;
    }

    pub fn noise3D(self: *const NoiseGenerator, x: f32, y: f32, z: f32) f32 {
        var value: f32 = 0.0;
        var frequency = self.frequency;
        var amplitude = self.amplitude;

        var i: u32 = 0;
        while (i < self.octaves) : (i += 1) {
            value += self.perlinNoise3D(x * frequency, y * frequency, z * frequency) * amplitude;
            frequency *= self.lacunarity;
            amplitude *= self.persistence;
        }

        return value;
    }

    fn perlinNoise2D(self: *const NoiseGenerator, x: f32, y: f32) f32 {
        const X = @as(i32, @intFromFloat(@floor(x))) & 255;
        const Y = @as(i32, @intFromFloat(@floor(y))) & 255;

        const x_frac = x - @floor(x);
        const y_frac = y - @floor(y);

        const u = fade(x_frac);
        const v = fade(y_frac);

        const A = self.perm(X) + Y;
        const B = self.perm(X + 1) + Y;

        return lerp(v, lerp(u, grad2D(self.perm(A), x_frac, y_frac), grad2D(self.perm(B), x_frac - 1, y_frac)), lerp(u, grad2D(self.perm(A + 1), x_frac, y_frac - 1), grad2D(self.perm(B + 1), x_frac - 1, y_frac - 1)));
    }

    fn perlinNoise3D(self: *const NoiseGenerator, x: f32, y: f32, z: f32) f32 {
        const X = @as(i32, @intFromFloat(@floor(x))) & 255;
        const Y = @as(i32, @intFromFloat(@floor(y))) & 255;
        const Z = @as(i32, @intFromFloat(@floor(z))) & 255;

        const x_frac = x - @floor(x);
        const y_frac = y - @floor(y);
        const z_frac = z - @floor(z);

        const u = fade(x_frac);
        const v = fade(y_frac);
        const w = fade(z_frac);

        const A = self.perm(X) + Y;
        const AA = self.perm(A) + Z;
        const AB = self.perm(A + 1) + Z;
        const B = self.perm(X + 1) + Y;
        const BA = self.perm(B) + Z;
        const BB = self.perm(B + 1) + Z;

        return lerp(w, lerp(v, lerp(u, grad3D(self.perm(AA), x_frac, y_frac, z_frac), grad3D(self.perm(BA), x_frac - 1, y_frac, z_frac)), lerp(u, grad3D(self.perm(AB), x_frac, y_frac - 1, z_frac), grad3D(self.perm(BB), x_frac - 1, y_frac - 1, z_frac))), lerp(v, lerp(u, grad3D(self.perm(AA + 1), x_frac, y_frac, z_frac - 1), grad3D(self.perm(BA + 1), x_frac - 1, y_frac, z_frac - 1)), lerp(u, grad3D(self.perm(AB + 1), x_frac, y_frac - 1, z_frac - 1), grad3D(self.perm(BB + 1), x_frac - 1, y_frac - 1, z_frac - 1))));
    }

    fn perm(self: *const NoiseGenerator, t: i32) i32 {
        return @as(i32, @intCast(((@as(u64, @intCast(t)) + self.seed) * 1103515245 + 12345) % 256));
    }

    fn fade(t: f32) f32 {
        return t * t * t * (t * (t * 6 - 15) + 10);
    }

    fn lerp(t: f32, a: f32, b: f32) f32 {
        return a + t * (b - a);
    }

    fn grad2D(hash: i32, x: f32, y: f32) f32 {
        const h = hash & 3;
        const u = if (h < 2) x else y;
        const v = if (h < 2) y else x;
        return (if (h & 1 != 0) -u else u) + (if (h & 2 != 0) -2.0 * v else 2.0 * v);
    }

    fn grad3D(hash: i32, x: f32, y: f32, z: f32) f32 {
        const h = hash & 15;
        const u = if (h < 8) x else y;
        const v = if (h < 4) y else if (h == 12 or h == 14) x else z;
        return (if (h & 1 != 0) -u else u) + (if (h & 2 != 0) -v else v);
    }
};

pub const TerrainGenerator = struct {
    noise: NoiseGenerator,
    height_scale: f32,
    sea_level: f32,
    mountain_frequency: f32,
    cave_frequency: f32,
    ore_frequency: f32,

    pub fn init(seed: u64) TerrainGenerator {
        return TerrainGenerator{
            .noise = NoiseGenerator.init(seed),
            .height_scale = 64.0,
            .sea_level = 32.0,
            .mountain_frequency = 0.005,
            .cave_frequency = 0.02,
            .ore_frequency = 0.03,
        };
    }

    pub fn generateChunk(self: *const TerrainGenerator, chunk: *VoxelChunk) void {
        const world_pos = chunk.position.toWorldPosition(chunk.size);

        var y: u32 = 0;
        while (y < chunk.size) : (y += 1) {
            var z: u32 = 0;
            while (z < chunk.size) : (z += 1) {
                var x: u32 = 0;
                while (x < chunk.size) : (x += 1) {
                    const world_x = world_pos.x + @as(f32, @floatFromInt(x));
                    const world_y = world_pos.y + @as(f32, @floatFromInt(y));
                    const world_z = world_pos.z + @as(f32, @floatFromInt(z));

                    const voxel_type = self.getVoxelAt(world_x, world_y, world_z);
                    chunk.setVoxel(x, y, z, voxel_type);
                }
            }
        }

        chunk.generated = true;
    }

    fn getVoxelAt(self: *const TerrainGenerator, x: f32, y: f32, z: f32) VoxelType {
        // Height map
        const height_noise = self.noise.noise2D(x * self.mountain_frequency, z * self.mountain_frequency);
        const height = self.sea_level + height_noise * self.height_scale;

        // Below bedrock
        if (y < 0) return .bedrock;

        // Above terrain
        if (y > height) {
            return if (y <= self.sea_level) .water else .air;
        }

        // Cave generation
        const cave_noise = self.noise.noise3D(x * self.cave_frequency, y * self.cave_frequency, z * self.cave_frequency);
        if (cave_noise > 0.6) return .air;

        // Ore generation
        const ore_noise = self.noise.noise3D(x * self.ore_frequency, y * self.ore_frequency, z * self.ore_frequency);

        // Deep underground - more valuable ores
        if (y < height * 0.3) {
            if (ore_noise > 0.8) return .diamond;
            if (ore_noise > 0.75) return .gold;
            if (ore_noise > 0.7) return .iron;
        }

        // Mid level
        if (y < height * 0.6) {
            if (ore_noise > 0.8) return .iron;
            if (ore_noise > 0.75) return .copper;
            if (ore_noise > 0.7) return .coal;
        }

        // Surface layers
        const depth_from_surface = height - y;
        if (depth_from_surface < 1) {
            return .grass;
        } else if (depth_from_surface < 4) {
            return .dirt;
        } else {
            return .stone;
        }
    }
};

pub const VoxelWorld = struct {
    allocator: Allocator,
    chunks: HashMap(ChunkPosition, *VoxelChunk, ChunkPosition.Context, std.hash_map.default_max_load_percentage),
    terrain_generator: TerrainGenerator,
    chunk_size: u32,
    render_distance: u32,
    active_chunks: ArrayList(ChunkPosition),
    chunk_cache_size: usize,

    pub fn init(allocator: Allocator, seed: u64, chunk_size: u32, render_distance: u32) VoxelWorld {
        return VoxelWorld{
            .allocator = allocator,
            .chunks = HashMap(ChunkPosition, *VoxelChunk, ChunkPosition.Context, std.hash_map.default_max_load_percentage).init(allocator),
            .terrain_generator = TerrainGenerator.init(seed),
            .chunk_size = chunk_size,
            .render_distance = render_distance,
            .active_chunks = ArrayList(ChunkPosition).init(allocator),
            .chunk_cache_size = 1000,
        };
    }

    pub fn deinit(self: *VoxelWorld) void {
        var chunk_iterator = self.chunks.iterator();
        while (chunk_iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.chunks.deinit();
        self.active_chunks.deinit();
    }

    pub fn updateActiveChunks(self: *VoxelWorld, center_position: Vec3) !void {
        const center_chunk = ChunkPosition.fromWorldPosition(center_position, self.chunk_size);
        self.active_chunks.clearRetainingCapacity();

        const render_dist = @as(i32, @intCast(self.render_distance));
        var dx: i32 = -render_dist;
        while (dx <= render_dist) : (dx += 1) {
            var dy: i32 = -render_dist;
            while (dy <= render_dist) : (dy += 1) {
                var dz: i32 = -render_dist;
                while (dz <= render_dist) : (dz += 1) {
                    const chunk_pos = ChunkPosition{
                        .x = center_chunk.x + dx,
                        .y = center_chunk.y + dy,
                        .z = center_chunk.z + dz,
                    };

                    // Check if within render distance
                    const dist_sq = dx * dx + dy * dy + dz * dz;
                    if (dist_sq <= render_dist * render_dist) {
                        try self.active_chunks.append(chunk_pos);

                        // Load chunk if not already loaded
                        if (!self.chunks.contains(chunk_pos)) {
                            try self.loadChunk(chunk_pos);
                        }
                    }
                }
            }
        }

        // Unload distant chunks to save memory
        try self.unloadDistantChunks(center_chunk);
    }

    pub fn loadChunk(self: *VoxelWorld, position: ChunkPosition) !void {
        if (self.chunks.contains(position)) return;

        const chunk = try self.allocator.create(VoxelChunk);
        chunk.* = try VoxelChunk.init(self.allocator, position, self.chunk_size);

        // Generate terrain
        self.terrain_generator.generateChunk(chunk);

        try self.chunks.put(position, chunk);
    }

    pub fn unloadChunk(self: *VoxelWorld, position: ChunkPosition) void {
        if (self.chunks.fetchRemove(position)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }

    fn unloadDistantChunks(self: *VoxelWorld, center: ChunkPosition) !void {
        var chunks_to_unload = ArrayList(ChunkPosition).init(self.allocator);
        defer chunks_to_unload.deinit();

        var chunk_iterator = self.chunks.iterator();
        while (chunk_iterator.next()) |entry| {
            const chunk_pos = entry.key_ptr.*;
            const dx = chunk_pos.x - center.x;
            const dy = chunk_pos.y - center.y;
            const dz = chunk_pos.z - center.z;
            const dist_sq = dx * dx + dy * dy + dz * dz;
            const max_dist = @as(i32, @intCast(self.render_distance + 2));

            if (dist_sq > max_dist * max_dist) {
                try chunks_to_unload.append(chunk_pos);
            }
        }

        for (chunks_to_unload.items) |pos| {
            self.unloadChunk(pos);
        }
    }

    pub fn getChunk(self: *VoxelWorld, position: ChunkPosition) ?*VoxelChunk {
        return self.chunks.get(position);
    }

    pub fn getVoxelAt(self: *VoxelWorld, world_x: f32, world_y: f32, world_z: f32) VoxelType {
        const chunk_pos = ChunkPosition.fromWorldPosition(Vec3{ .x = world_x, .y = world_y, .z = world_z }, self.chunk_size);

        if (self.getChunk(chunk_pos)) |chunk| {
            const chunk_world_pos = chunk_pos.toWorldPosition(self.chunk_size);
            const local_x = @as(u32, @intFromFloat(world_x - chunk_world_pos.x));
            const local_y = @as(u32, @intFromFloat(world_y - chunk_world_pos.y));
            const local_z = @as(u32, @intFromFloat(world_z - chunk_world_pos.z));

            return chunk.getVoxel(local_x, local_y, local_z);
        }

        return .air;
    }

    pub fn setVoxelAt(self: *VoxelWorld, world_x: f32, world_y: f32, world_z: f32, voxel_type: VoxelType) !void {
        const chunk_pos = ChunkPosition.fromWorldPosition(Vec3{ .x = world_x, .y = world_y, .z = world_z }, self.chunk_size);

        // Load chunk if not present
        if (!self.chunks.contains(chunk_pos)) {
            try self.loadChunk(chunk_pos);
        }

        if (self.getChunk(chunk_pos)) |chunk| {
            const chunk_world_pos = chunk_pos.toWorldPosition(self.chunk_size);
            const local_x = @as(u32, @intFromFloat(world_x - chunk_world_pos.x));
            const local_y = @as(u32, @intFromFloat(world_y - chunk_world_pos.y));
            const local_z = @as(u32, @intFromFloat(world_z - chunk_world_pos.z));

            chunk.setVoxel(local_x, local_y, local_z, voxel_type);
        }
    }

    pub fn getLoadedChunkCount(self: *const VoxelWorld) usize {
        return self.chunks.count();
    }

    pub fn getActiveChunkCount(self: *const VoxelWorld) usize {
        return self.active_chunks.items.len;
    }

    pub fn saveChunk(self: *VoxelWorld, position: ChunkPosition, path: []const u8) !void {
        const chunk = self.getChunk(position) orelse return VoxelError.ChunkNotFound;

        // Compress chunk data before saving
        try chunk.compress();

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Write chunk header
        try file.writeIntLittle(u32, chunk.size);
        try file.writeIntLittle(i32, chunk.position.x);
        try file.writeIntLittle(i32, chunk.position.y);
        try file.writeIntLittle(i32, chunk.position.z);
        try file.writeIntLittle(u32, chunk.mesh_version);

        // Write compressed data
        if (chunk.compressed_data) |data| {
            try file.writeIntLittle(u32, @as(u32, @intCast(data.len)));
            try file.writeAll(data);
        } else {
            try file.writeIntLittle(u32, 0);
        }
    }

    pub fn loadChunkFromFile(self: *VoxelWorld, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Read chunk header
        const size = try file.readIntLittle(u32);
        const pos_x = try file.readIntLittle(i32);
        const pos_y = try file.readIntLittle(i32);
        const pos_z = try file.readIntLittle(i32);
        const mesh_version = try file.readIntLittle(u32);

        const position = ChunkPosition{ .x = pos_x, .y = pos_y, .z = pos_z };

        // Create chunk
        const chunk = try self.allocator.create(VoxelChunk);
        chunk.* = try VoxelChunk.init(self.allocator, position, size);
        chunk.mesh_version = mesh_version;

        // Read compressed data
        const data_len = try file.readIntLittle(u32);
        if (data_len > 0) {
            chunk.compressed_data = try self.allocator.alloc(u8, data_len);
            _ = try file.readAll(chunk.compressed_data.?);
            try chunk.decompress();
        }

        try self.chunks.put(position, chunk);
    }
};

// Test the complete voxel engine system
test "voxel engine comprehensive test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test voxel types
    try std.testing.expect(VoxelType.stone.isSolid());
    try std.testing.expect(!VoxelType.air.isSolid());
    try std.testing.expect(VoxelType.water.isLiquid());
    try std.testing.expect(VoxelType.glass.isTransparent());

    // Test chunk creation
    const chunk_pos = ChunkPosition.init(0, 0, 0);
    var chunk = try VoxelChunk.init(allocator, chunk_pos, 16);
    defer chunk.deinit();

    // Test voxel operations
    chunk.setVoxel(8, 8, 8, .stone);
    try std.testing.expect(chunk.getVoxel(8, 8, 8) == .stone);

    // Test chunk filling
    chunk.fill(.dirt);
    try std.testing.expect(chunk.isFull(.dirt));

    // Test sphere generation
    chunk.fill(.air);
    chunk.sphere(8.0, 8.0, 8.0, 4.0, .stone);
    try std.testing.expect(chunk.getVoxel(8, 8, 8) == .stone);

    // Test noise generator
    var noise = NoiseGenerator.init(12345);
    const noise_value = noise.noise2D(10.0, 20.0);
    try std.testing.expect(noise_value >= -1.0 and noise_value <= 1.0);

    // Test terrain generator
    const terrain = TerrainGenerator.init(54321);
    terrain.generateChunk(&chunk);
    try std.testing.expect(chunk.generated);

    // Test voxel world
    var world = VoxelWorld.init(allocator, 98765, 16, 4);
    defer world.deinit();

    // Test chunk loading
    try world.loadChunk(ChunkPosition.init(0, 0, 0));
    try world.loadChunk(ChunkPosition.init(1, 0, 0));
    try std.testing.expect(world.getLoadedChunkCount() == 2);

    // Test active chunk management
    const center_pos = Vec3{ .x = 8.0, .y = 8.0, .z = 8.0 };
    try world.updateActiveChunks(center_pos);
    try std.testing.expect(world.getActiveChunkCount() > 0);

    // Test voxel access
    try world.setVoxelAt(8.0, 8.0, 8.0, .gold);
    try std.testing.expect(world.getVoxelAt(8.0, 8.0, 8.0) == .gold);

    // Test chunk compression
    if (world.getChunk(ChunkPosition.init(0, 0, 0))) |test_chunk| {
        try test_chunk.compress();
        try std.testing.expect(test_chunk.compressed_data != null);
        try test_chunk.decompress();
        try std.testing.expect(test_chunk.compressed_data == null);
    }

    // Test LOD calculation
    if (world.getChunk(ChunkPosition.init(0, 0, 0))) |test_chunk| {
        const lod_close = test_chunk.calculateLOD(Vec3{ .x = 8.0, .y = 8.0, .z = 8.0 });
        const lod_far = test_chunk.calculateLOD(Vec3{ .x = 100.0, .y = 100.0, .z = 100.0 });
        try std.testing.expect(lod_close <= lod_far);
    }
}
