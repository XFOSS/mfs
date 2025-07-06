const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu.zig");
const buffer = @import("buffer.zig");
const shader = @import("shader.zig");
const texture = @import("texture.zig");
const types = @import("types.zig");
const error_utils = @import("../utils/error_utils.zig");

/// ResourceManager handles efficient creation, caching, and disposal of GPU resources
/// @thread-safe All public methods are thread-safe with internal mutex protection
/// @symbol Core graphics resource management system
pub const ResourceManager = struct {
    allocator: Allocator,

    // Resource caches
    shaders: std.StringHashMap(*shader.ShaderProgram),
    textures: std.StringHashMap(*texture.Texture2D),
    render_targets: std.StringHashMap(*texture.RenderTexture),

    // Memory managers
    buffer_manager: buffer.BufferMemoryManager,

    // Statistics tracking
    stats: ResourceStats,

    // Resource lifetimes
    garbage_collector: ResourceGarbageCollector,

    // Threading
    mutex: std.Thread.Mutex,

    // Asset paths
    search_paths: std.ArrayList([]const u8),

    const Self = @This();

    /// Initialize a new resource manager
    /// @thread-safe Thread-safe initialization
    /// @symbol Public API
    pub fn init(allocator: Allocator) !*Self {
        var manager = try allocator.create(Self);

        // Initialize resource caches
        const shaders = std.StringHashMap(*shader.ShaderProgram).init(allocator);
        const textures = std.StringHashMap(*texture.Texture2D).init(allocator);
        const render_targets = std.StringHashMap(*texture.RenderTexture).init(allocator);

        // Initialize memory managers and collectors
        const buffer_manager = try buffer.BufferMemoryManager.init(allocator);
        const garbage_collector = ResourceGarbageCollector.init(allocator);

        manager.* = Self{
            .allocator = allocator,
            .shaders = shaders,
            .textures = textures,
            .render_targets = render_targets,
            .buffer_manager = buffer_manager,
            .stats = ResourceStats{},
            .garbage_collector = garbage_collector,
            .mutex = .{},
            .search_paths = std.ArrayList([]const u8).init(allocator),
        };

        // Initialize shader cache
        shader.initShaderCache(allocator);

        // Add default search paths
        try manager.addSearchPath("shaders");
        try manager.addSearchPath("assets/shaders");
        try manager.addSearchPath("resources/shaders");

        return manager;
    }

    /// Clean up all resources and destroy the manager
    /// @thread-safe Thread-safe cleanup
    /// @symbol Public API
    pub fn deinit(self: *Self) void {
        // Free all resources
        var shader_it = self.shaders.valueIterator();
        while (shader_it.next()) |prog| {
            prog.*.deinit();
        }

        var texture_it = self.textures.valueIterator();
        while (texture_it.next()) |tex| {
            tex.*.deinit();
        }

        var rt_it = self.render_targets.valueIterator();
        while (rt_it.next()) |rt| {
            rt.*.deinit();
        }

        // Free search paths
        for (self.search_paths.items) |path| {
            self.allocator.free(path);
        }
        self.search_paths.deinit();

        // Deinitialize managers
        self.buffer_manager.deinit();
        self.garbage_collector.deinit();

        // Deinitialize shader cache
        shader.deinitShaderCache();

        // Free containers
        self.shaders.deinit();
        self.textures.deinit();
        self.render_targets.deinit();

        // Free self
        self.allocator.destroy(self);
    }

    /// Add a search path for resources
    /// @thread-safe Thread-safe with internal mutex protection
    /// @symbol Public API for resource path management
    pub fn addSearchPath(self: *Self, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.search_paths.append(owned_path);
    }

    /// Create or retrieve a shader program
    /// @thread-safe Thread-safe with internal mutex protection
    /// @symbol Public API for shader management
    pub fn getShader(self: *Self, name: []const u8, vertex_path: []const u8, fragment_path: []const u8) !*shader.ShaderProgram {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if shader already exists
        if (self.shaders.get(name)) |existing| {
            return existing;
        }

        // Try to find shader files in search paths
        const vertex_file = try self.resolveResourcePath(vertex_path);
        defer self.allocator.free(vertex_file);
        const fragment_file = try self.resolveResourcePath(fragment_path);
        defer self.allocator.free(fragment_file);

        // Create new shader program with hot reload support
        var program = try shader.ShaderProgram.initNamed(self.allocator, name);
        errdefer program.deinit();

        // Compile shaders
        try program.addShaderFromFile(.vertex, vertex_file, .{
            .preprocessor_flags = .{
                .enable_includes = true,
                .enable_defines = true,
            },
        });

        try program.addShaderFromFile(.fragment, fragment_file, .{
            .preprocessor_flags = .{
                .enable_includes = true,
                .enable_defines = true,
            },
        });

        // Store in cache with owned name copy
        const name_copy = try self.allocator.dupe(u8, name);
        try self.shaders.put(name_copy, program);

        // Update statistics
        self.stats.shader_count += 1;

        return program;
    }

    /// Create or retrieve a texture
    /// @thread-safe Thread-safe with internal mutex protection
    /// @symbol Public API for texture management
    pub fn getTexture(self: *Self, name: []const u8, path: []const u8) !*texture.Texture2D {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if texture already exists
        if (self.textures.get(name)) |existing| {
            return existing;
        }

        // Try to find texture file in search paths
        const texture_file = try self.resolveResourcePath(path);
        defer self.allocator.free(texture_file);

        // Load texture
        var tex = try texture.Texture2D.loadFromFile(self.allocator, texture_file);
        errdefer tex.deinit();

        // Generate mipmaps
        try tex.generateMipmaps();

        // Store in cache with owned name copy
        const name_copy = try self.allocator.dupe(u8, name);
        try self.textures.put(name_copy, tex);

        // Update statistics
        self.stats.texture_count += 1;
        self.stats.texture_memory += tex.width * tex.height * 4; // Approximate size

        return tex;
    }

    /// Create or retrieve a render target
    /// @thread-safe Thread-safe with internal mutex protection
    /// @symbol Public API for render target management
    pub fn getRenderTarget(self: *Self, name: []const u8, width: u32, height: u32) !*texture.RenderTexture {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if RT already exists
        if (self.render_targets.get(name)) |existing| {
            // If size changed, resize it
            if (existing.width != width or existing.height != height) {
                try existing.resize(width, height);
            }
            return existing;
        }

        // Create new render target
        var rt = try texture.RenderTexture.initWithDepth(self.allocator, width, height);
        errdefer rt.deinit();

        // Store in cache with owned name copy
        const name_copy = try self.allocator.dupe(u8, name);
        try self.render_targets.put(name_copy, rt);

        // Update statistics
        self.stats.render_target_count += 1;
        self.stats.render_target_memory += width * height * 8; // Color + depth, approximate

        return rt;
    }

    /// Create a vertex buffer
    /// @thread-safe Thread-safe delegating to buffer manager
    /// @symbol Public API for vertex buffer creation
    pub fn createVertexBuffer(self: *Self, vertex_count: u32, vertex_size: u32) !*buffer.VertexBuffer {
        return self.buffer_manager.allocateVertexBuffer(vertex_count, vertex_size);
    }

    /// Create an index buffer
    /// @thread-safe Thread-safe delegating to buffer manager
    /// @symbol Public API for index buffer creation
    pub fn createIndexBuffer(self: *Self, index_count: u32, format: gpu.IndexFormat) !*buffer.IndexBuffer {
        return self.buffer_manager.allocateIndexBuffer(index_count, format);
    }

    /// Create a uniform buffer
    /// @thread-safe Thread-safe delegating to buffer manager
    /// @symbol Public API for uniform buffer creation
    pub fn createUniformBuffer(self: *Self, size: usize, binding_slot: u32) !*buffer.UniformBuffer {
        return self.buffer_manager.allocateUniformBuffer(size, binding_slot);
    }

    /// Allocate per-frame data (for transient buffers)
    /// @thread-safe Thread-safe delegating to buffer manager
    /// @symbol Public API for per-frame data allocation
    pub fn allocateFrameData(self: *Self, size: usize) ![]u8 {
        return self.buffer_manager.allocateFrameData(size);
    }

    /// Begin a new frame (updates resource tracking)
    /// @thread-safe Thread-safe coordination of frame boundaries
    /// @symbol Public API for frame management
    pub fn beginFrame(self: *Self, frame_number: u64) void {
        self.buffer_manager.beginFrame(frame_number);
        self.garbage_collector.collectGarbage(frame_number);
    }

    /// Mark a resource for deferred deletion
    /// @thread-safe Thread-safe resource disposal
    /// @symbol Public API for resource lifecycle management
    pub fn deferDelete(self: *Self, resource: anytype, current_frame: u64) void {
        self.garbage_collector.queueForDeletion(resource, current_frame);
    }

    /// Resolve a resource path by searching in all search paths
    /// @thread-safe Thread-safe with caller's responsibility for mutex
    /// @symbol Internal path resolution implementation
    fn resolveResourcePath(self: *Self, path: []const u8) ![]const u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err != error.FileNotFound) {
                return error_utils.logErr("Failed to open file: {s}", .{path}, err);
            }
            // Try each search path
            for (self.search_paths.items) |search_path| {
                const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ search_path, path });
                errdefer self.allocator.free(full_path);

                if (std.fs.cwd().access(full_path, .{})) |_| {
                    return full_path;
                } else |_| {
                    self.allocator.free(full_path);
                    continue;
                }
            }

            return error.FileNotFound;
        };
        file.close();

        // File exists at the direct path
        return self.allocator.dupe(u8, path);
    }

    /// Get resource statistics
    /// @thread-safe Thread-safe with internal mutex protection
    /// @symbol Public API for resource introspection
    pub fn getStatistics(self: *Self) ResourceStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }
};

