const std = @import("std");
const interface = @import("../interface.zig");

/// Common resource cleanup utilities shared across backends
pub fn cleanupSwapChainResources(allocator: std.mem.Allocator, render_targets: []?*anyopaque) void {
    for (render_targets) |rt| {
        if (rt) |resource| {
            allocator.destroy(resource);
        }
    }
}

/// Common descriptor heap management
pub const DescriptorHeapDesc = struct {
    type: enum {
        rtv,
        dsv,
        cbv_srv_uav,
    },
    num_descriptors: u32,
    flags: u32 = 0,
};

pub const ResourceState = interface.ResourceState;
pub const SubresourceRange = interface.SubresourceRange;

pub const ResourceBarrierDesc = struct {
    resource: *anyopaque,
    old_state: ResourceState,
    new_state: ResourceState,
    subresource: SubresourceRange = .{},
};

/// Common debug utilities
pub fn setDebugName(resource: *anyopaque, name: []const u8) void {
    _ = resource;
    _ = name;
    // Implementation varies by backend
}

pub fn beginDebugGroup(cmd: *anyopaque, name: []const u8) void {
    _ = cmd;
    _ = name;
    // Implementation varies by backend
}

pub fn endDebugGroup(cmd: *anyopaque) void {
    _ = cmd;
    // Implementation varies by backend
}
