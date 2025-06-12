const std = @import("std");
const mod = @import("mod.zig");

// Re-export all types and functionality
pub const VoxelType = mod.VoxelType;
pub const VoxelMaterial = mod.VoxelMaterial;
pub const VoxelChunk = mod.VoxelChunk;
pub const ChunkPosition = mod.ChunkPosition;
pub const VoxelWorld = mod.VoxelWorld;
pub const NoiseGenerator = mod.NoiseGenerator;
pub const TerrainGenerator = mod.TerrainGenerator;
pub const MLMeshConverter = mod.MLMeshConverter;

// Re-export error set
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
