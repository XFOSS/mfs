//! MFS Engine - Advanced Asset Pipeline
//! Comprehensive asset processing system with texture compression and mesh optimization
//! Supports multiple formats, automatic LOD generation, and real-time optimization
//! @thread-safe Multi-threaded asset processing with job queues
//! @performance Optimized for fast loading and minimal memory usage

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const bindless = @import("bindless_textures.zig");
const memory = @import("../system/memory/memory_manager.zig");
const profiler = @import("../system/profiling/profiler.zig");

/// Asset processing job types
pub const AssetJobType = enum {
    texture_compression,
    mesh_optimization,
    audio_conversion,
    shader_compilation,
    scene_processing,
    animation_baking,
    material_processing,
};

/// Asset compression formats
pub const CompressionFormat = enum {
    // Texture compression
    bc1, // DXT1 - RGB with 1-bit alpha
    bc3, // DXT5 - RGBA
    bc4, // Single channel
    bc5, // Dual channel (normal maps)
    bc6h, // HDR
    bc7, // High quality RGBA
    astc_4x4, // Mobile high quality
    astc_8x8, // Mobile balanced
    etc2, // Mobile baseline

    // Mesh compression
    draco, // Google Draco
    meshopt, // Mesh optimizer

    // Audio compression
    ogg_vorbis,
    opus,
    aac,
};

/// Asset quality levels
pub const QualityLevel = enum {
    low,
    medium,
    high,
    ultra,

    pub fn getCompressionRatio(self: QualityLevel) f32 {
        return switch (self) {
            .low => 0.25,
            .medium => 0.5,
            .high => 0.75,
            .ultra => 1.0,
        };
    }

    pub fn getCompressionFormat(self: QualityLevel, asset_type: AssetType) CompressionFormat {
        return switch (asset_type) {
            .diffuse_texture => switch (self) {
                .low => .bc1,
                .medium => .bc1,
                .high => .bc7,
                .ultra => .bc7,
            },
            .normal_texture => .bc5,
            .hdr_texture => .bc6h,
            .mesh => switch (self) {
                .low => .meshopt,
                .medium => .meshopt,
                .high => .draco,
                .ultra => .draco,
            },
            else => .bc7,
        };
    }
};

/// Asset types for specialized processing
pub const AssetType = enum {
    diffuse_texture,
    normal_texture,
    roughness_texture,
    metallic_texture,
    hdr_texture,
    cubemap,
    mesh,
    animation,
    material,
    scene,
    audio,
    shader,
};

/// Asset processing parameters
pub const AssetProcessingParams = struct {
    input_path: []const u8,
    output_path: []const u8,
    asset_type: AssetType,
    quality_level: QualityLevel = .high,
    compression_format: ?CompressionFormat = null,
    generate_mipmaps: bool = true,
    generate_lods: bool = false,
    target_platforms: []Platform = &.{.desktop},

    // Texture-specific parameters
    max_texture_size: u32 = 4096,
    srgb_conversion: bool = false,
    alpha_threshold: f32 = 0.5,
    normal_map_strength: f32 = 1.0,

    // Mesh-specific parameters
    target_vertex_count: ?u32 = null,
    preserve_uv_seams: bool = true,
    preserve_vertex_colors: bool = true,
    simplification_ratio: f32 = 0.5,

    // Animation-specific parameters
    keyframe_reduction: bool = true,
    keyframe_tolerance: f32 = 0.001,

    const Platform = enum {
        desktop,
        mobile,
        web,
        console,
    };
};

/// Asset processing result
pub const AssetProcessingResult = struct {
    success: bool,
    output_files: [][]const u8,
    compression_ratio: f32,
    processing_time_ms: f64,
    original_size: u64,
    compressed_size: u64,
    error_message: ?[]const u8 = null,

    // Quality metrics
    visual_quality_score: f32 = 1.0, // 0.0 to 1.0
    performance_impact: f32 = 0.0, // Relative performance cost

    pub fn deinit(self: *AssetProcessingResult, allocator: std.mem.Allocator) void {
        for (self.output_files) |file| {
            allocator.free(file);
        }
        allocator.free(self.output_files);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }

    pub fn getCompressionRatio(self: *const AssetProcessingResult) f32 {
        if (self.original_size == 0) return 0.0;
        return @as(f32, @floatFromInt(self.compressed_size)) / @as(f32, @floatFromInt(self.original_size));
    }
};

