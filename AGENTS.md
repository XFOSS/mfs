# MFS Engine - Agent Integration Guide

## Build/Test Commands

- `zig build` - Debug build
- `zig build -Doptimize=ReleaseFast` - Release build
- `zig build test` - Run all tests
- `zig test src/tests/test_math.zig` - Run single test file
- `zig run scripts/run_tests.zig --filter "Math"` - Run filtered tests
- `zig run scripts/run_tests.zig --verbose` - Verbose test output
- `zig run scripts/code_quality_check.zig` - Code quality analysis
- `.\scripts\run_all_checks.ps1` - Comprehensive checks (Windows)

## Code Style Guidelines

- **Files**: snake_case (`ray_tracing.zig`)
- **Types/Structs**: PascalCase (`RenderContext`)
- **Functions/Variables**: camelCase (`createWindow`, `maxVertexCount`)
- **Constants**: ALL_CAPS (`GRAVITY`, `MAX_VELOCITY`)
- **Error Handling**: Use error unions, avoid `catch unreachable`
- **Memory**: Pass allocators explicitly, use `defer`/`errdefer` for cleanup
- **Documentation**: `//!` doc comments for public APIs with `@thread-safe`, `@platform` tags
- **Imports**: Group std lib, external deps, internal imports
- **Testing**: Descriptive test names, good coverage
- **Formatting**: 4-space indentation, consistent spacing

## Commit Standards

- Format: `type(scope): description`
- Types: feat, fix, docs, style, refactor, perf, test, build
- Examples: `feat(graphics): add Vulkan ray tracing`, `fix(physics): correct collision detection`

## Engine Architecture

### Core Application Structure

The main engine coordination happens in `src/engine/mod.zig` via the `Application` struct:

- **Core Systems**: Memory manager, time system, event system (always initialized)
- **Subsystems**: Window, graphics, input, scene, physics, audio, AI, networking (optional via config)
- **Initialization Order**: Window → Graphics → Input → Scene → Physics → Audio → AI → Networking
- **Deinitialization Order**: Reverse of initialization (LIFO)

### Subsystem Integration Pattern

When integrating a new subsystem:

1. **Add to Config** (`src/engine/mod.zig`):

   ```zig
   enable_subsystem: bool = false,
   subsystem_config: subsystem.Config = .{},
   ```

2. **Add to Application struct**:

   ```zig
   subsystem: ?*subsystem.SubsystemType = null,
   ```

3. **Initialize in `initializeSubsystems()`**:

   ```zig
   if (self.config.enable_subsystem) {
       self.subsystem = try subsystem.init(self.allocator, self.config.subsystem_config);
   }
   ```

4. **Update in `update()`**:

   ```zig
   if (self.subsystem) |sys| {
       try sys.update(delta_time);
   }
   ```

5. **Deinitialize in `deinit()`** (reverse order):

   ```zig
   if (self.subsystem) |sys| {
       subsystem.deinit(sys);
       self.allocator.destroy(sys);
       self.subsystem = null;
   }
   ```

### System Dependencies

- **Graphics** requires **Window** (checks `window_system != null`)
- **Input** receives events from **Window** via `convertWindowEventToInputEvent()` and `pushEvent()`
- **Scene** coordinates with **Graphics**, **Physics**, and **Audio** for rendering/simulation
- **AI** operates on **Scene** entities (access via `Application.getScene()`)
- **Networking** syncs **Scene** state (access via `Application.getScene()`)
- **Input** accessible to **Scene** and other systems (via `Application.getInput()`)

### Common Pitfalls

⚠️ **Watch for syntax errors** when making bulk edits:

- Verify `const` not `onst`, `Allocator` not `Alocator`
- Check all struct field names are correct
- Ensure proper spacing in type annotations (`[]const u8` not `[]const 8`)
- Validate enum casting and error handling

⚠️ **Memory Management**:

- Always use `errdefer` for cleanup on initialization failure
- Destroy in reverse order of initialization
- Check for null before destroying optional systems

⚠️ **Delta Time**:

- Some systems use `f64` (audio), others use `f32` (physics, scene, AI, networking)
- Convert explicitly: `const delta_time_f32: f32 = @floatCast(delta_time);`

## Current Integration Status

### Fully Integrated Systems

- ✅ Window System
- ✅ Graphics System (multiple backends)
- ✅ Scene System (ECS-based)
- ✅ Physics System
- ✅ Audio System (3D spatial audio)
- ✅ Input System (fully integrated with window event routing)
- ✅ AI System (fully integrated with scene entity access)
- ✅ Networking System (fully integrated with scene synchronization)

### Configuration Example

```zig
var config = mfs.engine.createDefaultConfig();
config.enable_window = true;
config.enable_graphics = true;
config.enable_input = true;
config.enable_physics = true;
config.enable_audio = true;
config.enable_ai = true;  // Optional
config.enable_networking = false;  // Optional, requires network_mode
```

## Testing Integration Changes

1. **Verify compilation**: `zig build` should succeed
2. **Check initialization**: All enabled systems should initialize without errors
3. **Test update loop**: Systems should update in correct order
4. **Verify cleanup**: No memory leaks on shutdown
5. **Test toggling**: Enable/disable systems via config

## File Locations

- **Engine Core**: `src/engine/mod.zig` - Main Application class
- **Subsystem Modules**: `src/{subsystem}/mod.zig` - Individual system APIs
- **Main Entry**: `src/main.zig` - Application entry point
- **Build Config**: `build.zig` - Build system configuration
