const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const ChunkPosition = @import("chunk.zig").ChunkPosition;
const VoxelChunk = @import("chunk.zig").VoxelChunk;
const VoxelType = @import("types.zig").VoxelType;
const VoxelMaterial = @import("types.zig").VoxelMaterial;
const TerrainGenerator = @import("generation.zig").TerrainGenerator;
const math = @import("math");
const Vec3 = math.Vec3;

pub const VoxelWorld = struct {
    allocator: Allocator,
    chunks: AutoHashMap(u64, *VoxelChunk),
    generator: TerrainGenerator,
    chunk_size: u32,
    max_chunks: usize,
    loaded_chunks: ArrayList(*VoxelChunk),
    chunk_load_distance: u32,
    chunk_unload_distance: u32,

    pub fn init(allocator: Allocator, chunk_size: u32, max_chunks: usize, seed: u64) !*VoxelWorld {
        const world = try allocator.create(VoxelWorld);
        world.* = VoxelWorld{
            .allocator = allocator,
            .chunks = AutoHashMap(u64, *VoxelChunk).init(allocator),
            .generator = TerrainGenerator.init(allocator, seed),
            .chunk_size = chunk_size,
            .max_chunks = max_chunks,
            .loaded_chunks = ArrayList(*VoxelChunk).init(allocator),
            .chunk_load_distance = 8,
            .chunk_unload_distance = 12,
        };
        return world;
    }

    pub fn deinit(self: *VoxelWorld) void {
        var chunk_iter = self.chunks.valueIterator();
        while (chunk_iter.next()) |chunk| {
            chunk.*.deinit();
            self.allocator.destroy(chunk.*);
        }
        self.chunks.deinit();
        self.loaded_chunks.deinit();
        self.allocator.destroy(self);
    }

    pub fn getChunk(self: *VoxelWorld, position: ChunkPosition) ?*VoxelChunk {
        const hash = position.hash();
        return self.chunks.get(hash);
    }

    pub fn loadChunk(self: *VoxelWorld, position: ChunkPosition) !*VoxelChunk {
        const hash = position.hash();
        if (self.chunks.get(hash)) |chunk| {
            chunk.last_access = std.time.timestamp();
            return chunk;
        }

        // Evict oldest chunk if at capacity
        if (self.loaded_chunks.items.len >= self.max_chunks) {
            try self.evictOldestChunk();
        }

        var chunk = try VoxelChunk.init(self.allocator, position, self.chunk_size);
        try self.generator.generateTerrain(&chunk);
        try self.chunks.put(hash, &chunk);
        try self.loaded_chunks.append(&chunk);
        return &chunk;
    }

    fn evictOldestChunk(self: *VoxelWorld) !void {
        if (self.loaded_chunks.items.len == 0) return;

        var oldest_idx: usize = 0;
        var oldest_time = std.time.timestamp();

        for (self.loaded_chunks.items, 0..) |chunk, i| {
            if (chunk.last_access < oldest_time) {
                oldest_time = chunk.last_access;
                oldest_idx = i;
            }
        }

        const chunk = self.loaded_chunks.swapRemove(oldest_idx);
        const hash = chunk.position.hash();
        _ = self.chunks.remove(hash);
        chunk.deinit();
        self.allocator.destroy(chunk);
    }

    pub fn unloadChunk(self: *VoxelWorld, position: ChunkPosition) void {
        const hash = position.hash();
        if (self.chunks.get(hash)) |chunk| {
            for (self.loaded_chunks.items, 0..) |loaded, i| {
                if (loaded == chunk) {
                    _ = self.loaded_chunks.swapRemove(i);
                    break;
                }
            }
            _ = self.chunks.remove(hash);
            chunk.deinit();
            self.allocator.destroy(chunk);
        }
    }

    pub fn getVoxelAt(self: *VoxelWorld, x: i32, y: i32, z: i32) !VoxelType {
        const chunk_pos = ChunkPosition.fromWorldPosition(Vec3{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z) }, self.chunk_size);
        const chunk = try self.loadChunk(chunk_pos);

        const local_x = @mod(x, self.chunk_size);
        const local_y = @mod(y, self.chunk_size);
        const local_z = @mod(z, self.chunk_size);

        return chunk.getVoxel(@intCast(local_x), @intCast(local_y), @intCast(local_z));
    }

    pub fn setVoxelAt(self: *VoxelWorld, x: i32, y: i32, z: i32, voxel_type: VoxelType) !void {
        const chunk_pos = ChunkPosition.fromWorldPosition(Vec3{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z) }, self.chunk_size);
        const chunk = try self.loadChunk(chunk_pos);

        const local_x = @mod(x, self.chunk_size);
        const local_y = @mod(y, self.chunk_size);
        const local_z = @mod(z, self.chunk_size);

        chunk.setVoxel(@intCast(local_x), @intCast(local_y), @intCast(local_z), voxel_type);
    }

    pub fn updateChunks(self: *VoxelWorld, camera_pos: Vec3) !void {
        const camera_chunk = ChunkPosition.fromWorldPosition(camera_pos, self.chunk_size);
        var chunks_to_load = ArrayList(ChunkPosition).init(self.allocator);
        defer chunks_to_load.deinit();

        // Calculate chunks that should be loaded
        var x: i32 = camera_chunk.x - @as(i32, @intCast(self.chunk_load_distance));
        while (x <= camera_chunk.x + @as(i32, @intCast(self.chunk_load_distance))) : (x += 1) {
            var y: i32 = camera_chunk.y - @as(i32, @intCast(self.chunk_load_distance));
            while (y <= camera_chunk.y + @as(i32, @intCast(self.chunk_load_distance))) : (y += 1) {
                var z: i32 = camera_chunk.z - @as(i32, @intCast(self.chunk_load_distance));
                while (z <= camera_chunk.z + @as(i32, @intCast(self.chunk_load_distance))) : (z += 1) {
                    const pos = ChunkPosition.init(x, y, z);
                    if (self.getChunk(pos) == null) {
                        try chunks_to_load.append(pos);
                    }
                }
            }
        }

        // Load new chunks
        for (chunks_to_load.items) |pos| {
            _ = try self.loadChunk(pos);
        }

        // Unload distant chunks
        var i: usize = 0;
        while (i < self.loaded_chunks.items.len) {
            const chunk = self.loaded_chunks.items[i];
            const dx = @abs(chunk.position.x - camera_chunk.x);
            const dy = @abs(chunk.position.y - camera_chunk.y);
            const dz = @abs(chunk.position.z - camera_chunk.z);
            const max_dist = @max(@max(dx, dy), dz);

            if (max_dist > self.chunk_unload_distance) {
                self.unloadChunk(chunk.position);
            } else {
                i += 1;
            }
        }
    }
};