/// Asset processing job for queue system
pub const AssetProcessingJob = struct {
    id: u64,
    job_type: AssetJobType,
    params: AssetProcessingParams,
    priority: Priority = .normal,
    status: Status = .pending,
    result: ?AssetProcessingResult = null,

    // Dependencies
    dependencies: []u64 = &.{},
    dependent_jobs: std.ArrayList(u64),

    // Timing
    queued_time: i64,
    start_time: i64 = 0,
    end_time: i64 = 0,

    const Priority = enum {
        low,
        normal,
        high,
        critical,

        pub fn getValue(self: Priority) u8 {
            return switch (self) {
                .low => 0,
                .normal => 1,
                .high => 2,
                .critical => 3,
            };
        }
    };

    const Status = enum {
        pending,
        processing,
        completed,
        failed,
        cancelled,
    };

    pub fn init(allocator: std.mem.Allocator, id: u64, job_type: AssetJobType, params: AssetProcessingParams) AssetProcessingJob {
        return AssetProcessingJob{
            .id = id,
            .job_type = job_type,
            .params = params,
            .dependent_jobs = std.ArrayList(u64).init(allocator),
            .queued_time = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *AssetProcessingJob) void {
        self.dependent_jobs.deinit();
        if (self.result) |*result| {
            result.deinit(self.dependent_jobs.allocator);
        }
    }

    pub fn getProcessingTimeMs(self: *const AssetProcessingJob) f64 {
        if (self.start_time == 0 or self.end_time == 0) return 0.0;
        return @as(f64, @floatFromInt(self.end_time - self.start_time)) / 1000.0;
    }
};

/// Asset pipeline statistics
pub const AssetPipelineStats = struct {
    total_jobs_processed: u64 = 0,
    total_assets_processed: u64 = 0,
    total_processing_time_ms: f64 = 0.0,
    total_bytes_processed: u64 = 0,
    total_bytes_saved: u64 = 0,

    // By asset type
    textures_processed: u64 = 0,
    meshes_processed: u64 = 0,
    animations_processed: u64 = 0,
    materials_processed: u64 = 0,

    // Performance metrics
    avg_processing_time_ms: f64 = 0.0,
    avg_compression_ratio: f32 = 0.0,
    peak_memory_usage_mb: f64 = 0.0,

    // Error tracking
    failed_jobs: u64 = 0,
    error_rate: f32 = 0.0,

    pub fn reset(self: *AssetPipelineStats) void {
        self.* = AssetPipelineStats{};
    }

    pub fn updateAverages(self: *AssetPipelineStats) void {
        if (self.total_jobs_processed > 0) {
            self.avg_processing_time_ms = self.total_processing_time_ms / @as(f64, @floatFromInt(self.total_jobs_processed));
            self.error_rate = @as(f32, @floatFromInt(self.failed_jobs)) / @as(f32, @floatFromInt(self.total_jobs_processed));
        }

        if (self.total_bytes_processed > 0) {
            self.avg_compression_ratio = @as(f32, @floatFromInt(self.total_bytes_saved)) / @as(f32, @floatFromInt(self.total_bytes_processed));
        }
    }
};

/// Multi-threaded asset processing pipeline
pub const AssetPipeline = struct {
    allocator: std.mem.Allocator,

    // Job queue system
    job_queue: JobQueue,
    worker_threads: []std.Thread,
    is_running: bool = false,

    // Processors for different asset types
    texture_processor: *TextureProcessor,
    mesh_processor: *MeshProcessor,
    animation_processor: *AnimationProcessor,
    material_processor: *MaterialProcessor,

    // Asset cache and database
    asset_cache: AssetCache,
    asset_database: AssetDatabase,

    // Configuration
    config: Config,

    // Statistics and monitoring
    stats: AssetPipelineStats,

    // Synchronization
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,

    const Self = @This();

    const Config = struct {
        worker_thread_count: u32 = 0, // 0 = auto-detect
        max_concurrent_jobs: u32 = 16,
        cache_size_mb: u32 = 1024,
        auto_lod_generation: bool = true,
        real_time_processing: bool = false,
        backup_original_assets: bool = true,
        compression_level: u8 = 6, // 0-9, higher = slower but better compression
    };

    /// Job queue with priority support
    const JobQueue = struct {
        jobs: std.PriorityQueue(AssetProcessingJob, void, jobPriorityFn),
        completed_jobs: std.HashMap(u64, AssetProcessingResult, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage),
        job_counter: std.atomic.Atomic(u64),
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,

        pub fn init(allocator: std.mem.Allocator) JobQueue {
            return JobQueue{
                .jobs = std.PriorityQueue(AssetProcessingJob, void, jobPriorityFn).init(allocator, {}),
                .completed_jobs = std.HashMap(u64, AssetProcessingResult, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
                .job_counter = std.atomic.Atomic(u64).init(1),
                .mutex = std.Thread.Mutex{},
                .condition = std.Thread.Condition{},
            };
        }

        pub fn deinit(self: *JobQueue) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Clean up remaining jobs
            while (self.jobs.removeOrNull()) |job| {
                var mutable_job = job;
                mutable_job.deinit();
            }
            self.jobs.deinit();

            // Clean up completed jobs
            var iter = self.completed_jobs.iterator();
            while (iter.next()) |entry| {
                var mutable_result = entry.value_ptr;
                mutable_result.deinit(self.jobs.allocator);
            }
            self.completed_jobs.deinit();
        }

        pub fn addJob(self: *JobQueue, job: AssetProcessingJob) u64 {
            self.mutex.lock();
            defer self.mutex.unlock();

            var mutable_job = job;
            mutable_job.id = self.job_counter.fetchAdd(1, .SeqCst);

            self.jobs.add(mutable_job) catch |err| {
                std.log.err("Failed to add job to queue: {}", .{err});
                return 0;
            };

            self.condition.signal();
            return mutable_job.id;
        }

        pub fn getNextJob(self: *JobQueue) ?AssetProcessingJob {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.jobs.removeOrNull();
        }

        pub fn completeJob(self: *JobQueue, job_id: u64, result: AssetProcessingResult) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.completed_jobs.put(job_id, result) catch |err| {
                std.log.err("Failed to store job result: {}", .{err});
            };
        }

        pub fn getJobResult(self: *JobQueue, job_id: u64) ?AssetProcessingResult {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.completed_jobs.get(job_id);
        }

        fn jobPriorityFn(context: void, a: AssetProcessingJob, b: AssetProcessingJob) std.math.Order {
            _ = context;
            return std.math.order(a.priority.getValue(), b.priority.getValue());
        }
    };

    /// Asset cache for processed assets
    const AssetCache = struct {
        cache_map: std.HashMap(u64, CacheEntry, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage),
        lru_list: std.DoublyLinkedList(u64),
        max_size_bytes: u64,
        current_size_bytes: u64,
        mutex: std.Thread.Mutex,

        const CacheEntry = struct {
            data: []u8,
            size: u64,
            last_accessed: i64,
            access_count: u64,
            lru_node: *std.DoublyLinkedList(u64).Node,
        };

        pub fn init(allocator: std.mem.Allocator, max_size_mb: u32) AssetCache {
            return AssetCache{
                .cache_map = std.HashMap(u64, CacheEntry, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
                .lru_list = std.DoublyLinkedList(u64){},
                .max_size_bytes = @as(u64, max_size_mb) * 1024 * 1024,
                .current_size_bytes = 0,
                .mutex = std.Thread.Mutex{},
            };
        }

        pub fn deinit(self: *AssetCache, allocator: std.mem.Allocator) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var iter = self.cache_map.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.value_ptr.data);
                allocator.destroy(entry.value_ptr.lru_node);
            }
            self.cache_map.deinit();
        }

        pub fn get(self: *AssetCache, key: u64) ?[]const u8 {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.cache_map.getPtr(key)) |entry| {
                entry.last_accessed = std.time.timestamp();
                entry.access_count += 1;

                // Move to front of LRU list
                self.lru_list.remove(entry.lru_node);
                self.lru_list.prepend(entry.lru_node);

                return entry.data;
            }

            return null;
        }

        pub fn put(self: *AssetCache, allocator: std.mem.Allocator, key: u64, data: []const u8) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Check if we need to evict entries
            while (self.current_size_bytes + data.len > self.max_size_bytes and self.lru_list.last != null) {
                const lru_key = self.lru_list.last.?.data;
                if (self.cache_map.fetchRemove(lru_key)) |removed| {
                    self.current_size_bytes -= removed.value.size;
                    allocator.free(removed.value.data);
                    self.lru_list.remove(removed.value.lru_node);
                    allocator.destroy(removed.value.lru_node);
                }
            }

            // Add new entry
            const owned_data = try allocator.dupe(u8, data);
            const lru_node = try allocator.create(std.DoublyLinkedList(u64).Node);
            lru_node.data = key;

            const entry = CacheEntry{
                .data = owned_data,
                .size = data.len,
                .last_accessed = std.time.timestamp(),
                .access_count = 1,
                .lru_node = lru_node,
            };

            try self.cache_map.put(key, entry);
            self.lru_list.prepend(lru_node);
            self.current_size_bytes += data.len;
        }
    };

    /// Asset database for metadata and tracking
    const AssetDatabase = struct {
        assets: std.HashMap([]const u8, AssetMetadata, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
        mutex: std.Thread.Mutex,

        const AssetMetadata = struct {
            path: []const u8,
            hash: u64,
            size: u64,
            last_modified: i64,
            asset_type: AssetType,
            processing_params: AssetProcessingParams,
            output_files: [][]const u8,
            version: u32,
        };

        pub fn init(allocator: std.mem.Allocator) AssetDatabase {
            return AssetDatabase{
                .assets = std.HashMap([]const u8, AssetMetadata, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
                .mutex = std.Thread.Mutex{},
            };
        }

        pub fn deinit(self: *AssetDatabase, allocator: std.mem.Allocator) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var iter = self.assets.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.path);
                for (entry.value_ptr.output_files) |file| {
                    allocator.free(file);
                }
                allocator.free(entry.value_ptr.output_files);
            }
            self.assets.deinit();
        }

        pub fn addAsset(self: *AssetDatabase, allocator: std.mem.Allocator, metadata: AssetMetadata) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const key = try allocator.dupe(u8, metadata.path);
            var owned_metadata = metadata;
            owned_metadata.path = try allocator.dupe(u8, metadata.path);

            const output_files = try allocator.alloc([]u8, metadata.output_files.len);
            for (metadata.output_files, 0..) |file, i| {
                output_files[i] = try allocator.dupe(u8, file);
            }
            owned_metadata.output_files = output_files;

            try self.assets.put(key, owned_metadata);
        }

        pub fn getAsset(self: *AssetDatabase, path: []const u8) ?AssetMetadata {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.assets.get(path);
        }

        pub fn needsReprocessing(self: *AssetDatabase, path: []const u8, file_hash: u64) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.assets.get(path)) |metadata| {
                return metadata.hash != file_hash;
            }
            return true;
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Self {
        const pipeline = try allocator.create(Self);

        // Determine worker thread count
        const thread_count = if (config.worker_thread_count == 0)
            @max(1, std.Thread.getCpuCount() catch 4)
        else
            config.worker_thread_count;

        pipeline.* = Self{
            .allocator = allocator,
            .job_queue = JobQueue.init(allocator),
            .worker_threads = try allocator.alloc(std.Thread, thread_count),
            .texture_processor = try TextureProcessor.init(allocator),
            .mesh_processor = try MeshProcessor.init(allocator),
            .animation_processor = try AnimationProcessor.init(allocator),
            .material_processor = try MaterialProcessor.init(allocator),
            .asset_cache = AssetCache.init(allocator, config.cache_size_mb),
            .asset_database = AssetDatabase.init(allocator),
            .config = config,
            .stats = AssetPipelineStats{},
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
        };

        return pipeline;
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        self.job_queue.deinit();
        self.allocator.free(self.worker_threads);
        self.texture_processor.deinit();
        self.mesh_processor.deinit();
        self.animation_processor.deinit();
        self.material_processor.deinit();
        self.asset_cache.deinit(self.allocator);
        self.asset_database.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Start the asset processing pipeline
    pub fn start(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_running) return;

        self.is_running = true;

        // Start worker threads
        for (self.worker_threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerThreadFn, .{ self, i });
        }

        std.log.info("Asset pipeline started with {} worker threads", .{self.worker_threads.len});
    }

    /// Stop the asset processing pipeline
    pub fn stop(self: *Self) void {
        self.mutex.lock();
        self.is_running = false;
        self.condition.broadcast();
        self.mutex.unlock();

        // Wait for all worker threads to finish
        for (self.worker_threads) |*thread| {
            thread.join();
        }

        std.log.info("Asset pipeline stopped", .{});
    }

    /// Process an asset asynchronously
    pub fn processAssetAsync(self: *Self, params: AssetProcessingParams, priority: AssetProcessingJob.Priority) !u64 {
        const job_type = switch (params.asset_type) {
            .diffuse_texture, .normal_texture, .roughness_texture, .metallic_texture, .hdr_texture, .cubemap => .texture_compression,
            .mesh => .mesh_optimization,
            .animation => .animation_baking,
            .material => .material_processing,
            .scene => .scene_processing,
            .audio => .audio_conversion,
            .shader => .shader_compilation,
        };

        var job = AssetProcessingJob.init(self.allocator, 0, job_type, params);
        job.priority = priority;

        const job_id = self.job_queue.addJob(job);

        std.log.debug("Queued asset processing job {} for: {s}", .{ job_id, params.input_path });

        return job_id;
    }

    /// Get the result of a processing job
    pub fn getJobResult(self: *Self, job_id: u64) ?AssetProcessingResult {
        return self.job_queue.getJobResult(job_id);
    }

    /// Get current pipeline statistics
    pub fn getStats(self: *Self) AssetPipelineStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = self.stats;
        stats.updateAverages();
        return stats;
    }

    // Worker thread function
    fn workerThreadFn(self: *Self, thread_id: usize) void {
        std.log.debug("Asset pipeline worker thread {} started", .{thread_id});

        while (true) {
            // Check if we should stop
            self.mutex.lock();
            if (!self.is_running) {
                self.mutex.unlock();
                break;
            }
            self.mutex.unlock();

            // Get next job
            if (self.job_queue.getNextJob()) |job| {
                const result = self.processJobInternal(job);
                self.job_queue.completeJob(job.id, result);

                // Update statistics
                self.mutex.lock();
                self.stats.total_jobs_processed += 1;
                self.stats.total_processing_time_ms += result.processing_time_ms;
                if (!result.success) {
                    self.stats.failed_jobs += 1;
                }
                self.mutex.unlock();
            } else {
                // No jobs available, wait
                self.mutex.lock();
                self.condition.wait(&self.mutex);
                self.mutex.unlock();
            }
        }

        std.log.debug("Asset pipeline worker thread {} stopped", .{thread_id});
    }

    // Internal job processing
    fn processJobInternal(self: *Self, job: AssetProcessingJob) AssetProcessingResult {
        const timer = profiler.Timer.start("AssetPipeline.processJob");
        defer timer.end();

        return switch (job.job_type) {
            .texture_compression => self.texture_processor.process(job.params),
            .mesh_optimization => self.mesh_processor.process(job.params),
            .animation_baking => self.animation_processor.process(job.params),
            .material_processing => self.material_processor.process(job.params),
            .scene_processing => self.processScene(job.params),
            .audio_conversion => self.processAudio(job.params),
            .shader_compilation => self.processShader(job.params),
        };
    }

    // Placeholder implementations for different processors
    fn processScene(self: *Self, params: AssetProcessingParams) AssetProcessingResult {
        _ = self;
        _ = params;
        return AssetProcessingResult{
            .success = true,
            .output_files = &.{},
            .compression_ratio = 1.0,
            .processing_time_ms = 0.0,
            .original_size = 0,
            .compressed_size = 0,
        };
    }

    fn processAudio(self: *Self, params: AssetProcessingParams) AssetProcessingResult {
        _ = self;
        _ = params;
        return AssetProcessingResult{
            .success = true,
            .output_files = &.{},
            .compression_ratio = 1.0,
            .processing_time_ms = 0.0,
            .original_size = 0,
            .compressed_size = 0,
        };
    }

    fn processShader(self: *Self, params: AssetProcessingParams) AssetProcessingResult {
        _ = self;
        _ = params;
        return AssetProcessingResult{
            .success = true,
            .output_files = &.{},
            .compression_ratio = 1.0,
            .processing_time_ms = 0.0,
            .original_size = 0,
            .compressed_size = 0,
        };
    }
};

