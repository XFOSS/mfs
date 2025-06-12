const std = @import("std");
const testing = std.testing;
const VoxelType = @import("types.zig").VoxelType;
const VoxelMaterial = @import("types.zig").VoxelMaterial;
const VoxelChunk = @import("chunk.zig").VoxelChunk;
const ChunkPosition = @import("chunk.zig").ChunkPosition;
const VoxelWorld = @import("world.zig").VoxelWorld;
const NoiseGenerator = @import("generation.zig").NoiseGenerator;
const TerrainGenerator = @import("generation.zig").TerrainGenerator;

test "VoxelChunk basic operations" {
    const allocator = testing.allocator;
    const position = ChunkPosition.init(0, 0, 0);
    var chunk = try VoxelChunk.init(allocator, position, 16);
    defer chunk.deinit();

    try testing.expect(chunk.isEmpty());
    chunk.setVoxel(0, 0, 0, .stone);
    try testing.expect(!chunk.isEmpty());
    try testing.expect(chunk.getVoxel(0, 0, 0) == .stone);
}

test "VoxelChunk compression" {
    const allocator = testing.allocator;
    const position = ChunkPosition.init(0, 0, 0);
    var chunk = try VoxelChunk.init(allocator, position, 16);
    defer chunk.deinit();

    chunk.fill(.stone);
    try chunk.compress();
    try testing.expect(chunk.compressed_data != null);
    try chunk.decompress();
    try testing.expect(chunk.isFull(.stone));
}

test "ChunkPosition operations" {
    const pos1 = ChunkPosition.init(1, 2, 3);
    const pos2 = ChunkPosition.init(1, 2, 3);
    const pos3 = ChunkPosition.init(4, 5, 6);

    try testing.expect(ChunkPosition.eql(pos1, pos2));
    try testing.expect(!ChunkPosition.eql(pos1, pos3));

    const neighbors = pos1.getNeighbors();
    try testing.expect(neighbors.len == 26);
}

test "VoxelWorld chunk management" {
    const allocator = testing.allocator;
    var world = try VoxelWorld.init(allocator, 16, 64, 12345);
    defer world.deinit();

    const pos = ChunkPosition.init(0, 0, 0);
    const chunk = try world.loadChunk(pos);
    try testing.expect(chunk != null);
    try testing.expect(world.getChunk(pos) != null);

    world.unloadChunk(pos);
    try testing.expect(world.getChunk(pos) == null);
}

test "VoxelWorld voxel access" {
    const allocator = testing.allocator;
    var world = try VoxelWorld.init(allocator, 16, 64, 12345);
    defer world.deinit();

    try world.setVoxelAt(0, 0, 0, .stone);
    const voxel = try world.getVoxelAt(0, 0, 0);
    try testing.expect(voxel == .stone);
}

test "TerrainGenerator basic generation" {
    const allocator = testing.allocator;
    const generator = TerrainGenerator.init(allocator, 12345);
    const position = ChunkPosition.init(0, 0, 0);
    var chunk = try VoxelChunk.init(allocator, position, 16);
    defer chunk.deinit();

    try generator.generateTerrain(&chunk);
    try testing.expect(!chunk.isEmpty());
}

test "NoiseGenerator output range" {
    const allocator = testing.allocator;
    var noise = NoiseGenerator.init(allocator, 12345);

    const value = noise.generateNoise(1.0, 2.0, 3.0);
    try testing.expect(value >= -1.0 and value <= 1.0);
}

test "VoxelWorld chunk loading distance" {
    const allocator = testing.allocator;
    var world = try VoxelWorld.init(allocator, 16, 64, 12345);
    defer world.deinit();

    try world.updateChunks(.{ .x = 0, .y = 0, .z = 0 });
    const loaded_count = world.loaded_chunks.items.len;
    try testing.expect(loaded_count > 0);
}

test "VoxelMaterial properties" {
    const stone_material = VoxelMaterial.init(.stone);
    try testing.expect(stone_material.voxel_type == .stone);
    try testing.expect(stone_material.density > 0);
}

test "VoxelType properties" {
    try testing.expect(VoxelType.stone.isSolid());
    try testing.expect(VoxelType.water.isLiquid());
    try testing.expect(VoxelType.glass.isTransparent());
    try testing.expect(!VoxelType.air.isSolid());
}
