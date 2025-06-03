const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic.Value;

// Advanced logging with structured output
const log = std.log.scoped(.nyx_engine);

// SIMD and vectorization support
const Vector = std.meta.Vector;
const vector_width = if (builtin.cpu.arch == .x86_64) 4 else 2;
const Vec4f = Vector(4, f32);
const Vec8f = Vector(8, f32);

// Core modules with enhanced imports
pub const math = @import("math/math.zig");
pub const physics = @import("physics/physics_improved.zig");
pub const neural = @import("neural/brain.zig");
pub const scene = @import("scene/scene.zig");
pub const rendering = @import("render.zig");
pub const platform = @import("platform/platform.zig");
pub const gpu = @import("gpu.zig");
pub const ui = @import("ui/simple_window.zig");
pub const xr = @import("xr.zig");
pub const audio = @import("audio/audio.zig");

// Advanced memory management with object pooling
pub const ObjectPool = struct {
    pub fn Pool(comptime T: type) type {
        return struct {
            const Self = @This();
            const PoolNode = struct {
                data: T,
                next: ?*PoolNode,
            };

            allocator: Allocator,
            free_list: ?*PoolNode,
            allocated_nodes: std.ArrayList(*PoolNode),
            mutex: Mutex,
            capacity: usize,
            current_size: Atomic(usize),

            pub fn init(allocator: Allocator, initial_capacity: usize) !Self {
                var pool = Self{
                    .allocator = allocator,
                    .free_list = null,
                    .allocated_nodes = std.ArrayList(*PoolNode).init(allocator),
                    .mutex = Mutex{},
                    .capacity = initial_capacity,
                    .current_size = Atomic(usize).init(0),
                };

                try pool.allocated_nodes.ensureTotalCapacity(initial_capacity);
                try pool.expandPool(initial_capacity);
                return pool;
            }

            pub fn deinit(self: *Self) void {
                for (self.allocated_nodes.items) |node| {
                    self.allocator.destroy(node);
                }
                self.allocated_nodes.deinit();
            }

            pub fn acquire(self: *Self) !*T {
                self.mutex.lock();
                defer self.mutex.unlock();

                if (self.free_list) |node| {
                    self.free_list = node.next;
                    _ = self.current_size.fetchSub(1, .monotonic);
                    return &node.data;
                } else {
                    // Expand pool if needed
                    try self.expandPool(self.capacity / 2);
                    return self.acquire();
                }
            }

            pub fn release(self: *Self, item: *T) void {
                self.mutex.lock();
                defer self.mutex.unlock();

                const node: *PoolNode = @fieldParentPtr("data", item);
                node.next = self.free_list;
                self.free_list = node;
                _ = self.current_size.fetchAdd(1, .monotonic);
            }

            fn expandPool(self: *Self, count: usize) !void {
                for (0..count) |_| {
                    const node = try self.allocator.create(PoolNode);
                    node.* = PoolNode{
                        .data = undefined,
                        .next = self.free_list,
                    };
                    self.free_list = node;
                    try self.allocated_nodes.append(node);
                }
                _ = self.current_size.fetchAdd(count, .monotonic);
            }

            pub fn getSize(self: *const Self) usize {
                return self.current_size.load(.monotonic);
            }
        };
    }
};

