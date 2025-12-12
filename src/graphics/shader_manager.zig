//! Shader Management System for MFS Engine
//! Provides shader loading, compilation, and runtime management
//! @thread-safe Shader operations are thread-safe with proper synchronization
//! @symbol ShaderManager - Main shader management interface

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

/// Shader handle for referencing loaded shaders
pub const ShaderHandle = u32;

/// Invalid shader handle constant
pub const INVALID_SHADER: ShaderHandle = 0;

/// Shader types supported by the engine
pub const ShaderType = enum {
    vertex,
    fragment,
    geometry,
    compute,
    tessellation_control,
    tessellation_evaluation,

    pub fn toString(self: ShaderType) []const u8 {
        return switch (self) {
            .vertex => "Vertex",
            .fragment => "Fragment",
            .geometry => "Geometry",
            .compute => "Compute",
            .tessellation_control => "Tessellation Control",
            .tessellation_evaluation => "Tessellation Evaluation",
        };
    }

    pub fn getFileExtension(self: ShaderType) []const u8 {
        return switch (self) {
            .vertex => ".vert",
            .fragment => ".frag",
            .geometry => ".geom",
            .compute => ".comp",
            .tessellation_control => ".tesc",
            .tessellation_evaluation => ".tese",
        };
    }
};

/// Shader compilation status
pub const CompilationStatus = enum {
    pending,
    compiling,
    success,
    failed,
    cache_hit,
};

/// Shader resource binding information
pub const ShaderBinding = struct {
    name: []const u8,
    binding_point: u32,
    descriptor_set: u32,
    binding_type: BindingType,
    array_size: u32 = 1,

    pub const BindingType = enum {
        uniform_buffer,
        storage_buffer,
        texture_2d,
        texture_cube,
        texture_3d,
        texture_array,
        sampler,
        combined_image_sampler,
        storage_image,
        input_attachment,
    };
};

/// Shader reflection data
pub const ShaderReflection = struct {
    bindings: ArrayList(ShaderBinding),
    input_attributes: ArrayList(InputAttribute),
    output_attributes: ArrayList(OutputAttribute),
    push_constants_size: u32,
    local_workgroup_size: [3]u32, // For compute shaders

    pub const InputAttribute = struct {
        name: []const u8,
        location: u32,
        format: AttributeFormat,
    };

    pub const OutputAttribute = struct {
        name: []const u8,
        location: u32,
        format: AttributeFormat,
    };

    pub const AttributeFormat = enum {
        float1,
        float2,
        float3,
        float4,
        int1,
        int2,
        int3,
        int4,
        uint1,
        uint2,
        uint3,
        uint4,
    };

    pub fn init(allocator: Allocator) ShaderReflection {
        return ShaderReflection{
            .bindings = ArrayList(ShaderBinding).init(allocator),
            .input_attributes = ArrayList(InputAttribute).init(allocator),
            .output_attributes = ArrayList(OutputAttribute).init(allocator),
            .push_constants_size = 0,
            .local_workgroup_size = .{ 1, 1, 1 },
        };
    }

    pub fn deinit(self: *ShaderReflection, allocator: Allocator) void {
        // Free binding names
        for (self.bindings.items) |binding| {
            allocator.free(binding.name);
        }
        self.bindings.deinit();

        // Free attribute names
        for (self.input_attributes.items) |attr| {
            allocator.free(attr.name);
        }
        self.input_attributes.deinit();

        for (self.output_attributes.items) |attr| {
            allocator.free(attr.name);
        }
        self.output_attributes.deinit();
    }
};

