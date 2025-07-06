//! MFS Engine - System Module
//! System utilities for configuration, diagnostics, profiling, and memory management
//! Provides cross-platform system services and performance monitoring
//! @thread-safe System utilities are designed to be thread-safe
//! @performance Optimized for minimal overhead monitoring and profiling

const std = @import("std");
const builtin = @import("builtin");

// Core system components
pub const config = @import("config.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const perf_monitor = @import("perf_monitor.zig");

// Memory management
pub const memory = struct {
    pub const memory_manager = @import("memory/memory_manager.zig");

    // Re-export memory types
    pub const MemoryManager = memory_manager.MemoryManager;
    pub const MemoryConfig = memory_manager.MemoryConfig;
};

// Profiling system
pub const profiling = struct {
    pub const profiler = @import("profiling/profiler.zig");
    pub const memory_profiler = @import("profiling/memory_profiler.zig");

    // Re-export profiling types
    pub const Profiler = profiler.Profiler;
    pub const MemoryProfiler = memory_profiler.MemoryProfiler;
    pub const ProfileEntry = profiler.ProfileEntry;
};

// Re-export main system types
pub const Config = config.Config;
pub const Diagnostics = diagnostics.Diagnostics;
pub const PerfMonitor = perf_monitor.PerfMonitor;

// System information
pub const SystemInfo = struct {
    os: []const u8,
    arch: []const u8,
    cpu_count: u32,
    total_memory: u64,
    available_memory: u64,

    pub fn detect() SystemInfo {
        return SystemInfo{
            .os = @tagName(builtin.os.tag),
            .arch = @tagName(builtin.cpu.arch),
            .cpu_count = @intCast(std.Thread.getCpuCount() catch 1),
            .total_memory = getTotalMemory(),
            .available_memory = getAvailableMemory(),
        };
    }

    fn getTotalMemory() u64 {
        // Placeholder - would implement platform-specific memory detection
        return 8 * 1024 * 1024 * 1024; // 8GB default
    }

    fn getAvailableMemory() u64 {
        // Placeholder - would implement platform-specific available memory detection
        return 4 * 1024 * 1024 * 1024; // 4GB default
    }
};

// Performance metrics
pub const PerformanceMetrics = struct {
    frame_time_ms: f32,
    fps: f32,
    cpu_usage: f32,
    memory_usage: u64,
    gpu_usage: f32,

    pub fn init() PerformanceMetrics {
        return PerformanceMetrics{
            .frame_time_ms = 0.0,
            .fps = 0.0,
            .cpu_usage = 0.0,
            .memory_usage = 0,
            .gpu_usage = 0.0,
        };
    }
};

// System configuration
pub const SystemConfig = struct {
    enable_profiling: bool = builtin.mode == .Debug,
    enable_diagnostics: bool = true,
    enable_memory_tracking: bool = builtin.mode == .Debug,
    enable_performance_monitoring: bool = true,
    log_level: std.log.Level = if (builtin.mode == .Debug) .debug else .info,
    max_log_file_size_mb: u32 = 100,

    pub fn validate(self: SystemConfig) !void {
        if (self.max_log_file_size_mb == 0 or self.max_log_file_size_mb > 1000) {
            return error.InvalidParameter;
        }
    }
};

// Initialize system utilities
pub fn init(allocator: std.mem.Allocator, system_config: SystemConfig) !void {
    try system_config.validate();

    // Initialize subsystems
    if (system_config.enable_profiling) {
        try profiling.profiler.init(allocator);
    }

    if (system_config.enable_diagnostics) {
        try diagnostics.init(allocator);
    }

    if (system_config.enable_performance_monitoring) {
        try perf_monitor.init(allocator);
    }
}

// Cleanup system utilities
pub fn deinit() void {
    profiling.profiler.deinit();
    diagnostics.deinit();
    perf_monitor.deinit();
}

// Get current system information
pub fn getSystemInfo() SystemInfo {
    return SystemInfo.detect();
}

// Get current performance metrics
pub fn getPerformanceMetrics() PerformanceMetrics {
    return perf_monitor.getCurrentMetrics();
}

test "system module" {
    std.testing.refAllDecls(@This());
}
