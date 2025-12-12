//! MFS Engine - Advanced Rendering Features
//! Modern rendering techniques including compute shaders, mesh shaders, and ray tracing
//! Inspired by zig-renderkit's approach to modern graphics APIs

const std = @import("std");
const graphics = @import("mod.zig");
const math = @import("../math/mod.zig");
const build_options = @import("../build_options.zig");

/// Advanced rendering context for modern GPU features
pub const AdvancedRenderer = struct {
    allocator: std.mem.Allocator,
    backend: *graphics.backend_manager.BackendInterface,

    // Ray tracing resources
    ray_tracing: ?RayTracingContext = null,

    // Mesh shader resources
    mesh_shaders: ?MeshShaderContext = null,

    // Compute shader resources
    compute_context: ComputeContext,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface) !Self {
        var renderer = Self{
            .allocator = allocator,
            .backend = backend,
            .compute_context = try ComputeContext.init(allocator, backend),
        };

        // Initialize ray tracing if supported
        if (supportsRayTracing(backend.backend_type)) {
            renderer.ray_tracing = try RayTracingContext.init(allocator, backend);
        }

        // Initialize mesh shaders if supported
        if (supportsMeshShaders(backend.backend_type)) {
            renderer.mesh_shaders = try MeshShaderContext.init(allocator, backend);
        }

        return renderer;
    }

    pub fn deinit(self: *Self) void {
        if (self.ray_tracing) |*rt| {
            rt.deinit();
        }
        if (self.mesh_shaders) |*ms| {
            ms.deinit();
        }
        self.compute_context.deinit();
    }

    /// Dispatch a compute shader with automatic resource barriers
    pub fn dispatchCompute(self: *Self, shader: *graphics.types.Shader, groups_x: u32, groups_y: u32, groups_z: u32) !void {
        try self.compute_context.dispatch(shader, groups_x, groups_y, groups_z);
    }

    /// Render using mesh shaders (if supported)
    pub fn renderMeshlets(self: *Self, meshlet_data: []const Meshlet) !void {
        if (self.mesh_shaders) |*ms| {
            try ms.renderMeshlets(meshlet_data);
        } else {
            return error.MeshShadersNotSupported;
        }
    }

    /// Trace rays for global illumination or reflections
    pub fn traceRays(self: *Self, ray_gen_shader: *graphics.types.Shader, width: u32, height: u32) !void {
        if (self.ray_tracing) |*rt| {
            try rt.traceRays(ray_gen_shader, width, height);
        } else {
            return error.RayTracingNotSupported;
        }
    }
};

