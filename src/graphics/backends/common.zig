const types = @import("../types.zig");
pub const formats = @import("common/formats.zig");
pub const resource = @import("common/resource_management.zig");
pub const sync = @import("common/sync.zig");
pub const commands = @import("common/commands.zig");
pub const shaders = @import("common/shaders.zig");
pub const pipeline_cache = @import("common/pipeline_cache.zig");

// Re-export commonly used types and functions
pub const ResourceState = resource.ResourceState;
pub const SubresourceRange = resource.SubresourceRange;
pub const LoadAction = commands.LoadAction;
pub const StoreAction = commands.StoreAction;
pub const QueueType = commands.QueueType;

// Re-export commonly used functions
pub const getBytesPerPixel = formats.getBytesPerPixel;
pub const convertTextureFormat = formats.convertTextureFormat;
pub const convertVertexFormat = formats.convertVertexFormat;

test {
    // Test the public API
    _ = formats;
    _ = resource;
    _ = sync;
    _ = commands;
}
