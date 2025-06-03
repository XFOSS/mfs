const std = @import("std");
const builtin = @import("builtin");
const zigimg = @import("zigimg");

const AssetType = enum {
    texture,
    model,
    shader,
    font,
    audio,
    data,
    unknown,

    pub fn fromExtension(extension: []const u8) AssetType {
        if (std.mem.eql(u8, extension, ".png") or
            std.mem.eql(u8, extension, ".jpg") or
            std.mem.eql(u8, extension, ".tga") or
            std.mem.eql(u8, extension, ".bmp") or
            std.mem.eql(u8, extension, ".hdr"))
        {
            return .texture;
        } else if (std.mem.eql(u8, extension, ".obj") or
                   std.mem.eql(u8, extension, ".gltf") or
                   std.mem.eql(u8, extension, ".glb") or
                   std.mem.eql(u8, extension, ".fbx"))
        {
            return .model;
        } else if (std.mem.eql(u8, extension, ".vert") or
                   std.mem.eql(u8, extension, ".frag") or
                   std.mem.eql(u8, extension, ".comp") or
                   std.mem.eql(u8, extension, ".shader"))
        {
            return .shader;
        } else if (std.mem.eql(u8, extension, ".ttf") or
                   std.mem.eql(u8, extension, ".otf"))
        {
            return .font;
        } else if (std.mem.eql(u8, extension, ".wav") or
                   std.mem.eql(u8, extension, ".mp3") or
                   std.mem.eql(u8, extension, ".ogg"))
        {
            return .audio;
        } else if (std.mem.eql(u8, extension, ".json") or
                   std.mem.eql(u8, extension, ".xml") or
                   std.mem.eql(u8, extension, ".csv") or
                   std.mem.eql(u8, extension, ".yaml") or
                   std.mem.eql(u8, extension, ".toml"))
        {
            return .data;
        } else {
            return .unknown;
        }
    }
};

const ProcessorConfig = struct {
    input_dir: []const u8,
    output_dir: []const u8,
    asset_types: []const AssetType,
    compression_level: u8 = 9,
    generate_mipmaps: bool = true,
    normalize_models: bool = true,
    verbose: bool = false,
    force_reprocess: bool = false,
    threads: u8 = 0, // 0 means auto-detect
};

const ProcessedStats = struct {
    total: usize = 0,
    processed: usize = 0,
    skipped: usize = 0,
    failed: usize = 0,
    by_type: std.AutoHashMap(AssetType, usize),

    pub fn init(allocator: std.mem.Allocator) ProcessedStats {
        return .{
            .by_type = std.AutoHashMap(AssetType, usize).init(allocator),
        };
    }

    pub fn deinit(self: *ProcessedStats) void {
        self.by_type.deinit();
    }

    pub fn incrementType(self: *ProcessedStats, asset_type: AssetType) !void {
        const entry = try self.by_type.getOrPut(asset_type);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }
};

