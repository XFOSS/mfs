const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu.zig");
const types = @import("types.zig");
const interface = @import("backends/interface.zig");
const shader = @import("shader.zig");

/// Error types specific to pipeline operations
/// @symbol Public error type for pipeline operations
pub const PipelineError = error{
    InvalidOptions,
    CreationFailed,
    OutOfMemory,
    UnsupportedFeature,
    MissingShader,
};

/// PipelineType defines the type of pipeline being created
/// @symbol Public type definition for pipeline classification
pub const PipelineType = enum {
    graphics,
    compute,
};

/// PipelineState encapsulates all state needed to define a graphics pipeline
/// @thread-safe Not thread-safe, external synchronization required
/// @symbol Core pipeline state management component
pub const PipelineState = struct {
    allocator: Allocator,
    pipeline: ?gpu.Pipeline,
    vertex_shader: ?*gpu.Shader,
    fragment_shader: ?*gpu.Shader,
    geometry_shader: ?*gpu.Shader,
    compute_shader: ?*gpu.Shader,
    tessellation_control_shader: ?*gpu.Shader,
    tessellation_evaluation_shader: ?*gpu.Shader,
    vertex_layout: ?interface.VertexLayout,
    topology: interface.PrimitiveTopology,
    blend_state: interface.BlendState,
    depth_stencil_state: interface.DepthStencilState,
    rasterizer_state: interface.RasterizerState,
    target_formats: [8]types.TextureFormat,
    depth_format: types.TextureFormat,
    sample_count: u8,
    shader_program: ?*shader.ShaderProgram,
    pipeline_type: PipelineType,
    name: ?[]const u8,
    pipeline_hash: u64,

    const Self = @This();

    /// Initialize a new pipeline state object
    /// @thread-safe Not thread-safe
    /// @symbol Public pipeline initialization API
    pub fn init(allocator: Allocator) !*Self {
        const state = try allocator.create(Self);
        state.* = Self{
            .allocator = allocator,
            .pipeline = null,
            .vertex_shader = null,
            .fragment_shader = null,
            .geometry_shader = null,
            .compute_shader = null,
            .tessellation_control_shader = null,
            .tessellation_evaluation_shader = null,
            .vertex_layout = null,
            .topology = .triangles,
            .blend_state = .{
                .enabled = false,
                .src_color = .one,
                .dst_color = .zero,
                .color_op = .add,
                .src_alpha = .one,
                .dst_alpha = .zero,
                .alpha_op = .add,
                .color_mask = .{ .r = true, .g = true, .b = true, .a = true },
            },
            .depth_stencil_state = .{
                .depth_test_enabled = true,
                .depth_write_enabled = true,
                .depth_compare = .less,
                .stencil_enabled = false,
                .stencil_read_mask = 0xff,
                .stencil_write_mask = 0xff,
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
            .rasterizer_state = .{
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
            .target_formats = [_]types.TextureFormat{.rgba8} ++ [_]types.TextureFormat{.undefined} ** 7,
            .depth_format = .depth24_stencil8,
            .sample_count = 1,
            .shader_program = null,
            .pipeline_type = .graphics,
            .name = null,
            .pipeline_hash = 0,
        };

        return state;
    }

    /// Clean up resources and destroy the pipeline state
    /// @thread-safe Not thread-safe
    /// @symbol Public pipeline cleanup API
    pub fn deinit(self: *Self) void {
        if (self.pipeline) |*pipeline| {
            pipeline.deinit();
        }

        if (self.name) |name| {
            self.allocator.free(name);
        }

        self.allocator.destroy(self);
    }

    /// Set a debug name for the pipeline
    /// @thread-safe Not thread-safe
    /// @symbol Public naming API
    pub fn setName(self: *Self, name: []const u8) !void {
        if (self.name) |old_name| {
            self.allocator.free(old_name);
        }

        self.name = try self.allocator.dupe(u8, name);
        self.pipeline_hash = std.hash.Wyhash.hash(0, name);
    }

    /// Set the vertex shader for this pipeline
    /// @thread-safe Not thread-safe
    /// @symbol Public shader configuration API
    pub fn setVertexShader(self: *Self, shader_obj: *gpu.Shader) void {
        self.vertex_shader = shader_obj;
        if (shader_obj.compiled) {
            self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, @as([]const u8, @bitCast(&shader_obj.id)));
        }
    }

    /// Set the fragment shader for this pipeline
    /// @thread-safe Not thread-safe
    /// @symbol Public shader configuration API
    pub fn setFragmentShader(self: *Self, shader_obj: *gpu.Shader) void {
        self.fragment_shader = shader_obj;
        if (shader_obj.compiled) {
            self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, @as([]const u8, @bitCast(&shader_obj.id)));
        }
    }

    /// Set the geometry shader for this pipeline
    /// @thread-safe Not thread-safe
    /// @symbol Public shader configuration API
    pub fn setGeometryShader(self: *Self, shader_obj: *gpu.Shader) void {
        self.geometry_shader = shader_obj;
        if (shader_obj.compiled) {
            self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, @as([]const u8, @bitCast(&shader_obj.id)));
        }
    }

    /// Set the compute shader for this pipeline
    /// @thread-safe Not thread-safe
    /// @symbol Public shader configuration API
    pub fn setComputeShader(self: *Self, shader_obj: *gpu.Shader) void {
        self.compute_shader = shader_obj;
        self.pipeline_type = .compute;
        if (shader_obj.compiled) {
            self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, @as([]const u8, @bitCast(&shader_obj.id)));
        }
    }

    /// Set the vertex input layout for this pipeline
    /// @thread-safe Not thread-safe
    /// @symbol Public vertex configuration API
    pub fn setVertexLayout(self: *Self, layout: interface.VertexLayout) void {
        self.vertex_layout = layout;
        self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&layout.stride));
    }

    pub fn setTopology(self: *Self, topology: interface.PrimitiveTopology) void {
        self.topology = topology;
        self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&topology));
    }

    pub fn setBlendState(self: *Self, blend: interface.BlendState) void {
        self.blend_state = blend;
        self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&blend));
    }

    pub fn setDepthStencilState(self: *Self, depth_stencil: interface.DepthStencilState) void {
        self.depth_stencil_state = depth_stencil;
        self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&depth_stencil));
    }

    pub fn setRasterizerState(self: *Self, rasterizer: interface.RasterizerState) void {
        self.rasterizer_state = rasterizer;
        self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&rasterizer));
    }

    pub fn setTargetFormat(self: *Self, index: usize, format: types.TextureFormat) void {
        if (index < 8) {
            self.target_formats[index] = format;
            self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&format));
        }
    }

    pub fn setDepthFormat(self: *Self, format: types.TextureFormat) void {
        self.depth_format = format;
        self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&format));
    }

    pub fn setSampleCount(self: *Self, samples: u8) void {
        self.sample_count = samples;
        self.pipeline_hash = std.hash.Wyhash.hash(self.pipeline_hash, std.mem.asBytes(&samples));
    }

    pub fn setShaderProgram(self: *Self, program: *shader.ShaderProgram) void {
        self.shader_program = program;
        if (program.vertex_shader) |vs| self.setVertexShader(vs);
        if (program.fragment_shader) |fs| self.setFragmentShader(fs);
        if (program.geometry_shader) |gs| self.setGeometryShader(gs);
        if (program.compute_shader) |cs| self.setComputeShader(cs);
        if (program.tesselation_control_shader) |tcs| self.tessellation_control_shader = tcs;
        if (program.tesselation_evaluation_shader) |tes| self.tessellation_evaluation_shader = tes;
    }

    /// For alpha blending with premultiplied alpha
    /// Set predefined blend state for premultiplied alpha
    /// @thread-safe Not thread-safe
    /// @symbol Public blend configuration helper
    pub fn setPremultipliedAlphaBlend(self: *Self) void {
        self.blend_state = .{
            .enabled = true,
            .src_color = .one,
            .dst_color = .inv_src_alpha,
            .color_op = .add,
            .src_alpha = .one,
            .dst_alpha = .inv_src_alpha,
            .alpha_op = .add,
            .color_mask = .{ .r = true, .g = true, .b = true, .a = true },
        };
    }

    /// Set predefined blend state for standard (non-premultiplied) alpha
    /// @thread-safe Not thread-safe
    /// @symbol Public blend configuration helper
    pub fn setStandardAlphaBlend(self: *Self) void {
        self.blend_state = .{
            .enabled = true,
            .src_color = .src_alpha,
            .dst_color = .inv_src_alpha,
            .color_op = .add,
            .src_alpha = .one,
            .dst_alpha = .inv_src_alpha,
            .alpha_op = .add,
            .color_mask = .{ .r = true, .g = true, .b = true, .a = true },
        };
    }

    /// Set predefined blend state for additive blending
    /// @thread-safe Not thread-safe
    /// @symbol Public blend configuration helper
    pub fn setAdditiveBlend(self: *Self) void {
        self.blend_state = .{
            .enabled = true,
            .src_color = .src_alpha,
            .dst_color = .one,
            .color_op = .add,
            .src_alpha = .one,
            .dst_alpha = .one,
            .alpha_op = .add,
            .color_mask = .{ .r = true, .g = true, .b = true, .a = true },
        };
    }

    /// Disable depth testing and writing for UI or overlays
    /// @thread-safe Not thread-safe
    /// @symbol Public depth configuration helper
    pub fn disableDepthTest(self: *Self) void {
        self.depth_stencil_state.depth_test_enabled = false;
        self.depth_stencil_state.depth_write_enabled = false;
    }

    /// Enable depth testing but disable writing (for translucent objects)
    /// @thread-safe Not thread-safe
    /// @symbol Public depth configuration helper
    pub fn enableDepthTestNoWrite(self: *Self) void {
        self.depth_stencil_state.depth_test_enabled = true;
        self.depth_stencil_state.depth_write_enabled = false;
    }

    /// Create the pipeline state object from current configuration
    /// @thread-safe Not thread-safe
    /// @symbol Public pipeline finalization API
    pub fn build(self: *Self) !void {
        if (self.pipeline_type == .graphics) {
            if (self.vertex_shader == null) {
                return PipelineError.MissingShader;
            }

            const options = gpu.PipelineOptions{
                .vertex_shader = self.vertex_shader.?,
                .fragment_shader = self.fragment_shader,
                .vertex_layout = self.vertex_layout orelse interface.VertexLayout{
                    .attributes = &[_]interface.VertexAttribute{},
                    .stride = 0,
                },
                .primitive_topology = self.topology,
                .blend_state = self.blend_state,
                .depth_stencil_state = self.depth_stencil_state,
                .rasterizer_state = self.rasterizer_state,
            };

            self.pipeline = try gpu.createPipeline(options);
        } else if (self.pipeline_type == .compute) {
            if (self.compute_shader == null) {
                return PipelineError.MissingShader;
            }

            // For compute pipeline, we need a different set of options
            // Currently our gpu.zig doesn't expose compute pipeline creation
            return PipelineError.UnsupportedFeature;
        }

        // If we have a name, set the debug name
        if (self.name) |name| {
            if (self.pipeline) |pipeline| {
                gpu.setDebugName(interface.ResourceHandle{ .pipeline = &pipeline }, name) catch {};
            }
        }
    }

    /// Bind this pipeline for rendering
    /// @thread-safe Not thread-safe, must be called from render thread
    /// @symbol Public pipeline binding API
    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer) !void {
        if (self.pipeline) |*pipeline| {
            try gpu.bindPipeline(cmd, pipeline);
        } else {
            return PipelineError.InvalidOptions;
        }
    }
};

