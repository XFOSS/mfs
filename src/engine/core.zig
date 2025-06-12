const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;

// Import engine modules
const vk = @import("../graphics/backends/vulkan/vk.zig");
const material = @import("../graphics/backends/vulkan/material.zig");
const ui = @import("../ui/window.zig");
const worker = @import("../ui/worker.zig");

// Core engine types
pub const EntityId = u32;
pub const ComponentId = u32;
pub const SystemId = u32;

// Time management
pub const Time = struct {
    delta_time: f32,
    total_time: f32,
    frame_count: u64,
    fps: f32,
    target_fps: f32,

    const Self = @This();

    pub fn init(target_fps: f32) Self {
        return Self{
            .delta_time = 0.0,
            .total_time = 0.0,
            .frame_count = 0,
            .fps = 0.0,
            .target_fps = target_fps,
        };
    }

    pub fn update(self: *Self, new_delta: f32) void {
        self.delta_time = new_delta;
        self.total_time += new_delta;
        self.frame_count += 1;

        if (new_delta > 0.0) {
            self.fps = 1.0 / new_delta;
        }
    }

    pub fn getTargetFrameTime(self: *Self) f32 {
        return 1.0 / self.target_fps;
    }
};

// Input system
pub const InputState = struct {
    keys: [256]bool,
    mouse_x: f32,
    mouse_y: f32,
    mouse_buttons: [8]bool,
    mouse_wheel: f32,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .keys = [_]bool{false} ** 256,
            .mouse_x = 0.0,
            .mouse_y = 0.0,
            .mouse_buttons = [_]bool{false} ** 8,
            .mouse_wheel = 0.0,
        };
    }

    pub fn isKeyPressed(self: *const Self, key: u8) bool {
        return if (key < 256) self.keys[key] else false;
    }

    pub fn isMouseButtonPressed(self: *const Self, button: u8) bool {
        return if (button < 8) self.mouse_buttons[button] else false;
    }

    pub fn setKey(self: *Self, key: u8, pressed: bool) void {
        if (key < 256) {
            self.keys[key] = pressed;
        }
    }

    pub fn setMouseButton(self: *Self, button: u8, pressed: bool) void {
        if (button < 8) {
            self.mouse_buttons[button] = pressed;
        }
    }

    pub fn setMousePosition(self: *Self, x: f32, y: f32) void {
        self.mouse_x = x;
        self.mouse_y = y;
    }
};

// Component system
pub const Component = struct {
    id: ComponentId,
    entity: EntityId,
    data: []u8,

    const Self = @This();

    pub fn init(id: ComponentId, entity: EntityId, data: []u8) Self {
        return Self{
            .id = id,
            .entity = entity,
            .data = data,
        };
    }

    pub fn getData(self: *const Self, comptime T: type) *T {
        return @ptrCast(@alignCast(self.data.ptr));
    }
};

// Transform component
pub const Transform = struct {
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .position = [3]f32{ 0.0, 0.0, 0.0 },
            .rotation = [3]f32{ 0.0, 0.0, 0.0 },
            .scale = [3]f32{ 1.0, 1.0, 1.0 },
        };
    }

    pub fn getMatrix(self: *const Self) [16]f32 {
        // Create transformation matrix from position, rotation, scale
        const cos_x = @cos(self.rotation[0]);
        const sin_x = @sin(self.rotation[0]);
        const cos_y = @cos(self.rotation[1]);
        const sin_y = @sin(self.rotation[1]);
        const cos_z = @cos(self.rotation[2]);
        const sin_z = @sin(self.rotation[2]);

        return [16]f32{
            self.scale[0] * (cos_y * cos_z),
            self.scale[0] * (cos_y * sin_z),
            self.scale[0] * (-sin_y),
            0.0,

            self.scale[1] * (sin_x * sin_y * cos_z - cos_x * sin_z),
            self.scale[1] * (sin_x * sin_y * sin_z + cos_x * cos_z),
            self.scale[1] * (sin_x * cos_y),
            0.0,

            self.scale[2] * (cos_x * sin_y * cos_z + sin_x * sin_z),
            self.scale[2] * (cos_x * sin_y * sin_z - sin_x * cos_z),
            self.scale[2] * (cos_x * cos_y),
            0.0,

            self.position[0],
            self.position[1],
            self.position[2],
            1.0,
        };
    }
};

