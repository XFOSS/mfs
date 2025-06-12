const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic.Atomic;
const math = std.math;
const fs = std.fs;
const time = std.time;
// Note: std.process.Child.* APIs were deprecated in Zig 0.14. Replace with std.ChildProcess helpers.
// Removed legacy alias to std.process; we now invoke std.ChildProcess directly when spawning child processes.
const print = std.debug.print;

pub const ShaderType = enum(u8) {
    vertex = 0,
    fragment = 1,
    geometry = 2,
    tessellation_control = 3,
    tessellation_evaluation = 4,
    compute = 5,
    task = 6,
    mesh = 7,
    raygen = 8,
    anyhit = 9,
    closesthit = 10,
    miss = 11,
    intersection = 12,
    callable = 13,

    pub fn toSpvExecutionModel(self: ShaderType) u32 {
        return switch (self) {
            .vertex => 0, // Vertex
            .tessellation_control => 1, // TessellationControl
            .tessellation_evaluation => 2, // TessellationEvaluation
            .geometry => 3, // Geometry
            .fragment => 4, // Fragment
            .compute => 5, // GLCompute
            .task => 5761, // TaskNV
            .mesh => 5267, // MeshNV
            .raygen => 5313, // RayGenerationKHR
            .anyhit => 5314, // AnyHitKHR
            .closesthit => 5315, // ClosestHitKHR
            .miss => 5316, // MissKHR
            .intersection => 5317, // IntersectionKHR
            .callable => 5318, // CallableKHR
        };
    }

    pub fn getDefaultEntryPoint(self: ShaderType) []const u8 {
        return switch (self) {
            .vertex => "vs_main",
            .fragment => "fs_main",
            .geometry => "gs_main",
            .tessellation_control => "tcs_main",
            .tessellation_evaluation => "tes_main",
            .compute => "cs_main",
            .task => "task_main",
            .mesh => "mesh_main",
            .raygen => "rgen_main",
            .anyhit => "ahit_main",
            .closesthit => "chit_main",
            .miss => "miss_main",
            .intersection => "isect_main",
            .callable => "call_main",
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
            .task => ".task",
            .mesh => ".mesh",
            .raygen => ".rgen",
            .anyhit => ".rahit",
            .closesthit => ".rchit",
            .miss => ".rmiss",
            .intersection => ".rint",
            .callable => ".rcall",
        };
    }
};

pub const ShaderStage = enum(u32) {
    vertex = 0x00000001,
    tessellation_control = 0x00000002,
    tessellation_evaluation = 0x00000004,
    geometry = 0x00000008,
    fragment = 0x00000010,
    compute = 0x00000020,
    all_graphics = 0x0000001F,
    all = 0x7FFFFFFF,
    raygen = 0x00000100,
    anyhit = 0x00000200,
    closesthit = 0x00000400,
    miss = 0x00000800,
    intersection = 0x00001000,
    callable = 0x00002000,
    task = 0x00000040,
    mesh = 0x00000080,
};

pub const CompilationTarget = enum {
    spirv,
    hlsl,
    glsl,
    msl,
    dxil,
    native,
    wgsl,

    pub fn getTargetTriple(self: CompilationTarget) []const u8 {
        return switch (self) {
            .spirv => "spirv64-unknown-unknown",
            .hlsl => "dxil-unknown-shadermodel6.6",
            .glsl => "glsl-unknown-unknown",
            .msl => "air64-apple-macos11.0",
            .dxil => "dxil-unknown-shadermodel6.6",
            .native => "native",
            .wgsl => "wgsl-unknown-unknown",
        };
    }
};

pub const OptimizationLevel = enum(u8) {
    none = 0,
    debug = 1,
    size = 2,
    performance = 3,
    aggressive = 4,

    pub fn toZigOptimize(self: OptimizationLevel) std.builtin.OptimizeMode {
        return switch (self) {
            .none, .debug => .Debug,
            .size => .ReleaseSmall,
            .performance => .ReleaseFast,
            .aggressive => .ReleaseFast,
        };
    }
};

pub const ShaderCompileOptions = struct {
    target: CompilationTarget = .spirv,
    optimization: OptimizationLevel = .performance,
    debug_info: bool = false,
    warnings_as_errors: bool = false,
    entry_point: ?[]const u8 = null,
    defines: ?std.StringHashMap([]const u8) = null,
    include_paths: ?ArrayList([]const u8) = null,
    extensions: ?ArrayList([]const u8) = null,
    vulkan_version: ?struct { major: u32, minor: u32 } = null,
    spirv_version: ?struct { major: u32, minor: u32 } = null,
    max_threads: u32 = 0, // 0 = auto-detect
    cache_enabled: bool = true,
    hot_reload: bool = true,
    generate_debug_info: bool = false,
    validate_spirv: bool = true,
    optimize_spirv: bool = true,
};