const AssetMetadata = struct {
    original_path: []const u8,
    processed_path: []const u8,
    asset_type: AssetType,
    file_size: usize,
    hash: [32]u8, // SHA-256
    last_modified: i128,
    compression: enum { none, lz4, zstd },
    format_version: u32 = 1,
    custom_metadata: std.json.Value,

    pub fn init(allocator: std.mem.Allocator) AssetMetadata {
        return .{
            .original_path = "",
            .processed_path = "",
            .asset_type = .unknown,
            .file_size = 0,
            .hash = [_]u8{0} ** 32,
            .last_modified = 0,
            .compression = .none,
            .custom_metadata = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        };
    }

    pub fn deinit(self: *AssetMetadata) void {
        self.custom_metadata.deinit();
    }

    pub fn toJson(self: AssetMetadata, allocator: std.mem.Allocator) ![]const u8 {
        var json = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        
        try json.object.put("original_path", std.json.Value{ .string = self.original_path });
        try json.object.put("processed_path", std.json.Value{ .string = self.processed_path });
        try json.object.put("asset_type", std.json.Value{ .string = @tagName(self.asset_type) });
        try json.object.put("file_size", std.json.Value{ .integer = @intCast(self.file_size) });
        
        var hash_str = try allocator.alloc(u8, self.hash.len * 2);
        _ = try std.fmt.bufPrint(hash_str, "{s}", .{std.fmt.fmtSliceHexLower(&self.hash)});
        try json.object.put("hash", std.json.Value{ .string = hash_str });
        
        try json.object.put("last_modified", std.json.Value{ .integer = @intCast(self.last_modified) });
        try json.object.put("compression", std.json.Value{ .string = @tagName(self.compression) });
        try json.object.put("format_version", std.json.Value{ .integer = self.format_version });
        try json.object.put("custom_metadata", self.custom_metadata);

        return std.json.stringifyAlloc(allocator, json, .{});
    }

    pub fn fromJson(json_str: []const u8, allocator: std.mem.Allocator) !AssetMetadata {
        var result = AssetMetadata.init(allocator);
        
        var parser = std.json.Parser.init(allocator, false);
        defer parser.deinit();
        
        var tree = try parser.parse(json_str);
        defer tree.deinit();
        
        const root = tree.root;
        
        result.original_path = try allocator.dupe(u8, root.object.get("original_path").?.string);
        result.processed_path = try allocator.dupe(u8, root.object.get("processed_path").?.string);
        result.asset_type = std.meta.stringToEnum(AssetType, root.object.get("asset_type").?.string) orelse .unknown;
        result.file_size = @intCast(root.object.get("file_size").?.integer);
        
        const hash_str = root.object.get("hash").?.string;
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            const byte = try std.fmt.parseInt(u8, hash_str[i*2..i*2+2], 16);
            result.hash[i] = byte;
        }
        
        result.last_modified = root.object.get("last_modified").?.integer;
        result.compression = std.meta.stringToEnum(
            @TypeOf(result.compression), 
            root.object.get("compression").?.string
        ) orelse .none;
        
        if (root.object.get("format_version")) |version| {
            result.format_version = @intCast(version.integer);
        }
        
        if (root.object.get("custom_metadata")) |custom| {
            result.custom_metadata = try custom.deepClone();
        }
        
        return result;
    }
};

