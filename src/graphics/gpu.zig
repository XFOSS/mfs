const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
// Silence unused-import error during compilation. Remove when build_options fields are referenced here.
comptime {
    _ = build_options;
}
const backends = @import("backends/mod.zig");
const resource_manager = @import("resource_manager.zig");
const interface = @import("backends/interface.zig");
pub const BackendType = interface.BackendType;
pub const IndexFormat = interface.IndexFormat;
const types = @import("types.zig");
pub const TextureFormat = types.TextureFormat;
pub const TextureType = types.TextureType;
pub const ShaderType = types.ShaderType;
pub const BufferUsage = types.BufferUsage;
pub const Viewport = types.Viewport;
pub const ClearColor = types.ClearColor;
pub const Texture = types.Texture;
pub const Shader = types.Shader;
pub const Buffer = types.Buffer;
pub const RenderTarget = types.RenderTarget;

// Pipeline management
const pipeline_state = @import("pipeline_state.zig");
pub const PipelineState = pipeline_state.PipelineState;
pub const PipelineStateCache = pipeline_state.PipelineStateCache;

// Re-export the main graphics backend interface
pub const GraphicsBackend = backends.interface.GraphicsBackend;

pub const Error = error{
    NoSuitableBackendFound,
    BackendInitializationFailed,
    SwapChainCreationFailed,
    ResourceCreationFailed,
    InvalidOperation,
    OutOfMemory,
    UnsupportedFeature,
    ResourceManagerNotInitialized,
    PipelineCacheNotInitialized,
} || types.GraphicsError;

pub const SwapChainOptions = struct {
    width: u32,
    height: u32,
    buffer_count: u32 = 2,
    vsync: bool = true,
    window_handle: ?*anyopaque = null,
    format: TextureFormat = .rgba8,
};

pub const RenderPassOptions = struct {
    color_targets: []*Texture,
    depth_target: ?*Texture = null,
    clear_color: ?ClearColor = null,
    clear_depth: ?f32 = null,
    clear_stencil: ?u32 = null,
};

pub const PipelineOptions = struct {
    vertex_shader: *Shader,
    fragment_shader: ?*Shader = null,
    vertex_layout: ?interface.VertexLayout = null,
    primitive_topology: interface.PrimitiveTopology = .triangles,
    blend_state: interface.BlendState = .{
        .enabled = false,
        .src_color = .one,
        .dst_color = .zero,
        .color_op = .add,
        .src_alpha = .one,
        .dst_alpha = .zero,
        .alpha_op = .add,
        .color_mask = .all,
    },
    depth_stencil_state: interface.DepthStencilState = .{
        .depth_test_enabled = true,
        .depth_write_enabled = true,
        .depth_compare = .less,
        .stencil_enabled = false,
        .stencil_read_mask = 0xFF,
        .stencil_write_mask = 0xFF,
        .front_face = .{
            .fail = .keep,
            .depth_fail = .keep,
            .pass = .keep,
            .compare = .always,
        },
        .back_face = .{
            .fail = .keep,
            .depth_fail = .keep,
            .pass = .keep,
            .compare = .always,
        },
    },
    rasterizer_state: interface.RasterizerState = .{
        .fill_mode = .solid,
        .cull_mode = .back,
        .front_face = .counter_clockwise,
        .depth_bias = 0,
        .depth_bias_clamp = 0.0,
        .slope_scaled_depth_bias = 0.0,
        .depth_clip_enabled = true,
        .scissor_enabled = false,
        .multisample_enabled = false,
        .antialiased_line_enabled = false,
    },
};

pub const DrawOptions = struct {
    vertex_count: u32,
    instance_count: u32 = 1,
    first_vertex: u32 = 0,
    first_instance: u32 = 0,
};

pub const DrawIndexedOptions = struct {
    index_count: u32,
    instance_count: u32 = 1,
    first_index: u32 = 0,
    vertex_offset: i32 = 0,
    first_instance: u32 = 0,
};

pub const DispatchOptions = struct {
    group_count_x: u32,
    group_count_y: u32 = 1,
    group_count_z: u32 = 1,
};

pub const CommandBuffer = struct {
    command_buffer: *interface.CommandBuffer,
    active_render_pass: bool = false,
    active_pipeline: ?*interface.Pipeline = null,

    pub fn deinit(self: *CommandBuffer) void {
        self.command_buffer.deinit();
    }
};

pub const Pipeline = struct {
    pipeline: *interface.Pipeline,

    pub fn deinit(self: *Pipeline) void {
        self.pipeline.deinit();
    }
};

// Global state
var initialized = false;
var frame_counter: u64 = 0;
var default_allocator: std.mem.Allocator = undefined;
var backend: ?*interface.GraphicsBackend = null;
var backend_mgr: ?*resource_manager.BackendManager = null;

