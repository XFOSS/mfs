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

- [Zig](https://ziglang.org/) (0.11.0 or newer)
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