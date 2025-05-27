const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const c = @cImport({
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
    @cDefine("GLAD_GL_IMPLEMENTATION", "");
});

pub const OpenGLError = error{
    InitializationFailed,
    ShaderCompilationFailed,
    ProgramLinkingFailed,
    TextureCreationFailed,
    BufferCreationFailed,
    FramebufferCreationFailed,
    ExtensionNotSupported,
    ContextCreationFailed,
    InvalidOperation,
};

pub const OpenGLBackend = struct {
    allocator: Allocator,
    initialized: bool = false,
    version_major: u32 = 0,
    version_minor: u32 = 0,
    extensions: std.StringHashMap(bool),
    current_program: u32 = 0,
    current_texture_slots: [16]u32 = [_]u32{0} ** 16,
    current_vao: u32 = 0,
    viewport: types.Viewport,
    clear_color: types.ClearColor = types.ClearColor{},

    const Self = @This();

    pub fn init(allocator: Allocator, width: u32, height: u32) !*Self {
        var backend = try allocator.create(Self);
        backend.* = Self{
            .allocator = allocator,
            .extensions = std.StringHashMap(bool).init(allocator),
            .viewport = types.Viewport{ .width = width, .height = height },
        };

        // Initialize OpenGL context (simplified - in real implementation would need platform-specific code)
        if (!backend.initializeContext()) {
            allocator.destroy(backend);
            return OpenGLError.ContextCreationFailed;
        }

        backend.initialized = true;
        std.log.info("OpenGL backend initialized successfully", .{});
        return backend;
    }

    pub fn deinit(self: *Self) void {
        if (!self.initialized) return;

        self.extensions.deinit();
        self.initialized = false;
        self.allocator.destroy(self);
    }

    fn initializeContext(self: *Self) bool {
        // In a real implementation, this would:
        // 1. Create OpenGL context using platform-specific APIs (WGL on Windows, GLX on Linux, etc.)
        // 2. Load OpenGL function pointers
        // 3. Query OpenGL version and extensions

        // For now, we'll simulate successful initialization
        self.version_major = 3;
        self.version_minor = 3;

        // Simulate loading some common extensions
        self.extensions.put("GL_ARB_vertex_array_object", true) catch {};
        self.extensions.put("GL_ARB_framebuffer_object", true) catch {};
        self.extensions.put("GL_ARB_texture_storage", true) catch {};

        return true;
    }

    pub fn createTexture(self: *Self, texture: *types.Texture, data: ?[]const u8) !void {
        if (!self.initialized) return OpenGLError.InitializationFailed;

        var texture_id: u32 = 0;
        c.glGenTextures(1, &texture_id);
        if (texture_id == 0) return OpenGLError.TextureCreationFailed;

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
            .bgra8 => c.GL_BGRA,
            .r8 => c.GL_RED,
            .rg8 => c.GL_RG,
            .depth24_stencil8 => c.GL_DEPTH_STENCIL,
            .depth32f => c.GL_DEPTH_COMPONENT,
        };

        const gl_internal_format = switch (texture.format) {
            .rgba8 => c.GL_RGBA8,
            .rgb8 => c.GL_RGB8,
            .bgra8 => c.GL_RGBA8,
            .r8 => c.GL_R8,
            .rg8 => c.GL_RG8,
            .depth24_stencil8 => c.GL_DEPTH24_STENCIL8,
            .depth32f => c.GL_DEPTH_COMPONENT32F,
        };

        const gl_type = switch (texture.format) {
            .rgba8, .rgb8, .bgra8, .r8, .rg8 => c.GL_UNSIGNED_BYTE,
            .depth24_stencil8 => c.GL_UNSIGNED_INT_24_8,
            .depth32f => c.GL_FLOAT,
        };

        if (texture.texture_type == .texture_2d) {
            c.glTexImage2D(
                c.GL_TEXTURE_2D,
                0,
                gl_internal_format,
                @intCast(texture.width),
                @intCast(texture.height),
                0,
                gl_format,
                gl_type,
                if (data) |d| d.ptr else null,
            );
        }

        // Set default texture parameters
        c.glTexParameteri(gl_target, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(gl_target, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(gl_target, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(gl_target, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);

        c.glBindTexture(gl_target, 0);
    }

    pub fn createShader(self: *Self, shader: *types.Shader) !void {
        if (!self.initialized) return OpenGLError.InitializationFailed;

        const gl_shader_type = switch (shader.shader_type) {
            .vertex => c.GL_VERTEX_SHADER,
            .fragment => c.GL_FRAGMENT_SHADER,
            .compute => c.GL_COMPUTE_SHADER,
            .geometry => c.GL_GEOMETRY_SHADER,
            .tessellation_control => c.GL_TESS_CONTROL_SHADER,
            .tessellation_evaluation => c.GL_TESS_EVALUATION_SHADER,
        };

        const shader_id = c.glCreateShader(gl_shader_type);
        if (shader_id == 0) return OpenGLError.ShaderCompilationFailed;

        shader.id = shader_id;

        const source_ptr: [*c]const u8 = shader.source.ptr;
        const source_len: c.GLint = @intCast(shader.source.len);
        c.glShaderSource(shader_id, 1, &source_ptr, &source_len);
        c.glCompileShader(shader_id);

        var compile_status: c.GLint = 0;
        c.glGetShaderiv(shader_id, c.GL_COMPILE_STATUS, &compile_status);

        if (compile_status == c.GL_FALSE) {
            var log_length: c.GLint = 0;
            c.glGetShaderiv(shader_id, c.GL_INFO_LOG_LENGTH, &log_length);

            if (log_length > 0) {
                const log_buffer = self.allocator.alloc(u8, @intCast(log_length)) catch {
                    c.glDeleteShader(shader_id);
                    return OpenGLError.ShaderCompilationFailed;
                };
                defer self.allocator.free(log_buffer);

                c.glGetShaderInfoLog(shader_id, log_length, null, log_buffer.ptr);
                std.log.err("Shader compilation failed: {s}", .{log_buffer});
            }

            c.glDeleteShader(shader_id);
            return OpenGLError.ShaderCompilationFailed;
        }

        shader.compiled = true;
    }

    pub fn createBuffer(self: *Self, buffer: *types.Buffer, data: ?[]const u8) !void {
        if (!self.initialized) return OpenGLError.InitializationFailed;

        var buffer_id: u32 = 0;
        c.glGenBuffers(1, &buffer_id);
        if (buffer_id == 0) return OpenGLError.BufferCreationFailed;

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
        c.glBindBuffer(gl_target, 0);
    }

    pub fn createRenderTarget(self: *Self, render_target: *types.RenderTarget) !void {
        if (!self.initialized) return OpenGLError.InitializationFailed;

        var framebuffer_id: u32 = 0;
        c.glGenFramebuffers(1, &framebuffer_id);
        if (framebuffer_id == 0) return OpenGLError.FramebufferCreationFailed;

        render_target.id = framebuffer_id;

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, framebuffer_id);

        // Create color texture
        render_target.color_texture = try types.Texture.init(
            self.allocator,
            render_target.width,
            render_target.height,
            .rgba8,
        );
        try self.createTexture(render_target.color_texture.?, null);

        c.glFramebufferTexture2D(
            c.GL_FRAMEBUFFER,
            c.GL_COLOR_ATTACHMENT0,
            c.GL_TEXTURE_2D,
            render_target.color_texture.?.id,
            0,
        );

        // Create depth texture
        render_target.depth_texture = try types.Texture.init(
            self.allocator,
            render_target.width,
            render_target.height,
            .depth24_stencil8,
        );
        try self.createTexture(render_target.depth_texture.?, null);

        c.glFramebufferTexture2D(
            c.GL_FRAMEBUFFER,
            c.GL_DEPTH_STENCIL_ATTACHMENT,
            c.GL_TEXTURE_2D,
            render_target.depth_texture.?.id,
            0,
        );

        const framebuffer_status = c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER);
        if (framebuffer_status != c.GL_FRAMEBUFFER_COMPLETE) {
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
            return OpenGLError.FramebufferCreationFailed;
        }

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
    }

    pub fn bindTexture(self: *Self, texture: *const types.Texture, slot: u32) void {
        if (!self.initialized) return;
        if (slot >= self.current_texture_slots.len) return;

        c.glActiveTexture(c.GL_TEXTURE0 + slot);

        const gl_target = switch (texture.texture_type) {
            .texture_2d => c.GL_TEXTURE_2D,
            .texture_cube => c.GL_TEXTURE_CUBE_MAP,
            .texture_3d => c.GL_TEXTURE_3D,
            .texture_array => c.GL_TEXTURE_2D_ARRAY,
        };

        c.glBindTexture(gl_target, texture.id);
        self.current_texture_slots[slot] = texture.id;
    }

    pub fn bindShader(self: *Self, shader: *const types.Shader) void {
        if (!self.initialized or !shader.compiled) return;

        c.glUseProgram(shader.id);
        self.current_program = shader.id;
    }

    pub fn bindRenderTarget(self: *Self, render_target: ?*const types.RenderTarget) void {
        if (!self.initialized) return;

        if (render_target) |rt| {
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, rt.id);
            self.setViewport(0, 0, rt.width, rt.height);
        } else {
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
            self.setViewport(0, 0, self.viewport.width, self.viewport.height);
        }
    }

    pub fn setViewport(self: *Self, x: i32, y: i32, width: u32, height: u32) void {
        if (!self.initialized) return;

        c.glViewport(x, y, @intCast(width), @intCast(height));
        self.viewport = types.Viewport{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn setClearColor(self: *Self, color: types.ClearColor) void {
        if (!self.initialized) return;

        c.glClearColor(color.r, color.g, color.b, color.a);
        self.clear_color = color;
    }

    pub fn clear(self: *Self, color: bool, depth: bool, stencil: bool) void {
        if (!self.initialized) return;

        var clear_mask: c.GLbitfield = 0;
        if (color) clear_mask |= c.GL_COLOR_BUFFER_BIT;
        if (depth) clear_mask |= c.GL_DEPTH_BUFFER_BIT;
        if (stencil) clear_mask |= c.GL_STENCIL_BUFFER_BIT;

        c.glClear(clear_mask);
    }

    pub fn drawTriangles(self: *Self, vertex_count: u32, first_vertex: u32) void {
        if (!self.initialized) return;

        c.glDrawArrays(c.GL_TRIANGLES, @intCast(first_vertex), @intCast(vertex_count));
    }

    pub fn drawIndexed(self: *Self, index_count: u32, first_index: u32) void {
        if (!self.initialized) return;

        c.glDrawElements(
            c.GL_TRIANGLES,
            @intCast(index_count),
            c.GL_UNSIGNED_INT,
            @ptrFromInt(first_index * @sizeOf(u32)),
        );
    }

    pub fn present(self: *Self) void {
        if (!self.initialized) return;

        // In a real implementation, this would swap buffers
        // For now, we'll just flush the OpenGL commands
        c.glFlush();
        c.glFinish();
    }

    pub fn getError(self: *Self) ?OpenGLError {
        if (!self.initialized) return OpenGLError.InitializationFailed;

        const gl_error = c.glGetError();
        return switch (gl_error) {
            c.GL_NO_ERROR => null,
            c.GL_INVALID_ENUM => OpenGLError.InvalidOperation,
            c.GL_INVALID_VALUE => OpenGLError.InvalidOperation,
            c.GL_INVALID_OPERATION => OpenGLError.InvalidOperation,
            c.GL_OUT_OF_MEMORY => types.GraphicsError.OutOfMemory,
            else => OpenGLError.InvalidOperation,
        };
    }

    pub fn isExtensionSupported(self: *const Self, extension: []const u8) bool {
        return self.extensions.get(extension) orelse false;
    }

    pub fn getVersionString(self: *const Self) []const u8 {
        _ = self;
        // In a real implementation, this would query GL_VERSION
        return "OpenGL 3.3 (Fallback Implementation)";
    }

    // Utility functions for common operations
    pub fn createSimpleProgram(self: *Self, vertex_source: []const u8, fragment_source: []const u8) !u32 {
        var vertex_shader = try types.Shader.init(self.allocator, .vertex, vertex_source);
        defer vertex_shader.deinit();

        var fragment_shader = try types.Shader.init(self.allocator, .fragment, fragment_source);
        defer fragment_shader.deinit();

        try self.createShader(vertex_shader);
        try self.createShader(fragment_shader);

        const program_id = c.glCreateProgram();
        if (program_id == 0) return OpenGLError.ProgramLinkingFailed;

        c.glAttachShader(program_id, vertex_shader.id);
        c.glAttachShader(program_id, fragment_shader.id);
        c.glLinkProgram(program_id);

        var link_status: c.GLint = 0;
        c.glGetProgramiv(program_id, c.GL_LINK_STATUS, &link_status);

        if (link_status == c.GL_FALSE) {
            var log_length: c.GLint = 0;
            c.glGetProgramiv(program_id, c.GL_INFO_LOG_LENGTH, &log_length);

            if (log_length > 0) {
                const log_buffer = self.allocator.alloc(u8, @intCast(log_length)) catch {
                    c.glDeleteProgram(program_id);
                    return OpenGLError.ProgramLinkingFailed;
                };
                defer self.allocator.free(log_buffer);

                c.glGetProgramInfoLog(program_id, log_length, null, log_buffer.ptr);
                std.log.err("Program linking failed: {s}", .{log_buffer});
            }

            c.glDeleteProgram(program_id);
            return OpenGLError.ProgramLinkingFailed;
        }

        c.glDetachShader(program_id, vertex_shader.id);
        c.glDetachShader(program_id, fragment_shader.id);

        return program_id;
    }
};