const AssetProcessor = struct {
    allocator: std.mem.Allocator,
    config: ProcessorConfig,
    stats: ProcessedStats,
    metadata_map: std.StringHashMap(AssetMetadata),
    
    pub fn init(allocator: std.mem.Allocator, config: ProcessorConfig) !*AssetProcessor {
        var self = try allocator.create(AssetProcessor);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .stats = ProcessedStats.init(allocator),
            .metadata_map = std.StringHashMap(AssetMetadata).init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *AssetProcessor) void {
        self.stats.deinit();
        
        var metadata_iter = self.metadata_map.valueIterator();
        while (metadata_iter.next()) |metadata| {
            metadata.deinit();
        }
        self.metadata_map.deinit();
        
        self.allocator.destroy(self);
    }
    
    pub fn processAllAssets(self: *AssetProcessor) !void {
        std.log.info("Processing assets from {s} to {s}", .{ 
            self.config.input_dir, self.config.output_dir 
        });
        
        // Ensure output directory exists
        try std.fs.cwd().makePath(self.config.output_dir);
        
        // Load existing metadata if available
        try self.loadMetadata();
        
        // Walk the input directory and process all files
        var dir = try std.fs.cwd().openDir(self.config.input_dir, .{ .iterate = true });
        defer dir.close();
        
        try self.processDirectory(dir, "");
        
        // Save metadata
        try self.saveMetadata();
        
        // Print stats
        self.logStats();
    }
    
    fn processDirectory(self: *AssetProcessor, dir: std.fs.Dir, subpath: []const u8) !void {
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const entry_path = if (subpath.len == 0) 
                entry.name 
            else 
                try std.fs.path.join(self.allocator, &.{subpath, entry.name});
            defer if (subpath.len > 0) self.allocator.free(entry_path);
            
            switch (entry.kind) {
                .file => {
                    try self.processFile(entry_path);
                },
                .directory => {
                    var subdir = try dir.openDir(entry.name, .{ .iterate = true });
                    defer subdir.close();
                    try self.processDirectory(subdir, entry_path);
                },
                else => {}, // Skip other file types
            }
        }
    }
    
    fn processFile(self: *AssetProcessor, relative_path: []const u8) !void {
        self.stats.total += 1;
        
        // Check if file should be processed based on extension
        const extension = std.fs.path.extension(relative_path);
        const asset_type = AssetType.fromExtension(extension);
        
        // Skip if we're not processing this asset type
        if (!self.shouldProcessAssetType(asset_type)) {
            if (self.config.verbose) {
                std.log.debug("Skipping {s}: asset type {s} not selected", .{ 
                    relative_path, @tagName(asset_type) 
                });
            }
            self.stats.skipped += 1;
            return;
        }
        
        try self.stats.incrementType(asset_type);
        
        // Check if file needs processing by comparing metadata
        const full_input_path = try std.fs.path.join(self.allocator, &.{ 
            self.config.input_dir, relative_path 
        });
        defer self.allocator.free(full_input_path);
        
        if (!self.config.force_reprocess and self.isAssetUpToDate(full_input_path, relative_path)) {
            if (self.config.verbose) {
                std.log.debug("Skipping {s}: up to date", .{relative_path});
            }
            self.stats.skipped += 1;
            return;
        }
        
        // Process the file based on its type
        if (self.config.verbose) {
            std.log.info("Processing {s}", .{relative_path});
        }
        
        switch (asset_type) {
            .texture => try self.processTexture(full_input_path, relative_path),
            .model => try self.processModel(full_input_path, relative_path),
            .shader => try self.processShader(full_input_path, relative_path),
            .font => try self.processFont(full_input_path, relative_path),
            .audio => try self.processAudio(full_input_path, relative_path),
            .data => try self.processData(full_input_path, relative_path),
            .unknown => try self.copyFile(full_input_path, relative_path),
        }
        
        self.stats.processed += 1;
    }
    
    fn shouldProcessAssetType(self: AssetProcessor, asset_type: AssetType) bool {
        if (self.config.asset_types.len == 0) return true;
        
        for (self.config.asset_types) |t| {
            if (t == asset_type) return true;
        }
        return false;
    }
    
    fn isAssetUpToDate(self: *AssetProcessor, full_path: []const u8, relative_path: []const u8) bool {
        // Check if we have metadata for this file
        if (self.metadata_map.get(relative_path)) |metadata| {
            // Compare file modification times
            var stat: std.fs.File.Stat = std.fs.cwd().statFile(full_path) catch return false;
            if (stat.mtime != metadata.last_modified) return false;
            
            // Compare hash
            var hash: [32]u8 = undefined;
            self.hashFile(full_path, &hash) catch return false;
            
            // Return true if hashes match
            return std.mem.eql(u8, &hash, &metadata.hash);
        }
        
        return false;
    }
    
    fn hashFile(self: *AssetProcessor, path: []const u8, out_hash: *[32]u8) !void {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var buffer: [8192]u8 = undefined;
        
        while (true) {
            const bytes_read = try file.read(&buffer);
            if (bytes_read == 0) break;
            hasher.update(buffer[0..bytes_read]);
        }
        
        hasher.final(out_hash);
    }
    
    fn processTexture(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        // Create output directory
        const output_dir = try std.fs.path.dirname(relative_path);
        if (output_dir) |dir| {
            const full_output_dir = try std.fs.path.join(self.allocator, &.{ 
                self.config.output_dir, dir 
            });
            defer self.allocator.free(full_output_dir);
            try std.fs.cwd().makePath(full_output_dir);
        }
        
        // Generate output path
        const output_path = try std.fs.path.join(self.allocator, &.{ 
            self.config.output_dir, relative_path 
        });
        defer self.allocator.free(output_path);
        
        // Load image using zigimg
        var src_img = try zigimg.Image.fromFilePath(self.allocator, input_path);
        defer src_img.deinit();
        
        // Generate mipmaps if requested
        var mipmap_levels: u32 = 1;
        if (self.config.generate_mipmaps) {
            const max_dim = @max(src_img.width, src_img.height);
            mipmap_levels = std.math.log2_int(u32, max_dim) + 1;
            
            // TODO: Actually generate mipmaps - for now we just record the count
        }
        
        // Save processed image
        try src_img.writeToFilePath(output_path);
        
        // Create and save metadata
        var metadata = AssetMetadata.init(self.allocator);
        metadata.original_path = try self.allocator.dupe(u8, relative_path);
        metadata.processed_path = try self.allocator.dupe(u8, relative_path);
        metadata.asset_type = .texture;
        
        var stat = try std.fs.cwd().statFile(input_path);
        metadata.file_size = @intCast(stat.size);
        metadata.last_modified = stat.mtime;
        
        try self.hashFile(input_path, &metadata.hash);
        
        // Add custom metadata for textures
        var custom_obj = std.json.ObjectMap.init(self.allocator);
        try custom_obj.put("width", std.json.Value{ .integer = @intCast(src_img.width) });
        try custom_obj.put("height", std.json.Value{ .integer = @intCast(src_img.height) });
        try custom_obj.put("format", std.json.Value{ .string = @tagName(src_img.pixel_format) });
        try custom_obj.put("mipmap_levels", std.json.Value{ .integer = mipmap_levels });
        
        metadata.custom_metadata = .{ .object = custom_obj };
        
        // Store metadata
        if (self.metadata_map.get(relative_path)) |*existing| {
            existing.deinit();
        }
        try self.metadata_map.put(relative_path, metadata);
    }
    
    fn processModel(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        // For now, just copy the model file since we don't have a model processor
        try self.copyFile(input_path, relative_path);
    }
    
    fn processShader(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        // For now, just copy the shader file
        try self.copyFile(input_path, relative_path);
        
        // TODO: Implement shader compilation once we know the target format
    }
    
    fn processFont(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        try self.copyFile(input_path, relative_path);
    }
    
    fn processAudio(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        try self.copyFile(input_path, relative_path);
    }
    
    fn processData(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        try self.copyFile(input_path, relative_path);
    }
    
    fn copyFile(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        // Create output directory
        const output_dir = try std.fs.path.dirname(relative_path);
        if (output_dir) |dir| {
            const full_output_dir = try std.fs.path.join(self.allocator, &.{ 
                self.config.output_dir, dir 
            });
            defer self.allocator.free(full_output_dir);
            try std.fs.cwd().makePath(full_output_dir);
        }
        
        // Generate output path
        const output_path = try std.fs.path.join(self.allocator, &.{ 
            self.config.output_dir, relative_path 
        });
        defer self.allocator.free(output_path);
        
        // Copy the file
        try std.fs.copyFileAbsolute(input_path, output_path, .{});
        
        // Create and save metadata
        var metadata = AssetMetadata.init(self.allocator);
        metadata.original_path = try self.allocator.dupe(u8, relative_path);
        metadata.processed_path = try self.allocator.dupe(u8, relative_path);
        metadata.asset_type = AssetType.fromExtension(std.fs.path.extension(relative_path));
        
        var stat = try std.fs.cwd().statFile(input_path);
        metadata.file_size = @intCast(stat.size);
        metadata.last_modified = stat.mtime;
        
        try self.hashFile(input_path, &metadata.hash);
        
        // Store metadata
        if (self.metadata_map.get(relative_path)) |*existing| {
            existing.deinit();
        }
        try self.metadata_map.put(try self.allocator.dupe(u8, relative_path), metadata);
    }
    
    fn loadMetadata(self: *AssetProcessor) !void {
        const metadata_path = try std.fs.path.join(self.allocator, &.{ 
            self.config.output_dir, "asset_metadata.json" 
        });
        defer self.allocator.free(metadata_path);
        
        const file = std.fs.cwd().openFile(metadata_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Metadata doesn't exist yet, that's fine
                return;
            }
            return err;
        };
        defer file.close();
        
        const metadata_json = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(metadata_json);
        
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = try parser.parse(metadata_json);
        defer tree.deinit();
        
        const root = tree.root;
        if (root.object.get("assets")) |assets_array| {
            for (assets_array.array.items) |asset_json| {
                const json_str = try std.json.stringifyAlloc(self.allocator, asset_json, .{});
                defer self.allocator.free(json_str);
                
                const metadata = try AssetMetadata.fromJson(json_str, self.allocator);
                try self.metadata_map.put(try self.allocator.dupe(u8, metadata.original_path), metadata);
            }
        }
    }
    
    fn saveMetadata(self: *AssetProcessor) !void {
        const metadata_path = try std.fs.path.join(self.allocator, &.{ 
            self.config.output_dir, "asset_metadata.json" 
        });
        defer self.allocator.free(metadata_path);
        
        var file = try std.fs.cwd().createFile(metadata_path, .{});
        defer file.close();
        
        // Create JSON array of all metadata entries
        var json_array = std.ArrayList(std.json.Value).init(self.allocator);
        defer json_array.deinit();
        
        var metadata_iter = self.metadata_map.valueIterator();
        while (metadata_iter.next()) |metadata| {
            const json_str = try metadata.toJson(self.allocator);
            defer self.allocator.free(json_str);
            
            var parser = std.json.Parser.init(self.allocator, false);
            defer parser.deinit();
            
            var tree = try parser.parse(json_str);
            defer tree.deinit();
            
            try json_array.append(tree.root);
        }
        
        var root = std.json.ObjectMap.init(self.allocator);
        defer root.deinit();
        
        try root.put("format_version", std.json.Value{ .integer = 1 });
        try root.put("generator", std.json.Value{ .string = "MFS Asset Processor" });
        try root.put("timestamp", std.json.Value{ .integer = @intCast(std.time.timestamp()) });
        try root.put("assets", std.json.Value{ .array = json_array });
        
        const root_value = std.json.Value{ .object = root };
        try std.json.stringify(root_value, .{ .whitespace = .indent_2 }, file.writer());
    }
    
    fn logStats(self: *AssetProcessor) void {
        std.log.info("Asset Processing Complete:", .{});
        std.log.info("  Total files: {d}", .{self.stats.total});
        std.log.info("  Processed: {d}", .{self.stats.processed});
        std.log.info("  Skipped: {d}", .{self.stats.skipped});
        std.log.info("  Failed: {d}", .{self.stats.failed});
        
        std.log.info("By type:", .{});
        var iter = self.stats.by_type.iterator();
        while (iter.next()) |entry| {
            std.log.info("  {s}: {d}", .{ @tagName(entry.key_ptr.*), entry.value_ptr.* });
        }
    }
};