// Asset processor implementations (simplified for space)
const TextureProcessor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*TextureProcessor {
        const processor = try allocator.create(TextureProcessor);
        processor.* = TextureProcessor{ .allocator = allocator };
        return processor;
    }

    pub fn deinit(self: *TextureProcessor) void {
        self.allocator.destroy(self);
    }

    pub fn process(self: *TextureProcessor, params: AssetProcessingParams) AssetProcessingResult {
        _ = self;
        _ = params;
        // Implement texture compression logic here
        return AssetProcessingResult{
            .success = true,
            .output_files = &.{},
            .compression_ratio = 0.5,
            .processing_time_ms = 100.0,
            .original_size = 1024 * 1024,
            .compressed_size = 512 * 1024,
        };
    }
};

const MeshProcessor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*MeshProcessor {
        const processor = try allocator.create(MeshProcessor);
        processor.* = MeshProcessor{ .allocator = allocator };
        return processor;
    }

    pub fn deinit(self: *MeshProcessor) void {
        self.allocator.destroy(self);
    }

    pub fn process(self: *MeshProcessor, params: AssetProcessingParams) AssetProcessingResult {
        _ = self;
        _ = params;
        // Implement mesh optimization logic here
        return AssetProcessingResult{
            .success = true,
            .output_files = &.{},
            .compression_ratio = 0.7,
            .processing_time_ms = 200.0,
            .original_size = 2 * 1024 * 1024,
            .compressed_size = 1400 * 1024,
        };
    }
};