// Enhanced event system with priority queues and filtering
pub const Event = union(enum) {
    // Input events
    window_resize: struct { width: u32, height: u32, timestamp: i64 },
    window_close: struct { timestamp: i64 },
    window_focus: struct { focused: bool, timestamp: i64 },
    key_press: struct { key: u32, scancode: u32, modifiers: u32, timestamp: i64 },
    key_release: struct { key: u32, scancode: u32, modifiers: u32, timestamp: i64 },
    key_repeat: struct { key: u32, scancode: u32, modifiers: u32, timestamp: i64 },
    mouse_move: struct { x: f32, y: f32, dx: f32, dy: f32, timestamp: i64 },
    mouse_press: struct { button: u32, x: f32, y: f32, timestamp: i64 },
    mouse_release: struct { button: u32, x: f32, y: f32, timestamp: i64 },
    mouse_scroll: struct { x: f32, y: f32, timestamp: i64 },

    // Touch events
    touch_start: struct { id: u32, x: f32, y: f32, pressure: f32, timestamp: i64 },
    touch_move: struct { id: u32, x: f32, y: f32, pressure: f32, timestamp: i64 },
    touch_end: struct { id: u32, x: f32, y: f32, timestamp: i64 },

    // Gamepad events
    gamepad_connected: struct { id: u32, name: []const u8, timestamp: i64 },
    gamepad_disconnected: struct { id: u32, timestamp: i64 },
    gamepad_button: struct { id: u32, button: u32, pressed: bool, timestamp: i64 },
    gamepad_axis: struct { id: u32, axis: u32, value: f32, timestamp: i64 },

    // System events
    app_quit: struct { timestamp: i64 },
    app_pause: struct { timestamp: i64 },
    app_resume: struct { timestamp: i64 },
    memory_warning: struct { available_mb: u64, timestamp: i64 },

    // Custom events
    custom: struct { id: u32, data: ?*anyopaque, size: usize, timestamp: i64 },

    // Asset events
    asset_loaded: struct { path: []const u8, asset_type: AssetType, timestamp: i64 },
    asset_failed: struct { path: []const u8, error_msg: []const u8, timestamp: i64 },
    asset_reloaded: struct { path: []const u8, timestamp: i64 },

    pub fn getPriority(self: Event) u8 {
        return switch (self) {
            .app_quit, .memory_warning => 255,
            .window_close, .app_pause, .app_resume => 200,
            .window_resize, .window_focus => 150,
            .key_press, .key_release, .mouse_press, .mouse_release => 100,
            .mouse_move, .mouse_scroll, .gamepad_button, .gamepad_axis => 80,
            .touch_start, .touch_move, .touch_end => 70,
            .asset_loaded, .asset_failed, .asset_reloaded => 50,
            .gamepad_connected, .gamepad_disconnected => 40,
            .custom => 30,
            else => 10,
        };
    }

    pub fn getTimestamp(self: Event) i64 {
        return switch (self) {
            inline else => |event| event.timestamp,
        };
    }
};

// Advanced event handler with filtering and priority
pub const EventHandler = struct {
    callback: *const fn (Event, *anyopaque) void,
    context: *anyopaque,
    filter: EventFilter,
    priority: u8,
    enabled: Atomic(bool),

    pub const EventFilter = struct {
        event_types: std.EnumSet(std.meta.Tag(Event)),
        min_priority: u8 = 0,
        max_frequency_hz: ?f32 = null,
        last_processed_time: i64 = 0,

        pub fn accepts(self: *EventFilter, event: Event) bool {
            const event_tag = @as(std.meta.Tag(Event), event);

            if (!self.event_types.contains(event_tag)) return false;
            if (event.getPriority() < self.min_priority) return false;

            if (self.max_frequency_hz) |max_freq| {
                const current_time = std.time.nanoTimestamp();
                const min_interval = @as(i64, @intFromFloat(std.time.ns_per_s / max_freq));
                if (current_time - self.last_processed_time < min_interval) return false;
                self.last_processed_time = current_time;
            }

            return true;
        }
    };
};

