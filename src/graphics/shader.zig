const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu.zig");
const types = @import("types.zig");
const interface = @import("backends/interface.zig");

pub const ShaderError = error{
    CompilationFailed,
    LinkingFailed,
    InvalidShaderType,
    ShaderNotCompiled,
    OutOfMemory,
    IncludeResolutionFailed,
    PreprocessingFailed,
};

pub const ShaderPreprocessorFlags = packed struct {
    enable_includes: bool = true,
    enable_defines: bool = true,
    enable_conditionals: bool = true,
    allow_external_includes: bool = false,
    strip_comments: bool = true,
    _padding: u27 = 0,
};

pub const ShaderIncludeHandler = struct {
    context: ?*anyopaque = null,
    resolve_fn: ?*const fn (context: ?*anyopaque, path: []const u8) ?[]const u8 = null,
    free_fn: ?*const fn (context: ?*anyopaque, data: []const u8) void = null,

    pub fn resolve(self: *const ShaderIncludeHandler, path: []const u8) ?[]const u8 {
        if (self.resolve_fn) |resolver| {
            return resolver(self.context, path);
        }
        return null;
    }

    pub fn free(self: *const ShaderIncludeHandler, data: []const u8) void {
        if (self.free_fn) |free_func| {
            free_func(self.context, data);
        }
    }
};

pub const ShaderDefine = struct {
    name: []const u8,
    value: ?[]const u8 = null,
};

pub const ShaderCompileOptions = struct {
    include_handler: ?ShaderIncludeHandler = null,
    defines: ?[]const ShaderDefine = null,
    optimize_level: u8 = 0,
    preprocessor_flags: ShaderPreprocessorFlags = ShaderPreprocessorFlags{},
};

pub const ShaderProgram = struct {
    allocator: Allocator,
    vertex_shader: ?*gpu.Shader = null,
    fragment_shader: ?*gpu.Shader = null,
    geometry_shader: ?*gpu.Shader = null,
    compute_shader: ?*gpu.Shader = null,
    tesselation_control_shader: ?*gpu.Shader = null,
    tesselation_evaluation_shader: ?*gpu.Shader = null,
    pipeline: ?gpu.Pipeline = null,
    reflection_data: ReflectionData,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        var program = try allocator.create(Self);
        program.* = Self{
            .allocator = allocator,
            .reflection_data = ReflectionData.init(allocator),
        };
        return program;
    }

    pub fn deinit(self: *Self) void {
        if (self.vertex_shader) |shader| {
            shader.deinit();
        }
        if (self.fragment_shader) |shader| {
            shader.deinit();
        }
        if (self.geometry_shader) |shader| {
            shader.deinit();
        }
        if (self.compute_shader) |shader| {
            shader.deinit();
        }
        if (self.tesselation_control_shader) |shader| {
            shader.deinit();
        }
        if (self.tesselation_evaluation_shader) |shader| {
            shader.deinit();
        }
        if (self.pipeline) |*pipeline| {
            pipeline.deinit();
        }
        self.reflection_data.deinit();
        self.allocator.destroy(self);
    }

    pub fn addShader(self: *Self, shader_type: gpu.ShaderType, source: []const u8) !void {
        var shader = try gpu.createShader(shader_type, source);
        errdefer shader.deinit();

        switch (shader_type) {
            .vertex => {
                if (self.vertex_shader) |old_shader| {
                    old_shader.deinit();
                }
                self.vertex_shader = shader;
            },
            .fragment => {
                if (self.fragment_shader) |old_shader| {
                    old_shader.deinit();
                }
                self.fragment_shader = shader;
            },
            .compute => {
                if (self.compute_shader) |old_shader| {
                    old_shader.deinit();
                }
                self.compute_shader = shader;
            },
            .geometry => {
                if (self.geometry_shader) |old_shader| {
                    old_shader.deinit();
                }
                self.geometry_shader = shader;
            },
            .tessellation_control => {
                if (self.tesselation_control_shader) |old_shader| {
                    old_shader.deinit();
                }
                self.tesselation_control_shader = shader;
            },
            .tessellation_evaluation => {
                if (self.tesselation_evaluation_shader) |old_shader| {
                    old_shader.deinit();
                }
                self.tesselation_evaluation_shader = shader;
            },
        }
    }

    pub fn addShaderFromFile(self: *Self, shader_type: gpu.ShaderType, path: []const u8, options: ?ShaderCompileOptions) !void {
        const source = try self.loadShaderSource(path, options);
        defer self.allocator.free(source);

        try self.addShader(shader_type, source);
    }

    fn loadShaderSource(self: *Self, path: []const u8, options: ?ShaderCompileOptions) ![]const u8 {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const source = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        errdefer self.allocator.free(source);

        if (options) |opts| {
            if (opts.preprocessor_flags.enable_includes or
                opts.preprocessor_flags.enable_defines)
            {
                return self.preprocessShader(source, path, opts);
            }
        }

        return source;
    }

    fn preprocessShader(self: *Self, source: []const u8, base_path: []const u8, options: ShaderCompileOptions) ![]const u8 {
        var preprocessor = ShaderPreprocessor.init(self.allocator, options);
        defer preprocessor.deinit();

        return preprocessor.process(source, base_path);
    }

    pub fn createPipeline(self: *Self, options: gpu.PipelineOptions) !void {
        if (self.vertex_shader == null) {
            return ShaderError.ShaderNotCompiled;
        }

        var pipeline_options = options;
        pipeline_options.vertex_shader = self.vertex_shader.?;
        pipeline_options.fragment_shader = self.fragment_shader;

        self.pipeline = try gpu.createPipeline(pipeline_options);
    }

    pub fn bind(self: *Self, cmd: *gpu.CommandBuffer) !void {
        if (self.pipeline) |*pipeline| {
            try gpu.bindPipeline(cmd, pipeline);
        } else {
            return ShaderError.ShaderNotCompiled;
        }
    }
};