// Render component
pub const RenderComponent = struct {
    mesh_id: u32,
    material_id: u32,
    visible: bool,
    cast_shadows: bool,
    receive_shadows: bool,

    const Self = @This();

    pub fn init(mesh_id: u32, material_id: u32) Self {
        return Self{
            .mesh_id = mesh_id,
            .material_id = material_id,
            .visible = true,
            .cast_shadows = true,
            .receive_shadows = true,
        };
    }
};

// Entity component system
pub const EntityManager = struct {
    allocator: Allocator,
    entities: ArrayList(EntityId),
    components: HashMap(ComponentId, ArrayList(Component), std.hash_map.AutoContext(ComponentId)),
    next_entity_id: EntityId,
    next_component_id: ComponentId,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .entities = ArrayList(EntityId).init(allocator),
            .components = HashMap(ComponentId, ArrayList(Component), std.hash_map.AutoContext(ComponentId)).init(allocator),
            .next_entity_id = 1,
            .next_component_id = 1,
        };
    }

    pub fn deinit(self: *Self) void {
        var component_iter = self.components.valueIterator();
        while (component_iter.next()) |component_list| {
            for (component_list.items) |component| {
                self.allocator.free(component.data);
            }
            component_list.deinit();
        }
        self.components.deinit();
        self.entities.deinit();
    }

    pub fn createEntity(self: *Self) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        try self.entities.append(entity_id);
        return entity_id;
    }

    pub fn destroyEntity(self: *Self, entity_id: EntityId) void {
        // Remove entity from list
        for (self.entities.items, 0..) |id, i| {
            if (id == entity_id) {
                _ = self.entities.swapRemove(i);
                break;
            }
        }

        // Remove all components for this entity
        var component_iter = self.components.valueIterator();
        while (component_iter.next()) |component_list| {
            var i: usize = 0;
            while (i < component_list.items.len) {
                if (component_list.items[i].entity == entity_id) {
                    self.allocator.free(component_list.items[i].data);
                    _ = component_list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    pub fn addComponent(self: *Self, entity_id: EntityId, comptime T: type, component_data: T) !ComponentId {
        const component_id = self.next_component_id;
        self.next_component_id += 1;

        const data = try self.allocator.alloc(u8, @sizeOf(T));
        const typed_data: *T = @ptrCast(@alignCast(data.ptr));
        typed_data.* = component_data;

        const component = Component.init(component_id, entity_id, data);

        const type_id = @intFromPtr(&T);
        var gop = try self.components.getOrPut(@intCast(type_id));
        if (!gop.found_existing) {
            gop.value_ptr.* = ArrayList(Component).init(self.allocator);
        }

        try gop.value_ptr.append(component);
        return component_id;
    }

    pub fn getComponent(self: *Self, entity_id: EntityId, comptime T: type) ?*T {
        const type_id = @intFromPtr(&T);
        if (self.components.get(@intCast(type_id))) |component_list| {
            for (component_list.items) |*component| {
                if (component.entity == entity_id) {
                    return component.getData(T);
                }
            }
        }
        return null;
    }

    pub fn getAllComponents(self: *Self, comptime T: type) []Component {
        const type_id = @intFromPtr(&T);
        if (self.components.get(@intCast(type_id))) |component_list| {
            return component_list.items;
        }
        return &[_]Component{};
    }
};

// System interface
pub const System = struct {
    id: SystemId,
    name: []const u8,
    enabled: bool,
    update_fn: *const fn (system: *System, entities: *EntityManager, time: *const Time, input: *const InputState) void,

    const Self = @This();

    pub fn init(id: SystemId, name: []const u8, update_fn: *const fn (system: *System, entities: *EntityManager, time: *const Time, input: *const InputState) void) Self {
        return Self{
            .id = id,
            .name = name,
            .enabled = true,
            .update_fn = update_fn,
        };
    }

    pub fn update(self: *Self, entities: *EntityManager, time: *const Time, input: *const InputState) void {
        if (self.enabled) {
            self.update_fn(self, entities, time, input);
        }
    }
};

// Scene management
pub const Scene = struct {
    name: []const u8,
    entities: EntityManager,
    systems: ArrayList(System),
    camera_entity: ?EntityId,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8) Self {
        return Self{
            .name = name,
            .entities = EntityManager.init(allocator),
            .systems = ArrayList(System).init(allocator),
            .camera_entity = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit();
        self.systems.deinit();
    }

    pub fn addSystem(self: *Self, system: System) !void {
        try self.systems.append(system);
    }

    pub fn update(self: *Self, time: *const Time, input: *const InputState) void {
        for (self.systems.items) |*system| {
            system.update(&self.entities, time, input);
        }
    }
};

// Asset management
pub const AssetType = enum {
    texture,
    mesh,
    material,
    shader,
    audio,
    font,
};

pub const Asset = struct {
    id: u32,
    name: []const u8,
    asset_type: AssetType,
    data: []u8,
    ref_count: u32,

    const Self = @This();

    pub fn init(id: u32, name: []const u8, asset_type: AssetType, data: []u8) Self {
        return Self{
            .id = id,
            .name = name,
            .asset_type = asset_type,
            .data = data,
            .ref_count = 1,
        };
    }
};

pub const AssetManager = struct {
    allocator: Allocator,
    assets: HashMap(u32, Asset, std.hash_map.AutoContext(u32)),
    name_to_id: HashMap(u32, u32, std.hash_map.AutoContext(u32)),
    next_id: u32,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .assets = HashMap(u32, Asset, std.hash_map.AutoContext(u32)).init(allocator),
            .name_to_id = HashMap(u32, u32, std.hash_map.AutoContext(u32)).init(allocator),
            .next_id = 1,
        };
    }

    pub fn deinit(self: *Self) void {
        var asset_iter = self.assets.valueIterator();
        while (asset_iter.next()) |asset| {
            self.allocator.free(asset.name);
            self.allocator.free(asset.data);
        }
        self.assets.deinit();
        self.name_to_id.deinit();
    }

    pub fn loadAsset(self: *Self, name: []const u8, asset_type: AssetType, data: []u8) !u32 {
        const asset_id = self.next_id;
        self.next_id += 1;

        const name_copy = try self.allocator.dupe(u8, name);
        const data_copy = try self.allocator.dupe(u8, data);

        const asset = Asset.init(asset_id, name_copy, asset_type, data_copy);
        try self.assets.put(asset_id, asset);

        const name_hash = std.hash_map.hashString(name);
        try self.name_to_id.put(name_hash, asset_id);

        return asset_id;
    }

    pub fn getAsset(self: *Self, asset_id: u32) ?*Asset {
        return self.assets.getPtr(asset_id);
    }

    pub fn getAssetByName(self: *Self, name: []const u8) ?*Asset {
        const name_hash = std.hash_map.hashString(name);
        if (self.name_to_id.get(name_hash)) |asset_id| {
            return self.getAsset(asset_id);
        }
        return null;
    }

    pub fn unloadAsset(self: *Self, asset_id: u32) void {
        if (self.assets.getPtr(asset_id)) |asset| {
            asset.ref_count -= 1;
            if (asset.ref_count == 0) {
                self.allocator.free(asset.name);
                self.allocator.free(asset.data);
                _ = self.assets.remove(asset_id);
            }
        }
    }
};

// Event system
pub const EventType = enum {
    window_resize,
    key_press,
    key_release,
    mouse_button_press,
    mouse_button_release,
    mouse_move,
    custom,
};

pub const Event = struct {
    event_type: EventType,
    data: []u8,

    const Self = @This();

    pub fn init(event_type: EventType, data: []u8) Self {
        return Self{
            .event_type = event_type,
            .data = data,
        };
    }

    pub fn getData(self: *const Self, comptime T: type) *T {
        return @ptrCast(@alignCast(self.data.ptr));
    }
};

pub const EventHandler = struct {
    callback: *const fn (event: *const Event) void,

    const Self = @This();

    pub fn init(callback: *const fn (event: *const Event) void) Self {
        return Self{
            .callback = callback,
        };
    }
};

pub const EventManager = struct {
    allocator: Allocator,
    handlers: HashMap(EventType, ArrayList(EventHandler), std.hash_map.AutoContext(EventType)),
    event_queue: ArrayList(Event),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .handlers = HashMap(EventType, ArrayList(EventHandler), std.hash_map.AutoContext(EventType)).init(allocator),
            .event_queue = ArrayList(Event).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var handler_iter = self.handlers.valueIterator();
        while (handler_iter.next()) |handler_list| {
            handler_list.deinit();
        }
        self.handlers.deinit();

        for (self.event_queue.items) |event| {
            self.allocator.free(event.data);
        }
        self.event_queue.deinit();
    }

    pub fn subscribe(self: *Self, event_type: EventType, handler: EventHandler) !void {
        var gop = try self.handlers.getOrPut(event_type);
        if (!gop.found_existing) {
            gop.value_ptr.* = ArrayList(EventHandler).init(self.allocator);
        }
        try gop.value_ptr.append(handler);
    }

    pub fn emit(self: *Self, event_type: EventType, data: []const u8) !void {
        const data_copy = try self.allocator.dupe(u8, data);
        const event = Event.init(event_type, data_copy);
        try self.event_queue.append(event);
    }

    pub fn processEvents(self: *Self) void {
        for (self.event_queue.items) |*event| {
            if (self.handlers.get(event.event_type)) |handler_list| {
                for (handler_list.items) |handler| {
                    handler.callback(event);
                }
            }
            self.allocator.free(event.data);
        }
        self.event_queue.clearRetainingCapacity();
    }
};

