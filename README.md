# MFS Engine

[![MFS Engine CI](https://github.com/username/mfs/actions/workflows/ci.yml/badge.svg)](https://github.com/username/mfs/actions/workflows/ci.yml)

A cross-platform game engine and rendering framework written in Zig with a focus on performance, modularity, and developer experience.

## Features

- 🚀 **Multiple rendering backends**: Vulkan, DirectX 11/12, Metal, OpenGL, and more
- 🧩 **Modular architecture**: Use only what you need
- 🔄 **Hot reloading**: Shaders, assets, and code changes without restarting
- 📊 **Built-in profiling**: Performance monitoring and optimization tools
- 🎮 **Input handling**: Keyboard, mouse, gamepad with cross-platform support
- 🧠 **Physics engine**: Collision detection and resolution
- 🔊 **Audio system**: Spatial audio and mixing capabilities
- 📱 **Cross-platform**: Windows, Linux, macOS, and Web (via WASM)

## Getting Started

### Prerequisites

- [Zig](https://ziglang.org/) (0.14.1 or newer)
- For Vulkan: Vulkan SDK
- For DirectX: Windows SDK
- For Metal: macOS/Xcode

### Building

```bash
# Clone the repository
git clone https://github.com/username/mfs.git
cd mfs

# Build the engine
zig build

# Run a demo application
zig build run
```

## Project Structure

```
mfs/
├── src/                 # Source code
│   ├── app/             # Application frameworks
│   ├── bin/             # Executable entry points
│   ├── graphics/        # Graphics abstraction
│   ├── math/            # Math library
│   ├── physics/         # Physics engine
│   ├── platform/        # Platform-specific code
│   ├── render/          # Rendering systems
│   ├── system/          # Core systems
│   ├── ui/              # User interface components
│   ├── utils/           # Utilities and helpers
│   └── examples/        # Example applications
├── shaders/             # Shader files
├── tests/               # Test suite
└── build.zig           # Build system
```

## Examples

Several examples are provided to help you get started:

- Simple spinning cube (`zig build run-cube`)
- Advanced rendering demo (`zig build run-advanced-cube`)
- Enhanced renderer showcase (`zig build run-enhanced`)

## Usage

Create a new application using MFS:

```zig
const std = @import("std");
const mfs = @import("mfs");

pub fn main() !void {
    var app = try mfs.App.init(.{
        .title = "My MFS Application",
        .width = 1280,
        .height = 720,
    });
    defer app.deinit();
    
    while (app.running()) {
        try app.beginFrame();
        // Your rendering code here
        try app.endFrame();
    }
}
```

## Documentation

- [Engine Overview](docs/ENGINE_OVERVIEW.md)
- [API Reference](docs/API.md)
- [Rendering Backends](docs/BACKENDS.md)
- [Examples](docs/EXAMPLES.md)
- [Contributing Guide](docs/CONTRIBUTING.md)

## Performance

MFS is designed with performance in mind:

- Zero-allocation rendering paths
- SIMD-optimized math operations
- Multi-threaded task management
- Efficient memory management
- Low-level graphics API access

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- [Zig language

# MFS Physics Engine

A high-performance 3D physics engine written in Zig, optimized for games and real-time simulations.

## Features

### Core Physics
- SIMD-optimized vector operations
- Rigid body dynamics with proper rotation
- Continuous collision detection (CCD) to prevent tunneling
- Sleep optimization for inactive objects
- Spatial partitioning for efficient broad-phase collision detection
- Material properties (friction, restitution, density)
- Configurable time stepping

### Collision Shapes
- Spheres
- Boxes
- Capsules
- Cylinders
- Convex hulls

### Constraints & Joints
- Spring constraints
- Distance constraints
- Position constraints
- Angular constraints
- Fixed joints
- Hinge joints
- Slider joints
- Ball and socket joints
- Universal joints
- 6-DOF joints

### Event System
- Trigger volumes
- Collision callbacks
- Enter/Exit/Stay events for triggers

## Architecture

The physics engine is organized into several key modules:

### `physics_engine.zig`
The main entry point for the physics system, containing:
- `World`: Manages the physics simulation
- `PhysicalObject`: Represents a physical entity in the world
- `PhysicsConfig`: Configuration options for the simulation

### `shapes.zig`
Defines different collision shapes:
- `Shape`: Tagged union of all shape types
- `SphereShape`, `BoxShape`, `CapsuleShape`, etc.

### `spatial_partition.zig`
Implements spatial partitioning for efficient collision detection:
- `SpatialGrid`: Grid-based partitioning system
- `AABB`: Axis-aligned bounding box implementation

### `continuous_collision.zig`
Implements continuous collision detection to prevent fast objects from tunneling:
- `ContinuousCollision`: CCD algorithms and sweep tests
- `SweepResult`: Result of a linear cast through the world

### `collision_resolver.zig`
Handles collision detection and resolution:
- `CollisionResolver`: Detects and resolves collisions
- `CollisionData`: Contains information about a collision

### `constraints.zig`
Implements various constraints between objects:
- `Constraint`: Tagged union of all constraint types
- `SpringConstraint`, `DistanceConstraint`, etc.

### `joints.zig`
Implements joint types for more complex articulated structures:
- `Joint`: Tagged union of all joint types
- `FixedJoint`, `HingeJoint`, `SliderJoint`, etc.
- `JointManager`: Manages collections of joints

### `triggers.zig`
Implements non-physical trigger volumes for event triggering:
- `TriggerVolume`: Detects when objects enter/exit a region
- `TriggerEvent`: Event data for trigger callbacks
- `TriggerManager`: Manages collections of triggers

## Usage

See `src/tests/physics_test.zig` for example usage of the physics engine.

Basic usage:

```zig
// Initialize physics world
var config = physics.PhysicsConfig{
    .gravity = Vec4{ 0, -9.81, 0, 0 },
};
var world = try physics.World.init(allocator, config);
defer world.deinit();

// Create objects
const sphere_idx = try world.createSphere(
    Vec4{ 0, 10, 0, 0 },  // position
    1.0,                  // radius
    1.0,                  // mass
    material
);

const box_idx = try world.createBox(
    Vec4{ 5, 10, 0, 0 },  // position
    Vec4{ 2, 2, 2, 0 },   // size
    5.0,                  // mass
    material
);

// Add constraints
try world.addSpringConstraint(
    sphere_idx,
    box_idx,
    5.0,   // rest length
    10.0,  // stiffness
    0.5    // damping
);

// Update simulation
while (running) {
    try world.update(dt);
    // Render objects...
}
```

## Future Improvements

- Soft body dynamics
- Cloth simulation
- Fluid dynamics
- Heightfield terrain
- Compound shapes
- Mesh-based collision
- GPU acceleration for large-scale simulations