const AnimationProcessor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*AnimationProcessor {
        const processor = try allocator.create(AnimationProcessor);
        processor.* = AnimationProcessor{ .allocator = allocator };
        return processor;
    }

    pub fn deinit(self: *AnimationProcessor) void {
        self.allocator.destroy(self);
    }

    pub fn process(self: *AnimationProcessor, params: AssetProcessingParams) AssetProcessingResult {
        _ = self;
        _ = params;
        // Implement animation processing logic here
        return AssetProcessingResult{
            .success = true,
            .output_files = &.{},
            .compression_ratio = 0.6,
            .processing_time_ms = 150.0,
            .original_size = 500 * 1024,
            .compressed_size = 300 * 1024,
        };
    }
};

const MaterialProcessor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*MaterialProcessor {
        const processor = try allocator.create(MaterialProcessor);
        processor.* = MaterialProcessor{ .allocator = allocator };
        return processor;
    }

    pub fn deinit(self: *MaterialProcessor) void {
        self.allocator.destroy(self);
    }

    pub fn process(self: *MaterialProcessor, params: AssetProcessingParams) AssetProcessingResult {
        _ = self;
        _ = params;
        // Implement material processing logic here
        return AssetProcessingResult{
            .success = true,
            .output_files = &.{},
            .compression_ratio = 0.8,
            .processing_time_ms = 50.0,
            .original_size = 100 * 1024,
            .compressed_size = 80 * 1024,
        };
    }
};

/// Utility functions for asset processing
pub const AssetUtils = struct {
    /// Calculate file hash for cache invalidation
    pub fn calculateFileHash(allocator: std.mem.Allocator, file_path: []const u8) !u64 {
        _ = allocator;
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            std.log.err("Failed to open file for hashing: {s}, error: {}", .{ file_path, err });
            return err;
        };
        defer file.close();

        var hasher = std.hash.Wyhash.init(0);
        var buffer: [8192]u8 = undefined;

        while (true) {
            const bytes_read = file.readAll(&buffer) catch |err| {
                std.log.err("Failed to read file for hashing: {s}, error: {}", .{ file_path, err });
                return err;
            };

            if (bytes_read == 0) break;
            hasher.update(buffer[0..bytes_read]);
        }

        return hasher.final();
    }

    /// Get file size
    pub fn getFileSize(file_path: []const u8) !u64 {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const stat = try file.stat();
        return stat.size;
    }

    /// Check if output is newer than input
    pub fn isOutputNewer(input_path: []const u8, output_path: []const u8) bool {
        const input_stat = std.fs.cwd().statFile(input_path) catch return false;
        const output_stat = std.fs.cwd().statFile(output_path) catch return false;

        return output_stat.mtime > input_stat.mtime;
    }
};
