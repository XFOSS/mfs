const std = @import("std");
const types = @import("../../types.zig");
const interface = @import("../interface.zig");

/// Common command buffer pool/allocator utilities
pub const CommandPoolDesc = struct {
    queue_type: QueueType,
    flags: u32 = 0,
};

pub const QueueType = enum {
    graphics,
    compute,
    transfer,
    sparse_binding,
};

/// Common command buffer recording state tracking
pub const CommandBufferState = enum {
    initial,
    recording,
    executable,
    pending,
};

/// Common command buffer utilities
pub fn resetCommandBuffer(cmd: *anyopaque) void {
    _ = cmd;
    // Implementation varies by backend
}

pub fn beginCommandBufferRecording(cmd: *anyopaque, flags: u32) void {
    _ = cmd;
    _ = flags;
    // Implementation varies by backend
}

pub fn endCommandBufferRecording(cmd: *anyopaque) void {
    _ = cmd;
    // Implementation varies by backend
}

/// Common render pass utilities
pub const RenderPassBeginDesc = struct {
    render_targets: []const RenderTargetDesc,
    depth_target: ?DepthTargetDesc = null,
    clear_values: []const ClearValue,
};

pub const LoadAction = interface.LoadAction;
pub const StoreAction = interface.StoreAction;

pub const RenderTargetDesc = struct {
    texture: *types.Texture,
    mip_level: u32 = 0,
    array_slice: u32 = 0,
    load_action: LoadAction = .clear,
    store_action: StoreAction = .store,
};

pub const DepthTargetDesc = struct {
    texture: *types.Texture,
    mip_level: u32 = 0,
    array_slice: u32 = 0,
    depth_load_action: LoadAction = .clear,
    depth_store_action: StoreAction = .store,
    stencil_load_action: LoadAction = .clear,
    stencil_store_action: StoreAction = .store,
};

pub const ClearValue = union(enum) {
    color: [4]f32,
    depth_stencil: struct {
        depth: f32,
        stencil: u32,
    },
};