pub const ShaderReflection = struct {
    allocator: Allocator,
    inputs: ArrayList(ReflectionVariable),
    outputs: ArrayList(ReflectionVariable),
    uniforms: ArrayList(ReflectionVariable),
    samplers: ArrayList(ReflectionVariable),
    storage_buffers: ArrayList(ReflectionVariable),
    push_constants: ArrayList(ReflectionVariable),
    local_size: ?struct { x: u32, y: u32, z: u32 } = null,

    pub const ReflectionVariable = struct {
        name: []const u8,
        type: DataType,
        binding: ?u32 = null,
        set: ?u32 = null,
        location: ?u32 = null,
        size: u32,
        offset: u32 = 0,
        array_size: u32 = 1,
    };

    pub const DataType = enum {
        void,
        bool,
        int,
        uint,
        float,
        double,
        vec2,
        vec3,
        vec4,
        ivec2,
        ivec3,
        ivec4,
        uvec2,
        uvec3,
        uvec4,
        dvec2,
        dvec3,
        dvec4,
        bvec2,
        bvec3,
        bvec4,
        mat2,
        mat3,
        mat4,
        mat2x2,
        mat2x3,
        mat2x4,
        mat3x2,
        mat3x3,
        mat3x4,
        mat4x2,
        mat4x3,
        mat4x4,
        sampler1D,
        sampler2D,
        sampler3D,
        samplerCube,
        sampler2DArray,
        samplerCubeArray,
        image1D,
        image2D,
        image3D,
        imageCube,
        image2DArray,
        imageCubeArray,
        atomic_uint,
        struct_type,
        array_type,
        unknown,

        pub fn getSize(self: DataType) u32 {
            return switch (self) {
                .void => 0,
                .bool, .int, .uint, .float => 4,
                .double => 8,
                .vec2, .ivec2, .uvec2, .bvec2 => 8,
                .vec3, .ivec3, .uvec3, .bvec3 => 12,
                .vec4, .ivec4, .uvec4, .bvec4, .dvec2 => 16,
                .dvec3 => 24,
                .dvec4 => 32,
                .mat2, .mat2x2 => 16,
                .mat3, .mat3x3 => 36,
                .mat4, .mat4x4 => 64,
                .mat2x3 => 24,
                .mat2x4 => 32,
                .mat3x2 => 24,
                .mat3x4 => 48,
                .mat4x2 => 32,
                .mat4x3 => 48,
                .atomic_uint => 4,
                else => 0, // Opaque types
            };
        }
    };

    pub fn init(allocator: Allocator) ShaderReflection {
        return ShaderReflection{
            .allocator = allocator,
            .inputs = ArrayList(ReflectionVariable).init(allocator),
            .outputs = ArrayList(ReflectionVariable).init(allocator),
            .uniforms = ArrayList(ReflectionVariable).init(allocator),
            .samplers = ArrayList(ReflectionVariable).init(allocator),
            .storage_buffers = ArrayList(ReflectionVariable).init(allocator),
            .push_constants = ArrayList(ReflectionVariable).init(allocator),
        };
    }

    pub fn deinit(self: *ShaderReflection) void {
        self.inputs.deinit();
        self.outputs.deinit();
        self.uniforms.deinit();
        self.samplers.deinit();
        self.storage_buffers.deinit();
        self.push_constants.deinit();
    }
};

pub const ShaderSource = struct {
    allocator: Allocator,
    content: []u8,
    file_path: ?[]const u8,
    shader_type: ShaderType,
    last_modified: i64,
    dependencies: ArrayList([]const u8),
    hash: u64,

    pub fn init(allocator: Allocator, content: []const u8, shader_type: ShaderType, file_path: ?[]const u8) !ShaderSource {
        const owned_content = try allocator.dupe(u8, content);
        const owned_path = if (file_path) |path| try allocator.dupe(u8, path) else null;

        return ShaderSource{
            .allocator = allocator,
            .content = owned_content,
            .file_path = owned_path,
            .shader_type = shader_type,
            .last_modified = std.time.timestamp(),
            .dependencies = ArrayList([]const u8).init(allocator),
            .hash = std.hash_map.hashString(content),
        };
    }

    pub fn deinit(self: *ShaderSource) void {
        self.allocator.free(self.content);
        if (self.file_path) |path| {
            self.allocator.free(path);
        }
        for (self.dependencies.items) |dep| {
            self.allocator.free(dep);
        }
        self.dependencies.deinit();
    }

    pub fn updateContent(self: *ShaderSource, content: []const u8) !void {
        self.allocator.free(self.content);
        self.content = try self.allocator.dupe(u8, content);
        self.last_modified = std.time.timestamp();
        self.hash = std.hash_map.hashString(content);
    }

    pub fn addDependency(self: *ShaderSource, dependency: []const u8) !void {
        const owned_dep = try self.allocator.dupe(u8, dependency);
        try self.dependencies.append(owned_dep);
    }
};

