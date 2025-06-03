const std = @import("std");
const physics = @import("../physics_improved.zig");
const Vec3f = physics.Vec3f;

/// Advanced physics demo showcasing the improved physics system features
/// This includes collision detection, rigid body dynamics, constraints, and performance optimization
pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Create physics configuration with enhanced settings
    var config = physics.PhysicsConfig{
        .gravity = Vec3f{ 0.0, -9.81, 0.0, 0.0 },
        .enable_sleeping = true,
        .sleep_threshold = 0.05,
        .sleep_frames = 30,
        .collision_iterations = 3,
        .constraint_iterations = 8,
        .spatial_cell_size = 2.0,
        .world_size = 100.0,
        .collision_margin = 0.01,
        .max_objects = 1000,
        .max_constraints = 2000,
    };

    // Initialize physics world
    var world = try physics.World.init(allocator, config);
    defer world.deinit();

    // Create ground and walls to form a container
    _ = try world.createStaticPlane(Vec3f{ 0.0, 0.0, 0.0, 0.0 }, Vec3f{ 0.0, 1.0, 0.0, 0.0 }, 50.0); // Ground
    _ = try world.createStaticPlane(Vec3f{ -10.0, 0.0, 0.0, 0.0 }, Vec3f{ 1.0, 0.0, 0.0, 0.0 }, 10.0); // Left wall
    _ = try world.createStaticPlane(Vec3f{ 10.0, 0.0, 0.0, 0.0 }, Vec3f{ -1.0, 0.0, 0.0, 0.0 }, 10.0); // Right wall
    _ = try world.createStaticPlane(Vec3f{ 0.0, 0.0, -10.0, 0.0 }, Vec3f{ 0.0, 0.0, 1.0, 0.0 }, 10.0); // Back wall
    _ = try world.createStaticPlane(Vec3f{ 0.0, 0.0, 10.0, 0.0 }, Vec3f{ 0.0, 0.0, -1.0, 0.0 }, 10.0); // Front wall

    // Create a pile of boxes with different collision groups/masks
    const num_boxes = 25;
    var boxes: [num_boxes]usize = undefined;

    for (0..num_boxes) |i| {
        // Random position in a 5x5 grid
        const x = @mod(@intToFloat(f32, i), 5.0) * 1.2 - 2.4;
        const z = @floor(@intToFloat(f32, i) / 5.0) * 1.2 - 2.4;
        const height = 3.0 + @mod(@intToFloat(f32, i), 3.0) * 2.0;
        
        // Create box with slightly different sizes
        const size_variation = 0.8 + @intToFloat(f32, i % 4) * 0.1;
        const box_size = Vec3f{ size_variation, size_variation, size_variation, 0.0 };
        
        boxes[i] = try world.createRigidBodyBox(
            Vec3f{ x, height, z, 0.0 },
            box_size,
            1.0 + @intToFloat(f32, i % 3)
        );

        // Add random initial rotation
        world.objects[boxes[i]].orientation = physics.math.Quaternion.fromAxisAngle(
            @intToFloat(f32, i % 10) / 10.0,
            1.0, 
            @intToFloat(f32, i % 7) / 7.0,
            @intToFloat(f32, i) * 0.2
        );

        // Set collision properties for demo
        world.objects[boxes[i]].collision_group = 1 << @truncate(u4, i % 3);
        world.objects[boxes[i]].collision_mask = 0xFF;  // All boxes can collide with others
    }

    // Create a chain of rigid bodies connected by distance constraints
    const chain_length = 10;
    var chain_links: [chain_length]usize = undefined;
    
    // Create the anchor point (fixed in space)
    chain_links[0] = try world.createObject(
        Vec3f{ 8.0, 8.0, 0.0, 0.0 },
        0.0,  // Zero mass = immovable
        .StaticBody,
        0.3
    );
    world.objects[chain_links[0]].pinned = true;
    
    // Create chain links
    for (1..chain_length) |i| {
        const prev_idx = chain_links[i-1];
        const y_offset = world.objects[prev_idx].position[1] - 0.8;
        
        // Create sphere for chain link
        chain_links[i] = try world.createRigidBodySphere(
            Vec3f{ 
                world.objects[prev_idx].position[0],
                y_offset,
                world.objects[prev_idx].position[2],
                0.0 
            },
            0.3,  // radius
            0.5   // mass
        );
        
        // Connect with constraint manager
        if (world.constraint_manager) |*cm| {
            _ = try cm.addDistance(.{
                .object_index_a = chain_links[i-1],
                .object_index_b = chain_links[i],
                .distance = 0.8,
                .compliance = 0.0001,
            });
        }
    }
    
    // Create a compound pendulum system with angle constraints
    var pendulum_parts: [4]usize = undefined;
    
    // Pendulum anchor
    pendulum_parts[0] = try world.createObject(
        Vec3f{ -8.0, 8.0, 0.0, 0.0 },
        0.0,  // Zero mass = immovable
        .StaticBody,
        0.3
    );
    world.objects[pendulum_parts[0]].pinned = true;
    
    // Create pendulum parts
    for (1..pendulum_parts.len) |i| {
        pendulum_parts[i] = try world.createRigidBodyBox(
            Vec3f{ 
                world.objects[pendulum_parts[0]].position[0] + @intToFloat(f32, i) * 0.5,
                world.objects[pendulum_parts[0]].position[1] - @intToFloat(f32, i) * 1.0,
                0.0,
                0.0 
            },
            Vec3f{ 0.8, 0.2, 0.2, 0.0 },
            1.0
        );
        
        // Connect to previous part
        if (world.constraint_manager) |*cm| {
            const prev_idx = pendulum_parts[i-1];
            
            // Distance constraint
            _ = try cm.addDistance(.{
                .object_index_a = prev_idx,
                .object_index_b = pendulum_parts[i],
                .distance = 1.2,
                .compliance = 0.0005,
            });
            
            // Angle constraint to restrict swinging
            _ = try cm.addAngle(.{
                .object_index_a = prev_idx,
                .object_index_b = pendulum_parts[i],
                .target_angle = 0.1,  // Allow slight bending
                .stiffness = 0.1,
            });
        }
    }
    
    // Create a soft body "blob"
    _ = try world.createSoftBody(
        Vec3f{ 0.0, 10.0, 0.0, 0.0 }, 
        1.5,      // radius
        3,        // resolution (higher = more detailed)
        8.0,      // total mass
        40.0      // stiffness
    );
    
    // Create a cloth that will drape over objects
    try world.createClothGrid(
        Vec3f{ -5.0, 12.0, -5.0, 0.0 },  // top left
        10.0,   // width
        10.0,   // height
        15,     // rows
        15,     // columns
        0.05,   // particle mass
        200.0,  // stiffness
        0.8     // damping
    );
    
    // Create a "wrecking ball" with delayed impulse
    const ball = try world.createRigidBodySphere(
        Vec3f{ -15.0, 6.0, 0.0, 0.0 },
        1.2,    // radius
        20.0    // mass
    );
    
    // Create a position constraint that will be deactivated later
    var position_constraint: ?*physics.constraints_module.PositionConstraint = null;
    
    if (world.constraint_manager) |*cm| {
        position_constraint = try cm.addPosition(.{
            .object_index = ball,
            .target_position = Vec3f{ -15.0, 6.0, 0.0, 0.0 },
            .stiffness = 1.0,
            .active = true,
        });
    }

    // Register collision callback for sound/visual effects
    try world.registerCollisionCallback(handleCollision);

    // Simulation loop
    const simulation_time = 20.0;  // seconds
    const fixed_dt = 1.0 / 60.0;
    var time: f32 = 0.0;
    var ball_released = false;

    while (time < simulation_time) : (time += fixed_dt) {
        // Release the wrecking ball after 3 seconds
        if (time > 3.0 and !ball_released) {
            if (position_constraint) |pc| {
                pc.active = false;  // Deactivate position constraint
            }
            
            // Apply a strong impulse
            world.objects[ball].applyImpulse(Vec3f{ 30.0, 5.0, 0.0, 0.0 });
            ball_released = true;
        }

        // Update physics
        world.update(fixed_dt);

        // Print info every second
        if (@mod(time, 1.0) < fixed_dt) {
            const stats = world.getPerformanceStats();
            const total_energy = world.getTotalEnergy();
            std.debug.print("Time: {d:.1}s, Energy: {d:.2}, Active: {d}/{d}, Update: {d}ns\n", 
                .{ 
                    time, 
                    total_energy, 
                    stats.active_objects, 
                    world.object_count,
                    stats.update_time_ns 
                }
            );
        }
    }

    std.debug.print("\nSimulation complete\n", .{});
    std.debug.print("Final performance stats:\n", .{});
    
    const final_stats = world.getPerformanceStats();
    std.debug.print("  Active objects: {d}/{d}\n", .{ final_stats.active_objects, world.object_count });
    std.debug.print("  Update time: {d}ns\n", .{ final_stats.update_time_ns });
    std.debug.print("  Collision time: {d}ns\n", .{ final_stats.collision_time_ns });
    std.debug.print("  Constraint time: {d}ns\n", .{ final_stats.constraint_time_ns });
}

/// Simple collision callback function
fn handleCollision(a_idx: usize, b_idx: usize) void {
    // In a real application, this would trigger sound effects,
    // particle systems, or other visual feedback based on
    // collision strength, material types, etc.
    _ = a_idx;
    _ = b_idx;
}