/// Ray tracing context for hardware-accelerated ray tracing
pub const RayTracingContext = struct {
    allocator: std.mem.Allocator,
    backend: *graphics.backend_manager.BackendInterface,

    // Acceleration structures
    top_level_as: ?*anyopaque = null,
    bottom_level_as: std.array_list.Managed(*anyopaque),

    // Ray tracing pipeline
    rt_pipeline: ?*graphics.types.Pipeline = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface) !Self {
        return Self{
            .allocator = allocator,
            .backend = backend,
            .bottom_level_as = std.array_list.Managed(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up acceleration structures
        for (self.bottom_level_as.items) |blas| {
            _ = blas; // TODO: Proper cleanup
        }
        self.bottom_level_as.deinit();

        if (self.top_level_as) |tlas| {
            _ = tlas; // TODO: Proper cleanup
        }

        if (self.rt_pipeline) |pipeline| {
            pipeline.deinit();
        }
    }

    /// Build bottom-level acceleration structure for geometry
    pub fn buildBLAS(self: *Self, vertices: []const math.Vec3, indices: []const u32) !*anyopaque {
        // Create geometry description for BLAS
        const geometry_info = try self.backend.vtable.create_rt_geometry(
            self.backend.impl_data,
            .{
                .vertex_data = vertices.ptr,
                .vertex_count = @intCast(vertices.len),
                .vertex_stride = @sizeOf(math.Vec3),
                .index_data = indices.ptr,
                .index_count = @intCast(indices.len),
            },
        );

        // Build BLAS using backend-specific API
        const blas = try self.backend.vtable.build_blas(
            self.backend.impl_data,
            geometry_info,
            .{ .allow_update = false },
        );

        // Store BLAS for cleanup
        try self.bottom_level_as.append(blas);

        return blas;
    }

    /// Build top-level acceleration structure for instances
    pub fn buildTLAS(self: *Self, instances: []const RTInstance) !void {
        // Create instance buffer with transforms and BLAS references
        var instance_data = try self.allocator.alloc(graphics.types.RTInstanceData, instances.len);
        defer self.allocator.free(instance_data);

        for (instances, 0..) |instance, i| {
            instance_data[i] = .{
                .transform = instance.transform,
                .instance_id = instance.instance_id,
                .mask = instance.mask,
                .blas = instance.blas,
            };
        }

        // Build TLAS using backend-specific API
        if (self.top_level_as) |old_tlas| {
            self.backend.vtable.destroy_tlas(self.backend.impl_data, old_tlas);
        }

        self.top_level_as = try self.backend.vtable.build_tlas(
            self.backend.impl_data,
            instance_data.ptr,
            @intCast(instance_data.len),
            .{ .allow_update = true },
        );
    }

    /// Create ray tracing pipeline
    pub fn createRTPipeline(self: *Self, desc: RTPipelineDesc) !*graphics.types.Pipeline {
        // Create ray tracing pipeline configuration
        const pipeline_info = graphics.types.RTPipelineInfo{
            .ray_gen_shader = desc.ray_gen_shader,
            .miss_shaders = desc.miss_shaders,
            .hit_groups = desc.hit_groups,
            .max_recursion_depth = desc.max_recursion_depth,
            .pipeline_layout = null, // Will be created by backend
        };

        // Create the pipeline using backend-specific API
        const pipeline = try self.backend.vtable.create_rt_pipeline(
            self.backend.impl_data,
            pipeline_info,
        );

        // Store reference to the created pipeline
        if (self.rt_pipeline) |old_pipeline| {
            old_pipeline.deinit();
        }
        self.rt_pipeline = pipeline;

        return pipeline;
    }

    /// Trace rays using the current pipeline
    pub fn traceRays(self: *Self, ray_gen_shader: *graphics.types.Shader, width: u32, height: u32) !void {
        if (self.rt_pipeline == null) {
            return error.NoPipelineActive;
        }

        // Set up shader binding table
        const sbt = try self.backend.vtable.create_shader_binding_table(
            self.backend.impl_data,
            self.rt_pipeline.?,
            .{
                .ray_gen_shader = ray_gen_shader,
                .miss_shaders = &.{},
                .hit_groups = &.{},
            },
        );
        defer self.backend.vtable.destroy_shader_binding_table(self.backend.impl_data, sbt);

        // Dispatch ray tracing work
        try self.backend.vtable.cmd_trace_rays(
            self.backend.impl_data,
            .{
                .pipeline = self.rt_pipeline.?,
                .sbt = sbt,
                .width = width,
                .height = height,
                .depth = 1,
            },
        );
    }
};

/// Mesh shader context for modern geometry pipeline
pub const MeshShaderContext = struct {
    allocator: std.mem.Allocator,
    backend: *graphics.backend_manager.BackendInterface,

    // Mesh shader pipelines
    mesh_pipeline: ?*graphics.types.Pipeline = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface) !Self {
        return Self{
            .allocator = allocator,
            .backend = backend,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.mesh_pipeline) |pipeline| {
            pipeline.deinit();
        }
    }

    /// Create mesh shader pipeline
    pub fn createMeshPipeline(self: *Self, desc: MeshPipelineDesc) !*graphics.types.Pipeline {
        // Create mesh shader pipeline configuration
        const pipeline_info = graphics.types.MeshPipelineInfo{
            .task_shader = desc.task_shader,
            .mesh_shader = desc.mesh_shader,
            .fragment_shader = desc.fragment_shader,
            .pipeline_layout = null, // Will be created by backend
        };

        // Create the pipeline using backend-specific API
        const pipeline = try self.backend.vtable.create_mesh_pipeline(
            self.backend.impl_data,
            pipeline_info,
        );

        // Store reference to the created pipeline
        if (self.mesh_pipeline) |old_pipeline| {
            old_pipeline.deinit();
        }
        self.mesh_pipeline = pipeline;

        return pipeline;
    }

    /// Render meshlets using mesh shaders
    pub fn renderMeshlets(self: *Self, meshlets: []const Meshlet) !void {
        if (self.mesh_pipeline == null) {
            return error.NoPipelineActive;
        }

        // Create meshlet buffer
        const meshlet_buffer = try self.backend.vtable.create_buffer(
            self.backend.impl_data,
            .{
                .size = meshlets.len * @sizeOf(Meshlet),
                .usage = .{ .storage = true, .transfer_dst = true },
                .memory = .device,
            },
        );
        defer meshlet_buffer.deinit();

        // Upload meshlet data
        try self.backend.vtable.update_buffer(
            self.backend.impl_data,
            meshlet_buffer,
            0,
            std.mem.sliceAsBytes(meshlets),
        );

        // Bind pipeline and meshlet buffer
        try self.backend.vtable.cmd_bind_pipeline(
            self.backend.impl_data,
            self.mesh_pipeline.?,
        );

        try self.backend.vtable.cmd_bind_storage_buffer(
            self.backend.impl_data,
            0, // binding
            meshlet_buffer,
        );

        // Draw meshlets
        const workgroup_size = 32;
        const num_workgroups = (meshlets.len + workgroup_size - 1) / workgroup_size;

        try self.backend.vtable.cmd_draw_mesh_tasks(
            self.backend.impl_data,
            @intCast(num_workgroups),
            1,
            1,
        );
    }
};

