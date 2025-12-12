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

Use the main physics module:

```zig
const physics = @import("physics/mod.zig");
```

### 2. Update Engine Initialization

Initialize the physics engine with configuration:

```zig
// Create physics config with enhanced options
var config = physics.Config{
    .gravity = [_]f32{ 0.0, -9.81, 0.0 },
    .enable_sleeping = true,        // Enable object sleeping
    .solver_iterations = 8,         // Solver iterations for stability
    .enable_ccd = true,             // Enable continuous collision detection
};

// Initialize physics engine
var engine = try physics.init(allocator, config);
defer physics.deinit(engine);
```

### 3. Work with Rigid Bodies

Use the `createRigidBody` function with configuration:

```zig
// Create a box rigid body
const box_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
    .position = .{ .x = 0, .y = 5, .z = 0 },
    .mass = 2.0,
    .shape = .{ .box = .{ .width = 1.0, .height = 1.0, .depth = 1.0 } },
    .object_type = .dynamic,
});

// Create a sphere rigid body
const sphere_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
    .position = .{ .x = 2, .y = 5, .z = 0 },
    .mass = 1.5,
    .shape = .{ .sphere = .{ .radius = 1.0 } },
    .object_type = .dynamic,
});
```

### 4. Use Advanced Constraints

The enhanced system provides constraint support through the engine:

```zig
// Create a spring constraint
_ = try engine.addConstraint(
    object_a_idx,
    object_b_idx,
    .spring,
    .{ .x = 0, .y = 0, .z = 0 }, // anchor_a
    .{ .x = 0, .y = 0, .z = 0 }, // anchor_b
    .{
        .spring = .{
            .rest_length = 2.0,
            .stiffness = 10.0,
            .damping = 0.5,
        },
    },
);

// Create a hinge joint
_ = try engine.addConstraint(
    object_a_idx,
    object_b_idx,
    .hinge,
    .{ .x = 0, .y = 0, .z = 0 }, // anchor_a
    .{ .x = 0, .y = 0, .z = 0 }, // anchor_b
    .{
        .hinge = .{
            .axis = .{ .x = 0, .y = 0, .z = 1 },
            .lower_limit = -std.math.pi,
            .upper_limit = std.math.pi,
        },
    },
);
```

### 5. Apply Forces to Rigid Bodies

Apply impulses directly to rigid bodies:

```zig
// Apply an impulse to a rigid body
engine.applyImpulse(object_idx, .{ .x = 10, .y = 0, .z = 0 });
```

### 6. Collision Filtering

Collision filtering is configured through the `RigidBodyConfig`:

```zig
const object_idx = try engine.createRigidBody(physics.PhysicsEngine.RigidBodyConfig{
    .position = .{ .x = 0, .y = 0, .z = 0 },
    .mass = 1.0,
    .shape = .{ .sphere = .{ .radius = 1.0 } },
    .object_type = .dynamic,
    // Collision filtering can be added to RigidBodyConfig if supported
});
```

### 7. Update and Simulation Loop

Update the physics engine each frame:

```zig
// Main game loop
while (running) {
    // Calculate delta time
    const dt: f32 = timer.lap();
    
    // Update physics
    engine.update(dt);
    
    // Access objects directly
    const object = &engine.objects.items[object_idx];
    std.debug.print("Position: {d:.2}, {d:.2}, {d:.2}\n", 
        .{ object.position.x, object.position.y, object.position.z });
}
```

## Advanced Features

### Object Sleeping

Objects automatically sleep when they come to rest, saving CPU time. To manually control:

```zig
// Wake up a sleeping object
engine.objects.items[object_idx].wake();
```

### Performance Monitoring

Access performance statistics through the engine:

```zig
// Access performance stats if available
const stats = engine.performance_stats;
std.debug.print("Active bodies: {}\n", .{stats.active_bodies});
```

### Enhanced Spring Constraints

Spring constraints are created using the `addConstraint` method:

```zig
_ = try engine.addConstraint(
    object_a_idx,
    object_b_idx,
    .spring,
    .{ .x = 0, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = 0 },
    .{
        .spring = .{
            .rest_length = 2.0,
            .stiffness = 10.0,
            .damping = 0.3,
        },
    },
);
```

## Example Implementation

See `src/physics/examples/advanced_physics_demo.zig` for a complete example that demonstrates the features of the enhanced physics system.

## Common Issues

1. **Object Tunneling**: If fast-moving objects pass through thin objects, increase the `collision_iterations` or reduce the fixed timestep.

2. **Unstable Constraints**: If constraints seem unstable, try increasing the `constraint_iterations` or adjusting the compliance values.

3. **Performance Concerns**: Use object sleeping, appropriate collision groups/masks, and monitor the performance stats to identify bottlenecks.

4. **Rigid Body Rotation**: Remember that rigid body physics requires more computational resources than simple particles, so use only where necessary.
