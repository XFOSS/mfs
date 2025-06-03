const std = @import("std");
const nyx = @import("../nyx_std.zig");
const platform = @import("../platform/platform.zig");
const physics = nyx.physics;
const math = nyx.math;
const Vec3f = physics.Vec3f;
const Timer = platform.time.Timer;

/// Physics showcase demonstrating the enhanced physics system capabilities
pub fn main() !void {
    // Print welcome message
    std.debug.print("\n=== Enhanced Physics System Showcase ===\n\n", .{});

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Setup physics configuration with enhanced options
    var config = physics.PhysicsConfig{
        .gravity = Vec3f{ 0.0, -9.81, 0.0, 0.0 },
        .enable_sleeping = true,
        .sleep_threshold = 0.03,
        .sleep_frames = 30,
        .collision_iterations = 3,
        .constraint_iterations = 8,
        .spatial_cell_size = 2.0,
        .world_size = 100.0,
        .collision_margin = 0.01,
        .max_objects = 500,
        .max_constraints = 1000,
        .cloth_damping = 0.8,
        .timestep = 1.0 / 120.0,
    };

    // Initialize physics world
    std.debug.print("Initializing physics world...\n", .{});
    var world = try physics.World.init(allocator, config);
    defer world.deinit();

    // Create environment boundaries
    createEnvironment(&world) catch |err| {
        std.debug.print("Error creating environment: {}\n", .{err});
        return err;
    };

    // Create a showcase of different physics features
    try createRigidBodyShowcase(&world);
    try createConstraintShowcase(&world);
    try createClothAndSoftBodyShowcase(&world);
    try createCollisionGroupsShowcase(&world);

    // Register collision callback
    try world.registerCollisionCallback(handleCollision);

    // Initialize timer
    var timer = try Timer.init();
    const simulation_time = 30.0; // seconds
    const fixed_dt = 1.0 / 60.0;
    var time: f32 = 0.0;
    var frame_count: u32 = 0;

    std.debug.print("\nStarting simulation for {d} seconds...\n", .{simulation_time});

    // Create a performance tracker
    var perf_tracker = PerformanceTracker.init();

    // Simulation loop
    while (time < simulation_time) : (time += fixed_dt) {
        const start_time = timer.read();

        // Update physics
        world.update(fixed_dt);

        // Track performance
        const update_time = timer.read() - start_time;
        perf_tracker.recordSample(update_time, world.getPerformanceStats());

        frame_count += 1;

        // Print info every second
        if (@mod(time, 1.0) < fixed_dt) {
            const stats = world.getPerformanceStats();
            const energy = world.getTotalEnergy();
            std.debug.print("Time: {d:.1}s | Energy: {d:.1} | Active: {d}/{d} | Update: {d}μs\n",
                .{
                    time,
                    energy,
                    stats.active_objects,
                    world.object_count,
                    stats.update_time_ns / 1000
                }
            );
        }

        // Periodically inject new objects or forces to show dynamics
        try periodicInteractions(&world, time);
    }

    // Print final performance report
    std.debug.print("\n=== Simulation Summary ===\n", .{});
    std.debug.print("Total frames: {d}\n", .{frame_count});
    std.debug.print("Total objects: {d}\n", .{world.object_count});

    perf_tracker.printReport();

    std.debug.print("\nSimulation complete!\n", .{});
}

