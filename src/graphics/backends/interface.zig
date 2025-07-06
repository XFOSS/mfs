const std = @import("std");
const gpu = @import("gpu");
const types = @import("../types.zig");
const build_options = @import("../../build_options.zig");

/// Error types for graphics backend operations
/// @symbol Error types for backend implementations
pub const GraphicsBackendError = error{
    InitializationFailed,
    DeviceCreationFailed,
    SwapChainCreationFailed,
    ResourceCreationFailed,
    CommandSubmissionFailed,
    OutOfMemory,
    InvalidOperation,
    UnsupportedFormat,
    UnsupportedOperation,
    BackendNotAvailable,
    NotInitialized,
    ResizeFailed,
    PresentFailed,
};

/// Graphics backend type mapping to build options
/// @symbol Backend type identification
pub const BackendType = build_options.Backend;

/// Backend configuration for initialization
/// @thread-safe Thread-compatible data structure
/// @symbol Backend configuration
pub const BackendConfig = struct {
    backend_type: BackendType = .auto,
    enable_validation: bool = false,
    enable_ray_tracing: bool = false,
    enable_compute_shaders: bool = false,
    max_frames_in_flight: u32 = 2,
    enable_debug: bool = false,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    enable_vsync: bool = true,
    sample_count: u32 = 1,
    window_handle: ?*anyopaque = null,

    pub fn validate(self: *const BackendConfig) !void {
        if (self.window_width == 0 or self.window_height == 0) {
            return error.InvalidWindowSize;
        }
        if (self.sample_count == 0 or (self.sample_count & (self.sample_count - 1)) != 0) {
            return error.InvalidSampleCount;
        }
    }
};

/// Swap chain configuration descriptor
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Swap chain configuration
pub const SwapChainDesc = struct {
    width: u32,
    height: u32,
    format: types.TextureFormat = .rgba8_unorm,
    buffer_count: u32 = 2,
    vsync: bool = true,
    window_handle: ?*anyopaque = null,
};

/// Render pass configuration descriptor
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Render pass configuration
pub const RenderPassDesc = struct {
    color_targets: []const ColorTargetDesc = &.{},
    depth_target: ?DepthTargetDesc = null,
    clear_color: types.ClearColor = .{},
    clear_depth: f32 = 1.0,
    clear_stencil: u32 = 0,
};

/// Color render target configuration descriptor
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Color target configuration
pub const ColorTargetDesc = struct {
    texture: *types.Texture,
    mip_level: u32 = 0,
    array_slice: u32 = 0,
    load_action: LoadAction = .clear,
    store_action: StoreAction = .store,
};

/// Depth stencil render target configuration descriptor
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Depth target configuration
pub const DepthTargetDesc = struct {
    texture: *types.Texture,
    mip_level: u32 = 0,
    array_slice: u32 = 0,
    depth_load_action: LoadAction = .clear,
    depth_store_action: StoreAction = .store,
    stencil_load_action: LoadAction = .clear,
    stencil_store_action: StoreAction = .store,
};

/// Render target load action
/// @symbol Render target load operations
pub const LoadAction = enum {
    load,
    clear,
    dont_care,
};

/// Render target store action
/// @symbol Render target store operations
pub const StoreAction = enum {
    store,
    dont_care,
    resolve,
};

/// Graphics pipeline configuration descriptor
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Pipeline configuration
pub const PipelineDesc = struct {
    vertex_shader: ?*types.Shader = null,
    fragment_shader: ?*types.Shader = null,
    geometry_shader: ?*types.Shader = null,
    compute_shader: ?*types.Shader = null,
    vertex_layout: VertexLayout = .{},
    blend_state: BlendState = .{},
    depth_stencil_state: DepthStencilState = .{},
    rasterizer_state: RasterizerState = .{},
    primitive_topology: PrimitiveTopology = .triangles,
    render_target_formats: []const types.TextureFormat = &.{},
    depth_format: ?types.TextureFormat = null,
    sample_count: u32 = 1,
};

pub const VertexLayout = struct {
    attributes: []const VertexAttribute = &.{},
    stride: u32 = 0,
};

/// Vertex attribute descriptor for shader inputs
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Vertex attribute configuration
pub const VertexAttribute = struct {
    location: u32,
    format: VertexFormat,
    offset: u32,
};

/// Supported vertex attribute data formats
/// @symbol Vertex data format types
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

