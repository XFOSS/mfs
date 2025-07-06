//! Core Engine Systems
//! Essential services and utilities used throughout the engine.
//!
//! The core module provides fundamental building blocks for the engine:
//! - Memory management (allocators, pools, tracking)
//! - Time management (timers, frame timing, profiling)
//! - Event system (pub/sub, event queues, dispatching)
//! - Asset management (loading, caching, hot-reloading)
//! - Configuration (engine settings, runtime config)
//! - Logging (structured logging, log levels, sinks)
//! - Type definitions (common types, handles, IDs)
//!
//! @thread-safe: Individual components document their thread-safety
//! @allocator-aware: yes - all components support custom allocators
//! @platform: all

const std = @import("std");

// Re-export standard allocator interface for convenience
pub const Allocator = std.mem.Allocator;

// =============================================================================
// Memory Management
// =============================================================================

/// Memory management utilities
pub const memory = @import("memory.zig");

/// Custom allocator implementations
pub const allocator = @import("allocator.zig");
pub const DebugAllocator = allocator.DebugAllocator;
pub const PoolAllocator = allocator.PoolAllocator;
pub const LinearAllocator = allocator.LinearAllocator;

/// Object pooling for high-frequency allocations
pub const object_pool = @import("object_pool.zig");
pub const ObjectPool = object_pool.ObjectPool;

// Legacy aliases for backward compatibility
pub const Pool = memory.Pool;

// =============================================================================
// Time Management
// =============================================================================

/// Time utilities and frame timing
pub const time = @import("time.zig");
pub const Time = time.Time;
pub const Timer = time.Timer;
pub const FrameTimer = time.FrameTimer;

// =============================================================================
// Event System
// =============================================================================

/// Main event system - type-safe with priority support
pub const events = @import("events.zig");
pub const EventSystem = events.EventSystem;
pub const EventListener = events.EventListener;
pub const BaseEvent = events.BaseEvent;
pub const Event = events.Event; // Legacy alias
pub const Priority = events.Priority;
pub const EventError = events.EventError;

// Common event types
pub const WindowEvent = events.WindowEvent;
pub const InputEvent = events.InputEvent;
pub const SystemEvent = events.SystemEvent;

/// Alternative event system implementation
pub const event_system = @import("event_system.zig");
pub const EventDispatcher = event_system.EventDispatcher;
pub const EventQueue = event_system.EventQueue;

// =============================================================================
// Asset Management
// =============================================================================

/// Modern asset management system
pub const asset_manager = @import("asset_manager.zig");
pub const AssetManager = asset_manager.AssetManager;
pub const AssetHandle = asset_manager.AssetHandle;
pub const AssetState = asset_manager.AssetState;

/// Legacy asset system (deprecated - use asset_manager)
pub const assets = @import("assets.zig");
pub const Asset = assets.Asset;

// =============================================================================
// Core Types and Utilities
// =============================================================================

/// Common type definitions
pub const types = @import("types.zig");
pub const Id = types.Id;
pub const Handle = types.Handle;
pub const Result = types.Result;
pub const Version = types.Version;

/// UUID generation and management
pub const uuid = @import("uuid.zig");
pub const UUID = uuid.UUID;
pub const UUIDGenerator = uuid.Generator;

// =============================================================================
// Logging System
// =============================================================================

/// Structured logging system
pub const log = @import("log.zig");
pub const Logger = log.Logger;
pub const LogLevel = log.Level;
pub const LogConfig = log.Config;

// =============================================================================
// Configuration
// =============================================================================

/// Engine and runtime configuration
pub const config = @import("config.zig");
pub const Config = config.Config;
pub const ConfigLoader = config.Loader;
pub const ConfigValue = config.Value;

// =============================================================================
// Error Types
// =============================================================================

/// Core module error set
pub const CoreError = error{
    /// Memory allocation failed
    OutOfMemory,
    /// Invalid configuration provided
    InvalidConfiguration,
    /// Resource not found
    ResourceNotFound,
    /// Operation timed out
    Timeout,
    /// System not initialized
    NotInitialized,
    /// System already initialized
    AlreadyInitialized,
    /// Invalid handle or reference
    InvalidHandle,
    /// Thread synchronization error
    SyncError,
    /// I/O operation failed
    IoError,
    /// Unsupported operation
    Unsupported,
};

// =============================================================================
// Module Initialization
// =============================================================================

/// Initialize core systems
///
/// This function initializes all core subsystems in the correct order.
/// Must be called before using any core functionality.
///
/// **Thread Safety**: Not thread-safe, call from main thread only
pub fn init(alloc: Allocator, cfg: Config) CoreError!void {
    // Initialize logging first
    try log.init(alloc, cfg.log_config);

    // Initialize time system
    try time.init();

    // Initialize other systems as needed
    std.log.info("Core systems initialized", .{});
}

/// Shutdown core systems
///
/// This function cleanly shuts down all core subsystems.
/// Must be called before program exit to ensure clean shutdown.
///
/// **Thread Safety**: Not thread-safe, call from main thread only
pub fn deinit() void {
    // Shutdown in reverse order
    time.deinit();
    log.deinit();

    std.log.info("Core systems shut down", .{});
}

// =============================================================================
// Tests
// =============================================================================

test "core module imports" {
    // Ensure all submodules compile
    std.testing.refAllDecls(@This());
}

test "core initialization" {
    const testing = std.testing;
    const test_alloc = testing.allocator;

    const cfg = Config{
        .log_config = .{
            .level = .info,
            .enable_colors = false,
        },
    };

    try init(test_alloc, cfg);
    defer deinit();

    // Verify systems are initialized
    try testing.expect(log.isInitialized());
    try testing.expect(time.isInitialized());
}
