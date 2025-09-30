//! Entity Component System (ECS) for MFS Engine
//! Simple ECS implementation for game entities and components

const std = @import("std");

/// Entity ID type
pub const EntityId = u32;

/// Component type identifier
pub const ComponentType = u32;

/// Maximum number of entities
pub const MAX_ENTITIES = 10000;

/// Maximum number of component types
pub const MAX_COMPONENT_TYPES = 64;

/// Entity Component System World
pub const World = struct {
    allocator: std.mem.Allocator,
    next_entity_id: EntityId,
    alive_entities: std.bit_set.IntegerBitSet(MAX_ENTITIES),
    component_masks: [MAX_ENTITIES]std.bit_set.IntegerBitSet(MAX_COMPONENT_TYPES),
    component_pools: std.array_list.Managed(?*anyopaque),
    systems: std.array_list.Managed(*System),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .next_entity_id = 0,
            .alive_entities = std.bit_set.IntegerBitSet(MAX_ENTITIES).initEmpty(),
            .component_masks = [_]std.bit_set.IntegerBitSet(MAX_COMPONENT_TYPES){std.bit_set.IntegerBitSet(MAX_COMPONENT_TYPES).initEmpty()} ** MAX_ENTITIES,
            .component_pools = std.array_list.Managed(?*anyopaque).init(allocator),
            .systems = std.array_list.Managed(*System).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up component pools
        for (self.component_pools.items) |pool| {
            if (pool) |p| {
                self.allocator.destroy(@as(*ComponentPool, @ptrCast(@alignCast(p))));
            }
        }
        self.component_pools.deinit();

        // Clean up systems
        for (self.systems.items) |system| {
            system.deinit();
            self.allocator.destroy(system);
        }
        self.systems.deinit();
    }

    /// Create a new entity
    pub fn createEntity(self: *Self) !EntityId {
        if (self.next_entity_id >= MAX_ENTITIES) {
            return error.TooManyEntities;
        }

        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        self.alive_entities.set(entity_id);
        self.component_masks[entity_id] = std.bit_set.IntegerBitSet(MAX_COMPONENT_TYPES).initEmpty();

        return entity_id;
    }

    /// Destroy an entity
    pub fn destroyEntity(self: *Self, entity_id: EntityId) void {
        if (entity_id >= MAX_ENTITIES or !self.alive_entities.isSet(entity_id)) {
            return;
        }

        // Remove all components from this entity
        self.component_masks[entity_id] = std.bit_set.IntegerBitSet(MAX_COMPONENT_TYPES).initEmpty();
        self.alive_entities.unset(entity_id);
    }

    /// Check if an entity is alive
    pub fn isAlive(self: *const Self, entity_id: EntityId) bool {
        return entity_id < MAX_ENTITIES and self.alive_entities.isSet(entity_id);
    }

    /// Add a component to an entity
    pub fn addComponent(self: *Self, entity_id: EntityId, component_type: ComponentType, component: anytype) !void {
        if (!self.isAlive(entity_id) or component_type >= MAX_COMPONENT_TYPES) {
            return error.InvalidEntity;
        }

        // Ensure component pool exists
        while (self.component_pools.items.len <= component_type) {
            try self.component_pools.append(null);
        }

        if (self.component_pools.items[component_type] == null) {
            const pool = try self.allocator.create(ComponentPool);
            pool.* = ComponentPool.init(self.allocator, @TypeOf(component));
            self.component_pools.items[component_type] = pool;
        }

        // Add component to pool
        const pool = @as(*ComponentPool, @ptrCast(@alignCast(self.component_pools.items[component_type].?)));
        try pool.add(entity_id, component);

        // Set component mask
        self.component_masks[entity_id].set(component_type);
    }

    /// Remove a component from an entity
    pub fn removeComponent(self: *Self, entity_id: EntityId, component_type: ComponentType) void {
        if (!self.isAlive(entity_id) or component_type >= self.component_pools.items.len) {
            return;
        }

        if (self.component_pools.items[component_type]) |pool| {
            const typed_pool = @as(*ComponentPool, @ptrCast(@alignCast(pool)));
            typed_pool.remove(entity_id);
        }

        self.component_masks[entity_id].unset(component_type);
    }

    /// Check if an entity has a component
    pub fn hasComponent(self: *const Self, entity_id: EntityId, component_type: ComponentType) bool {
        if (!self.isAlive(entity_id) or component_type >= MAX_COMPONENT_TYPES) {
            return false;
        }
        return self.component_masks[entity_id].isSet(component_type);
    }

    /// Add a system to the world
    pub fn addSystem(self: *Self, system: *System) !void {
        try self.systems.append(system);
    }

    /// Update all systems
    pub fn update(self: *Self, delta_time: f64) !void {
        for (self.systems.items) |system| {
            try system.update(self, delta_time);
        }
    }

    /// Get all entities with a specific component mask
    pub fn getEntitiesWithComponents(self: *const Self, required_mask: std.bit_set.IntegerBitSet(MAX_COMPONENT_TYPES)) std.ArrayList(EntityId) {
        var entities = std.ArrayList(EntityId).init(self.allocator);

        var entity_id: EntityId = 0;
        while (entity_id < self.next_entity_id) : (entity_id += 1) {
            if (self.isAlive(entity_id)) {
                const entity_mask = self.component_masks[entity_id];
                if (entity_mask.intersectWith(required_mask).eql(required_mask)) {
                    entities.append(entity_id) catch continue;
                }
            }
        }

        return entities;
    }
};

