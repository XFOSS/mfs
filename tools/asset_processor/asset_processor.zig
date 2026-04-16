const std = @import("std");
const builtin = @import("builtin");

// Remove zigimg dependency for now as it's not in the project
// const zigimg = @import("zigimg");

const AssetType = enum {
    texture,
    model,
    shader,
    font,
    audio,
    data,
    unknown,

    pub fn fromExtension(extension: []const u8) AssetType {
        const extension_map = [_]struct { ext: []const u8, kind: AssetType }{
            // Textures
            .{ .ext = ".png", .kind = .texture }, .{ .ext = ".jpg", .kind = .texture }, .{ .ext = ".tga", .kind = .texture },   .{ .ext = ".bmp", .kind = .texture }, .{ .ext = ".hdr", .kind = .texture },
            // Models
            .{ .ext = ".obj", .kind = .model },   .{ .ext = ".gltf", .kind = .model },  .{ .ext = ".glb", .kind = .model },     .{ .ext = ".fbx", .kind = .model },
            // Shaders
              .{ .ext = ".vert", .kind = .shader },
            .{ .ext = ".frag", .kind = .shader }, .{ .ext = ".comp", .kind = .shader }, .{ .ext = ".shader", .kind = .shader },
            // Fonts
            .{ .ext = ".ttf", .kind = .font },    .{ .ext = ".otf", .kind = .font },
            // Audio
            .{ .ext = ".wav", .kind = .audio },   .{ .ext = ".mp3", .kind = .audio },   .{ .ext = ".ogg", .kind = .audio },
            // Data
                .{ .ext = ".json", .kind = .data },   .{ .ext = ".xml", .kind = .data },
            .{ .ext = ".csv", .kind = .data },    .{ .ext = ".yaml", .kind = .data },   .{ .ext = ".toml", .kind = .data },
        };

        for (extension_map) |entry| {
            if (std.mem.eql(u8, extension, entry.ext)) return entry.kind;
        }
        return .unknown;
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
    compression: enum { none, lz4, zstd } = .none,
    format_version: u32 = 1,
    width: ?u32 = null,
    height: ?u32 = null,
    pixel_format: ?[]const u8 = null,
    mipmap_levels: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator) AssetMetadata {
        _ = allocator; // Remove unused parameter warning
        return .{
            .original_path = "",
            .processed_path = "",
            .asset_type = .unknown,
            .file_size = 0,
            .hash = [_]u8{0} ** 32,
            .last_modified = 0,
        };
    }

    pub fn deinit(self: *AssetMetadata, allocator: std.mem.Allocator) void {
        if (self.original_path.len > 0) {
            allocator.free(self.original_path);
        }
        if (self.processed_path.len > 0) {
            allocator.free(self.processed_path);
        }
        if (self.pixel_format) |format| {
            allocator.free(format);
        }
    }
};

// JSON serialization structures
const AssetMetadataJson = struct {
    original_path: []const u8,
    processed_path: []const u8,
    asset_type: []const u8,
    file_size: usize,
    hash: []const u8,
    last_modified: i128,
    compression: []const u8,
    format_version: u32,
    width: ?u32 = null,
    height: ?u32 = null,
    pixel_format: ?[]const u8 = null,
    mipmap_levels: ?u32 = null,
};

const AssetDatabase = struct {
    format_version: u32,
    generator: []const u8,
    timestamp: i64,
    assets: []AssetMetadataJson,
};

