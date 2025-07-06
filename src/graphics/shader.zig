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
    shader_hash: u64 = 0,
    last_used_time: i64 = 0,
    compile_duration_ns: u64 = 0,
    is_hot_reloadable: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        const program = try allocator.create(Self);
        program.* = Self{
            .allocator = allocator,
            .reflection_data = ReflectionData.init(allocator),
            .last_used_time = std.time.timestamp(),
        };
        return program;
    }

    /// Initialize a shader program with a unique name for caching/reloading
    pub fn initNamed(allocator: Allocator, name: []const u8) !*Self {
        var program = try Self.init(allocator);
        program.shader_hash = std.hash.Wyhash.hash(0, name);
        program.is_hot_reloadable = true;
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
        const timer_opt = std.time.Timer.start() catch null;
        const start_time = if (timer_opt) |timer| timer.read() else 0;

        // Try to load from shader cache first if we have a hash
        if (self.shader_hash != 0) {
            if (shader_cache.getCompiledShader(self.shader_hash, shader_type)) |cached_shader| {
                std.log.info("Using cached shader for {s}", .{path});
                try self.addCompiledShader(shader_type, cached_shader);
                return;
            }
        }

        const source = try self.loadShaderSource(path, options);
        defer self.allocator.free(source);

        try self.addShader(shader_type, source);

        if (timer_opt) |timer| {
            const compile_time = timer.read() - start_time;
            self.compile_duration_ns += compile_time;
            std.log.info("Shader {s} compilation took {d:.2}ms", .{
                path,
                @as(f64, @floatFromInt(compile_time)) / 1_000_000.0,
            });
        }

        // Update last used time
        self.last_used_time = std.time.timestamp();
    }

    pub fn addCompiledShader(self: *Self, shader_type: gpu.ShaderType, shader: *gpu.Shader) !void {
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

/// Global shader cache for compiled shaders
pub const ShaderCache = struct {
    allocator: Allocator,
    shader_map: std.AutoHashMap(u64, *gpu.Shader),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator) ShaderCache {
        return .{
            .allocator = allocator,
            .shader_map = std.AutoHashMap(u64, *gpu.Shader).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *ShaderCache) void {
        var it = self.shader_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.shader_map.deinit();
    }

    pub fn cacheShader(self: *ShaderCache, hash: u64, shader_type: gpu.ShaderType, shader: *gpu.Shader) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const cache_key = hash ^ @intFromEnum(shader_type);
        try self.shader_map.put(cache_key, shader);
    }

    pub fn getCompiledShader(self: *ShaderCache, hash: u64, shader_type: gpu.ShaderType) ?*gpu.Shader {
        self.mutex.lock();
        defer self.mutex.unlock();

        const cache_key = hash ^ @intFromEnum(shader_type);
        return self.shader_map.get(cache_key);
    }

    pub fn purgeUnused(self: *ShaderCache, older_than_seconds: i64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();
        var to_remove = std.ArrayList(u64).init(self.allocator);
        defer to_remove.deinit();

        var it = self.shader_map.iterator();
        while (it.next()) |entry| {
            const shader = entry.value_ptr.*;
            if (shader.last_used_time + older_than_seconds < current_time) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            if (self.shader_map.fetchRemove(key)) |kv| {
                kv.value.deinit();
            }
        }
    }
};

var shader_cache: ShaderCache = undefined;

/// Initialize the global shader cache
pub fn initShaderCache(allocator: Allocator) void {
    shader_cache = ShaderCache.init(allocator);
}

/// Deinitialize the global shader cache
pub fn deinitShaderCache() void {
    shader_cache.deinit();
}

pub const ShaderPreprocessor = struct {
    allocator: Allocator,
    options: ShaderCompileOptions,
    include_stack: std.ArrayList([]const u8),
    defines: std.StringHashMap([]const u8),
    processed_includes: std.StringHashMap([]const u8),

    const Self = @This();

    pub fn init(allocator: Allocator, options: ShaderCompileOptions) Self {
        var preprocessor = Self{
            .allocator = allocator,
            .options = options,
            .include_stack = std.ArrayList([]const u8).init(allocator),
            .defines = std.StringHashMap([]const u8).init(allocator),
            .processed_includes = std.StringHashMap([]const u8).init(allocator),
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

        // Free any cached processed includes
        var include_it = self.processed_includes.iterator();
        while (include_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.processed_includes.deinit();
    }

    pub fn process(self: *Self, source: []const u8, base_path: []const u8) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        try self.include_stack.append(base_path);
        defer _ = self.include_stack.pop();

        var lines = std.mem.splitSequence(u8, source, "\n");
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
        // Check if we've already processed this include
        if (self.processed_includes.get(path)) |content| {
            return content;
        }

        // Try custom include handler first if available
        if (self.options.include_handler) |handler| {
            if (handler.resolve(path)) |content| {
                // Cache the include content for future use
                const path_copy = try self.allocator.dupe(u8, path);
                const content_copy = try self.allocator.dupe(u8, content);
                try self.processed_includes.put(path_copy, content_copy);
                return content;
            }
        }

        // Fall back to regular file loading
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));

        // Cache the include content for future use
        const path_copy = try self.allocator.dupe(u8, path);
        const content_copy = try self.allocator.dupe(u8, content);
        try self.processed_includes.put(path_copy, content_copy);

        return content;
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
/// Structure for reflection data that can be extracted from shaders
pub const ReflectionData = struct {
    allocator: Allocator,
    uniforms: std.StringHashMap(UniformInfo),
    attributes: std.StringHashMap(AttributeInfo),
    samplers: std.StringHashMap(SamplerInfo),
    storage_buffers: std.StringHashMap(StorageBufferInfo),
    uniform_blocks: std.StringHashMap(UniformBlockInfo),
    entry_points: std.ArrayList(EntryPointInfo),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .uniforms = std.StringHashMap(UniformInfo).init(allocator),
            .attributes = std.StringHashMap(AttributeInfo).init(allocator),
            .samplers = std.StringHashMap(SamplerInfo).init(allocator),
            .storage_buffers = std.StringHashMap(StorageBufferInfo).init(allocator),
            .uniform_blocks = std.StringHashMap(UniformBlockInfo).init(allocator),
            .entry_points = std.ArrayList(EntryPointInfo).init(allocator),
        };
    }

    /// Add an entry point to the reflection data
    pub fn addEntryPoint(self: *Self, name: []const u8, stage: gpu.ShaderType) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.entry_points.append(EntryPointInfo{
            .name = name_copy,
            .stage = stage,
        });
    }

    /// Get all entry points for a specific shader stage
    pub fn getEntryPoints(self: *const Self, stage: gpu.ShaderType, allocator: Allocator) ![]EntryPointInfo {
        var result = std.ArrayList(EntryPointInfo).init(allocator);
        defer result.deinit();

        for (self.entry_points.items) |entry| {
            if (entry.stage == stage) {
                try result.append(entry);
            }
        }

        return result.toOwnedSlice();
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

        var block_it = self.uniform_blocks.iterator();
        while (block_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.members) |members| {
                self.allocator.free(members);
            }
        }

        for (self.entry_points.items) |entry| {
            self.allocator.free(entry.name);
        }

        self.uniforms.deinit();
        self.attributes.deinit();
        self.samplers.deinit();
        self.storage_buffers.deinit();
        self.uniform_blocks.deinit();
        self.entry_points.deinit();
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

