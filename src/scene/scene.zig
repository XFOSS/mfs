const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SceneConfig = struct {
    max_entities: u32 = 1000,
    enable_culling: bool = true,
    enable_lod: bool = false,
};

pub const EntityId = u32;
pub const ComponentId = u32;

pub const Transform = struct {
    position: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 },
    rotation: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 },
    scale: [3]f32 = [3]f32{ 1.0, 1.0, 1.0 },

    pub fn init() Transform {
        return Transform{};
    }

    pub fn setPosition(self: *Transform, x: f32, y: f32, z: f32) void {
        self.position = [3]f32{ x, y, z };
    }

    pub fn setRotation(self: *Transform, x: f32, y: f32, z: f32) void {
        self.rotation = [3]f32{ x, y, z };
    }

    pub fn setScale(self: *Transform, x: f32, y: f32, z: f32) void {
        self.scale = [3]f32{ x, y, z };
    }
};

pub const Model = struct {
    allocator: Allocator,
    name: []const u8,
    vertex_count: u32 = 0,
    triangle_count: u32 = 0,
    loaded: bool = false,

    pub fn init(allocator: Allocator, name: []const u8) !*Model {
        const model = try allocator.create(Model);
        const owned_name = try allocator.dupe(u8, name);
        model.* = Model{
            .allocator = allocator,
            .name = owned_name,
        };
        return model;
    }

    pub fn deinit(self: *Model) void {
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    pub fn loadFromFile(self: *Model, path: []const u8) !void {
        _ = path; // TODO: Implement actual model loading
        self.vertex_count = 8; // Placeholder for cube
        self.triangle_count = 12; // Placeholder for cube
        self.loaded = true;
    }

    pub fn isLoaded(self: *const Model) bool {
        return self.loaded;
    }
};

pub const Material = struct {
    allocator: Allocator,
    name: []const u8,
    diffuse_color: [4]f32 = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
    specular_color: [3]f32 = [3]f32{ 1.0, 1.0, 1.0 },
    shininess: f32 = 32.0,
    loaded: bool = false,

    pub fn init(allocator: Allocator, name: []const u8) !*Material {
        const material = try allocator.create(Material);
        const owned_name = try allocator.dupe(u8, name);
        material.* = Material{
            .allocator = allocator,
            .name = owned_name,
        };
        return material;
    }

    pub fn deinit(self: *Material) void {
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    pub fn setDiffuseColor(self: *Material, r: f32, g: f32, b: f32, a: f32) void {
        self.diffuse_color = [4]f32{ r, g, b, a };
    }

    pub fn setSpecularColor(self: *Material, r: f32, g: f32, b: f32) void {
        self.specular_color = [3]f32{ r, g, b };
    }

    pub fn setShininess(self: *Material, shininess: f32) void {
        self.shininess = shininess;
    }

    pub fn isLoaded(self: *const Material) bool {
        return self.loaded;
    }
};

pub const Entity = struct {
    id: EntityId,
    transform: Transform,
    active: bool = true,

    pub fn init(id: EntityId) Entity {
        return Entity{
            .id = id,
            .transform = Transform.init(),
        };
    }
};

pub const Camera = struct {
    position: [3]f32 = [3]f32{ 0.0, 0.0, 5.0 },
    target: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 },
    up: [3]f32 = [3]f32{ 0.0, 1.0, 0.0 },
    fov: f32 = 45.0,
    aspect: f32 = 16.0 / 9.0,
    near: f32 = 0.1,
    far: f32 = 100.0,

    pub fn init() Camera {
        return Camera{};
    }

    pub fn setPosition(self: *Camera, x: f32, y: f32, z: f32) void {
        self.position = [3]f32{ x, y, z };
    }

    pub fn setTarget(self: *Camera, x: f32, y: f32, z: f32) void {
        self.target = [3]f32{ x, y, z };
    }

    pub fn setPerspective(self: *Camera, fov: f32, aspect: f32, near: f32, far: f32) void {
        self.fov = fov;
        self.aspect = aspect;
        self.near = near;
        self.far = far;
    }
};

pub const Scene = struct {
    allocator: Allocator,
    config: SceneConfig,
    entities: std.ArrayList(Entity),
    camera: Camera,
    next_entity_id: EntityId = 1,
    active: bool = true,

    const Self = @This();

    pub fn init(allocator: Allocator, config: SceneConfig) !Scene {
        return Scene{
            .allocator = allocator,
            .config = config,
            .entities = std.ArrayList(Entity).init(allocator),
            .camera = Camera.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit();
    }

    pub fn createEntity(self: *Self) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;

        const entity = Entity.init(entity_id);
        try self.entities.append(entity);

        return entity_id;
    }

    pub fn destroyEntity(self: *Self, entity_id: EntityId) bool {
        for (self.entities.items, 0..) |entity, i| {
            if (entity.id == entity_id) {
                _ = self.entities.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn getEntity(self: *Self, entity_id: EntityId) ?*Entity {
        for (self.entities.items) |*entity| {
            if (entity.id == entity_id) {
                return entity;
            }
        }
        return null;
    }

    pub fn getEntityTransform(self: *Self, entity_id: EntityId) ?*Transform {
        if (self.getEntity(entity_id)) |entity| {
            return &entity.transform;
        }
        return null;
    }

    pub fn setEntityPosition(self: *Self, entity_id: EntityId, x: f32, y: f32, z: f32) bool {
        if (self.getEntityTransform(entity_id)) |transform| {
            transform.setPosition(x, y, z);
            return true;
        }
        return false;
    }

    pub fn setEntityRotation(self: *Self, entity_id: EntityId, x: f32, y: f32, z: f32) bool {
        if (self.getEntityTransform(entity_id)) |transform| {
            transform.setRotation(x, y, z);
            return true;
        }
        return false;
    }

    pub fn getCamera(self: *Self) *Camera {
        return &self.camera;
    }

    pub fn getEntityCount(self: *const Self) u32 {
        return @intCast(self.entities.items.len);
    }

    pub fn getAllEntities(self: *Self) []Entity {
        return self.entities.items;
    }

    pub fn update(self: *Self, delta_time: f64) void {
        _ = delta_time; // Currently unused but available for future updates

        // Update any scene-level logic here
        // For now, just ensure scene remains active
        if (!self.active) return;

        // Future: Update entity systems, animations, etc.
    }

    pub fn isActive(self: *const Self) bool {
        return self.active;
    }

    pub fn setActive(self: *Self, active: bool) void {
        self.active = active;
    }
};

test "scene creation and entity management" {
    const allocator = std.testing.allocator;
    var scene = try Scene.init(allocator, SceneConfig{});
    defer scene.deinit();

    // Test entity creation
    const entity1 = try scene.createEntity();
    const entity2 = try scene.createEntity();

    try std.testing.expect(entity1 == 1);
    try std.testing.expect(entity2 == 2);
    try std.testing.expect(scene.getEntityCount() == 2);

    // Test entity position setting
    try std.testing.expect(scene.setEntityPosition(entity1, 1.0, 2.0, 3.0));

    if (scene.getEntityTransform(entity1)) |transform| {
        try std.testing.expect(transform.position[0] == 1.0);
        try std.testing.expect(transform.position[1] == 2.0);
        try std.testing.expect(transform.position[2] == 3.0);
    }

    // Test entity destruction
    try std.testing.expect(scene.destroyEntity(entity1));
    try std.testing.expect(scene.getEntityCount() == 1);
}
