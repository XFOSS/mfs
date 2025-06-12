const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Vec3 = @import("../../math/vec3.zig").Vec3f;
const Mat4 = @import("../../math/mat4.zig").Mat4f;
const Entity = @import("../core/entity.zig").Entity;
const Scene = @import("../core/scene.zig").Scene;
const TransformComponent = @import("../components/transform.zig").TransformComponent;
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
