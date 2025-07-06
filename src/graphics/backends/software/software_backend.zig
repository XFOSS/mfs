//! Software backend implementation for CPU rasterization fallback
const std = @import("std");
const builtin = @import("builtin");
const interface = @import("../interface.zig");
const types = @import("../../types.zig");
const common = @import("../common.zig");
const build_options = @import("build_options");
comptime {
    _ = build_options;
}

pub const SoftwareBackend = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,
    width: u32 = 800,
    height: u32 = 600,
    frame_buffer: ?[]u32 = null,
    depth_buffer: ?[]f32 = null,
    clear_color: types.ClearColor = types.ClearColor{},
    viewport: types.Viewport,

    const Self = @This();

    fn packColorRGBA(color: types.ClearColor) u32 {
        const r = @as(u32, @intFromFloat(color.r * 255.0)) & 0xFF;
        const g = @as(u32, @intFromFloat(color.g * 255.0)) & 0xFF;
        const b = @as(u32, @intFromFloat(color.b * 255.0)) & 0xFF;
        const a = @as(u32, @intFromFloat(color.a * 255.0)) & 0xFF;
        return (a << 24) | (r << 16) | (g << 8) | b;
    }

    const vtable = interface.GraphicsBackend.VTable{
        .deinit = deinitImpl,
        .create_swap_chain = createSwapChainImpl,
        .resize_swap_chain = resizeSwapChainImpl,
        .present = presentImpl,
        .get_current_back_buffer = getCurrentBackBufferImpl,
        .create_texture = createTextureImpl,
        .create_buffer = createBufferImpl,
        .create_shader = createShaderImpl,
        .create_pipeline = createPipelineImpl,
        .create_render_target = createRenderTargetImpl,
        .update_buffer = updateBufferImpl,
        .update_texture = updateTextureImpl,
        .destroy_texture = destroyTextureImpl,
        .destroy_buffer = destroyBufferImpl,
        .destroy_shader = destroyShaderImpl,
        .destroy_render_target = destroyRenderTargetImpl,
        .create_command_buffer = createCommandBufferImpl,
        .begin_command_buffer = beginCommandBufferImpl,
        .end_command_buffer = endCommandBufferImpl,
        .submit_command_buffer = submitCommandBufferImpl,
        .begin_render_pass = beginRenderPassImpl,
        .end_render_pass = endRenderPassImpl,
        .set_viewport = setViewportImpl,
        .set_scissor = setScissorImpl,
        .bind_pipeline = bindPipelineImpl,
        .bind_vertex_buffer = bindVertexBufferImpl,
        .bind_index_buffer = bindIndexBufferImpl,
        .bind_texture = bindTextureImpl,
        .bind_uniform_buffer = bindUniformBufferImpl,
        .draw = drawImpl,
        .draw_indexed = drawIndexedImpl,
        .dispatch = dispatchImpl,
        .copy_buffer = copyBufferImpl,
        .copy_texture = copyTextureImpl,
        .copy_buffer_to_texture = copyBufferToTextureImpl,
        .copy_texture_to_buffer = copyTextureToBufferImpl,
        .resource_barrier = resourceBarrierImpl,
        .get_backend_info = getBackendInfoImpl,
        .set_debug_name = setDebugNameImpl,
        .begin_debug_group = beginDebugGroupImpl,
        .end_debug_group = endDebugGroupImpl,
    };

    /// Create and initialize a software backend, returning a pointer to the interface.GraphicsBackend
    pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        const backend = try allocator.create(Self);
        backend.* = Self{
            .allocator = allocator,
            .viewport = types.Viewport{ .width = 800, .height = 600 },
        };

        try backend.initializeBuffers();

        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .software,
            .vtable = &vtable,
            .impl_data = backend,
            .initialized = true,
        };

        std.log.info("Software renderer backend initialized", .{});
        return graphics_backend;
    }

    fn initializeBuffers(self: *Self) !void {
        const pixel_count = self.width * self.height;
        self.frame_buffer = try self.allocator.alloc(u32, pixel_count);
        self.depth_buffer = try self.allocator.alloc(f32, pixel_count);

        // Clear buffers
        @memset(self.frame_buffer.?, 0x00000000);
        for (self.depth_buffer.?) |*depth| {
            depth.* = 1.0;
        }

        self.initialized = true;
    }

    // Implementation functions
    fn deinitImpl(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.deinitInternal();
    }

    fn deinitInternal(self: *Self) void {
        if (!self.initialized) return;

        if (self.frame_buffer) |fb| {
            self.allocator.free(fb);
        }
        if (self.depth_buffer) |db| {
            self.allocator.free(db);
        }

        self.initialized = false;
        self.allocator.destroy(self);
    }

    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Resize buffers if needed
        if (self.width != desc.width or self.height != desc.height) {
            self.width = desc.width;
            self.height = desc.height;

            // Reallocate buffers
            if (self.frame_buffer) |fb| {
                self.allocator.free(fb);
            }
            if (self.depth_buffer) |db| {
                self.allocator.free(db);
            }

            try self.initializeBuffers();
        }
    }

    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        self.width = width;
        self.height = height;

        // Reallocate buffers
        if (self.frame_buffer) |fb| {
            self.allocator.free(fb);
        }
        if (self.depth_buffer) |db| {
            self.allocator.free(db);
        }

        try self.initializeBuffers();
    }

    fn presentImpl(impl: *anyopaque) interface.GraphicsBackendError!void {
        _ = impl;
        // In a real implementation, this would copy the frame buffer to the screen
        // For now, this is a no-op
    }

    fn getCurrentBackBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        const self: *Self = @ptrCast(@alignCast(impl));

        const texture = try self.allocator.create(types.Texture);
        texture.* = types.Texture{
            .id = @intFromPtr(self.frame_buffer.?.ptr),
            .width = self.width,
            .height = self.height,
            .depth = 1,
            .format = .rgba8,
            .texture_type = .texture_2d,
            .mip_levels = 1,
            .allocator = self.allocator,
        };

        return texture;
    }

    fn createTextureImpl(impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        const pixel_count = texture.width * texture.height * texture.depth;
        const bytes_per_pixel = common.getBytesPerPixel(texture.format);
        const total_bytes = pixel_count * bytes_per_pixel;

        const texture_data = try self.allocator.alloc(u8, total_bytes);

        if (data) |initial_data| {
            const copy_size = @min(initial_data.len, total_bytes);
            @memcpy(texture_data[0..copy_size], initial_data[0..copy_size]);
        } else {
            @memset(texture_data, 0);
        }

        texture.id = @intFromPtr(texture_data.ptr);
    }

    fn createBufferImpl(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        const buffer_data = try self.allocator.alloc(u8, buffer.size);

        if (data) |initial_data| {
            const copy_size = @min(initial_data.len, buffer.size);
            @memcpy(buffer_data[0..copy_size], initial_data[0..copy_size]);
        } else {
            @memset(buffer_data, 0);
        }

        buffer.id = @intFromPtr(buffer_data.ptr);
    }

    fn createShaderImpl(impl: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        _ = impl;

        // Software renderer doesn't compile shaders, just mark as compiled
        shader.id = 1; // Non-zero to indicate success
        shader.compiled = true;
    }

    fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = desc;

        const pipeline = try self.allocator.create(interface.Pipeline);
        pipeline.* = interface.Pipeline{
            .id = 1,
            .backend_handle = undefined,
            .allocator = self.allocator,
        };

        return pipeline;
    }

    fn createRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        _ = impl;
        _ = render_target;
        // Software renderer uses frame buffer directly
    }

    fn updateBufferImpl(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;

        const buffer_ptr: [*]u8 = @ptrFromInt(buffer.id);
        const dest_slice = buffer_ptr[offset .. offset + data.len];
        @memcpy(dest_slice, data);
    }

    fn updateTextureImpl(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = texture;
        _ = region;
        _ = data;
        // Simplified implementation
    }

    fn destroyTextureImpl(impl: *anyopaque, texture: *types.Texture) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (texture.id != 0) {
            const texture_ptr: [*]u8 = @ptrFromInt(texture.id);
            const bytes_per_pixel = common.getBytesPerPixel(texture.format);
            const total_bytes = texture.width * texture.height * texture.depth * bytes_per_pixel;
            self.allocator.free(texture_ptr[0..total_bytes]);
            texture.id = 0;
        }
    }

    fn destroyBufferImpl(impl: *anyopaque, buffer: *types.Buffer) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (buffer.id != 0) {
            const buffer_ptr: [*]u8 = @ptrFromInt(buffer.id);
            self.allocator.free(buffer_ptr[0..buffer.size]);
            buffer.id = 0;
        }
    }

    fn destroyShaderImpl(impl: *anyopaque, shader: *types.Shader) void {
        _ = impl;
        shader.id = 0;
        shader.compiled = false;
    }

    fn destroyRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) void {
        _ = impl;
        _ = render_target;
    }

    fn createCommandBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*interface.CommandBuffer {
        const self: *Self = @ptrCast(@alignCast(impl));

        const cmd = try self.allocator.create(interface.CommandBuffer);
        cmd.* = interface.CommandBuffer{
            .id = 0,
            .backend_handle = undefined,
            .allocator = self.allocator,
        };

        return cmd;
    }

    fn beginCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        cmd.recording = true;
    }

    fn endCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        cmd.recording = false;
    }

    fn submitCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        // Software renderer executes immediately
    }

    fn beginRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        // Clear frame buffer
        if (self.frame_buffer) |fb| {
            const clear_color_u32 = packColorRGBA(desc.clear_color);
            @memset(fb, clear_color_u32);
        }

        // Clear depth buffer
        if (self.depth_buffer) |db| {
            for (db) |*depth| {
                depth.* = desc.clear_depth;
            }
        }
    }

    fn endRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
    }

    fn setViewportImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        self.viewport = viewport.*;
    }

    fn setScissorImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = rect;
        // Software renderer doesn't implement scissor test
    }

    fn bindPipelineImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = pipeline;
    }

    fn bindVertexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
    }

    fn bindIndexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = buffer;
        _ = offset;
        _ = format;
    }

    fn bindTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = texture;
    }

    fn bindUniformBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
        _ = size;
    }

    fn drawImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        // Simple software rendering - draw colored triangles
        if (self.frame_buffer) |fb| {
            const color = 0xFF00FF00; // Green
            const center_x = self.width / 2;
            const center_y = self.height / 2;
            const size = 50;

            for (0..draw_cmd.vertex_count / 3) |_| {
                // Draw a simple triangle
                for (0..size) |y| {
                    for (0..size) |x| {
                        const px = center_x + x - size / 2;
                        const py = center_y + y - size / 2;

                        if (px < self.width and py < self.height) {
                            fb[py * self.width + px] = color;
                        }
                    }
                }
            }
        }
    }

    fn drawIndexedImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = draw_cmd;
        // Software renderer doesn't implement indexed drawing
    }

    fn dispatchImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = dispatch_cmd;
        // Software renderer doesn't support compute
        return interface.GraphicsBackendError.InvalidOperation;
    }

    fn copyBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const interface.BufferCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        const src_ptr: [*]u8 = @ptrFromInt(src.id);
        const dst_ptr: [*]u8 = @ptrFromInt(dst.id);

        const src_slice = src_ptr[region.src_offset .. region.src_offset + region.size];
        const dst_slice = dst_ptr[region.dst_offset .. region.dst_offset + region.size];

        @memcpy(dst_slice, src_slice);
    }

    fn copyTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        // Software renderer doesn't implement texture copying
    }

    fn copyBufferToTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        // Software renderer doesn't implement buffer to texture copying
    }

    fn copyTextureToBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        // Software renderer doesn't implement texture to buffer copying
    }

    fn resourceBarrierImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = barriers;
        // Software renderer doesn't need resource barriers
    }

    fn getBackendInfoImpl(impl: *anyopaque) interface.BackendInfo {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = self;

        return interface.BackendInfo{
            .name = "Software Renderer",
            .version = "1.0",
            .vendor = "MFS Engine",
            .device_name = "CPU",
            .api_version = 1,
            .driver_version = 0,
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 4096,
            .max_render_targets = 1,
            .max_vertex_attributes = 8,
            .max_uniform_buffer_bindings = 8,
            .max_texture_bindings = 8,
            .supports_compute = false,
            .supports_geometry_shaders = false,
            .supports_tessellation = false,
            .supports_raytracing = false,
            .supports_mesh_shaders = false,
            .supports_variable_rate_shading = false,
            .supports_multiview = false,
        };
    }

    fn setDebugNameImpl(impl: *anyopaque, resource: interface.ResourceHandle, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = resource;
        _ = name;
        // Software renderer doesn't support debug names
    }

    fn beginDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = name;
        // Software renderer doesn't support debug groups
    }

    fn endDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        // Software renderer doesn't support debug groups
    }
};

/// Create a software backend instance (module-level wrapper for SoftwareBackend.createBackend)
pub fn create(allocator: std.mem.Allocator, config: anytype) !*interface.GraphicsBackend {
    _ = config; // Config not used yet but may be in the future
    return SoftwareBackend.createBackend(allocator);
}
