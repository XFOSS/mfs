//! MFS Engine - Audio Module
//! Comprehensive audio system with 3D spatial audio, mixing, and effects
//! Supports multiple audio backends and formats
//! @thread-safe Audio operations are thread-safe with proper synchronization
//! @performance Optimized for low-latency audio processing

const std = @import("std");
const builtin = @import("builtin");

// Core audio components
pub const audio = @import("audio.zig");

// Re-export main audio types
pub const AudioSystem = audio.AudioEngine;
pub const AudioEngine = audio.AudioEngine;
pub const AudioConfig = audio.AudioEngine.AudioSettings;
pub const AudioSource = audio.AudioEngine.AudioSource;
pub const AudioListener = audio.AudioEngine.AudioListener;
pub const AudioBuffer = audio.AudioEngine.AudioBuffer;

// Audio format support
pub const AudioFormat = enum {
    wav,
    mp3,
    ogg,
    flac,
    aac,
};

// Audio backend types
pub const AudioBackend = enum {
    openal,
    wasapi,
    coreaudio,
    alsa,
    pulse,
    web_audio,

    pub fn isAvailable(self: AudioBackend) bool {
        return switch (self) {
            .openal => true, // OpenAL is cross-platform
            .wasapi => builtin.os.tag == .windows,
            .coreaudio => builtin.os.tag == .macos,
            .alsa => builtin.os.tag == .linux,
            .pulse => builtin.os.tag == .linux,
            .web_audio => builtin.os.tag == .wasi,
        };
    }

    pub fn getName(self: AudioBackend) []const u8 {
        return switch (self) {
            .openal => "OpenAL",
            .wasapi => "WASAPI",
            .coreaudio => "Core Audio",
            .alsa => "ALSA",
            .pulse => "PulseAudio",
            .web_audio => "Web Audio API",
        };
    }
};

// Audio system configuration
pub const Config = struct {
    preferred_backend: ?AudioBackend = null,
    sample_rate: u32 = 44100,
    buffer_size: u32 = 1024,
    max_sources: u32 = 64,
    enable_3d_audio: bool = true,
    enable_effects: bool = true,
    enable_streaming: bool = true,
    master_volume: f32 = 1.0,

    pub fn validate(self: Config) !void {
        if (self.sample_rate < 8000 or self.sample_rate > 192000) {
            return error.InvalidParameter;
        }
        if (self.buffer_size == 0 or self.buffer_size > 8192) {
            return error.InvalidParameter;
        }
        if (self.max_sources == 0 or self.max_sources > 256) {
            return error.InvalidParameter;
        }
        if (self.master_volume < 0.0 or self.master_volume > 2.0) {
            return error.InvalidParameter;
        }
    }
};

// Alias for backward compatibility
pub const AudioSystemConfig = struct {
    preferred_backend: ?AudioBackend = null,
    sample_rate: u32 = 44100,
    buffer_size: u32 = 1024,
    max_sources: u32 = 64,
    enable_3d_audio: bool = true,
    enable_effects: bool = true,
    enable_streaming: bool = true,
    master_volume: f32 = 1.0,

    pub fn validate(self: AudioSystemConfig) !void {
        if (self.sample_rate < 8000 or self.sample_rate > 192000) {
            return error.InvalidParameter;
        }
        if (self.buffer_size == 0 or self.buffer_size > 8192) {
            return error.InvalidParameter;
        }
        if (self.max_sources == 0 or self.max_sources > 256) {
            return error.InvalidParameter;
        }
        if (self.master_volume < 0.0 or self.master_volume > 2.0) {
            return error.InvalidParameter;
        }
    }
};

// Initialize audio system
pub fn init(allocator: std.mem.Allocator, config: Config) !*AudioSystem {
    try config.validate();

    // Convert Config to AudioSettings
    const audio_settings = audio.AudioEngine.AudioSettings{
        .sample_rate = config.sample_rate,
        .buffer_size = config.buffer_size,
        .max_sources = config.max_sources,
        .enable_3d_audio = config.enable_3d_audio,
        .enable_effects = config.enable_effects,
        // Use defaults for fields not in Config
        .channels = 2,
        .bit_depth = 16,
        .max_streaming_sources = 32,
        .enable_reverb = true,
        .doppler_factor = 1.0,
        .speed_of_sound = 343.0,
        .distance_model = .inverse_distance_clamped,
        .rolloff_factor = 1.0,
        .reference_distance = 1.0,
        .max_distance = 1000.0,
    };

    return try AudioSystem.init(allocator, audio_settings);
}

// Cleanup audio system
pub fn deinit(audio_system: *AudioSystem) void {
    audio_system.deinit();
}

// Get available audio backends
pub fn getAvailableBackends(allocator: std.mem.Allocator) ![]AudioBackend {
    var available = std.ArrayList(AudioBackend).init(allocator);
    defer available.deinit();

    inline for (std.meta.fields(AudioBackend)) |field| {
        const backend = @as(AudioBackend, @enumFromInt(field.value));
        if (backend.isAvailable()) {
            try available.append(backend);
        }
    }

    return available.toOwnedSlice();
}

// Reverb settings for 3D audio effects
pub const ReverbSettings = struct {
    room_size: f32 = 0.5,
    damping: f32 = 0.5,
    wet_level: f32 = 0.3,
    dry_level: f32 = 0.7,
    width: f32 = 1.0,
    freeze_mode: bool = false,
    pre_delay: f32 = 0.0,

    pub fn preset_hall() ReverbSettings {
        return ReverbSettings{
            .room_size = 0.9,
            .damping = 0.3,
            .wet_level = 0.5,
            .dry_level = 0.5,
            .width = 1.0,
            .pre_delay = 0.03,
        };
    }

    pub fn preset_room() ReverbSettings {
        return ReverbSettings{
            .room_size = 0.5,
            .damping = 0.7,
            .wet_level = 0.2,
            .dry_level = 0.8,
            .width = 0.8,
            .pre_delay = 0.01,
        };
    }

    pub fn preset_cathedral() ReverbSettings {
        return ReverbSettings{
            .room_size = 1.0,
            .damping = 0.1,
            .wet_level = 0.8,
            .dry_level = 0.2,
            .width = 1.0,
            .pre_delay = 0.05,
        };
    }
};

test "audio module" {
    std.testing.refAllDecls(@This());
}
