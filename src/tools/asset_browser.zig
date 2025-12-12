const std = @import("std");

pub const AssetType = enum {
    texture,
    model,
    audio,
    script,
    material,
    animation,
    font,
    other,
};

pub const AssetInfo = struct {
    name: []const u8,
    path: []const u8,
    type: AssetType,
    size: u64,
    modified_time: i64,
    thumbnail_path: ?[]const u8 = null,
};

pub const BrowserConfig = struct {
    root_directory: []const u8 = "assets",
    show_thumbnails: bool = true,
    thumbnail_size: u32 = 128,
    supported_formats: []const []const u8 = &.{},
};

pub const AssetBrowser = struct {
    allocator: std.mem.Allocator,
    config: BrowserConfig,
    assets: std.array_list.Managed(AssetInfo),
    current_directory: []const u8,

    pub fn init(allocator: std.mem.Allocator, config: BrowserConfig) !AssetBrowser {
        return AssetBrowser{
            .allocator = allocator,
            .config = config,
            .assets = std.array_list.Managed(AssetInfo).init(allocator),
            .current_directory = try allocator.dupe(u8, config.root_directory),
        };
    }

    pub fn refresh(self: *AssetBrowser) !void {
        self.assets.clearRetainingCapacity();
        // TODO: Scan directory for assets
    }

    pub fn navigateToDirectory(self: *AssetBrowser, path: []const u8) !void {
        self.allocator.free(self.current_directory);
        self.current_directory = try self.allocator.dupe(u8, path);
        try self.refresh();
    }

    pub fn getAssets(self: *const AssetBrowser) []const AssetInfo {
        return self.assets.items;
    }

    pub fn filterByType(self: *const AssetBrowser, asset_type: AssetType, results: *std.array_list.Managed(AssetInfo)) !void {
        results.clearRetainingCapacity();
        for (self.assets.items) |asset| {
            if (asset.type == asset_type) {
                try results.append(asset);
            }
        }
    }

    pub fn searchAssets(self: *const AssetBrowser, query: []const u8, results: *std.array_list.Managed(AssetInfo)) !void {
        results.clearRetainingCapacity();
        for (self.assets.items) |asset| {
            if (std.mem.indexOf(u8, asset.name, query) != null) {
                try results.append(asset);
            }
        }
    }

    pub fn generateThumbnail(self: *AssetBrowser, asset_path: []const u8) !?[]const u8 {
        _ = self;
        _ = asset_path;
        // TODO: Generate thumbnail for asset
        return null;
    }

    pub fn getCurrentDirectory(self: *const AssetBrowser) []const u8 {
        return self.current_directory;
    }

    pub fn deinit(self: *AssetBrowser) void {
        self.allocator.free(self.current_directory);
        for (self.assets.items) |asset| {
            self.allocator.free(asset.name);
            self.allocator.free(asset.path);
            if (asset.thumbnail_path) |thumb| {
                self.allocator.free(thumb);
            }
        }
        self.assets.deinit();
    }
};