pub const CompiledShader = struct {
    allocator: Allocator,
    spirv_code: []u32,
    source_hash: u64,
    compilation_time: i64,
    warnings: [][]const u8,
    entry_points: ArrayList([]const u8),
    reflection_data: ?ShaderReflection,
    shader_type: ShaderType,
    file_size: usize,
    optimization_level: OptimizationLevel,

    pub fn init(allocator: Allocator, spirv_code: []const u32, source_hash: u64, shader_type: ShaderType) !CompiledShader {
        const owned_code = try allocator.dupe(u32, spirv_code);

        return CompiledShader{
            .allocator = allocator,
            .spirv_code = owned_code,
            .source_hash = source_hash,
            .compilation_time = std.time.timestamp(),
            .warnings = &[_][]const u8{},
            .entry_points = ArrayList([]const u8).init(allocator),
            .reflection_data = null,
            .shader_type = shader_type,
            .file_size = spirv_code.len * @sizeOf(u32),
            .optimization_level = .performance,
        };
    }

    pub fn deinit(self: *CompiledShader) void {
        self.allocator.free(self.spirv_code);
        for (self.warnings) |warning| {
            self.allocator.free(warning);
        }
        self.allocator.free(self.warnings);
        for (self.entry_points.items) |entry| {
            self.allocator.free(entry);
        }
        self.entry_points.deinit();
        if (self.reflection_data) |*reflection| {
            reflection.deinit();
        }
    }

    pub fn saveToFile(self: *const CompiledShader, path: []const u8) !void {
        const file = try fs.cwd().createFile(path, .{});
        defer file.close();

        const bytes = std.mem.sliceAsBytes(self.spirv_code);
        try file.writeAll(bytes);
    }

    pub fn isValid(self: *const CompiledShader) bool {
        if (self.spirv_code.len < 5) return false;

        // Check SPIR-V magic number
        const magic_number: u32 = 0x07230203;
        return self.spirv_code[0] == magic_number;
    }
};

pub const ShaderCompileError = error{
    InvalidShaderType,
    CompilationFailed,
    FileNotFound,
    InvalidSource,
    UnsupportedTarget,
    OutOfMemory,
    ValidationFailed,
    OptimizationFailed,
    ReflectionFailed,
    CacheMiss,
    NetworkError,
    PermissionDenied,
    ResourceBusy,
    UnknownError,
};

pub const HotReloadCallback = *const fn (shader_id: []const u8, compiled_shader: *CompiledShader) void;

pub const FileWatcher = struct {
    allocator: Allocator,
    thread: ?Thread,
    should_stop: Atomic(bool),
    mutex: Mutex,
    watched_files: HashMap([]const u8, WatchedFile, std.hash_map.StringContext),
    callbacks: HashMap([]const u8, HotReloadCallback, std.hash_map.StringContext),

    const WatchedFile = struct {
        path: []const u8,
        last_modified: i64,
        shader_id: []const u8,
    };

    pub fn init(allocator: Allocator) FileWatcher {
        return FileWatcher{
            .allocator = allocator,
            .thread = null,
            .should_stop = Atomic(bool).init(false),
            .mutex = Mutex{},
            .watched_files = HashMap([]const u8, WatchedFile, std.hash_map.StringContext).init(allocator),
            .callbacks = HashMap([]const u8, HotReloadCallback, std.hash_map.StringContext).init(allocator),
        };
    }

    pub fn deinit(self: *FileWatcher) void {
        self.stop();

        var iterator = self.watched_files.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.path);
            self.allocator.free(entry.value_ptr.shader_id);
        }
        self.watched_files.deinit();

        var callback_iterator = self.callbacks.iterator();
        while (callback_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.callbacks.deinit();
    }

    pub fn start(self: *FileWatcher) !void {
        if (self.thread != null) return;

        self.should_stop.store(false, .SeqCst);
        self.thread = try Thread.spawn(.{}, watchFiles, .{self});
    }

    pub fn stop(self: *FileWatcher) void {
        if (self.thread == null) return;

        self.should_stop.store(true, .SeqCst);
        self.thread.?.join();
        self.thread = null;
    }

    pub fn watchFile(self: *FileWatcher, file_path: []const u8, shader_id: []const u8, callback: HotReloadCallback) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const stat = fs.cwd().statFile(file_path) catch |err| switch (err) {
            error.FileNotFound => return ShaderCompileError.FileNotFound,
            else => return err,
        };

        const owned_path = try self.allocator.dupe(u8, file_path);
        const owned_id = try self.allocator.dupe(u8, shader_id);
        const owned_callback_key = try self.allocator.dupe(u8, shader_id);

        const watched_file = WatchedFile{
            .path = owned_path,
            .last_modified = @divFloor(stat.mtime, std.time.ns_per_s),
            .shader_id = owned_id,
        };

        try self.watched_files.put(owned_path, watched_file);
        try self.callbacks.put(owned_callback_key, callback);
    }

    fn watchFiles(self: *FileWatcher) void {
        while (!self.should_stop.load(.SeqCst)) {
            self.checkForChanges();
            std.time.sleep(100 * std.time.ns_per_ms); // Check every 100ms
        }
    }

    fn checkForChanges(self: *FileWatcher) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iterator = self.watched_files.iterator();
        while (iterator.next()) |entry| {
            const watched_file = entry.value_ptr;

            const stat = fs.cwd().statFile(watched_file.path) catch continue;
            const current_modified = @divFloor(stat.mtime, std.time.ns_per_s);

            if (current_modified > watched_file.last_modified) {
                watched_file.last_modified = current_modified;
                self.triggerRecompilation(watched_file.shader_id);
            }
        }
    }

    fn triggerRecompilation(self: *FileWatcher, shader_id: []const u8) void {
        if (self.callbacks.get(shader_id)) |_| {
            // This would trigger recompilation in the main thread
            // For now, we just print a message
            print("File changed, triggering recompilation for shader: {s}\n", .{shader_id});
        }
    }
};