pub const ShaderPreprocessor = struct {
    allocator: Allocator,
    options: ShaderCompileOptions,
    include_stack: std.ArrayList([]const u8),
    defines: std.StringHashMap([]const u8),

    const Self = @This();

    pub fn init(allocator: Allocator, options: ShaderCompileOptions) Self {
        var preprocessor = Self{
            .allocator = allocator,
            .options = options,
            .include_stack = std.ArrayList([]const u8).init(allocator),
            .defines = std.StringHashMap([]const u8).init(allocator),
        };

        if (options.defines) |defs| {
            for (defs) |define| {
                preprocessor.defines.put(define.name, define.value orelse "") catch {};
            }
        }

        return preprocessor;
    }

    pub fn deinit(self: *Self) void {
        self.include_stack.deinit();

        var it = self.defines.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.*.len > 0) {
                self.allocator.free(entry.value_ptr.*);
            }
        }
        self.defines.deinit();
    }

    pub fn process(self: *Self, source: []const u8, base_path: []const u8) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        try self.include_stack.append(base_path);
        defer _ = self.include_stack.pop();

        var lines = std.mem.split(u8, source, "\n");
        var line_number: usize = 1;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (self.options.preprocessor_flags.strip_comments) {
                if (std.mem.indexOf(u8, trimmed, "//")) |comment_start| {
                    try output.appendSlice(trimmed[0..comment_start]);
                    try output.append('\n');
                    line_number += 1;
                    continue;
                }
            }

            if (self.options.preprocessor_flags.enable_includes and
                std.mem.startsWith(u8, trimmed, "#include"))
            {
                const include_path = self.parseIncludePath(trimmed);
                if (include_path) |path| {
                    const resolved_path = try self.resolveIncludePath(path);
                    defer self.allocator.free(resolved_path);

                    const include_content = try self.loadInclude(resolved_path);
                    defer {
                        if (self.options.include_handler) |handler| {
                            handler.free(include_content);
                        } else {
                            self.allocator.free(include_content);
                        }
                    }
                    try output.appendSlice(include_content);
                } else {
                    try output.appendSlice(line);
                }
            } else if (self.options.preprocessor_flags.enable_defines and
                std.mem.startsWith(u8, trimmed, "#define"))
            {
                try self.handleDefine(trimmed);
                try output.appendSlice(line);
            } else if (self.options.preprocessor_flags.enable_conditionals and
                (std.mem.startsWith(u8, trimmed, "#if") or
                    std.mem.startsWith(u8, trimmed, "#else") or
                    std.mem.startsWith(u8, trimmed, "#endif")))
            {
                // In a real implementation, we would handle preprocessor conditionals here
                try output.appendSlice(line);
            } else {
                if (self.options.preprocessor_flags.enable_defines) {
                    // Handle macro replacements
                    const processed_line = try self.replaceMacros(line);
                    try output.appendSlice(processed_line);
                    self.allocator.free(processed_line);
                } else {
                    try output.appendSlice(line);
                }
            }

            try output.append('\n');
            line_number += 1;
        }

        return output.toOwnedSlice();
    }

    fn parseIncludePath(self: *Self, line: []const u8) ?[]const u8 {
        _ = self;

        // Simple parsing of #include "path" or #include <path>
        var it = std.mem.tokenize(u8, line, " \t\r");
        _ = it.next(); // Skip #include

        if (it.next()) |path_with_quotes| {
            if ((path_with_quotes[0] == '"' and path_with_quotes[path_with_quotes.len - 1] == '"') or
                (path_with_quotes[0] == '<' and path_with_quotes[path_with_quotes.len - 1] == '>'))
            {
                return path_with_quotes[1 .. path_with_quotes.len - 1];
            }
        }

        return null;
    }

    fn resolveIncludePath(self: *Self, path: []const u8) ![]const u8 {
        const current_dir = std.fs.path.dirname(self.include_stack.items[self.include_stack.items.len - 1]) orelse ".";
        return std.fs.path.join(self.allocator, &[_][]const u8{ current_dir, path });
    }

    fn loadInclude(self: *Self, path: []const u8) ![]const u8 {
        // Try custom include handler first if available
        if (self.options.include_handler) |handler| {
            if (handler.resolve(path)) |content| {
                return content;
            }
        }

        // Fall back to regular file loading
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        return file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
    }

    fn handleDefine(self: *Self, line: []const u8) !void {
        var parts = std.mem.tokenize(u8, line, " \t\r");
        _ = parts.next(); // Skip #define

        const name = parts.next() orelse return;
        const value_start = std.mem.indexOf(u8, line, name) orelse return;
        const value = std.mem.trim(u8, line[value_start + name.len ..], " \t\r");

        const owned_value = try self.allocator.dupe(u8, value);

        try self.defines.put(name, owned_value);
    }

    fn replaceMacros(self: *Self, line: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var i: usize = 0;
        while (i < line.len) {
            // Simple macro replacement - in a real implementation this would be more sophisticated
            var found_macro = false;
            var it = self.defines.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                if (i + name.len <= line.len and std.mem.eql(u8, line[i .. i + name.len], name)) {
                    try result.appendSlice(entry.value_ptr.*);
                    i += name.len;
                    found_macro = true;
                    break;
                }
            }

            if (!found_macro) {
                try result.append(line[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }
};

// Shader reflection data
pub const ReflectionData = struct {
    allocator: Allocator,
    uniforms: std.StringHashMap(UniformInfo),
    attributes: std.StringHashMap(AttributeInfo),
    samplers: std.StringHashMap(SamplerInfo),
    storage_buffers: std.StringHashMap(StorageBufferInfo),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .uniforms = std.StringHashMap(UniformInfo).init(allocator),
            .attributes = std.StringHashMap(AttributeInfo).init(allocator),
            .samplers = std.StringHashMap(SamplerInfo).init(allocator),
            .storage_buffers = std.StringHashMap(StorageBufferInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all the string keys
        var uniform_it = self.uniforms.iterator();
        while (uniform_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.type_name) |name| {
                self.allocator.free(name);
            }
        }

        var attr_it = self.attributes.iterator();
        while (attr_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        var sampler_it = self.samplers.iterator();
        while (sampler_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        var storage_it = self.storage_buffers.iterator();
        while (storage_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.type_name) |name| {
                self.allocator.free(name);
            }
        }

        self.uniforms.deinit();
        self.attributes.deinit();
        self.samplers.deinit();
        self.storage_buffers.deinit();
    }
};

pub const UniformType = enum {
    float,
    float2,
    float3,
    float4,
    int,
    int2,
    int3,
    int4,
    uint,
    uint2,
    uint3,
    uint4,
    bool,
    bool2,
    bool3,
    bool4,
    mat2,
    mat3,
    mat4,
    mat2x3,
    mat2x4,
    mat3x2,
    mat3x4,
    mat4x2,
    mat4x3,
    struct_type,
    array_type,
};

pub const UniformInfo = struct {
    type: UniformType,
    size: usize,
    offset: usize,
    type_name: ?[]const u8 = null,
    array_size: usize = 0,
};

pub const AttributeInfo = struct {
    location: u32,
    format: interface.VertexFormat,
    offset: u32,
};

pub const SamplerInfo = struct {
    binding: u32,
    count: u32 = 1,
};

pub const StorageBufferInfo = struct {
    binding: u32,
    size: usize,
    type_name: ?[]const u8 = null,
};
