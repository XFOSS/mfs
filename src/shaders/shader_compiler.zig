//! Advanced Shader Compilation System for MFS Engine
//! Provides cross-platform shader compilation with optimization and caching
//! @thread-safe Shader compilation is thread-safe with proper synchronization
//! @symbol ShaderCompiler - Main shader compilation interface

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const AutoHashMap = std.AutoHashMap;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const RwLock = std.Thread.RwLock;

// Import engine systems
const memory = @import("../system/memory/memory_manager.zig");
const profiler = @import("../system/profiling/profiler.zig");

/// Supported shader languages
pub const ShaderLanguage = enum {
    hlsl,
    glsl,
    spirv,
    metal,
    wgsl,

    pub fn toString(self: ShaderLanguage) []const u8 {
        return switch (self) {
            .hlsl => "HLSL",
            .glsl => "GLSL",
            .spirv => "SPIR-V",
            .metal => "Metal",
            .wgsl => "WGSL",
        };
    }

    pub fn getFileExtension(self: ShaderLanguage) []const u8 {
        return switch (self) {
            .hlsl => ".hlsl",
            .glsl => ".glsl",
            .spirv => ".spv",
            .metal => ".metal",
            .wgsl => ".wgsl",
        };
    }
};

/// Shader stage types
pub const ShaderStage = enum {
    vertex,
    fragment,
    geometry,
    compute,
    tessellation_control,
    tessellation_evaluation,

    pub fn toString(self: ShaderStage) []const u8 {
        return switch (self) {
            .vertex => "Vertex",
            .fragment => "Fragment",
            .geometry => "Geometry",
            .compute => "Compute",
            .tessellation_control => "Tessellation Control",
            .tessellation_evaluation => "Tessellation Evaluation",
        };
    }

    pub fn getHLSLTarget(self: ShaderStage) []const u8 {
        return switch (self) {
            .vertex => "vs_5_0",
            .fragment => "ps_5_0",
            .geometry => "gs_5_0",
            .compute => "cs_5_0",
            .tessellation_control => "hs_5_0",
            .tessellation_evaluation => "ds_5_0",
        };
    }

    pub fn getGLSLStage(self: ShaderStage) []const u8 {
        return switch (self) {
            .vertex => "#version 450\n#define VERTEX_SHADER\n",
            .fragment => "#version 450\n#define FRAGMENT_SHADER\n",
            .geometry => "#version 450\n#define GEOMETRY_SHADER\n",
            .compute => "#version 450\n#define COMPUTE_SHADER\n",
            .tessellation_control => "#version 450\n#define TESSELLATION_CONTROL_SHADER\n",
            .tessellation_evaluation => "#version 450\n#define TESSELLATION_EVALUATION_SHADER\n",
        };
    }
};

/// Shader compilation options
pub const CompilationOptions = struct {
    optimization_level: OptimizationLevel = .default,
    debug_info: bool = false,
    warnings_as_errors: bool = false,
    include_paths: []const []const u8 = &.{},
    defines: AutoHashMap([]const u8, []const u8),
    entry_point: []const u8 = "main",
    target_language: ShaderLanguage,
    target_stage: ShaderStage,

    pub fn init(allocator: Allocator, target_language: ShaderLanguage, target_stage: ShaderStage) CompilationOptions {
        return CompilationOptions{
            .defines = AutoHashMap([]const u8, []const u8).init(allocator),
            .target_language = target_language,
            .target_stage = target_stage,
        };
    }

    pub fn deinit(self: *CompilationOptions) void {
        self.defines.deinit();
    }

    pub fn addDefine(self: *CompilationOptions, name: []const u8, value: []const u8) !void {
        try self.defines.put(name, value);
    }
};

/// Optimization levels
pub const OptimizationLevel = enum {
    none,
    basic,
    default,
    aggressive,

    pub fn getHLSLFlag(self: OptimizationLevel) []const u8 {
        return switch (self) {
            .none => "/Od",
            .basic => "/O1",
            .default => "/O2",
            .aggressive => "/O3",
        };
    }

    pub fn getGLSLFlag(self: OptimizationLevel) []const u8 {
        return switch (self) {
            .none => "-O0",
            .basic => "-O1",
            .default => "-O2",
            .aggressive => "-O3",
        };
    }
};