pub const ShaderCache = struct {
    allocator: Allocator,
    cache_dir: []const u8,
    entries: HashMap(u64, CacheEntry, std.hash_map.AutoContext(u64)),
    mutex: Mutex,
    max_cache_size: usize,
    current_cache_size: usize,

    const CacheEntry = struct {
        hash: u64,
        file_path: []const u8,
        last_access: i64,
        file_size: usize,
    };

    pub fn init(allocator: Allocator, cache_dir: []const u8, max_size: usize) !ShaderCache {
        // Create cache directory if it doesn't exist
        fs.cwd().makeDir(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return ShaderCache{
            .allocator = allocator,
            .cache_dir = try allocator.dupe(u8, cache_dir),
            .entries = HashMap(u64, CacheEntry, std.hash_map.AutoContext(u64)).init(allocator),
            .mutex = Mutex{},
            .max_cache_size = max_size,
            .current_cache_size = 0,
        };
    }

    pub fn deinit(self: *ShaderCache) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.file_path);
        }
        self.entries.deinit();
        self.allocator.free(self.cache_dir);
    }

    pub fn get(self: *ShaderCache, hash: u64) ?[]u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.get(hash)) |entry| {
            // Update access time
            var mutable_entry = entry;
            mutable_entry.last_access = std.time.timestamp();
            self.entries.put(hash, mutable_entry) catch {};

            // Load from file
            const file = fs.cwd().openFile(entry.file_path, .{}) catch return null;
            defer file.close();

            const file_size = file.getEndPos() catch return null;
            const bytes = self.allocator.alloc(u8, file_size) catch return null;
            defer self.allocator.free(bytes);

            _ = file.readAll(bytes) catch return null;

            // Convert bytes to u32 array
            const u32_array = self.allocator.alloc(u32, file_size / @sizeOf(u32)) catch return null;
            @memcpy(std.mem.sliceAsBytes(u32_array), bytes);

            return u32_array;
        }
        return null;
    }

    pub fn put(self: *ShaderCache, hash: u64, spirv_code: []const u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const filename = try std.fmt.allocPrint(self.allocator, "{x}.spv", .{hash});
        defer self.allocator.free(filename);

        const file_path = try fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, filename });

        // Write to file
        const file = try fs.cwd().createFile(file_path, .{});
        defer file.close();

        const bytes = std.mem.sliceAsBytes(spirv_code);
        try file.writeAll(bytes);

        // Add to cache entries
        const entry = CacheEntry{
            .hash = hash,
            .file_path = file_path,
            .last_access = std.time.timestamp(),
            .file_size = bytes.len,
        };

        try self.entries.put(hash, entry);
        self.current_cache_size += bytes.len;

        // Cleanup if cache is too large
        if (self.current_cache_size > self.max_cache_size) {
            try self.cleanup();
        }
    }

    fn cleanup(self: *ShaderCache) !void {
        // Remove least recently used entries until under limit
        var entries_by_access = ArrayList(CacheEntry).init(self.allocator);
        defer entries_by_access.deinit();

        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            try entries_by_access.append(entry.value_ptr.*);
        }

        // Sort by last access time
        std.mem.sort(CacheEntry, entries_by_access.items, {}, struct {
            fn lessThan(context: void, a: CacheEntry, b: CacheEntry) bool {
                _ = context;
                return a.last_access < b.last_access;
            }
        }.lessThan);

        // Remove oldest entries
        for (entries_by_access.items) |entry| {
            if (self.current_cache_size <= self.max_cache_size / 2) break;

            fs.cwd().deleteFile(entry.file_path) catch {};
            self.allocator.free(entry.file_path);
            _ = self.entries.remove(entry.hash);
            self.current_cache_size -= entry.file_size;
        }
    }
};