// Core engine
pub const Engine = struct {
    allocator: Allocator,
    time: Time,
    input: InputState,
    current_scene: ?Scene,
    asset_manager: AssetManager,
    event_manager: EventManager,
    thread_pool: ?worker.ThreadPool,
    window_manager: ?ui.WindowManager,
    running: bool,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .time = Time.init(60.0),
            .input = InputState.init(),
            .current_scene = null,
            .asset_manager = AssetManager.init(allocator),
            .event_manager = EventManager.init(allocator),
            .thread_pool = null,
            .window_manager = null,
            .running = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_scene) |*scene| {
            scene.deinit();
        }
        self.asset_manager.deinit();
        self.event_manager.deinit();
        if (self.thread_pool) |*pool| {
            pool.deinit();
        }
        if (self.window_manager) |*wm| {
            wm.deinit();
        }
    }

    pub fn initialize(self: *Self) !void {
        // Initialize subsystems
        self.thread_pool = try worker.ThreadPool.init(self.allocator, 4);
        self.window_manager = try ui.WindowManager.init(self.allocator);

        // Create default scene
        self.current_scene = Scene.init(self.allocator, "Default Scene");

        self.running = true;
    }

    pub fn loadScene(self: *Self, scene: Scene) void {
        if (self.current_scene) |*current| {
            current.deinit();
        }
        self.current_scene = scene;
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.time.update(delta_time);
        self.event_manager.processEvents();

        if (self.current_scene) |*scene| {
            scene.update(&self.time, &self.input);
        }
    }

    pub fn run(self: *Self) !void {
        try self.initialize();

        var last_time = std.time.timestamp();

        while (self.running) {
            const current_time = std.time.timestamp();
            const delta_time = @as(f32, @floatFromInt(current_time - last_time)) / 1000000.0; // Convert to seconds
            last_time = current_time;

            self.update(delta_time);

            // Limit frame rate
            const target_frame_time = self.time.getTargetFrameTime();
            if (delta_time < target_frame_time) {
                const sleep_time = target_frame_time - delta_time;
                std.time.sleep(@as(u64, @intFromFloat(sleep_time * 1000000000.0))); // Convert to nanoseconds
            }
        }
    }

    pub fn shutdown(self: *Self) void {
        self.running = false;
    }
};

// Built-in systems
pub fn transformSystem(system: *System, entities: *EntityManager, time: *const Time, input: *const InputState) void {
    _ = system;
    _ = time;
    _ = input;

    const transforms = entities.getAllComponents(Transform);
    for (transforms) |component| {
        const transform = component.getData(Transform);
        _ = transform; // Transform updates would go here
    }
}

pub fn renderSystem(system: *System, entities: *EntityManager, time: *const Time, input: *const InputState) void {
    _ = system;
    _ = time;
    _ = input;

    const render_components = entities.getAllComponents(RenderComponent);
    for (render_components) |component| {
        const render_comp = component.getData(RenderComponent);
        if (render_comp.visible) {
            // Rendering logic would go here
        }
    }
}