pub const EventSystem = struct {
    allocator: Allocator,
    handlers: std.ArrayList(EventHandler),
    event_queue: std.PriorityQueue(Event, void, eventPriorityCompare),
    event_pool: ObjectPool.Pool(Event),
    mutex: Mutex,
    processing: Atomic(bool),
    stats: EventStats,

    const EventStats = struct {
        events_processed: Atomic(u64) = Atomic(u64).init(0),
        events_dropped: Atomic(u64) = Atomic(u64).init(0),
        processing_time_ns: Atomic(u64) = Atomic(u64).init(0),
        peak_queue_size: Atomic(u32) = Atomic(u32).init(0),
    };

    pub fn init(allocator: Allocator) !EventSystem {
        return EventSystem{
            .allocator = allocator,
            .handlers = std.ArrayList(EventHandler).init(allocator),
            .event_queue = std.PriorityQueue(Event, void, eventPriorityCompare).init(allocator, {}),
            .event_pool = try ObjectPool.Pool(Event).init(allocator, 1000),
            .mutex = Mutex{},
            .processing = Atomic(bool).init(false),
            .stats = EventStats{},
        };
    }

    pub fn deinit(self: *EventSystem) void {
        self.handlers.deinit();
        self.event_queue.deinit();
        self.event_pool.deinit();
    }

    pub fn addHandler(self: *EventSystem, handler: EventHandler) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.handlers.append(handler);

        // Sort handlers by priority
        std.sort.pdq(EventHandler, self.handlers.items, {}, handlerPriorityCompare);
    }

    pub fn removeHandler(self: *EventSystem, context: *anyopaque) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.handlers.items.len) {
            if (self.handlers.items[i].context == context) {
                _ = self.handlers.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn pushEvent(self: *EventSystem, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const queue_size = @as(u32, @intCast(self.event_queue.len));
        _ = self.stats.peak_queue_size.fetchMax(queue_size, .monotonic);

        // Drop low priority events if queue is full
        if (queue_size > 10000) {
            if (event.getPriority() < 100) {
                _ = self.stats.events_dropped.fetchAdd(1, .monotonic);
                return;
            }

            // Remove lowest priority event
            if (self.event_queue.len > 0) {
                _ = self.event_queue.remove();
                _ = self.stats.events_dropped.fetchAdd(1, .monotonic);
            }
        }

        try self.event_queue.add(event);
    }

    pub fn processEvents(self: *EventSystem) !void {
        if (self.processing.swap(true, .acquire)) return; // Already processing
        defer self.processing.store(false, .release);

        const start_time = std.time.nanoTimestamp();
        var processed_count: u64 = 0;

        self.mutex.lock();
        const events_to_process = self.event_queue.len;
        self.mutex.unlock();

        for (0..events_to_process) |_| {
            self.mutex.lock();
            const event = if (self.event_queue.len > 0) self.event_queue.remove() else null;
            self.mutex.unlock();

            if (event) |evt| {
                for (self.handlers.items) |*handler| {
                    if (handler.enabled.load(.monotonic) and handler.filter.accepts(evt)) {
                        handler.callback(evt, handler.context);
                    }
                }
                processed_count += 1;
            } else break;
        }

        const end_time = std.time.nanoTimestamp();
        _ = self.stats.processing_time_ns.fetchAdd(@intCast(end_time - start_time), .monotonic);
        _ = self.stats.events_processed.fetchAdd(processed_count, .monotonic);
    }

    pub fn getStats(self: *const EventSystem) EventStats {
        return self.stats;
    }

    fn eventPriorityCompare(context: void, a: Event, b: Event) std.math.Order {
        _ = context;
        return std.math.order(b.getPriority(), a.getPriority()); // Higher priority first
    }

    fn handlerPriorityCompare(context: void, a: EventHandler, b: EventHandler) bool {
        _ = context;
        return a.priority > b.priority;
    }
};

// Enhanced asset management with streaming and caching
pub const AssetType = enum(u8) {
    texture = 0,
    model = 1,
    sound = 2,
    shader = 3,
    material = 4,
    font = 5,
    script = 6,
    config = 7,
    animation = 8,
    particle_system = 9,
    level_data = 10,
    audio_bank = 11,
    shader_program = 12,
    compute_shader = 13,
    video = 14,
    compressed_archive = 15,
    binary_data = 16,
    json_data = 17,
    xml_data = 18,
    custom = 255,

    pub fn getFileExtensions(self: AssetType) []const []const u8 {
        return switch (self) {
            .texture => &[_][]const u8{ ".png", ".jpg", ".jpeg", ".bmp", ".tga", ".dds", ".ktx", ".basis" },
            .model => &[_][]const u8{ ".obj", ".fbx", ".gltf", ".glb", ".dae", ".3ds", ".ply" },
            .sound => &[_][]const u8{ ".wav", ".mp3", ".ogg", ".flac", ".aiff", ".m4a" },
            .shader => &[_][]const u8{ ".vert", ".frag", ".geom", ".comp", ".glsl", ".hlsl", ".spv" },
            .material => &[_][]const u8{ ".mat", ".mtl" },
            .font => &[_][]const u8{ ".ttf", ".otf", ".woff", ".woff2" },
            .script => &[_][]const u8{ ".lua", ".js", ".py", ".zig", ".c", ".cpp" },
            .config => &[_][]const u8{ ".json", ".toml", ".yaml", ".yml", ".ini", ".cfg" },
            .animation => &[_][]const u8{ ".anim", ".bvh", ".fbx" },
            .video => &[_][]const u8{ ".mp4", ".avi", ".mov", ".webm", ".mkv" },
            .compressed_archive => &[_][]const u8{ ".zip", ".tar", ".gz", ".7z", ".rar" },
            else => &[_][]const u8{},
        };
    }
};

pub const AssetState = enum(u8) {
    unloaded = 0,
    loading = 1,
    loaded = 2,
    load_error = 3,
    streaming = 4,
    cached = 5,
    hot_reloading = 6,
};

pub const AssetLoadOptions = struct {
    persistent: bool = false,
    hot_reloadable: bool = false,
    async_load: bool = true,
    use_cache: bool = true,
    streaming: bool = false,
    compression: CompressionType = .none,
    priority: LoadPriority = .normal,
    max_memory_mb: ?u32 = null,
    custom_loader: ?*const fn ([]const u8, Allocator, AssetLoadOptions) anyerror!AssetData = null,

    pub const CompressionType = enum {
        none,
        lz4,
        zstd,
        gzip,
        custom,
    };

    pub const LoadPriority = enum(u8) {
        critical = 255,
        high = 200,
        normal = 100,
        low = 50,
        background = 10,
    };
};

pub const AssetData = union(AssetType) {
    texture: TextureData,
    model: ModelData,
    sound: SoundData,
    shader: ShaderData,
    material: MaterialData,
    font: FontData,
    script: ScriptData,
    config: ConfigData,
    animation: AnimationData,
    particle_system: ParticleSystemData,
    level_data: LevelData,
    audio_bank: AudioBankData,
    shader_program: ShaderProgramData,
    compute_shader: ComputeShaderData,
    video: VideoData,
    compressed_archive: CompressedArchiveData,
    binary_data: BinaryData,
    json_data: JsonData,
    xml_data: XmlData,
    custom: CustomData,

    const TextureData = struct {
        width: u32,
        height: u32,
        channels: u32,
        format: u32,
        data: []u8,
        mipmap_levels: u32 = 1,
        compression: ?AssetLoadOptions.CompressionType = null,
    };

    const ModelData = struct {
        vertices: []f32,
        indices: []u32,
        materials: []u32,
        bone_data: ?[]BoneData = null,
        animations: ?[]AnimationData = null,
        bounding_box: math.BoundingBox,
    };

    const SoundData = struct {
        sample_rate: u32,
        channels: u32,
        bit_depth: u32,
        data: []u8,
        duration_seconds: f32,
        format: SoundFormat,

        const SoundFormat = enum { pcm, mp3, ogg, flac };
    };

    const ShaderData = struct {
        source: []const u8,
        stage: ShaderStage,
        entry_point: []const u8 = "main",
        target_api: TargetAPI = .opengl,

        const ShaderStage = enum { vertex, fragment, geometry, compute, tessellation_control, tessellation_evaluation };
        const TargetAPI = enum { opengl, vulkan, directx, metal, webgpu };
    };

    const MaterialData = struct {
        diffuse_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
        specular_color: [3]f32 = .{ 1.0, 1.0, 1.0 },
        roughness: f32 = 0.5,
        metallic: f32 = 0.0,
        emission: [3]f32 = .{ 0.0, 0.0, 0.0 },
        normal_scale: f32 = 1.0,
        textures: std.StringHashMap(u32),
    };

    const FontData = struct {
        ttf_data: []u8,
        size_pixels: u32,
        glyph_atlas: ?TextureData = null,
        glyph_metrics: std.AutoHashMap(u32, GlyphMetrics),

        const GlyphMetrics = struct {
            advance_x: f32,
            advance_y: f32,
            bearing_x: f32,
            bearing_y: f32,
            width: f32,
            height: f32,
        };
    };

    const ScriptData = struct {
        source: []const u8,
        language: ScriptLanguage,
        bytecode: ?[]u8 = null,

        const ScriptLanguage = enum { lua, javascript, python, zig, c, cpp };
    };

    const ConfigData = struct {
        data: std.json.Value,
        format: ConfigFormat,

        const ConfigFormat = enum { json, toml, yaml, ini };
    };

    const AnimationData = struct {
        duration: f32,
        keyframes: []Keyframe,
        bone_count: u32,

        const Keyframe = struct {
            time: f32,
            bone_transforms: []math.Transform,
        };
    };

    const ParticleSystemData = struct {
        max_particles: u32,
        emission_rate: f32,
        lifetime: f32,
        initial_velocity: math.Vec3(f32),
        gravity: math.Vec3(f32),
        size_over_time: []f32,
        color_over_time: [][4]f32,
    };

    const LevelData = struct {
        entities: []EntityData,
        terrain: ?TerrainData = null,
        lighting: LightingData,
        audio_zones: []AudioZoneData,

        const EntityData = struct {
            id: u64,
            transform: math.Transform,
            components: std.StringHashMap(ComponentData),
        };

        const ComponentData = struct {
            type_name: []const u8,
            data: []u8,
        };

        const TerrainData = struct {
            heightmap: TextureData,
            materials: []MaterialData,
            detail_maps: []TextureData,
        };

        const LightingData = struct {
            ambient_color: [3]f32,
            directional_lights: []DirectionalLight,
            point_lights: []PointLight,
            spot_lights: []SpotLight,

            const DirectionalLight = struct {
                direction: math.Vec3(f32),
                color: [3]f32,
                intensity: f32,
            };

            const PointLight = struct {
                position: math.Vec3(f32),
                color: [3]f32,
                intensity: f32,
                radius: f32,
            };

            const SpotLight = struct {
                position: math.Vec3(f32),
                direction: math.Vec3(f32),
                color: [3]f32,
                intensity: f32,
                inner_angle: f32,
                outer_angle: f32,
            };
        };

        const AudioZoneData = struct {
            bounds: math.BoundingBox,
            ambient_sound: ?u32 = null,
            reverb_settings: ReverbSettings,

            const ReverbSettings = struct {
                room_size: f32 = 0.5,
                damping: f32 = 0.5,
                wet_level: f32 = 0.3,
                dry_level: f32 = 0.7,
            };
        };
    };

    const AudioBankData = struct {
        sounds: std.StringHashMap(SoundData),
        metadata: AudioBankMetadata,

        const AudioBankMetadata = struct {
            version: u32,
            compression: AssetLoadOptions.CompressionType,
            total_size: u64,
            sound_count: u32,
        };
    };

    const ShaderProgramData = struct {
        vertex_shader: u32,
        fragment_shader: u32,
        geometry_shader: ?u32 = null,
        compute_shader: ?u32 = null,
        uniforms: std.StringHashMap(UniformInfo),

        const UniformInfo = struct {
            location: i32,
            type: UniformType,
            size: u32,

            const UniformType = enum {
                float,
                vec2,
                vec3,
                vec4,
                int,
                ivec2,
                ivec3,
                ivec4,
                mat2,
                mat3,
                mat4,
                texture2d,
                texture_cube,
                sampler2d,
                sampler_cube,
            };
        };
    };

    const ComputeShaderData = struct {
        source: []const u8,
        local_size_x: u32 = 1,
        local_size_y: u32 = 1,
        local_size_z: u32 = 1,
        uniforms: std.StringHashMap(ShaderProgramData.UniformInfo),
    };

    const VideoData = struct {
        width: u32,
        height: u32,
        fps: f32,
        duration: f32,
        codec: VideoCodec,
        audio_track: ?SoundData = null,

        const VideoCodec = enum { h264, h265, vp8, vp9, av1 };
    };

    const CompressedArchiveData = struct {
        files: std.StringHashMap([]u8),
        compression: AssetLoadOptions.CompressionType,
        original_size: u64,
        compressed_size: u64,
    };

    const BinaryData = struct {
        data: []u8,
        metadata: std.StringHashMap([]const u8),
    };

    const JsonData = struct {
        value: std.json.Value,
        schema_version: ?[]const u8 = null,
    };

    const XmlData = struct {
        content: []const u8,
        encoding: []const u8 = "UTF-8",
        schema: ?[]const u8 = null,
    };

    const CustomData = struct {
        type_id: u64,
        data: []u8,
        deserializer: ?*const fn ([]u8, Allocator) anyerror!*anyopaque = null,
    };

    const BoneData = struct {
        name: []const u8,
        parent_index: ?u32,
        bind_pose: math.Transform,
    };
};

pub const AssetStats = struct {
    size_bytes: u64,
    load_time_ns: u64,
    last_accessed: i64,
    access_count: u64,
    memory_usage: u64,
    reference_count: u32,
    compression_ratio: f32 = 1.0,
};

pub const Asset = struct {
    path: []const u8,
    type: AssetType,
    state: Atomic(AssetState),
    data: ?AssetData,
    stats: AssetStats,
    options: AssetLoadOptions,
    allocator: Allocator,
    mutex: Mutex,
    dependencies: std.ArrayList([]const u8),
    dependents: std.ArrayList([]const u8),
    version: u64,
    hash: u64,

    pub fn init(allocator: Allocator, path: []const u8, asset_type: AssetType, options: AssetLoadOptions) !Asset {
        const path_copy = try allocator.dupe(u8, path);
        const hash = std.hash_map.hashString(path);

        return Asset{
            .path = path_copy,
            .type = asset_type,
            .state = Atomic(AssetState).init(.unloaded),
            .data = null,
            .stats = AssetStats{
                .size_bytes = 0,
                .load_time_ns = 0,
                .last_accessed = std.time.timestamp(),
                .access_count = 0,
                .memory_usage = 0,
                .reference_count = 0,
            },
            .options = options,
            .allocator = allocator,
            .mutex = Mutex{},
            .dependencies = std.ArrayList([]const u8).init(allocator),
            .dependents = std.ArrayList([]const u8).init(allocator),
            .version = 1,
            .hash = hash,
        };
    }

    pub fn deinit(self: *Asset) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free asset data based on type
        if (self.data) |data| {
            switch (data) {
                .texture => |tex| self.allocator.free(tex.data),
                .model => |model| {
                    self.allocator.free(model.vertices);
                    self.allocator.free(model.indices);
                    self.allocator.free(model.materials);
                    if (model.bone_data) |bones| self.allocator.free(bones);
                    if (model.animations) |anims| self.allocator.free(anims);
                },
                .sound => |sound| self.allocator.free(sound.data),
                .shader => |shader| self.allocator.free(shader.source),
                .font => |font| {
                    self.allocator.free(font.ttf_data);
                    // Note: glyph_metrics cleanup handled by allocator since it uses AutoHashMap
                },
                .script => |script| {
                    self.allocator.free(script.source);
                    if (script.bytecode) |bytecode| self.allocator.free(bytecode);
                },
                .config => |config| config.data.deinit(),
                .binary_data => |binary| self.allocator.free(binary.data),
                .custom => |custom| self.allocator.free(custom.data),
                else => {},
            }
        }

        // Free dependencies and dependents
        for (self.dependencies.items) |dep| {
            self.allocator.free(dep);
        }
        self.dependencies.deinit();

        for (self.dependents.items) |dep| {
            self.allocator.free(dep);
        }
        self.dependents.deinit();

        self.allocator.free(self.path);
    }

    pub fn getTypedData(self: *Asset, comptime T: type) ?*T {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.stats.last_accessed = std.time.timestamp();
        self.stats.access_count += 1;

        if (self.data) |*data| {
            return switch (T) {
                AssetData.TextureData => if (data.* == .texture) &data.texture else null,
                AssetData.ModelData => if (data.* == .model) &data.model else null,
                AssetData.SoundData => if (data.* == .sound) &data.sound else null,
                AssetData.ShaderData => if (data.* == .shader) &data.shader else null,
                AssetData.MaterialData => if (data.* == .material) &data.material else null,
                AssetData.FontData => if (data.* == .font) &data.font else null,
                AssetData.ScriptData => if (data.* == .script) &data.script else null,
                AssetData.ConfigData => if (data.* == .config) &data.config else null,
                AssetData.BinaryData => if (data.* == .binary_data) &data.binary_data else null,
                AssetData.CustomData => if (data.* == .custom) &data.custom else null,
                else => null,
            };
        }
        return null;
    }

    pub fn isLoaded(self: *const Asset) bool {
        return self.state.load(.monotonic) == .loaded;
    }

    pub fn getState(self: *const Asset) AssetState {
        return self.state.load(.monotonic);
    }

    pub fn addDependency(self: *Asset, dependency_path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, dependency_path);
        try self.dependencies.append(path_copy);
    }

    pub fn addDependent(self: *Asset, dependent_path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, dependent_path);
        try self.dependents.append(path_copy);
    }
};

