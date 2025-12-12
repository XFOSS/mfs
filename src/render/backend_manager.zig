//! Render-layer BackendManager wrapper
//! Thin shim that forwards to the canonical implementation that currently
//! lives in `graphics/backend_manager.zig`.  This keeps older include paths
//! working while we reorganise the codebase.

const gfx_backend_mgr = @import("../graphics/backend_manager.zig");

pub const BackendType = gfx_backend_mgr.BackendType;
pub const BackendInterface = gfx_backend_mgr.BackendInterface;
pub const BackendConfig = gfx_backend_mgr.BackendConfig;

pub const BackendManager = gfx_backend_mgr.BackendManager;

pub const createBackend = gfx_backend_mgr.createBackend;
pub const getAvailableBackends = gfx_backend_mgr.getAvailableBackends;
pub const isBackendSupported = gfx_backend_mgr.isBackendSupported;
pub const getPreferredBackend = gfx_backend_mgr.getPreferredBackend;

pub const printBackendInfo = gfx_backend_mgr.printBackendInfo;

pub const BackendManagerError = gfx_backend_mgr.BackendManagerError;

test "render backend manager wrapper compiles" {
    @import("std").testing.refAllDecls(@This());
}