/// Periodic interactions to make the simulation dynamic
fn periodicInteractions(world: *physics.World, time: f32) !void {
    // Every 3 seconds, apply random impulses to objects
    if (@mod(time, 3.0) < 0.017) { // Within one frame of the 3-second mark
        // Find an active object to apply force to
        for (0..world.object_count) |i| {
            if (world.objects[i].active and !world.objects[i].pinned and world.objects[i].obj_type == .RigidBody) {
                const impulse = Vec3f{
                    (std.math.sin(time) * 10.0),
                    4.0,
                    (std.math.cos(time) * 10.0),
                    0.0
                };
                world.objects[i].applyImpulse(impulse);
                break;
            }
        }
    }

    // Every 5 seconds, add a new object
    if (@mod(time, 5.0) < 0.017) {
        const drop_height = 15.0;
        switch (@floatToInt(u8, @mod(time, 20.0)) / 5) {
            0 => { // Add sphere
                _ = try world.createRigidBodySphere(
                    Vec3f{ std.math.sin(time) * 3.0, drop_height, std.math.cos(time) * 3.0, 0.0 },
                    0.7 + std.math.sin(time) * 0.3,  // radius 0.4-1.0
                    2.0
                );
            },
            1 => { // Add box
                _ = try world.createRigidBodyBox(
                    Vec3f{ std.math.cos(time) * 3.0, drop_height, std.math.sin(time) * 3.0, 0.0 },
                    Vec3f{ 0.8, 0.8, 0.8, 0.0 },
                    1.5
                );
            },
            2 => { // Add softbody
                _ = try world.createSoftBody(
                    Vec3f{ std.math.sin(time) * 2.0, drop_height, std.math.cos(time) * 2.0, 0.0 },
                    0.8,  // radius
                    2,    // resolution
                    1.0,  // mass
                    30.0  // stiffness
                );
            },
            3 => { // Break a random constraint
                if (world.constraint_manager) |*cm| {
                    if (cm.springs.items.len > 0) {
                        const idx = @floatToInt(usize, @mod(time, @intToFloat(f32, cm.springs.items.len)));
                        if (idx < cm.springs.items.len) {
                            cm.springs.items[idx].active = false;
                        }
                    }
                }
            },
            else => {},
        }
    }
}

/// Handle collision events
fn handleCollision(object_a_idx: usize, object_b_idx: usize) void {
    // In a real application, this would be used to trigger sound effects,
    // particle systems, or other feedback based on collisions
    _ = object_a_idx;
    _ = object_b_idx;
}

/// Create the environment boundaries
fn createEnvironment(world: *physics.World) !void {
    // Create ground plane
    _ = try world.createStaticPlane(
        Vec3f{ 0.0, 0.0, 0.0, 0.0 },
        Vec3f{ 0.0, 1.0, 0.0, 0.0 },
        50.0
    );

    // Create walls to form a containment area
    const wall_height = 15.0;
    const arena_size = 12.0;

    // Left wall
    _ = try world.createStaticPlane(
        Vec3f{ -arena_size, wall_height/2, 0.0, 0.0 },
        Vec3f{ 1.0, 0.0, 0.0, 0.0 },
        wall_height
    );

    // Right wall
    _ = try world.createStaticPlane(
        Vec3f{ arena_size, wall_height/2, 0.0, 0.0 },
        Vec3f{ -1.0, 0.0, 0.0, 0.0 },
        wall_height
    );

    // Back wall
    _ = try world.createStaticPlane(
        Vec3f{ 0.0, wall_height/2, -arena_size, 0.0 },
        Vec3f{ 0.0, 0.0, 1.0, 0.0 },
        wall_height
    );

    // Front wall
    _ = try world.createStaticPlane(
        Vec3f{ 0.0, wall_height/2, arena_size, 0.0 },
        Vec3f{ 0.0, 0.0, -1.0, 0.0 },
        wall_height
    );
}

/// Create a showcase of rigid body physics
fn createRigidBodyShowcase(world: *physics.World) !void {
    std.debug.print("Creating rigid body showcase...\n", .{});

    // Create a pyramid of boxes
    const pyramid_rows = 6;
    const box_size = 1.0;
    var box_idx: usize = 0;

    for (0..pyramid_rows) |row| {
        const y = box_size / 2.0 + @intToFloat(f32, row) * box_size;
        const row_boxes = pyramid_rows - row;
        const row_width = @intToFloat(f32, row_boxes) * box_size;
        const start_x = -row_width / 2.0 + box_size / 2.0;

        for (0..row_boxes) |col| {
            const x = start_x + @intToFloat(f32, col) * box_size;
            box_idx = try world.createRigidBodyBox(
                Vec3f{ x, y, -5.0, 0.0 },
                Vec3f{ box_size * 0.95, box_size * 0.95, box_size * 0.95, 0.0 },
                1.0
            );

            // Set material properties
            world.objects[box_idx].friction = 0.8;
            world.objects[box_idx].restitution = 0.2;
        }
    }

    // Create a line of different spheres
    for (0..5) |i| {
        const x = -5.0 + @intToFloat(f32, i) * 2.0;
        const radius = 0.4 + @intToFloat(f32, i) * 0.1;
        const mass = @intToFloat(f32, i + 1) * 0.5;

        const sphere_idx = try world.createRigidBodySphere(
            Vec3f{ x, radius, 5.0, 0.0 },
            radius,
            mass
        );

        // Give each sphere different material properties
        world.objects[sphere_idx].friction = 0.2 + @intToFloat(f32, i) * 0.15;
        world.objects[sphere_idx].restitution = 0.3 + @intToFloat(f32, i) * 0.1;

        // Give initial spin to demonstrate rotational physics
        world.objects[sphere_idx].angular_velocity = Vec3f{ 0.0, 3.0, 1.0, 0.0 };
    }

    // Create a large sphere that will roll into the pyramid
    const wrecking_ball = try world.createRigidBodySphere(
        Vec3f{ 0.0, 1.5, -8.0, 0.0 },
        1.5,
        8.0
    );

    // Give it an initial push
    world.objects[wrecking_ball].applyImpulse(Vec3f{ 0.0, 2.0, 10.0, 0.0 });
}

