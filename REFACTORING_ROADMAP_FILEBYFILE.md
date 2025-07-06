# MFS Engine - File-by-File Refactoring Roadmap

## Overview
This document outlines the systematic refactoring approach for every file in the MFS Engine, organized by priority and dependencies.

## Refactoring Order (by Priority)

### Phase 1: Core Foundation (Critical Path) ✅ COMPLETE
These files form the foundation and must be refactored first.

#### 1.1 Core Module ✅ COMPLETE  
- [x] `src/core/mod.zig` - Module organization ✅
- [x] `src/core/types.zig` - Base type definitions ✅
- [x] `src/core/allocator.zig` - Memory management foundation ✅
- [x] `src/core/log.zig` - Logging infrastructure ✅
- [x] `src/core/config.zig` - Configuration management ✅
- [x] `src/core/events.zig` - Event system ✅

#### 1.2 Math Module ✅ COMPLETE
- [x] `src/math/mod.zig` - Module exports ✅
- [x] `src/math/vec2.zig` - 2D vectors ✅
- [x] `src/math/vec3.zig` - 3D vectors ✅
- [x] `src/math/vec4.zig` - 4D vectors ✅
- [x] `src/math/mat4.zig` - 4x4 matrices ✅
- [x] `src/math/simd.zig` - SIMD optimizations ✅

#### 1.3 Platform Layer
- [ ] `src/platform/mod.zig` - Platform abstraction
- [ ] `src/platform/platform.zig` - Platform detection
- [ ] `src/window/window.zig` - Window management
- [ ] `src/window/linux_window.zig` - Linux implementation
- [ ] `src/window/macos_window.zig` - macOS implementation

### Phase 2: Graphics System
Graphics backend refactoring with consistent interfaces.

#### 2.1 Graphics Core
- [ ] `src/graphics/mod.zig` - Graphics module
- [ ] `src/graphics/backend_manager.zig` - Backend selection
- [ ] `src/graphics/types.zig` - Graphics types
- [ ] `src/graphics/gpu.zig` - GPU abstraction

#### 2.2 Vulkan Backend
- [ ] `src/graphics/backends/vulkan/vk.zig` - Vulkan FFI (already started)
- [ ] `src/graphics/backends/vulkan/vulkan_backend.zig` - Main implementation
- [ ] `src/graphics/backends/vulkan/memory_manager.zig` - Memory management
- [ ] `src/graphics/backends/vulkan/pipeline.zig` - Pipeline management

#### 2.3 Other Backends
- [ ] `src/graphics/backends/directx/d3d12_backend.zig` - DirectX 12
- [ ] `src/graphics/backends/opengl/advanced_opengl_backend.zig` - OpenGL
- [ ] `src/graphics/backends/webgpu/webgpu_backend.zig` - WebGPU

### Phase 3: Engine Systems

#### 3.1 Engine Core
- [ ] `src/engine/engine.zig` - Main engine (needs cleanup)
- [ ] `src/engine/core.zig` - Core functionality
- [ ] `src/engine/ecs.zig` - Entity Component System

#### 3.2 Scene Management
- [ ] `src/scene/mod.zig` - Scene module
- [ ] `src/scene/scene.zig` - Scene graph
- [ ] `src/scene/core/entity.zig` - Entity management
- [ ] `src/scene/components/*.zig` - All components

#### 3.3 Physics System
- [ ] `src/physics/mod.zig` - Physics module
- [ ] `src/physics/physics_engine.zig` - Main physics
- [ ] `src/physics/rigid_body.zig` - Rigid body dynamics
- [ ] `src/physics/collision_resolver.zig` - Collision detection

### Phase 4: Audio & Input

#### 4.1 Audio System
- [ ] `src/audio/mod.zig` - Audio module
- [ ] `src/audio/audio.zig` - Audio engine

#### 4.2 Input System
- [ ] `src/input/mod.zig` - Input module
- [ ] `src/input/input.zig` - Input handling

### Phase 5: UI Framework

