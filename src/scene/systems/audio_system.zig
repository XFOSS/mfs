const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Entity = @import("../core/entity.zig").Entity;
const Scene = @import("../core/scene.zig").Scene;
const TransformComponent = @import("../components/transform.zig").Transform;
const System = @import("../core/scene.zig").System;
const AudioComponent = @import("../components/audio.zig").AudioComponent;
const math = @import("../../libs/math/mod.zig");
const Vec3 = math.Vec3;
const openal = @import("openal.zig");

pub const AudioSystem = struct {
    allocator: Allocator,
    scene: *Scene,
    listener: ?Entity,
    active_sources: ArrayList(Entity),
    master_volume: f32,
    enabled: bool,

    pub fn init(allocator: Allocator, scene: *Scene) !AudioSystem {
        return AudioSystem{
            .allocator = allocator,
            .scene = scene,
            .listener = null,
            .active_sources = ArrayList(Entity).init(allocator),
            .master_volume = 1.0,
            .enabled = true,
        };
    }

    pub fn deinit(self: *AudioSystem) void {
        self.active_sources.deinit();
    }

    pub fn update(self: *AudioSystem) !void {
        if (!self.enabled) return;

        // Find listener if not set
        if (self.listener == null) {
            var it = self.scene.iterator(.{ .audio = true });
            while (it.next()) |entity| {
                const audio = self.scene.getComponent(entity, AudioComponent) orelse continue;
                if (audio.isListener()) {
                    self.listener = entity;
                    break;
                }
            }
        }

        // Update active sources
        self.active_sources.clearRetainingCapacity();

        var it = self.scene.iterator(.{ .audio = true, .transform = true });
        while (it.next()) |entity| {
            const audio = self.scene.getComponent(entity, AudioComponent) orelse continue;
            const transform = self.scene.getComponent(entity, TransformComponent) orelse continue;

            if (audio.isSource()) {
                const source = audio.getSource() orelse continue;

                // Skip if not playing
                if (!source.playing or source.paused) continue;

                // Add to active sources
                try self.active_sources.append(entity);

                // Update source position if spatial
                if (source.spatial) {
                    const position = transform.position; // Use current world position (local for now)
                    // Ensure we have a valid OpenAL source id before sending commands
                    if (source.source_id) |sid| {
                        // Assuming OpenAL function to set source position
                        openal.alSource3f(sid, openal.AL_POSITION, position.x, position.y, position.z);
                    }
                }

                // Update source volume
                const volume = source.volume * self.master_volume;
                if (source.source_id) |sid_gain| {
                    openal.alSourcef(sid_gain, openal.AL_GAIN, volume);
                }
            } else if (audio.isListener()) {
                const listener = audio.getListener() orelse continue;

                // Skip if disabled
                if (!listener.enabled) continue;

                // Update listener position
                const listener_position = transform.position;

                // Ensure we have a valid listener id before sending commands (optional in OpenAL, using global listener here)
                openal.alListener3f(openal.AL_POSITION, listener_position.x, listener_position.y, listener_position.z);

                // Update listener volume (global listener gain)
                const volume = listener.volume * self.master_volume;
                openal.alListenerf(openal.AL_GAIN, volume);
            }
        }
    }

    pub fn setMasterVolume(self: *AudioSystem, volume: f32) void {
        self.master_volume = volume;
    }

    pub fn setEnabled(self: *AudioSystem, enabled: bool) void {
        self.enabled = enabled;
    }

    pub fn playSound(self: *AudioSystem, entity: Entity) !void {
        const audio = self.scene.getComponent(entity, AudioComponent) orelse return;
        if (audio.isSource()) {
            if (audio.getSource()) |source| {
                source.play();
            }
        }
    }

    pub fn pauseSound(self: *AudioSystem, entity: Entity) void {
        const audio = self.scene.getComponent(entity, AudioComponent) orelse return;
        if (audio.isSource()) {
            if (audio.getSource()) |source| {
                source.pause();
            }
        }
    }

    pub fn stopSound(self: *AudioSystem, entity: Entity) void {
        const audio = self.scene.getComponent(entity, AudioComponent) orelse return;
        if (audio.isSource()) {
            if (audio.getSource()) |source| {
                source.stop();
            }
        }
    }

    pub fn setListener(self: *AudioSystem, entity: Entity) !void {
        const audio = self.scene.getComponent(entity, AudioComponent) orelse return;
        if (audio.isListener()) {
            self.listener = entity;
        }
    }

    pub fn getListener(self: *AudioSystem) ?Entity {
        return self.listener;
    }

    pub fn getActiveSources(self: *AudioSystem) []const Entity {
        return self.active_sources.items;
    }
};

/// Standalone update function for use with Scene.addSystem
pub fn update(system: *System, scene: *Scene, delta_time: f32) void {
    _ = system;
    // The standalone update mirrors the behaviour of the AudioSystem struct‐based
    // implementation above but operates directly on the Scene.
    _ = delta_time; // Currently unused but kept for future time-based effects

    const master_volume: f32 = 1.0;

    // ---------------------------------------------------------------------
    // 1. Locate the active listener (if any) and update its properties
    // ---------------------------------------------------------------------
    var listener_position = Vec3.init(0, 0, 0);
    var listener_volume: f32 = 1.0;

    var entity_iter = scene.entities.iterator();
    while (entity_iter.next()) |entry| {
        const entity = entry.value_ptr;

        if (entity.getComponent(AudioComponent)) |audio| {
            if (audio.isListener()) {
                if (audio.getListener()) |listener| {
                    listener_volume = listener.volume * master_volume;
                }

                if (entity.getComponent(TransformComponent)) |transform| {
                    listener_position = transform.position;
                }

                // Found listener, no need to search further
                break;
            }
        }
    }

    // Apply listener settings via OpenAL (global listener)
    openal.alListener3f(openal.AL_POSITION, listener_position.x, listener_position.y, listener_position.z);
    openal.alListenerf(openal.AL_GAIN, listener_volume);

    // ---------------------------------------------------------------------
    // 2. Iterate over all audio sources and update their spatial data / gain
    // ---------------------------------------------------------------------
    var source_iter = scene.entities.iterator();
    while (source_iter.next()) |entry| {
        const entity = entry.value_ptr;

        if (entity.getComponent(AudioComponent)) |audio| {
            if (!audio.isSource()) continue;

            const src = audio.getSource() orelse continue;

            // Skip sources that are not currently playing
            if (!src.playing or src.paused) continue;

            const sid = src.source_id orelse continue; // OpenAL source handle must exist

            // Spatial position update
            if (src.spatial) {
                if (entity.getComponent(TransformComponent)) |transform| {
                    const pos = transform.position;
                    openal.alSource3f(sid, openal.AL_POSITION, pos.x, pos.y, pos.z);
                }
            }

            // Gain update
            const vol = src.volume * master_volume;
            openal.alSourcef(sid, openal.AL_GAIN, vol);
        }
    }
}
