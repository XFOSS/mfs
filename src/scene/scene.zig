//! MFS Scene System - Main Scene Module
//! This module provides the unified interface to the scene management system
//! @thread-safe Scene-level thread safety coordination
//! @symbol PublicSceneAPI

const std = @import("std");
const math = @import("math");

// Core scene management
pub const core = @import("core/scene.zig");
pub const entity = @import("core/entity.zig");

// Scene components
pub const components = struct {
    pub const Transform = @import("components/transform.zig").Transform;
    pub const Camera = @import("components/camera.zig").Camera;
    pub const Light = @import("components/light.zig").Light;
    pub const Render = @import("components/render.zig").RenderComponent;
    pub const Physics = @import("components/physics.zig").PhysicsComponent;
    pub const Audio = @import("components/audio.zig").AudioComponent;
    pub const Script = @import("components/script.zig").ScriptComponent;
};

// Scene systems
pub const systems = struct {
    pub const RenderSystem = @import("systems/render_system.zig").RenderSystem;
    pub const PhysicsSystem = @import("systems/physics_system.zig").PhysicsSystem;
    pub const AudioSystem = @import("systems/audio_system.zig").AudioSystem;
    pub const ScriptSystem = @import("systems/script_system.zig").ScriptSystem;
    pub const TransformSystem = @import("systems/transform_system.zig").TransformSystem;
};

// Spatial partitioning
pub const spatial = struct {
    pub const Octree = @import("spatial/octree.zig").Octree;
};

// Re-export main types
pub const Scene = core.Scene;
pub const Entity = entity.Entity;
pub const EntityId = entity.EntityId;

// Scene management functions
pub fn createScene(allocator: std.mem.Allocator, name: []const u8) !*Scene {
    return try Scene.init(allocator, name);
}

pub fn destroyScene(scene: *Scene) void {
    scene.deinit();
}

// Entity management functions
pub fn createEntity(scene: *Scene) !EntityId {
    return try scene.createEntity();
}

pub fn destroyEntity(scene: *Scene, entity_id: EntityId) void {
    scene.destroyEntity(entity_id);
}

// Component management
pub fn addComponent(scene: *Scene, entity_id: EntityId, component: anytype) !void {
    return try scene.addComponent(entity_id, component);
}

pub fn removeComponent(scene: *Scene, entity_id: EntityId, comptime ComponentType: type) void {
    scene.removeComponent(entity_id, ComponentType);
}

pub fn getComponent(scene: *Scene, entity_id: EntityId, comptime ComponentType: type) ?*ComponentType {
    return scene.getComponent(entity_id, ComponentType);
}

// Scene version information
pub const VERSION = struct {
    pub const MAJOR = 0;
    pub const MINOR = 1;
    pub const PATCH = 0;
    pub const STRING = "0.1.0";
};

test "scene module" {
    const testing = std.testing;

    // Test version constants
    try testing.expect(VERSION.MAJOR == 0);
    try testing.expect(VERSION.MINOR == 1);
    try testing.expect(VERSION.PATCH == 0);
}
