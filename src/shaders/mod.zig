//! MFS Engine - Shaders Module
//! Shader compilation, management, and node-based shader editing system
//! Supports multiple shader languages and cross-compilation
//! @thread-safe Shader operations can be multi-threaded for compilation
//! @performance Optimized for fast shader compilation and hot-reload

const std = @import("std");
const builtin = @import("builtin");

// Core shader components
pub const shader_compiler = @import("shader_compiler.zig");
pub const node_shader_editor = @import("node_shader_editor.zig");
pub const dynamic_shader_compiler = @import("dynamic_shader_compiler.zig");

// Re-export main shader types
pub const ShaderCompiler = shader_compiler.ShaderCompiler;
pub const NodeShaderEditor = node_shader_editor.NodeShaderEditor;
pub const DynamicShaderCompiler = dynamic_shader_compiler.DynamicShaderCompiler;

// Shader languages
pub const ShaderLanguage = enum {
    glsl,
    hlsl,
    spirv,
    metal,
    wgsl,

    pub fn getName(self: ShaderLanguage) []const u8 {
        return switch (self) {
            .glsl => "GLSL",
            .hlsl => "HLSL",
            .spirv => "SPIR-V",
            .metal => "Metal Shading Language",
            .wgsl => "WGSL",
        };
    }

    pub fn getFileExtension(self: ShaderLanguage) []const u8 {
        return switch (self) {
            .glsl => ".glsl",
            .hlsl => ".hlsl",
            .spirv => ".spv",
            .metal => ".metal",
            .wgsl => ".wgsl",
        };
    }
};

// Shader types
pub const ShaderType = enum {
    vertex,
    fragment,
    geometry,
    tessellation_control,
    tessellation_evaluation,
    compute,

    pub fn getName(self: ShaderType) []const u8 {
        return switch (self) {
            .vertex => "Vertex",
            .fragment => "Fragment",
            .geometry => "Geometry",
            .tessellation_control => "Tessellation Control",
            .tessellation_evaluation => "Tessellation Evaluation",
            .compute => "Compute",
        };
    }

    pub fn getFileExtension(self: ShaderType) []const u8 {
        return switch (self) {
            .vertex => ".vert",
            .fragment => ".frag",
            .geometry => ".geom",
            .tessellation_control => ".tesc",
            .tessellation_evaluation => ".tese",
            .compute => ".comp",
        };
    }
};

// Shader compilation targets
pub const CompilationTarget = enum {
    vulkan,
    d3d11,
    d3d12,
    metal,
    opengl,
    opengles,
    webgpu,

    pub fn getShaderLanguage(self: CompilationTarget) ShaderLanguage {
        return switch (self) {
            .vulkan => .spirv,
            .d3d11, .d3d12 => .hlsl,
            .metal => .metal,
            .opengl, .opengles => .glsl,
            .webgpu => .wgsl,
        };
    }
};

// Shader compilation configuration
pub const ShaderCompilationConfig = struct {
    target: CompilationTarget,
    optimization_level: OptimizationLevel = .default,
    enable_debug_info: bool = builtin.mode == .Debug,
    enable_validation: bool = builtin.mode == .Debug,
    include_directories: []const []const u8 = &.{},
    defines: []const []const u8 = &.{},

    pub const OptimizationLevel = enum {
        none,
        default,
        performance,
        size,
    };

    pub fn validate(self: ShaderCompilationConfig) !void {
        // Validation logic would go here
        _ = self;
    }
};

// Shader system configuration
pub const ShaderSystemConfig = struct {
    enable_hot_reload: bool = builtin.mode == .Debug,
    enable_caching: bool = true,
    cache_directory: []const u8 = "shader_cache",
    max_compilation_threads: u32 = 0, // 0 = auto-detect
    enable_node_editor: bool = builtin.mode == .Debug,

    pub fn validate(self: ShaderSystemConfig) !void {
        if (self.cache_directory.len == 0) {
            return error.InvalidParameter;
        }
    }
};

// Shader manager
pub const ShaderManager = struct {
    allocator: std.mem.Allocator,
    config: ShaderSystemConfig,
    compiler: *ShaderCompiler,
    node_editor: ?*NodeShaderEditor,
    dynamic_compiler: ?*DynamicShaderCompiler,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ShaderSystemConfig) !*Self {
        try config.validate();

        const manager = try allocator.create(Self);
        manager.* = Self{
            .allocator = allocator,
            .config = config,
            .compiler = try ShaderCompiler.init(allocator),
            .node_editor = if (config.enable_node_editor) try NodeShaderEditor.init(allocator) else null,
            .dynamic_compiler = if (config.enable_hot_reload) try DynamicShaderCompiler.init(allocator) else null,
        };

        // Create cache directory
        if (config.enable_caching) {
            try std.fs.cwd().makePath(config.cache_directory);
        }

        return manager;
    }

    pub fn deinit(self: *Self) void {
        if (self.dynamic_compiler) |compiler| {
            compiler.deinit();
        }
        if (self.node_editor) |editor| {
            editor.deinit();
        }
        self.compiler.deinit();
        self.allocator.destroy(self);
    }

    pub fn compileShader(
        self: *Self,
        source_path: []const u8,
        shader_type: ShaderType,
        compilation_config: ShaderCompilationConfig,
    ) ![]const u8 {
        return try self.compiler.compile(source_path, shader_type, compilation_config);
    }

    pub fn compileShaderFromSource(
        self: *Self,
        source: []const u8,
        shader_type: ShaderType,
        compilation_config: ShaderCompilationConfig,
    ) ![]const u8 {
        return try self.compiler.compileFromSource(source, shader_type, compilation_config);
    }

    pub fn getNodeEditor(self: *Self) ?*NodeShaderEditor {
        return self.node_editor;
    }

    pub fn enableHotReload(self: *Self, shader_path: []const u8) !void {
        if (self.dynamic_compiler) |compiler| {
            try compiler.watchFile(shader_path);
        }
    }
};

// Initialize shader system
pub fn init(allocator: std.mem.Allocator, config: ShaderSystemConfig) !*ShaderManager {
    return try ShaderManager.init(allocator, config);
}

// Cleanup shader system
pub fn deinit(manager: *ShaderManager) void {
    manager.deinit();
}

// Get supported shader languages for a compilation target
pub fn getSupportedLanguages(target: CompilationTarget) []const ShaderLanguage {
    return switch (target) {
        .vulkan => &[_]ShaderLanguage{ .spirv, .glsl },
        .d3d11, .d3d12 => &[_]ShaderLanguage{.hlsl},
        .metal => &[_]ShaderLanguage{.metal},
        .opengl, .opengles => &[_]ShaderLanguage{.glsl},
        .webgpu => &[_]ShaderLanguage{.wgsl},
    };
}

test "shaders module" {
    std.testing.refAllDecls(@This());
}
