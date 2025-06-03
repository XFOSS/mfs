# MFS Engine Source Code

This directory contains the source code for the MFS cross-platform graphics and game engine. The code is organized into logical modules based on functionality.

## Directory Structure

- **app/** - Application implementations including demo apps
- **audio/** - Audio subsystem for sound playback and 3D audio
- **bin/** - Main executable entry points
- **examples/** - Example applications demonstrating engine features
- **graphics/** - Core rendering system including backend implementations
- **math/** - Math utilities (vectors, matrices, quaternions, etc.)
- **neural/** - Machine learning and neural network implementations
- **physics/** - Physics simulation and collision detection
- **platform/** - Platform-specific code for different operating systems
- **render/** - Higher-level rendering utilities built on the graphics system
- **scene/** - Scene management and entity systems
- **system/** - Core engine systems (config, diagnostics, etc.)
- **tests/** - Unit and integration tests
- **tools/** - Development utilities and tooling
- **ui/** - User interface components
- **utils/** - General utility functions
- **vulkan/** - Vulkan-specific implementation details

## Core Files

- `main.zig` - Primary entry point for the engine
- `nyx_std.zig` - Standard library for the engine, re-exporting key modules
- `build_options.zig` - Compile-time configuration options
- `gpu.zig` - GPU abstraction layer
- `render.zig` - High-level rendering API
- `xr.zig` - XR (VR/AR) support

## Build System

The build system is based on Zig's build system and is configured via `build.zig` in the project root. Additional build helpers are available in `build_helpers.zig`.

## Contributing

When adding new code:

1. Place it in the appropriate subdirectory based on functionality
2. Follow existing code style and naming conventions
3. Add tests to the `tests/` directory
4. Update documentation as needed

## License

See the LICENSE file in the root directory of the project.