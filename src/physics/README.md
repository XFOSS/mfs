# Enhanced Physics System

This directory contains an improved physics simulation system for the MFS engine. The system has been reorganized and enhanced for better performance, flexibility, and feature support.

## Key Improvements

### 1. Modular Architecture

The physics system has been split into multiple modules for better organization:

- `physics.zig` - Core physics types and world simulation
- `collision.zig` - Enhanced collision detection and resolution
- `constraints.zig` - Advanced constraint system
- `rigid_body.zig` - Full rigid body dynamics with proper rotational physics

### 2. Enhanced Collision System

- Spatial partitioning for O(n+m) collision detection instead of O(n²)
- Contact point generation for more accurate collision resolution
- Collision filtering using group/mask system
- Improved collision response with proper impulse resolution

### 3. Extended Constraint System

Added new constraint types beyond basic springs:

- **Distance Constraints** - Maintains exact distances between bodies
- **Position Constraints** - Pins objects to specific world positions
- **Angle Constraints** - Controls orientation between bodies
- **Spring Constraints** - Enhanced with min/max length and directionality

### 4. Full Rigid Body Dynamics

- Proper inertia tensor handling for accurate rotation
- Support for various shapes: boxes, spheres, cylinders
- Force and torque application at arbitrary points
- Sleepable bodies for better performance

### 5. Performance Optimizations

- Object sleeping for inactive bodies
- Optimized broadphase collision detection
- Fine-grained performance tracking
- SIMD acceleration where available

## Usage Examples

### Basic World Setup

```zig
// Create physics config
var config = physics.PhysicsConfig{
    .gravity = physics.Vec3f{ 0, -9.81, 0, 0 },
    .enable_sleeping = true,
};

// Initialize physics world
var world = try physics.World.init(allocator, config);
defer world.deinit();
```

### Creating Objects

```zig
// Create a sphere
const sphere_idx = try world.createRigidBodySphere(
    physics.Vec3f{ 0, 5, 0, 0 },  // position
    1.0,                          // radius
    2.0                           // mass
);

// Create a box
const box_idx = try world.createRigidBodyBox(
    physics.Vec3f{ 2, 5, 0, 0 },               // position
    physics.Vec3f{ 1.0, 1.0, 1.0, 0.0 },       // size
    1.5                                         // mass
);

// Create a static plane (ground)
const plane_idx = try world.createStaticPlane(
    physics.Vec3f{ 0, 0, 0, 0 },               // position  
    physics.Vec3f{ 0, 1, 0, 0 },               // normal
    50.0                                        // size
);
```

### Creating Constraints

```zig
// Create a spring between objects
const spring_idx = try world.createConstraint(
    object_a_idx,            // first object
    object_b_idx,            // second object
    null,                    // auto calculate rest length
    10.0,                    // stiffness
    0.1                      // damping
);

// Create a distance constraint (using the constraint manager)
const distance = try world.constraint_manager.?.addDistance(.{
    .object_index_a = object_a_idx,
    .object_index_b = object_b_idx,
    .distance = 2.0,
    .compliance = 0.0001,
});
```

### Simulation Update

```zig
// Main game loop
while (running) {
    // Calculate delta time
    const dt = timer.lap();
    
    // Update physics
    world.update(dt);
    
    // Get physics stats
    const stats = world.getPerformanceStats();
    std.debug.print("Active objects: {d}, Update time: {d}ns\n", 
        .{stats.active_objects, stats.update_time_ns});
}
```

### Advanced Usage

```zig
// Apply forces to objects
var obj = &world.objects[object_idx];
obj.applyForce(physics.Vec3f{ 10, 0, 0, 0 }, dt);

// Apply torque
obj.applyTorque(physics.Vec3f{ 0, 1, 0, 0 }, dt);

// Get rigid body for advanced control
if (world.rigid_body_manager) |*rbm| {
    if (rbm.getRigidBody(object_idx)) |rb| {
        // Apply force at specific point
        rb.applyForceAtPoint(
            physics.Vec3f{ 10, 0, 0, 0 },         // force
            physics.Vec3f{ 0, 1, 0, 0 },          // point
            &world.objects[object_idx]            // object
        );
    }
}
```

## Migration from Old Physics System

To use the improved physics system:

1. Import the improved physics module: `const physics = @import("physics/physics_improved.zig");`
2. Use the enhanced constraint types from the constraint manager
3. Set up the rigid body manager for proper rotational physics
4. Use the collision system for more accurate collisions

The improved system is designed to be backward compatible with existing physics code while providing enhanced functionality.