/// Pipeline blend state configuration
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Blend state configuration
pub const BlendState = struct {
    enabled: bool = false,
    src_color: BlendFactor = .one,
    dst_color: BlendFactor = .zero,
    color_op: BlendOp = .add,
    src_alpha: BlendFactor = .one,
    dst_alpha: BlendFactor = .zero,
    alpha_op: BlendOp = .add,
    color_mask: ColorMask = .all,
};

/// Blend factors for color/alpha blending
/// @symbol Blend factor enumeration
pub const BlendFactor = enum {
    zero,
    one,
    src_color,
    inv_src_color,
    src_alpha,
    inv_src_alpha,
    dst_color,
    inv_dst_color,
    dst_alpha,
    inv_dst_alpha,
    blend_color,
    inv_blend_color,
};

/// Viewport structure for rendering
/// @symbol Viewport configuration
pub const Viewport = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32,
    height: f32,
    min_depth: f32 = 0.0,
    max_depth: f32 = 1.0,
};

/// 2D Rectangle for scissor testing
/// @symbol Rectangle structure
pub const Rect2D = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32,
    height: u32,
};

/// Index type for Vulkan compatibility
/// @symbol Index type enumeration
pub const IndexType = enum {
    uint16,
    uint32,
};

/// Render pass opaque handle
/// @symbol Render pass structure
pub const RenderPass = struct {
    handle: usize = 0,
};

/// Blend operations for color/alpha blending
/// @symbol Blend operation enumeration
pub const BlendOp = enum {
    add,
    subtract,
    reverse_subtract,
    min,
    max,
};

/// Color write mask for render targets
/// @symbol Color component write control
pub const ColorMask = packed struct {
    r: bool = true,
    g: bool = true,
    b: bool = true,
    a: bool = true,

    pub const all = ColorMask{};
    pub const none = ColorMask{ .r = false, .g = false, .b = false, .a = false };
};

/// Depth and stencil test configuration
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Depth stencil state configuration
pub const DepthStencilState = struct {
    depth_test_enabled: bool = false,
    depth_write_enabled: bool = true,
    depth_compare: CompareFunc = .less,
    stencil_enabled: bool = false,
    stencil_read_mask: u8 = 0xFF,
    stencil_write_mask: u8 = 0xFF,
    front_face: StencilOp = .{},
    back_face: StencilOp = .{},
};

/// Stencil operation configuration
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Stencil operation configuration
pub const StencilOp = struct {
    fail: StencilAction = .keep,
    depth_fail: StencilAction = .keep,
    pass: StencilAction = .keep,
    compare: CompareFunc = .always,
};

/// Stencil operations for different test outcomes
/// @symbol Stencil action enumeration
pub const StencilAction = enum {
    keep,
    zero,
    replace,
    incr_clamp,
    decr_clamp,
    invert,
    incr_wrap,
    decr_wrap,
};

/// Comparison functions for depth/stencil tests
/// @symbol Comparison function enumeration
pub const CompareFunc = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

/// Rasterizer configuration for primitive assembly and processing
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Rasterizer state configuration
pub const RasterizerState = struct {
    fill_mode: FillMode = .solid,
    cull_mode: CullMode = .back,
    front_face: FrontFace = .counter_clockwise,
    depth_bias: f32 = 0.0,
    depth_bias_clamp: f32 = 0.0,
    slope_scaled_depth_bias: f32 = 0.0,
    depth_clip_enabled: bool = true,
    scissor_enabled: bool = false,
    multisample_enabled: bool = false,
    antialiased_line_enabled: bool = false,
};

/// Polygon fill modes
/// @symbol Fill mode enumeration
pub const FillMode = enum {
    solid,
    wireframe,
    point,
};

/// Face culling modes
/// @symbol Cull mode enumeration
pub const CullMode = enum {
    none,
    front,
    back,
};

/// Front face vertex winding order
/// @symbol Front face enumeration
pub const FrontFace = enum {
    clockwise,
    counter_clockwise,
};

/// Primitive topology types for vertex assembly
/// @symbol Primitive topology enumeration
pub const PrimitiveTopology = enum {
    points,
    lines,
    line_strip,
    triangles,
    triangle_strip,
    triangle_fan,
    lines_adjacency,
    line_strip_adjacency,
    triangles_adjacency,
    triangle_strip_adjacency,
    patches,
};

/// Non-indexed draw command parameters
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Draw command parameters
pub const DrawCommand = struct {
    vertex_count: u32,
    instance_count: u32 = 1,
    first_vertex: u32 = 0,
    first_instance: u32 = 0,
};