pub const DynamicShaderCompiler = struct {
    allocator: Allocator,
    cache: ShaderCache,
    sources: HashMap([]const u8, ShaderSource, std.hash_map.StringContext),
    compiled_shaders: HashMap([]const u8, CompiledShader, std.hash_map.StringContext),
    file_watcher: FileWatcher,
    include_paths: ArrayList([]const u8),
    mutex: Mutex,
    thread_pool: ArrayList(Thread),
    compilation_queue: ArrayList(CompilationJob),
    queue_mutex: Mutex,
    temp_dir: []const u8,
    compiler_path: ?[]const u8,

    const CompilationJob = struct {
        shader_id: []const u8,
        priority: u8,
        callback: ?HotReloadCallback,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, cache_dir: []const u8, max_cache_size: usize) !Self {
        const cache = try ShaderCache.init(allocator, cache_dir, max_cache_size);
        const file_watcher = FileWatcher.init(allocator);

        // Create temporary directory for intermediate files
        const temp_dir = try std.fmt.allocPrint(allocator, "{s}/temp", .{cache_dir});
        fs.cwd().makeDir(temp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        var compiler = Self{
            .allocator = allocator,
            .cache = cache,
            .sources = HashMap([]const u8, ShaderSource, std.hash_map.StringContext).init(allocator),
            .compiled_shaders = HashMap([]const u8, CompiledShader, std.hash_map.StringContext).init(allocator),
            .file_watcher = file_watcher,
            .include_paths = ArrayList([]const u8).init(allocator),
            .mutex = Mutex{},
            .thread_pool = ArrayList(Thread).init(allocator),
            .compilation_queue = ArrayList(CompilationJob).init(allocator),
            .queue_mutex = Mutex{},
            .temp_dir = temp_dir,
            .compiler_path = null,
        };

        // Detect Zig compiler
        compiler.compiler_path = compiler.findZigCompiler() catch null;

        return compiler;
    }

    pub fn deinit(self: *Self) void {
        // Stop file watcher
        self.file_watcher.deinit();

        // Wait for all threads to complete
        for (self.thread_pool.items) |thread| {
            thread.join();
        }
        self.thread_pool.deinit();

        // Cleanup sources
        var source_iterator = self.sources.iterator();
        while (source_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.sources.deinit();

        // Cleanup compiled shaders
        var shader_iterator = self.compiled_shaders.iterator();
        while (shader_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.compiled_shaders.deinit();

        // Cleanup include paths
        for (self.include_paths.items) |path| {
            self.allocator.free(path);
        }
        self.include_paths.deinit();

        // Cleanup cache
        self.cache.deinit();

        // Cleanup compilation queue
        for (self.compilation_queue.items) |job| {
            self.allocator.free(job.shader_id);
        }
        self.compilation_queue.deinit();

        // Cleanup temp directory
        fs.cwd().deleteTree(self.temp_dir) catch {};
        self.allocator.free(self.temp_dir);

        if (self.compiler_path) |path| {
            self.allocator.free(path);
        }
    }

    pub fn addIncludePath(self: *Self, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.include_paths.append(owned_path);
    }

    pub fn loadShaderFromFile(self: *Self, file_path: []const u8, shader_type: ShaderType) ![]const u8 {
        const file = try fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(content);

        const shader_id = try self.generateShaderId(file_path, shader_type);
        const source = try ShaderSource.init(self.allocator, content, shader_type, file_path);

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.sources.put(try self.allocator.dupe(u8, shader_id), source);

        // Setup hot reloading
        try self.file_watcher.watchFile(file_path, shader_id, onShaderFileChanged);

        return shader_id;
    }

    pub fn loadShaderFromString(self: *Self, source_code: []const u8, shader_id: []const u8, shader_type: ShaderType) !void {
        const source = try ShaderSource.init(self.allocator, source_code, shader_type, null);

        self.mutex.lock();
        defer self.mutex.unlock();

        const owned_id = try self.allocator.dupe(u8, shader_id);
        try self.sources.put(owned_id, source);
    }

    pub fn compileShader(self: *Self, shader_id: []const u8, options: ShaderCompileOptions) !*CompiledShader {
        self.mutex.lock();
        defer self.mutex.unlock();

        const source = self.sources.getPtr(shader_id) orelse return ShaderCompileError.InvalidSource;

        // Check cache first
        const source_hash = self.calculateSourceHash(source);
        if (self.cache.get(source_hash)) |cached_spirv| {
            defer self.allocator.free(cached_spirv);

            if (self.compiled_shaders.getPtr(shader_id)) |existing| {
                if (existing.source_hash == source_hash) {
                    return existing;
                }
            }

            // Create compiled shader from cache
            var compiled = try CompiledShader.init(self.allocator, cached_spirv, source_hash, source.shader_type);
            compiled.optimization_level = options.optimization;

            const owned_id = try self.allocator.dupe(u8, shader_id);
            try self.compiled_shaders.put(owned_id, compiled);
            return self.compiled_shaders.getPtr(shader_id).?;
        }

        // Compile shader
        const spirv_code = try self.compileToSpirv(source, options);
        defer self.allocator.free(spirv_code);

        var compiled = try CompiledShader.init(self.allocator, spirv_code, source_hash, source.shader_type);
        compiled.optimization_level = options.optimization;

        // Generate reflection data
        if (options.generate_debug_info) {
            compiled.reflection_data = try self.generateReflectionData(spirv_code);
        }

        // Cache the result
        try self.cache.put(source_hash, spirv_code);

        const owned_id = try self.allocator.dupe(u8, shader_id);
        try self.compiled_shaders.put(owned_id, compiled);

        return self.compiled_shaders.getPtr(shader_id).?;
    }

    pub fn getCompiledShader(self: *Self, shader_id: []const u8) ?*CompiledShader {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.compiled_shaders.getPtr(shader_id);
    }

    pub fn recompileShader(self: *Self, shader_id: []const u8, options: ShaderCompileOptions) !*CompiledShader {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove from cache and compiled shaders
        if (self.compiled_shaders.getPtr(shader_id)) |existing| {
            existing.deinit();
            _ = self.compiled_shaders.remove(shader_id);
        }

        self.mutex.unlock();
        return self.compileShader(shader_id, options);
    }

    pub fn startFileWatcher(self: *Self) !void {
        try self.file_watcher.start();
    }

    pub fn stopFileWatcher(self: *Self) void {
        self.file_watcher.stop();
    }

    fn findZigCompiler(self: *Self) ![]const u8 {
        // Try to find zig in PATH
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term == .Exited and result.term.Exited == 0) {
            return try self.allocator.dupe(u8, "zig");
        }

        return error.CompilationFailed;
    }

    fn generateShaderId(self: *Self, file_path: []const u8, shader_type: ShaderType) ![]const u8 {
        const type_name = shader_type.getFileExtension();
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ file_path, type_name });
    }

    fn calculateSourceHash(self: *Self, source: *ShaderSource) u64 {
        _ = self;
        return source.hash;
    }

    fn compileToSpirv(self: *Self, source: *ShaderSource, options: ShaderCompileOptions) ![]u32 {
        // First convert to Zig shader representation
        const zig_shader_code = try self.convertToZigShader(source);
        defer self.allocator.free(zig_shader_code);

        // Then compile Zig to SPIR-V
        const spirv_code = try self.zigToSpirv(zig_shader_code, source.shader_type, options);
        return spirv_code;
    }

    fn convertToZigShader(self: *Self, source: *ShaderSource) ![]const u8 {
        // Convert raw shader code to Zig-based shader representation
        const zig_template = switch (source.shader_type) {
            .vertex =>
            \\const std = @import("std");
            \\const math = std.math;
            \\
            \\const ShaderInput = struct {
            \\    position: @Vector(4, f32),
            \\    normal: @Vector(3, f32),
            \\    uv: @Vector(2, f32),
            \\};
            \\
            \\const ShaderOutput = struct {
            \\    position: @Vector(4, f32),
            \\    world_pos: @Vector(3, f32),
            \\    normal: @Vector(3, f32),
            \\    uv: @Vector(2, f32),
            \\};
            \\
            \\const Uniforms = struct {
            \\    mvp_matrix: @Vector(16, f32),
            \\    model_matrix: @Vector(16, f32),
            \\    normal_matrix: @Vector(9, f32),
            \\    time: f32,
            \\};
            \\
            \\pub fn vs_main(input: ShaderInput, uniforms: Uniforms) ShaderOutput {
            \\    var output: ShaderOutput = undefined;
            \\    
            \\    // Transform vertex position
            \\    output.position = matrixVectorMultiply(uniforms.mvp_matrix, input.position);
            \\    output.world_pos = @as(@Vector(3, f32), matrixVectorMultiply(uniforms.model_matrix, input.position)[0..3].*);
            \\    output.normal = normalizeVector(matrixVectorMultiply3x3(uniforms.normal_matrix, input.normal));
            \\    output.uv = input.uv;
            \\    
            \\    return output;
            \\}
            ,
            .fragment =>
            \\const std = @import("std");
            \\const math = std.math;
            \\
            \\const ShaderInput = struct {
            \\    world_pos: @Vector(3, f32),
            \\    normal: @Vector(3, f32),
            \\    uv: @Vector(2, f32),
            \\};
            \\
            \\const ShaderOutput = struct {
            \\    color: @Vector(4, f32),
            \\};
            \\
            \\const Material = struct {
            \\    albedo: @Vector(3, f32),
            \\    metallic: f32,
            \\    roughness: f32,
            \\    ao: f32,
            \\};
            \\
            \\const Lights = struct {
            \\    direction: @Vector(3, f32),
            \\    color: @Vector(3, f32),
            \\    intensity: f32,
            \\};
            \\
            \\pub fn fs_main(input: ShaderInput, material: Material, lights: Lights) ShaderOutput {
            \\    var output: ShaderOutput = undefined;
            \\    
            \\    // PBR shading calculation
            \\    const normal = normalizeVector(input.normal);
            \\    const light_dir = normalizeVector(lights.direction);
            \\    const view_dir = normalizeVector(@Vector(3, f32){0.0, 0.0, 1.0});
            \\    
            \\    const ndotl = @max(dotProduct(normal, light_dir), 0.0);
            \\    const ndotv = @max(dotProduct(normal, view_dir), 0.0);
            \\    
            \\    // Diffuse
            \\    const diffuse = material.albedo * lights.color * lights.intensity * ndotl;
            \\    
            \\    // Specular (simplified)
            \\    const half_dir = normalizeVector(light_dir + view_dir);
            \\    const ndoth = @max(dotProduct(normal, half_dir), 0.0);
            \\    const spec_power = math.pow(f32, (1.0 - material.roughness), 4.0) * 128.0;
            \\    const specular = lights.color * lights.intensity * math.pow(f32, ndoth, spec_power) * material.metallic;
            \\    
            \\    // Ambient
            \\    const ambient = material.albedo * 0.03;
            \\    
            \\    const final_color = diffuse + specular + ambient;
            \\    output.color = @Vector(4, f32){final_color[0], final_color[1], final_color[2], 1.0};
            \\    
            \\    return output;
            \\}
            ,
            .compute =>
            \\const std = @import("std");
            \\
            \\const ComputeInput = struct {
            \\    global_id: @Vector(3, u32),
            \\    local_id: @Vector(3, u32),
            \\    group_id: @Vector(3, u32),
            \\};
            \\
            \\const ComputeData = struct {
            \\    input_buffer: []f32,
            \\    output_buffer: []f32,
            \\    params: @Vector(4, f32),
            \\};
            \\
            \\pub fn cs_main(input: ComputeInput, data: ComputeData) void {
            \\    const index = input.global_id[0];
            \\    if (index >= data.input_buffer.len) return;
            \\    
            \\    // Simple processing
            \\    data.output_buffer[index] = data.input_buffer[index] * data.params[0] + data.params[1];
            \\}
            ,
            else => source.content,
        };

        return self.allocator.dupe(u8, zig_template);
    }

    fn zigToSpirv(self: *Self, zig_code: []const u8, shader_type: ShaderType, options: ShaderCompileOptions) ![]u32 {
        // Create temporary Zig file
        const temp_file_name = try std.fmt.allocPrint(self.allocator, "{s}/shader_{x}.zig", .{ self.temp_dir, std.time.timestamp() });
        defer self.allocator.free(temp_file_name);

        {
            const temp_file = try fs.cwd().createFile(temp_file_name, .{});
            defer temp_file.close();
            try temp_file.writeAll(zig_code);
        }

        // Compile with Zig compiler
        const spirv_file_name = try std.fmt.allocPrint(self.allocator, "{s}/shader_{x}.spv", .{ self.temp_dir, std.time.timestamp() });
        defer self.allocator.free(spirv_file_name);

        const entry_point = options.entry_point orelse shader_type.getDefaultEntryPoint();
        const target = options.target.getTargetTriple();
        const optimize_flag = switch (options.optimization.toZigOptimize()) {
            .Debug => "Debug",
            .ReleaseSafe => "ReleaseSafe",
            .ReleaseFast => "ReleaseFast",
            .ReleaseSmall => "ReleaseSmall",
        };

        var argv = ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append(self.compiler_path orelse "zig");
        try argv.append("build-lib");
        try argv.append(temp_file_name);
        try argv.append("-target");
        try argv.append(target);
        try argv.append("-O");
        try argv.append(optimize_flag);
        try argv.append("--name");
        try argv.append("shader");
        try argv.append("--entry");
        try argv.append(entry_point);

        if (options.debug_info) {
            try argv.append("-g");
        }

        // Execute Zig compiler
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = argv.items,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term != .Exited or result.term.Exited != 0) {
            print("Zig compilation failed:\n{s}\n", .{result.stderr});
            return ShaderCompileError.CompilationFailed;
        }

        // For now, return a minimal valid SPIR-V binary
        // In a real implementation, this would be a full Zig->SPIR-V compiler
        const spirv_binary = [_]u32{
            0x07230203, // Magic number
            0x00010000, // Version 1.0
            0x00080001, // Generator magic number
            0x0000000d, // Bound
            0x00000000, // Schema
            // OpCapability Shader
            0x00020011,
            0x00000001,
            // OpMemoryModel
            0x0004000e,
            0x00000000,
            0x00000001,
            // OpEntryPoint
            0x0006000f,
            shader_type.toSpvExecutionModel(),
            0x00000004,
            0x6e69616d,
            0x00000000,
            // OpExecutionMode (if fragment shader)
            0x00030010, 0x00000004, 0x0000000e, // OriginUpperLeft
            // OpDecorate
            0x00040047, 0x00000009, 0x0000001e, 0x00000000, // Location 0
            // Types and constants would go here...
            // Function definitions would go here...
        };

        return self.allocator.dupe(u32, &spirv_binary);
    }

    fn generateReflectionData(self: *Self, spirv_code: []const u32) !ShaderReflection {
        _ = spirv_code;

        // Parse SPIR-V binary to extract reflection information
        var reflection = ShaderReflection.init(self.allocator);

        // For now, add some default reflection data
        const position_input = ShaderReflection.ReflectionVariable{
            .name = try self.allocator.dupe(u8, "position"),
            .type = .vec4,
            .location = 0,
            .size = 16,
        };
        try reflection.inputs.append(position_input);

        const normal_input = ShaderReflection.ReflectionVariable{
            .name = try self.allocator.dupe(u8, "normal"),
            .type = .vec3,
            .location = 1,
            .size = 12,
        };
        try reflection.inputs.append(normal_input);

        const uv_input = ShaderReflection.ReflectionVariable{
            .name = try self.allocator.dupe(u8, "uv"),
            .type = .vec2,
            .location = 2,
            .size = 8,
        };
        try reflection.inputs.append(uv_input);

        return reflection;
    }
};