/// Shader compilation result
pub const CompilationResult = struct {
    success: bool,
    bytecode: ?[]u8 = null,
    error_message: ?[]u8 = null,
    warning_messages: ArrayList([]u8),
    compilation_time_ms: u64,
    source_hash: u64,

    pub fn init(allocator: Allocator) CompilationResult {
        return CompilationResult{
            .success = false,
            .warning_messages = ArrayList([]u8).init(allocator),
            .compilation_time_ms = 0,
            .source_hash = 0,
        };
    }

    pub fn deinit(self: *CompilationResult, allocator: Allocator) void {
        if (self.bytecode) |bytecode| {
            allocator.free(bytecode);
        }
        if (self.error_message) |error_msg| {
            allocator.free(error_msg);
        }
        for (self.warning_messages.items) |warning| {
            allocator.free(warning);
        }
        self.warning_messages.deinit();
    }
};

/// Shader include resolver for handling #include directives
pub const IncludeResolver = struct {
    const Self = @This();

    include_paths: ArrayList([]const u8),
    file_cache: AutoHashMap(u64, []u8), // Hash -> Content
    allocator: Allocator,
    mutex: RwLock,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .include_paths = ArrayList([]const u8).init(allocator),
            .file_cache = AutoHashMap(u64, []u8).init(allocator),
            .allocator = allocator,
            .mutex = RwLock{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free cached file contents
        var cache_iter = self.file_cache.valueIterator();
        while (cache_iter.next()) |content| {
            self.allocator.free(content.*);
        }
        self.file_cache.deinit();

        // Free include paths
        for (self.include_paths.items) |path| {
            self.allocator.free(path);
        }
        self.include_paths.deinit();
    }

    pub fn addIncludePath(self: *Self, path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const owned_path = try self.allocator.dupe(u8, path);
        try self.include_paths.append(owned_path);
    }

    pub fn resolveInclude(self: *Self, include_name: []const u8) !?[]const u8 {
        const path_hash = std.hash_map.hashString(include_name);

        // Check cache first
        self.mutex.lockShared();
        if (self.file_cache.get(path_hash)) |cached_content| {
            defer self.mutex.unlockShared();
            return cached_content;
        }
        self.mutex.unlockShared();

        // Search in include paths
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.include_paths.items) |include_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ include_path, include_name });
            defer self.allocator.free(full_path);

            if (std.fs.cwd().readFileAlloc(self.allocator, full_path, 1024 * 1024)) |content| {
                // Cache the content
                try self.file_cache.put(path_hash, content);
                return content;
            } else |_| {
                // File not found in this path, continue searching
                continue;
            }
        }

        return null;
    }

    pub fn preprocessSource(self: *Self, source: []const u8) ![]u8 {
        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var lines = std.mem.splitSequence(u8, source, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (std.mem.startsWith(u8, trimmed, "#include")) {
                // Parse include directive
                const include_start = std.mem.indexOf(u8, trimmed, "\"") orelse std.mem.indexOf(u8, trimmed, "<");
                const include_end = std.mem.lastIndexOf(u8, trimmed, "\"") orelse std.mem.lastIndexOf(u8, trimmed, ">");

                if (include_start != null and include_end != null and include_end.? > include_start.?) {
                    const include_name = trimmed[include_start.? + 1 .. include_end.?];

                    if (try self.resolveInclude(include_name)) |include_content| {
                        // Recursively preprocess included content
                        const processed_include = try self.preprocessSource(include_content);
                        defer self.allocator.free(processed_include);

                        try result.appendSlice(processed_include);
                        try result.append('\n');
                    } else {
                        // Include not found, keep the directive as-is
                        try result.appendSlice(line);
                        try result.append('\n');
                    }
                } else {
                    // Malformed include directive
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            } else {
                // Regular line
                try result.appendSlice(line);
                try result.append('\n');
            }
        }

        return result.toOwnedSlice();
    }
};

