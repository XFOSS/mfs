//! MFS Engine - Development Tools
//! Visual editors, debugging tools, and development utilities
//! Provides comprehensive tooling for game development

const std = @import("std");
const builtin = @import("builtin");

// Re-export tool modules
pub const visual_editor = @import("visual_editor.zig");
// Asset processor is in the root tools directory - commented out due to module path restrictions
// pub const asset_processor = @import("../../tools/asset_processor/asset_processor.zig");
pub const profiler = @import("profiler.zig");
pub const debugger = @import("debugger.zig");
pub const asset_browser = @import("asset_browser.zig");
pub const property_inspector = @import("property_inspector.zig");
pub const capability_checker = @import("capability_checker.zig");
pub const project_manager = @import("project_manager.zig");

/// Tools Manager - coordinates all development tools
pub const ToolsManager = struct {
    allocator: std.mem.Allocator,

    // Tool instances
    visual_editor: ?visual_editor.VisualEditor = null,
    profiler: ?profiler.Profiler = null,
    debugger: ?debugger.Debugger = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.visual_editor) |*editor| {
            editor.deinit();
        }
        if (self.profiler) |*prof| {
            prof.deinit();
        }
        if (self.debugger) |*debug| {
            debug.deinit();
        }
    }

    /// Initialize the visual editor
    pub fn initVisualEditor(self: *Self) !void {
        if (self.visual_editor == null) {
            self.visual_editor = try visual_editor.VisualEditor.init(self.allocator);
            std.log.info("Visual Editor initialized", .{});
        }
    }

    /// Initialize the profiler
    pub fn initProfiler(self: *Self) !void {
        if (self.profiler == null) {
            self.profiler = try profiler.Profiler.init(self.allocator);
            std.log.info("Profiler initialized", .{});
        }
    }

    /// Initialize the debugger
    pub fn initDebugger(self: *Self) !void {
        if (self.debugger == null) {
            self.debugger = try debugger.Debugger.init(self.allocator);
            std.log.info("Debugger initialized", .{});
        }
    }

    /// Update all active tools
    pub fn update(self: *Self, delta_time: f32) !void {
        if (self.visual_editor) |*editor| {
            try editor.update(delta_time);
        }
        if (self.profiler) |*prof| {
            try prof.update(delta_time);
        }
        if (self.debugger) |*debug| {
            try debug.update(delta_time);
        }
    }

    /// Render all active tools
    pub fn render(self: *Self) !void {
        if (self.visual_editor) |*editor| {
            try editor.render();
        }
        if (self.profiler) |*prof| {
            try prof.render();
        }
        if (self.debugger) |*debug| {
            try debug.render();
        }
    }
};

// Tool types
pub const ToolType = enum {
    asset_processor,
    profiler_visualizer,
    capability_checker,
    shader_compiler,
    texture_converter,
    model_importer,

    pub fn getName(self: ToolType) []const u8 {
        return switch (self) {
            .asset_processor => "Asset Processor",
            .profiler_visualizer => "Profiler Visualizer",
            .capability_checker => "Capability Checker",
            .shader_compiler => "Shader Compiler",
            .texture_converter => "Texture Converter",
            .model_importer => "Model Importer",
        };
    }

    pub fn getDescription(self: ToolType) []const u8 {
        return switch (self) {
            .asset_processor => "Processes and optimizes game assets",
            .profiler_visualizer => "Visualizes profiling data and performance metrics",
            .capability_checker => "Checks system capabilities and hardware support",
            .shader_compiler => "Compiles shaders for different graphics backends",
            .texture_converter => "Converts and optimizes texture formats",
            .model_importer => "Imports 3D models and animations",
        };
    }
};

// Tool configuration
pub const ToolConfig = struct {
    enable_verbose_output: bool = false,
    enable_progress_reporting: bool = true,
    output_directory: []const u8 = "output",
    temp_directory: []const u8 = "temp",
    max_parallel_jobs: u32 = 0, // 0 = auto-detect

    pub fn validate(self: ToolConfig) !void {
        if (self.output_directory.len == 0) {
            return error.InvalidParameter;
        }
        if (self.temp_directory.len == 0) {
            return error.InvalidParameter;
        }
    }
};

// Tool interface
pub const Tool = struct {
    allocator: std.mem.Allocator,
    config: ToolConfig,
    tool_type: ToolType,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, tool_type: ToolType, config: ToolConfig) !*Self {
        try config.validate();

        const tool = try allocator.create(Self);
        tool.* = Self{
            .allocator = allocator,
            .config = config,
            .tool_type = tool_type,
        };

        return tool;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn run(self: *Self, args: []const []const u8) !void {
        switch (self.tool_type) {
            .capability_checker => try self.runCapabilityChecker(args),
            .asset_processor => try self.runAssetProcessor(args),
            .profiler_visualizer => try self.runProfilerVisualizer(args),
            .shader_compiler => try self.runShaderCompiler(args),
            .texture_converter => try self.runTextureConverter(args),
            .model_importer => try self.runModelImporter(args),
        }
    }

    fn runCapabilityChecker(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Placeholder implementation
        std.debug.print("Running capability checker...\n", .{});
    }

    fn runAssetProcessor(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Placeholder implementation
        std.debug.print("Running asset processor...\n", .{});
    }

    fn runProfilerVisualizer(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Placeholder implementation
        std.debug.print("Running profiler visualizer...\n", .{});
    }

    fn runShaderCompiler(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Placeholder implementation
        std.debug.print("Running shader compiler...\n", .{});
    }

    fn runTextureConverter(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Placeholder implementation
        std.debug.print("Running texture converter...\n", .{});
    }

    fn runModelImporter(self: *Self, args: []const []const u8) !void {
        _ = self;
        _ = args;
        // Placeholder implementation
        std.debug.print("Running model importer...\n", .{});
    }
};

// Initialize tools system
pub fn init(allocator: std.mem.Allocator, config: ToolConfig) !void {
    try config.validate();

    // Create output directories if they don't exist
    try std.fs.cwd().makePath(config.output_directory);
    try std.fs.cwd().makePath(config.temp_directory);

    _ = allocator; // Suppress unused parameter warning
}

// Create a tool instance
pub fn createTool(allocator: std.mem.Allocator, tool_type: ToolType, config: ToolConfig) !*Tool {
    return try Tool.init(allocator, tool_type, config);
}

// Get list of available tools
pub fn getAvailableTools() []const ToolType {
    return &[_]ToolType{
        .asset_processor,
        .profiler_visualizer,
        .capability_checker,
        .shader_compiler,
        .texture_converter,
        .model_importer,
    };
}

test "tools module" {
    std.testing.refAllDecls(@This());
}