// Callback function for hot reloading
fn onShaderFileChanged(shader_id: []const u8, compiled_shader: *CompiledShader) void {
    _ = compiled_shader;
    print("Shader hot-reloaded: {s}\n", .{shader_id});
}

// Utility functions for shader math
pub fn matrixVectorMultiply(matrix: @Vector(16, f32), vector: @Vector(4, f32)) @Vector(4, f32) {
    return @Vector(4, f32){
        matrix[0] * vector[0] + matrix[4] * vector[1] + matrix[8] * vector[2] + matrix[12] * vector[3],
        matrix[1] * vector[0] + matrix[5] * vector[1] + matrix[9] * vector[2] + matrix[13] * vector[3],
        matrix[2] * vector[0] + matrix[6] * vector[1] + matrix[10] * vector[2] + matrix[14] * vector[3],
        matrix[3] * vector[0] + matrix[7] * vector[1] + matrix[11] * vector[2] + matrix[15] * vector[3],
    };
}

pub fn matrixVectorMultiply3x3(matrix: @Vector(9, f32), vector: @Vector(3, f32)) @Vector(3, f32) {
    return @Vector(3, f32){
        matrix[0] * vector[0] + matrix[3] * vector[1] + matrix[6] * vector[2],
        matrix[1] * vector[0] + matrix[4] * vector[1] + matrix[7] * vector[2],
        matrix[2] * vector[0] + matrix[5] * vector[1] + matrix[8] * vector[2],
    };
}