/// Generic component pool
pub const ComponentPool = struct {
    allocator: std.mem.Allocator,
    components: std.HashMap(EntityId, *anyopaque, std.hash_map.DefaultContext(EntityId), std.hash_map.default_max_load_percentage),
    component_size: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, comptime T: type) Self {
        return Self{
            .allocator = allocator,
            .components = std.HashMap(EntityId, *anyopaque, std.hash_map.DefaultContext(EntityId), std.hash_map.default_max_load_percentage).init(allocator),
            .component_size = @sizeOf(T),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all component memory
        var iterator = self.components.iterator();
        while (iterator.next()) |entry| {
            self.allocator.destroy(@as(*u8, @ptrCast(entry.value_ptr.*)));
        }
        self.components.deinit();
    }

    pub fn add(self: *Self, entity_id: EntityId, component: anytype) !void {
        const component_ptr = try self.allocator.create(@TypeOf(component));
        component_ptr.* = component;
        try self.components.put(entity_id, component_ptr);
    }

    pub fn remove(self: *Self, entity_id: EntityId) void {
        if (self.components.get(entity_id)) |component_ptr| {
            self.allocator.destroy(@as(*u8, @ptrCast(component_ptr)));
            _ = self.components.remove(entity_id);
        }
    }

    pub fn get(self: *Self, entity_id: EntityId, comptime T: type) ?*T {
        if (self.components.get(entity_id)) |component_ptr| {
            return @as(*T, @ptrCast(@alignCast(component_ptr)));
        }
        return null;
    }
};

/// Base system interface
pub const System = struct {
    vtable: *const VTable,

    const VTable = struct {
        update: *const fn (*System, *World, f64) anyerror!void,
        deinit: *const fn (*System) void,
    };

    pub fn update(self: *System, world: *World, delta_time: f64) !void {
        return self.vtable.update(self, world, delta_time);
    }

    pub fn deinit(self: *System) void {
        self.vtable.deinit(self);
    }
};

/// Example transform component
pub const Transform = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    rotation: f32 = 0.0,
    scale: f32 = 1.0,
};

/// Example velocity component
pub const Velocity = struct {
    dx: f32 = 0.0,
    dy: f32 = 0.0,
    dz: f32 = 0.0,
};

/// Component type constants
pub const ComponentTypes = struct {
    pub const TRANSFORM: ComponentType = 0;
    pub const VELOCITY: ComponentType = 1;
    pub const RENDER: ComponentType = 2;
    pub const PHYSICS: ComponentType = 3;
};

test "ECS basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var world = World.init(allocator);
    defer world.deinit();

    // Create entity
    const entity = try world.createEntity();
    try testing.expect(world.isAlive(entity));

    // Add transform component
    const transform = Transform{ .x = 10.0, .y = 20.0, .z = 30.0 };
    try world.addComponent(entity, ComponentTypes.TRANSFORM, transform);
    try testing.expect(world.hasComponent(entity, ComponentTypes.TRANSFORM));

    // Remove component
    world.removeComponent(entity, ComponentTypes.TRANSFORM);
    try testing.expect(!world.hasComponent(entity, ComponentTypes.TRANSFORM));

    // Destroy entity
    world.destroyEntity(entity);
    try testing.expect(!world.isAlive(entity));
}