/// Compute shader context for general-purpose GPU computing
pub const ComputeContext = struct {
    allocator: std.mem.Allocator,
    backend: *graphics.backend_manager.BackendInterface,

    // Compute resources
    compute_queue: ?*anyopaque = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface) !Self {
        return Self{
            .allocator = allocator,
            .backend = backend,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // TODO: Cleanup compute resources
    }

    /// Dispatch compute shader work
    pub fn dispatch(self: *Self, shader: *graphics.types.Shader, groups_x: u32, groups_y: u32, groups_z: u32) !void {
        // Create compute pipeline if not already created
        const pipeline = try self.backend.vtable.create_compute_pipeline(
            self.backend.impl_data,
            .{
                .shader = shader,
                .pipeline_layout = null, // Will be created by backend
            },
        );
        defer pipeline.deinit();

        // Bind compute pipeline
        try self.backend.vtable.cmd_bind_pipeline(
            self.backend.impl_data,
            pipeline,
        );

        // Insert memory barrier before dispatch
        try self.backend.vtable.cmd_pipeline_barrier(
            self.backend.impl_data,
            .{
                .src_stage = .{ .compute = true },
                .dst_stage = .{ .compute = true },
                .memory = .{ .compute = true },
            },
        );

        // Dispatch compute work
        try self.backend.vtable.cmd_dispatch(
            self.backend.impl_data,
            groups_x,
            groups_y,
            groups_z,
        );

        // Insert memory barrier after dispatch
        try self.backend.vtable.cmd_pipeline_barrier(
            self.backend.impl_data,
            .{
                .src_stage = .{ .compute = true },
                .dst_stage = .{ .compute = true },
                .memory = .{ .compute = true },
            },
        );
    }

    /// Create compute pipeline with automatic uniform management
    pub fn createComputePipeline(self: *Self, shader_source: []const u8, uniforms: anytype) !ComputePipeline(@TypeOf(uniforms)) {
        return ComputePipeline(@TypeOf(uniforms)).init(self.allocator, self.backend, shader_source, uniforms);
    }
};

/// Generic compute pipeline with typed uniforms (inspired by zig-renderkit)
pub fn ComputePipeline(comptime UniformType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        backend: *graphics.backend_manager.BackendInterface,
        pipeline: *graphics.types.Pipeline,
        uniform_buffer: *graphics.types.Buffer,
        uniforms: UniformType,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface, shader_source: []const u8, initial_uniforms: UniformType) !Self {
            _ = shader_source;

            // Create pipeline
            const pipeline = try allocator.create(graphics.types.Pipeline);
            pipeline.* = graphics.types.Pipeline.init(allocator);

            // Create uniform buffer
            const uniform_buffer = try allocator.create(graphics.types.Buffer);
            uniform_buffer.* = graphics.types.Buffer{
                .id = 0,
                .size = @sizeOf(UniformType),
                .usage = .uniform,
                .allocator = allocator,
            };

            return Self{
                .allocator = allocator,
                .backend = backend,
                .pipeline = pipeline,
                .uniform_buffer = uniform_buffer,
                .uniforms = initial_uniforms,
            };
        }

        pub fn deinit(self: *Self) void {
            self.pipeline.deinit();
            self.uniform_buffer.deinit();
            self.allocator.destroy(self.pipeline);
            self.allocator.destroy(self.uniform_buffer);
        }

        /// Update uniforms and dispatch compute work
        pub fn dispatchWithUniforms(self: *Self, groups_x: u32, groups_y: u32, groups_z: u32) !void {
            // Update uniform buffer with current uniform values
            const uniform_data = std.mem.asBytes(&self.uniforms);
            try self.backend.vtable.update_buffer(self.backend.impl_data, self.uniform_buffer, 0, uniform_data);

            // Dispatch compute work
            std.log.info("Dispatching compute with uniforms: {}x{}x{}", .{ groups_x, groups_y, groups_z });
        }
    };
}

