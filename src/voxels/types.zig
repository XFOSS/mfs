const std = @import("std");
const math = @import("math");
const Vec4 = math.Vec4;

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