// Initialize the GPU subsystem with the given options
pub fn init(allocator: std.mem.Allocator, options: resource_manager.BackendManager.InitOptions) Error!void {
    if (initialized) return;

    default_allocator = allocator;
    backend_mgr = try resource_manager.BackendManager.init(allocator, options);
    errdefer {
        if (backend_mgr) |mgr| {
            mgr.deinit();
        }
    }

    backend = backend_mgr.?.getPrimaryBackend();
    if (backend == null) return Error.NoSuitableBackendFound;

    initialized = true;
}

// Clean up resources and shutdown
pub fn deinit() void {
    if (!initialized) return;

    if (backend_mgr) |mgr| {
        mgr.deinit();
        backend_mgr = null;
    }

    backend = null;
    initialized = false;
}

// Get information about the current backend
pub fn getBackendInfo() interface.BackendInfo {
    if (!initialized or backend == null) {
        return interface.BackendInfo{
            .name = "Uninitialized",
            .version = "0.0",
            .vendor = "None",
            .device_name = "None",
            .api_version = 0,
            .driver_version = 0,
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 0,
            .max_render_targets = 0,
            .max_vertex_attributes = 0,
            .max_uniform_buffer_bindings = 0,
            .max_texture_bindings = 0,
            .supports_compute = false,
            .supports_geometry_shaders = false,
            .supports_tessellation = false,
            .supports_raytracing = false,
            .supports_mesh_shaders = false,
            .supports_variable_rate_shading = false,
            .supports_multiview = false,
        };
    }

    return backend.?.getBackendInfo();
}

// Get the backend type currently in use
pub fn getBackendType() BackendType {
    if (!initialized or backend == null) return .software;
    return backend.?.backend_type;
}

// Switch to a different backend
pub fn switchBackend(backend_type: BackendType) Error!void {
    if (!initialized or backend_mgr == null) return Error.InvalidOperation;

    try backend_mgr.?.switchBackend(backend_type);
    backend = backend_mgr.?.getPrimaryBackend();
    if (backend == null) return Error.NoSuitableBackendFound;
}

// Create a swap chain with the given options
pub fn createSwapChain(options: SwapChainOptions) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    const desc = interface.SwapChainDesc{
        .width = options.width,
        .height = options.height,
        .format = options.format,
        .buffer_count = options.buffer_count,
        .vsync = options.vsync,
        .window_handle = options.window_handle,
    };

    backend.?.createSwapChain(&desc) catch |err| {
        return translateError(err);
    };
}

// Resize the swap chain
pub fn resizeSwapChain(width: u32, height: u32) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.resizeSwapChain(width, height) catch |err| {
        return translateError(err);
    };
}

// Present the current frame to the screen
pub fn present() Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.present() catch |err| {
        return translateError(err);
    };
}

// Get the current back buffer texture
pub fn getCurrentBackBuffer() Error!*Texture {
    if (!initialized or backend == null) return Error.InvalidOperation;

    return backend.?.getCurrentBackBuffer() catch |err| {
        return translateError(err);
    };
}

// Create a texture with the given parameters
pub fn createTexture(width: u32, height: u32, format: TextureFormat, texture_type: TextureType, data: ?[]const u8) Error!*Texture {
    if (!initialized or backend == null) return Error.InvalidOperation;

    var texture = try Texture.init(default_allocator, width, height, format);
    texture.texture_type = texture_type;
    errdefer texture.deinit();

    backend.?.createTexture(texture, data) catch |err| {
        return translateError(err);
    };

    return texture;
}

// Create a buffer with the given parameters
pub fn createBuffer(size: usize, usage: BufferUsage, data: ?[]const u8) Error!*Buffer {
    if (!initialized or backend == null) return Error.InvalidOperation;

    var buffer = try Buffer.init(default_allocator, size, usage);
    errdefer buffer.deinit();

    backend.?.createBuffer(buffer, data) catch |err| {
        return translateError(err);
    };

    return buffer;
}

// Create a shader with the given source and type
pub fn createShader(shader_type: ShaderType, source: []const u8) Error!*Shader {
    if (!initialized or backend == null) return Error.InvalidOperation;

    var shader = try Shader.init(default_allocator, shader_type, source);
    errdefer shader.deinit();

    backend.?.createShader(shader) catch |err| {
        return translateError(err);
    };

    return shader;
}

// Create a render target
pub fn createRenderTarget(width: u32, height: u32) Error!*RenderTarget {
    if (!initialized or backend == null) return Error.InvalidOperation;

    var render_target = try RenderTarget.init(default_allocator, width, height);
    errdefer render_target.deinit();

    backend.?.createRenderTarget(render_target) catch |err| {
        return translateError(err);
    };

    return render_target;
}

