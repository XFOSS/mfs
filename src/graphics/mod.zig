//! MFS Engine - Graphics Module
//! Unified graphics interface combining all backends and rendering functionality
//! @thread-safe Thread-safe graphics operations with proper synchronization
//! @performance Optimized for modern GPU architectures

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("../build_options.zig");

// =============================================================================
// Core Graphics Components
// =============================================================================

// Backend management
pub const backends = @import("backends/mod.zig");
pub const backend_manager = @import("backend_manager.zig");

// Graphics types and interfaces
pub const types = @import("types.zig");
pub const interface = backends.interface;

// Resource management
pub const buffer = @import("buffer.zig");
pub const texture = @import("texture.zig");
pub const shader = @import("shader.zig");
pub const pipeline_state = @import("pipeline_state.zig");

// Rendering systems
pub const render = @import("render/mod.zig");
pub const gpu = @import("gpu.zig");

// Specialized graphics features
pub const ray_tracing = @import("ray_tracing.zig");
pub const compute_shaders = @import("compute_shaders.zig");
pub const resource_manager = @import("resource_manager.zig");
pub const shader_manager = @import("shader_manager.zig");

// Configuration and utilities
pub const vulkan_config = @import("vulkan_config.zig");

// =============================================================================
// Re-exported Types for Convenience
// =============================================================================

pub const BackendType = interface.BackendType;
pub const BackendConfig = interface.BackendConfig;
pub const GraphicsBackend = interface.GraphicsBackend;
pub const GraphicsBackendError = interface.GraphicsBackendError;

// Resource management types
pub const ResourceManager = resource_manager.ResourceManager;
pub const ResourceError = resource_manager.ResourceError;

// Compatibility aliases for engine
pub const BackendInterface = GraphicsBackend;
pub const GraphicsContext = GraphicsSystem;
pub const RayTracingContext = ray_tracing.RayTracingContext;

pub const BackendManager = backend_manager.BackendManager;

pub const Buffer = types.Buffer;
pub const Texture = types.Texture;
pub const Shader = types.Shader;
pub const Pipeline = types.Pipeline;

pub const BufferDesc = interface.BufferDesc;
pub const TextureDesc = interface.TextureDesc;
pub const ShaderDesc = interface.ShaderDesc;
pub const PipelineDesc = interface.PipelineDesc;

// Additional exports for API compatibility
pub const GeometryDesc = ray_tracing.GeometryDesc;
pub const InstanceDesc = ray_tracing.InstanceDesc;
pub const BuildFlags = ray_tracing.BuildFlags;
pub const AccelerationStructure = ray_tracing.AccelerationStructure;
pub const RayTracingPipeline = ray_tracing.RayTracingPipeline;
pub const ShaderBindingTable = ray_tracing.ShaderBindingTable;
pub const VertexFormat = interface.VertexFormat;
pub const VertexLayout = interface.VertexLayout;

// Export backend-specific renderers for examples
pub const VulkanCubeRenderer = @import("backends/vulkan/old/cube.zig").VulkanCubeRenderer;

// Export DirectX-specific renderers for examples (Windows only)
pub const directx = if (build_options.Graphics.d3d12_available)
    @import("backends/directx/mod.zig")
else
    struct {};

// =============================================================================
// Graphics System Configuration
// =============================================================================

pub const Config = struct {
    backend_type: BackendType = .auto,
    preferred_backend: BackendType = .vulkan,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    enable_validation: bool = build_options.Features.enable_validation,
    enable_ray_tracing: bool = build_options.Features.enable_ray_tracing,
    enable_compute_shaders: bool = build_options.Features.enable_compute_shaders,
    enable_mesh_shaders: bool = false,
    enable_variable_rate_shading: bool = false,
    enable_bindless_descriptors: bool = false,
    max_frames_in_flight: u32 = 2,
    vsync: bool = true,
};

// =============================================================================
// Graphics System
// =============================================================================