/// Create a showcase of the constraint system
fn createConstraintShowcase(world: *physics.World) !void {
    std.debug.print("Creating constraint showcase...\n", .{});

    if (world.constraint_manager == null) {
        std.debug.print("Warning: Constraint manager not available\n", .{});
        return;
    }

    const cm = world.constraint_manager.?;

    // Create a chain pendulum
    const chain_length = 8;
    var chain_anchors: [chain_length]usize = undefined;

    // Create the fixed anchor point
    chain_anchors[0] = try world.createObject(
        Vec3f{ -8.0, 10.0, 0.0, 0.0 },
        0.0,  // Zero mass = immovable
        .StaticBody,
        0.2
    );
    world.objects[chain_anchors[0]].pinned = true;

    // Create chain links with distance constraints
    for (1..chain_length) |i| {
        chain_anchors[i] = try world.createRigidBodySphere(
            Vec3f{ -8.0, 10.0 - @intToFloat(f32, i) * 1.0, 0.0, 0.0 },
            0.2,
            0.5
        );

        // Add distance constraint to previous link
        _ = try cm.addDistance(.{
            .object_index_a = chain_anchors[i-1],
            .object_index_b = chain_anchors[i],
            .distance = 1.0,
            .compliance = 0.0001,
        });
    }

    // Give the pendulum an initial push
    world.objects[chain_anchors[chain_length-1]].applyImpulse(
        Vec3f{ 2.0, 0.0, 0.0, 0.0 }
    );

    // Create a spring-mass system
    const spring_grid_size = 4;
    var spring_masses: [spring_grid_size * spring_grid_size]usize = undefined;

    // Create a grid of masses
    for (0..spring_grid_size) |row| {
        for (0..spring_grid_size) |col| {
            const idx = row * spring_grid_size + col;
            spring_masses[idx] = try world.createRigidBodySphere(
                Vec3f{
                    5.0 + @intToFloat(f32, col) * 1.0,
                    8.0 - @intToFloat(f32, row) * 1.0,
                    -2.0,
                    0.0
                },
                0.15,
                0.3
            );

            // Pin the top row
            if (row == 0) {
                world.objects[spring_masses[idx]].pinned = true;
            }
        }
    }

    // Create springs between adjacent masses
    for (0..spring_grid_size) |row| {
        for (0..spring_grid_size) |col| {
            const idx = row * spring_grid_size + col;

            // Connect to right neighbor
            if (col < spring_grid_size - 1) {
                _ = try cm.addSpring(.{
                    .object_index_a = spring_masses[idx],
                    .object_index_b = spring_masses[idx + 1],
                    .rest_length = 1.0,
                    .stiffness = 100.0,
                    .damping = 1.0,
                    .min_length = 0.5,
                    .max_length = 1.5,
                    .bidirectional = true,
                });
            }

            // Connect to bottom neighbor
            if (row < spring_grid_size - 1) {
                _ = try cm.addSpring(.{
                    .object_index_a = spring_masses[idx],
                    .object_index_b = spring_masses[idx + spring_grid_size],
                    .rest_length = 1.0,
                    .stiffness = 100.0,
                    .damping = 1.0,
                    .min_length = 0.5,
                    .max_length = 1.5,
                    .bidirectional = true,
                });
            }
        }
    }

    // Create an object held by angle constraints
    const angle_anchor = try world.createObject(
        Vec3f{ 0.0, 6.0, -5.0, 0.0 },
        0.0,
        .StaticBody,
        0.2
    );
    world.objects[angle_anchor].pinned = true;

    // Create a rigid bar
    const angle_obj = try world.createRigidBodyBox(
        Vec3f{ 0.0, 5.0, -5.0, 0.0 },
        Vec3f{ 1.5, 0.2, 0.2, 0.0 },
        1.0
    );

    // Add distance constraint
    _ = try cm.addDistance(.{
        .object_index_a = angle_anchor,
        .object_index_b = angle_obj,
        .distance = 1.0,
        .compliance = 0.0005,
    });

    // Add angle constraint to limit rotation
    _ = try cm.addAngle(.{
        .object_index_a = angle_anchor,
        .object_index_b = angle_obj,
        .target_angle = 0.0,
        .stiffness = 0.2,
    });
}

