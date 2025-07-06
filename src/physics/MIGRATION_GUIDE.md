# Migration Guide: Enhanced Physics System

This document explains how to migrate from the standard physics system to the enhanced physics system in the MFS engine.

## Why Migrate?

The enhanced physics system provides several significant improvements:

- Full rigid body dynamics with proper rotational physics
- Improved collision detection with spatial partitioning (O(n+m) instead of O(n²))
- Enhanced constraint system with multiple constraint types
- Better performance through object sleeping and optimized algorithms
- More accurate collision response with contact point generation

## Basic Migration Steps

### 1. Import the Enhanced Physics Module

Replace your physics import with the improved version:

```zig
// Old import
const physics = @import("physics/physics.zig");

// New import
const physics = @import("physics/physics_improved.zig");
```

### 2. Update World Initialization

The world initialization remains similar, but you can take advantage of additional configuration options:

```zig
// Create physics config with enhanced options
var config = physics.PhysicsConfig{
    .gravity = physics.Vec3f{ 0, -9.81, 0, 0 },
    .enable_sleeping = true,        // Enable object sleeping
    .collision_iterations = 3,      // More iterations for better stability
    .constraint_iterations = 6,     // More constraint iterations
    .spatial_cell_size = 2.0,       // Cell size for spatial partitioning
};

// Initialize physics world
var world = try physics.World.init(allocator, config);
defer world.deinit();
```

### 3. Work with Rigid Bodies

Use the dedicated rigid body creation functions:

```zig
// Create a box rigid body
const box_idx = try world.createRigidBodyBox(
    physics.Vec3f{ 0, 5, 0, 0 },                // position
    physics.Vec3f{ 1.0, 1.0, 1.0, 0.0 },        // size
    2.0                                          // mass
);

// Create a sphere rigid body
const sphere_idx = try world.createRigidBodySphere(
    physics.Vec3f{ 2, 5, 0, 0 },                // position
    1.0,                                         // radius
    1.5                                          // mass
);
```

### 4. Use Advanced Constraints

The enhanced system provides a constraint manager with multiple constraint types:

```zig
// Access the constraint manager (it's an optional, so use if check)
if (world.constraint_manager) |*cm| {
    // Create a distance constraint
    const distance_constraint = try cm.addDistance(.{
        .object_index_a = object_a_idx,
        .object_index_b = object_b_idx,
        .distance = 2.0,
        .compliance = 0.0001,
    });
    
    // Create a position constraint
    const position_constraint = try cm.addPosition(.{
        .object_index = object_idx,
        .target_position = physics.Vec3f{ 0, 10, 0, 0 },
        .stiffness = 0.5,
    });
    
    // Create an angle constraint
    const angle_constraint = try cm.addAngle(.{
        .object_index_a = object_a_idx,
        .object_index_b = object_b_idx,
        .target_angle = 0.5,
        .stiffness = 0.2,
    });
}
```

### 5. Apply Forces to Rigid Bodies

For advanced force application to rigid bodies:

```zig
// Get access to the rigid body manager
if (world.rigid_body_manager) |*rbm| {
    // Get a rigid body by object index
    if (rbm.getRigidBody(object_idx)) |rb| {
        // Apply force at a specific point
        rb.applyForceAtPoint(
            physics.Vec3f{ 10, 0, 0, 0 },        // force direction & magnitude
            physics.Vec3f{ 0, 1, 0, 0 },         // point of application (relative to center)
            &world.objects[object_idx]           // reference to the physical object
        );
    }
}
```

### 6. Collision Filtering

The enhanced system supports collision filtering with groups and masks:

```zig
// Set collision group and mask (bitfields)
world.objects[object_idx].collision_group = 0x01;  // Group 1
world.objects[object_idx].collision_mask = 0x02;   // Can collide with group 2

// Another object that can collide with the above
world.objects[other_idx].collision_group = 0x02;   // Group 2
world.objects[other_idx].collision_mask = 0x01;    // Can collide with group 1
```

### 7. Update and Simulation Loop

The update function remains the same:

```zig
// Main game loop
while (running) {
    // Calculate delta time
    const dt = timer.lap();
    
    // Update physics
    world.update(dt);
    
    // Get physics stats for monitoring
    const stats = world.getPerformanceStats();
}
```

## Advanced Features

### Object Sleeping

Objects automatically sleep when they come to rest, saving CPU time. To manually control:

```zig
// Wake up a sleeping object
world.objects[object_idx].wake();

// Force an object to sleep
world.objects[object_idx].sleep();
```

### Performance Monitoring

The enhanced system includes performance statistics:

```zig
const stats = world.getPerformanceStats();
std.debug.print("Active objects: {d}, Update time: {d}ns\n", 
    .{stats.active_objects, stats.update_time_ns});
std.debug.print("Collision time: {d}ns, Constraint time: {d}ns\n",
    .{stats.collision_time_ns, stats.constraint_time_ns});
```

### Enhanced Spring Constraints

The improved system supports more advanced spring options:

```zig
if (world.constraint_manager) |*cm| {
    const spring = try cm.addSpring(.{
        .object_index_a = object_a_idx,
        .object_index_b = object_b_idx,
        .rest_length = 2.0,
        .stiffness = 10.0,
        .damping = 0.3,
        .min_length = 1.0,       // Spring can't compress beyond this
        .max_length = 3.0,       // Spring can't stretch beyond this
        .bidirectional = false,  // Only applies force when stretched (not compressed)
        .break_threshold = 4.0,  // Spring breaks if stretched too far
    });
}
```

## Example Implementation

See `src/physics/examples/advanced_physics_demo.zig` for a complete example that demonstrates the features of the enhanced physics system.

## Common Issues

1. **Object Tunneling**: If fast-moving objects pass through thin objects, increase the `collision_iterations` or reduce the fixed timestep.

2. **Unstable Constraints**: If constraints seem unstable, try increasing the `constraint_iterations` or adjusting the compliance values.

3. **Performance Concerns**: Use object sleeping, appropriate collision groups/masks, and monitor the performance stats to identify bottlenecks.

4. **Rigid Body Rotation**: Remember that rigid body physics requires more computational resources than simple particles, so use only where necessary.
