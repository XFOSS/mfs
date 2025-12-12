//! AI Platform Detection
//! Platform-specific utilities for AI systems
//! @symbol AI platform utilities

const std = @import("std");
const build_options = @import("../../build_options.zig");

/// Platform detection for AI systems
/// @thread-safe Thread-compatible data structure
pub const Platform = struct {
    /// Check if CPU optimizations are available
    pub fn hasCpuOptimizations() bool {
        // Check for SIMD/AVX support
        return std.Target.current.cpu.arch == .x86_64;
    }

    /// Check if GPU acceleration is available
    pub fn hasGpuAcceleration() bool {
        // Check for CUDA/OpenCL support
        return build_options.Graphics.vulkan_available;
    }

    /// Get optimal thread count for AI processing
    pub fn getOptimalThreadCount() u32 {
        const cpu_count = std.Thread.getCpuCount() catch 4;
        return @min(cpu_count, 8); // Cap at 8 threads for AI processing
    }

    /// Check if platform supports advanced AI features
    pub fn supportsAdvancedFeatures() bool {
        return hasCpuOptimizations() and hasGpuAcceleration();
    }
};