/// Indexed draw command parameters
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Indexed draw command parameters
pub const DrawIndexedCommand = struct {
    index_count: u32,
    instance_count: u32 = 1,
    first_index: u32 = 0,
    vertex_offset: i32 = 0,
    first_instance: u32 = 0,
};

/// Index buffer format specification
/// @symbol Index format enumeration
pub const IndexFormat = enum {
    uint16,
    uint32,
};

/// Compute dispatch command parameters
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Compute dispatch parameters
pub const DispatchCommand = struct {
    group_count_x: u32,
    group_count_y: u32 = 1,
    group_count_z: u32 = 1,
};

/// Buffer copy operation parameters
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Buffer copy region parameters
pub const BufferCopyRegion = struct {
    src_offset: u64 = 0,
    dst_offset: u64 = 0,
    size: u64,
};

/// Texture copy operation parameters
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Texture copy region parameters
pub const TextureCopyRegion = struct {
    src_offset: [3]u32 = .{ 0, 0, 0 },
    dst_offset: [3]u32 = .{ 0, 0, 0 },
    extent: [3]u32,
    src_mip_level: u32 = 0,
    dst_mip_level: u32 = 0,
    src_array_slice: u32 = 0,
    dst_array_slice: u32 = 0,
    array_layer_count: u32 = 1,
};

/// Resource state transition barrier
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Resource barrier parameters
pub const ResourceBarrier = struct {
    resource: ResourceHandle,
    old_state: ResourceState,
    new_state: ResourceState,
    subresource: SubresourceRange = .{},
};

/// Unified resource handle for debug operations
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Resource handle wrapper
pub const ResourceHandle = union(enum) {
    buffer: *types.Buffer,
    texture: *types.Texture,
};

/// Resource usage states for synchronization
/// @symbol Resource state enumeration
pub const ResourceState = enum {
    undefined,
    common,
    vertex_buffer,
    index_buffer,
    constant_buffer,
    shader_resource,
    unordered_access,
    render_target,
    depth_write,
    depth_read,
    copy_dest,
    copy_source,
    present,
};

/// Texture subresource range specification
/// @thread-safe Thread-compatible data structure passed to thread-safe functions
/// @symbol Subresource range parameters
pub const SubresourceRange = struct {
    first_mip_level: u32 = 0,
    mip_level_count: u32 = std.math.maxInt(u32),
    first_array_slice: u32 = 0,
    array_slice_count: u32 = std.math.maxInt(u32),
};

/// Pipeline state object
/// @thread-safe Not thread-safe, external synchronization required
/// @symbol Graphics pipeline object
pub const Pipeline = struct {
    id: usize,
    backend_handle: *anyopaque,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Pipeline) void {
        self.allocator.destroy(self);
    }
};

/// Command buffer object
/// @thread-safe Not thread-safe, external synchronization required
/// @symbol Graphics command buffer
pub const CommandBuffer = struct {
    id: usize,
    backend_handle: *anyopaque,
    allocator: std.mem.Allocator,
    recording: bool = false,

    pub fn deinit(self: *CommandBuffer) void {
        self.allocator.destroy(self);
    }
};

