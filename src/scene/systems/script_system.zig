const std = @import("std");
const Scene = @import("../core/scene.zig").Scene;
const System = @import("../core/scene.zig").System;

/// Standalone update function for use with Scene.addSystem
pub fn update(system: *System, scene: *Scene, delta_time: f32) void {
    _ = system;
    _ = scene;
    _ = delta_time;

    // TODO: Implement script system functionality
    // This would typically iterate through entities with script components
    // and execute their scripts
}
