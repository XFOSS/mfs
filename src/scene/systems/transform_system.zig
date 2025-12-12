const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const math = @import("math");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Entity = @import("../core/entity.zig").Entity;
const Scene = @import("../core/scene.zig").Scene;
const System = @import("../core/scene.zig").System;
const TransformComponent = @import("../components/transform.zig").Transform;
const RenderComponent = @import("../components/render.zig").RenderComponent;
const CameraComponent = @import("../components/camera.zig").CameraComponent;
const LightComponent = @import("../components/light.zig").LightComponent;

pub const TransformSystem = struct {
    allocator: Allocator,
    scene: *Scene,
    dirty_entities: ArrayList(Entity),

    pub fn init(allocator: Allocator, scene: *Scene) !TransformSystem {
        return TransformSystem{
            .allocator = allocator,
            .scene = scene,
            .dirty_entities = ArrayList(Entity).init(allocator),
        };
    }

    pub fn deinit(self: *TransformSystem) void {
        self.dirty_entities.deinit();
    }

    pub fn update(self: *TransformSystem) !void {
        // Clear dirty entities list
        self.dirty_entities.clearRetainingCapacity();

        // Find all entities with dirty transforms
        var it = self.scene.iterator(.{ .transform = true });
        while (it.next()) |entity| {
            const transform = self.scene.getComponent(entity, TransformComponent) orelse continue;
            if (transform.dirty) {
                try self.dirty_entities.append(entity);
            }
        }

        // Update transforms and dependent components
        for (self.dirty_entities.items) |entity| {
            const transform = self.scene.getComponent(entity, TransformComponent) orelse continue;
            const world_matrix = transform.getWorldMatrix();

            // Update render component if present
            if (self.scene.getComponent(entity, RenderComponent)) |render| {
                render.updateWorldBounds(world_matrix);
            }

            // Update camera component if present
            if (self.scene.getComponent(entity, CameraComponent)) |camera| {
                camera.updateMatrices(transform.position, transform.rotation);
            }

            // Update light component if present
            if (self.scene.getComponent(entity, LightComponent)) |light| {
                if (light.light_type == .Directional) {
                    const direction = Vec3.init(@cos(transform.rotation.y) * @cos(transform.rotation.x), @sin(transform.rotation.x), @sin(transform.rotation.y) * @cos(transform.rotation.x)).normalize();
                    light.setDirection(direction);
                }
            }

            // Update child transforms
            self.updateChildTransforms(entity, world_matrix);

            // Mark transform as clean
            transform.dirty = false;
        }
    }

    fn updateChildTransforms(self: *TransformSystem, parent: Entity, parent_matrix: Mat4) void {
        var it = self.scene.iterator(.{ .transform = true });
        while (it.next()) |entity| {
            const transform = self.scene.getComponent(entity, TransformComponent) orelse continue;
            if (transform.parent == parent) {
                transform.updateWorldMatrix(parent_matrix);
                self.updateChildTransforms(entity, transform.getWorldMatrix());
            }
        }
    }
};

/// Standalone update function for use with Scene.addSystem
pub fn update(system: *System, scene: *Scene, delta_time: f32) void {
    _ = system;
    _ = delta_time;

    // Find all entities with dirty transforms and update them
    var entity_iter = scene.entities.iterator();
    while (entity_iter.next()) |entry| {
        const entity = entry.value_ptr;

        // Check if entity has transform component
        var comp_iter = entity.components.iterator();
        while (comp_iter.next()) |comp_entry| {
            switch (comp_entry.value_ptr.*) {
                .transform => |*transform| {
                    if (transform.dirty) {
                        // Update transform matrix
                        transform.updateMatrices(null);
                        transform.dirty = false;
                    }
                },
                else => {},
            }
        }
    }
}