// Create a pipeline from the given options
pub fn createPipeline(options: PipelineOptions) Error!Pipeline {
    if (!initialized or backend == null) return Error.InvalidOperation;

    var desc = interface.PipelineDesc{
        .vertex_shader = options.vertex_shader,
        .fragment_shader = options.fragment_shader,
        .geometry_shader = null,
        .compute_shader = null,
        .vertex_layout = options.vertex_layout,
        .blend_state = options.blend_state,
        .depth_stencil_state = options.depth_stencil_state,
        .rasterizer_state = options.rasterizer_state,
        .primitive_topology = options.primitive_topology,
        .render_target_formats = &[_]TextureFormat{.rgba8},
        .depth_format = .depth24_stencil8,
        .sample_count = 1,
    };

    const pipeline = backend.?.createPipeline(&desc) catch |err| {
        return translateError(err);
    };

    return Pipeline{
        .pipeline = pipeline,
    };
}

// Create a command buffer for recording commands
pub fn createCommandBuffer() Error!CommandBuffer {
    if (!initialized or backend == null) return Error.InvalidOperation;

    const cmd = backend.?.createCommandBuffer() catch |err| {
        return translateError(err);
    };

    return CommandBuffer{
        .command_buffer = cmd,
    };
}

// Begin recording commands to a command buffer
pub fn beginCommandBuffer(cmd: *CommandBuffer) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.beginCommandBuffer(cmd.command_buffer) catch |err| {
        return translateError(err);
    };
}

// End recording commands to a command buffer
pub fn endCommandBuffer(cmd: *CommandBuffer) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.endCommandBuffer(cmd.command_buffer) catch |err| {
        return translateError(err);
    };
}

// Submit a command buffer for execution
pub fn submitCommandBuffer(cmd: *CommandBuffer) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.submitCommandBuffer(cmd.command_buffer) catch |err| {
        return translateError(err);
    };
}

// Begin a render pass
pub fn beginRenderPass(cmd: *CommandBuffer, options: RenderPassOptions) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (cmd.active_render_pass) return Error.InvalidOperation;

    var desc = interface.RenderPassDesc{
        .color_targets = options.color_targets,
        .depth_target = options.depth_target,
        .clear_color = options.clear_color orelse ClearColor{},
        .clear_depth = options.clear_depth orelse 1.0,
        .clear_stencil = options.clear_stencil orelse 0,
    };

    backend.?.beginRenderPass(cmd.command_buffer, &desc) catch |err| {
        return translateError(err);
    };

    cmd.active_render_pass = true;
}

// End a render pass
pub fn endRenderPass(cmd: *CommandBuffer) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.endRenderPass(cmd.command_buffer) catch |err| {
        return translateError(err);
    };

    cmd.active_render_pass = false;
}

// Set the viewport
pub fn setViewport(cmd: *CommandBuffer, viewport: *const Viewport) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.setViewport(cmd.command_buffer, viewport) catch |err| {
        return translateError(err);
    };
}

// Set the scissor rectangle
pub fn setScissor(cmd: *CommandBuffer, rect: *const Viewport) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.setScissor(cmd.command_buffer, rect) catch |err| {
        return translateError(err);
    };
}

// Bind a pipeline
pub fn bindPipeline(cmd: *CommandBuffer, pipeline: *Pipeline) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.bindPipeline(cmd.command_buffer, pipeline.pipeline) catch |err| {
        return translateError(err);
    };

    cmd.active_pipeline = pipeline.pipeline;
}

// Bind a vertex buffer
pub fn bindVertexBuffer(cmd: *CommandBuffer, slot: u32, buffer: *Buffer, offset: u64) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.bindVertexBuffer(cmd.command_buffer, slot, buffer, offset) catch |err| {
        return translateError(err);
    };
}

// Bind an index buffer
pub fn bindIndexBuffer(cmd: *CommandBuffer, buffer: *Buffer, offset: u64, format: IndexFormat) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.bindIndexBuffer(cmd.command_buffer, buffer, offset, format) catch |err| {
        return translateError(err);
    };
}

// Bind a texture
pub fn bindTexture(cmd: *CommandBuffer, slot: u32, texture: *Texture) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.bindTexture(cmd.command_buffer, slot, texture) catch |err| {
        return translateError(err);
    };
}

// Bind a uniform buffer
pub fn bindUniformBuffer(cmd: *CommandBuffer, slot: u32, buffer: *Buffer, offset: u64, size: u64) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;

    backend.?.bindUniformBuffer(cmd.command_buffer, slot, buffer, offset, size) catch |err| {
        return translateError(err);
    };
}

