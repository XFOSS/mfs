//! MFS Engine - Level of Detail (LOD) System
//! Automatic quality scaling based on distance, performance, and visual importance
//! Supports mesh LOD, texture LOD, shader LOD, and dynamic quality adjustment
//! @performance Optimized for maintaining target frame rates while maximizing visual quality

const std = @import("std");
const builtin = @import("builtin");
const math = @import("../math/mod.zig");
const types = @import("types.zig");

/// LOD quality levels
pub const LODLevel = enum(u8) {
    ultra = 0, // Highest quality
    high = 1, // High quality
    medium = 2, // Medium quality
    low = 3, // Low quality
    minimal = 4, // Minimal quality

    pub fn getQualityFactor(self: LODLevel) f32 {
        return switch (self) {
            .ultra => 1.0,
            .high => 0.75,
            .medium => 0.5,
            .low => 0.25,
            .minimal => 0.1,
        };
    }

    pub fn getDistanceThreshold(self: LODLevel) f32 {
        return switch (self) {
            .ultra => 50.0,
            .high => 100.0,
            .medium => 200.0,
            .low => 400.0,
            .minimal => 800.0,
        };
    }
};

/// LOD object types
pub const LODObjectType = enum {
    static_mesh,
    animated_mesh,
    particle_system,
    light_source,
    texture,
    material,
    effect,
    audio_source,
};

/// LOD configuration
pub const LODConfig = struct {
    enable_distance_lod: bool = true,
    enable_performance_lod: bool = true,
    enable_importance_lod: bool = true,
    target_framerate: f32 = 60.0,
    framerate_tolerance: f32 = 5.0,
    distance_bias: f32 = 1.0,
    size_bias: f32 = 1.0,
    importance_bias: f32 = 1.0,
    hysteresis_factor: f32 = 0.1, // Prevent LOD thrashing
    update_frequency_hz: f32 = 10.0, // LOD update rate
};

/// LOD metrics for decision making
pub const LODMetrics = struct {
    distance_to_camera: f32,
    screen_size_ratio: f32, // Object size / screen size
    visual_importance: f32, // 0.0 to 1.0
    performance_impact: f32, // Relative performance cost
    last_visible_frame: u64,
    visibility_duration: f32, // Seconds visible

    pub fn calculateLODScore(self: LODMetrics, config: LODConfig) f32 {
        var score: f32 = 0.0;

        // Distance factor (closer = higher score)
        if (config.enable_distance_lod) {
            const distance_factor = 1.0 / (1.0 + self.distance_to_camera * 0.01);
            score += distance_factor * config.distance_bias;
        }

        // Size factor (larger on screen = higher score)
        const size_factor = std.math.clamp(self.screen_size_ratio * 10.0, 0.0, 1.0);
        score += size_factor * config.size_bias;

        // Importance factor
        if (config.enable_importance_lod) {
            score += self.visual_importance * config.importance_bias;
        }

        return std.math.clamp(score, 0.0, 1.0);
    }
};

