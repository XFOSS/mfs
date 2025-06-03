const std = @import("std");
const Allocator = std.mem.Allocator;
const vulkan_backend = @import("vulkan_backend.zig");
const interface = @import("interface.zig");
const builtin = @import("builtin");
// Import shaders from src directory
const shaders = @import("src/shaders/shaders.zig");
// Import MLIR for shader compilation and optimization
const mlir = @import("src/mlir/mlir.zig");
// Import GUI and UI modules
const gui = @import("gui/gui.zig");
const ui = @import("ui/ui.zig");
const graphics = @import("graphics/graphics.zig");

// Backend type selection
pub const BackendType = enum {
    vulkan,
    opengl,
    metal,
    directx,
    // Add more backends as needed
};

/// GPU context that holds the currently active graphics backend
pub const GPU = struct {
    allocator: Allocator,
    backend_type: BackendType,
    backend: *BackendInterface,
    shader_cache: shaders.ShaderCache,
    mlir_context: mlir.Context, // MLIR context for shader compilation
    gui_context: ?gui.GuiContext = null,
    ui_system: ?ui.UiSystem = null,
    graphics_renderer: ?graphics.Renderer = null,

    /// Initialize the GPU with the selected backend
    pub fn init(allocator: Allocator, backend_type: BackendType) !GPU {
        const backend = switch (backend_type) {
            .vulkan => try vulkan_backend.create(allocator),
            .opengl, .metal, .directx => return error.BackendNotImplemented,
            // Add more backends here
        };

        const shader_cache = try shaders.ShaderCache.init(allocator);
        const mlir_context = try mlir.Context.init(allocator);

        return GPU{
            .allocator = allocator,
            .backend_type = backend_type,
            .backend = backend,
            .shader_cache = shader_cache,
            .mlir_context = mlir_context,
        };
    }

    pub fn deinit(self: *GPU) void {
        // Clean up graphics, GUI and UI if initialized
        if (self.graphics_renderer) |*renderer| {
            renderer.deinit();
        }
        if (self.gui_context) |*context| {
            context.deinit();
        }
        if (self.ui_system) |*system| {
            system.deinit();
        }

        self.mlir_context.deinit();
        self.shader_cache.deinit();
        self.backend.destroy();
        self.allocator.destroy(self.backend);
    }

    // Shader management methods with MLIR support
    pub fn loadShader(self: *GPU, path: []const u8, shader_type: shaders.ShaderType) !shaders.ShaderId {
        // Use MLIR for loading and optimizing the shader
        const mlir_module = try self.mlir_context.parseShaderFile(path);
        try self.optimizeShaderModule(&mlir_module, shader_type);
        return self.shader_cache.loadShaderFromMlir(mlir_module, shader_type, self.backend_type);
    }

    pub fn compileShaderSource(self: *GPU, source: []const u8, shader_type: shaders.ShaderType) !shaders.ShaderId {
        // Use MLIR pipeline for compiling and optimizing shader source
        const mlir_module = try self.mlir_context.parseShaderSource(source, shader_type);
        try self.optimizeShaderModule(&mlir_module, shader_type);
        return self.shader_cache.compileFromMlir(mlir_module, shader_type, self.backend_type);
    }

    // Apply MLIR optimization passes to shader module
    pub fn optimizeShaderModule(self: *GPU, module: *mlir.Module, shader_type: shaders.ShaderType) !void {
        var pipeline = try mlir.OptimizationPipeline.init(self.allocator, self.backend_type);
        defer pipeline.deinit();

        // Add common optimizations
        try pipeline.addPass(mlir.Pass.inlining);
        try pipeline.addPass(mlir.Pass.constantFolding);
        try pipeline.addPass(mlir.Pass.loopUnrolling);

        // Add backend-specific optimizations
        switch (self.backend_type) {
            .vulkan => try pipeline.addPass(mlir.Pass.vulkanSpecific),
            .opengl => try pipeline.addPass(mlir.Pass.openglSpecific),
            .metal => try pipeline.addPass(mlir.Pass.metalSpecific),
            .directx => try pipeline.addPass(mlir.Pass.directxSpecific),
        }

        // Execute the optimization pipeline
        try pipeline.run(module);
    }

    pub fn bindShader(self: *GPU, id: shaders.ShaderId) !void {
        return self.backend.bindShader(self.shader_cache.getShader(id) orelse return error.ShaderNotFound);
    }

    // Graphics rendering methods
    pub fn initGraphics(self: *GPU, config: graphics.RendererConfig) !void {
        if (self.graphics_renderer != null) return error.GraphicsAlreadyInitialized;
        self.graphics_renderer = try graphics.Renderer.init(self.allocator, self.backend, config);
    }

    pub fn drawPrimitive(self: *GPU, primitive: graphics.Primitive) !void {
        if (self.graphics_renderer) |*renderer| {
            try renderer.drawPrimitive(primitive);
        } else return error.GraphicsNotInitialized;
    }

    // GUI management methods
    pub fn initGui(self: *GPU, config: gui.GuiConfig) !void {
        if (self.gui_context != null) return error.GuiAlreadyInitialized;
        self.gui_context = try gui.GuiContext.init(self.allocator, self.backend, config);
    }

    pub fn beginGuiFrame(self: *GPU) !void {
        if (self.gui_context) |*context| {
            try context.beginFrame();
        } else return error.GuiNotInitialized;
    }

    pub fn endGuiFrame(self: *GPU) !void {
        if (self.gui_context) |*context| {
            try context.endFrame();
        } else return error.GuiNotInitialized;
    }

    // UI management methods
    pub fn initUi(self: *GPU, config: ui.UiConfig) !void {
        if (self.ui_system != null) return error.UiAlreadyInitialized;
        self.ui_system = try ui.UiSystem.init(self.allocator, self.backend, config);
    }

    pub fn createUiElement(self: *GPU, element_type: ui.ElementType, properties: ui.ElementProperties) !ui.ElementId {
        if (self.ui_system) |*system| {
            return system.createElement(element_type, properties);
        } else return error.UiNotInitialized;
    }

    pub fn renderUi(self: *GPU) !void {
        if (self.ui_system) |*system| {
            try system.render();
        } else return error.UiNotInitialized;
    }

    // Forward interface methods
    pub usingnamespace interface.forwardBackendInterface(GPU);
};

