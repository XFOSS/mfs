const std = @import("std");
const Allocator = std.mem.Allocator;

pub const GraphicsError = error{
    InitializationFailed,
    TextureCreationFailed,
    ShaderCompilationFailed,
    BufferCreationFailed,
    RenderTargetCreationFailed,
    OutOfMemory,
    InvalidFormat,
    UnsupportedOperation,
};

pub const TextureFormat = enum {
    rgba8,
    rgb8,
    bgra8,
    r8,
    rg8,
    depth24_stencil8,
    depth32f,
};

pub const TextureType = enum {
    texture_2d,
    texture_cube,
    texture_3d,
    texture_array,
};

pub const ShaderType = enum {
    vertex,
    fragment,
    compute,
    geometry,
    tessellation_control,
    tessellation_evaluation,
};

pub const BufferUsage = enum {
    vertex,
    index,
    uniform,
    storage,
    staging,
};

pub const Texture = struct {
    id: u32,
    width: u32,
    height: u32,
    depth: u32,
    format: TextureFormat,
    texture_type: TextureType,
    mip_levels: u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator, width: u32, height: u32, format: TextureFormat) !*Texture {
        const texture = try allocator.create(Texture);
        texture.* = Texture{
            .id = 0, // Will be set by backend
            .width = width,
            .height = height,
            .depth = 1,
            .format = format,
            .texture_type = .texture_2d,
            .mip_levels = 1,
            .allocator = allocator,
        };
        return texture;
    }

    pub fn deinit(self: *Texture) void {
        self.allocator.destroy(self);
    }

    pub fn bind(self: *const Texture, slot: u32) void {
        _ = self;
        _ = slot;
        // Implementation will be provided by backend
    }

    pub fn upload(self: *Texture, data: []const u8) !void {
        _ = self;
        _ = data;
        // Implementation will be provided by backend
        return GraphicsError.UnsupportedOperation;
    }
};

pub const Shader = struct {
    id: u32,
    shader_type: ShaderType,
    source: []const u8,
    compiled: bool,
    allocator: Allocator,

    pub fn init(allocator: Allocator, shader_type: ShaderType, source: []const u8) !*Shader {
        const shader = try allocator.create(Shader);
        const owned_source = try allocator.dupe(u8, source);
        shader.* = Shader{
            .id = 0,
            .shader_type = shader_type,
            .source = owned_source,
            .compiled = false,
            .allocator = allocator,
        };
        return shader;
    }

    pub fn deinit(self: *Shader) void {
        self.allocator.free(self.source);
        self.allocator.destroy(self);
    }

    pub fn compile(self: *Shader) !void {
        _ = self;
        // Implementation will be provided by backend
        return GraphicsError.UnsupportedOperation;
    }

    pub fn bind(self: *const Shader) void {
        _ = self;
        // Implementation will be provided by backend
    }
};

pub const Buffer = struct {
    id: u32,
    size: usize,
    usage: BufferUsage,
    data: ?[]u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, size: usize, usage: BufferUsage) !*Buffer {
        const buffer = try allocator.create(Buffer);
        buffer.* = Buffer{
            .id = 0,
            .size = size,
            .usage = usage,
            .data = null,
            .allocator = allocator,
        };
        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        if (self.data) |data| {
            self.allocator.free(data);
        }
        self.allocator.destroy(self);
    }

    pub fn upload(self: *Buffer, data: []const u8) !void {
        if (data.len > self.size) return GraphicsError.BufferCreationFailed;

        if (self.data) |old_data| {
            self.allocator.free(old_data);
        }

        self.data = try self.allocator.dupe(u8, data);
    }

    pub fn bind(self: *const Buffer) void {
        _ = self;
        // Implementation will be provided by backend
    }
};

pub const RenderTarget = struct {
    id: u32,
    width: u32,
    height: u32,
    color_texture: ?*Texture,
    depth_texture: ?*Texture,
    allocator: Allocator,

    pub fn init(allocator: Allocator, width: u32, height: u32) !*RenderTarget {
        const render_target = try allocator.create(RenderTarget);
        render_target.* = RenderTarget{
            .id = 0,
            .width = width,
            .height = height,
            .color_texture = null,
            .depth_texture = null,
            .allocator = allocator,
        };
        return render_target;
    }

    pub fn deinit(self: *RenderTarget) void {
        if (self.color_texture) |texture| {
            texture.deinit();
        }
        if (self.depth_texture) |texture| {
            texture.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn bind(self: *const RenderTarget) void {
        _ = self;
        // Implementation will be provided by backend
    }
};

pub const Viewport = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32,
    height: u32,
};

pub const ClearColor = struct {
    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 1.0,
};
