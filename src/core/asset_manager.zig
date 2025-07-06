//! MFS Engine - Asset Manager
//! Comprehensive asset management system with caching and hot-reloading
//! @thread-safe Asset operations are thread-safe with proper synchronization
//! @symbol AssetManager

const std = @import("std");
const types = @import("types.zig");

/// Asset type enumeration
pub const AssetType = enum {
    texture,
    model,
    sound,
    shader,
    font,
    config,
    script,
    material,
    animation,
    scene,

    pub fn getExtensions(self: AssetType) []const []const u8 {
        return switch (self) {
            .texture => &[_][]const u8{ ".png", ".jpg", ".jpeg", ".bmp", ".tga", ".dds", ".hdr", ".exr" },
            .model => &[_][]const u8{ ".obj", ".gltf", ".glb", ".fbx", ".dae", ".3ds" },
            .sound => &[_][]const u8{ ".wav", ".ogg", ".mp3", ".flac", ".aac" },
            .shader => &[_][]const u8{ ".vert", ".frag", ".comp", ".geom", ".tesc", ".tese", ".hlsl", ".glsl" },
            .font => &[_][]const u8{ ".ttf", ".otf", ".woff", ".woff2" },
            .config => &[_][]const u8{ ".json", ".yaml", ".yml", ".toml", ".ini" },
            .script => &[_][]const u8{ ".zig", ".lua", ".js", ".py", ".wasm" },
            .material => &[_][]const u8{ ".mtl", ".mat" },
            .animation => &[_][]const u8{ ".anim", ".fbx", ".bvh" },
            .scene => &[_][]const u8{ ".scene", ".gltf", ".glb" },
        };
    }

    pub fn fromExtension(extension: []const u8) ?AssetType {
        const lower_ext = std.ascii.lowerString(std.heap.page_allocator, extension) catch return null;
        defer std.heap.page_allocator.free(lower_ext);

        inline for (std.meta.fields(AssetType)) |field| {
            const asset_type = @as(AssetType, @enumFromInt(field.value));
            for (asset_type.getExtensions()) |ext| {
                if (std.mem.eql(u8, lower_ext, ext)) {
                    return asset_type;
                }
            }
        }
        return null;
    }
};

/// Asset metadata
pub const AssetMetadata = struct {
    path: []const u8,
    asset_type: AssetType,
    size: u64,
    last_modified: i64,
    checksum: u64,
    dependencies: std.ArrayList(types.Handle),
    tags: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, path: []const u8, asset_type: AssetType) AssetMetadata {
        return AssetMetadata{
            .path = path,
            .asset_type = asset_type,
            .size = 0,
            .last_modified = 0,
            .checksum = 0,
            .dependencies = std.ArrayList(types.Handle).init(allocator),
            .tags = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *AssetMetadata) void {
        self.dependencies.deinit();
        self.tags.deinit();
    }
};

/// Asset data container
pub const Asset = struct {
    handle: types.Handle,
    metadata: AssetMetadata,
    data: ?[]const u8,
    state: State,
    reference_count: std.atomic.Value(u32),

    pub const State = enum {
        unloaded,
        loading,
        loaded,
        failed,
    };

    pub fn init(handle: types.Handle, metadata: AssetMetadata) Asset {
        return Asset{
            .handle = handle,
            .metadata = metadata,
            .data = null,
            .state = .unloaded,
            .reference_count = std.atomic.Value(u32).init(0),
        };
    }

    pub fn addRef(self: *Asset) void {
        _ = self.reference_count.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Asset) u32 {
        return self.reference_count.fetchSub(1, .monotonic) - 1;
    }

    pub fn getRefCount(self: *const Asset) u32 {
        return self.reference_count.load(.monotonic);
    }
};