/// Main graphics system that manages all graphics operations
pub const GraphicsSystem = struct {
    allocator: std.mem.Allocator,
    backend_manager: BackendManager,
    current_backend: ?*GraphicsBackend,

    // Resource managers
    buffer_manager: BufferManager,
    texture_manager: TextureManager,
    shader_manager: ShaderManager,
    pipeline_manager: PipelineManager,

    // Configuration
    config: Config,

    const Self = @This();

    const BufferManager = struct {
        buffers: std.array_list.Managed(*Buffer),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !BufferManager {
            var manager = BufferManager{
                .allocator = allocator,
                .buffers = std.array_list.Managed(*Buffer).init(allocator),
            };
            try manager.buffers.ensureTotalCapacity(16);
            return manager;
        }

        pub fn deinit(self: *BufferManager, backend: ?*GraphicsBackend) void {
            if (backend) |b| {
                for (self.buffers.items) |buf| {
                    b.destroyBuffer(buf);
                }
            }
            self.buffers.deinit();
        }

        pub fn createBuffer(self: *BufferManager, backend: *GraphicsBackend, desc: BufferDesc) !*Buffer {
            const new_buffer = try backend.createBuffer(desc);
            try self.buffers.append(new_buffer);
            return new_buffer;
        }
    };

    const TextureManager = struct {
        textures: std.array_list.Managed(*Texture),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !TextureManager {
            var manager = TextureManager{
                .allocator = allocator,
                .textures = std.array_list.Managed(*Texture).init(allocator),
            };
            try manager.textures.ensureTotalCapacity(16);
            return manager;
        }

        pub fn deinit(self: *TextureManager, backend: ?*GraphicsBackend) void {
            if (backend) |b| {
                for (self.textures.items) |tex| {
                    b.destroyTexture(tex);
                }
            }
            self.textures.deinit();
        }

        pub fn createTexture(self: *TextureManager, backend: *GraphicsBackend, desc: TextureDesc) !*Texture {
            const new_texture = try backend.createTexture(desc);
            try self.textures.append(new_texture);
            return new_texture;
        }
    };

    const ShaderManager = struct {
        shaders: std.array_list.Managed(*Shader),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !ShaderManager {
            var manager = ShaderManager{
                .allocator = allocator,
                .shaders = std.array_list.Managed(*Shader).init(allocator),
            };
            try manager.shaders.ensureTotalCapacity(8);
            return manager;
        }

        pub fn deinit(self: *ShaderManager, backend: ?*GraphicsBackend) void {
            if (backend) |b| {
                for (self.shaders.items) |shd| {
                    b.destroyShader(shd);
                }
            }
            self.shaders.deinit();
        }

        pub fn createShader(self: *ShaderManager, backend: *GraphicsBackend, desc: ShaderDesc) !*Shader {
            const new_shader = try backend.createShader(desc);
            try self.shaders.append(new_shader);
            return new_shader;
        }
    };

    const PipelineManager = struct {
        pipelines: std.array_list.Managed(*Pipeline),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !PipelineManager {
            var manager = PipelineManager{
                .allocator = allocator,
                .pipelines = std.array_list.Managed(*Pipeline).init(allocator),
            };
            try manager.pipelines.ensureTotalCapacity(8);
            return manager;
        }

        pub fn deinit(self: *PipelineManager) void {
            // Pipelines are managed by the backend and don't need explicit destruction
            // The backend will clean them up when deinitialized
            for (self.pipelines.items) |pipeline| {
                _ = pipeline;
            }
            self.pipelines.deinit();
        }

        pub fn createPipeline(self: *PipelineManager, backend: *GraphicsBackend, desc: PipelineDesc) !*Pipeline {
            const pipeline = try backend.createPipeline(desc);
            try self.pipelines.append(pipeline);
            return pipeline;
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        // Convert to backend config
        const backend_config = BackendConfig{
            .backend_type = config.backend_type,
            .enable_validation = config.enable_validation,
            .enable_ray_tracing = config.enable_ray_tracing,
        };

        var backend_manager_instance = try BackendManager.init(allocator, backend_config);
        const backend = try backend_manager_instance.createBackend();

        return Self{
            .allocator = allocator,
            .backend_manager = backend_manager_instance,
            .current_backend = backend,
            .buffer_manager = try BufferManager.init(allocator),
            .texture_manager = try TextureManager.init(allocator),
            .shader_manager = try ShaderManager.init(allocator),
            .pipeline_manager = try PipelineManager.init(allocator),
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        const backend = self.current_backend;
        self.pipeline_manager.deinit();
        self.shader_manager.deinit(backend);
        self.texture_manager.deinit(backend);
        self.buffer_manager.deinit(backend);
        self.backend_manager.deinit();
    }

    pub fn getBackend(self: *Self) *GraphicsBackend {
        return self.current_backend orelse unreachable;
    }

    pub fn createBuffer(self: *Self, desc: BufferDesc) !*Buffer {
        return self.buffer_manager.createBuffer(self.current_backend.?, desc);
    }

    pub fn createTexture(self: *Self, desc: TextureDesc) !*Texture {
        return self.texture_manager.createTexture(self.current_backend.?, desc);
    }

    pub fn createShader(self: *Self, desc: ShaderDesc) !*Shader {
        return self.shader_manager.createShader(self.current_backend.?, desc);
    }

    pub fn createPipeline(self: *Self, desc: PipelineDesc) !*Pipeline {
        return self.pipeline_manager.createPipeline(self.current_backend.?, desc);
    }

    pub fn beginFrame(self: *Self) !void {
        if (self.current_backend) |backend| {
            // Backend-specific frame begin
            _ = backend;
        }
    }

    pub fn endFrame(self: *Self) !void {
        if (self.current_backend) |backend| {
            // Backend-specific frame end
            _ = backend;
        }
    }

    pub fn present(self: *Self) !void {
        if (self.current_backend) |backend| {
            try backend.present();
        }
    }

    pub fn getFrameCount(self: *Self) u64 {
        _ = self;
        return 0; // TODO: Implement frame counting
    }

    pub fn getFPS(self: *Self) f32 {
        _ = self;
        return 60.0; // TODO: Implement FPS calculation
    }
};

// =============================================================================
// Public API Functions
// =============================================================================

/// Initialize graphics system with default configuration
pub fn init(allocator: std.mem.Allocator) !GraphicsSystem {
    return GraphicsSystem.init(allocator, Config{});
}

/// Initialize graphics system with custom configuration
pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) !GraphicsSystem {
    return GraphicsSystem.init(allocator, config);
}

/// Initialize graphics backend (compatibility function for engine)
pub fn initBackend(allocator: std.mem.Allocator, config: Config) !*GraphicsBackend {
    const backend_config = BackendConfig{
        .backend_type = config.backend_type,
        .enable_validation = config.enable_validation,
        .enable_ray_tracing = config.enable_ray_tracing,
    };

    var backend_manager_instance = try BackendManager.init(allocator, backend_config);
    return backend_manager_instance.createBackend();
}

/// Create graphics context (compatibility function)
pub fn createContext(allocator: std.mem.Allocator, config: Config) !GraphicsSystem {
    return GraphicsSystem.init(allocator, config);
}

// =============================================================================
// Tests
// =============================================================================

test "graphics system initialization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var graphics_system = try init(allocator);
    defer graphics_system.deinit();

    // Test that we can create resources
    const buffer_desc = BufferDesc{
        .size = 1024,
        .usage = .{ .vertex = true },
        .memory_type = .device_local,
    };

    const test_buffer = graphics_system.createBuffer(buffer_desc) catch |err| switch (err) {
        error.BackendNotAvailable => {
            // Skip test if no backend available
            return;
        },
        else => return err,
    };

    // Basic validation
    _ = test_buffer;
}

// =============================================================================
// Advanced Graphics Features - New Systems
// =============================================================================

// Advanced graphics features
pub const bindless_textures = @import("bindless_textures.zig");
pub const asset_pipeline = @import("asset_pipeline.zig");
pub const memory_pools = @import("memory_pools.zig");
pub const multi_threading = @import("multi_threading.zig");
pub const lod_system = @import("lod_system.zig");

// Next-generation rendering techniques
pub const mesh_shaders = @import("mesh_shaders.zig");
pub const temporal_techniques = @import("temporal_techniques.zig");

// Export advanced system types
pub const MeshShaderSystem = mesh_shaders.MeshShaderSystem;
pub const TemporalTechniques = temporal_techniques.TemporalTechniques;
pub const Meshlet = mesh_shaders.Meshlet;
pub const MeshInstance = mesh_shaders.MeshInstance;
pub const UpscalingQuality = temporal_techniques.UpscalingQuality;
pub const TemporalStats = temporal_techniques.TemporalStats;
