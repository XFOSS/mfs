//! Enhanced Plugin Loader System
//! Provides dynamic plugin loading, hot-reloading, and thread-safe plugin management
//! @thread-safe All operations are thread-safe with appropriate synchronization
//! @symbol Public plugin management API

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.plugin_loader);

/// Enhanced ABI between the main executable and dynamic plugin shared libraries
/// Provides versioning, metadata, and extended lifecycle management
/// @symbol Plugin ABI interface
pub const PluginAPI = extern struct {
    // Core identification
    name: [*:0]const u8,
    description: [*:0]const u8,
    author: [*:0]const u8,

    // Versioning with semantic versioning support
    version_major: u32,
    version_minor: u32,
    version_patch: u32,

    // Minimum engine version required
    min_engine_version_major: u32,
    min_engine_version_minor: u32,
    min_engine_version_patch: u32,

    // Plugin capabilities and requirements
    capabilities: u32, // Bitfield of PluginCapability
    requirements: u32, // Bitfield of PluginRequirement

    // Extended lifecycle functions
    init_fn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, engine_api: *const EngineAPI) PluginError!void,
    deinit_fn: *const fn (ctx: *anyopaque) void,
    update_fn: ?*const fn (ctx: *anyopaque, dt: f64) PluginError!void,
    render_fn: ?*const fn (ctx: *anyopaque, render_ctx: *anyopaque) PluginError!void,

    // Hot-reload support
    pre_reload_fn: ?*const fn (ctx: *anyopaque) PluginError!*anyopaque, // Serialize state
    post_reload_fn: ?*const fn (ctx: *anyopaque, saved_state: *anyopaque, allocator: std.mem.Allocator) PluginError!void,

    // Event handling
    handle_event_fn: ?*const fn (ctx: *anyopaque, event: *const anyopaque) PluginError!bool,

    // Configuration and settings
    get_config_schema_fn: ?*const fn () [*:0]const u8, // JSON schema
    set_config_fn: ?*const fn (ctx: *anyopaque, config_json: [*:0]const u8) PluginError!void,
    get_config_fn: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator) PluginError![*:0]const u8,
};

/// Plugin capability flags
pub const PluginCapability = enum(u32) {
    rendering = 1 << 0,
    audio = 1 << 1,
    input = 1 << 2,
    networking = 1 << 3,
    scripting = 1 << 4,
    asset_processing = 1 << 5,
    physics = 1 << 6,
    ui = 1 << 7,

    pub fn toFlag(self: PluginCapability) u32 {
        return @intFromEnum(self);
    }
};

/// Plugin requirement flags
pub const PluginRequirement = enum(u32) {
    gpu_access = 1 << 0,
    file_access = 1 << 1,
    network_access = 1 << 2,
    system_access = 1 << 3,
    exclusive_resource = 1 << 4,

    pub fn toFlag(self: PluginRequirement) u32 {
        return @intFromEnum(self);
    }
};

/// Plugin-specific error types
pub const PluginError = error{
    InitializationFailed,
    InvalidConfiguration,
    ResourceNotAvailable,
    VersionMismatch,
    PermissionDenied,
    DependencyMissing,
    StateCorrupted,
    HotReloadFailed,
} || std.mem.Allocator.Error;

/// Engine API provided to plugins
pub const EngineAPI = struct {
    version: struct {
        major: u32,
        minor: u32,
        patch: u32,
    },

    // Memory management
    allocator: std.mem.Allocator,

    // Logging
    log_fn: *const fn (level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime fmt: []const u8, args: anytype) void,

    // Resource management
    load_asset_fn: *const fn (path: [*:0]const u8) ?*anyopaque,
    unload_asset_fn: *const fn (asset: *anyopaque) void,

    // Event system
    register_event_handler_fn: *const fn (event_type: u32, handler: *const fn (*anyopaque) void, ctx: *anyopaque) void,
    emit_event_fn: *const fn (event_type: u32, data: *const anyopaque) void,

    // Configuration
    get_config_value_fn: *const fn (key: [*:0]const u8) ?[*:0]const u8,
    set_config_value_fn: *const fn (key: [*:0]const u8, value: [*:0]const u8) void,
};

