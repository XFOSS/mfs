//! MFS Engine - Scene Module
//! Scene management system with Entity-Component-System (ECS) architecture
//! Provides entity management, component systems, and spatial organization
//! @thread-safe Scene operations can be multi-threaded with proper synchronization
//! @performance Optimized with spatial partitioning and system scheduling

const std = @import("std");
const builtin = @import("builtin");

// Core scene components
pub const scene = @import("scene.zig");
pub const entity = @import("core/entity.zig");
pub const core_scene = @import("core/scene.zig");

// Component types
pub const components = struct {
    pub const transform = @import("components/transform.zig");
    pub const camera = @import("components/camera.zig");
    pub const light = @import("components/light.zig");
    pub const render = @import("components/render.zig");
    pub const physics = @import("components/physics.zig");
    pub const audio = @import("components/audio.zig");
    pub const script = @import("components/script.zig");

    // Re-export component types
    pub const Transform = transform.Transform;
    pub const Camera = camera.Camera;
    pub const Light = light.Light;
    pub const RenderComponent = render.RenderComponent;
    pub const PhysicsComponent = physics.PhysicsComponent;
    pub const AudioComponent = audio.AudioComponent;
    pub const ScriptComponent = script.ScriptComponent;
};

// System types
pub const systems = struct {
    pub const render_system = @import("systems/render_system.zig");
    pub const physics_system = @import("systems/physics_system.zig");
    pub const audio_system = @import("systems/audio_system.zig");
    pub const script_system = @import("systems/script_system.zig");
    pub const transform_system = @import("systems/transform_system.zig");

    // Re-export system types
    pub const RenderSystem = render_system.RenderSystem;
    pub const PhysicsSystem = physics_system.PhysicsSystem;
    pub const AudioSystem = audio_system.AudioSystem;
    pub const ScriptSystem = script_system.ScriptSystem;
    pub const TransformSystem = transform_system.TransformSystem;
};

// Spatial organization
pub const spatial = struct {
    pub const octree = @import("spatial/octree.zig");

    // Re-export spatial types
    pub const Octree = octree.Octree;
};

// Re-export main scene types
pub const Scene = core_scene.Scene;
pub const Entity = entity.Entity;
pub const EntityId = entity.EntityId;

// Scene configuration
pub const SceneConfig = struct {
    max_entities: u32 = 10000,
    max_components_per_type: u32 = 10000,
    enable_spatial_partitioning: bool = true,
    spatial_partition_depth: u32 = 8,
    enable_frustum_culling: bool = true,
    enable_occlusion_culling: bool = false,

    pub fn validate(self: SceneConfig) !void {
        if (self.max_entities == 0 or self.max_entities > 1000000) {
            return error.InvalidParameter;
        }
        if (self.max_components_per_type == 0 or self.max_components_per_type > 1000000) {
            return error.InvalidParameter;
        }
        if (self.spatial_partition_depth == 0 or self.spatial_partition_depth > 16) {
            return error.InvalidParameter;
        }
    }
};

// Initialize scene system
pub fn init(allocator: std.mem.Allocator, config: SceneConfig) !*Scene {
    try config.validate();
    return try Scene.init(allocator);
}

// Cleanup scene system
pub fn deinit(scene_instance: *Scene) void {
    scene_instance.deinit();
}

test "scene module" {
    std.testing.refAllDecls(@This());
}