/// PipelineStateCache stores and reuses pipeline state objects based on their configuration hash
pub const PipelineStateCache = struct {
    allocator: Allocator,
    pipelines: std.AutoHashMap(u64, *PipelineState),

    pub fn init(allocator: Allocator) PipelineStateCache {
        return PipelineStateCache{
            .allocator = allocator,
            .pipelines = std.AutoHashMap(u64, *PipelineState).init(allocator),
        };
    }

    pub fn deinit(self: *PipelineStateCache) void {
        var it = self.pipelines.valueIterator();
        while (it.next()) |pipeline| {
            pipeline.*.deinit();
        }
        self.pipelines.deinit();
    }

    pub fn getPipeline(self: *PipelineStateCache, hash: u64) ?*PipelineState {
        return self.pipelines.get(hash);
    }

    pub fn addPipeline(self: *PipelineStateCache, pipeline: *PipelineState) !void {
        try self.pipelines.put(pipeline.pipeline_hash, pipeline);
    }

    pub fn removePipeline(self: *PipelineStateCache, hash: u64) void {
        _ = self.pipelines.remove(hash);
    }

    pub fn clear(self: *PipelineStateCache) void {
        var it = self.pipelines.valueIterator();
        while (it.next()) |pipeline| {
            pipeline.*.deinit();
        }
        self.pipelines.clearRetainingCapacity();
    }
};

/// Global pipeline cache
var global_pipeline_cache: ?PipelineStateCache = null;

/// Initialize the global pipeline cache
pub fn initPipelineCache(allocator: std.mem.Allocator) void {
    global_pipeline_cache = PipelineStateCache.init(allocator);
}

/// Deinitialize the global pipeline cache
pub fn deinitPipelineCache() void {
    if (global_pipeline_cache) |*cache| {
        cache.deinit();
        global_pipeline_cache = null;
    }
}

/// Get or create a pipeline with a given configuration
pub fn getOrCreatePipeline(allocator: std.mem.Allocator, hash: u64) !*PipelineState {
    if (global_pipeline_cache) |*cache| {
        if (cache.getPipeline(hash)) |pipeline| {
            return pipeline;
        }
    }

    // Create a new pipeline
    const pipeline = try PipelineState.init(allocator);

    // Add to cache if available
    if (global_pipeline_cache) |*cache| {
        try cache.addPipeline(pipeline);
    }

    return pipeline;
}