// Supporting types and structures

pub const RTInstance = struct {
    transform: math.Mat4,
    blas: *anyopaque,
    instance_id: u32,
    mask: u8 = 0xFF,
};

pub const RTPipelineDesc = struct {
    ray_gen_shader: *graphics.types.Shader,
    miss_shaders: []const *graphics.types.Shader,
    hit_groups: []const RTHitGroup,
    max_recursion_depth: u32 = 1,
};

pub const RTHitGroup = struct {
    closest_hit_shader: ?*graphics.types.Shader = null,
    any_hit_shader: ?*graphics.types.Shader = null,
    intersection_shader: ?*graphics.types.Shader = null,
};

pub const MeshPipelineDesc = struct {
    task_shader: ?*graphics.types.Shader = null,
    mesh_shader: *graphics.types.Shader,
    fragment_shader: ?*graphics.types.Shader = null,
};

pub const Meshlet = struct {
    vertex_offset: u32,
    vertex_count: u32,
    triangle_offset: u32,
    triangle_count: u32,
    bounds: BoundingSphere,
};

pub const BoundingSphere = struct {
    center: math.Vec3,
    radius: f32,
};

// Feature detection functions

pub fn supportsRayTracing(backend_type: graphics.backend_manager.BackendType) bool {
    return switch (backend_type) {
        .vulkan => build_options.Graphics.vulkan_available and build_options.Features.enable_ray_tracing,
        .d3d12 => build_options.Graphics.d3d12_available and build_options.Features.enable_ray_tracing,
        else => false,
    };
}

pub fn supportsMeshShaders(backend_type: graphics.backend_manager.BackendType) bool {
    return switch (backend_type) {
        .vulkan => build_options.Graphics.vulkan_available and build_options.Features.enable_mesh_shaders,
        .d3d12 => build_options.Graphics.d3d12_available and build_options.Features.enable_mesh_shaders,
        else => false,
    };
}

pub fn supportsComputeShaders(backend_type: graphics.backend_manager.BackendType) bool {
    return switch (backend_type) {
        .vulkan, .d3d11, .d3d12, .metal, .webgpu => true,
        .opengl, .opengles => true, // Modern versions
        .software => false,
        .auto => true,
    };
}

// Example uniform structures (inspired by zig-renderkit's approach)

pub const PostProcessUniforms = struct {
    // Automatically aligned for GPU usage
    time: f32 = 0.0,
    resolution: [2]f32 = .{ 1920.0, 1080.0 },
    mouse: [2]f32 align(16) = .{ 0.0, 0.0 },

    // Color grading
    exposure: f32 = 1.0,
    gamma: f32 = 2.2,
    saturation: f32 = 1.0,
    contrast: f32 = 1.0,
};

pub const ParticleUniforms = struct {
    delta_time: f32 = 0.016,
    gravity: [3]f32 = .{ 0.0, -9.81, 0.0 },
    wind_force: [3]f32 align(16) = .{ 0.0, 0.0, 0.0 },

    particle_count: u32 = 1000,
    emit_rate: f32 = 60.0,
    life_time: f32 = 5.0,
    _padding: f32 = 0.0, // Explicit padding for alignment
};

// Advanced rendering utilities

/// Create a post-processing compute pipeline
pub fn createPostProcessPipeline(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface) !ComputePipeline(PostProcessUniforms) {
    const shader_source =
        \\#version 450
        \\layout(local_size_x = 16, local_size_y = 16) in;
        \\
        \\layout(binding = 0, rgba8) uniform writeonly image2D result_image;
        \\layout(binding = 1) uniform sampler2D input_texture;
        \\
        \\layout(binding = 2) uniform PostProcessUniforms {
        \\    float time;
        \\    vec2 resolution;
        \\    vec2 mouse;
        \\    float exposure;
        \\    float gamma;
        \\    float saturation;
        \\    float contrast;
        \\};
        \\
        \\void main() {
        \\    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
        \\    if (coord.x >= int(resolution.x) || coord.y >= int(resolution.y)) return;
        \\    
        \\    vec2 uv = vec2(coord) / resolution;
        \\    vec3 color = texture(input_texture, uv).rgb;
        \\    
        \\    // Apply post-processing effects
        \\    color *= exposure;
        \\    color = pow(color, vec3(1.0 / gamma));
        \\    
        \\    imageStore(result_image, coord, vec4(color, 1.0));
        \\}
    ;

    const compute_context = ComputeContext{
        .allocator = allocator,
        .backend = backend,
    };

    return try compute_context.createComputePipeline(shader_source, PostProcessUniforms{});
}
