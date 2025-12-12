const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

pub const AudioSource = struct {
    buffer_id: u32,
    volume: f32,
    pitch: f32,
    loop: bool,
    spatial: bool,
    min_distance: f32,
    max_distance: f32,
    rolloff_factor: f32,
    playing: bool,
    paused: bool,
    source_id: ?u32,

    pub fn init(buffer_id: u32) AudioSource {
        return AudioSource{
            .buffer_id = buffer_id,
            .volume = 1.0,
            .pitch = 1.0,
            .loop = false,
            .spatial = true,
            .min_distance = 1.0,
            .max_distance = 100.0,
            .rolloff_factor = 1.0,
            .playing = false,
            .paused = false,
            .source_id = null,
        };
    }
};

pub const AudioListener = struct {
    enabled: bool,
    volume: f32,
    listener_id: ?u32,

    pub fn init() AudioListener {
        return AudioListener{
            .enabled = true,
            .volume = 1.0,
            .listener_id = null,
        };
    }
};

pub const AudioComponent = union(enum) {
    source: AudioSource,
    listener: AudioListener,

    pub fn initSource(buffer_id: u32) AudioComponent {
        return AudioComponent{ .source = AudioSource.init(buffer_id) };
    }

    pub fn initListener() AudioComponent {
        return AudioComponent{ .listener = AudioListener.init() };
    }

    pub fn isSource(self: AudioComponent) bool {
        return self == .source;
    }

    pub fn isListener(self: AudioComponent) bool {
        return self == .listener;
    }

    pub fn getSource(self: *AudioComponent) ?*AudioSource {
        if (self.* == .source) {
            return &self.source;
        }
        return null;
    }

    pub fn getListener(self: *AudioComponent) ?*AudioListener {
        if (self.* == .listener) {
            return &self.listener;
        }
        return null;
    }

    pub fn play(self: *AudioComponent) void {
        if (self.getSource()) |source| {
            source.playing = true;
            source.paused = false;
        }
    }

    pub fn pause(self: *AudioComponent) void {
        if (self.getSource()) |source| {
            source.paused = true;
        }
    }

    pub fn stop(self: *AudioComponent) void {
        if (self.getSource()) |source| {
            source.playing = false;
            source.paused = false;
        }
    }

    pub fn setVolume(self: *AudioComponent, volume: f32) void {
        if (self.getSource()) |source| {
            source.volume = volume;
        } else if (self.getListener()) |listener| {
            listener.volume = volume;
        }
    }

    pub fn setPitch(self: *AudioComponent, pitch: f32) void {
        if (self.getSource()) |source| {
            source.pitch = pitch;
        }
    }

    pub fn setLoop(self: *AudioComponent, loop: bool) void {
        if (self.getSource()) |source| {
            source.loop = loop;
        }
    }

    pub fn setSpatial(self: *AudioComponent, spatial: bool) void {
        if (self.getSource()) |source| {
            source.spatial = spatial;
        }
    }

    pub fn setMinDistance(self: *AudioComponent, distance: f32) void {
        if (self.getSource()) |source| {
            source.min_distance = distance;
        }
    }

    pub fn setMaxDistance(self: *AudioComponent, distance: f32) void {
        if (self.getSource()) |source| {
            source.max_distance = distance;
        }
    }

    pub fn setRolloffFactor(self: *AudioComponent, factor: f32) void {
        if (self.getSource()) |source| {
            source.rolloff_factor = factor;
        }
    }

    pub fn setEnabled(self: *AudioComponent, enabled: bool) void {
        if (self.getListener()) |listener| {
            listener.enabled = enabled;
        }
    }
};
