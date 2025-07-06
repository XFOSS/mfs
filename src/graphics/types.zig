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
    rgba8_unorm,
    rgba8_unorm_srgb,
    rgb8,
    rgb8_unorm,
    bgra8,
    bgra8_unorm,
    bgra8_unorm_srgb,
    r8_unorm,
    rg8,
    rg8_unorm,
    depth24_stencil8,
    depth32f,
};

pub const TextureType = enum {
    texture_2d,
    texture_cube,
    texture_3d,
    texture_array,
};

pub const TextureUsage = packed struct {
    shader_resource: bool = false,
    render_target: bool = false,
    depth_stencil: bool = false,
    unordered_access: bool = false,
    copy_src: bool = false,
    copy_dst: bool = false,
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
    id: usize = 0,
    handle: usize = 0,
    width: u32,
    height: u32,
    depth: u32,
    mip_levels: u32,
    array_layers: u32,
    format: TextureFormat,
    texture_type: TextureType = .texture_2d,
    usage: TextureUsage,
    sample_count: u32,

    pub fn init(width: u32, height: u32, format: TextureFormat) Texture {
        return Texture{
            .width = width,
            .height = height,
            .depth = 1,
            .mip_levels = 1,
            .array_layers = 1,
            .format = format,
            .usage = .{ .shader_resource = true },
            .sample_count = 1,
        };
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
    id: usize = 0,
    handle: usize = 0,
    shader_type: ShaderType,
    source: []const u8,
    compiled: bool = false,

    pub fn init(shader_type: ShaderType, source: []const u8) Shader {
        return Shader{
            .shader_type = shader_type,
            .source = source,
        };
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
    id: usize = 0,
    handle: usize = 0,
    size: usize,
    usage: BufferUsage,

    pub fn init(size: usize, usage: BufferUsage) Buffer {
        return Buffer{
            .size = size,
            .usage = usage,
        };
    }

    pub fn upload(self: *Buffer, data: []const u8) !void {
        _ = self;
        _ = data;
        // Implementation will be provided by backend
        return GraphicsError.UnsupportedOperation;
    }

    pub fn bind(self: *const Buffer) void {
        _ = self;
        // Implementation will be provided by backend
    }
};

pub const RenderTarget = struct {
    handle: usize = 0,
    width: u32,
    height: u32,
    color_texture: ?*Texture,
    depth_texture: ?*Texture,

    pub fn init(width: u32, height: u32) RenderTarget {
        return RenderTarget{
            .width = width,
            .height = height,
            .color_texture = null,
            .depth_texture = null,
        };
    }

    pub fn bind(self: *const RenderTarget) void {
        _ = self;
        // Implementation will be provided by backend
    }
};

pub const Viewport = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32,
    height: f32,
    min_depth: f32 = 0.0,
    max_depth: f32 = 1.0,
};

pub const ClearColor = struct {
    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 1.0,
};

pub const Pipeline = struct {
    handle: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Pipeline {
        return Pipeline{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        _ = self;
    }
};

pub const CommandBuffer = struct {
    handle: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator) CommandBuffer {
        return CommandBuffer{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CommandBuffer) void {
        _ = self;
    }
};

pub const ResourceBarrierType = enum {
    vertex_buffer_to_shader_resource,
    shader_resource_to_render_target,
    render_target_to_shader_resource,
    depth_write_to_shader_resource,
    shader_resource_to_depth_write,
    unordered_access_to_shader_resource,
    shader_resource_to_unordered_access,
};

pub const BackendInfo = struct {
    name: []const u8,
    version: []const u8,
    vendor: []const u8,
    memory_budget: u64,
    memory_usage: u64,
};

pub const ResourceStats = struct {
    texture_count: u32,
    buffer_count: u32,
    shader_count: u32,
    pipeline_count: u32,
    memory_allocated: u64,
    memory_used: u64,
};

pub const DebugObjectType = enum {
    texture,
    buffer,
    shader,
    pipeline,
    render_target,
    command_buffer,
};

pub const VertexFormat = enum {
    float1,
    float2,
    float3,
    float4,
    int1,
    int2,
    int3,
    int4,
    uint1,
    uint2,
    uint3,
    uint4,
    byte4_norm,
    ubyte4_norm,
    short2_norm,
    ushort2_norm,
    half2,
    half4,
};

/// Swap chain configuration and management
pub const SwapChain = struct {
    handle: usize = 0,
    width: u32,
    height: u32,
    buffer_count: u32,
    format: TextureFormat,
    vsync: bool,
    window_handle: ?*anyopaque,

    pub fn init(width: u32, height: u32, format: TextureFormat) SwapChain {
        return SwapChain{
            .width = width,
            .height = height,
            .buffer_count = 2,
            .format = format,
            .vsync = true,
            .window_handle = null,
        };
    }

    pub fn present(self: *SwapChain) !void {
        _ = self;
        // Implementation will be provided by backend
        return GraphicsError.UnsupportedOperation;
    }

    pub fn resize(self: *SwapChain, width: u32, height: u32) !void {
        self.width = width;
        self.height = height;
        // Implementation will be provided by backend
        return GraphicsError.UnsupportedOperation;
    }
};

/// Memory types for buffer and texture allocation
pub const MemoryType = enum {
    gpu_only,
    cpu_only,
    cpu_to_gpu,
    gpu_to_cpu,
};

/// Buffer creation descriptor
pub const BufferDesc = struct {
    size: usize,
    usage: BufferUsage,
    memory_type: MemoryType = .gpu_only,
    initial_data: ?[]const u8 = null,

    pub fn init(size: usize, usage: BufferUsage) BufferDesc {
        return BufferDesc{
            .size = size,
            .usage = usage,
        };
    }
};

/// Shader creation descriptor
pub const ShaderDesc = struct {
    stage: ShaderStage,
    source: []const u8,
    entry_point: []const u8 = "main",
    source_type: ShaderSourceType = .hlsl,

    pub fn init(stage: ShaderStage, source: []const u8) ShaderDesc {
        return ShaderDesc{
            .stage = stage,
            .source = source,
        };
    }
};

/// Shader stages
pub const ShaderStage = enum {
    vertex,
    fragment,
    pixel, // Alias for fragment
    compute,
    geometry,
    hull,
    domain,
};

/// Shader source language type
pub const ShaderSourceType = enum {
    hlsl,
    glsl,
    spirv,
    wgsl,
};

/// Texture creation descriptor
pub const TextureDesc = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    format: TextureFormat,
    texture_type: TextureType = .texture_2d,
    usage: TextureUsage,
    sample_count: u32 = 1,
    memory_type: MemoryType = .gpu_only,
    initial_data: ?[]const u8 = null,

    pub fn init(width: u32, height: u32, format: TextureFormat) TextureDesc {
        return TextureDesc{
            .width = width,
            .height = height,
            .format = format,
            .usage = .{ .shader_resource = true },
        };
    }
};

/// Render state configuration
pub const RenderState = struct {
    depth_test: bool = false,
    depth_write: bool = true,
    cull_mode: CullMode = .back,
    fill_mode: FillMode = .solid,
    blend_enabled: bool = false,

    pub const CullMode = enum {
        none,
        front,
        back,
    };

    pub const FillMode = enum {
        solid,
        wireframe,
        point,
    };
};

/// Vertex attribute layout
pub const VertexAttribute = struct {
    location: u32,
    format: VertexFormat,
    offset: u32,
};

/// Vertex layout descriptor
pub const VertexLayout = struct {
    attributes: []const VertexAttribute,
    stride: u32,
};

/// Primitive topology
pub const PrimitiveTopology = enum {
    point_list,
    line_list,
    line_strip,
    triangle_list,
    triangle_strip,
    triangle_fan,
};

/// Color attachment descriptor
pub const ColorAttachment = struct {
    texture: *Texture,
    mip_level: u32 = 0,
    array_slice: u32 = 0,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    load_op: LoadOp = .clear,
    store_op: StoreOp = .store,
};

/// Depth attachment descriptor
pub const DepthAttachment = struct {
    texture: *Texture,
    mip_level: u32 = 0,
    array_slice: u32 = 0,
    clear_depth: f32 = 1.0,
    clear_stencil: u32 = 0,
    depth_load_op: LoadOp = .clear,
    depth_store_op: StoreOp = .store,
    stencil_load_op: LoadOp = .clear,
    stencil_store_op: StoreOp = .store,
};

/// Load operation for render targets
pub const LoadOp = enum {
    load,
    clear,
    dont_care,
};

/// Store operation for render targets
pub const StoreOp = enum {
    store,
    dont_care,
    resolve,
};

/// Render pass descriptor
pub const RenderPassDesc = struct {
    color_attachments: []const ColorAttachment = &.{},
    depth_attachment: ?DepthAttachment = null,
};

/// Index buffer format
pub const IndexFormat = enum {
    uint16,
    uint32,
};

/// Draw command parameters
pub const DrawCommand = struct {
    vertex_count: u32,
    instance_count: u32 = 1,
    first_vertex: u32 = 0,
    first_instance: u32 = 0,
};

/// Indexed draw command parameters
pub const DrawIndexedCommand = struct {
    index_count: u32,
    instance_count: u32 = 1,
    first_index: u32 = 0,
    vertex_offset: i32 = 0,
    first_instance: u32 = 0,
};

/// Graphics Backend Interface - Placeholder for backend abstraction
pub const GraphicsBackend = struct {
    handle: usize = 0,

    pub fn createBuffer(self: *GraphicsBackend, desc: anytype) !*Buffer {
        _ = self;
        _ = desc;
        return GraphicsError.UnsupportedOperation;
    }

    pub fn createTexture(self: *GraphicsBackend, desc: anytype) !*Texture {
        _ = self;
        _ = desc;
        return GraphicsError.UnsupportedOperation;
    }

    pub fn createShader(self: *GraphicsBackend, desc: anytype) !*Shader {
        _ = self;
        _ = desc;
        return GraphicsError.UnsupportedOperation;
    }

    pub fn createPipeline(self: *GraphicsBackend, desc: anytype) !*Pipeline {
        _ = self;
        _ = desc;
        return GraphicsError.UnsupportedOperation;
    }
};

/// Device abstraction
pub const Device = struct {
    handle: usize = 0,
};

/// Command Pool abstraction
pub const CommandPool = struct {
    handle: usize = 0,
};

/// Descriptor Pool abstraction
pub const DescriptorPool = struct {
    handle: usize = 0,
};

/// Queue abstraction
pub const Queue = struct {
    handle: usize = 0,
};

/// Descriptor Set abstraction
pub const DescriptorSet = struct {
    handle: usize = 0,
};

/// Descriptor Set Layout abstraction
pub const DescriptorSetLayout = struct {
    handle: usize = 0,
};

/// Pipeline Layout abstraction
pub const PipelineLayout = struct {
    handle: usize = 0,
};

/// Shader Module abstraction
pub const ShaderModule = struct {
    handle: usize = 0,
};
