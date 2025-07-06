//! MFS Engine - Software Graphics Backend
//! Provides a software-based fallback renderer
//! Always available regardless of platform or hardware

const std = @import("std");
const interface = @import("../interface.zig");
const types = @import("../../types.zig");

/// Software backend implementation
pub const SoftwareBackend = struct {
    allocator: std.mem.Allocator,
    config: interface.BackendConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: interface.BackendConfig) !*Self {
        const backend = try allocator.create(Self);
        backend.* = Self{
            .allocator = allocator,
            .config = config,
        };
        return backend;
    }

    pub fn deinit(self: *Self) void {
        // Clean up any resources
        _ = self;
        // Note: Don't destroy self here - that's handled by the caller
    }

    // VTable wrapper functions
    fn deinitWrapper(impl_data: *anyopaque) void {
        const self = @as(*Self, @ptrCast(@alignCast(impl_data)));
        self.deinit();
        // Note: Don't destroy self here - that's handled by destroyBackend
    }

    // SwapChain management stubs
    fn createSwapChainWrapper(impl_data: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = desc;
        // Software rendering doesn't need a real swap chain
    }

    fn resizeSwapChainWrapper(impl_data: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = width;
        _ = height;
        // Software rendering doesn't need swap chain resize
    }

    fn presentWrapper(impl_data: *anyopaque) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        // Software rendering present - do nothing for now
    }

    fn getCurrentBackBufferWrapper(impl_data: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Resource creation stubs
    fn createTextureWrapper(impl_data: *anyopaque, texture: *types.Texture, data: ?[]const u8) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = texture;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createBufferWrapper(impl_data: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = buffer;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createShaderWrapper(impl_data: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = shader;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createPipelineWrapper(impl_data: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = desc;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createRenderTargetWrapper(impl_data: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = render_target;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Resource management stubs
    fn updateBufferWrapper(impl_data: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = buffer;
        _ = offset;
        _ = data;
    }

    fn updateTextureWrapper(impl_data: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = texture;
        _ = region;
        _ = data;
    }

    fn destroyTextureWrapper(impl_data: *anyopaque, texture: *types.Texture) void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = texture;
    }

    fn destroyBufferWrapper(impl_data: *anyopaque, buffer: *types.Buffer) void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = buffer;
    }

    fn destroyShaderWrapper(impl_data: *anyopaque, shader: *types.Shader) void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = shader;
    }

    fn destroyRenderTargetWrapper(impl_data: *anyopaque, render_target: *types.RenderTarget) void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = render_target;
    }

    // Command recording stubs
    fn createCommandBufferWrapper(impl_data: *anyopaque) interface.GraphicsBackendError!*interface.CommandBuffer {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn beginCommandBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
    }

    fn endCommandBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
    }

    fn submitCommandBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
    }

    // Additional required wrapper functions (basic stubs)
    fn beginRenderPassWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = desc;
    }

    fn endRenderPassWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
    }

    fn setViewportWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = viewport;
    }

    fn setScissorWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = rect;
    }

    fn bindPipelineWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = pipeline;
    }

    fn bindVertexBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
    }

    fn bindIndexBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = buffer;
        _ = offset;
        _ = format;
    }

    fn bindTextureWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = slot;
        _ = texture;
    }

    fn bindUniformBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
        _ = size;
    }

    fn drawWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = draw_cmd;
    }

    fn drawIndexedWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = draw_cmd;
    }

    fn dispatchWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = dispatch_cmd;
    }

    fn copyBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const interface.BufferCopyRegion) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyTextureWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyBufferToTextureWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyTextureToBufferWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn resourceBarrierWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = barriers;
    }

    fn getBackendInfoWrapper(impl_data: *anyopaque) interface.BackendInfo {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        return getInfo();
    }

    fn setDebugNameWrapper(impl_data: *anyopaque, resource: interface.ResourceHandle, name: []const u8) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = resource;
        _ = name;
    }

    fn beginDebugGroupWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
        _ = name;
    }

    fn endDebugGroupWrapper(impl_data: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = @as(*Self, @ptrCast(@alignCast(impl_data)));
        _ = cmd;
    }
};