/// LOD object representation
pub const LODObject = struct {
    id: u64,
    object_type: LODObjectType,
    position: math.Vec3,
    bounding_radius: f32,

    // LOD levels
    lod_levels: []LODLevelData,
    current_lod: LODLevel,
    target_lod: LODLevel,
    lod_transition_time: f32 = 0.0,

    // Metrics
    metrics: LODMetrics,

    // Flags
    is_visible: bool = false,
    is_static: bool = true,
    force_lod: ?LODLevel = null, // Override automatic LOD

    const LODLevelData = struct {
        level: LODLevel,
        mesh: ?*types.Buffer = null,
        texture: ?*types.Texture = null,
        material: ?*anyopaque = null,
        vertex_count: u32 = 0,
        triangle_count: u32 = 0,
        memory_usage: u64 = 0,
        render_cost: f32 = 1.0, // Relative rendering cost
    };

    pub fn init(allocator: std.mem.Allocator, id: u64, object_type: LODObjectType) !LODObject {
        return LODObject{
            .id = id,
            .object_type = object_type,
            .position = math.Vec3.zero(),
            .bounding_radius = 1.0,
            .lod_levels = try allocator.alloc(LODLevelData, 5), // 5 LOD levels
            .current_lod = .ultra,
            .target_lod = .ultra,
            .metrics = LODMetrics{
                .distance_to_camera = 0.0,
                .screen_size_ratio = 0.0,
                .visual_importance = 1.0,
                .performance_impact = 1.0,
                .last_visible_frame = 0,
                .visibility_duration = 0.0,
            },
        };
    }

    pub fn deinit(self: *LODObject, allocator: std.mem.Allocator) void {
        allocator.free(self.lod_levels);
    }

    pub fn updateMetrics(self: *LODObject, camera_pos: math.Vec3, screen_dimensions: math.Vec2, frame_number: u64) void {
        // Update distance to camera
        const to_camera = camera_pos.sub(self.position);
        self.metrics.distance_to_camera = to_camera.length();

        // Calculate screen size ratio
        if (self.metrics.distance_to_camera > 0.1) {
            const projected_size = (self.bounding_radius * 2.0) / self.metrics.distance_to_camera;
            const screen_diagonal = @sqrt(screen_dimensions.x * screen_dimensions.x + screen_dimensions.y * screen_dimensions.y);
            self.metrics.screen_size_ratio = projected_size / screen_diagonal;
        }

        // Update visibility tracking
        if (self.is_visible) {
            if (self.metrics.last_visible_frame == 0) {
                self.metrics.last_visible_frame = frame_number;
            }
            self.metrics.visibility_duration += 1.0 / 60.0; // Assume 60 FPS
        } else {
            self.metrics.visibility_duration = 0.0;
        }
    }

    pub fn selectLOD(self: *LODObject, config: LODConfig) LODLevel {
        // Check for forced LOD
        if (self.force_lod) |forced| {
            return forced;
        }

        // Calculate LOD score
        const score = self.metrics.calculateLODScore(config);

        // Map score to LOD level
        const new_lod = if (score > 0.8)
            LODLevel.ultra
        else if (score > 0.6)
            LODLevel.high
        else if (score > 0.4)
            LODLevel.medium
        else if (score > 0.2)
            LODLevel.low
        else
            LODLevel.minimal;

        // Apply hysteresis to prevent thrashing
        if (@intFromEnum(new_lod) != @intFromEnum(self.current_lod)) {
            const level_diff = @as(i8, @intCast(@intFromEnum(new_lod))) - @as(i8, @intCast(@intFromEnum(self.current_lod)));
            if (@abs(level_diff) == 1) {
                // Adjacent level change, apply hysteresis
                const threshold = if (level_diff > 0) score + config.hysteresis_factor else score - config.hysteresis_factor;
                if (threshold < 0.0 or threshold > 1.0) {
                    return self.current_lod; // Stay at current level
                }
            }
        }

        return new_lod;
    }

    pub fn getCurrentLODData(self: *const LODObject) ?*const LODLevelData {
        for (self.lod_levels) |*level_data| {
            if (level_data.level == self.current_lod) {
                return level_data;
            }
        }
        return null;
    }
};

/// Performance monitor for adaptive LOD
pub const PerformanceMonitor = struct {
    target_framerate: f32,
    current_framerate: f32,
    frame_times: [60]f32, // Rolling average
    frame_index: usize = 0,

    cpu_usage: f32 = 0.0,
    gpu_usage: f32 = 0.0,
    memory_usage: f32 = 0.0,

    performance_trend: Trend = .stable,

    const Trend = enum {
        improving,
        stable,
        degrading,
    };

    pub fn init(target_framerate: f32) PerformanceMonitor {
        return PerformanceMonitor{
            .target_framerate = target_framerate,
            .current_framerate = target_framerate,
            .frame_times = [_]f32{1.0 / target_framerate} ** 60,
        };
    }

    pub fn updateFrameTime(self: *PerformanceMonitor, frame_time_ms: f32) void {
        self.frame_times[self.frame_index] = frame_time_ms / 1000.0;
        self.frame_index = (self.frame_index + 1) % self.frame_times.len;

        // Calculate rolling average
        var total_time: f32 = 0.0;
        for (self.frame_times) |time| {
            total_time += time;
        }
        const avg_frame_time = total_time / @as(f32, @floatFromInt(self.frame_times.len));
        self.current_framerate = 1.0 / avg_frame_time;

        // Determine performance trend
        const performance_ratio = self.current_framerate / self.target_framerate;
        if (performance_ratio > 1.1) {
            self.performance_trend = .improving;
        } else if (performance_ratio < 0.9) {
            self.performance_trend = .degrading;
        } else {
            self.performance_trend = .stable;
        }
    }

    pub fn shouldReduceQuality(self: *const PerformanceMonitor) bool {
        return self.current_framerate < (self.target_framerate * 0.9);
    }

    pub fn shouldIncreaseQuality(self: *const PerformanceMonitor) bool {
        return self.current_framerate > (self.target_framerate * 1.1) and
            self.performance_trend == .improving;
    }

    pub fn getPerformanceScore(self: *const PerformanceMonitor) f32 {
        return std.math.clamp(self.current_framerate / self.target_framerate, 0.0, 2.0);
    }
};

