const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const AutoHashMap = std.AutoHashMap;
// const math = @import("math");
const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }
};

const Entity = @import("entity.zig").Entity;
const EntityId = @import("entity.zig").EntityId;
const SystemId = @import("entity.zig").SystemId;
const Component = @import("entity.zig").Component;

const Transform = @import("../components/transform.zig").Transform;
const RenderComponent = @import("../components/render.zig").RenderComponent;
const PhysicsComponent = @import("../components/physics.zig").PhysicsComponent;
const ScriptComponent = @import("../components/script.zig").ScriptComponent;
const AudioComponent = @import("../components/audio.zig").AudioComponent;
const LightComponent = @import("../components/light.zig").LightComponent;
const CameraComponent = @import("../components/camera.zig").CameraComponent;

const Octree = @import("../spatial/octree.zig").Octree;

pub const System = struct {
    id: SystemId,
    name: []const u8,
    priority: i32,
    enabled: bool,
    update_fn: *const fn (*System, *Scene, f32) void,

    pub fn init(id: SystemId, name: []const u8, priority: i32, update_fn: *const fn (*System, *Scene, f32) void) System {
        return System{
            .id = id,
            .name = name,
            .priority = priority,
            .enabled = true,
            .update_fn = update_fn,
        };
    }
};

pub const Scene = struct {
    allocator: Allocator,
    entities: AutoHashMap(EntityId, Entity),
    systems: ArrayList(System),
    next_entity_id: EntityId,
    next_system_id: SystemId,
    main_camera: ?EntityId,
    active: bool,
    time_scale: f32,
    physics_gravity: Vec3,
    octree: ?*Octree,
    event_handlers: AutoHashMap([]const u8, ArrayList(*const fn (*Scene, []const u8, ?*anyopaque) void)),

    pub fn init(allocator: Allocator) !*Scene {
        const scene = try allocator.create(Scene);
        scene.* = Scene{
            .allocator = allocator,
            .entities = AutoHashMap(EntityId, Entity).init(allocator),
            .systems = blk: {
                var list = ArrayList(System).init(allocator);
                try list.ensureTotalCapacity(8);
                break :blk list;
            },
            .next_entity_id = 1,
            .next_system_id = 1,
            .main_camera = null,
            .active = true,
            .time_scale = 1.0,
            .physics_gravity = Vec3.init(0, -9.81, 0),
            .octree = null,
            .event_handlers = AutoHashMap([]const u8, ArrayList(*const fn (*Scene, []const u8, ?*anyopaque) void)).init(allocator),
        };

        // Initialize octree
        const render = @import("../components/render.zig");
        const BoundingBox = render.BoundingBox;
        const world_bounds = BoundingBox.init(.{ .x = -1000, .y = -1000, .z = -1000 }, .{ .x = 1000, .y = 1000, .z = 1000 });
        scene.octree = try Octree.init(allocator, world_bounds, 10, 6);

        // Register default systems
        try scene.registerDefaultSystems();

        return scene;
    }

    pub fn deinit(self: *Scene) void {
        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.entities.deinit();

        self.systems.deinit();

        if (self.octree) |octree| {
            octree.deinit();
        }

        var event_iter = self.event_handlers.iterator();
        while (event_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.event_handlers.deinit();

        self.allocator.destroy(self);
    }

    pub fn createEntity(self: *Scene, name: []const u8) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;

        var entity = try Entity.init(self.allocator, entity_id, name);

        // All entities have a transform component by default
        try entity.addComponent(Component{ .transform = Transform.init() });

        try self.entities.put(entity_id, entity);
        return entity_id;
    }

    pub fn destroyEntity(self: *Scene, entity_id: EntityId) void {
        if (self.entities.fetchRemove(entity_id)) |entry| {
            var entity = entry.value;

            // Remove from parent
            if (entity.parent) |parent_id| {
                if (self.getEntity(parent_id)) |parent| {
                    parent.removeChild(entity_id);
                }
            }

            // Destroy children
            for (entity.children.items) |child_id| {
                self.destroyEntity(child_id);
            }

            entity.deinit();
        }
    }

    pub fn getEntity(self: *Scene, entity_id: EntityId) ?*Entity {
        return self.entities.getPtr(entity_id);
    }

    pub fn findEntityByName(self: *Scene, name: []const u8) ?*Entity {
        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.name, name)) {
                return entry.value_ptr;
            }
        }
        return null;
    }

    pub fn findEntitiesByTag(self: *Scene, tag: []const u8, results: *ArrayList(EntityId), _: Allocator) !void {
        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.tag, tag)) {
                try results.append(entry.key_ptr.*);
            }
        }
    }

    pub fn addSystem(self: *Scene, name: []const u8, priority: i32, update_fn: *const fn (*System, *Scene, f32) void) !SystemId {
        const system_id = self.next_system_id;
        self.next_system_id += 1;

        const system = System.init(system_id, name, priority, update_fn);
        try self.systems.append(system);

        // Sort systems by priority
        std.sort.heap(System, self.systems.items, {}, systemCompare);

        return system_id;
    }

    fn systemCompare(context: void, a: System, b: System) bool {
        _ = context;
        return a.priority < b.priority;
    }

    pub fn removeSystem(self: *Scene, system_id: SystemId) void {
        for (self.systems.items, 0..) |system, i| {
            if (system.id == system_id) {
                _ = self.systems.swapRemove(i);
                break;
            }
        }
    }

    pub fn update(self: *Scene, delta_time: f32) void {
        if (!self.active) return;

        const scaled_delta = delta_time * self.time_scale;

        // Update systems
        for (self.systems.items) |*system| {
            if (system.enabled) {
                system.update_fn(system, self, scaled_delta);
            }
        }
    }

    pub fn addEventListener(self: *Scene, event_name: []const u8, handler: *const fn (*Scene, []const u8, ?*anyopaque) void) !void {
        const key = try self.allocator.dupe(u8, event_name);

        if (self.event_handlers.getPtr(key)) |handlers| {
            try handlers.append(handler);
        } else {
            var handlers = ArrayList(*const fn (*Scene, []const u8, ?*anyopaque) void).init(self.allocator);
            try handlers.ensureTotalCapacity(4);
            try handlers.append(handler);
            try self.event_handlers.put(key, handlers);
        }
    }

    pub fn dispatchEvent(self: *Scene, event_name: []const u8, data: ?*anyopaque) void {
        if (self.event_handlers.get(event_name)) |handlers| {
            for (handlers.items) |handler| {
                handler(self, event_name, data);
            }
        }
    }

    fn registerDefaultSystems(self: *Scene) !void {
        const transform_system = @import("../systems/transform_system.zig");
        const physics_system = @import("../systems/physics_system.zig");
        const script_system = @import("../systems/script_system.zig");
        const audio_system = @import("../systems/audio_system.zig");
        const render_system = @import("../systems/render_system.zig");

        _ = try self.addSystem("Transform", 0, transform_system.update);
        _ = try self.addSystem("Physics", 100, physics_system.update);
        _ = try self.addSystem("Script", 200, script_system.update);
        _ = try self.addSystem("Audio", 300, audio_system.update);
        _ = try self.addSystem("Render", 1000, render_system.update);
    }
};