const AssetProcessor = struct {
    allocator: std.mem.Allocator,
    config: ProcessorConfig,
    stats: ProcessedStats,
    metadata_map: std.StringHashMap(AssetMetadata),

    pub fn init(allocator: std.mem.Allocator, config: ProcessorConfig) !*AssetProcessor {
        const self = try allocator.create(AssetProcessor);
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

        var metadata_iter = self.metadata_map.iterator();
        while (metadata_iter.next()) |entry| {
            var metadata = entry.value_ptr;
            metadata.deinit(self.allocator);
        }
        self.metadata_map.deinit();

        self.allocator.destroy(self);
    }

    pub fn processAllAssets(self: *AssetProcessor) !void {
        std.log.info("Processing assets from {s} to {s}", .{ self.config.input_dir, self.config.output_dir });

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
                try std.fs.path.join(self.allocator, &.{ subpath, entry.name });
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
                std.log.debug("Skipping {s}: asset type {s} not selected", .{ relative_path, @tagName(asset_type) });
            }
            self.stats.skipped += 1;
            return;
        }

        try self.stats.incrementType(asset_type);

        // Check if file needs processing by comparing metadata
        const full_input_path = try std.fs.path.join(self.allocator, &.{ self.config.input_dir, relative_path });
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
            const stat = std.fs.cwd().statFile(full_path) catch return false;
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
        _ = self; // Remove unused parameter warning
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
        if (std.fs.path.dirname(relative_path)) |dir| {
            const full_output_dir = try std.fs.path.join(self.allocator, &.{ self.config.output_dir, dir });
            defer self.allocator.free(full_output_dir);
            try std.fs.cwd().makePath(full_output_dir);
        }

        // Generate output path
        const output_path = try std.fs.path.join(self.allocator, &.{ self.config.output_dir, relative_path });
        defer self.allocator.free(output_path);

        // For now, just copy the texture since we don't have zigimg
        try std.fs.copyFileAbsolute(input_path, output_path, .{});

        // Create and save metadata
        var metadata = AssetMetadata.init(self.allocator);
        metadata.original_path = try self.allocator.dupe(u8, relative_path);
        metadata.processed_path = try self.allocator.dupe(u8, relative_path);
        metadata.asset_type = .texture;

        const stat = try std.fs.cwd().statFile(input_path);
        metadata.file_size = @intCast(stat.size);
        metadata.last_modified = stat.mtime;

        try self.hashFile(input_path, &metadata.hash);

        // Add texture-specific metadata (would be filled by actual image processing)
        metadata.width = 512; // Placeholder
        metadata.height = 512; // Placeholder
        metadata.pixel_format = try self.allocator.dupe(u8, "RGBA8");
        metadata.mipmap_levels = if (self.config.generate_mipmaps) 9 else 1;

        // Store metadata
        if (self.metadata_map.getPtr(relative_path)) |existing| {
            existing.deinit(self.allocator);
        }
        try self.metadata_map.put(try self.allocator.dupe(u8, relative_path), metadata);
    }

    fn processModel(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        // For now, just copy the model file since we don't have a model processor
        try self.copyFile(input_path, relative_path);
    }

    fn processShader(self: *AssetProcessor, input_path: []const u8, relative_path: []const u8) !void {
        // Read the shader source
        const shader_source = try std.fs.cwd().readFileAlloc(self.allocator, input_path, 1024 * 1024);
        defer self.allocator.free(shader_source);

        // Determine shader type from file extension
        const ext = std.fs.path.extension(relative_path);
        var shader_type: []const u8 = "unknown";

        if (std.mem.eql(u8, ext, ".vert")) {
            shader_type = "vertex";
        } else if (std.mem.eql(u8, ext, ".frag")) {
            shader_type = "fragment";
        } else if (std.mem.eql(u8, ext, ".comp")) {
            shader_type = "compute";
        } else if (std.mem.eql(u8, ext, ".geom")) {
            shader_type = "geometry";
        } else if (std.mem.eql(u8, ext, ".tesc")) {
            shader_type = "tessellation_control";
        } else if (std.mem.eql(u8, ext, ".tese")) {
            shader_type = "tessellation_evaluation";
        }

        std.log.info("Processing {s} shader: {s}", .{ shader_type, relative_path });

        // For now, just copy the shader file
        // In a full implementation, this would:
        // 1. Parse the shader source
        // 2. Validate syntax and semantics
        // 3. Compile to target format (SPIR-V, DXIL, etc.)
        // 4. Optimize the shader
        // 5. Generate reflection data
        try self.copyFile(input_path, relative_path);

        // TODO: Implement actual shader compilation with:
        // - GLSL to SPIR-V compilation
        // - HLSL to DXIL compilation
        // - Shader validation and optimization
        // - Reflection data generation
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
        if (std.fs.path.dirname(relative_path)) |dir| {
            const full_output_dir = try std.fs.path.join(self.allocator, &.{ self.config.output_dir, dir });
            defer self.allocator.free(full_output_dir);
            try std.fs.cwd().makePath(full_output_dir);
        }

        // Generate output path
        const output_path = try std.fs.path.join(self.allocator, &.{ self.config.output_dir, relative_path });
        defer self.allocator.free(output_path);

        // Copy the file
        try std.fs.copyFileAbsolute(input_path, output_path, .{});

        // Create and save metadata
        var metadata = AssetMetadata.init(self.allocator);
        metadata.original_path = try self.allocator.dupe(u8, relative_path);
        metadata.processed_path = try self.allocator.dupe(u8, relative_path);
        metadata.asset_type = AssetType.fromExtension(std.fs.path.extension(relative_path));

        const stat = try std.fs.cwd().statFile(input_path);
        metadata.file_size = @intCast(stat.size);
        metadata.last_modified = stat.mtime;

        try self.hashFile(input_path, &metadata.hash);

        // Store metadata
        const key = try self.allocator.dupe(u8, relative_path);
        const put_result = self.metadata_map.fetchPut(key, metadata) catch |err| {
            // If fetchPut failed, we need to free the key we allocated
            self.allocator.free(key);
            return err;
        };

        if (put_result) |old_entry| {
            // Free the old key and metadata
            self.allocator.free(old_entry.key);
            var old_metadata = old_entry.value;
            old_metadata.deinit(self.allocator);
        }
    }

    fn loadMetadata(self: *AssetProcessor) !void {
        const metadata_path = try std.fs.path.join(self.allocator, &.{ self.config.output_dir, "asset_metadata.json" });
        defer self.allocator.free(metadata_path);

        const file = std.fs.cwd().openFile(metadata_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Metadata doesn't exist yet, that's fine
                return;
            }
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const metadata_json = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(metadata_json);
        _ = try file.readAll(metadata_json);

        const parsed = std.json.parseFromSlice(AssetDatabase, self.allocator, metadata_json, .{}) catch |err| {
            std.log.warn("Failed to parse metadata file: {}", .{err});
            return;
        };
        defer parsed.deinit();

        const database = parsed.value;

        for (database.assets) |asset_json| {
            var metadata = AssetMetadata{
                .original_path = try self.allocator.dupe(u8, asset_json.original_path),
                .processed_path = try self.allocator.dupe(u8, asset_json.processed_path),
                .asset_type = std.meta.stringToEnum(AssetType, asset_json.asset_type) orelse .unknown,
                .file_size = asset_json.file_size,
                .hash = [_]u8{0} ** 32,
                .last_modified = asset_json.last_modified,
                .compression = std.meta.stringToEnum(@TypeOf(@as(AssetMetadata, undefined).compression), asset_json.compression) orelse .none,
                .format_version = asset_json.format_version,
                .width = asset_json.width,
                .height = asset_json.height,
                .pixel_format = if (asset_json.pixel_format) |format| try self.allocator.dupe(u8, format) else null,
                .mipmap_levels = asset_json.mipmap_levels,
            };

            // Parse hash from hex string
            if (asset_json.hash.len == 64) { // SHA-256 hex string
                var i: usize = 0;
                while (i < 32) : (i += 1) {
                    const byte = std.fmt.parseInt(u8, asset_json.hash[i * 2 .. i * 2 + 2], 16) catch 0;
                    metadata.hash[i] = byte;
                }
            }

            const key = try self.allocator.dupe(u8, metadata.original_path);
            try self.metadata_map.put(key, metadata);
        }
    }

    fn saveMetadata(self: *AssetProcessor) !void {
        const metadata_path = try std.fs.path.join(self.allocator, &.{ self.config.output_dir, "asset_metadata.json" });
        defer self.allocator.free(metadata_path);

        var file = try std.fs.cwd().createFile(metadata_path, .{});
        defer file.close();

        // Create array of asset metadata for JSON serialization
        var assets_list = std.array_list.Managed(AssetMetadataJson).init(self.allocator);
        defer assets_list.deinit();

        var metadata_iter = self.metadata_map.iterator();
        while (metadata_iter.next()) |entry| {
            const metadata = entry.value_ptr;

            // Convert hash to hex string
            const hash_str = try self.allocator.alloc(u8, 64);
            defer self.allocator.free(hash_str);
            _ = try std.fmt.bufPrint(hash_str, "{}", .{std.fmt.fmtSliceHexLower(&metadata.hash)});

            const asset_json = AssetMetadataJson{
                .original_path = metadata.original_path,
                .processed_path = metadata.processed_path,
                .asset_type = @tagName(metadata.asset_type),
                .file_size = metadata.file_size,
                .hash = try self.allocator.dupe(u8, hash_str),
                .last_modified = metadata.last_modified,
                .compression = @tagName(metadata.compression),
                .format_version = metadata.format_version,
                .width = metadata.width,
                .height = metadata.height,
                .pixel_format = metadata.pixel_format,
                .mipmap_levels = metadata.mipmap_levels,
            };

            try assets_list.append(asset_json);
        }

        const database = AssetDatabase{
            .format_version = 1,
            .generator = "MFS Asset Processor",
            .timestamp = std.time.timestamp(),
            .assets = assets_list.items,
        };

        var buffer: [8192]u8 = undefined;
        const writer = file.writer(&buffer);
        try std.json.stringify(database, .{ .whitespace = .indent_2 }, writer);

        // Clean up allocated strings
        for (assets_list.items) |asset| {
            self.allocator.free(asset.hash);
        }
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
    var asset_types = std.array_list.Managed(AssetType).init(allocator);
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

    _ = try temp_dir.dir.makeDir("input");
    _ = try temp_dir.dir.makeDir("output");

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
    const processed_path = try std.fs.path.join(std.testing.allocator, &.{ config.output_dir, "test.txt" });
    defer std.testing.allocator.free(processed_path);

    const result_file = try std.fs.openFileAbsolute(processed_path, .{});
    defer result_file.close();

    const file_size = try result_file.getEndPos();
    const content = try std.testing.allocator.alloc(u8, file_size);
    defer std.testing.allocator.free(content);
    _ = try result_file.readAll(content);

    try std.testing.expectEqualStrings("test content", content);

    // Verify metadata was created
    const metadata_path = try std.fs.path.join(std.testing.allocator, &.{ config.output_dir, "asset_metadata.json" });
    defer std.testing.allocator.free(metadata_path);

    const metadata_exists = blk: {
        std.fs.accessAbsolute(metadata_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };
    try std.testing.expect(metadata_exists);
}