/// Compiled shader data
pub const CompiledShader = struct {
    handle: ShaderHandle,
    shader_type: ShaderType,
    source_path: []const u8,
    source_hash: u64,
    bytecode: []u8,
    reflection: ShaderReflection,
    compilation_status: CompilationStatus,
    error_message: ?[]const u8,
    compilation_time_ms: u64,
    last_modified: i64,

    pub fn deinit(self: *CompiledShader, allocator: Allocator) void {
        allocator.free(self.source_path);
        allocator.free(self.bytecode);
        self.reflection.deinit(allocator);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Shader program combining multiple shader stages
pub const ShaderProgram = struct {
    handle: ShaderHandle,
    name: []const u8,
    vertex_shader: ?ShaderHandle = null,
    fragment_shader: ?ShaderHandle = null,
    geometry_shader: ?ShaderHandle = null,
    compute_shader: ?ShaderHandle = null,
    tessellation_control_shader: ?ShaderHandle = null,
    tessellation_evaluation_shader: ?ShaderHandle = null,
    combined_reflection: ShaderReflection,
    is_linked: bool = false,
    link_error: ?[]const u8 = null,

    pub fn deinit(self: *ShaderProgram, allocator: Allocator) void {
        allocator.free(self.name);
        self.combined_reflection.deinit(allocator);
        if (self.link_error) |error_msg| {
            allocator.free(error_msg);
        }
    }

    pub fn hasShader(self: *const ShaderProgram, shader_type: ShaderType) bool {
        return switch (shader_type) {
            .vertex => self.vertex_shader != null,
            .fragment => self.fragment_shader != null,
            .geometry => self.geometry_shader != null,
            .compute => self.compute_shader != null,
            .tessellation_control => self.tessellation_control_shader != null,
            .tessellation_evaluation => self.tessellation_evaluation_shader != null,
        };
    }

    pub fn getShader(self: *const ShaderProgram, shader_type: ShaderType) ?ShaderHandle {
        return switch (shader_type) {
            .vertex => self.vertex_shader,
            .fragment => self.fragment_shader,
            .geometry => self.geometry_shader,
            .compute => self.compute_shader,
            .tessellation_control => self.tessellation_control_shader,
            .tessellation_evaluation => self.tessellation_evaluation_shader,
        };
    }

    pub fn setShader(self: *ShaderProgram, shader_type: ShaderType, shader_handle: ShaderHandle) void {
        switch (shader_type) {
            .vertex => self.vertex_shader = shader_handle,
            .fragment => self.fragment_shader = shader_handle,
            .geometry => self.geometry_shader = shader_handle,
            .compute => self.compute_shader = shader_handle,
            .tessellation_control => self.tessellation_control_shader = shader_handle,
            .tessellation_evaluation => self.tessellation_evaluation_shader = shader_handle,
        }
        self.is_linked = false; // Need to relink when shaders change
    }
};

/// Shader hot-reload watcher
pub const ShaderWatcher = struct {
    const Self = @This();

    watched_files: AutoHashMap([]const u8, WatchedFile),
    allocator: Allocator,
    mutex: Mutex,

    const WatchedFile = struct {
        path: []const u8,
        last_modified: i64,
        shader_handle: ShaderHandle,
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .watched_files = AutoHashMap([]const u8, WatchedFile).init(allocator),
            .allocator = allocator,
            .mutex = Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.watched_files.keyIterator();
        while (iter.next()) |path| {
            self.allocator.free(path.*);
        }
        self.watched_files.deinit();
    }

    pub fn watchFile(self: *Self, path: []const u8, shader_handle: ShaderHandle) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const owned_path = try self.allocator.dupe(u8, path);

        const stat = std.fs.cwd().statFile(path) catch |err| {
            self.allocator.free(owned_path);
            return err;
        };

        const watched_file = WatchedFile{
            .path = owned_path,
            .last_modified = stat.mtime,
            .shader_handle = shader_handle,
        };

        try self.watched_files.put(owned_path, watched_file);
    }

    pub fn checkForChanges(self: *Self) !ArrayList(ShaderHandle) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var changed_shaders = ArrayList(ShaderHandle).init(self.allocator);

        var iter = self.watched_files.valueIterator();
        while (iter.next()) |watched_file| {
            const current_stat = std.fs.cwd().statFile(watched_file.path) catch continue;

            if (current_stat.mtime > watched_file.last_modified) {
                try changed_shaders.append(watched_file.shader_handle);
                watched_file.last_modified = current_stat.mtime;
            }
        }

        return changed_shaders;
    }
};