pub const ResourceManagerStats = struct {
    asset_count: u64,
    memory_used: u64,
    load_count: u64,
    cache_hits: u64,
    failed_loads: u64,
};

pub const ResourceManager = struct {
    allocator: Allocator,
    assets: std.AutoHashMap(u64, *Asset),
    stats: ResourceManagerStats,
    mutex: Mutex,

    pub fn init(allocator: Allocator) ResourceManager {
        return ResourceManager{
            .allocator = allocator,
            .assets = std.HashMap(u64, *Asset, std.hash_map.DefaultHashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .stats = ResourceManagerStats{
                .asset_count = 0,
                .memory_used = 0,
                .load_count = 0,
                .cache_hits = 0,
                .failed_loads = 0,
            },
            .mutex = Mutex{},
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        var iterator = self.assets.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.assets.deinit();
    }

    pub fn loadAsset(self: *ResourceManager, path: []const u8, asset_type: AssetType, options: AssetLoadOptions) !*Asset {
        const hash_value = std.hash_map.hashString(path);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.assets.get(hash_value)) |existing_asset| {
            self.stats.cache_hits += 1;
            return existing_asset;
        }

        const asset = try self.allocator.create(Asset);
        asset.* = try Asset.init(self.allocator, path, asset_type, options);

        try self.assets.put(hash_value, asset);
        self.stats.asset_count += 1;
        self.stats.load_count += 1;

        return asset;
    }

    pub fn getAsset(self: *ResourceManager, path: []const u8) ?*Asset {
        const hash_value = std.hash_map.hashString(path);

        self.mutex.lock();
        defer self.mutex.unlock();

        return self.assets.get(hash_value);
    }

    pub fn getStats(self: *const ResourceManager) ResourceManagerStats {
        return self.stats;
    }
};

// Enhanced engine configuration
pub const EngineError = error{
    InitializationFailed,
    InvalidConfiguration,
    ResourceLoadError,
    OutOfMemory,
    GraphicsAPIError,
    AudioSystemError,
    NetworkError,
    FileSystemError,
    ThreadingError,
    ValidationError,
};

pub const EngineConfig = struct {
    enable_gpu: bool = true,
    enable_physics: bool = true,
    enable_neural: bool = false,
    enable_xr: bool = false,
    enable_audio: bool = true,
    enable_networking: bool = false,
    window_handle: ?*anyopaque = null,
    backend: u32 = 0,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    window_title: []const u8 = "Nyx Engine",
    fullscreen: bool = false,
    vsync: bool = true,
    enable_debug_allocator: bool = false,
    max_memory_budget_mb: u64 = 512,
    max_worker_threads: u32 = 0,
    enable_task_profiling: bool = false,
    target_fps: u32 = 60,
    enable_frame_pacing: bool = true,
    asset_path: []const u8 = "assets/",
    shader_path: []const u8 = "shaders/",
    config_path: []const u8 = "config/",
    shadow_quality: u32 = 2,
    texture_quality: u32 = 2,
    antialiasing: u32 = 2,

    pub fn validate(self: *const EngineConfig) !void {
        if (self.window_width == 0 or self.window_height == 0) {
            return EngineError.InvalidConfiguration;
        }
        if (self.target_fps == 0 or self.target_fps > 500) {
            return EngineError.InvalidConfiguration;
        }
        if (self.max_memory_budget_mb < 32) {
            return EngineError.InvalidConfiguration;
        }
    }
};

pub const Engine = struct {
    allocator: Allocator,
    config: EngineConfig,
    event_system: EventSystem,
    resource_manager: ResourceManager,
    initialized: bool = false,

    pub fn init(allocator: Allocator, config: EngineConfig) !Engine {
        try config.validate();

        return Engine{
            .allocator = allocator,
            .config = config,
            .event_system = try EventSystem.init(allocator),
            .resource_manager = ResourceManager.init(allocator),
            .initialized = true,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.event_system.deinit();
        self.resource_manager.deinit();
        self.initialized = false;
    }

    pub fn update(self: *Engine, delta_time: f64) !void {
        _ = delta_time;
        if (!self.initialized) return EngineError.InitializationFailed;

        try self.event_system.processEvents();
    }

    pub fn render(self: *Engine, interpolation_alpha: f32) !void {
        _ = interpolation_alpha;
        if (!self.initialized) return EngineError.InitializationFailed;
    }
};