/// Cross-platform shader compiler
pub const ShaderCompiler = struct {
    const Self = @This();

    allocator: Allocator,
    include_resolver: IncludeResolver,
    cache: AutoHashMap(u64, CompilationResult), // Source hash -> Result
    cache_mutex: RwLock,
    compilation_mutex: Mutex,

    // Platform-specific compiler paths
    dxc_path: ?[]const u8 = null,
    glslc_path: ?[]const u8 = null,
    spirv_cross_path: ?[]const u8 = null,

    // Statistics
    total_compilations: std.atomic.Value(u64),
    cache_hits: std.atomic.Value(u64),
    compilation_time_total: std.atomic.Value(u64),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .include_resolver = IncludeResolver.init(allocator),
            .cache = AutoHashMap(u64, CompilationResult).init(allocator),
            .cache_mutex = RwLock{},
            .compilation_mutex = Mutex{},
            .total_compilations = std.atomic.Value(u64).init(0),
            .cache_hits = std.atomic.Value(u64).init(0),
            .compilation_time_total = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        // Free cached compilation results
        var cache_iter = self.cache.valueIterator();
        while (cache_iter.next()) |result| {
            result.deinit();
        }
        self.cache.deinit();

        self.include_resolver.deinit();

        if (self.dxc_path) |path| self.allocator.free(path);
        if (self.glslc_path) |path| self.allocator.free(path);
        if (self.spirv_cross_path) |path| self.allocator.free(path);
    }

    pub fn setCompilerPath(self: *Self, compiler: enum { dxc, glslc, spirv_cross }, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);

        switch (compiler) {
            .dxc => {
                if (self.dxc_path) |old_path| self.allocator.free(old_path);
                self.dxc_path = owned_path;
            },
            .glslc => {
                if (self.glslc_path) |old_path| self.allocator.free(old_path);
                self.glslc_path = owned_path;
            },
            .spirv_cross => {
                if (self.spirv_cross_path) |old_path| self.allocator.free(old_path);
                self.spirv_cross_path = owned_path;
            },
        }
    }

    pub fn addIncludePath(self: *Self, path: []const u8) !void {
        try self.include_resolver.addIncludePath(path);
    }

    pub fn compileShader(self: *Self, source: []const u8, options: CompilationOptions) !CompilationResult {
        const zone_id = profiler.Profiler.beginZone("Shader Compilation");
        defer profiler.Profiler.endZone(zone_id);

        const start_time = std.time.milliTimestamp();

        // Calculate source hash for caching
        const source_hash = std.hash_map.hashString(source);

        // Check cache first
        self.cache_mutex.lockShared();
        if (self.cache.get(source_hash)) |cached_result| {
            self.cache_mutex.unlockShared();
            _ = self.cache_hits.fetchAdd(1, .monotonic);

            // Return a copy of the cached result
            var result = CompilationResult.init(self.allocator);
            result.success = cached_result.success;
            result.compilation_time_ms = cached_result.compilation_time_ms;
            result.source_hash = cached_result.source_hash;

            if (cached_result.bytecode) |bytecode| {
                result.bytecode = try self.allocator.dupe(u8, bytecode);
            }
            if (cached_result.error_message) |error_msg| {
                result.error_message = try self.allocator.dupe(u8, error_msg);
            }

            return result;
        }
        self.cache_mutex.unlockShared();

        // Perform compilation
        self.compilation_mutex.lock();
        defer self.compilation_mutex.unlock();

        var result = CompilationResult.init(self.allocator);
        result.source_hash = source_hash;

        // Preprocess source to handle includes
        const preprocessed_source = self.include_resolver.preprocessSource(source) catch |err| {
            result.error_message = try std.fmt.allocPrint(self.allocator, "Preprocessing failed: {}", .{err});
            return result;
        };
        defer self.allocator.free(preprocessed_source);

        // Compile based on target language
        switch (options.target_language) {
            .hlsl => {
                result = try self.compileHLSL(preprocessed_source, options);
            },
            .glsl => {
                result = try self.compileGLSL(preprocessed_source, options);
            },
            .spirv => {
                result.error_message = try self.allocator.dupe(u8, "Direct SPIR-V compilation not supported");
            },
            .metal => {
                result = try self.compileMetal(preprocessed_source, options);
            },
            .wgsl => {
                result = try self.compileWGSL(preprocessed_source, options);
            },
        }

        const end_time = std.time.milliTimestamp();
        result.compilation_time_ms = @intCast(end_time - start_time);

        // Cache the result
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        // Create a copy for caching
        var cached_result = CompilationResult.init(self.allocator);
        cached_result.success = result.success;
        cached_result.compilation_time_ms = result.compilation_time_ms;
        cached_result.source_hash = result.source_hash;

        if (result.bytecode) |bytecode| {
            cached_result.bytecode = try self.allocator.dupe(u8, bytecode);
        }
        if (result.error_message) |error_msg| {
            cached_result.error_message = try self.allocator.dupe(u8, error_msg);
        }

        try self.cache.put(source_hash, cached_result);

        // Update statistics
        _ = self.total_compilations.fetchAdd(1, .monotonic);
        _ = self.compilation_time_total.fetchAdd(result.compilation_time_ms, .monotonic);

        return result;
    }

    fn compileHLSL(self: *Self, source: []const u8, options: CompilationOptions) !CompilationResult {
        var result = CompilationResult.init(self.allocator);

        if (self.dxc_path == null) {
            result.error_message = try self.allocator.dupe(u8, "DXC compiler path not set");
            return result;
        }

        // Create temporary files for input and output
        const temp_dir = std.fs.cwd().makeOpenPath("temp_shaders", .{}) catch |err| {
            result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to create temp directory: {}", .{err});
            return result;
        };
        defer temp_dir.close();

        const input_filename = try std.fmt.allocPrint(self.allocator, "shader_{}.hlsl", .{std.time.milliTimestamp()});
        defer self.allocator.free(input_filename);

        const output_filename = try std.fmt.allocPrint(self.allocator, "shader_{}.dxbc", .{std.time.milliTimestamp()});
        defer self.allocator.free(output_filename);

        // Write source to temporary file
        temp_dir.writeFile(input_filename, source) catch |err| {
            result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to write shader source: {}", .{err});
            return result;
        };
        defer temp_dir.deleteFile(input_filename) catch {};

        // Build DXC command
        var args = ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.dxc_path.?);
        try args.append(input_filename);
        try args.append("-T");
        try args.append(options.target_stage.getHLSLTarget());
        try args.append("-E");
        try args.append(options.entry_point);
        try args.append(options.optimization_level.getHLSLFlag());
        try args.append("-Fo");
        try args.append(output_filename);

        if (options.debug_info) {
            try args.append("-Zi");
        }

        // Add defines
        var define_iter = options.defines.iterator();
        while (define_iter.next()) |entry| {
            const define_arg = try std.fmt.allocPrint(self.allocator, "-D{}={s}", .{ entry.key_ptr.*, entry.value_ptr.* });
            defer self.allocator.free(define_arg);
            try args.append(define_arg);
        }

        // Execute DXC
        const exec_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args.items,
            .cwd_dir = temp_dir,
        }) catch |err| {
            result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to execute DXC: {}", .{err});
            return result;
        };
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited == 0) {
            // Compilation successful, read bytecode
            result.bytecode = temp_dir.readFileAlloc(self.allocator, output_filename, 10 * 1024 * 1024) catch |err| {
                result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to read compiled bytecode: {}", .{err});
                return result;
            };
            result.success = true;

            // Clean up output file
            temp_dir.deleteFile(output_filename) catch {};
        } else {
            // Compilation failed
            result.error_message = try self.allocator.dupe(u8, exec_result.stderr);
        }

        return result;
    }

    fn compileGLSL(self: *Self, source: []const u8, options: CompilationOptions) !CompilationResult {
        var result = CompilationResult.init(self.allocator);

        if (self.glslc_path == null) {
            result.error_message = try self.allocator.dupe(u8, "glslc compiler path not set");
            return result;
        }

        // Add GLSL version and stage defines
        const stage_prefix = options.target_stage.getGLSLStage();
        const full_source = try std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ stage_prefix, source });
        defer self.allocator.free(full_source);

        // Create temporary files
        const temp_dir = std.fs.cwd().makeOpenPath("temp_shaders", .{}) catch |err| {
            result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to create temp directory: {}", .{err});
            return result;
        };
        defer temp_dir.close();

        const input_filename = try std.fmt.allocPrint(self.allocator, "shader_{}.glsl", .{std.time.milliTimestamp()});
        defer self.allocator.free(input_filename);

        const output_filename = try std.fmt.allocPrint(self.allocator, "shader_{}.spv", .{std.time.milliTimestamp()});
        defer self.allocator.free(output_filename);

        // Write source
        temp_dir.writeFile(input_filename, full_source) catch |err| {
            result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to write shader source: {}", .{err});
            return result;
        };
        defer temp_dir.deleteFile(input_filename) catch {};

        // Build glslc command
        var args = ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.glslc_path.?);
        try args.append(input_filename);
        try args.append("-o");
        try args.append(output_filename);
        try args.append(options.optimization_level.getGLSLFlag());

        if (options.debug_info) {
            try args.append("-g");
        }

        // Execute glslc
        const exec_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args.items,
            .cwd_dir = temp_dir,
        }) catch |err| {
            result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to execute glslc: {}", .{err});
            return result;
        };
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited == 0) {
            result.bytecode = temp_dir.readFileAlloc(self.allocator, output_filename, 10 * 1024 * 1024) catch |err| {
                result.error_message = try std.fmt.allocPrint(self.allocator, "Failed to read compiled SPIR-V: {}", .{err});
                return result;
            };
            result.success = true;
            temp_dir.deleteFile(output_filename) catch {};
        } else {
            result.error_message = try self.allocator.dupe(u8, exec_result.stderr);
        }

        return result;
    }

    fn compileMetal(self: *Self, source: []const u8, options: CompilationOptions) !CompilationResult {
        var result = CompilationResult.init(self.allocator);

        // Metal shaders are typically compiled at runtime by the Metal framework
        // For now, just validate the source syntax
        _ = source;
        _ = options;

        result.error_message = try self.allocator.dupe(u8, "Metal shader compilation not implemented");
        return result;
    }

    fn compileWGSL(self: *Self, source: []const u8, options: CompilationOptions) !CompilationResult {
        var result = CompilationResult.init(self.allocator);

        // WGSL compilation would typically use the browser's WebGPU implementation
        // or a standalone WGSL validator
        _ = source;
        _ = options;

        result.error_message = try self.allocator.dupe(u8, "WGSL shader compilation not implemented");
        return result;
    }

    pub fn getStatistics(self: *const Self) CompilerStats {
        return CompilerStats{
            .total_compilations = self.total_compilations.load(.monotonic),
            .cache_hits = self.cache_hits.load(.monotonic),
            .total_compilation_time_ms = self.compilation_time_total.load(.monotonic),
            .cache_size = self.cache.count(),
        };
    }

    pub fn clearCache(self: *Self) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        var cache_iter = self.cache.valueIterator();
        while (cache_iter.next()) |result| {
            result.deinit();
        }
        self.cache.clearAndFree();
    }
};