/// Abstract graphics backend interface
/// @thread-safe Depends on implementation, generally not thread-safe
/// @symbol Graphics backend wrapper
pub const GraphicsBackend = struct {
    allocator: std.mem.Allocator,
    backend_type: BackendType,
    initialized: bool = false,

    // Function pointers for backend implementation
    vtable: *const VTable,
    impl_data: *anyopaque,

    const Self = @This();

    pub const VTable = struct {
        // Lifecycle
        deinit: *const fn (impl: *anyopaque) void,

        // SwapChain management
        create_swap_chain: *const fn (impl: *anyopaque, desc: *const SwapChainDesc) GraphicsBackendError!void,
        resize_swap_chain: *const fn (impl: *anyopaque, width: u32, height: u32) GraphicsBackendError!void,
        present: *const fn (impl: *anyopaque) GraphicsBackendError!void,
        get_current_back_buffer: *const fn (impl: *anyopaque) GraphicsBackendError!*types.Texture,

        // Resource creation
        create_texture: *const fn (impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) GraphicsBackendError!void,
        create_buffer: *const fn (impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) GraphicsBackendError!void,
        create_shader: *const fn (impl: *anyopaque, shader: *types.Shader) GraphicsBackendError!void,
        create_pipeline: *const fn (impl: *anyopaque, desc: *const PipelineDesc) GraphicsBackendError!*Pipeline,
        create_render_target: *const fn (impl: *anyopaque, render_target: *types.RenderTarget) GraphicsBackendError!void,

        // Resource management
        update_buffer: *const fn (impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) GraphicsBackendError!void,
        update_texture: *const fn (impl: *anyopaque, texture: *types.Texture, region: *const TextureCopyRegion, data: []const u8) GraphicsBackendError!void,
        destroy_texture: *const fn (impl: *anyopaque, texture: *types.Texture) void,
        destroy_buffer: *const fn (impl: *anyopaque, buffer: *types.Buffer) void,
        destroy_shader: *const fn (impl: *anyopaque, shader: *types.Shader) void,
        destroy_render_target: *const fn (impl: *anyopaque, render_target: *types.RenderTarget) void,

        // Command recording
        create_command_buffer: *const fn (impl: *anyopaque) GraphicsBackendError!*CommandBuffer,
        begin_command_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer) GraphicsBackendError!void,
        end_command_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer) GraphicsBackendError!void,
        submit_command_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer) GraphicsBackendError!void,

        // Render commands
        begin_render_pass: *const fn (impl: *anyopaque, cmd: *CommandBuffer, desc: *const RenderPassDesc) GraphicsBackendError!void,
        end_render_pass: *const fn (impl: *anyopaque, cmd: *CommandBuffer) GraphicsBackendError!void,
        set_viewport: *const fn (impl: *anyopaque, cmd: *CommandBuffer, viewport: *const types.Viewport) GraphicsBackendError!void,
        set_scissor: *const fn (impl: *anyopaque, cmd: *CommandBuffer, rect: *const types.Viewport) GraphicsBackendError!void,
        bind_pipeline: *const fn (impl: *anyopaque, cmd: *CommandBuffer, pipeline: *Pipeline) GraphicsBackendError!void,
        bind_vertex_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) GraphicsBackendError!void,
        bind_index_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer, buffer: *types.Buffer, offset: u64, format: IndexFormat) GraphicsBackendError!void,
        bind_texture: *const fn (impl: *anyopaque, cmd: *CommandBuffer, slot: u32, texture: *types.Texture) GraphicsBackendError!void,
        bind_uniform_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) GraphicsBackendError!void,

        // Draw commands
        draw: *const fn (impl: *anyopaque, cmd: *CommandBuffer, draw_cmd: *const DrawCommand) GraphicsBackendError!void,
        draw_indexed: *const fn (impl: *anyopaque, cmd: *CommandBuffer, draw_cmd: *const DrawIndexedCommand) GraphicsBackendError!void,
        dispatch: *const fn (impl: *anyopaque, cmd: *CommandBuffer, dispatch_cmd: *const DispatchCommand) GraphicsBackendError!void,

        // Resource copying
        copy_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const BufferCopyRegion) GraphicsBackendError!void,
        copy_texture: *const fn (impl: *anyopaque, cmd: *CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const TextureCopyRegion) GraphicsBackendError!void,
        copy_buffer_to_texture: *const fn (impl: *anyopaque, cmd: *CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const TextureCopyRegion) GraphicsBackendError!void,
        copy_texture_to_buffer: *const fn (impl: *anyopaque, cmd: *CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const TextureCopyRegion) GraphicsBackendError!void,

        // Synchronization
        resource_barrier: *const fn (impl: *anyopaque, cmd: *CommandBuffer, barriers: []const ResourceBarrier) GraphicsBackendError!void,

        // Query and debug
        get_backend_info: *const fn (impl: *anyopaque) BackendInfo,
        set_debug_name: *const fn (impl: *anyopaque, resource: ResourceHandle, name: []const u8) GraphicsBackendError!void,
        begin_debug_group: *const fn (impl: *anyopaque, cmd: *CommandBuffer, name: []const u8) GraphicsBackendError!void,
        end_debug_group: *const fn (impl: *anyopaque, cmd: *CommandBuffer) GraphicsBackendError!void,
    };

    /// Clean up the graphics backend
    /// @thread-safe Not thread-safe, external synchronization required
    /// @symbol Public backend cleanup API
    pub fn deinit(self: *Self) void {
        if (!self.initialized) return;
        self.vtable.deinit(self.impl_data);
        self.initialized = false;
    }

    // SwapChain management
    /// Create a swap chain for presenting to a window
    /// @thread-safe Not thread-safe, external synchronization required
    /// @symbol Public swap chain creation API
    pub fn createSwapChain(self: *Self, desc: *const SwapChainDesc) GraphicsBackendError!void {
        return self.vtable.create_swap_chain(self.impl_data, desc);
    }

    pub fn resizeSwapChain(self: *Self, width: u32, height: u32) GraphicsBackendError!void {
        return self.vtable.resize_swap_chain(self.impl_data, width, height);
    }

    pub fn present(self: *Self) GraphicsBackendError!void {
        return self.vtable.present(self.impl_data);
    }

    pub fn getCurrentBackBuffer(self: *Self) GraphicsBackendError!*types.Texture {
        return self.vtable.get_current_back_buffer(self.impl_data);
    }

    // Resource creation
    pub fn createTexture(self: *Self, texture: *types.Texture, data: ?[]const u8) GraphicsBackendError!void {
        return self.vtable.create_texture(self.impl_data, texture, data);
    }

    pub fn createBuffer(self: *Self, buffer: *types.Buffer, data: ?[]const u8) GraphicsBackendError!void {
        return self.vtable.create_buffer(self.impl_data, buffer, data);
    }

    pub fn createShader(self: *Self, shader: *types.Shader) GraphicsBackendError!void {
        return self.vtable.create_shader(self.impl_data, shader);
    }

    pub fn createPipeline(self: *Self, desc: *const PipelineDesc) GraphicsBackendError!*Pipeline {
        return self.vtable.create_pipeline(self.impl_data, desc);
    }

    pub fn createRenderTarget(self: *Self, render_target: *types.RenderTarget) GraphicsBackendError!void {
        return self.vtable.create_render_target(self.impl_data, render_target);
    }

    // Resource management
    pub fn updateBuffer(self: *Self, buffer: *types.Buffer, offset: u64, data: []const u8) GraphicsBackendError!void {
        return self.vtable.update_buffer(self.impl_data, buffer, offset, data);
    }

    pub fn updateTexture(self: *Self, texture: *types.Texture, region: *const TextureCopyRegion, data: []const u8) GraphicsBackendError!void {
        return self.vtable.update_texture(self.impl_data, texture, region, data);
    }

    pub fn destroyTexture(self: *Self, texture: *types.Texture) void {
        self.vtable.destroy_texture(self.impl_data, texture);
    }

    pub fn destroyBuffer(self: *Self, buffer: *types.Buffer) void {
        self.vtable.destroy_buffer(self.impl_data, buffer);
    }

    pub fn destroyShader(self: *Self, shader: *types.Shader) void {
        self.vtable.destroy_shader(self.impl_data, shader);
    }

    pub fn destroyRenderTarget(self: *Self, render_target: *types.RenderTarget) void {
        self.vtable.destroy_render_target(self.impl_data, render_target);
    }

    // Command recording
    pub fn createCommandBuffer(self: *Self) GraphicsBackendError!*CommandBuffer {
        return self.vtable.create_command_buffer(self.impl_data);
    }

    pub fn beginCommandBuffer(self: *Self, cmd: *CommandBuffer) GraphicsBackendError!void {
        return self.vtable.begin_command_buffer(self.impl_data, cmd);
    }

    pub fn endCommandBuffer(self: *Self, cmd: *CommandBuffer) GraphicsBackendError!void {
        return self.vtable.end_command_buffer(self.impl_data, cmd);
    }

    pub fn submitCommandBuffer(self: *Self, cmd: *CommandBuffer) GraphicsBackendError!void {
        return self.vtable.submit_command_buffer(self.impl_data, cmd);
    }

    // Render commands
    pub fn beginRenderPass(self: *Self, cmd: *CommandBuffer, desc: *const RenderPassDesc) GraphicsBackendError!void {
        return self.vtable.begin_render_pass(self.impl_data, cmd, desc);
    }

    pub fn endRenderPass(self: *Self, cmd: *CommandBuffer) GraphicsBackendError!void {
        return self.vtable.end_render_pass(self.impl_data, cmd);
    }

    pub fn setViewport(self: *Self, cmd: *CommandBuffer, viewport: *const types.Viewport) GraphicsBackendError!void {
        return self.vtable.set_viewport(self.impl_data, cmd, viewport);
    }

    pub fn setScissor(self: *Self, cmd: *CommandBuffer, rect: *const types.Viewport) GraphicsBackendError!void {
        return self.vtable.set_scissor(self.impl_data, cmd, rect);
    }

    pub fn bindPipeline(self: *Self, cmd: *CommandBuffer, pipeline: *Pipeline) GraphicsBackendError!void {
        return self.vtable.bind_pipeline(self.impl_data, cmd, pipeline);
    }

    pub fn bindVertexBuffer(self: *Self, cmd: *CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) GraphicsBackendError!void {
        return self.vtable.bind_vertex_buffer(self.impl_data, cmd, slot, buffer, offset);
    }

    pub fn bindIndexBuffer(self: *Self, cmd: *CommandBuffer, buffer: *types.Buffer, offset: u64, format: IndexFormat) GraphicsBackendError!void {
        return self.vtable.bind_index_buffer(self.impl_data, cmd, buffer, offset, format);
    }

    pub fn bindTexture(self: *Self, cmd: *CommandBuffer, slot: u32, texture: *types.Texture) GraphicsBackendError!void {
        return self.vtable.bind_texture(self.impl_data, cmd, slot, texture);
    }

    pub fn bindUniformBuffer(self: *Self, cmd: *CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) GraphicsBackendError!void {
        return self.vtable.bind_uniform_buffer(self.impl_data, cmd, slot, buffer, offset, size);
    }

    // Draw commands
    pub fn draw(self: *Self, cmd: *CommandBuffer, draw_cmd: *const DrawCommand) GraphicsBackendError!void {
        return self.vtable.draw(self.impl_data, cmd, draw_cmd);
    }

    pub fn drawIndexed(self: *Self, cmd: *CommandBuffer, draw_cmd: *const DrawIndexedCommand) GraphicsBackendError!void {
        return self.vtable.draw_indexed(self.impl_data, cmd, draw_cmd);
    }

    pub fn dispatch(self: *Self, cmd: *CommandBuffer, dispatch_cmd: *const DispatchCommand) GraphicsBackendError!void {
        return self.vtable.dispatch(self.impl_data, cmd, dispatch_cmd);
    }

    // Resource copying
    pub fn copyBuffer(self: *Self, cmd: *CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const BufferCopyRegion) GraphicsBackendError!void {
        return self.vtable.copy_buffer(self.impl_data, cmd, src, dst, region);
    }

    pub fn copyTexture(self: *Self, cmd: *CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const TextureCopyRegion) GraphicsBackendError!void {
        return self.vtable.copy_texture(self.impl_data, cmd, src, dst, region);
    }

    pub fn copyBufferToTexture(self: *Self, cmd: *CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const TextureCopyRegion) GraphicsBackendError!void {
        return self.vtable.copy_buffer_to_texture(self.impl_data, cmd, src, dst, region);
    }

    pub fn copyTextureToBuffer(self: *Self, cmd: *CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const TextureCopyRegion) GraphicsBackendError!void {
        return self.vtable.copy_texture_to_buffer(self.impl_data, cmd, src, dst, region);
    }

    // Synchronization
    pub fn resourceBarrier(self: *Self, cmd: *CommandBuffer, barriers: []const ResourceBarrier) GraphicsBackendError!void {
        return self.vtable.resource_barrier(self.impl_data, cmd, barriers);
    }

    // Query and debug
    pub fn getBackendInfo(self: *Self) BackendInfo {
        return self.vtable.get_backend_info(self.impl_data);
    }

    pub fn setDebugName(self: *Self, resource: ResourceHandle, name: []const u8) GraphicsBackendError!void {
        return self.vtable.set_debug_name(self.impl_data, resource, name);
    }

    pub fn beginDebugGroup(self: *Self, cmd: *CommandBuffer, name: []const u8) GraphicsBackendError!void {
        return self.vtable.begin_debug_group(self.impl_data, cmd, name);
    }

    pub fn endDebugGroup(self: *Self, cmd: *CommandBuffer) GraphicsBackendError!void {
        return self.vtable.end_debug_group(self.impl_data, cmd);
    }
};

/// Graphics backend capability and information structure
/// @thread-safe Thread-compatible data structure
/// @symbol Backend information structure
pub const BackendInfo = struct {
    name: []const u8,
    version: []const u8,
    vendor: []const u8,
    device_name: []const u8,
    api_version: u32,
    driver_version: u32,
    memory_budget: u64,
    memory_usage: u64,
    max_texture_size: u32,
    max_render_targets: u32,
    max_vertex_attributes: u32,
    max_uniform_buffer_bindings: u32,
    max_texture_bindings: u32,
    supports_compute: bool,
    supports_geometry_shaders: bool,
    supports_tessellation: bool,
    supports_raytracing: bool,
    supports_mesh_shaders: bool,
    supports_variable_rate_shading: bool,
    supports_multiview: bool,
};