#### 5.1 UI Core
- [ ] `src/ui/mod.zig` - UI module
- [ ] `src/ui/core.zig` - Core UI
- [ ] `src/ui/ui_framework.zig` - Framework implementation
- [ ] `src/ui/view_modifiers.zig` - View modifiers (partially done)

### Phase 6: Advanced Features

#### 6.1 AI System
- [ ] `src/ai/mod.zig` - AI module
- [ ] `src/ai/neural_networks.zig` - Neural networks
- [ ] `src/ai/behavior_trees.zig` - Behavior trees

#### 6.2 Networking
- [ ] `src/networking/mod.zig` - Networking module
- [ ] `src/networking/server.zig` - Server implementation
- [ ] `src/networking/client.zig` - Client implementation

### Phase 7: Tools & Utilities

#### 7.1 Tools
- [ ] `src/tools/mod.zig` - Tools module
- [ ] `src/tools/profiler.zig` - Profiling tools
- [ ] `src/tools/debugger.zig` - Debug utilities
- [ ] `src/tools/asset_browser.zig` - Asset management
- [ ] `src/tools/visual_editor.zig` - Visual editor

## CLEANUP PHASE: Unused File Removal

### Files to Delete (Duplicates/Unused)

#### Duplicate Files
- [ ] **DELETE** `examples/physics_demo.zig` - Duplicate of `examples/physics_demo/main.zig` (keep the folder version)
- [ ] **DELETE** `tools/asset_processor.zig` - Duplicate of `tools/asset_processor/asset_processor.zig` (keep the folder version)
- [ ] **DELETE** `tools/profiler_visualizer/profiler_visualizer.zig` - Duplicate of `tools/profiler_visualizer/visualizer.zig`

#### Legacy/Deprecated Files  
- [ ] **DELETE** `src/root.zig` - Deprecated legacy compatibility layer
- [ ] **DELETE** `src/nyx_std.zig` - Unused custom standard library wrapper

#### Empty/Stub Files with Only TODOs
- [ ] **REVIEW** `tools/texture_converter.zig` - Only contains TODO
- [ ] **REVIEW** `tools/model_viewer.zig` - Only contains TODO
- [ ] **REVIEW** `src/xr.zig` - Mostly TODOs, may need to keep for future

#### Documentation Bloat (Keep Essential Only)
- [ ] **DELETE** `ADVANCED_FEATURES_COMPLETION.md`
- [ ] **DELETE** `ADVANCED_FEATURES_IMPLEMENTATION.md` 
- [ ] **DELETE** `ADVANCED_FEATURES_ROADMAP.md`
- [ ] **DELETE** `ADVANCED_REFACTORING_COMPLETION_REPORT.md`
- [ ] **DELETE** `BREAKTHROUGH_COMPLETION_REPORT.md`
- [ ] **DELETE** `CLEANUP_SUMMARY.md`
- [ ] **DELETE** `CODEBASE_CLEANUP_FINAL_STATUS.md`
- [ ] **DELETE** `CODEBASE_FINALIZED.md`
- [ ] **DELETE** `CODEBASE_IMPROVEMENT_COMPLETION_REPORT.md`
- [ ] **DELETE** `CODEBASE_IMPROVEMENTS_COMPLETION_REPORT.md`
- [ ] **DELETE** `COMPLETE_FIX_SUMMARY.md`
- [ ] **DELETE** `COMPLETE_GRAPHICS_SYSTEM.md`
- [ ] **DELETE** `COMPLETION_AND_TESTING_REPORT.md`
- [ ] **DELETE** `COMPLETION_STATUS_REPORT.md`
- [ ] **DELETE** `COMPREHENSIVE_CLEANUP_REPORT.md`
- [ ] **DELETE** `DIRECTX12_DEFAULT_SUMMARY.md`
- [ ] **DELETE** `DIRECTX12_IMPLEMENTATION_STATUS.md`
- [ ] **DELETE** `ENGINE_COMPLETION_REPORT.md`
- [ ] **DELETE** `ENGINE_STATUS.md`
- [ ] **DELETE** `EXAMPLES_COMPLETION_FINAL_REPORT.md`
- [ ] **DELETE** `FINAL_CODE_COMPLETION_REPORT.md`
- [ ] **DELETE** `MFS_ENGINE_SRC_COMPLETION_FINAL_REPORT.md`
- [ ] **DELETE** `NEXT_GENERATION_ENHANCEMENTS_REPORT.md`
- [ ] **DELETE** `NEXT_GENERATION_EVOLUTION_REPORT.md`
- [ ] **DELETE** `PRODUCTION_DEPLOYMENT_FINAL.md`
- [ ] **DELETE** `PRODUCTION_DEPLOYMENT_GUIDE.md`
- [ ] **DELETE** `PRODUCTION_READINESS_FINAL_ASSESSMENT.md`
- [ ] **DELETE** `PRODUCTION_READY_FINAL.md`
- [ ] **DELETE** `PRODUCTION_READY_SUMMARY.md`
- [ ] **DELETE** `REFACTORING_COMPLETE.md`
- [ ] **DELETE** `REFACTORING_PLAN_2024.md`
- [ ] **DELETE** `REFACTORING_PROGRESS.md`
- [ ] **DELETE** `REFACTORING_SUMMARY.md`
- [ ] **DELETE** `SRC_COMPLETION_REPORT.md`
- [ ] **DELETE** `SRC_FIX_SUMMARY.md`
- [ ] **DELETE** `TEST_AND_BUILD_REPORT.md`
- [ ] **DELETE** `TEST_REPORT.md`
- [ ] **DELETE** `VULKAN_REFACTORING_SUMMARY.md`

