//! MFS Engine - Graphics Backend Manager
//! Centralizes backend selection, initialization, and management
//! Provides unified interface for all graphics backends

const std = @import("std");
const backends = @import("backends/mod.zig");
const build_options = @import("../build_options.zig");

pub const BackendType = build_options.Backend;
pub const BackendInterface = backends.BackendInterface;
pub const BackendConfig = backends.interface.BackendConfig;

/// Backend manager for centralized backend handling
pub const BackendManager = struct {
    allocator: std.mem.Allocator,
    current_backend: ?*BackendInterface = null,
    config: BackendConfig,

    pub fn init(allocator: std.mem.Allocator, config: BackendConfig) !BackendManager {
        try config.validate();
        return BackendManager{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *BackendManager) void {
        if (self.current_backend) |backend| {
            backends.destroyBackend(backend);
            self.current_backend = null;
        }
    }

    pub fn createBackend(self: *BackendManager) !*BackendInterface {
        if (self.current_backend) |backend| {
            return backend;
        }

        // Create backend based on configuration
        const backend_type = if (self.config.backend_type == .auto)
            backends.getPreferredBackend()
        else
            self.config.backend_type;

        // Update config with resolved backend type
        var config = self.config;
        config.backend_type = backend_type;

        self.current_backend = try backends.createBackend(self.allocator, config);
        return self.current_backend.?;
    }

    pub fn switchBackend(self: *BackendManager, new_backend_type: BackendType) !*BackendInterface {
        if (self.current_backend) |backend| {
            backends.destroyBackend(backend);
            self.current_backend = null;
        }

        self.config.backend_type = new_backend_type;
        return try self.createBackend();
    }

    pub fn getCurrentBackend(self: *BackendManager) ?*BackendInterface {
        return self.current_backend;
    }

    pub fn getPrimaryBackend(self: *BackendManager) ?*BackendInterface {
        return self.current_backend;
    }

    pub fn isBackendCreated(self: *BackendManager) bool {
        return self.current_backend != null;
    }

    // Removed convertToInterfaceConfig since it's not needed anymore
};

/// Create a backend instance directly
pub fn createBackend(allocator: std.mem.Allocator, config: BackendConfig) !*BackendInterface {
    try config.validate();

    // Create backend based on configuration
    const backend_type = if (config.backend_type == .auto)
        backends.getPreferredBackend()
    else
        config.backend_type;

    // Update config with resolved backend type
    var resolved_config = config;
    resolved_config.backend_type = backend_type;

    return try backends.createBackend(allocator, resolved_config);
}

/// Get available backends
pub fn getAvailableBackends() []const BackendType {
    // Return a static list of all backends that could potentially be available
    // The actual availability is checked at runtime by the backend itself
    return &[_]BackendType{
        .software,
        .vulkan,
        .d3d11,
        .d3d12,
        .metal,
        .opengl,
        .opengles,
        .webgpu,
    };
}

/// Check if a backend is supported
pub fn isBackendSupported(backend_type: BackendType) bool {
    return backends.isBackendSupported(backend_type);
}

/// Get the preferred backend for the current platform
pub fn getPreferredBackend() BackendType {
    return backends.getPreferredBackend();
}

/// Print backend information
pub fn printBackendInfo() void {
    backends.printBackendInfo();
}

/// Errors that can occur during backend management
pub const BackendManagerError = error{
    InvalidWindowSize,
    InvalidSampleCount,
    BackendNotAvailable,
    InitializationFailed,
    BackendAlreadyCreated,
    NoBackendCreated,
};

test "backend manager" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test configuration validation
    var config = BackendConfig{};
    try config.validate();

    // Test backend manager creation
    var manager = try BackendManager.init(allocator, config);
    defer manager.deinit();

    try testing.expect(!manager.isBackendCreated());
    try testing.expect(manager.getCurrentBackend() == null);

    // Test backend availability
    try testing.expect(isBackendSupported(.software));

    const preferred = getPreferredBackend();
    try testing.expect(preferred.isAvailable());
}