/// Create cloth and soft body examples
fn createClothAndSoftBodyShowcase(world: *physics.World) !void {
    std.debug.print("Creating cloth and soft body showcase...\n", .{});

    // Create a cloth banner
    try world.createClothGrid(
        Vec3f{ -3.0, 10.0, -8.0, 0.0 },  // top left
        6.0,    // width
        4.0,    // height
        12,     // rows
        18,     // columns
        0.05,   // particle mass
        30.0,   // stiffness
        0.5     // damping
    );

    // Create soft bodies of different resolutions
    for (0..3) |i| {
        _ = try world.createSoftBody(
            Vec3f{
                -3.0 + @intToFloat(f32, i) * 3.0,
                3.0,
                6.0,
                0.0
            },
            1.0,                         // radius
            @intCast(u32, i + 2),        // resolution (2, 3, 4)
            2.0,                         // mass
            30.0 + @intToFloat(f32, i) * 20.0  // stiffness
        );
    }
}

/// Create a showcase of collision filtering with different groups
fn createCollisionGroupsShowcase(world: *physics.World) !void {
    std.debug.print("Creating collision groups showcase...\n", .{});

    // Create three groups of objects with different collision properties
    const groups = 3;
    const objects_per_group = 5;

    for (0..groups) |group| {
        // Define collision group and mask
        const group_bit = @as(u32, 1) << @intCast(u5, group);
        const collision_mask = if (group == 0)
            @as(u32, 0x04)  // Group 1 only collides with group 3
        else if (group == 1)
            @as(u32, 0x01)  // Group 2 only collides with group 1
        else
            @as(u32, 0x03); // Group 3 collides with groups 1 and 2

        for (0..objects_per_group) |i| {
            const sphere_idx = try world.createRigidBodySphere(
                Vec3f{
                    @intToFloat(f32, group) * 5.0 - 5.0,
                    5.0 + @intToFloat(f32, i) * 1.5,
                    2.0 + @intToFloat(f32, i) * 0.5,
                    0.0
                },
                0.4,
                1.0
            );

            // Set the collision group and mask
            world.objects[sphere_idx].collision_group = group_bit;
            world.objects[sphere_idx].collision_mask = collision_mask;

            // Colorize in a real application
            // world.objects[sphere_idx].material_id = @intCast(u8, group);
        }
    }
}

/// Performance tracking utility
const PerformanceTracker = struct {
    avg_update_time_ns: f64,
    max_update_time_ns: u64,
    min_update_time_ns: u64,
    avg_active_objects: f64,
    avg_collision_time_ns: f64,
    avg_constraint_time_ns: f64,
    sample_count: u32,

    fn init() PerformanceTracker {
        return .{
            .avg_update_time_ns = 0,
            .max_update_time_ns = 0,
            .min_update_time_ns = std.math.maxInt(u64),
            .avg_active_objects = 0,
            .avg_collision_time_ns = 0,
            .avg_constraint_time_ns = 0,
            .sample_count = 0,
        };
    }

    fn recordSample(self: *PerformanceTracker, update_time: u64, stats