/// Main shader manager
pub const ShaderManager = struct {
    const Self = @This();

    allocator: Allocator,

    // Shader storage
    shaders: AutoHashMap(ShaderHandle, CompiledShader),
    programs: AutoHashMap(ShaderHandle, ShaderProgram),
    shader_mutex: RwLock,
    program_mutex: RwLock,

    // Handle generation
    next_shader_handle: std.atomic.Value(ShaderHandle),
    next_program_handle: std.atomic.Value(ShaderHandle),

    // Shader paths and caching
    shader_search_paths: ArrayList([]const u8),
    shader_cache_dir: []const u8,
    enable_caching: bool,

    // Hot reload support
    shader_watcher: ShaderWatcher,
    hot_reload_enabled: bool,

    // Statistics
    total_shaders_loaded: std.atomic.Value(u64),
    total_programs_created: std.atomic.Value(u64),
    cache_hits: std.atomic.Value(u64),
    compilation_time_total: std.atomic.Value(u64),

    pub fn init(allocator: Allocator, cache_dir: []const u8) !Self {
        const owned_cache_dir = try allocator.dupe(u8, cache_dir);

        // Ensure cache directory exists
        std.fs.cwd().makePath(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return Self{
            .allocator = allocator,
            .shaders = AutoHashMap(ShaderHandle, CompiledShader).init(allocator),
            .programs = AutoHashMap(ShaderHandle, ShaderProgram).init(allocator),
            .shader_mutex = RwLock{},
            .program_mutex = RwLock{},
            .next_shader_handle = std.atomic.Value(ShaderHandle).init(1),
            .next_program_handle = std.atomic.Value(ShaderHandle).init(1),
            .shader_search_paths = ArrayList([]const u8).init(allocator),
            .shader_cache_dir = owned_cache_dir,
            .enable_caching = true,
            .shader_watcher = ShaderWatcher.init(allocator),
            .hot_reload_enabled = false,
            .total_shaders_loaded = std.atomic.Value(u64).init(0),
            .total_programs_created = std.atomic.Value(u64).init(0),
            .cache_hits = std.atomic.Value(u64).init(0),
            .compilation_time_total = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up shaders
        self.shader_mutex.lock();
        var shader_iter = self.shaders.valueIterator();
        while (shader_iter.next()) |shader| {
            shader.deinit(self.allocator);
        }
        self.shaders.deinit();
        self.shader_mutex.unlock();

        // Clean up programs
        self.program_mutex.lock();
        var program_iter = self.programs.valueIterator();
        while (program_iter.next()) |program| {
            program.deinit(self.allocator);
        }
        self.programs.deinit();
        self.program_mutex.unlock();

        // Clean up search paths
        for (self.shader_search_paths.items) |path| {
            self.allocator.free(path);
        }
        self.shader_search_paths.deinit();

        self.allocator.free(self.shader_cache_dir);
        self.shader_watcher.deinit();
    }

    pub fn addSearchPath(self: *Self, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.shader_search_paths.append(owned_path);
    }

    pub fn enableHotReload(self: *Self, enabled: bool) void {
        self.hot_reload_enabled = enabled;
    }

    pub fn loadShader(self: *Self, path: []const u8, shader_type: ShaderType) !ShaderHandle {
        const zone_id = profiler.Profiler.beginZone("Load Shader");
        defer profiler.Profiler.endZone(zone_id);

        const start_time = std.time.milliTimestamp();

        // Generate new handle
        const handle = self.next_shader_handle.fetchAdd(1, .monotonic);

        // Find shader file
        const full_path = try self.findShaderFile(path);
        defer self.allocator.free(full_path);

        // Check cache first
        const source_hash = try self.calculateFileHash(full_path);
        if (self.enable_caching) {
            if (try self.loadFromCache(handle, full_path, source_hash, shader_type)) {
                _ = self.cache_hits.fetchAdd(1, .monotonic);
                return handle;
            }
        }

        // Load and compile shader
        const source = try std.fs.cwd().readFileAlloc(self.allocator, full_path, 10 * 1024 * 1024);
        defer self.allocator.free(source);

        var compiled_shader = CompiledShader{
            .handle = handle,
            .shader_type = shader_type,
            .source_path = try self.allocator.dupe(u8, full_path),
            .source_hash = source_hash,
            .bytecode = undefined,
            .reflection = ShaderReflection.init(self.allocator),
            .compilation_status = .compiling,
            .error_message = null,
            .compilation_time_ms = 0,
            .last_modified = (try std.fs.cwd().statFile(full_path)).mtime,
        };

        // Compile shader (simplified - would use actual graphics API)
        const compilation_result = try self.compileShaderSource(source, shader_type);

        compiled_shader.bytecode = compilation_result.bytecode;
        compiled_shader.compilation_status = if (compilation_result.success) .success else .failed;
        if (!compilation_result.success) {
            compiled_shader.error_message = compilation_result.error_message;
        }

        const end_time = std.time.milliTimestamp();
        compiled_shader.compilation_time_ms = @intCast(end_time - start_time);

        // Store shader
        self.shader_mutex.lock();
        defer self.shader_mutex.unlock();
        try self.shaders.put(handle, compiled_shader);

        // Cache compiled shader
        if (self.enable_caching and compilation_result.success) {
            self.saveToCache(compiled_shader) catch |err| {
                std.log.warn("Failed to cache shader {s}: {}", .{ path, err });
            };
        }

        // Setup hot reload watching
        if (self.hot_reload_enabled) {
            self.shader_watcher.watchFile(full_path, handle) catch |err| {
                std.log.warn("Failed to watch shader file {s}: {}", .{ path, err });
            };
        }

        _ = self.total_shaders_loaded.fetchAdd(1, .monotonic);
        _ = self.compilation_time_total.fetchAdd(compiled_shader.compilation_time_ms, .monotonic);

        return handle;
    }

    pub fn createProgram(self: *Self, name: []const u8) !ShaderHandle {
        const handle = self.next_program_handle.fetchAdd(1, .monotonic);

        const program = ShaderProgram{
            .handle = handle,
            .name = try self.allocator.dupe(u8, name),
            .combined_reflection = ShaderReflection.init(self.allocator),
        };

        self.program_mutex.lock();
        defer self.program_mutex.unlock();
        try self.programs.put(handle, program);

        _ = self.total_programs_created.fetchAdd(1, .monotonic);

        return handle;
    }

    pub fn attachShaderToProgram(self: *Self, program_handle: ShaderHandle, shader_handle: ShaderHandle) !void {
        self.program_mutex.lock();
        defer self.program_mutex.unlock();

        const program = self.programs.getPtr(program_handle) orelse return error.InvalidProgramHandle;

        self.shader_mutex.lockShared();
        defer self.shader_mutex.unlockShared();

        const shader = self.shaders.get(shader_handle) orelse return error.InvalidShaderHandle;

        if (shader.compilation_status != .success) {
            return error.ShaderNotCompiled;
        }

        program.setShader(shader.shader_type, shader_handle);
    }

    pub fn linkProgram(self: *Self, program_handle: ShaderHandle) !void {
        self.program_mutex.lock();
        defer self.program_mutex.unlock();

        const program = self.programs.getPtr(program_handle) orelse return error.InvalidProgramHandle;

        // Validate program has required shaders
        if (program.compute_shader == null) {
            // Graphics pipeline - needs at least vertex and fragment
            if (program.vertex_shader == null or program.fragment_shader == null) {
                program.link_error = try self.allocator.dupe(u8, "Graphics program requires vertex and fragment shaders");
                return error.LinkFailed;
            }
        }

        // Combine reflection data from all attached shaders
        try self.combineReflectionData(program);

        // Mark as linked
        program.is_linked = true;

        // TODO: Actual linking would happen here with graphics API
        std.log.info("Linking shader program {} with shaders:", .{program_handle});
        if (program.vertex_shader) |vs| std.log.info("  Vertex shader: {}", .{vs});
        if (program.fragment_shader) |fs| std.log.info("  Fragment shader: {}", .{fs});
        if (program.geometry_shader) |gs| std.log.info("  Geometry shader: {}", .{gs});
        if (program.compute_shader) |cs| std.log.info("  Compute shader: {}", .{cs});

        // In a real implementation, this would:
        // 1. Create a graphics API program object
        // 2. Attach all compiled shader objects
        // 3. Link the program
        // 4. Check for link errors
        // 5. Store the linked program handle
    }

    pub fn getShader(self: *Self, handle: ShaderHandle) ?*const CompiledShader {
        self.shader_mutex.lockShared();
        defer self.shader_mutex.unlockShared();
        return self.shaders.getPtr(handle);
    }

    pub fn getProgram(self: *Self, handle: ShaderHandle) ?*const ShaderProgram {
        self.program_mutex.lockShared();
        defer self.program_mutex.unlockShared();
        return self.programs.getPtr(handle);
    }

    pub fn checkHotReload(self: *Self) !void {
        if (!self.hot_reload_enabled) return;

        const changed_shaders = try self.shader_watcher.checkForChanges();
        defer changed_shaders.deinit();

        for (changed_shaders.items) |shader_handle| {
            try self.reloadShader(shader_handle);
        }
    }

    pub fn getStatistics(self: *const Self) ShaderManagerStats {
        return ShaderManagerStats{
            .total_shaders_loaded = self.total_shaders_loaded.load(.monotonic),
            .total_programs_created = self.total_programs_created.load(.monotonic),
            .cache_hits = self.cache_hits.load(.monotonic),
            .total_compilation_time_ms = self.compilation_time_total.load(.monotonic),
            .active_shaders = self.shaders.count(),
            .active_programs = self.programs.count(),
        };
    }

    // Private helper methods
    fn findShaderFile(self: *Self, path: []const u8) ![]u8 {
        // Try absolute path first
        if (std.fs.path.isAbsolute(path)) {
            if (std.fs.cwd().access(path, .{})) {
                return self.allocator.dupe(u8, path);
            } else |_| {}
        }

        // Search in search paths
        for (self.shader_search_paths.items) |search_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ search_path, path });
            defer self.allocator.free(full_path);

            if (std.fs.cwd().access(full_path, .{})) {
                return self.allocator.dupe(u8, full_path);
            } else |_| {}
        }

        return error.ShaderFileNotFound;
    }

    fn calculateFileHash(self: *Self, path: []const u8) !u64 {
        _ = self;
        const file_content = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 10 * 1024 * 1024);
        defer std.heap.page_allocator.free(file_content);

        return std.hash_map.hashString(file_content);
    }

    fn loadFromCache(self: *Self, handle: ShaderHandle, path: []const u8, source_hash: u64, shader_type: ShaderType) !bool {
        _ = handle;
        _ = shader_type;

        // Create cache file path based on source hash
        const cache_filename = try std.fmt.allocPrint(self.allocator, "{x}.cache", .{source_hash});
        defer self.allocator.free(cache_filename);

        const cache_path = try std.fs.path.join(self.allocator, &.{ self.shader_cache_dir, cache_filename });
        defer self.allocator.free(cache_path);

        // Try to load cached bytecode
        const cache_file = std.fs.cwd().openFile(cache_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.log.debug("No cache file found for shader: {s}", .{path});
                return false;
            }
            return err;
        };
        defer cache_file.close();

        // Read cache header to verify it's valid
        var cache_header: struct { hash: u64, timestamp: i64 } = undefined;
        _ = cache_file.readAll(std.mem.asBytes(&cache_header)) catch {
            std.log.warn("Failed to read cache header for shader: {s}", .{path});
            return false;
        };

        if (cache_header.hash != source_hash) {
            std.log.debug("Cache hash mismatch for shader: {s}", .{path});
            return false;
        }

        // Check if source file is newer than cache
        const source_stat = std.fs.cwd().statFile(path) catch {
            std.log.warn("Failed to stat source file: {s}", .{path});
            return false;
        };

        if (source_stat.mtime > cache_header.timestamp) {
            std.log.debug("Source file newer than cache for shader: {s}", .{path});
            return false;
        }

        std.log.info("Loaded shader from cache: {s}", .{path});
        self.cache_hits.fetchAdd(1, .monotonic);
        return true;
    }

    fn saveToCache(self: *Self, shader: CompiledShader) !void {
        const cache_filename = try std.fmt.allocPrint(self.allocator, "{x}.cache", .{shader.source_hash});
        defer self.allocator.free(cache_filename);

        const cache_path = try std.fs.path.join(self.allocator, &.{ self.shader_cache_dir, cache_filename });
        defer self.allocator.free(cache_path);

        // Create cache directory if it doesn't exist
        std.fs.cwd().makePath(self.shader_cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                std.log.warn("Failed to create cache directory: {}", .{err});
                return;
            }
        };

        // Write cache file
        const cache_file = std.fs.cwd().createFile(cache_path, .{}) catch |err| {
            std.log.warn("Failed to create cache file: {}", .{err});
            return;
        };
        defer cache_file.close();

        // Write cache header
        const cache_header = struct { hash: u64, timestamp: i64 }{
            .hash = shader.source_hash,
            .timestamp = std.time.timestamp(),
        };

        _ = cache_file.writeAll(std.mem.asBytes(&cache_header)) catch |err| {
            std.log.warn("Failed to write cache header: {}", .{err});
            return;
        };

        // Write bytecode
        _ = cache_file.writeAll(shader.bytecode) catch |err| {
            std.log.warn("Failed to write cache bytecode: {}", .{err});
            return;
        };

        std.log.debug("Saved shader to cache: {s}", .{cache_path});
    }

    fn compileShaderSource(self: *Self, source: []const u8, shader_type: ShaderType) !CompilationResult {
        _ = shader_type;

        // Simplified compilation - in real implementation would use graphics API
        const bytecode = try self.allocator.dupe(u8, source);

        return CompilationResult{
            .success = true,
            .bytecode = bytecode,
            .error_message = null,
        };
    }

    fn combineReflectionData(self: *Self, program: *ShaderProgram) !void {
        // Clear existing reflection data
        program.reflection.deinit(self.allocator);
        program.reflection = ShaderReflection.init(self.allocator);

        // Combine reflection data from all attached shaders
        const shader_handles = [_]?ShaderHandle{
            program.vertex_shader,
            program.fragment_shader,
            program.geometry_shader,
            program.tessellation_control_shader,
            program.tessellation_evaluation_shader,
            program.compute_shader,
        };

        for (shader_handles) |maybe_handle| {
            if (maybe_handle) |handle| {
                if (self.shaders.get(handle)) |shader| {
                    // Merge bindings
                    for (shader.reflection.bindings.items) |binding| {
                        // Check for duplicates
                        var found = false;
                        for (program.reflection.bindings.items) |existing| {
                            if (std.mem.eql(u8, existing.name, binding.name)) {
                                found = true;
                                break;
                            }
                        }

                        if (!found) {
                            const binding_copy = ShaderBinding{
                                .name = try self.allocator.dupe(u8, binding.name),
                                .binding_point = binding.binding_point,
                                .descriptor_set = binding.descriptor_set,
                                .binding_type = binding.binding_type,
                            };
                            try program.reflection.bindings.append(binding_copy);
                        }
                    }

                    // Merge attributes
                    for (shader.reflection.input_attributes.items) |attribute| {
                        // Check for duplicates
                        var found = false;
                        for (program.reflection.input_attributes.items) |existing| {
                            if (std.mem.eql(u8, existing.name, attribute.name)) {
                                found = true;
                                break;
                            }
                        }

                        if (!found) {
                            const attribute_copy = ShaderReflection.InputAttribute{
                                .name = try self.allocator.dupe(u8, attribute.name),
                                .location = attribute.location,
                                .format = attribute.format,
                            };
                            try program.reflection.input_attributes.append(attribute_copy);
                        }
                    }
                }
            }
        }

        std.log.debug("Combined reflection data: {} bindings, {} attributes", .{
            program.reflection.bindings.items.len,
            program.reflection.input_attributes.items.len,
        });
    }

    fn reloadShader(self: *Self, shader_handle: ShaderHandle) !void {
        const shader = self.shaders.getPtr(shader_handle) orelse return error.InvalidShaderHandle;

        std.log.info("Reloading shader: {s}", .{shader.source_path});

        // Re-read source file
        const source_content = try std.fs.cwd().readFileAlloc(self.allocator, shader.source_path, 10 * 1024 * 1024);
        defer self.allocator.free(source_content);

        // Calculate new hash
        const new_hash = std.hash_map.hashString(source_content);

        // Only recompile if source changed
        if (new_hash == shader.source_hash) {
            std.log.debug("Shader source unchanged, skipping reload: {s}", .{shader.source_path});
            return;
        }

        // Recompile shader
        const compilation_result = try self.compileShaderSource(source_content, shader.shader_type);

        if (!compilation_result.success) {
            std.log.err("Failed to recompile shader {s}: {s}", .{ shader.source_path, compilation_result.error_message orelse "Unknown error" });
            return;
        }

        // Update shader with new bytecode
        self.allocator.free(shader.bytecode);
        shader.bytecode = compilation_result.bytecode;
        shader.source_hash = new_hash;
        shader.compilation_status = .success;

        // Save to cache
        try self.saveToCache(shader.*);

        std.log.info("Successfully reloaded shader: {s}", .{shader.source_path});
    }

    const CompilationResult = struct {
        success: bool,
        bytecode: []u8,
        error_message: ?[]const u8,
    };
};

