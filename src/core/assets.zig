//! Asset Management System
//! Handles loading, caching, and lifetime management of game assets

const std = @import("std");
const types = @import("types.zig");

/// Asset type enumeration
pub const AssetType = enum {
    texture,
    model,
    sound,
    shader,
    font,
    animation,
    material,
    unknown,
};

/// Asset status during loading
pub const AssetStatus = enum {
    unloaded,
    loading,
    loaded,
    failed,
};

/// Generic asset interface
pub const Asset = struct {
    id: types.Handle,
    asset_type: AssetType,
    status: AssetStatus,
    reference_count: u32,
    file_path: []const u8,
    data: ?*anyopaque = null,
    size: usize = 0,

    const Self = @This();

    pub fn init(id: types.Handle, asset_type: AssetType, file_path: []const u8) Self {
        return Self{
            .id = id,
            .asset_type = asset_type,
            .status = .unloaded,
            .reference_count = 0,
            .file_path = file_path,
        };
    }

    pub fn addRef(self: *Self) void {
        self.reference_count += 1;
    }

    pub fn release(self: *Self) void {
        if (self.reference_count > 0) {
            self.reference_count -= 1;
        }
    }

    pub fn isLoaded(self: *const Self) bool {
        return self.status == .loaded;
    }
};

/// Asset loading callback
pub const AssetLoadCallback = *const fn (asset: *Asset, success: bool) void;

/// Asset manager for loading and caching assets
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    assets: std.HashMap(types.Handle, *Asset, std.hash_map.HashMap(types.Handle, *Asset, std.hash_map.Context(types.Handle, std.hash_map.default_hash, std.hash_map.default_eql, 80), 80).Context, 80),
    next_id: u64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .assets = @TypeOf(Self.assets).init(allocator),
            .next_id = 1,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all assets
        var iterator = self.assets.iterator();
        while (iterator.next()) |entry| {
            const asset = entry.value_ptr.*;
            self.unloadAsset(asset);
            self.allocator.destroy(asset);
        }
        self.assets.deinit();
    }

    /// Load an asset asynchronously
    pub fn loadAsset(self: *Self, file_path: []const u8, asset_type: AssetType, callback: ?AssetLoadCallback) !types.Handle {
        const handle = types.Handle{ .id = self.next_id, .generation = 1 };
        self.next_id += 1;

        const asset = try self.allocator.create(Asset);
        asset.* = Asset.init(handle, asset_type, file_path);
        asset.status = .loading;

        try self.assets.put(handle, asset);

        // TODO: Implement actual async loading
        // For now, just mark as loaded
        asset.status = .loaded;
        if (callback) |cb| {
            cb(asset, true);
        }

        return handle;
    }

    /// Get an asset by handle
    pub fn getAsset(self: *Self, handle: types.Handle) ?*Asset {
        return self.assets.get(handle);
    }

    /// Unload an asset
    pub fn unloadAsset(self: *Self, asset: *Asset) void {
        _ = self; // unused parameter
        if (asset.data) |data| {
            // TODO: Implement proper asset-specific cleanup
            _ = data;
        }
        asset.status = .unloaded;
        asset.data = null;
        asset.size = 0;
    }

    /// Remove an asset from the manager
    pub fn removeAsset(self: *Self, handle: types.Handle) void {
        if (self.assets.get(handle)) |asset| {
            self.unloadAsset(asset);
            self.allocator.destroy(asset);
            _ = self.assets.remove(handle);
        }
    }

    /// Get statistics about asset usage
    pub fn getStats(self: *const Self) AssetStats {
        var stats = AssetStats{};

        var iterator = self.assets.iterator();
        while (iterator.next()) |entry| {
            const asset = entry.value_ptr.*;
            stats.total_assets += 1;
            stats.total_memory += asset.size;

            switch (asset.status) {
                .loaded => stats.loaded_assets += 1,
                .loading => stats.loading_assets += 1,
                .failed => stats.failed_assets += 1,
                .unloaded => {},
            }
        }

        return stats;
    }
};

/// Asset usage statistics
pub const AssetStats = struct {
    total_assets: u32 = 0,
    loaded_assets: u32 = 0,
    loading_assets: u32 = 0,
    failed_assets: u32 = 0,
    total_memory: usize = 0,
};

test "asset management" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = AssetManager.init(allocator);
    defer manager.deinit();

    // Test asset loading
    const handle = try manager.loadAsset("test.png", .texture, null);
    try testing.expect(handle.isValid());

    // Test asset retrieval
    const asset = manager.getAsset(handle);
    try testing.expect(asset != null);
    try testing.expect(asset.?.isLoaded());

    // Test stats
    const stats = manager.getStats();
    try testing.expect(stats.total_assets == 1);
    try testing.expect(stats.loaded_assets == 1);
}