/// Enhanced plugin wrapper with metadata and state management
pub const Plugin = struct {
    // Core plugin data
    handle: ?std.DynamicLibrary = null,
    api: *const PluginAPI = undefined,
    ctx: *anyopaque = undefined,

    // Metadata and state
    id: u32,
    path: []const u8,
    last_modified: i128,
    load_time: i64,
    state: PluginState,
    error_count: u32 = 0,
    last_error: ?PluginError = null,

    // Hot-reload state
    saved_state: ?*anyopaque = null,
    reload_pending: bool = false,

    // Performance tracking
    update_time_ns: u64 = 0,
    render_time_ns: u64 = 0,

    const PluginState = enum {
        unloaded,
        loading,
        loaded,
        err,
        reloading,
        disabled,
    };

    pub fn init(id: u32, path: []const u8) Plugin {
        return Plugin{
            .id = id,
            .path = path,
            .last_modified = 0,
            .load_time = std.time.nanoTimestamp(),
            .state = .unloaded,
        };
    }

    pub fn unload(self: *Plugin, allocator: std.mem.Allocator) void {
        if (self.state == .loaded and self.api.deinit_fn != null) {
            self.api.deinit_fn(self.ctx);
        }

        if (self.handle) |*lib| {
            lib.close();
            self.handle = null;
        }

        if (self.saved_state) |state| {
            allocator.destroy(state);
            self.saved_state = null;
        }

        self.state = .unloaded;
    }

    pub fn isVersionCompatible(self: *const Plugin, engine_version: struct { major: u32, minor: u32, patch: u32 }) bool {
        // Check if engine version meets minimum requirements
        if (engine_version.major < self.api.min_engine_version_major) return false;
        if (engine_version.major == self.api.min_engine_version_major and
            engine_version.minor < self.api.min_engine_version_minor) return false;
        if (engine_version.major == self.api.min_engine_version_major and
            engine_version.minor == self.api.min_engine_version_minor and
            engine_version.patch < self.api.min_engine_version_patch) return false;

        return true;
    }

    pub fn getVersionString(self: *const Plugin, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
            self.api.version_major,
            self.api.version_minor,
            self.api.version_patch,
        });
    }
};