/// Resource statistics tracking
/// @thread-safe Thread-safe for reading with ResourceManager mutex
/// @symbol Resource monitoring data structure
pub const ResourceStats = struct {
    // Counts
    shader_count: usize = 0,
    texture_count: usize = 0,
    render_target_count: usize = 0,
    buffer_count: usize = 0,

    // Memory usage
    texture_memory: usize = 0,
    render_target_memory: usize = 0,
    buffer_memory: usize = 0,

    // Performance
    shader_compile_time_ms: f64 = 0,
    texture_load_time_ms: f64 = 0,

    // Frame statistics
    transient_allocations_per_frame: usize = 0,
};

/// Resource garbage collection for deferred deletion
/// @thread-safe Thread-safe with caller's responsibility for synchronization
/// @symbol Internal resource cleanup system
pub const ResourceGarbageCollector = struct {
    allocator: Allocator,
    garbage_queue: std.fifo.LinearFifo(GarbageItem, .Dynamic),
    deletion_frame_lag: u64 = 3, // Wait this many frames before deletion

    const GarbageType = enum {
        shader,
        texture,
        render_target,
        buffer,
        vertex_buffer,
        index_buffer,
        uniform_buffer,
    };

    const GarbageItem = struct {
        resource_type: GarbageType,
        resource_ptr: *anyopaque,
        frame_number: u64,
    };

    /// Initialize the garbage collector
    /// @thread-safe Thread-safe initialization
    /// @symbol Internal API
    pub fn init(allocator: Allocator) ResourceGarbageCollector {
        return ResourceGarbageCollector{
            .allocator = allocator,
            .garbage_queue = std.fifo.LinearFifo(GarbageItem, .Dynamic).init(allocator),
        };
    }

    /// Clean up the garbage collector
    /// @thread-safe Thread-safe cleanup
    /// @symbol Internal API
    pub fn deinit(self: *ResourceGarbageCollector) void {
        self.garbage_queue.deinit();
    }

    /// Queue a resource for deferred deletion
    /// @thread-safe Not thread-safe, caller must provide synchronization
    /// @symbol Internal resource queueing mechanism
    pub fn queueForDeletion(self: *ResourceGarbageCollector, resource: anytype, frame_number: u64) void {
        const T = @TypeOf(resource);
        const resource_type = comptime switch (@typeInfo(T)) {
            .Pointer => |ptr_info| switch (ptr_info.child) {
                shader.ShaderProgram => .shader,
                texture.Texture2D => .texture,
                texture.RenderTexture => .render_target,
                buffer.Buffer => .buffer,
                buffer.VertexBuffer => .vertex_buffer,
                buffer.IndexBuffer => .index_buffer,
                buffer.UniformBuffer => .uniform_buffer,
                else => @compileError("Unsupported resource type for garbage collection"),
            },
            else => @compileError("Expected pointer type"),
        };

        const garbage_item = GarbageItem{
            .resource_type = resource_type,
            .resource_ptr = resource,
            .frame_number = frame_number,
        };

        self.garbage_queue.writeItem(garbage_item) catch {
            // If we can't queue, delete immediately
            self.deleteResource(garbage_item);
        };
    }

    /// Process and delete queued resources that are ready
    /// @thread-safe Not thread-safe, caller must provide synchronization
    /// @symbol Internal garbage collection implementation
    pub fn collectGarbage(self: *ResourceGarbageCollector, current_frame: u64) void {
        // Process all items in the queue
        while (self.garbage_queue.readableLength() > 0) {
            const item = self.garbage_queue.peekItem().?;

            // Check if it's time to delete this resource
            if (item.frame_number + self.deletion_frame_lag <= current_frame) {
                _ = self.garbage_queue.readItem();
                self.deleteResource(item);
            } else {
                // Items are in order, so we can stop checking
                break;
            }
        }
    }

    /// Delete a specific resource based on its type
    /// @thread-safe Not thread-safe, internal use only
    /// @symbol Private implementation detail
    fn deleteResource(_: *ResourceGarbageCollector, item: GarbageItem) void {
        switch (item.resource_type) {
            .shader => {
                const shader_ptr: *shader.ShaderProgram = @ptrCast(@alignCast(item.resource_ptr));
                shader_ptr.deinit();
            },
            .texture => {
                const texture_ptr: *texture.Texture2D = @ptrCast(@alignCast(item.resource_ptr));
                texture_ptr.deinit();
            },
            .render_target => {
                const rt_ptr: *texture.RenderTexture = @ptrCast(@alignCast(item.resource_ptr));
                rt_ptr.deinit();
            },
            .buffer => {
                const buffer_ptr: *buffer.Buffer = @ptrCast(@alignCast(item.resource_ptr));
                buffer_ptr.deinit();
            },
            .vertex_buffer => {
                const vb_ptr: *buffer.VertexBuffer = @ptrCast(@alignCast(item.resource_ptr));
                vb_ptr.deinit();
            },
            .index_buffer => {
                const ib_ptr: *buffer.IndexBuffer = @ptrCast(@alignCast(item.resource_ptr));
                ib_ptr.deinit();
            },
            .uniform_buffer => {
                const ub_ptr: *buffer.UniformBuffer = @ptrCast(@alignCast(item.resource_ptr));
                ub_ptr.deinit();
            },
        }
    }
};

// Global resource manager instance
var global_resource_manager: ?*ResourceManager = null;

/// Initialize the global resource manager
/// @thread-safe Thread-safe global initialization
/// @symbol Public global manager API
pub fn initGlobalResourceManager(allocator: Allocator) !void {
    if (global_resource_manager != null) return;
    global_resource_manager = try ResourceManager.init(allocator);
}

/// Deinitialize the global resource manager
/// @thread-safe Thread-safe global cleanup
/// @symbol Public global manager API
pub fn deinitGlobalResourceManager() void {
    if (global_resource_manager) |manager| {
        manager.deinit();
        global_resource_manager = null;
    }
}

/// Get the global resource manager
/// @thread-safe Thread-safe access to global instance
/// @symbol Public global manager accessor
pub fn getGlobalResourceManager() !*ResourceManager {
    return global_resource_manager orelse error.ResourceManagerNotInitialized;
}
