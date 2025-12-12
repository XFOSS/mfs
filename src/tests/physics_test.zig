const std = @import("std");
const physics = @import("../physics/mod.zig");

/// Test the physics engine
pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create physics configuration
    var config = physics.Config{
        .gravity = [_]f32{ 0.0, -9.81, 0.0 },
        .enable_sleeping = true,
        .enable_ccd = true,
        .solver_iterations = 8,
    };

    // Create physics engine
    var engine = try physics.init(allocator, config);
    defer physics.deinit(engine);

    // Create floor (static box)
    const floor_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
        .position = .{ .x = 0, .y = -5, .z = 0 },
        .mass = 0.0, // Static object
        .shape = .{ .box = .{ .width = 50, .height = 1, .depth = 50 } },
        .object_type = .static,
        .material = .{
            .friction = 0.8,
            .restitution = 0.1,
        },
    });

    // Create different shapes
    const sphere1_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
        .position = .{ .x = -5, .y = 10, .z = 0 },
        .mass = 2.0,
        .shape = .{ .sphere = .{ .radius = 1.0 } },
        .object_type = .dynamic,
        .material = .{
            .friction = 0.5,
            .restitution = 0.7,
        },
    });

    const sphere2_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
        .position = .{ .x = 0, .y = 15, .z = 0 },
        .mass = 3.0,
        .shape = .{ .sphere = .{ .radius = 1.5 } },
        .object_type = .dynamic,
        .material = .{
            .friction = 0.5,
            .restitution = 0.7,
        },
    });

    const box_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
        .position = .{ .x = 5, .y = 10, .z = 0 },
        .mass = 5.0,
        .shape = .{ .box = .{ .width = 2, .height = 2, .depth = 2 } },
        .object_type = .dynamic,
        .material = .{
            .friction = 0.3,
            .restitution = 0.4,
        },
    });

    const capsule_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
        .position = .{ .x = 0, .y = 10, .z = 5 },
        .mass = 1.5,
        .shape = .{ .capsule = .{ .radius = 0.5, .height = 2.0 } },
        .object_type = .dynamic,
        .material = .{
            .friction = 0.2,
            .restitution = 0.6,
        },
    });

    // Add constraints between objects
    _ = try engine.addConstraint(
        sphere1_idx,
        sphere2_idx,
        .spring,
        .{ .x = 0, .y = 0, .z = 0 }, // anchor_a
        .{ .x = 0, .y = 0, .z = 0 }, // anchor_b
        .{
            .spring = .{
                .rest_length = 7.0,
                .stiffness = 10.0,
                .damping = 0.5,
            },
        },
    );

    _ = try engine.addConstraint(
        box_idx,
        capsule_idx,
        .hinge,
        .{ .x = 1, .y = 0, .z = 0 }, // anchor_a
        .{ .x = 0, .y = -1, .z = 0 }, // anchor_b
        .{
            .hinge = .{
                .axis = .{ .x = 0, .y = 0, .z = 1 },
                .lower_limit = -std.math.pi,
                .upper_limit = std.math.pi,
            },
        },
    );

    // Apply some forces to get things moving
    engine.applyImpulse(sphere1_idx, .{ .x = 5, .y = 2, .z = 0 });
    engine.applyImpulse(box_idx, .{ .x = -3, .y = 1, .z = 2 });

    // Run simulation for a few seconds
    const sim_duration = 10.0;
    const frame_dt: f32 = 1.0 / 60.0;
    var time: f32 = 0.0;

    while (time < sim_duration) : (time += frame_dt) {
        engine.update(frame_dt);

        // Print object positions every 0.5 seconds
        if (@mod(time, 0.5) < frame_dt) {
            const sphere1 = &engine.objects.items[sphere1_idx];
            const box_obj = &engine.objects.items[box_idx];
            std.debug.print("Time: {d:.1}s\n", .{time});
            std.debug.print("  Sphere1: pos={d:.2},{d:.2},{d:.2}\n", .{ sphere1.position.x, sphere1.position.y, sphere1.position.z });
            std.debug.print("  Box: pos={d:.2},{d:.2},{d:.2}\n", .{ box_obj.position.x, box_obj.position.y, box_obj.position.z });
        }
    }

    std.debug.print("Physics simulation completed\n", .{});
}
