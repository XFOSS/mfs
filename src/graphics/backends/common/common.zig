/// Common utilities and helpers for graphics backends
/// This module re-exports all common functionality to be used by backend implementations
pub const memory = @import("memory.zig");
pub const errors = @import("errors.zig");
pub const profiling = @import("profiling.zig");
pub const resources = @import("resources.zig");
pub const shader_utils = @import("shader_utils.zig");
pub const backend_base = @import("backend_base.zig");

pub const test_utils = @import("test_utils.zig");

// Re-export commonly used types for convenience
pub const MemoryBlock = memory.MemoryBlock;
pub const MemoryUsage = memory.MemoryUsage;
pub const AllocStrategy = memory.AllocStrategy;
pub const MemoryAllocator = memory.Allocator;
pub const MemoryPool = memory.MemoryPool;

pub const GraphicsError = errors.GraphicsError;
pub const ErrorContext = errors.ErrorContext;
pub const ErrorSeverity = errors.ErrorSeverity;
pub const ErrorLogger = errors.ErrorLogger;
pub const makeError = errors.makeError;

pub const GpuMetrics = profiling.GpuMetrics;
pub const GpuProfiler = profiling.GpuProfiler;
pub const PerformanceMarker = profiling.PerformanceMarker;

pub const ResourceManager = resources.ResourceManager;
pub const TextureUtils = resources.TextureUtils;
pub const BufferUtils = resources.BufferUtils;

pub const ShaderStage = shader_utils.ShaderStage;
pub const ShaderSourceType = shader_utils.ShaderSourceType;
pub const ShaderCompileOptions = shader_utils.ShaderCompileOptions;
pub const ShaderReflection = shader_utils.ShaderReflection;
pub const ShaderUtils = shader_utils.ShaderUtils;

pub const BackendBase = backend_base.BackendBase;