pub fn main() !void {
    // Set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse command line arguments
    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 3) {
        try printUsage(stdout);
        std.process.exit(1);
    }
    
    const input_dir = args[1];
    const output_dir = args[2];
    
    // Set up configuration with default options
    var asset_types = std.ArrayList(AssetType).init(allocator);
    defer asset_types.deinit();
    
    var compression_level: u8 = 9;
    var generate_mipmaps = true;
    var normalize_models = true;
    var verbose = false;
    var force_reprocess = false;
    var threads: u8 = 0;
    
    // Parse additional arguments
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage(stdout);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--type") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) {
                std.log.err("Missing value for --type", .{});
                std.process.exit(1);
            }
            const type_str = args[i];
            const asset_type = std.meta.stringToEnum(AssetType, type_str) orelse {
                std.log.err("Unknown asset type: {s}", .{type_str});
                std.process.exit(1);
            };
            try asset_types.append(asset_type);
        } else if (std.mem.eql(u8, arg, "--compression") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= args.len) {
                std.log.err("Missing value for --compression", .{});
                std.process.exit(1);
            }
            compression_level = try std.fmt.parseInt(u8, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--no-mipmaps")) {
            generate_mipmaps = false;
        } else if (std.mem.eql(u8, arg, "--no-normalize")) {
            normalize_models = false;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            force_reprocess = true;
        } else if (std.mem.eql(u8, arg, "--threads") or std.mem.eql(u8, arg, "-j")) {
            i += 1;
            if (i >= args.len) {
                std.log.err("Missing value for --threads", .{});
                std.process.exit(1);
            }
            threads = try std.fmt.parseInt(u8, args[i], 10);
        } else {
            std.log.err("Unknown option: {s}", .{arg});
            try printUsage(stdout);
            std.process.exit(1);
        }
    }
    
    // Create processor config
    const config = ProcessorConfig{
        .input_dir = input_dir,
        .output_dir = output_dir,
        .asset_types = asset_types.items,
        .compression_level = compression_level,
        .generate_mipmaps = generate_mipmaps,
        .normalize_models = normalize_models,
        .verbose = verbose,
        .force_reprocess = force_reprocess,
        .threads = threads,
    };
    
    // Create and run processor
    var processor = try AssetProcessor.init(allocator, config);
    defer processor.deinit();
    
    try processor.processAllAssets();
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: asset_processor <input_dir> <output_dir> [options]
        \\
        \\Options:
        \\  --type, -t <type>      Process only assets of specified type
        \\                          (can be used multiple times)
        \\  --compression, -c <0-9> Set compression level (default: 9)
        \\  --no-mipmaps           Don't generate mipmaps for textures
        \\  --no-normalize         Don't normalize models
        \\  --verbose, -v          Enable verbose output
        \\  --force, -f            Force reprocessing of all assets
        \\  --threads, -j <num>    Number of threads (0 = auto)
        \\  --help, -h             Show this help message
        \\
        \\Asset Types:
        \\  texture, model, shader, font, audio, data
        \\
    );
}

