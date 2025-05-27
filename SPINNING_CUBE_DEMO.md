# Spinning Cube Demo - MFS Engine

A complete demonstration of a textured, materialized spinning cube with dynamic lighting using the MFS cross-platform game engine.

## Features

### Visual Features
- **Textured Cube**: Procedurally generated checkered pattern texture
- **Dynamic Animation**: Smooth rotation on multiple axes
- **PBR Materials**: Physically-based rendering with metallic and roughness properties
- **Dynamic Lighting**: Orbiting light source with real-time shadows
- **Vertex Colors**: Each face has unique colors that blend with the texture

### Technical Features
- **Cross-Platform**: Supports Windows, Linux, and macOS
- **Multi-Backend**: Auto-detects best graphics API (Vulkan, DirectX, Metal, OpenGL)
- **Real-time Shaders**: Custom vertex and fragment shaders with animation
- **Scene Management**: Entity-component system with transforms
- **Window Management**: Native window creation with event handling

## Quick Start

### Windows

**Option 1: PowerShell (Recommended)**
```powershell
.\run_spinning_cube.ps1
```

**Option 2: Command Prompt**
```cmd
run_spinning_cube.bat
```

### Linux/macOS
```bash
zig build --build-file build_spinning_cube.zig -Doptimize=ReleaseFast
./zig-out/bin/spinning_cube
```

## Requirements

- **Zig Compiler**: Version 0.11.0 or newer
- **Graphics Driver**: OpenGL 3.3+ or Vulkan 1.0+ support
- **Memory**: 64MB RAM minimum
- **Platform**: Windows 10+, Linux with X11, or macOS 10.14+

### Windows Dependencies
- Direct3D 11 or OpenGL drivers
- Visual C++ Redistributable (usually pre-installed)

### Linux Dependencies
```bash
# Ubuntu/Debian
sudo apt install libx11-dev libgl1-mesa-dev libvulkan-dev

# Fedora/RHEL
sudo dnf install libX11-devel mesa-libGL-devel vulkan-devel
```

## Controls

| Input | Action |
|-------|--------|
| **ESC** | Exit application |
| **Close Window** | Exit application |
| **Mouse** | (Future: Camera control) |

## Technical Details

### Rendering Pipeline
1. **Vertex Shader**: Applies model transforms and animation
2. **Fragment Shader**: Handles lighting, materials, and texturing
3. **Uniform Buffers**: MVP matrices, lighting data, material properties
4. **Texture Sampling**: Procedural checkered pattern

### Animation System
- **Rotation Speed**: 1.5 rad/s (Y-axis), 0.8 rad/s (X-axis)
- **Light Orbit**: 4.0 unit radius, 0.5 rad/s orbital speed
- **Frame Rate**: Target 60 FPS with adaptive vsync

### Material Properties
```glsl
Material {
    ambient:   [0.2, 0.2, 0.2]
    diffuse:   [0.8, 0.8, 0.8]
    specular:  [1.0, 1.0, 1.0]
    shininess: 64.0
    metallic:  0.3
    roughness: 0.4
    emissive:  [0.0, 0.0, 0.0]
}
```

## File Structure

```
mfs/
├── src/
│   ├── spinning_cube_app.zig      # Main application
│   ├── ui/simple_window.zig       # Window management
│   ├── scene/scene.zig             # Scene management
│   └── graphics/                   # Graphics backends
├── shaders/
│   ├── textured_cube.vert          # Vertex shader
│   └── textured_cube.frag          # Fragment shader
├── build_spinning_cube.zig         # Build configuration
├── run_spinning_cube.ps1           # PowerShell runner
├── run_spinning_cube.bat           # Batch runner
└── SPINNING_CUBE_DEMO.md          # This file
```

## Customization

### Modify Rotation Speed
Edit `mfs/shaders/textured_cube.vert`:
```glsl
float rotationY = ubo.time * 1.5;  // Change multiplier
float rotationX = ubo.time * 0.8;  // Change multiplier
```

### Change Material Properties
Edit `mfs/src/spinning_cube_app.zig` in `setupMaterial()`:
```zig
self.material_ubo = MaterialUBO{
    .ambient = [3]f32{0.2, 0.2, 0.2},    // Ambient color
    .diffuse = [3]f32{0.8, 0.8, 0.8},    // Diffuse color
    .metallic = 0.3,                      // Metallic factor
    .roughness = 0.4,                     // Roughness factor
    // ... other properties
};
```

### Modify Texture Pattern
Edit `loadTexture()` in `spinning_cube_app.zig`:
```zig
const checker = ((x / 32) + (y / 32)) % 2;  // Change 32 for different size
```

## Performance Notes

- **Debug Mode**: Includes validation layers and verbose logging
- **Release Mode**: Optimized for performance, minimal logging
- **Memory Usage**: ~10-20MB typical, ~50MB maximum
- **CPU Usage**: <5% on modern systems
- **GPU Usage**: <10% on dedicated cards

## Troubleshooting

### Build Issues
```
Error: Zig compiler not found
→ Install Zig from https://ziglang.org/download/
→ Add Zig to your system PATH
```

### Graphics Issues
```
Error: Failed to create graphics context
→ Update graphics drivers
→ Check OpenGL/Vulkan support
→ Try different optimization level
```

### Runtime Issues
```
Error: Window creation failed
→ Check display configuration
→ Ensure no other apps using exclusive fullscreen
→ Try running as administrator (Windows)
```

## Development

### Adding New Features
1. Modify `spinning_cube_app.zig` for logic changes
2. Update shaders in `shaders/` for visual changes
3. Rebuild with `zig build --build-file build_spinning_cube.zig`

### Debug Mode
```bash
zig build --build-file build_spinning_cube.zig -Doptimize=Debug
```

### Testing
```bash
zig build test --build-file build_spinning_cube.zig
```

## License

Part of the MFS Engine project. See main LICENSE file for details.

## Credits

- **Engine**: MFS Cross-Platform Game Engine
- **Graphics**: Vulkan, DirectX, Metal, OpenGL backends
- **Math**: Custom linear algebra library
- **Platform**: Native window and input handling

---

**Enjoy the spinning cube demo!** 🎮✨

For more information about the MFS Engine, see the main README.md file.