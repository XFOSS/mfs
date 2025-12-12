//! MFS Engine - Main Module
//! Central import module for the MFS Engine providing access to all subsystems
//! This is the main entry point for applications using the MFS Engine

const std = @import("std");
const builtin = @import("builtin");

// =============================================================================
// Core Modules
// =============================================================================

pub const core = @import("core/mod.zig");
pub const engine = @import("engine/mod.zig");
pub const app = @import("app/mod.zig");

// =============================================================================
// Platform and System Modules
// =============================================================================

pub const platform = @import("platform/mod.zig");
pub const window = @import("window/mod.zig");
pub const build_options = @import("build_options.zig");

// =============================================================================
// Graphics and Rendering
// =============================================================================

pub const graphics = @import("graphics/mod.zig");
pub const render = @import("render/mod.zig");
pub const shaders = @import("shaders/mod.zig");

// =============================================================================
// Audio System
// =============================================================================

pub const audio = @import("audio/mod.zig");

// =============================================================================
// Physics System
// =============================================================================

pub const physics = @import("physics/mod.zig");

// =============================================================================
// Scene Management
// =============================================================================

pub const scene = @import("scene/mod.zig");

// =============================================================================
// Input System
// =============================================================================

pub const input = @import("input/mod.zig");

// =============================================================================
// Math and Utilities
// =============================================================================

pub const math = @import("libs/math/mod.zig");
pub const utils = @import("libs/utils/mod.zig");

// =============================================================================
// User Interface
// =============================================================================

pub const ui = @import("ui/mod.zig");

// =============================================================================
// Specialized Modules
// =============================================================================

pub const voxels = @import("voxels/mod.zig");
pub const xr = @import("xr.zig");

// =============================================================================
// Next-Generation Evolution Modules
// =============================================================================

pub const ai = @import("ai/mod.zig");
pub const networking = @import("networking/mod.zig");
pub const community = @import("community/mod.zig");
pub const tools = @import("tools/mod.zig");
pub const system = @import("system/mod.zig");

// =============================================================================
// Configuration and Build Options
// =============================================================================

pub const config = build_options;

// =============================================================================
// Version Information
// =============================================================================

pub const version = struct {
    pub const major = 1;
    pub const minor = 0;
    pub const patch = 0;
    pub const string = "1.0.0";
    pub const name = "MFS Engine";

    pub fn getFullVersionString() []const u8 {
        return name ++ " v" ++ string;
    }
};

// =============================================================================
// Platform Information
// =============================================================================

pub const Platform = struct {
    pub fn getName() []const u8 {
        return @tagName(builtin.os.tag);
    }

    pub fn getArchName() []const u8 {
        return @tagName(builtin.cpu.arch);
    }

    pub const is_desktop = switch (builtin.os.tag) {
        .windows, .linux, .macos => true,
        else => false,
    };

    pub const is_mobile = switch (builtin.os.tag) {
        .ios, .android => true,
        else => false,
    };

    pub const is_web = switch (builtin.os.tag) {
        .emscripten, .wasi, .freestanding => true,
        else => false,
    };
};

// =============================================================================
// Public API
// =============================================================================

/// Initialize the MFS Engine with configuration
pub fn init(allocator: std.mem.Allocator, app_config: engine.Config) !*engine.Application {
    return try engine.init(allocator, app_config);
}

/// Initialize the MFS Engine with custom configuration
pub fn initWithConfig(allocator: std.mem.Allocator, engine_config: engine.Config) !*engine.Application {
    return try engine.init(allocator, engine_config);
}

/// Cleanup the MFS Engine
pub fn deinit(application: *engine.Application) void {
    engine.deinit(application);
}

/// Get engine version information
pub fn getVersion() []const u8 {
    return version.getFullVersionString();
}

/// Check if a specific graphics backend is available
pub fn isBackendAvailable(backend: graphics.BackendType) bool {
    return backend.isAvailable();
}

/// Get platform information
pub fn getPlatformInfo() struct {
    os: []const u8,
    arch: []const u8,
    is_desktop: bool,
    is_mobile: bool,
    is_web: bool,
} {
    return .{
        .os = Platform.getName(),
        .arch = Platform.getArchName(),
        .is_desktop = Platform.is_desktop,
        .is_mobile = Platform.is_mobile,
        .is_web = Platform.is_web,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "mfs module" {
    std.testing.refAllDecls(@This());
}

test "version info" {
    const v = getVersion();
    try std.testing.expect(v.len > 0);
}

test "platform info" {
    const info = getPlatformInfo();
    try std.testing.expect(info.os.len > 0);
    try std.testing.expect(info.arch.len > 0);
}
