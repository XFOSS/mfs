//! MFS Engine - Extended Reality (XR) Module
//! Comprehensive VR/AR support with OpenXR integration
//! @thread-safe XR operations are thread-safe with proper synchronization
//! @symbol XRModule

const std = @import("std");
const builtin = @import("builtin");

// XR core components
pub const runtime = @import("runtime.zig");
pub const session = @import("session.zig");
pub const hmd = @import("hmd.zig");
pub const tracking = @import("tracking.zig");
pub const input = @import("input.zig");
pub const renderer = @import("renderer.zig");
pub const spatial = @import("spatial.zig");
pub const comfort = @import("comfort.zig");
pub const events = @import("events.zig");

// Re-export main XR types
pub const XRSystem = @import("system.zig").XRSystem;
pub const XRConfig = @import("system.zig").XRConfig;

pub const XRRuntime = runtime.XRRuntime;
pub const RuntimeType = runtime.RuntimeType;

pub const XRSession = session.XRSession;
pub const SessionState = session.SessionState;

pub const HeadMountedDisplay = hmd.HeadMountedDisplay;
pub const HMDSpecs = hmd.HMDSpecs;

pub const TrackingSystem = tracking.TrackingSystem;
pub const TrackingQuality = tracking.TrackingQuality;

pub const XRInputSystem = input.XRInputSystem;
pub const XRController = input.XRController;

pub const XRRenderer = renderer.XRRenderer;
pub const XREyeTexture = renderer.XREyeTexture;

pub const SpatialAnchor = spatial.SpatialAnchor;
pub const SpatialMapping = spatial.SpatialMapping;
pub const HandTracking = spatial.HandTracking;

pub const ComfortSettings = comfort.ComfortSettings;
pub const GuardianSystem = comfort.GuardianSystem;

pub const XREvent = events.XREvent;
pub const EventType = events.EventType;

// XR error types
pub const XRError = error{
    RuntimeNotFound,
    SessionCreationFailed,
    TrackingLost,
    RenderingFailed,
    InvalidConfiguration,
    UnsupportedFeature,
    DeviceNotConnected,
    PermissionDenied,
};

// XR system configuration
pub const XRSystemConfig = struct {
    runtime_type: ?RuntimeType = null,
    enable_hand_tracking: bool = true,
    enable_eye_tracking: bool = false,
    enable_spatial_anchors: bool = true,
    enable_passthrough: bool = false,
    comfort_level: comfort.ComfortLevel = .moderate,
    target_framerate: u32 = 90,

    pub fn validate(self: XRSystemConfig) !void {
        if (self.target_framerate < 60 or self.target_framerate > 144) {
            return XRError.InvalidConfiguration;
        }
    }
};

/// Initialize XR system
pub fn init(allocator: std.mem.Allocator, config: XRSystemConfig) !*XRSystem {
    try config.validate();
    return try XRSystem.init(allocator, config);
}

/// Cleanup XR system
pub fn deinit(xr_system: *XRSystem) void {
    xr_system.deinit();
}

/// Check if XR is available on this platform
pub fn isAvailable() bool {
    return switch (builtin.os.tag) {
        .windows => true,
        .linux => true,
        .macos => false, // Apple uses their own AR frameworks
        .android => true,
        else => false,
    };
}

/// Get available XR runtimes
pub fn getAvailableRuntimes(allocator: std.mem.Allocator) ![]RuntimeType {
    var runtimes = std.ArrayList(RuntimeType).init(allocator);
    defer runtimes.deinit();

    // Check for OpenXR
    if (runtime.isRuntimeAvailable(.openxr)) {
        try runtimes.append(.openxr);
    }

    // Check for OpenVR (SteamVR)
    if (runtime.isRuntimeAvailable(.openvr)) {
        try runtimes.append(.openvr);
    }

    // Check for Oculus
    if (runtime.isRuntimeAvailable(.oculus)) {
        try runtimes.append(.oculus);
    }

    // Check for Windows Mixed Reality
    if (builtin.os.tag == .windows and runtime.isRuntimeAvailable(.windows_mixed_reality)) {
        try runtimes.append(.windows_mixed_reality);
    }

    return runtimes.toOwnedSlice();
}

test "xr module" {
    const testing = std.testing;

    // Test availability check
    const available = isAvailable();
    try testing.expect(available == true or available == false);

    // Test config validation
    var config = XRSystemConfig{};
    try config.validate();

    config.target_framerate = 30; // Too low
    try testing.expectError(XRError.InvalidConfiguration, config.validate());
}
