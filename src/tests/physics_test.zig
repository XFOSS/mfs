const std = @import("std");
const mfs = @import("mfs");
const physics = mfs.physics;
const math = mfs.math;
const Vector = math.Vector;
const Vec4 = math.Vec4;
const Quaternion = math.Quaternion;
// const TriggerEvent = triggers.TriggerEvent; // TODO: Fix when physics module is properly exported

/// Test the physics engine
pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create physics configuration
    const config = physics.PhysicsConfig{
        .gravity = Vec4{ 0, -9.81, 0, 0 },
        .use_continuous_collision = true,
        .enable_sleeping = true,
        .world_size = 50.0,
        .spatial_cell_size = 2.0,
    };

    // Create physics world
    var world = try physics.World.init(allocator, config);
    defer world.deinit();

    // Create floor
    const floor_material = physics.PhysicsMaterial{
        .friction = 0.8,
        .restitution = 0.1,
        .density = 10.0,
        .name = "floor",
    };

    _ = try world.createBox(Vec4{ 0, -5, 0, 0 }, // position
        Vec4{ 50, 1, 50, 0 }, // size
        0.0, // mass (0 = static)
        floor_material);

    // Create different shapes
    const sphere_material = physics.PhysicsMaterial{
        .friction = 0.5,
        .restitution = 0.7,
        .density = 1.0,
        .name = "rubber",
    };

    const sphere1_idx = try world.createSphere(Vec4{ -5, 10, 0, 0 }, // position
        1.0, // radius
        2.0, // mass
        sphere_material);

    const sphere2_idx = try world.createSphere(Vec4{ 0, 15, 0, 0 }, // position
        1.5, // radius
        3.0, // mass
        sphere_material);

    const box_material = physics.PhysicsMaterial{
        .friction = 0.3,
        .restitution = 0.4,
        .density = 2.0,
        .name = "wood",
    };

    const box_idx = try world.createBox(Vec4{ 5, 10, 0, 0 }, // position
        Vec4{ 2, 2, 2, 0 }, // size
        5.0, // mass
        box_material);

    const capsule_material = physics.PhysicsMaterial{
        .friction = 0.2,
        .restitution = 0.6,
        .density = 1.5,
        .name = "plastic",
    };

    const capsule_idx = try world.createCapsule(Vec4{ 0, 10, 5, 0 }, // position
        0.5, // radius
        2.0, // height
        1.5, // mass
        capsule_material);

    // Add constraints between objects
    try world.addSpringConstraint(sphere1_idx, sphere2_idx, 7.0, // rest length
        10.0, // stiffness
        0.5 // damping
    );

    try world.addHingeJoint(box_idx, capsule_idx, Vec4{ 1, 0, 0, 0 }, // anchor point on box (local)
        Vec4{ 0, -1, 0, 0 }, // anchor point on capsule (local)
        Vec4{ 0, 0, 1, 0 } // hinge axis
    );

    // Create a trigger volume
    // TODO: Re-enable when TriggerEvent is properly exported
    // const trigger_callback = struct {
    //     fn onTrigger(event: TriggerEvent) void {
    //         switch (event.event_type) {
    //             .Enter => std.debug.print("Object {} entered trigger {}\n", .{ event.object_id, event.trigger_id }),
    //             .Exit => std.debug.print("Object {} exited trigger {}\n", .{ event.object_id, event.trigger_id }),
    //             .Stay => {}, // Ignore stay events for cleaner output
    //         }
    //     }
    // }.onTrigger;

    // TODO: Re-enable when physics module exports are fixed
    // const trigger_shape = Shape{ .Box = shapes.BoxShape.init(10, 5, 10) };
    // _ = try world.createTrigger(trigger_shape, Vec4{ 0, 0, 0, 0 }, trigger_callback);

    // Apply some forces to get things moving
    var sphere1 = &world.objects.items[sphere1_idx];
    sphere1.applyImpulse(Vec4{ 5, 2, 0, 0 });

    var box_obj = &world.objects.items[box_idx];
    box_obj.applyImpulse(Vec4{ -3, 1, 2, 0 });
    box_obj.applyTorque(Vec4{ 0, 0, 5, 0 });

    // Run simulation for a few seconds
    const sim_duration = 10.0;
    const frame_dt = 1.0 / 60.0;
    var time: f32 = 0.0;

    while (time < sim_duration) : (time += frame_dt) {
        try world.update(frame_dt);

        // Print object positions every 0.5 seconds
        if (@mod(time, 0.5) < frame_dt) {
            std.debug.print("Time: {d:.1}s\n", .{time});
            std.debug.print("  Sphere1: pos={d:.2},{d:.2},{d:.2}\n", .{ sphere1.position[0], sphere1.position[1], sphere1.position[2] });
            std.debug.print("  Box: pos={d:.2},{d:.2},{d:.2}\n", .{ box_obj.position[0], box_obj.position[1], box_obj.position[2] });
        }
    }

    std.debug.print("Physics simulation completed\n", .{});
}