// Draw vertices
pub fn draw(cmd: *CommandBuffer, options: DrawOptions) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;
    if (cmd.active_pipeline == null) return Error.InvalidOperation;

    const draw_cmd = interface.DrawCommand{
        .vertex_count = options.vertex_count,
        .instance_count = options.instance_count,
        .first_vertex = options.first_vertex,
        .first_instance = options.first_instance,
    };

    backend.?.draw(cmd.command_buffer, &draw_cmd) catch |err| {
        return translateError(err);
    };
}

// Draw indexed vertices
pub fn drawIndexed(cmd: *CommandBuffer, options: DrawIndexedOptions) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;
    if (!cmd.active_render_pass) return Error.InvalidOperation;
    if (cmd.active_pipeline == null) return Error.InvalidOperation;

    const draw_cmd = interface.DrawIndexedCommand{
        .index_count = options.index_count,
        .instance_count = options.instance_count,
        .first_index = options.first_index,
        .vertex_offset = options.vertex_offset,
        .first_instance = options.first_instance,
    };

    backend.?.drawIndexed(cmd.command_buffer, &draw_cmd) catch |err| {
        return translateError(err);
    };
}

// Dispatch compute work
pub fn dispatch(cmd: *CommandBuffer, options: DispatchOptions) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    const dispatch_cmd = interface.DispatchCommand{
        .group_count_x = options.group_count_x,
        .group_count_y = options.group_count_y,
        .group_count_z = options.group_count_z,
    };

    backend.?.dispatch(cmd.command_buffer, &dispatch_cmd) catch |err| {
        return translateError(err);
    };
}

// Update a buffer's contents
pub fn updateBuffer(buffer: *Buffer, offset: u64, data: []const u8) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.updateBuffer(buffer, offset, data) catch |err| {
        return translateError(err);
    };
}

// Update a texture's contents
pub fn updateTexture(texture: *Texture, region: *const interface.TextureCopyRegion, data: []const u8) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.updateTexture(texture, region, data) catch |err| {
        return translateError(err);
    };
}

// Copy data between buffers
pub fn copyBuffer(cmd: *CommandBuffer, src: *Buffer, dst: *Buffer, region: *const interface.BufferCopyRegion) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.copyBuffer(cmd.command_buffer, src, dst, region) catch |err| {
        return translateError(err);
    };
}

// Copy data between textures
pub fn copyTexture(cmd: *CommandBuffer, src: *Texture, dst: *Texture, region: *const interface.TextureCopyRegion) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.copyTexture(cmd.command_buffer, src, dst, region) catch |err| {
        return translateError(err);
    };
}

// Copy data from a buffer to a texture
pub fn copyBufferToTexture(cmd: *CommandBuffer, src: *Buffer, dst: *Texture, region: *const interface.TextureCopyRegion) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.copyBufferToTexture(cmd.command_buffer, src, dst, region) catch |err| {
        return translateError(err);
    };
}

// Copy data from a texture to a buffer
pub fn copyTextureToBuffer(cmd: *CommandBuffer, src: *Texture, dst: *Buffer, region: *const interface.TextureCopyRegion) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.copyTextureToBuffer(cmd.command_buffer, src, dst, region) catch |err| {
        return translateError(err);
    };
}

// Insert a resource barrier
pub fn resourceBarrier(cmd: *CommandBuffer, barriers: []const interface.ResourceBarrier) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.resourceBarrier(cmd.command_buffer, barriers) catch |err| {
        return translateError(err);
    };
}

// Set a debug name for a resource
pub fn setDebugName(resource: interface.ResourceHandle, name: []const u8) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.setDebugName(resource, name) catch |err| {
        return translateError(err);
    };
}

// Begin a debug group
pub fn beginDebugGroup(cmd: *CommandBuffer, name: []const u8) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.beginDebugGroup(cmd.command_buffer, name) catch |err| {
        return translateError(err);
    };
}

// End a debug group
pub fn endDebugGroup(cmd: *CommandBuffer) Error!void {
    if (!initialized or backend == null) return Error.InvalidOperation;

    backend.?.endDebugGroup(cmd.command_buffer) catch |err| {
        return translateError(err);
    };
}

// Helper function to translate backend-specific errors to unified errors
fn translateError(err: interface.GraphicsBackendError) Error {
    return switch (err) {
        error.BackendInitializationFailed => Error.BackendInitializationFailed,
        error.OutOfMemory => Error.OutOfMemory,
        error.InvalidOperation => Error.InvalidOperation,
        error.UnsupportedOperation => Error.UnsupportedFeature,
        error.ResourceCreationFailed => Error.ResourceCreationFailed,
        error.SwapChainCreationFailed => Error.SwapChainCreationFailed,
        error.ShaderCompilationFailed => Error.ResourceCreationFailed,
        error.InvalidFormat => Error.InvalidOperation,
        error.InvalidParameter => Error.InvalidOperation,
    };
}
