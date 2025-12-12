const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const AutoHashMap = std.AutoHashMap;

pub const EntityId = u64;
pub const ComponentTypeId = u32;
pub const SystemId = u32;

pub const Component = union(enum) {
    transform: Transform,
    render: RenderComponent,
    physics: PhysicsComponent,
    script: ScriptComponent,
    audio: AudioComponent,
    light: LightComponent,
    camera: CameraComponent,

    pub fn getTypeId(self: Component) ComponentTypeId {
        return switch (self) {
            .transform => 0,
            .render => 1,
            .physics => 2,
            .script => 3,
            .audio => 4,
            .light => 5,
            .camera => 6,
        };
    }
};

pub const Entity = struct {
    id: EntityId,
    name: []const u8,
    active: bool,
    tag: []const u8,
    layer: u32,
    parent: ?EntityId,
    children: ArrayList(EntityId),
    components: AutoHashMap(ComponentTypeId, Component),

    pub fn init(allocator: Allocator, id: EntityId, name: []const u8) !Entity {
        return Entity{
            .id = id,
            .name = try allocator.dupe(u8, name),
            .active = true,
            .tag = try allocator.dupe(u8, "Untagged"),
            .layer = 0,
            .parent = null,
            .children = ArrayList(EntityId).init(allocator),
            .components = AutoHashMap(ComponentTypeId, Component).init(allocator),
        };
    }

    pub fn deinit(self: *Entity, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.tag);
        self.children.deinit();

        var comp_iter = self.components.iterator();
        while (comp_iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                .script => |*script| script.deinit(),
                else => {},
            }
        }
        self.components.deinit();
    }

    pub fn addComponent(self: *Entity, component: Component) !void {
        try self.components.put(component.getTypeId(), component);
    }

    pub fn getComponent(self: *Entity, comptime T: type) ?*T {
        const type_id = switch (T) {
            Transform => 0,
            RenderComponent => 1,
            PhysicsComponent => 2,
            ScriptComponent => 3,
            AudioComponent => 4,
            LightComponent => 5,
            CameraComponent => 6,
            else => return null,
        };

        if (self.components.getPtr(type_id)) |component| {
            return switch (component.*) {
                inline else => |*comp| if (@TypeOf(comp.*) == T) comp else null,
            };
        }
        return null;
    }

    pub fn hasComponent(self: *Entity, comptime T: type) bool {
        return self.getComponent(T) != null;
    }

    pub fn removeComponent(self: *Entity, comptime T: type) bool {
        const type_id = switch (T) {
            Transform => 0,
            RenderComponent => 1,
            PhysicsComponent => 2,
            ScriptComponent => 3,
            AudioComponent => 4,
            LightComponent => 5,
            CameraComponent => 6,
            else => return false,
        };

        return self.components.remove(type_id);
    }

    pub fn setParent(self: *Entity, parent_id: ?EntityId, scene: *Scene) !void {
        if (self.parent) |old_parent_id| {
            if (scene.getEntity(old_parent_id)) |old_parent| {
                for (old_parent.children.items, 0..) |child_id, i| {
                    if (child_id == self.id) {
                        _ = old_parent.children.swapRemove(i);
                        break;
                    }
                }
            }
        }

        self.parent = parent_id;

        if (parent_id) |new_parent_id| {
            if (scene.getEntity(new_parent_id)) |new_parent| {
                try new_parent.children.append(self.id);
            }
        }
    }

    pub fn addChild(self: *Entity, child_id: EntityId) !void {
        try self.children.append(child_id);
    }

    pub fn removeChild(self: *Entity, child_id: EntityId) void {
        for (self.children.items, 0..) |id, i| {
            if (id == child_id) {
                _ = self.children.swapRemove(i);
                break;
            }
        }
    }
};

// Forward declarations for component types
pub const Transform = @import("../components/transform.zig").Transform;
pub const RenderComponent = @import("../components/render.zig").RenderComponent;
pub const PhysicsComponent = @import("../components/physics.zig").PhysicsComponent;
pub const ScriptComponent = @import("../components/script.zig").ScriptComponent;
pub const AudioComponent = @import("../components/audio.zig").AudioComponent;
pub const LightComponent = @import("../components/light.zig").LightComponent;
pub const CameraComponent = @import("../components/camera.zig").CameraComponent;
pub const Scene = @import("scene.zig").Scene;
