const std = @import("std");
const builtin = @import("builtin");
const interface = @import("interface.zig");
const types = @import("../types.zig");

// OpenGL ES C bindings
const c = @cImport({
    @cInclude("GLES3/gl3.h");
    @cInclude("GLES3/gl3ext.h");
    @cInclude("EGL/egl.h");
});

pub const OpenGLESBackend = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,
    version_major: u32 = 0,
    version_minor: u32 = 0,
    extensions: std.ArrayList([]const u8),
    current_program: u32 = 0,
    current_texture_slots: [16]u32 = [_]u32{0} ** 16,
    current_vao: u32 = 0,
    viewport: types.Viewport,
    clear_color: types.ClearColor = types.ClearColor{},
    width: u32 = 0,
    height: u32 = 0,
    egl_display: ?c.EGLDisplay = null,
    egl_context: ?c.EGLContext = null,
    egl_surface: ?c.EGLSurface = null,

    const Self = @This();

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

    pub fn init(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        if (builtin.os.tag != .linux and builtin.os.tag != .ios) {
            return interface.GraphicsBackendError.BackendNotAvailable;
        }

        const backend = try allocator.create(Self);
        backend.* = Self{
            .allocator = allocator,
            .extensions = std.ArrayList([]const u8).init(allocator),
            .viewport = types.Viewport{ .width = 800, .height = 600 },
        };

        try backend.initializeContext();

        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .opengles,
            .vtable = &vtable,
            .impl_data = backend,
            .initialized = true,
        };

        return graphics_backend;
    }

    fn initializeContext(self: *Self) !void {
        if (builtin.os.tag == .linux) {
            // Android EGL initialization
            self.egl_display = c.eglGetDisplay(c.EGL_DEFAULT_DISPLAY);
            if (self.egl_display == c.EGL_NO_DISPLAY) {
                return interface.GraphicsBackendError.InitializationFailed;
            }

            var major: c.EGLint = 0;
            var minor: c.EGLint = 0;
            if (c.eglInitialize(self.egl_display, &major, &minor) == c.EGL_FALSE) {
                return interface.GraphicsBackendError.InitializationFailed;
            }

            const config_attribs = [_]c.EGLint{
                c.EGL_SURFACE_TYPE,    c.EGL_WINDOW_BIT,
                c.EGL_BLUE_SIZE,       8,
                c.EGL_GREEN_SIZE,      8,
                c.EGL_RED_SIZE,        8,
                c.EGL_ALPHA_SIZE,      8,
                c.EGL_DEPTH_SIZE,      24,
                c.EGL_STENCIL_SIZE,    8,
                c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES3_BIT,
                c.EGL_NONE,
            };

            var config: c.EGLConfig = undefined;
            var num_configs: c.EGLint = 0;
            if (c.eglChooseConfig(self.egl_display, &config_attribs[0], &config, 1, &num_configs) == c.EGL_FALSE) {
                return interface.GraphicsBackendError.InitializationFailed;
            }

            const context_attribs = [_]c.EGLint{
                c.EGL_CONTEXT_CLIENT_VERSION, 3,
                c.EGL_NONE,
            };

            self.egl_context = c.eglCreateContext(self.egl_display, config, c.EGL_NO_CONTEXT, &context_attribs[0]);
            if (self.egl_context == c.EGL_NO_CONTEXT) {
                return interface.GraphicsBackendError.InitializationFailed;
            }
        }

        // Query OpenGL ES version and extensions
        const version_string = c.glGetString(c.GL_VERSION);
        if (version_string != null) {
            // Parse version (e.g., "OpenGL ES 3.2")
            self.version_major = 3;
            self.version_minor = 2;
        }

        // Load common extensions
        try self.extensions.append(try self.allocator.dupe(u8, "GL_EXT_texture_storage"));
        try self.extensions.append(try self.allocator.dupe(u8, "GL_OES_vertex_array_object"));

        self.initialized = true;
        std.log.info("OpenGL ES backend initialized successfully", .{});
        std.log.info("Version: {d}.{d}", .{ self.version_major, self.version_minor });
    }

    // Implementation functions
    fn deinitImpl(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.deinitInternal();
    }

    fn deinitInternal(self: *Self) void {
        if (!self.initialized) return;

        // Cleanup EGL context
        if (self.egl_display != null) {
            if (self.egl_context != null) {
                _ = c.eglDestroyContext(self.egl_display, self.egl_context);
            }
            if (self.egl_surface != null) {
                _ = c.eglDestroySurface(self.egl_display, self.egl_surface);
            }
            _ = c.eglTerminate(self.egl_display);
        }

        for (self.extensions.items) |ext| {
            self.allocator.free(ext);
        }
        self.extensions.deinit();

        self.initialized = false;
        self.allocator.destroy(self);
    }

    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        self.width = desc.width;
        self.height = desc.height;

        // Set default framebuffer
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        std.log.info("OpenGL ES swap chain created: {}x{}", .{ desc.width, desc.height });
    }

    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        self.width = width;
        self.height = height;

        c.glViewport(0, 0, @intCast(width), @intCast(height));
    }

    fn presentImpl(impl: *anyopaque) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.egl_display != null and self.egl_surface != null) {
            if (c.eglSwapBuffers(self.egl_display, self.egl_surface) == c.EGL_FALSE) {
                return interface.GraphicsBackendError.CommandSubmissionFailed;
            }
        }
    }

    fn getCurrentBackBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        const self: *Self = @ptrCast(@alignCast(impl));

        const texture = try self.allocator.create(types.Texture);
        texture.* = types.Texture{
            .id = 0, // Default framebuffer
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
        _ = impl;

        var texture_id: u32 = 0;
        c.glGenTextures(1, &texture_id);
        if (texture_id == 0) return interface.GraphicsBackendError.ResourceCreationFailed;

        texture.id = texture_id;

        const gl_target = switch (texture.texture_type) {
            .texture_2d => c.GL_TEXTURE_2D,
            .texture_cube => c.GL_TEXTURE_CUBE_MAP,
            .texture_3d => c.GL_TEXTURE_3D,
            .texture_array => c.GL_TEXTURE_2D_ARRAY,
        };

        c.glBindTexture(gl_target, texture_id);

        const gl_format = switch (texture.format) {
            .rgba8 => c.GL_RGBA,
            .rgb8 => c.GL_RGB,
            .bgra8 => c.GL_RGBA, // OpenGL ES doesn't have BGRA, use RGBA
            .r8 => c.GL_RED,
            .rg8 => c.GL_RG,
            .depth24_stencil8 => c.GL_DEPTH24_STENCIL8,
            .depth32f => c.GL_DEPTH_COMPONENT32F,
        };

        const gl_type = switch (texture.format) {
            .rgba8, .rgb8, .bgra8, .r8, .rg8 => c.GL_UNSIGNED_BYTE,
            .depth24_stencil8 => c.GL_UNSIGNED_INT_24_8,
            .depth32f => c.GL_FLOAT,
        };

        c.glTexImage2D(
            gl_target,
            0, // mip level
            @intCast(gl_format),
            @intCast(texture.width),
            @intCast(texture.height),
            0, // border
            gl_format,
            gl_type,
            if (data) |d| d.ptr else null,
        );

        // Set texture parameters
        c.glTexParameteri(gl_target, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(gl_target, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(gl_target, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(gl_target, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
    }

    fn createBufferImpl(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        _ = impl;

        var buffer_id: u32 = 0;
        c.glGenBuffers(1, &buffer_id);
        if (buffer_id == 0) return interface.GraphicsBackendError.ResourceCreationFailed;

        buffer.id = buffer_id;

        const gl_target = switch (buffer.usage) {
            .vertex => c.GL_ARRAY_BUFFER,
            .index => c.GL_ELEMENT_ARRAY_BUFFER,
            .uniform => c.GL_UNIFORM_BUFFER,
            .storage => c.GL_SHADER_STORAGE_BUFFER,
            .staging => c.GL_COPY_READ_BUFFER,
        };

        c.glBindBuffer(gl_target, buffer_id);
        c.glBufferData(
            gl_target,
            @intCast(buffer.size),
            if (data) |d| d.ptr else null,
            c.GL_STATIC_DRAW,
        );
    }

    fn createShaderImpl(impl: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        _ = impl;

        const gl_shader_type = switch (shader.shader_type) {
            .vertex => c.GL_VERTEX_SHADER,
            .fragment => c.GL_FRAGMENT_SHADER,
            .compute => c.GL_COMPUTE_SHADER,
            else => return interface.GraphicsBackendError.UnsupportedOperation,
        };

        const shader_id = c.glCreateShader(gl_shader_type);
        if (shader_id == 0) return interface.GraphicsBackendError.ResourceCreationFailed;

        // Compile shader
        const source_ptr: [*c]const u8 = @ptrCast(shader.source.ptr);
        const source_len: i32 = @intCast(shader.source.len);
        c.glShaderSource(shader_id, 1, &source_ptr, &source_len);
        c.glCompileShader(shader_id);

        // Check compilation status
        var status: i32 = 0;
        c.glGetShaderiv(shader_id, c.GL_COMPILE_STATUS, &status);
        if (status == c.GL_FALSE) {
            var log_length: i32 = 0;
            c.glGetShaderiv(shader_id, c.GL_INFO_LOG_LENGTH, &log_length);

            if (log_length > 0) {
                const log = std.heap.page_allocator.alloc(u8, @intCast(log_length)) catch return interface.GraphicsBackendError.ResourceCreationFailed;
                defer std.heap.page_allocator.free(log);

                c.glGetShaderInfoLog(shader_id, log_length, null, @ptrCast(log.ptr));
                std.log.err("OpenGL ES shader compilation failed: {s}", .{log});
            }

            c.glDeleteShader(shader_id);
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        shader.id = shader_id;
        shader.compiled = true;
    }

    fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = desc;

        const pipeline = try self.allocator.create(interface.Pipeline);
        pipeline.* = interface.Pipeline{
            .id = 0,
            .backend_handle = undefined,
            .allocator = self.allocator,
        };

        return pipeline;
    }

    fn createRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        _ = impl;
        _ = render_target;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn updateBufferImpl(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;

        const gl_target = switch (buffer.usage) {
            .vertex => c.GL_ARRAY_BUFFER,
            .index => c.GL_ELEMENT_ARRAY_BUFFER,
            .uniform => c.GL_UNIFORM_BUFFER,
            .storage => c.GL_SHADER_STORAGE_BUFFER,
            .staging => c.GL_COPY_READ_BUFFER,
        };

        c.glBindBuffer(gl_target, buffer.id);
        c.glBufferSubData(gl_target, @intCast(offset), @intCast(data.len), data.ptr);
    }

    fn updateTextureImpl(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;

        const gl_target = switch (texture.texture_type) {
            .texture_2d => c.GL_TEXTURE_2D,
            .texture_cube => c.GL_TEXTURE_CUBE_MAP,
            .texture_3d => c.GL_TEXTURE_3D,
            .texture_array => c.GL_TEXTURE_2D_ARRAY,
        };

        c.glBindTexture(gl_target, texture.id);

        const gl_format = switch (texture.format) {
            .rgba8 => c.GL_RGBA,
            .rgb8 => c.GL_RGB,
            .bgra8 => c.GL_RGBA,
            .r8 => c.GL_RED,
            .rg8 => c.GL_RG,
            else => return interface.GraphicsBackendError.UnsupportedOperation,
        };

        c.glTexSubImage2D(
            gl_target,
            @intCast(region.dst_mip_level),
            @intCast(region.dst_offset[0]),
            @intCast(region.dst_offset[1]),
            @intCast(region.extent[0]),
            @intCast(region.extent[1]),
            gl_format,
            c.GL_UNSIGNED_BYTE,
            data.ptr,
        );
    }

    fn destroyTextureImpl(impl: *anyopaque, texture: *types.Texture) void {
        _ = impl;
        if (texture.id != 0) {
            c.glDeleteTextures(1, &texture.id);
            texture.id = 0;
        }
    }

    fn destroyBufferImpl(impl: *anyopaque, buffer: *types.Buffer) void {
        _ = impl;
        if (buffer.id != 0) {
            c.glDeleteBuffers(1, &buffer.id);
            buffer.id = 0;
        }
    }

    fn destroyShaderImpl(impl: *anyopaque, shader: *types.Shader) void {
        _ = impl;
        if (shader.id != 0) {
            c.glDeleteShader(shader.id);
            shader.id = 0;
            shader.compiled = false;
        }
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
        // OpenGL ES commands are executed immediately
    }

    fn beginRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        // Bind default framebuffer
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        // Clear buffers
        c.glClearColor(desc.clear_color.r, desc.clear_color.g, desc.clear_color.b, desc.clear_color.a);
        c.glClearDepthf(desc.clear_depth);
        c.glClearStencil(@intCast(desc.clear_stencil));
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT);

        // Set viewport
        c.glViewport(0, 0, @intCast(self.width), @intCast(self.height));
    }

    fn endRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
    }

    fn setViewportImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        c.glViewport(viewport.x, viewport.y, @intCast(viewport.width), @intCast(viewport.height));
    }

    fn setScissorImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        c.glEnable(c.GL_SCISSOR_TEST);
        c.glScissor(rect.x, rect.y, @intCast(rect.width), @intCast(rect.height));
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
        _ = offset;

        c.glBindBuffer(c.GL_ARRAY_BUFFER, buffer.id);
    }

    fn bindIndexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = offset;
        _ = format;

        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, buffer.id);
    }

    fn bindTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        c.glActiveTexture(c.GL_TEXTURE0 + slot);
        c.glBindTexture(c.GL_TEXTURE_2D, texture.id);
    }

    fn bindUniformBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = size;

        c.glBindBufferRange(c.GL_UNIFORM_BUFFER, slot, buffer.id, @intCast(offset), @intCast(buffer.size));
    }

    fn drawImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        if (draw_cmd.instance_count > 1) {
            c.glDrawArraysInstanced(
                c.GL_TRIANGLES,
                @intCast(draw_cmd.first_vertex),
                @intCast(draw_cmd.vertex_count),
                @intCast(draw_cmd.instance_count),
            );
        } else {
            c.glDrawArrays(
                c.GL_TRIANGLES,
                @intCast(draw_cmd.first_vertex),
                @intCast(draw_cmd.vertex_count),
            );
        }
    }

    fn drawIndexedImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        const gl_type = c.GL_UNSIGNED_SHORT; // Assume 16-bit indices for mobile

        if (draw_cmd.instance_count > 1) {
            c.glDrawElementsInstanced(
                c.GL_TRIANGLES,
                @intCast(draw_cmd.index_count),
                gl_type,
                @ptrFromInt(draw_cmd.first_index * 2), // 2 bytes per index
                @intCast(draw_cmd.instance_count),
            );
        } else {
            c.glDrawElements(
                c.GL_TRIANGLES,
                @intCast(draw_cmd.index_count),
                gl_type,
                @ptrFromInt(draw_cmd.first_index * 2),
            );
        }
    }

    fn dispatchImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        c.glDispatchCompute(
            dispatch_cmd.group_count_x,
            dispatch_cmd.group_count_y,
            dispatch_cmd.group_count_z,
        );
        c.glMemoryBarrier(c.GL_ALL_BARRIER_BITS);
    }

    fn copyBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const interface.BufferCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;

        c.glBindBuffer(c.GL_COPY_READ_BUFFER, src.id);
        c.glBindBuffer(c.GL_COPY_WRITE_BUFFER, dst.id);
        c.glCopyBufferSubData(
            c.GL_COPY_READ_BUFFER,
            c.GL_COPY_WRITE_BUFFER,
            @intCast(region.src_offset),
            @intCast(region.dst_offset),
            @intCast(region.size),
        );
    }

    fn copyTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyBufferToTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyTextureToBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn resourceBarrierImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = barriers;
        // OpenGL ES handles synchronization automatically
    }

    fn getBackendInfoImpl(impl: *anyopaque) interface.BackendInfo {
        const self: *Self = @ptrCast(@alignCast(impl));

        return interface.BackendInfo{
            .name = "OpenGL ES",
            .version = "3.2",
            .vendor = "Khronos Group",
            .device_name = "OpenGL ES Device",
            .api_version = 32,
            .driver_version = 0,
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 4096,
            .max_render_targets = 4,
            .max_vertex_attributes = 16,
            .max_uniform_buffer_bindings = 16,
            .max_texture_bindings = 16,
            .supports_compute = self.version_major >= 3 and self.version_minor >= 1,
            .supports_geometry_shaders = false, // Not available in OpenGL ES
            .supports_tessellation = false, // Not available in standard OpenGL ES
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
        // TODO: Implement debug naming using KHR_debug extension
    }

    fn beginDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = name;
        // TODO: Implement debug groups using KHR_debug extension
    }

    fn endDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        // TODO: Implement debug groups using KHR_debug extension
    }
};
