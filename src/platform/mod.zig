//! MFS Engine - Platform Module
//! Platform abstraction layer providing cross-platform functionality
//! Handles OS-specific operations, capabilities detection, and platform services
//! @thread-safe Platform operations are generally thread-safe
//! @performance Optimized for minimal overhead abstraction

const std = @import("std");
const builtin = @import("builtin");

// Core platform components
pub const platform = @import("platform.zig");
pub const capabilities = @import("capabilities.zig");

// Platform-specific modules
pub const web = if (builtin.os.tag == .wasi) @import("web/web_platform.zig") else struct {};

// Re-export main platform types
pub const Platform = platform.Platform;
pub const PlatformConfig = platform.PlatformConfig;
pub const Capabilities = capabilities.Capabilities;
pub const GraphicsBackend = capabilities.GraphicsBackend;

// Platform types
pub const PlatformType = enum {
    windows,
    macos,
    linux,
    web,
    android,
    ios,

    pub fn current() PlatformType {
        return switch (builtin.os.tag) {
            .windows => .windows,
            .macos => .macos,
            .linux => .linux,
            .wasi => .web,
            else => .linux, // Default fallback
        };
    }

    pub fn getName(self: PlatformType) []const u8 {
        return switch (self) {
            .windows => "Windows",
            .macos => "macOS",
            .linux => "Linux",
            .web => "Web",
            .android => "Android",
            .ios => "iOS",
        };
    }

    pub fn isDesktop(self: PlatformType) bool {
        return switch (self) {
            .windows, .macos, .linux => true,
            .web, .android, .ios => false,
        };
    }

    pub fn isMobile(self: PlatformType) bool {
        return switch (self) {
            .android, .ios => true,
            .windows, .macos, .linux, .web => false,
        };
    }
};

// Platform configuration
pub const PlatformSystemConfig = struct {
    enable_high_dpi: bool = true,
    enable_vsync: bool = true,
    enable_borderless: bool = false,
    enable_resizable: bool = true,
    min_window_width: u32 = 320,
    min_window_height: u32 = 240,

    pub fn validate(self: PlatformSystemConfig) !void {
        if (self.min_window_width == 0 or self.min_window_width > 4096) {
            return error.InvalidParameter;
        }
        if (self.min_window_height == 0 or self.min_window_height > 4096) {
            return error.InvalidParameter;
        }
    }
};

// Initialize platform system
pub fn init(allocator: std.mem.Allocator, config: PlatformSystemConfig) !*Platform {
    try config.validate();
    return try Platform.init(allocator, config);
}

// Cleanup platform system
pub fn deinit(platform_instance: *Platform) void {
    platform_instance.deinit();
}

// Get current platform information
pub fn getCurrentPlatform() PlatformType {
    return PlatformType.current();
}

// Check if a feature is supported on current platform
pub fn isFeatureSupported(feature: []const u8) bool {
    const caps = capabilities.detect();
    return caps.hasFeature(feature);
}

test "platform module" {
    std.testing.refAllDecls(@This());
}