/// Common interface for all graphics backends
pub const BackendInterface = interface.GraphicsInterface;

/// Re-export shader types for easier access
pub const ShaderType = shaders.ShaderType;
pub const ShaderId = shaders.ShaderId;
pub const Shader = shaders.Shader;

// Re-export graphics, GUI and UI types for easier access
pub const GraphicsRenderer = graphics.Renderer;
pub const GraphicsPrimitive = graphics.Primitive;
pub const GuiContext = gui.GuiContext;
pub const UiSystem = ui.UiSystem;
pub const UiElementType = ui.ElementType;

/// Utility to compile Zig shader code using MLIR and SPIR-V
pub const ShaderCompiler = struct {
    pub fn compileGlsl(comptime source: []const u8, comptime shader_type: ShaderType) []const u32 {
        // Use MLIR pipeline internally for better optimization
        return shaders.compileGlslToSpirv(source, shader_type);
    }

    pub fn loadShaderFile(comptime path: []const u8) []const u8 {
        return @embedFile(path);
    }

    pub fn compileWithMlir(comptime source: []const u8, comptime shader_type: ShaderType, comptime target: BackendType) []const u8 {
        // Compile through MLIR pipeline with advanced optimizations
        return mlir.compileShader(source, shader_type, target);
    }

    pub fn optimizeShader(comptime source: []const u8, comptime shader_type: ShaderType, comptime optimization_level: u8) []const u8 {
        // Apply MLIR optimizations at compile time
        return mlir.optimizeShader(source, shader_type, optimization_level);
    }
};