/// Shader manager statistics
pub const ShaderManagerStats = struct {
    total_shaders_loaded: u64,
    total_programs_created: u64,
    cache_hits: u64,
    total_compilation_time_ms: u64,
    active_shaders: usize,
    active_programs: usize,

    pub fn getCacheHitRate(self: ShaderManagerStats) f32 {
        if (self.total_shaders_loaded == 0) return 0.0;
        return @as(f32, @floatFromInt(self.cache_hits)) / @as(f32, @floatFromInt(self.total_shaders_loaded));
    }

    pub fn getAverageCompilationTime(self: ShaderManagerStats) f32 {
        const actual_compilations = self.total_shaders_loaded - self.cache_hits;
        if (actual_compilations == 0) return 0.0;
        return @as(f32, @floatFromInt(self.total_compilation_time_ms)) / @as(f32, @floatFromInt(actual_compilations));
    }
};

// Tests
test "shader manager basic operations" {
    const testing = std.testing;

    var manager = try ShaderManager.init(testing.allocator, "test_cache");
    defer manager.deinit();

    // Test program creation
    const program = try manager.createProgram("test_program");
    try testing.expect(program != INVALID_SHADER);

    const stats = manager.getStatistics();
    try testing.expect(stats.total_programs_created == 1);
}

test "shader reflection" {
    const testing = std.testing;

    var reflection = ShaderReflection.init(testing.allocator);
    defer reflection.deinit(testing.allocator);

    const binding = ShaderBinding{
        .name = try testing.allocator.dupe(u8, "test_uniform"),
        .binding_point = 0,
        .descriptor_set = 0,
        .binding_type = .uniform_buffer,
    };

    try reflection.bindings.append(binding);
    try testing.expect(reflection.bindings.items.len == 1);
}
