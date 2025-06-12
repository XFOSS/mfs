const std = @import("std");
const vk = @import("vk.zig");
const backend = @import("backend.zig");
const Allocator = std.mem.Allocator;

pub const ShaderCompileError = error{
    FileNotFound,
    CompilationFailed,
    InvalidShaderStage,
    OutOfMemory,
    ShaderModuleCreationFailed,
};

pub const ShaderStage = enum {
    vertex,
    fragment,
    geometry,
    tessellation_control,
    tessellation_evaluation,
    compute,

    pub fn toVulkanStage(self: ShaderStage) u32 {
        return switch (self) {
            .vertex => 0x00000001, // VK_SHADER_STAGE_VERTEX_BIT
            .fragment => 0x00000010, // VK_SHADER_STAGE_FRAGMENT_BIT
            .geometry => 0x00000008, // VK_SHADER_STAGE_GEOMETRY_BIT
            .tessellation_control => 0x00000002, // VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT
            .tessellation_evaluation => 0x00000004, // VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT
            .compute => 0x00000020, // VK_SHADER_STAGE_COMPUTE_BIT
        };
    }

    pub fn getFileExtension(self: ShaderStage) []const u8 {
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
pub const CompiledShader = struct {
    spirv_code: []u8,
    stage: ShaderStage,
    entry_point: []const u8,
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        if (self.spirv_code.len > 0) {
            self.allocator.free(self.spirv_code);
        }
        if (self.entry_point.len > 0) {
            self.allocator.free(self.entry_point);
        }
    }

    pub fn createShaderModule(self: *Self, device: vk.VkDevice) !vk.VkShaderModule {
        const create_info = vk.VkShaderModuleCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = self.spirv_code.len,
            .pCode = @ptrCast(self.spirv_code.ptr),
        };

        var shader_module: vk.VkShaderModule = undefined;
        const result = vk.vkCreateShaderModule(device, &create_info, null, &shader_module);

        if (result != vk.VK_SUCCESS) {
            std.debug.print("Failed to create shader module: {} ({})\n", .{ result, @errorName(error.ShaderModuleCreationFailed) });
            return error.ShaderModuleCreationFailed;
        }

        return shader_module;
    }
};

pub const ShaderLoader = struct {
    allocator: Allocator,
    shader_cache: std.HashMap(u64, CompiledShader, std.hash_map.AutoContext(u64)),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .shader_cache = std.HashMap(u64, CompiledShader, std.hash_map.AutoContext(u64)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.shader_cache.valueIterator();
        while (iterator.next()) |shader| {
            var mutable_shader = shader.*;
            mutable_shader.deinit();
        }
        self.shader_cache.deinit();
    }

    pub fn loadShaderFromFile(self: *Self, file_path: []const u8, stage: ShaderStage) !CompiledShader {
        const hash = std.hash_map.hashString(file_path);

        // Check cache first
        if (self.shader_cache.get(hash)) |cached_shader| {
            std.debug.print("Using cached shader: {s}\n", .{file_path});
            return cached_shader;
        }

        std.debug.print("Loading shader: {s}\n", .{file_path});

        // Read shader source
        const source_code = try self.readShaderFile(file_path);
        defer self.allocator.free(source_code);

        // Compile to SPIR-V
        const spirv_code = try self.compileShader(source_code, stage);

        const compiled_shader = CompiledShader{
            .spirv_code = spirv_code,
            .stage = stage,
            .entry_point = try self.allocator.dupe(u8, "main"),
            .allocator = self.allocator,
        };

        // Cache the compiled shader
        try self.shader_cache.put(hash, compiled_shader);

        return compiled_shader;
    }

    pub fn loadShaderFromSource(self: *Self, source_code: []const u8, stage: ShaderStage, name: []const u8) !CompiledShader {
        std.debug.print("Compiling shader from source: {s}\n", .{name});

        const spirv_code = try self.compileShader(source_code, stage);

        return CompiledShader{
            .spirv_code = spirv_code,
            .stage = stage,
            .entry_point = try self.allocator.dupe(u8, "main"),
            .allocator = self.allocator,
        };
    }

    pub fn loadPrecompiledShader(self: *Self, spirv_file_path: []const u8, stage: ShaderStage) !CompiledShader {
        std.debug.print("Loading precompiled shader: {s}\n", .{spirv_file_path});

        const file = std.fs.cwd().openFile(spirv_file_path, .{}) catch |err| {
            std.debug.print("Failed to open SPIR-V file: {s} - {s}\n", .{ spirv_file_path, @errorName(err) });
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const spirv_code = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(spirv_code);

        return CompiledShader{
            .spirv_code = spirv_code,
            .stage = stage,
            .entry_point = try self.allocator.dupe(u8, "main"),
            .allocator = self.allocator,
        };
    }

    fn readShaderFile(self: *Self, file_path: []const u8) ![]u8 {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            std.debug.print("Failed to open shader file: {s} - {s}\n", .{ file_path, @errorName(err) });
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const source_code = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(source_code);

        return source_code;
    }

    fn compileShader(self: *Self, source_code: []const u8, stage: ShaderStage) ![]u8 {
        // Create temporary files for input and output
        std.fs.cwd().makeOpenPath("temp", .{}) catch |err| {
            std.debug.print("Failed to create temp directory: {s}\n", .{@errorName(err)});
            return err;
        };

        // Ensure cleanup happens even on error
        defer {
            std.fs.cwd().deleteTree("temp") catch |cleanup_err| {
                std.debug.print("Warning: Failed to cleanup temp directory: {s}\n", .{@errorName(cleanup_err)});
            };
        }

        const source_path = try std.fmt.allocPrint(self.allocator, "temp/shader{s}", .{stage.getFileExtension()});
        defer self.allocator.free(source_path);
        const spirv_path = try std.fmt.allocPrint(self.allocator, "temp/shader{s}.spv", .{stage.getFileExtension()});
        defer self.allocator.free(spirv_path);

        // Write source to temp file
        const source_file = try std.fs.cwd().createFile(source_path, .{});
        defer source_file.close();
        try source_file.writeAll(source_code);

        // Compile using glslc
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "glslc", "-fshader-stage=" ++ @tagName(stage), source_path, "-o", spirv_path },
        }) catch |err| {
            std.debug.print("Failed to run glslc: {s}\n", .{@errorName(err)});
            return err;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term != .Exited or result.term.Exited != 0) {
            std.debug.print("Shader compilation failed:\n{s}\n", .{result.stderr});
            return error.CompilationFailed;
        }

        // Read compiled SPIR-V
        const spirv_file = try std.fs.cwd().openFile(spirv_path, .{});
        defer spirv_file.close();

        const spirv_size = try spirv_file.getEndPos();
        const spirv_code = try self.allocator.alloc(u8, spirv_size);
        _ = try spirv_file.readAll(spirv_code);

        return spirv_code;
    }

    pub fn compileShaderWithGlslc(self: *Self, source_file: []const u8, output_file: []const u8) !void {
        // Execute glslc compiler
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "glslc", source_file, "-o", output_file },
        }) catch |err| {
            std.debug.print("Failed to run glslc: {s}\n", .{@errorName(err)});
            return err;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term != .Exited or result.term.Exited != 0) {
            std.debug.print("Shader compilation failed:\n{s}\n", .{result.stderr});
            return error.CompilationFailed;
        }

        std.debug.print("Shader compiled successfully: {s} -> {s}\n", .{ source_file, output_file });
    }

    pub fn validateShader(spirv_code: []const u8) bool {
        // Check SPIR-V magic number
        if (spirv_code.len < 4) return false;

        const magic = (@as(u32, spirv_code[3]) << 24) |
            (@as(u32, spirv_code[2]) << 16) |
            (@as(u32, spirv_code[1]) << 8) |
            @as(u32, spirv_code[0]);

        return magic == 0x07230203;
    }

    pub fn getShaderInfo(spirv_code: []const u8) !ShaderInfo {
        if (!validateShader(spirv_code)) {
            return error.InvalidShaderFormat;
        }

        // Mock implementation - in real code would parse SPIR-V headers
        return ShaderInfo{
            .version = 100,
            .generator = "Mock Compiler",
            .entry_points = &[_][]const u8{"main"},
        };
    }
};

