const std = @import("std");
const physics = @import("../physics_improved.zig");
const Vec3f = physics.Vec3f;

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Set up physics configuration
    var config = physics.PhysicsConfig{
        .gravity = Vec3f{ 0.0, -9.81, 0.0, 0.0 },
        .enable_sleeping = true,
        .collision_iterations = 2,
        .constraint_iterations = 6,
        .spatial_cell_size = 2.0,
    };

    // Initialize physics world
    var world = try physics.World.init(allocator, config);
    defer world.deinit();

    // Create ground plane
    const ground = try world.createStaticPlane(Vec3f{ 0.0, 0.0, 0.0, 0.0 }, Vec3f{ 0.0, 1.0, 0.0, 0.0 }, 50.0);

    // Create a stack of boxes
    const stack_height = 10;
    const box_size = Vec3f{ 1.0, 1.0, 1.0, 0.0 };
    var boxes: [stack_height]usize = undefined;

    for (0..stack_height) |i| {
        const height = @intToFloat(f32, i) * 1.2 + 1.0;
        boxes[i] = try world.createRigidBodyBox(Vec3f{ 0.0, height, 0.0, 0.0 }, box_size, 1.0);

        // Slightly rotate some boxes for instability
        if (i % 2 == 0) {
            world.objects[boxes[i]].orientation = physics.math.Quaternion.fromAxisAngle(0.0, 1.0, 0.0, 0.1);
        }
    }

    // Create a pendulum
    const pendulum_anchor = try world.createObject(Vec3f{ 5.0, 10.0, 0.0, 0.0 }, 0.0, // Zero mass = immovable
        .StaticBody, 0.2);
    world.objects[pendulum_anchor].pinned = true;

    const pendulum_bob = try world.createRigidBodySphere(Vec3f{ 5.0, 6.0, 0.0, 0.0 }, 0.5, 2.0);

    // Connect with constraint
    if (world.constraint_manager) |*cm| {
        _ = try cm.addDistance(.{
            .object_index_a = pendulum_anchor,
            .object_index_b = pendulum_bob,
            .distance = 4.0,
            .compliance = 0.0001,
        });
    }

    // Create a soft body
    _ = try world.createSoftBody(Vec3f{ -5.0, 5.0, 0.0, 0.0 }, 1.5, // radius
        2, // resolution
        5.0, // total mass
        50.0 // stiffness
    );

    // Create a cloth
    try world.createClothGrid(Vec3f{ -2.0, 8.0, -2.0, 0.0 }, // top left
        4.0, // width
        4.0, // height
        10, // rows
        10, // columns
        0.1, // particle mass
        50.0, // stiffness
        1.0 // damping
    );

    // Create a bowling ball to hit the stack
    const ball = try world.createRigidBodySphere(Vec3f{ -10.0, 1.0, 0.0, 0.0 }, 0.8, // radius
        10.0 // mass
    );

    // Give it an initial impulse
    world.objects[ball].applyImpulse(Vec3f{ 15.0, 5.0, 0.0, 0.0 });

    // Register collision callback
    try world.registerCollisionCallback(handleCollision);

    // Simulation loop
    const simulation_time = 10.0; // seconds
    const fixed_dt = 1.0 / 60.0;
    var time: f32 = 0.0;

    while (time < simulation_time) : (time += fixed_dt) {
        // Update physics
        world.update(fixed_dt);

        // Print info every second
        if (@mod(time, 1.0) < fixed_dt) {
            const stats = world.getPerformanceStats();
            const total_energy = world.getTotalEnergy();
            std.debug.print("Time: {d:.1}s, Energy: {d:.2}, Active: {d}\n", .{ time, total_energy, stats.active_objects });
        }
    }

    std.debug.print("Simulation complete\n", .{});
}

fn handleCollision(a: usize, b: usize) void {
    // Just a simple callback
    _ = a;
    _ = b;
}