pub const UniformBlockInfo = struct {
    binding: u32,
    size: usize,
    members: ?[]UniformMemberInfo = null,
};

pub const UniformMemberInfo = struct {
    name: []const u8,
    type: UniformType,
    offset: usize,
    size: usize,
};

pub const EntryPointInfo = struct {
    name: []const u8,
    stage: gpu.ShaderType,
};

/// Hot reload support for shader programs
pub const ShaderHotReloader = struct {
    allocator: Allocator,
    watch_paths: std.StringHashMap(ShaderWatchInfo),
    mutex: std.Thread.Mutex,
    watcher_thread: ?std.Thread = null,
    running: bool = false,

    pub fn init(allocator: Allocator) !*ShaderHotReloader {
        const reloader = try allocator.create(ShaderHotReloader);
        reloader.* = ShaderHotReloader{
            .allocator = allocator,
            .watch_paths = std.StringHashMap(ShaderWatchInfo).init(allocator),
            .mutex = .{},
        };
        return reloader;
    }

    pub fn deinit(self: *ShaderHotReloader) void {
        self.stopWatching();

        var it = self.watch_paths.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.watch_paths.deinit();
        self.allocator.destroy(self);
    }

    pub fn watchShader(self: *ShaderHotReloader, path: []const u8, program: *ShaderProgram, shader_type: gpu.ShaderType) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const path_copy = try self.allocator.dupe(u8, path);
        try self.watch_paths.put(path_copy, ShaderWatchInfo{
            .program = program,
            .shader_type = shader_type,
            .last_modified = try getFileModTime(path),
        });
    }

    pub fn startWatching(self: *ShaderHotReloader) !void {
        if (self.running) return;

        self.running = true;
        self.watcher_thread = try std.Thread.spawn(.{}, watcherThreadFn, .{self});
    }

    pub fn stopWatching(self: *ShaderHotReloader) void {
        if (!self.running) return;

        self.running = false;
        if (self.watcher_thread) |thread| {
            thread.join();
            self.watcher_thread = null;
        }
    }

    fn watcherThreadFn(self: *ShaderHotReloader) void {
        while (self.running) {
            self.checkForChanges() catch |err| {
                std.log.err("Error in shader watcher: {}", .{err});
            };
            std.time.sleep(1 * std.time.ns_per_s); // Check every second
        }
    }

    fn checkForChanges(self: *ShaderHotReloader) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var to_reload = std.ArrayList(struct {
            path: []const u8,
            info: ShaderWatchInfo,
        }).init(self.allocator);
        defer to_reload.deinit();

        var it = self.watch_paths.iterator();
        while (it.next()) |entry| {
            const path = entry.key_ptr.*;
            const info = entry.value_ptr.*;

            const current_mod_time = getFileModTime(path) catch continue;

            if (current_mod_time > info.last_modified) {
                try to_reload.append(.{ .path = path, .info = info });

                // Update the last modified time
                var updated_info = info;
                updated_info.last_modified = current_mod_time;
                try self.watch_paths.put(path, updated_info);
            }
        }

        // Release the lock while reloading shaders
        self.mutex.unlock();

        // Reload shaders that have changed
        for (to_reload.items) |item| {
            std.log.info("Hot reloading shader: {s}", .{item.path});
            item.info.program.reloadShader(item.info.shader_type, item.path) catch |err| {
                std.log.err("Failed to hot reload shader {s}: {}", .{ item.path, err });
            };
        }

        // Reacquire the lock
        self.mutex.lock();
    }

    fn getFileModTime(path: []const u8) !i128 {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        return stat.mtime;
    }
};

pub const ShaderWatchInfo = struct {
    program: *ShaderProgram,
    shader_type: gpu.ShaderType,
    last_modified: i128,
};