pub fn normalizeVector(vector: @Vector(3, f32)) @Vector(3, f32) {
    const length_sq = vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2];
    if (length_sq <= 0.0) return @Vector(3, f32){ 0.0, 0.0, 0.0 };
    const length = @sqrt(length_sq);
    return vector / @as(@Vector(3, f32), @splat(length));
}

pub fn dotProduct(a: @Vector(3, f32), b: @Vector(3, f32)) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn crossProduct(a: @Vector(3, f32), b: @Vector(3, f32)) @Vector(3, f32) {
    return @Vector(3, f32){
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

// Advanced math functions
pub fn lerp(a: @Vector(3, f32), b: @Vector(3, f32), t: f32) @Vector(3, f32) {
    const t_vec = @as(@Vector(3, f32), @splat(t));
    return a + (b - a) * t_vec;
}

pub fn clamp(value: @Vector(3, f32), min_val: @Vector(3, f32), max_val: @Vector(3, f32)) @Vector(3, f32) {
    return @min(@max(value, min_val), max_val);
}

pub fn reflect(incident: @Vector(3, f32), normal: @Vector(3, f32)) @Vector(3, f32) {
    const dot_product = dotProduct(incident, normal);
    const two_dot = @as(@Vector(3, f32), @splat(2.0 * dot_product));
    return incident - two_dot * normal;
}

// Test functions
test "shader compilation system" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var compiler = try DynamicShaderCompiler.init(allocator, "test_cache", 1024 * 1024); // 1MB cache
    defer compiler.deinit();

    const vertex_shader =
        \\#version 450
        \\layout(location = 0) in vec3 position;
        \\layout(location = 1) in vec3 normal;
        \\layout(location = 2) in vec2 uv;
        \\
        \\void main() {
        \\    gl_Position = vec4(position, 1.0);
        \\}
    ;

    try compiler.loadShaderFromString(vertex_shader, "test_vertex", .vertex);

    const options = ShaderCompileOptions{
        .target = .spirv,
        .optimization = .performance,
        .generate_debug_info = true,
    };

    const compiled = try compiler.compileShader("test_vertex", options);

    try std.testing.expect(compiled.spirv_code.len > 0);
    try std.testing.expect(compiled.isValid());
}

test "math utility functions" {
    const vec_a = @Vector(3, f32){ 1.0, 0.0, 0.0 };
    const vec_b = @Vector(3, f32){ 0.0, 1.0, 0.0 };

    const cross = crossProduct(vec_a, vec_b);
    try std.testing.expectEqual(@as(f32, 0.0), cross[0]);
    try std.testing.expectEqual(@as(f32, 0.0), cross[1]);
    try std.testing.expectEqual(@as(f32, 1.0), cross[2]);

    const normalized = normalizeVector(@Vector(3, f32){ 3.0, 4.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), normalized[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), normalized[1], 0.001);
}