/// Enhanced plugin loader with file watching, hot-reloading, and thread safety
pub const PluginLoader = struct {
    allocator: std.mem.Allocator,
    plugins: std.array_list.Managed(Plugin),
    plugin_map: std.StringHashMap(u32), // path -> plugin index
    next_plugin_id: u32 = 1,

    // Thread safety
    mutex: std.Thread.Mutex = .{},

    // File watching for hot-reload
    watch_thread: ?std.Thread = null,
    should_stop_watching: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    watch_directories: std.array_list.Managed([]const u8),

    // Engine integration
    engine_api: EngineAPI,

    // Configuration
    config: LoaderConfig,

    pub const LoaderConfig = struct {
        enable_hot_reload: bool = builtin.mode == .Debug,
        watch_interval_ms: u64 = 1000,
        max_error_count: u32 = 5,
        enable_validation: bool = true,
        sandbox_plugins: bool = true,
        concurrent_loading: bool = false,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, engine_api: EngineAPI, config: LoaderConfig) !Self {
        var loader = Self{
            .allocator = allocator,
            .plugins = std.array_list.Managed(Plugin).init(allocator),
            .plugin_map = std.StringHashMap(u32).init(allocator),
            .watch_directories = std.array_list.Managed([]const u8).init(allocator),
            .engine_api = engine_api,
            .config = config,
        };

        if (config.enable_hot_reload) {
            try loader.startFileWatcher();
        }

        return loader;
    }

    pub fn deinit(self: *Self) void {
        // Stop file watcher
        if (self.watch_thread) |_| {
            self.should_stop_watching.store(true, .release);
            self.watch_thread.?.join();
        }

        // Unload all plugins
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items) |*plugin| {
            plugin.unload(self.allocator);
        }
        self.plugins.deinit();
        self.plugin_map.deinit();

        // Cleanup watch directories
        for (self.watch_directories.items) |dir| {
            self.allocator.free(dir);
        }
        self.watch_directories.deinit();
    }

    /// Load a single shared library with enhanced error handling and validation
    pub fn load(self: *Self, path: []const u8) !u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if already loaded
        if (self.plugin_map.get(path)) |existing_id| {
            log.warn("Plugin already loaded: {s}", .{path});
            return existing_id;
        }

        const plugin_id = self.next_plugin_id;
        self.next_plugin_id += 1;

        var plugin = Plugin.init(plugin_id, path);
        plugin.state = .loading;

        // Get file modification time for hot-reload tracking
        if (std.fs.cwd().statFile(path)) |stat| {
            plugin.last_modified = stat.mtime;
        } else |err| {
            log.err("Failed to stat plugin file {s}: {}", .{ path, err });
            return err;
        }

        // Load the dynamic library
        plugin.handle = std.DynamicLibrary.open(path) catch |err| {
            log.err("Failed to load plugin library {s}: {}", .{ path, err });
            plugin.state = .err;
            plugin.last_error = switch (err) {
                error.FileNotFound => PluginError.DependencyMissing,
                else => PluginError.InitializationFailed,
            };
            return err;
        };

        // Get the plugin API
        const sym_name: [:0]const u8 = "nyx_get_plugin_api";
        const sym = plugin.handle.?.lookup(sym_name) orelse {
            log.err("Plugin {s} missing required symbol: {s}", .{ path, sym_name });
            plugin.handle.?.close();
            plugin.state = .err;
            plugin.last_error = PluginError.InitializationFailed;
            return error.SymbolNotFound;
        };

        const get_api: *const fn () callconv(.C) *const PluginAPI = @ptrCast(sym);
        plugin.api = get_api();

        // Validate plugin compatibility
        if (self.config.enable_validation) {
            if (!self.validatePlugin(&plugin)) {
                plugin.unload(self.allocator);
                return PluginError.VersionMismatch;
            }
        }

        // Initialize plugin context
        const ctx_buf = self.allocator.alloc(u8, @sizeOf(usize)) catch |err| {
            plugin.unload(self.allocator);
            return err;
        };
        plugin.ctx = ctx_buf.ptr;

        // Initialize the plugin
        plugin.api.init_fn(plugin.ctx, self.allocator, &self.engine_api) catch |err| {
            log.err("Plugin {s} initialization failed: {}", .{ path, err });
            self.allocator.free(@as([*]u8, @ptrCast(plugin.ctx))[0..@sizeOf(usize)]);
            plugin.unload(self.allocator);
            plugin.state = .err;
            plugin.last_error = err;
            return err;
        };

        plugin.state = .loaded;

        // Store the plugin
        const owned_path = try self.allocator.dupe(u8, path);
        plugin.path = owned_path;

        try self.plugins.append(plugin);
        try self.plugin_map.put(owned_path, plugin_id);

        log.info("Successfully loaded plugin: {s} v{d}.{d}.{d}", .{
            plugin.api.name,
            plugin.api.version_major,
            plugin.api.version_minor,
            plugin.api.version_patch,
        });

        return plugin_id;
    }

    /// Unload a specific plugin by ID
    pub fn unload(self: *Self, plugin_id: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items, 0..) |*plugin, i| {
            if (plugin.id == plugin_id) {
                _ = self.plugin_map.remove(plugin.path);
                self.allocator.free(plugin.path);
                plugin.unload(self.allocator);
                _ = self.plugins.swapRemove(i);
                break;
            }
        }
    }

    /// Call update_fn on all loaded plugins with performance tracking
    pub fn update(self: *Self, dt: f64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items) |*plugin| {
            if (plugin.state != .loaded) continue;
            if (plugin.api.update_fn == null) continue;

            const start_time = std.time.nanoTimestamp();

            if (plugin.api.update_fn.?(plugin.ctx, dt)) {
                const end_time = std.time.nanoTimestamp();
                plugin.update_time_ns = @intCast(end_time - start_time);
            } else |err| {
                plugin.error_count += 1;
                plugin.last_error = err;

                log.warn("Plugin '{}' update failed (error #{d}): {}", .{
                    std.mem.span(plugin.api.name),
                    plugin.error_count,
                    err,
                });

                if (plugin.error_count >= self.config.max_error_count) {
                    log.err("Plugin '{}' disabled due to too many errors", .{std.mem.span(plugin.api.name)});
                    plugin.state = .disabled;
                }
            }
        }
    }

    /// Get plugin information
    pub fn getPluginInfo(self: *Self, plugin_id: u32) ?PluginInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items) |*plugin| {
            if (plugin.id == plugin_id) {
                return PluginInfo{
                    .id = plugin.id,
                    .name = std.mem.span(plugin.api.name),
                    .description = std.mem.span(plugin.api.description),
                    .author = std.mem.span(plugin.api.author),
                    .version = .{
                        .major = plugin.api.version_major,
                        .minor = plugin.api.version_minor,
                        .patch = plugin.api.version_patch,
                    },
                    .state = plugin.state,
                    .path = plugin.path,
                    .error_count = plugin.error_count,
                    .last_error = plugin.last_error,
                };
            }
        }
        return null;
    }

    /// Add directory to watch for hot-reload
    pub fn addWatchDirectory(self: *Self, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.watch_directories.append(owned_path);
    }

    // Private implementation methods

    fn validatePlugin(self: *Self, plugin: *const Plugin) bool {
        // Check version compatibility
        if (!plugin.isVersionCompatible(self.engine_api.version)) {
            log.err("Plugin '{}' requires engine version {d}.{d}.{d}, but current is {d}.{d}.{d}", .{
                std.mem.span(plugin.api.name),
                plugin.api.min_engine_version_major,
                plugin.api.min_engine_version_minor,
                plugin.api.min_engine_version_patch,
                self.engine_api.version.major,
                self.engine_api.version.minor,
                self.engine_api.version.patch,
            });
            return false;
        }

        // Validate required functions exist
        if (plugin.api.init_fn == null or plugin.api.deinit_fn == null) {
            log.err("Plugin '{}' missing required lifecycle functions", .{std.mem.span(plugin.api.name)});
            return false;
        }

        return true;
    }

    fn startFileWatcher(self: *Self) !void {
        self.watch_thread = try std.Thread.spawn(.{}, fileWatcherThread, .{self});
    }

    fn fileWatcherThread(self: *Self) void {
        while (!self.should_stop_watching.load(.acquire)) {
            self.checkForChanges();
            std.time.sleep(self.config.watch_interval_ms * std.time.ns_per_ms);
        }
    }

    fn checkForChanges(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items) |*plugin| {
            if (plugin.state != .loaded) continue;

            if (std.fs.cwd().statFile(plugin.path)) |stat| {
                if (stat.mtime != plugin.last_modified) {
                    log.info("Plugin file changed, triggering hot-reload: {s}", .{plugin.path});
                    self.hotReloadPlugin(plugin) catch |err| {
                        log.err("Hot-reload failed for plugin {s}: {}", .{ plugin.path, err });
                    };
                }
            } else |err| {
                log.warn("Failed to check plugin file {s}: {}", .{ plugin.path, err });
            }
        }
    }

    fn hotReloadPlugin(self: *Self, plugin: *Plugin) !void {
        if (plugin.state != .loaded) return;

        plugin.state = .reloading;

        // Save plugin state if supported
        if (plugin.api.pre_reload_fn) |save_fn| {
            plugin.saved_state = save_fn(plugin.ctx) catch |err| {
                log.warn("Failed to save plugin state for hot-reload: {}", .{err});
                null;
            };
        }

        // Unload current version
        if (plugin.api.deinit_fn != null) {
            plugin.api.deinit_fn(plugin.ctx);
        }

        if (plugin.handle) |*lib| {
            lib.close();
        }

        // Reload the library
        plugin.handle = std.DynamicLibrary.open(plugin.path) catch |err| {
            plugin.state = .err;
            plugin.last_error = PluginError.HotReloadFailed;
            return err;
        };

        // Get new API
        const sym_name: [:0]const u8 = "nyx_get_plugin_api";
        const sym = plugin.handle.?.lookup(sym_name) orelse {
            plugin.state = .err;
            plugin.last_error = PluginError.HotReloadFailed;
            return error.SymbolNotFound;
        };

        const get_api: *const fn () callconv(.C) *const PluginAPI = @ptrCast(sym);
        plugin.api = get_api();

        // Reinitialize
        plugin.api.init_fn(plugin.ctx, self.allocator, &self.engine_api) catch |err| {
            plugin.state = .err;
            plugin.last_error = err;
            return err;
        };

        // Restore state if available
        if (plugin.saved_state) |saved_state| {
            if (plugin.api.post_reload_fn) |restore_fn| {
                restore_fn(plugin.ctx, saved_state, self.allocator) catch |err| {
                    log.warn("Failed to restore plugin state after hot-reload: {}", .{err});
                };
                self.allocator.destroy(saved_state);
                plugin.saved_state = null;
            }
        }

        plugin.state = .loaded;

        // Update modification time
        if (std.fs.cwd().statFile(plugin.path)) |stat| {
            plugin.last_modified = stat.mtime;
        } else |_| {}

        log.info("Successfully hot-reloaded plugin: {s}", .{plugin.path});
    }
};

/// Plugin information structure for external queries
pub const PluginInfo = struct {
    id: u32,
    name: []const u8,
    description: []const u8,
    author: []const u8,
    version: struct {
        major: u32,
        minor: u32,
        patch: u32,
    },
    state: Plugin.PluginState,
    path: []const u8,
    error_count: u32,
    last_error: ?PluginError,
};
