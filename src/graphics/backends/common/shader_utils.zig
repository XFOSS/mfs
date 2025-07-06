const std = @import("std");
const types = @import("../../types.zig");
const errors = @import("errors.zig");

/// Common shader stage types
pub const ShaderStage = enum {
    vertex,
    fragment,
    compute,
    geometry,
    tessellation_control,
    tessellation_evaluation,
};

/// Common shader source type
pub const ShaderSourceType = enum {
    glsl,
    hlsl,
    spirv,
    metal,
    wgsl,
    binary,
};

/// Shader compilation options
pub const ShaderCompileOptions = struct {
    debug: bool = false,
    optimize: bool = true,
    entry_point: ?[]const u8 = null,
    defines: ?[]const []const u8 = null,
    include_paths: ?[]const []const u8 = null,
};

/// Shader reflection data
pub const ShaderReflection = struct {
    uniforms: std.ArrayList(UniformInfo),
    textures: std.ArrayList(TextureInfo),
    inputs: std.ArrayList(InputInfo),
    outputs: std.ArrayList(OutputInfo),
    push_constants: std.ArrayList(PushConstantInfo),

    const UniformInfo = struct {
        name: []const u8,
        type: UniformType,
        size: usize,
        offset: usize,
        binding: u32,
        set: u32,
    };

    const TextureInfo = struct {
        name: []const u8,
        binding: u32,
        set: u32,
        dimension: TextureDimension,
    };

    const InputInfo = struct {
        name: []const u8,
        location: u32,
        format: types.VertexFormat,
    };

    const OutputInfo = struct {
        name: []const u8,
        location: u32,
        format: types.VertexFormat,
    };

    const PushConstantInfo = struct {
        name: []const u8,
        size: usize,
        offset: usize,
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
        mat2,
        mat3,
        mat4,
        struct_type,
        array,
    };

    pub const TextureDimension = enum {
        tex1d,
        tex2d,
        tex3d,
        texCube,
    };

    pub fn init(allocator: std.mem.Allocator) ShaderReflection {
        return ShaderReflection{
            .uniforms = std.ArrayList(UniformInfo).init(allocator),
            .textures = std.ArrayList(TextureInfo).init(allocator),
            .inputs = std.ArrayList(InputInfo).init(allocator),
            .outputs = std.ArrayList(OutputInfo).init(allocator),
            .push_constants = std.ArrayList(PushConstantInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ShaderReflection) void {
        self.uniforms.deinit();
        self.textures.deinit();
        self.inputs.deinit();
        self.outputs.deinit();
        self.push_constants.deinit();
    }
};

/// Common shader utilities that can be shared across backends
pub const ShaderUtils = struct {
    /// Parse shader source and determine its type
    pub fn detectShaderType(source: []const u8) ShaderSourceType {
        // Check for SPIR-V magic number
        if (source.len >= 4 and source[0] == 0x03 and source[1] == 0x02 and source[2] == 0x23 and source[3] == 0x07) {
            return .spirv;
        }

        // Check for GLSL
        if (std.mem.indexOf(u8, source, "#version") != null or
            std.mem.indexOf(u8, source, "void main") != null)
        {
            return .glsl;
        }

        // Check for HLSL
        if (std.mem.indexOf(u8, source, "cbuffer") != null or
            std.mem.indexOf(u8, source, "struct VS_INPUT") != null or
            std.mem.indexOf(u8, source, "struct PS_INPUT") != null)
        {
            return .hlsl;
        }

        // Check for Metal
        if (std.mem.indexOf(u8, source, "#include <metal_stdlib>") != null or
            std.mem.indexOf(u8, source, "using namespace metal;") != null)
        {
            return .metal;
        }

        // Check for WGSL
        if (std.mem.indexOf(u8, source, "@compute") != null or
            std.mem.indexOf(u8, source, "@vertex") != null or
            std.mem.indexOf(u8, source, "@fragment") != null)
        {
            return .wgsl;
        }

        // Default to binary if we can't determine
        return .binary;
    }

    /// Detect shader stage from file name or directive
    pub fn detectShaderStage(filename: []const u8, source: []const u8) ShaderStage {
        // Check filename for common patterns
        if (std.mem.indexOf(u8, filename, "vert") != null or
            std.mem.indexOf(u8, filename, "vs") != null)
        {
            return .vertex;
        }

        if (std.mem.indexOf(u8, filename, "frag") != null or
            std.mem.indexOf(u8, filename, "fs") != null or
            std.mem.indexOf(u8, filename, "ps") != null)
        {
            return .fragment;
        }

        if (std.mem.indexOf(u8, filename, "comp") != null or
            std.mem.indexOf(u8, filename, "cs") != null)
        {
            return .compute;
        }

        if (std.mem.indexOf(u8, filename, "geom") != null or
            std.mem.indexOf(u8, filename, "gs") != null)
        {
            return .geometry;
        }

        if (std.mem.indexOf(u8, filename, "tesc") != null or
            std.mem.indexOf(u8, filename, "hs") != null)
        {
            return .tessellation_control;
        }

        if (std.mem.indexOf(u8, filename, "tese") != null or
            std.mem.indexOf(u8, filename, "ds") != null)
        {
            return .tessellation_evaluation;
        }

        // Check source for stage hints
        if (std.mem.indexOf(u8, source, "@vertex") != null or
            std.mem.indexOf(u8, source, "#pragma stage vertex") != null)
        {
            return .vertex;
        }

        if (std.mem.indexOf(u8, source, "@fragment") != null or
            std.mem.indexOf(u8, source, "#pragma stage fragment") != null)
        {
            return .fragment;
        }

        if (std.mem.indexOf(u8, source, "@compute") != null or
            std.mem.indexOf(u8, source, "#pragma stage compute") != null)
        {
            return .compute;
        }

        // Default to vertex if we can't determine
        return .vertex;
    }

    /// Extract shader defines from source code
    pub fn extractDefines(allocator: std.mem.Allocator, source: []const u8) !std.StringHashMap([]const u8) {
        var defines = std.StringHashMap([]const u8).init(allocator);

        var lines = std.mem.splitSequence(u8, source, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (std.mem.startsWith(u8, trimmed, "#define ")) {
                const define_content = trimmed[8..]; // Skip "#define "
                var parts = std.mem.splitSequence(u8, define_content, " ");
                if (parts.next()) |name| {
                    const name_copy = try allocator.dupe(u8, name);
                    const value_part = parts.rest();
                    const value = if (value_part.len > 0) try allocator.dupe(u8, value_part) else "";
                    try defines.put(name_copy, value);
                }
            }
        }

        return defines;
    }

    /// Extract shader includes from source code
    pub fn extractIncludes(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList([]const u8) {
        var includes = std.ArrayList([]const u8).init(allocator);

        var lines = std.mem.splitSequence(u8, source, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (std.mem.startsWith(u8, trimmed, "#include ")) {
                const include_path = std.mem.trim(u8, trimmed[9..], " \t\"<>"); // Skip "#include " and trim quotes
                const path_copy = try allocator.dupe(u8, include_path);
                try includes.append(path_copy);
            }
        }

        return includes;
    }

    /// Load shader from file
    pub fn loadShaderFromFile(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);
        const bytes_read = try file.readAll(buffer);

        if (bytes_read != file_size) {
            allocator.free(buffer);
            return errors.GraphicsError.ResourceCreationFailed;
        }

        return buffer;
    }

    /// Simple shader preprocessor to handle includes
    pub fn preprocessShader(allocator: std.mem.Allocator, source: []const u8, include_paths: []const []const u8) ![]const u8 {
        var includes = try extractIncludes(allocator, source);
        defer {
            for (includes.items) |include| {
                allocator.free(include);
            }
            includes.deinit();
        }

        if (includes.items.len == 0) {
            return allocator.dupe(u8, source);
        }

        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var lines = std.mem.splitSequence(u8, source, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (std.mem.startsWith(u8, trimmed, "#include ")) {
                const include_path = std.mem.trim(u8, trimmed[9..], " \t\"<>"); // Skip "#include " and trim quotes

                var found = false;
                for (include_paths) |path| {
                    const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, include_path });
                    defer allocator.free(full_path);

                    const included_source = loadShaderFromFile(allocator, full_path) catch continue;
                    defer allocator.free(included_source);

                    const processed_include = try preprocessShader(allocator, included_source, include_paths);
                    defer allocator.free(processed_include);

                    try result.appendSlice(processed_include);
                    try result.append('\n');
                    found = true;
                    break;
                }

                if (!found) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            } else {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }

        return result.toOwnedSlice();
    }
};