/// Compiler statistics
pub const CompilerStats = struct {
    total_compilations: u64,
    cache_hits: u64,
    total_compilation_time_ms: u64,
    cache_size: usize,

    pub fn getCacheHitRate(self: CompilerStats) f32 {
        if (self.total_compilations == 0) return 0.0;
        return @as(f32, @floatFromInt(self.cache_hits)) / @as(f32, @floatFromInt(self.total_compilations));
    }

    pub fn getAverageCompilationTime(self: CompilerStats) f32 {
        const actual_compilations = self.total_compilations - self.cache_hits;
        if (actual_compilations == 0) return 0.0;
        return @as(f32, @floatFromInt(self.total_compilation_time_ms)) / @as(f32, @floatFromInt(actual_compilations));
    }
};

// Tests
test "shader compilation options" {
    const testing = std.testing;

    var options = CompilationOptions.init(testing.allocator, .hlsl, .vertex);
    defer options.deinit();

    try options.addDefine("TEST_DEFINE", "1");
    try testing.expect(options.defines.count() == 1);
}

test "include resolver" {
    const testing = std.testing;

    var resolver = IncludeResolver.init(testing.allocator);
    defer resolver.deinit();

    try resolver.addIncludePath("shaders/");

    const source = "#include \"common.hlsl\"\nfloat4 main() : SV_Position { return float4(0,0,0,1); }";
    const processed = try resolver.preprocessSource(source);
    defer testing.allocator.free(processed);

    try testing.expect(processed.len > 0);
}

test "compiler statistics" {
    const testing = std.testing;

    const stats = CompilerStats{
        .total_compilations = 100,
        .cache_hits = 80,
        .total_compilation_time_ms = 5000,
        .cache_size = 50,
    };

    try testing.expect(stats.getCacheHitRate() == 0.8);
    try testing.expect(stats.getAverageCompilationTime() == 250.0);
}