pub const ShaderInfo = struct {
    version: u32,
    generator: []const u8,
    entry_points: []const []const u8,
};

// Built-in shaders
pub const embedded_vertex_shader =
    \\#version 450
    \\
    \\layout(binding = 0) uniform UniformBufferObject {
    \\    mat4 model;
    \\    mat4 view;
    \\    mat4 proj;
    \\} ubo;
    \\
    \\layout(location = 0) in vec3 inPosition;
    \\layout(location = 1) in vec3 inColor;
    \\
    \\layout(location = 0) out vec3 fragColor;
    \\
    \\void main() {
    \\    gl_Position = ubo.proj * ubo.view * ubo.model * vec4(inPosition, 1.0);
    \\    fragColor = inColor;
    \\}
;

pub const embedded_fragment_shader =
    \\#version 450
    \\
    \\layout(location = 0) in vec3 fragColor;
    \\layout(location = 0) out vec4 outColor;
    \\
    \\void main() {
    \\    outColor = vec4(fragColor, 1.0);
    \\}
;

pub const embedded_fragment_shader_animated =
    \\#version 450
    \\
    \\layout(binding = 0) uniform UniformBufferObject {
    \\    mat4 model;
    \\    mat4 view;
    \\    mat4 proj;
    \\    float time;
    \\} ubo;
    \\
    \\layout(location = 0) in vec3 fragColor;
    \\layout(location = 0) out vec4 outColor;
    \\
    \\void main() {
    \\    float pulse = 0.5 + 0.5 * sin(ubo.time * 3.0);
    \\    vec3 animatedColor = fragColor * pulse;
    \\    outColor = vec4(animatedColor, 1.0);
    \\}
;

// Utility functions
pub fn createShaderLoader(allocator: Allocator) ShaderLoader {
    return ShaderLoader.init(allocator);
}

pub fn loadEmbeddedShaders(allocator: Allocator) !struct { vertex: CompiledShader, fragment: CompiledShader } {
    var loader = ShaderLoader.init(allocator);
    defer loader.deinit();

    const vertex_shader = loader.loadShaderFromSource(embedded_vertex_shader, .vertex, "embedded_vertex") catch |err| {
        std.debug.print("Failed to load embedded vertex shader: {s}\n", .{@errorName(err)});
        return err;
    };

    const fragment_shader = loader.loadShaderFromSource(embedded_fragment_shader, .fragment, "embedded_fragment") catch |err| {
        std.debug.print("Failed to load embedded fragment shader: {s}\n", .{@errorName(err)});
        return err;
    };

    return .{
        .vertex = vertex_shader,
        .fragment = fragment_shader,
    };
}