#### Build Artifacts/Generated Files
- [ ] **DELETE** `asset_processor.exe`
- [ ] **DELETE** `asset_processor.pdb`
- [ ] **DELETE** `code_quality_check.pdb`
- [ ] **DELETE** `build_date.txt`
- [ ] **DELETE** `build_output.txt`
- [ ] **DELETE** `build_report.csv`
- [ ] **DELETE** `code_quality_report.csv`
- [ ] **DELETE** `function_dupes.json` (empty file)
- [ ] **DELETE** `zig-out/` directory (build artifacts)

#### Unused Scripts
- [ ] **REVIEW** `scripts/build_web.py` - Python version may be unused if PowerShell version exists
- [ ] **REVIEW** `run_vulkan_cube.ps1` - May be duplicate of example run scripts

### Consolidation Tasks

#### Example Consolidation
- [ ] **CONSOLIDATE** Multiple Vulkan cube examples into one comprehensive example
  - Keep: `examples/vulkan_rt_spinning_cube/` (most complete)
  - Review: `examples/vulkan_spinning_cube_real.zig`, `examples/vulkan_spinning_cube_simple.zig`, `examples/vulkan_spinning_cube_demo.zig`

#### Documentation Consolidation  
- [ ] **KEEP** Essential docs: `README.md`, `docs/` folder, `IMPROVEMENTS.md`
- [ ] **CREATE** Single `CHANGELOG.md` to replace all completion reports
- [ ] **CREATE** Single `ROADMAP.md` to replace multiple roadmap files

## Post-Cleanup Verification

### Build System Updates
- [ ] Update `build.zig` to remove references to deleted files
- [ ] Update `.gitignore` to exclude build artifacts
- [ ] Verify all examples still build after cleanup

### Documentation Updates  
- [ ] Update main `README.md` with current status
- [ ] Update `docs/` folder to reflect actual codebase state
- [ ] Remove broken references in documentation

### Testing
- [ ] Run full build after cleanup
- [ ] Test remaining examples
- [ ] Verify no broken imports

## Estimated Impact
- **Files to delete**: ~50+ files
- **Size reduction**: ~70% of documentation bloat
- **Maintenance reduction**: Significant
- **Build time improvement**: Moderate

## Next Phase Priority
After cleanup, focus on **Phase 2: Graphics System** as it's the most critical for engine functionality.