test "basic asset processing" {
    // Create test temporary directories
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();
    
    const in_path = try temp_dir.dir.makePath("input");
    const out_path = try temp_dir.dir.makePath("output");
    
    // Create a test file
    var test_file = try temp_dir.dir.createFile("input/test.txt", .{});
    try test_file.writeAll("test content");
    test_file.close();
    
    // Run the processor
    const config = ProcessorConfig{
        .input_dir = try temp_dir.dir.realpathAlloc(std.testing.allocator, "input"),
        .output_dir = try temp_dir.dir.realpathAlloc(std.testing.allocator, "output"),
        .asset_types = &[_]AssetType{},
        .verbose = true,
    };
    defer std.testing.allocator.free(config.input_dir);
    defer std.testing.allocator.free(config.output_dir);
    
    var processor = try AssetProcessor.init(std.testing.allocator, config);
    defer processor.deinit();
    
    try processor.processAllAssets();
    
    // Verify the file was processed
    const processed_path = try std.fs.path.join(
        std.testing.allocator, 
        &.{ config.output_dir, "test.txt" }
    );
    defer std.testing.allocator.free(processed_path);
    
    const result_file = try std.fs.openFileAbsolute(processed_path, .{});
    defer result_file.close();
    
    const content = try result_file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(content);
    
    try std.testing.expectEqualStrings("test content", content);
    
    // Verify metadata was created
    const metadata_path = try std.fs.path.join(
        std.testing.allocator, 
        &.{ config.output_dir, "asset_metadata.json" }
    );
    defer std.testing.allocator.free(metadata_path);
    
    const metadata_exists = std.fs.accessAbsolute(metadata_path, .{}) catch false;
    try std.testing.expect(metadata_exists);
}