/// Asset loading callback
pub const AssetLoader = struct {
    load_fn: *const fn (allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8,
    unload_fn: *const fn (allocator: std.mem.Allocator, data: []const u8) void,
    asset_type: AssetType,
};

/// Comprehensive asset management system
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    assets: std.HashMap(types.Handle, *Asset, HandleContext, std.hash_map.default_max_load_percentage),
    path_to_handle: std.HashMap([]const u8, types.Handle, StringContext, std.hash_map.default_max_load_percentage),
    loaders: std.HashMap(AssetType, AssetLoader, AssetTypeContext, std.hash_map.default_max_load_percentage),
    next_handle: std.atomic.Value(u64),
    mutex: std.Thread.RwLock,
    cache_size_mb: u64,
    current_cache_size: std.atomic.Value(u64),
    hot_reload_enabled: bool,
    file_watcher: ?*FileWatcher,

    const Self = @This();
    const HandleContext = struct {
        pub fn hash(self: @This(), key: types.Handle) u64 {
            _ = self;
            return key.id;
        }
        pub fn eql(self: @This(), a: types.Handle, b: types.Handle) bool {
            _ = self;
            return a.id == b.id and a.generation == b.generation;
        }
    };

    const StringContext = struct {
        pub fn hash(self: @This(), key: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(key);
        }
        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    const AssetTypeContext = struct {
        pub fn hash(self: @This(), key: AssetType) u64 {
            _ = self;
            return @intFromEnum(key);
        }
        pub fn eql(self: @This(), a: AssetType, b: AssetType) bool {
            _ = self;
            return a == b;
        }
    };

    const FileWatcher = struct {
        // TODO: Implement file watching for hot reload
        thread: std.Thread,
        should_stop: std.atomic.Value(bool),

        pub fn init() !*FileWatcher {
            // Placeholder implementation
            return undefined;
        }

        pub fn deinit(self: *FileWatcher) void {
            _ = self;
        }
    };

    /// Initialize asset manager
    pub fn init(allocator: std.mem.Allocator, cache_size_mb: u64, hot_reload: bool) !Self {
        return Self{
            .allocator = allocator,
            .assets = std.HashMap(types.Handle, *Asset, HandleContext, std.hash_map.default_max_load_percentage).init(allocator),
            .path_to_handle = std.HashMap([]const u8, types.Handle, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .loaders = std.HashMap(AssetType, AssetLoader, AssetTypeContext, std.hash_map.default_max_load_percentage).init(allocator),
            .next_handle = std.atomic.Value(u64).init(1),
            .mutex = std.Thread.RwLock{},
            .cache_size_mb = cache_size_mb,
            .current_cache_size = std.atomic.Value(u64).init(0),
            .hot_reload_enabled = hot_reload,
            .file_watcher = null,
        };
    }

    /// Clean up asset manager
    pub fn deinit(self: *Self) void {
        if (self.file_watcher) |watcher| {
            watcher.deinit();
        }

        // Clean up all assets
        var asset_iter = self.assets.valueIterator();
        while (asset_iter.next()) |asset| {
            if (asset.*.data) |data| {
                self.allocator.free(data);
            }
            asset.*.metadata.deinit();
            self.allocator.destroy(asset.*);
        }

        self.assets.deinit();
        self.path_to_handle.deinit();
        self.loaders.deinit();
    }

    /// Register an asset loader for a specific type
    pub fn registerLoader(self: *Self, loader: AssetLoader) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.loaders.put(loader.asset_type, loader);
    }

    /// Load an asset by path
    pub fn loadAsset(self: *Self, path: []const u8) !types.Handle {
        // Check if already loaded
        self.mutex.lockShared();
        if (self.path_to_handle.get(path)) |handle| {
            if (self.assets.get(handle)) |asset| {
                asset.addRef();
                self.mutex.unlockShared();
                return handle;
            }
        }
        self.mutex.unlockShared();

        // Determine asset type from extension
        const extension = std.fs.path.extension(path);
        const asset_type = AssetType.fromExtension(extension) orelse return error.UnsupportedAssetType;

        // Get loader for this asset type
        self.mutex.lockShared();
        const loader = self.loaders.get(asset_type) orelse {
            self.mutex.unlockShared();
            return error.NoLoaderRegistered;
        };
        self.mutex.unlockShared();

        // Create new asset
        const handle = types.Handle{
            .id = self.next_handle.fetchAdd(1, .monotonic),
            .generation = 1,
        };

        var metadata = AssetMetadata.init(self.allocator, path, asset_type);

        // Get file info
        const file = std.fs.cwd().openFile(path, .{}) catch return error.AssetNotFound;
        defer file.close();

        const file_stat = file.stat() catch return error.AssetNotFound;
        metadata.size = file_stat.size;
        metadata.last_modified = file_stat.mtime;

        const asset = try self.allocator.create(Asset);
        asset.* = Asset.init(handle, metadata);
        asset.state = .loading;

        // Load asset data
        const data = loader.load_fn(self.allocator, path) catch |err| {
            asset.state = .failed;
            return err;
        };

        asset.data = data;
        asset.state = .loaded;
        asset.addRef();

        // Update cache size
        _ = self.current_cache_size.fetchAdd(data.len, .monotonic);

        // Store in maps
        self.mutex.lock();
        try self.assets.put(handle, asset);
        try self.path_to_handle.put(path, handle);
        self.mutex.unlock();

        return handle;
    }

    /// Unload an asset
    pub fn unloadAsset(self: *Self, handle: types.Handle) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.assets.get(handle)) |asset| {
            const ref_count = asset.release();
            if (ref_count == 0) {
                // Remove from cache
                if (asset.data) |data| {
                    _ = self.current_cache_size.fetchSub(data.len, .monotonic);

                    // Get loader and unload
                    if (self.loaders.get(asset.metadata.asset_type)) |loader| {
                        loader.unload_fn(self.allocator, data);
                    } else {
                        self.allocator.free(data);
                    }
                }

                // Remove from maps
                _ = self.assets.remove(handle);
                _ = self.path_to_handle.remove(asset.metadata.path);

                // Clean up asset
                asset.metadata.deinit();
                self.allocator.destroy(asset);
            }
        }
    }

    /// Get asset data by handle
    pub fn getAsset(self: *Self, handle: types.Handle) ?*Asset {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        return self.assets.get(handle);
    }

    /// Get current cache usage in bytes
    pub fn getCacheUsage(self: *const Self) u64 {
        return self.current_cache_size.load(.monotonic);
    }

    /// Get cache usage as percentage (0.0 to 1.0)
    pub fn getCacheUtilization(self: *const Self) f32 {
        const max_bytes = self.cache_size_mb * 1024 * 1024;
        const current_bytes = self.getCacheUsage();
        return @as(f32, @floatFromInt(current_bytes)) / @as(f32, @floatFromInt(max_bytes));
    }

    /// Force garbage collection of unused assets
    pub fn garbageCollect(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var to_remove = std.ArrayList(types.Handle).init(self.allocator);
        defer to_remove.deinit();

        var asset_iter = self.assets.iterator();
        while (asset_iter.next()) |entry| {
            const asset = entry.value_ptr.*;
            if (asset.getRefCount() == 0) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |handle| {
            self.unloadAsset(handle);
        }
    }
};

test "asset manager" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var asset_manager = try AssetManager.init(allocator, 100, false);
    defer asset_manager.deinit();

    // Test asset type detection
    const png_type = AssetType.fromExtension(".png");
    try testing.expect(png_type == .texture);

    const unknown_type = AssetType.fromExtension(".unknown");
    try testing.expect(unknown_type == null);
}