/// Create a software backend instance
pub fn create(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    const backend_impl = try SoftwareBackend.init(allocator, config);

    // Create the VTable for the software backend
    const vtable = try allocator.create(interface.GraphicsBackend.VTable);
    vtable.* = interface.GraphicsBackend.VTable{
        .deinit = SoftwareBackend.deinitWrapper,
        .create_swap_chain = SoftwareBackend.createSwapChainWrapper,
        .resize_swap_chain = SoftwareBackend.resizeSwapChainWrapper,
        .present = SoftwareBackend.presentWrapper,
        .get_current_back_buffer = SoftwareBackend.getCurrentBackBufferWrapper,
        .create_texture = SoftwareBackend.createTextureWrapper,
        .create_buffer = SoftwareBackend.createBufferWrapper,
        .create_shader = SoftwareBackend.createShaderWrapper,
        .create_pipeline = SoftwareBackend.createPipelineWrapper,
        .create_render_target = SoftwareBackend.createRenderTargetWrapper,
        .update_buffer = SoftwareBackend.updateBufferWrapper,
        .update_texture = SoftwareBackend.updateTextureWrapper,
        .destroy_texture = SoftwareBackend.destroyTextureWrapper,
        .destroy_buffer = SoftwareBackend.destroyBufferWrapper,
        .destroy_shader = SoftwareBackend.destroyShaderWrapper,
        .destroy_render_target = SoftwareBackend.destroyRenderTargetWrapper,
        .create_command_buffer = SoftwareBackend.createCommandBufferWrapper,
        .begin_command_buffer = SoftwareBackend.beginCommandBufferWrapper,
        .end_command_buffer = SoftwareBackend.endCommandBufferWrapper,
        .submit_command_buffer = SoftwareBackend.submitCommandBufferWrapper,
        .begin_render_pass = SoftwareBackend.beginRenderPassWrapper,
        .end_render_pass = SoftwareBackend.endRenderPassWrapper,
        .set_viewport = SoftwareBackend.setViewportWrapper,
        .set_scissor = SoftwareBackend.setScissorWrapper,
        .bind_pipeline = SoftwareBackend.bindPipelineWrapper,
        .bind_vertex_buffer = SoftwareBackend.bindVertexBufferWrapper,
        .bind_index_buffer = SoftwareBackend.bindIndexBufferWrapper,
        .bind_texture = SoftwareBackend.bindTextureWrapper,
        .bind_uniform_buffer = SoftwareBackend.bindUniformBufferWrapper,
        .draw = SoftwareBackend.drawWrapper,
        .draw_indexed = SoftwareBackend.drawIndexedWrapper,
        .dispatch = SoftwareBackend.dispatchWrapper,
        .copy_buffer = SoftwareBackend.copyBufferWrapper,
        .copy_texture = SoftwareBackend.copyTextureWrapper,
        .copy_buffer_to_texture = SoftwareBackend.copyBufferToTextureWrapper,
        .copy_texture_to_buffer = SoftwareBackend.copyTextureToBufferWrapper,
        .resource_barrier = SoftwareBackend.resourceBarrierWrapper,
        .get_backend_info = SoftwareBackend.getBackendInfoWrapper,
        .set_debug_name = SoftwareBackend.setDebugNameWrapper,
        .begin_debug_group = SoftwareBackend.beginDebugGroupWrapper,
        .end_debug_group = SoftwareBackend.endDebugGroupWrapper,
    };

    const graphics_backend = try allocator.create(interface.GraphicsBackend);
    graphics_backend.* = interface.GraphicsBackend{
        .allocator = allocator,
        .backend_type = .software,
        .initialized = true,
        .vtable = vtable,
        .impl_data = backend_impl,
    };

    return graphics_backend;
}

/// Create a software backend instance (alternative name for compatibility)
pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
    const config = interface.BackendConfig{
        .backend_type = .software,
    };
    return create(allocator, config);
}

/// Get information about the software backend
pub fn getInfo() interface.BackendInfo {
    return interface.BackendInfo{
        .name = "Software Renderer",
        .version = "1.0.0",
        .vendor = "MFS Engine",
        .device_name = "CPU",
        .api_version = 1,
        .driver_version = 1,
        .memory_budget = 1024 * 1024 * 512, // 512MB
        .memory_usage = 0,
        .max_texture_size = 2048,
        .max_render_targets = 8,
        .max_vertex_attributes = 16,
        .max_uniform_buffer_bindings = 16,
        .max_texture_bindings = 32,
        .supports_compute = false,
        .supports_geometry_shaders = false,
        .supports_tessellation = false,
        .supports_raytracing = false,
        .supports_mesh_shaders = false,
        .supports_variable_rate_shading = false,
        .supports_multiview = false,
    };
}

test {
    _ = SoftwareBackend;
}