/// LOD system statistics
pub const LODStats = struct {
    total_objects: u32 = 0,
    objects_by_lod: [5]u32 = [_]u32{0} ** 5,
    lod_transitions: u64 = 0,
    memory_saved_mb: f64 = 0.0,
    triangles_culled: u64 = 0,
    draw_calls_saved: u32 = 0,

    // Performance impact
    avg_update_time_ms: f64 = 0.0,
    quality_degradation: f32 = 0.0, // 0.0 = no degradation, 1.0 = maximum

    pub fn reset(self: *LODStats) void {
        self.lod_transitions = 0;
        self.triangles_culled = 0;
        self.draw_calls_saved = 0;
        self.objects_by_lod = [_]u32{0} ** 5;
    }

    pub fn getAverageLODLevel(self: *const LODStats) f32 {
        if (self.total_objects == 0) return 0.0;

        var weighted_sum: f32 = 0.0;
        for (self.objects_by_lod, 0..) |count, level| {
            weighted_sum += @as(f32, @floatFromInt(count)) * @as(f32, @floatFromInt(level));
        }

        return weighted_sum / @as(f32, @floatFromInt(self.total_objects));
    }
};

/// Main LOD system
pub const LODSystem = struct {
    allocator: std.mem.Allocator,

    // Configuration
    config: LODConfig,

    // Objects
    objects: std.HashMap(u64, LODObject, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage),

    // Performance monitoring
    performance_monitor: PerformanceMonitor,

    // Camera and scene information
    camera_position: math.Vec3,
    screen_dimensions: math.Vec2,
    current_frame: u64,

    // Update timing
    last_update_time: f64,
    update_timer: f64,

    // Statistics
    stats: LODStats,

    // Global LOD bias for performance adjustment
    global_lod_bias: f32 = 0.0, // -1.0 to 1.0, negative = lower quality

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: LODConfig) !*Self {
        const system = try allocator.create(Self);
        system.* = Self{
            .allocator = allocator,
            .config = config,
            .objects = std.HashMap(u64, LODObject, std.hash_map.HashContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .performance_monitor = PerformanceMonitor.init(config.target_framerate),
            .camera_position = math.Vec3.zero(),
            .screen_dimensions = math.Vec2.init(1920.0, 1080.0),
            .current_frame = 0,
            .last_update_time = 0.0,
            .update_timer = 0.0,
            .stats = LODStats{},
        };

        return system;
    }

    pub fn deinit(self: *Self) void {
        var iter = self.objects.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.objects.deinit();

        self.allocator.destroy(self);
    }

    /// Register an object for LOD management
    pub fn registerObject(self: *Self, object: LODObject) !void {
        try self.objects.put(object.id, object);
        self.stats.total_objects += 1;
    }

    /// Unregister an object from LOD management
    pub fn unregisterObject(self: *Self, object_id: u64) void {
        if (self.objects.fetchRemove(object_id)) |removed| {
            var mutable_object = removed.value;
            mutable_object.deinit(self.allocator);
            self.stats.total_objects -= 1;
        }
    }

    /// Update the LOD system
    pub fn update(self: *Self, delta_time: f32, camera_pos: math.Vec3, screen_dims: math.Vec2) !void {
        self.camera_position = camera_pos;
        self.screen_dimensions = screen_dims;
        self.current_frame += 1;

        // Update timer
        self.update_timer += delta_time;
        const update_interval = 1.0 / self.config.update_frequency_hz;

        if (self.update_timer < update_interval) {
            return; // Skip update this frame
        }

        const start_time = std.time.nanoTimestamp();

        self.update_timer = 0.0;

        // Update performance monitoring
        self.updatePerformanceBasedLOD();

        // Reset frame statistics
        self.stats.objects_by_lod = [_]u32{0} ** 5;

        // Update all objects
        var iter = self.objects.iterator();
        while (iter.next()) |entry| {
            var object = entry.value_ptr;

            // Update object metrics
            object.updateMetrics(camera_pos, screen_dims, self.current_frame);

            // Select new LOD level
            const old_lod = object.current_lod;
            const new_lod = object.selectLOD(self.config);

            // Apply global LOD bias
            const biased_lod = self.applyGlobalLODBias(new_lod);

            if (biased_lod != old_lod) {
                object.target_lod = biased_lod;
                object.lod_transition_time = 0.0;
                self.stats.lod_transitions += 1;
            }

            // Update current LOD (with smooth transition)
            self.updateLODTransition(object, delta_time);

            // Update statistics
            const lod_index = @intFromEnum(object.current_lod);
            if (lod_index < self.stats.objects_by_lod.len) {
                self.stats.objects_by_lod[lod_index] += 1;
            }
        }

        // Calculate update time
        const end_time = std.time.nanoTimestamp();
        self.stats.avg_update_time_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    }

    /// Update frame performance metrics
    pub fn updateFramePerformance(self: *Self, frame_time_ms: f32) void {
        self.performance_monitor.updateFrameTime(frame_time_ms);
    }

    /// Get object by ID
    pub fn getObject(self: *Self, object_id: u64) ?*LODObject {
        return self.objects.getPtr(object_id);
    }

    /// Get current statistics
    pub fn getStats(self: *const Self) LODStats {
        return self.stats;
    }

    /// Force global LOD level (for debugging/testing)
    pub fn setGlobalLODLevel(self: *Self, lod_level: ?LODLevel) void {
        var iter = self.objects.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.force_lod = lod_level;
        }
    }

    /// Get recommended LOD level for new objects at given distance
    pub fn getRecommendedLOD(self: *const Self, distance: f32, screen_size: f32) LODLevel {
        const synthetic_metrics = LODMetrics{
            .distance_to_camera = distance,
            .screen_size_ratio = screen_size,
            .visual_importance = 1.0,
            .performance_impact = 1.0,
            .last_visible_frame = self.current_frame,
            .visibility_duration = 1.0,
        };

        const score = synthetic_metrics.calculateLODScore(self.config);

        if (score > 0.8) return LODLevel.ultra else if (score > 0.6) return LODLevel.high else if (score > 0.4) return LODLevel.medium else if (score > 0.2) return LODLevel.low else return LODLevel.minimal;
    }

    // Private methods
    fn updatePerformanceBasedLOD(self: *Self) void {
        if (!self.config.enable_performance_lod) return;

        // Adjust global LOD bias based on performance
        if (self.performance_monitor.shouldReduceQuality()) {
            self.global_lod_bias = std.math.clamp(self.global_lod_bias + 0.1, -1.0, 1.0);
        } else if (self.performance_monitor.shouldIncreaseQuality()) {
            self.global_lod_bias = std.math.clamp(self.global_lod_bias - 0.05, -1.0, 1.0);
        }

        // Calculate quality degradation
        self.stats.quality_degradation = std.math.clamp(self.global_lod_bias, 0.0, 1.0);
    }

    fn applyGlobalLODBias(self: *const Self, base_lod: LODLevel) LODLevel {
        if (self.global_lod_bias == 0.0) return base_lod;

        const base_value = @as(f32, @floatFromInt(@intFromEnum(base_lod)));
        const biased_value = base_value + self.global_lod_bias * 2.0; // Scale bias
        const clamped_value = std.math.clamp(biased_value, 0.0, 4.0);
        const lod_index = @as(u8, @intFromFloat(@round(clamped_value)));

        return @enumFromInt(std.math.clamp(lod_index, 0, 4));
    }

    fn updateLODTransition(self: *Self, object: *LODObject, delta_time: f32) void {
        if (object.current_lod != object.target_lod) {
            // Smooth transition between LOD levels
            object.lod_transition_time += delta_time;

            const transition_duration = 0.2; // 200ms transition
            if (object.lod_transition_time >= transition_duration) {
                object.current_lod = object.target_lod;
                object.lod_transition_time = 0.0;
            }
        }

        _ = self; // Suppress unused parameter warning
    }
};
