const std = @import("std");
const math = @import("../math/mod.zig");
const Vec4 = math.Vec4;
const Vector = math.Vector;
const shapes = @import("shapes.zig");
const Shape = shapes.Shape;
const spatial_partition = @import("spatial_partition.zig");
const AABB = spatial_partition.AABB;
const physics_engine = @import("physics_engine.zig");
const PhysicalObject = physics_engine.PhysicalObject;

/// Trigger event types
pub const TriggerEventType = enum {
    Enter,
    Stay,
    Exit,
};

/// Trigger event data
pub const TriggerEvent = struct {
    trigger_id: usize,
    object_id: usize,
    event_type: TriggerEventType,
    position: Vec4,
    time: f64,
};

/// Trigger callback function type
pub const TriggerCallback = fn (event: TriggerEvent) void;

/// Trigger volume that detects when objects enter/exit
pub const TriggerVolume = struct {
    id: usize,
    shape: Shape,
    position: Vec4,
    orientation: math.Quaternion,
    active: bool = true,
    filter_mask: u32 = 0xFFFFFFFF,
    filter_group: u32 = 1,
    user_data: ?*anyopaque = null,

    contained_objects: std.AutoHashMap(usize, bool),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: usize, shape: Shape, position: Vec4) !TriggerVolume {
        return TriggerVolume{
            .id = id,
            .shape = shape,
            .position = position,
            .orientation = math.Quaternion.identity(),
            .contained_objects = std.AutoHashMap(usize, bool).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TriggerVolume) void {
        self.contained_objects.deinit();

        // Free convex hull if present
        if (self.shape == .ConvexHull) {
            self.shape.ConvexHull.deinit();
        }
    }

    /// Check if an object is inside this trigger volume
    pub fn containsObject(self: *TriggerVolume, object: *const PhysicalObject) bool {
        if (!self.active) return false;

        // Skip objects that don't match filter (PhysicalObject doesn't have collision_group/collision_mask, so skip filter check)
        // Note: If collision filtering is needed, these properties should be added to PhysicalObject

        // Simple sphere vs bounding box check for quick rejection
        const object_aabb = AABB.fromSphere(object.position, object.radius);
        const trigger_aabb = self.shape.getBoundingBox(self.position, self.orientation);

        if (!trigger_aabb.overlaps(object_aabb)) return false;

        // Perform more precise check based on shape type
        return switch (self.shape) {
            .Sphere => |sphere| {
                const delta = object.position - self.position;
                const dist_sq = Vector.dot3(delta, delta);
                const radius_sum = sphere.radius + object.radius;
                return dist_sq <= radius_sum * radius_sum;
            },
            .Box => |box| {
                // Transform object position to local box space
                const inv_orientation = self.orientation.conjugate();
                const local_pos = inv_orientation.rotateVector(object.position - self.position);

                // Check if point is inside box (plus object radius)
                return std.math.fabs(local_pos[0]) <= box.half_extents[0] + object.radius and
                    std.math.fabs(local_pos[1]) <= box.half_extents[1] + object.radius and
                    std.math.fabs(local_pos[2]) <= box.half_extents[2] + object.radius;
            },
            // For other shapes, just use sphere check for now
            else => {
                const delta = object.position - self.position;
                const dist_sq = Vector.dot3(delta, delta);
                const effective_radius = @max(Vector.length3(self.shape.getBoundingBox(Vec4{ 0, 0, 0, 0 }, math.Quaternion.identity()).max), object.radius);
                return dist_sq <= effective_radius * effective_radius;
            },
        };
    }

    /// Update trigger state and generate events
    pub fn update(
        self: *TriggerVolume,
        objects: []PhysicalObject,
        time: f64,
        callback: ?TriggerCallback,
    ) !void {
        if (!self.active) return;

        var event: TriggerEvent = undefined;
        event.trigger_id = self.id;
        event.time = time;

        // Track which objects we've processed to detect exits
        var processed = std.AutoHashMap(usize, void).init(self.allocator);
        defer processed.deinit();

        // Check each object for containment
        for (objects, 0..) |*obj, i| {
            if (!obj.active) continue;

            try processed.put(i, {});
            const is_contained = self.containsObject(obj);
            const was_contained = self.contained_objects.contains(i);

            if (is_contained) {
                if (!was_contained) {
                    // Object entered the trigger
                    try self.contained_objects.put(i, true);

                    if (callback) |cb| {
                        event.object_id = i;
                        event.event_type = .Enter;
                        event.position = obj.position;
                        cb(event);
                    }
                } else {
                    // Object is staying in the trigger
                    if (callback) |cb| {
                        event.object_id = i;
                        event.event_type = .Stay;
                        event.position = obj.position;
                        cb(event);
                    }
                }
            } else if (was_contained) {
                // Object exited the trigger
                _ = self.contained_objects.remove(i);

                if (callback) |cb| {
                    event.object_id = i;
                    event.event_type = .Exit;
                    event.position = obj.position;
                    cb(event);
                }
            }
        }

        // Check for objects that were contained but no longer exist
        var it = self.contained_objects.keyIterator();
        while (it.next()) |key| {
            if (!processed.contains(key.*)) {
                _ = self.contained_objects.remove(key.*);
            }
        }
    }
};

/// Manager for multiple trigger volumes
pub const TriggerManager = struct {
    allocator: std.mem.Allocator,
    triggers: std.ArrayList(TriggerVolume),
    next_id: usize = 0,
    callbacks: std.AutoHashMap(usize, TriggerCallback),
    time: f64 = 0,

    pub fn init(allocator: std.mem.Allocator) TriggerManager {
        return TriggerManager{
            .allocator = allocator,
            .triggers = std.ArrayList(TriggerVolume).init(allocator),
            .callbacks = std.AutoHashMap(usize, TriggerCallback).init(allocator),
        };
    }

    pub fn deinit(self: *TriggerManager) void {
        for (self.triggers.items) |*trigger| {
            trigger.deinit();
        }
        self.triggers.deinit();
        self.callbacks.deinit();
    }

    /// Create a new trigger volume
    pub fn createTrigger(
        self: *TriggerManager,
        shape: Shape,
        position: Vec4,
        callback: ?TriggerCallback,
    ) !usize {
        const id = self.next_id;
        self.next_id += 1;

        const trigger = try TriggerVolume.init(self.allocator, id, shape, position);
        try self.triggers.append(trigger);

        if (callback) |cb| {
            try self.callbacks.put(id, cb);
        }

        return id;
    }

    /// Remove a trigger by ID
    pub fn removeTrigger(self: *TriggerManager, id: usize) bool {
        for (self.triggers.items, 0..) |trigger, i| {
            if (trigger.id == id) {
                var removed = self.triggers.swapRemove(i);
                removed.deinit();
                _ = self.callbacks.remove(id);
                return true;
            }
        }
        return false;
    }

    /// Update all triggers
    pub fn update(self: *TriggerManager, objects: []PhysicalObject, dt: f32) !void {
        self.time += dt;

        for (self.triggers.items) |*trigger| {
            const callback_opt = self.callbacks.get(trigger.id);
            try trigger.update(objects, self.time, callback_opt);
        }
    }

    /// Set a callback for a trigger
    pub fn setCallback(self: *TriggerManager, id: usize, callback: TriggerCallback) !bool {
        for (self.triggers.items) |trigger| {
            if (trigger.id == id) {
                try self.callbacks.put(id, callback);
                return true;
            }
        }
        return false;
    }

    /// Remove a callback from a trigger
    pub fn removeCallback(self: *TriggerManager, id: usize) bool {
        return self.callbacks.remove(id);
    }
};
