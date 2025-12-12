//! Advanced Audio System for MFS Engine
//! Implements 3D spatial audio, effects processing, streaming, and synthesis
//! @thread-safe Audio processing is thread-safe with lock-free queues
//! @symbol AudioEngine - High-performance audio processing

const std = @import("std");
// const math = @import("math");
const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn scale(self: Vec3, scalar: f32) Vec3 {
        return Vec3{
            .x = self.x * scalar,
            .y = self.y * scalar,
            .z = self.z * scalar,
        };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn magnitude(self: Vec3) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn distanceTo(self: Vec3, other: Vec3) f32 {
        return self.sub(other).magnitude();
    }

    pub fn normalize(self: Vec3) Vec3 {
        const mag = self.magnitude();
        if (mag == 0.0) return Vec3.zero;
        return self.scale(1.0 / mag);
    }
};
const Mat4 = struct {
    data: [16]f32,

    pub fn lookAt(eye: Vec3, target: Vec3, up: Vec3) Mat4 {
        const f = target.sub(eye).normalize();
        const s = f.cross(up).normalize();
        const u = s.cross(f);

        return Mat4{
            .data = [16]f32{
                s.x,         u.x,         -f.x,       0.0,
                s.y,         u.y,         -f.y,       0.0,
                s.z,         u.z,         -f.z,       0.0,
                -s.dot(eye), -u.dot(eye), f.dot(eye), 1.0,
            },
        };
    }
};
const platform = @import("../platform/platform.zig");

/// Advanced Audio Engine with modern features
/// @thread-safe Thread-safe audio processing with real-time guarantees
/// @symbol AudioEngine
pub const AudioEngine = struct {
    allocator: std.mem.Allocator,

    // Audio device and context
    audio_device: *AudioDevice,
    audio_context: *AudioContext,

    // Audio sources and buffers
    sources: std.array_list.Managed(*AudioSource),
    buffers: std.array_list.Managed(*AudioBuffer),
    streaming_sources: std.array_list.Managed(*StreamingSource),

    // 3D Audio and listener
    listener: AudioListener,

    // Effects and processing
    reverb_zones: std.array_list.Managed(*ReverbZone),
    effect_chain: *EffectChain,

    // Audio synthesis
    synthesizer: *AudioSynthesizer,

    // Threading and real-time processing
    audio_thread: ?std.Thread = null,
    audio_queue: *LockFreeQueue(AudioCommand),
    is_running: std.atomic.Value(bool),

    // Performance tracking
    stats: AudioStats,

    // Audio settings
    settings: AudioSettings,

    const Self = @This();

    /// Audio engine settings and configuration
    pub const AudioSettings = struct {
        sample_rate: u32 = 44100,
        buffer_size: u32 = 512,
        channels: u32 = 2, // Stereo
        bit_depth: u32 = 16,
        max_sources: u32 = 256,
        max_streaming_sources: u32 = 32,
        enable_3d_audio: bool = true,
        enable_reverb: bool = true,
        enable_effects: bool = true,
        doppler_factor: f32 = 1.0,
        speed_of_sound: f32 = 343.0, // m/s
        distance_model: DistanceModel = .inverse_distance_clamped,
        rolloff_factor: f32 = 1.0,
        reference_distance: f32 = 1.0,
        max_distance: f32 = 1000.0,
    };

    /// Distance attenuation models for 3D audio
    pub const DistanceModel = enum {
        none,
        inverse_distance,
        inverse_distance_clamped,
        linear_distance,
        linear_distance_clamped,
        exponent_distance,
        exponent_distance_clamped,
    };

    /// Audio performance statistics
    pub const AudioStats = struct {
        active_sources: u32 = 0,
        streaming_sources: u32 = 0,
        buffer_underruns: u32 = 0,
        cpu_usage_percent: f32 = 0.0,
        latency_ms: f32 = 0.0,
        sample_rate: u32 = 0,
        buffer_size: u32 = 0,

        pub fn reset(self: *AudioStats) void {
            self.buffer_underruns = 0;
        }
    };

    /// 3D Audio listener (camera/player position)
    pub const AudioListener = struct {
        position: Vec3 = Vec3.zero,
        velocity: Vec3 = Vec3.zero,
        forward: Vec3 = Vec3.init(0, 0, -1),
        up: Vec3 = Vec3.init(0, 1, 0),
        gain: f32 = 1.0,

        pub fn setPosition(self: *AudioListener, position: Vec3) void {
            self.position = position;
        }

        pub fn setVelocity(self: *AudioListener, velocity: Vec3) void {
            self.velocity = velocity;
        }

        pub fn setOrientation(self: *AudioListener, forward: Vec3, up: Vec3) void {
            self.forward = forward.normalize();
            self.up = up.normalize();
        }

        pub fn getTransform(self: *AudioListener) Mat4 {
            const right = self.forward.cross(self.up).normalize();
            const corrected_up = right.cross(self.forward).normalize();

            return Mat4.lookAt(self.position, self.position.add(self.forward), corrected_up);
        }
    };

    /// Audio source for playing sounds in 3D space
    pub const AudioSource = struct {
        id: u32,
        buffer: ?*AudioBuffer = null,

        // 3D properties
        position: Vec3 = Vec3.zero,
        velocity: Vec3 = Vec3.zero,
        direction: Vec3 = Vec3.init(0, 0, -1),

        // Audio properties
        gain: f32 = 1.0,
        pitch: f32 = 1.0,
        min_gain: f32 = 0.0,
        max_gain: f32 = 1.0,
        reference_distance: f32 = 1.0,
        rolloff_factor: f32 = 1.0,
        max_distance: f32 = 1000.0,
        cone_inner_angle: f32 = 360.0,
        cone_outer_angle: f32 = 360.0,
        cone_outer_gain: f32 = 0.0,

        // State
        is_playing: bool = false,
        is_looping: bool = false,
        is_paused: bool = false,
        is_3d: bool = true,

        // Playback state
        playback_position: f64 = 0.0,

        pub fn init(id: u32) AudioSource {
            return AudioSource{
                .id = id,
            };
        }

        pub fn play(self: *AudioSource) void {
            self.is_playing = true;
            self.is_paused = false;
        }

        pub fn pause(self: *AudioSource) void {
            self.is_paused = true;
        }

        pub fn stop(self: *AudioSource) void {
            self.is_playing = false;
            self.is_paused = false;
            self.playback_position = 0.0;
        }

        pub fn setBuffer(self: *AudioSource, buffer: *AudioBuffer) void {
            self.buffer = buffer;
        }

        pub fn setPosition(self: *AudioSource, position: Vec3) void {
            self.position = position;
        }

        pub fn setVelocity(self: *AudioSource, velocity: Vec3) void {
            self.velocity = velocity;
        }

        pub fn setGain(self: *AudioSource, gain: f32) void {
            self.gain = std.math.clamp(gain, 0.0, 1.0);
        }

        pub fn setPitch(self: *AudioSource, pitch: f32) void {
            self.pitch = std.math.clamp(pitch, 0.1, 10.0);
        }

        pub fn setLooping(self: *AudioSource, looping: bool) void {
            self.is_looping = looping;
        }

        pub fn calculateGain(self: *AudioSource, listener: *const AudioListener, settings: *const AudioSettings) f32 {
            if (!self.is_3d) return self.gain;

            const distance = self.position.distanceTo(listener.position);

            // Apply distance attenuation
            var attenuation: f32 = 1.0;
            switch (settings.distance_model) {
                .none => {},
                .inverse_distance => {
                    attenuation = self.reference_distance / (self.reference_distance + self.rolloff_factor * (distance - self.reference_distance));
                },
                .inverse_distance_clamped => {
                    const clamped_distance = std.math.clamp(distance, self.reference_distance, self.max_distance);
                    attenuation = self.reference_distance / (self.reference_distance + self.rolloff_factor * (clamped_distance - self.reference_distance));
                },
                .linear_distance => {
                    attenuation = 1.0 - self.rolloff_factor * (distance - self.reference_distance) / (self.max_distance - self.reference_distance);
                },
                .linear_distance_clamped => {
                    const clamped_distance = std.math.clamp(distance, self.reference_distance, self.max_distance);
                    attenuation = 1.0 - self.rolloff_factor * (clamped_distance - self.reference_distance) / (self.max_distance - self.reference_distance);
                },
                .exponent_distance => {
                    attenuation = std.math.pow(f32, distance / self.reference_distance, -self.rolloff_factor);
                },
                .exponent_distance_clamped => {
                    const clamped_distance = std.math.clamp(distance, self.reference_distance, self.max_distance);
                    attenuation = std.math.pow(f32, clamped_distance / self.reference_distance, -self.rolloff_factor);
                },
            }

            // Apply cone attenuation
            if (self.cone_inner_angle < 360.0) {
                const to_listener = listener.position.sub(self.position).normalize();
                const dot = self.direction.dot(to_listener);
                const angle = std.math.acos(std.math.clamp(dot, -1.0, 1.0)) * 180.0 / std.math.pi;

                if (angle > self.cone_outer_angle * 0.5) {
                    attenuation *= self.cone_outer_gain;
                } else if (angle > self.cone_inner_angle * 0.5) {
                    const factor = (angle - self.cone_inner_angle * 0.5) / (self.cone_outer_angle * 0.5 - self.cone_inner_angle * 0.5);
                    attenuation *= std.math.lerp(1.0, self.cone_outer_gain, factor);
                }
            }

            return std.math.clamp(self.gain * attenuation, self.min_gain, self.max_gain);
        }

        pub fn calculatePitch(self: *AudioSource, listener: *const AudioListener, settings: *const AudioSettings) f32 {
            if (!self.is_3d or settings.doppler_factor == 0.0) return self.pitch;

            // Calculate Doppler effect
            const to_listener = listener.position.sub(self.position);
            const distance = to_listener.magnitude();

            if (distance < 0.001) return self.pitch;

            const direction_to_listener = to_listener.scale(1.0 / distance);
            const source_velocity_component = self.velocity.dot(direction_to_listener);
            const listener_velocity_component = listener.velocity.dot(direction_to_listener);

            const relative_velocity = listener_velocity_component - source_velocity_component;
            const doppler_shift = (settings.speed_of_sound + settings.doppler_factor * relative_velocity) / settings.speed_of_sound;

            return self.pitch * std.math.clamp(doppler_shift, 0.1, 10.0);
        }
    };

    /// Audio buffer containing PCM audio data
    pub const AudioBuffer = struct {
        id: u32,
        data: []f32,
        sample_rate: u32,
        channels: u32,
        duration: f64,

        pub fn init(allocator: std.mem.Allocator, id: u32, data: []const f32, sample_rate: u32, channels: u32) !*AudioBuffer {
            const buffer = try allocator.create(AudioBuffer);
            buffer.* = AudioBuffer{
                .id = id,
                .data = try allocator.dupe(f32, data),
                .sample_rate = sample_rate,
                .channels = channels,
                .duration = @as(f64, @floatFromInt(data.len)) / @as(f64, @floatFromInt(sample_rate * channels)),
            };
            return buffer;
        }

        pub fn deinit(self: *AudioBuffer, allocator: std.mem.Allocator) void {
            allocator.free(self.data);
            allocator.destroy(self);
        }

        pub fn getSample(self: *AudioBuffer, sample_index: usize, channel: u32) f32 {
            const index = sample_index * self.channels + channel;
            if (index >= self.data.len) return 0.0;
            return self.data[index];
        }

        pub fn getSampleInterpolated(self: *AudioBuffer, position: f64, channel: u32) f32 {
            const sample_position = position * @as(f64, @floatFromInt(self.sample_rate));
            const sample_index = @as(usize, @intFromFloat(@floor(sample_position)));
            const fraction = @as(f32, @floatCast(sample_position - @floor(sample_position)));

            const sample1 = self.getSample(sample_index, channel);
            const sample2 = self.getSample(sample_index + 1, channel);

            return std.math.lerp(sample1, sample2, fraction);
        }
    };

    /// Streaming audio source for large audio files
    pub const StreamingSource = struct {
        id: u32,
        file_path: []const u8,
        decoder: *AudioDecoder,

        // Streaming buffers
        buffers: [2]*AudioBuffer,
        current_buffer: u32 = 0,

        // Source properties (same as AudioSource)
        position: Vec3 = Vec3.zero,
        velocity: Vec3 = Vec3.zero,
        gain: f32 = 1.0,
        pitch: f32 = 1.0,
        is_playing: bool = false,
        is_looping: bool = false,
        is_paused: bool = false,

        // Streaming state
        stream_position: f64 = 0.0,
        needs_buffer_update: bool = false,

        pub fn init(allocator: std.mem.Allocator, id: u32, file_path: []const u8) !*StreamingSource {
            const source = try allocator.create(StreamingSource);
            source.* = StreamingSource{
                .id = id,
                .file_path = try allocator.dupe(u8, file_path),
                .decoder = try AudioDecoder.init(allocator, file_path),
                .buffers = undefined,
            };

            // Initialize streaming buffers
            const buffer_size = 4096; // samples per buffer
            const empty_data = try allocator.alloc(f32, buffer_size * 2); // stereo
            @memset(empty_data, 0.0);

            source.buffers[0] = try AudioBuffer.init(allocator, 0, empty_data, 44100, 2);
            source.buffers[1] = try AudioBuffer.init(allocator, 1, empty_data, 44100, 2);

            allocator.free(empty_data);
            return source;
        }

        pub fn deinit(self: *StreamingSource, allocator: std.mem.Allocator) void {
            self.buffers[0].deinit();
            self.buffers[1].deinit();
            self.decoder.deinit();
            allocator.free(self.file_path);
            allocator.destroy(self);
        }

        pub fn updateBuffer(self: *StreamingSource) !void {
            if (!self.needs_buffer_update) return;

            const buffer = self.buffers[1 - self.current_buffer];
            try self.decoder.decode(buffer.data);

            self.current_buffer = 1 - self.current_buffer;
            self.needs_buffer_update = false;
        }
    };

    /// Audio decoder for various formats
    pub const AudioDecoder = struct {
        allocator: std.mem.Allocator,
        file_path: []const u8,
        format: AudioFormat,

        pub const AudioFormat = enum {
            wav,
            ogg,
            mp3,
            flac,
        };

        pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !*AudioDecoder {
            const decoder = try allocator.create(AudioDecoder);
            decoder.* = AudioDecoder{
                .allocator = allocator,
                .file_path = try allocator.dupe(u8, file_path),
                .format = detectFormat(file_path),
            };
            return decoder;
        }

        pub fn deinit(self: *AudioDecoder) void {
            self.allocator.free(self.file_path);
            self.allocator.destroy(self);
        }

        pub fn decode(self: *AudioDecoder, output_buffer: []f32) !void {
            switch (self.format) {
                .wav => try self.decodeWav(output_buffer),
                .ogg => try self.decodeOgg(output_buffer),
                .mp3 => try self.decodeMp3(output_buffer),
                .flac => try self.decodeFlac(output_buffer),
            }
        }

        fn detectFormat(file_path: []const u8) AudioFormat {
            if (std.mem.endsWith(u8, file_path, ".wav")) return .wav;
            if (std.mem.endsWith(u8, file_path, ".ogg")) return .ogg;
            if (std.mem.endsWith(u8, file_path, ".mp3")) return .mp3;
            if (std.mem.endsWith(u8, file_path, ".flac")) return .flac;
            return .wav; // default
        }

        fn decodeWav(self: *AudioDecoder, output_buffer: []f32) !void {
            // Load WAV file data
            const file = std.fs.cwd().openFile(self.file_path, .{}) catch |err| {
                std.log.warn("Failed to open WAV file '{s}': {}", .{ self.file_path, err });
                @memset(output_buffer, 0.0);
                return;
            };
            defer file.close();

            const file_size = file.getEndPos() catch {
                std.log.warn("Failed to get WAV file size", .{});
                @memset(output_buffer, 0.0);
                return;
            };

            if (file_size < 44) {
                std.log.warn("WAV file too small (less than 44 bytes)", .{});
                @memset(output_buffer, 0.0);
                return;
            }

            const file_data = self.allocator.alloc(u8, file_size) catch {
                std.log.warn("Failed to allocate memory for WAV file", .{});
                @memset(output_buffer, 0.0);
                return;
            };
            defer self.allocator.free(file_data);

            // Ensure complete file read
            var total_bytes_read: usize = 0;
            while (total_bytes_read < file_data.len) {
                const bytes_read = file.read(file_data[total_bytes_read..]) catch {
                    std.log.warn("Failed to read WAV file data at offset {}", .{total_bytes_read});
                    @memset(output_buffer, 0.0);
                    return;
                };
                if (bytes_read == 0) break; // EOF
                total_bytes_read += bytes_read;
            }

            if (total_bytes_read != file_data.len) {
                std.log.warn("Incomplete WAV file read: expected {} bytes, got {}", .{ file_data.len, total_bytes_read });
                @memset(output_buffer, 0.0);
                return;
            }

            // Parse WAV header
            if (!std.mem.eql(u8, file_data[0..4], "RIFF")) {
                std.log.warn("Invalid WAV file: missing RIFF header", .{});
                @memset(output_buffer, 0.0);
                return;
            }

            if (!std.mem.eql(u8, file_data[8..12], "WAVE")) {
                std.log.warn("Invalid WAV file: missing WAVE identifier", .{});
                @memset(output_buffer, 0.0);
                return;
            }

            if (!std.mem.eql(u8, file_data[12..16], "fmt ")) {
                std.log.warn("Invalid WAV file: missing fmt chunk", .{});
                @memset(output_buffer, 0.0);
                return;
            }

            const format_chunk_size = std.mem.readInt(u32, file_data[16..20], .little);
            if (format_chunk_size < 16) {
                std.log.warn("Invalid WAV file: fmt chunk too small", .{});
                @memset(output_buffer, 0.0);
                return;
            }

            const audio_format = std.mem.readInt(u16, file_data[20..22], .little);
            const num_channels = std.mem.readInt(u16, file_data[22..24], .little);
            const bits_per_sample = std.mem.readInt(u16, file_data[34..36], .little);

            // Find data chunk
            var offset: usize = 20 + format_chunk_size;
            while (offset + 8 < file_data.len) {
                if (std.mem.eql(u8, file_data[offset .. offset + 4], "data")) {
                    const data_size = std.mem.readInt(u32, file_data[offset + 4 .. offset + 8][0..4], .little);
                    const audio_data = file_data[offset + 8 .. @min(offset + 8 + data_size, file_data.len)];

                    // Convert to f32 based on bit depth
                    switch (bits_per_sample) {
                        16 => {
                            const samples = audio_data.len / 2;
                            const max_samples = @min(samples, output_buffer.len);
                            for (0..max_samples) |i| {
                                const sample_i16 = std.mem.readInt(i16, audio_data[i * 2 .. i * 2 + 2][0..2], .little);
                                output_buffer[i] = @as(f32, @floatFromInt(sample_i16)) / 32768.0;
                            }
                        },
                        24 => {
                            const samples = audio_data.len / 3;
                            const max_samples = @min(samples, output_buffer.len);
                            for (0..max_samples) |i| {
                                var sample_i32: i32 = 0;
                                sample_i32 |= @as(i32, @intCast(audio_data[i * 3]));
                                sample_i32 |= @as(i32, @intCast(audio_data[i * 3 + 1])) << 8;
                                sample_i32 |= @as(i32, @intCast(audio_data[i * 3 + 2])) << 16;
                                if (sample_i32 & 0x800000 != 0) sample_i32 |= @as(i32, @bitCast(@as(u32, 0xFF000000))); // Sign extend
                                output_buffer[i] = @as(f32, @floatFromInt(sample_i32)) / 8388608.0;
                            }
                        },
                        32 => {
                            if (audio_format == 1) { // PCM
                                const samples = audio_data.len / 4;
                                const max_samples = @min(samples, output_buffer.len);
                                for (0..max_samples) |i| {
                                    const sample_i32 = std.mem.readInt(i32, audio_data[i * 4 .. i * 4 + 4][0..4], .little);
                                    output_buffer[i] = @as(f32, @floatFromInt(sample_i32)) / 2147483648.0;
                                }
                            } else if (audio_format == 3) { // IEEE float
                                const samples = audio_data.len / 4;
                                const max_samples = @min(samples, output_buffer.len);
                                for (0..max_samples) |i| {
                                    output_buffer[i] = @bitCast(std.mem.readInt(u32, audio_data[i * 4 .. i * 4 + 4][0..4], .little));
                                }
                            }
                        },
                        else => {
                            std.log.warn("Unsupported WAV bit depth: {}", .{bits_per_sample});
                            @memset(output_buffer, 0.0);
                            return;
                        },
                    }

                    // Handle channel conversion (for multi-channel audio)
                    if (num_channels > 2) {
                        // For now, just take the first channel if more than 2 channels
                        const stride = num_channels;
                        var i: usize = 0;
                        while (i * stride < output_buffer.len) {
                            if (i < output_buffer.len) {
                                output_buffer[i] = output_buffer[i * stride];
                            }
                            i += 1;
                        }
                    }

                    return;
                }

                // Skip to next chunk
                const chunk_size = std.mem.readInt(u32, file_data[offset + 4 .. offset + 8][0..4], .little);
                offset += 8 + chunk_size;
            }

            std.log.warn("WAV file has no data chunk", .{});
            @memset(output_buffer, 0.0);
        }

        fn decodeOgg(self: *AudioDecoder, output_buffer: []f32) !void {
            _ = self;
            // Basic OGG Vorbis decoding stub - would need libvorbis integration
            // For now, generate silence with a warning
            std.log.warn("OGG Vorbis decoding not yet implemented, generating silence", .{});
            @memset(output_buffer, 0.0);
        }

        fn decodeMp3(self: *AudioDecoder, output_buffer: []f32) !void {
            _ = self;
            // Basic MP3 decoding stub - would need libmp3lame or similar integration
            // For now, generate silence with a warning
            std.log.warn("MP3 decoding not yet implemented, generating silence", .{});
            @memset(output_buffer, 0.0);
        }

        fn decodeFlac(self: *AudioDecoder, output_buffer: []f32) !void {
            _ = self;
            // Basic FLAC decoding stub - would need libflac integration
            // For now, generate silence with a warning
            std.log.warn("FLAC decoding not yet implemented, generating silence", .{});
            @memset(output_buffer, 0.0);
        }
    };

    /// Reverb zone for environmental audio effects
    pub const ReverbZone = struct {
        position: Vec3,
        radius: f32,
        reverb_params: ReverbParameters,

        pub const ReverbParameters = struct {
            room_size: f32 = 0.5,
            damping: f32 = 0.5,
            wet_level: f32 = 0.3,
            dry_level: f32 = 0.7,
            width: f32 = 1.0,
            freeze_mode: bool = false,
        };

        pub fn init(position: Vec3, radius: f32) ReverbZone {
            return ReverbZone{
                .position = position,
                .radius = radius,
                .reverb_params = ReverbParameters{},
            };
        }

        pub fn getInfluence(self: *ReverbZone, listener_position: Vec3) f32 {
            const distance = self.position.distance(listener_position);
            if (distance >= self.radius) return 0.0;
            return 1.0 - (distance / self.radius);
        }
    };

    /// Audio effects chain processor
    pub const EffectChain = struct {
        allocator: std.mem.Allocator,
        effects: std.ArrayList(*AudioEffect),

        pub fn init(allocator: std.mem.Allocator) !*EffectChain {
            const chain = try allocator.create(EffectChain);
            chain.* = EffectChain{
                .allocator = allocator,
                .effects = try std.ArrayList(*AudioEffect).initCapacity(allocator, 4),
            };
            return chain;
        }

        pub fn deinit(self: *EffectChain) void {
            for (self.effects.items) |effect| {
                effect.deinit();
            }
            self.effects.deinit();
            self.allocator.destroy(self);
        }

        pub fn addEffect(self: *EffectChain, effect: *AudioEffect) !void {
            try self.effects.append(effect);
        }

        pub fn process(self: *EffectChain, input: []const f32, output: []f32) void {
            if (self.effects.items.len == 0) {
                // Avoid aliasing by checking if input and output are the same
                if (@intFromPtr(input.ptr) != @intFromPtr(output.ptr)) {
                    @memcpy(output, input);
                }
                return;
            }

            // Create temporary buffers for effect chain
            const temp_buffer1 = self.allocator.alloc(f32, input.len) catch return;
            const temp_buffer2 = self.allocator.alloc(f32, input.len) catch return;
            defer self.allocator.free(temp_buffer1);
            defer self.allocator.free(temp_buffer2);

            @memcpy(temp_buffer1, input);

            for (self.effects.items, 0..) |effect, i| {
                const src = if (i % 2 == 0) temp_buffer1 else temp_buffer2;
                const dst = if (i % 2 == 0) temp_buffer2 else temp_buffer1;
                effect.process(src, dst);
            }

            const final_buffer = if (self.effects.items.len % 2 == 1) temp_buffer2 else temp_buffer1;
            // Avoid aliasing by checking if output and final_buffer are the same
            if (@intFromPtr(output.ptr) != @intFromPtr(final_buffer.ptr)) {
                @memcpy(output, final_buffer);
            }
        }
    };

    /// Base audio effect interface
    pub const AudioEffect = struct {
        effect_type: EffectType,
        vtable: *const VTable,

        pub const EffectType = enum {
            reverb,
            delay,
            chorus,
            distortion,
            equalizer,
            compressor,
            limiter,
        };

        pub const VTable = struct {
            process: *const fn (*AudioEffect, []const f32, []f32) void,
            deinit: *const fn (*AudioEffect) void,
        };

        pub fn process(self: *AudioEffect, input: []const f32, output: []f32) void {
            self.vtable.process(self, input, output);
        }

        pub fn deinit(self: *AudioEffect) void {
            self.vtable.deinit(self);
        }
    };

    /// Audio synthesizer for procedural sound generation
    pub const AudioSynthesizer = struct {
        allocator: std.mem.Allocator,
        oscillators: std.ArrayList(*Oscillator),
        sample_rate: u32,

        pub fn init(allocator: std.mem.Allocator, sample_rate: u32) !*AudioSynthesizer {
            const synth = try allocator.create(AudioSynthesizer);
            synth.* = AudioSynthesizer{
                .allocator = allocator,
                .oscillators = try std.ArrayList(*Oscillator).initCapacity(allocator, 8),
                .sample_rate = sample_rate,
            };
            return synth;
        }

        pub fn deinit(self: *AudioSynthesizer) void {
            for (self.oscillators.items) |osc| {
                osc.deinit();
            }
            self.oscillators.deinit();
            self.allocator.destroy(self);
        }

        pub fn createOscillator(self: *AudioSynthesizer, wave_type: WaveType, frequency: f32) !*Oscillator {
            const osc = try Oscillator.init(self.allocator, wave_type, frequency, self.sample_rate);
            try self.oscillators.append(osc);
            return osc;
        }

        pub fn synthesize(self: *AudioSynthesizer, output: []f32, channels: u32) void {
            @memset(output, 0.0);

            for (self.oscillators.items) |osc| {
                if (osc.is_active) {
                    osc.generate(output, channels);
                }
            }
        }

        pub const WaveType = enum {
            sine,
            square,
            triangle,
            sawtooth,
            noise,
        };

        pub const Oscillator = struct {
            wave_type: WaveType,
            frequency: f32,
            amplitude: f32 = 1.0,
            phase: f32 = 0.0,
            sample_rate: u32,
            is_active: bool = true,

            pub fn init(allocator: std.mem.Allocator, wave_type: WaveType, frequency: f32, sample_rate: u32) !*Oscillator {
                const osc = try allocator.create(Oscillator);
                osc.* = Oscillator{
                    .wave_type = wave_type,
                    .frequency = frequency,
                    .sample_rate = sample_rate,
                };
                return osc;
            }

            pub fn deinit(self: *Oscillator, allocator: std.mem.Allocator) void {
                allocator.destroy(self);
            }

            pub fn generate(self: *Oscillator, output: []f32, channels: u32) void {
                const samples_per_channel = output.len / channels;
                const phase_increment = 2.0 * std.math.pi * self.frequency / @as(f32, @floatFromInt(self.sample_rate));

                for (0..samples_per_channel) |i| {
                    const sample = self.generateSample();

                    for (0..channels) |ch| {
                        output[i * channels + ch] += sample * self.amplitude;
                    }

                    self.phase += phase_increment;
                    if (self.phase >= 2.0 * std.math.pi) {
                        self.phase -= 2.0 * std.math.pi;
                    }
                }
            }

            fn generateSample(self: *Oscillator) f32 {
                return switch (self.wave_type) {
                    .sine => @sin(self.phase),
                    .square => if (@sin(self.phase) >= 0.0) 1.0 else -1.0,
                    .triangle => (2.0 / std.math.pi) * std.math.asin(@sin(self.phase)),
                    .sawtooth => (2.0 / std.math.pi) * (self.phase - std.math.pi),
                    .noise => (std.crypto.random.float(f32) * 2.0) - 1.0,
                };
            }

            pub fn setFrequency(self: *Oscillator, frequency: f32) void {
                self.frequency = frequency;
            }

            pub fn setAmplitude(self: *Oscillator, amplitude: f32) void {
                self.amplitude = std.math.clamp(amplitude, 0.0, 1.0);
            }
        };
    };

    /// Audio device abstraction
    pub const AudioDevice = struct {
        allocator: std.mem.Allocator,
        settings: AudioSettings,
        is_active: bool = false,

        pub fn init(allocator: std.mem.Allocator, settings: AudioSettings) !*AudioDevice {
            const device = try allocator.create(AudioDevice);
            device.* = AudioDevice{
                .allocator = allocator,
                .settings = settings,
            };

            std.log.info("Audio device initialized with settings:", .{});
            std.log.info("  Sample rate: {} Hz", .{settings.sample_rate});
            std.log.info("  Buffer size: {} samples", .{settings.buffer_size});
            std.log.info("  Channels: {}", .{settings.channels});

            return device;
        }

        pub fn deinit(self: *AudioDevice, allocator: std.mem.Allocator) void {
            if (self.is_active) {
                self.stop();
            }
            allocator.destroy(self);
        }

        pub fn start(self: *AudioDevice) !void {
            if (self.is_active) return;

            // Platform-specific audio device initialization would go here
            // For now, we'll just mark it as active
            self.is_active = true;
            std.log.info("Audio device started", .{});
        }

        pub fn stop(self: *AudioDevice) void {
            if (!self.is_active) return;

            // Platform-specific audio device cleanup would go here
            self.is_active = false;
            std.log.info("Audio device stopped", .{});
        }

        pub fn isActive(self: *const AudioDevice) bool {
            return self.is_active;
        }

        pub fn sendBuffer(self: *AudioDevice, buffer: []const f32) void {
            if (!self.is_active) return;

            // In a real implementation, this would send the buffer to the audio driver
            // For now, we'll just update some internal state
            _ = buffer;
            // Platform-specific buffer submission would happen here
        }
    };

    /// Audio context for managing audio state
    pub const AudioContext = struct {
        pub fn init(allocator: std.mem.Allocator) !*AudioContext {
            const context = try allocator.create(AudioContext);
            return context;
        }

        pub fn deinit(self: *AudioContext, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };

    /// Lock-free queue for real-time audio commands
    pub fn LockFreeQueue(comptime T: type) type {
        return struct {
            const Queue = @This();

            items: []T,
            head: std.atomic.Value(usize),
            tail: std.atomic.Value(usize),
            capacity: usize,

            pub fn init(allocator: std.mem.Allocator, capacity: usize) !*Queue {
                const queue = try allocator.create(Queue);
                queue.* = Queue{
                    .items = try allocator.alloc(T, capacity),
                    .head = std.atomic.Value(usize).init(0),
                    .tail = std.atomic.Value(usize).init(0),
                    .capacity = capacity,
                };
                return queue;
            }

            pub fn deinit(self: *Queue, allocator: std.mem.Allocator) void {
                allocator.free(self.items);
                allocator.destroy(self);
            }

            pub fn push(self: *Queue, item: T) bool {
                const current_tail = self.tail.load(.acquire);
                const next_tail = (current_tail + 1) % self.capacity;

                if (next_tail == self.head.load(.acquire)) {
                    return false; // Queue is full
                }

                self.items[current_tail] = item;
                self.tail.store(next_tail, .release);
                return true;
            }

            pub fn pop(self: *Queue) ?T {
                const current_head = self.head.load(.acquire);

                if (current_head == self.tail.load(.acquire)) {
                    return null; // Queue is empty
                }

                const item = self.items[current_head];
                self.head.store((current_head + 1) % self.capacity, .release);
                return item;
            }
        };
    }

    /// Audio command for thread communication
    pub const AudioCommand = union(enum) {
        play_source: struct { source_id: u32 },
        stop_source: struct { source_id: u32 },
        set_listener_position: struct { position: Vec3 },
        set_source_position: struct { source_id: u32, position: Vec3 },
        load_buffer: struct { buffer_id: u32, file_path: []const u8 },
    };

    pub fn init(allocator: std.mem.Allocator, settings: AudioSettings) !*Self {
        const engine = try allocator.create(Self);
        engine.* = Self{
            .allocator = allocator,
            .audio_device = try AudioDevice.init(allocator, settings),
            .audio_context = try AudioContext.init(allocator),
            .sources = try std.ArrayList(*AudioSource).initCapacity(allocator, 32),
            .buffers = try std.ArrayList(*AudioBuffer).initCapacity(allocator, 16),
            .streaming_sources = try std.ArrayList(*StreamingSource).initCapacity(allocator, 8),
            .listener = AudioListener{},
            .reverb_zones = try std.ArrayList(*ReverbZone).initCapacity(allocator, 4),
            .effect_chain = try EffectChain.init(allocator),
            .synthesizer = try AudioSynthesizer.init(allocator, settings.sample_rate),
            .audio_queue = try LockFreeQueue(AudioCommand).init(allocator, 1024),
            .is_running = std.atomic.Value(bool).init(false),
            .stats = AudioStats{
                .sample_rate = settings.sample_rate,
                .buffer_size = settings.buffer_size,
            },
            .settings = settings,
        };

        // Start audio processing thread
        try engine.start();

        std.log.info("Audio engine initialized", .{});
        std.log.info("  Sample rate: {d} Hz", .{settings.sample_rate});
        std.log.info("  Buffer size: {d} samples", .{settings.buffer_size});
        std.log.info("  Channels: {d}", .{settings.channels});
        std.log.info("  3D Audio: {}", .{settings.enable_3d_audio});
        std.log.info("  Effects: {}", .{settings.enable_effects});

        return engine;
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        // Clean up sources
        for (self.sources.items) |source| {
            self.allocator.destroy(source);
        }
        self.sources.deinit();

        // Clean up buffers
        for (self.buffers.items) |buffer| {
            buffer.deinit();
        }
        self.buffers.deinit();

        // Clean up streaming sources
        for (self.streaming_sources.items) |source| {
            source.deinit();
        }
        self.streaming_sources.deinit();

        // Clean up reverb zones
        for (self.reverb_zones.items) |zone| {
            self.allocator.destroy(zone);
        }
        self.reverb_zones.deinit();

        // Clean up subsystems
        self.effect_chain.deinit();
        self.synthesizer.deinit();
        self.audio_queue.deinit();
        self.audio_context.deinit();
        self.audio_device.deinit();

        self.allocator.destroy(self);
    }

    pub fn update(self: *Self, delta_time: f64) !void {
        _ = self;
        _ = delta_time;
        // TODO: Update audio engine subsystems
        // This would include:
        // - Processing audio effects
        // - Updating 3D audio positions
        // - Managing audio streaming
        // - Handling audio events
    }

    pub fn start(self: *Self) !void {
        self.is_running.store(true, .release);
        try self.audio_device.start();

        self.audio_thread = try std.Thread.spawn(.{}, audioThreadMain, .{self});
    }

    pub fn stop(self: *Self) void {
        self.is_running.store(false, .release);

        if (self.audio_thread) |thread| {
            thread.join();
            self.audio_thread = null;
        }

        self.audio_device.stop();
    }

    fn audioThreadMain(self: *Self) void {
        const buffer_size = self.settings.buffer_size * self.settings.channels;
        const output_buffer = self.allocator.alloc(f32, buffer_size) catch return;
        defer self.allocator.free(output_buffer);

        while (self.is_running.load(.acquire)) {
            // Process audio commands
            while (self.audio_queue.pop()) |command| {
                self.processCommand(command);
            }

            // Generate audio
            self.generateAudioFrame(output_buffer);

            // Send buffer to audio device
            if (self.audio_device.isActive()) {
                self.audio_device.sendBuffer(output_buffer);
            }

            // Update statistics
            self.updateStats();

            // Small sleep to prevent busy waiting
            // TODO: Fix sleep API for Zig 0.16 - std.time.sleep API changed
            // std.time.sleep(1_000_000); // 1ms
        }
    }

    fn processCommand(self: *Self, command: AudioCommand) void {
        switch (command) {
            .play_source => |cmd| {
                if (self.findSource(cmd.source_id)) |source| {
                    source.play();
                }
            },
            .stop_source => |cmd| {
                if (self.findSource(cmd.source_id)) |source| {
                    source.stop();
                }
            },
            .set_listener_position => |cmd| {
                self.listener.setPosition(cmd.position);
            },
            .set_source_position => |cmd| {
                if (self.findSource(cmd.source_id)) |source| {
                    source.setPosition(cmd.position);
                }
            },
            .load_buffer => |cmd| {
                // Load audio buffer from file
                self.loadBufferFromFile(cmd.buffer_id, cmd.file_path) catch |err| {
                    std.log.warn("Failed to load audio buffer from '{s}': {}", .{ cmd.file_path, err });
                };
            },
        }
    }

    fn generateAudioFrame(self: *Self, output_buffer: []f32) void {
        @memset(output_buffer, 0.0);

        // Mix all active sources
        for (self.sources.items) |source| {
            if (source.is_playing and !source.is_paused and source.buffer != null) {
                self.mixSource(source, output_buffer);
            }
        }

        // Mix streaming sources
        for (self.streaming_sources.items) |source| {
            if (source.is_playing and !source.is_paused) {
                self.mixStreamingSource(source, output_buffer);
            }
        }

        // Apply effects
        if (self.settings.enable_effects) {
            // Create temporary buffer to avoid aliasing
            const temp_buffer = self.allocator.alloc(f32, output_buffer.len) catch {
                std.log.warn("Failed to allocate temporary audio buffer for effects", .{});
                return;
            };
            defer self.allocator.free(temp_buffer);

            @memcpy(temp_buffer, output_buffer);
            self.effect_chain.process(temp_buffer, output_buffer);
        }

        // Apply master gain and limiting
        for (output_buffer) |*sample| {
            sample.* = std.math.clamp(sample.* * self.listener.gain, -1.0, 1.0);
        }
    }

    fn mixSource(self: *Self, source: *AudioSource, output_buffer: []f32) void {
        const buffer = source.buffer.?;
        const samples_per_channel = output_buffer.len / self.settings.channels;

        const gain = source.calculateGain(&self.listener, &self.settings);
        const pitch = source.calculatePitch(&self.listener, &self.settings);

        for (0..samples_per_channel) |i| {
            if (source.playback_position >= buffer.duration) {
                if (source.is_looping) {
                    source.playback_position = 0.0;
                } else {
                    source.stop();
                    break;
                }
            }

            // Get sample from buffer with interpolation
            const sample_l = buffer.getSampleInterpolated(source.playback_position, 0) * gain;
            const sample_r = if (buffer.channels > 1)
                buffer.getSampleInterpolated(source.playback_position, 1) * gain
            else
                sample_l;

            // Apply 3D positioning (simplified stereo panning)
            var left_gain: f32 = 1.0;
            var right_gain: f32 = 1.0;

            if (self.settings.enable_3d_audio and source.is_3d) {
                const to_source = source.position.sub(self.listener.position);
                const right = self.listener.forward.cross(self.listener.up).normalize();
                const pan = std.math.clamp(to_source.dot(right), -1.0, 1.0);

                left_gain = std.math.sqrt((1.0 - pan) * 0.5);
                right_gain = std.math.sqrt((1.0 + pan) * 0.5);
            }

            // Mix into output buffer
            if (self.settings.channels >= 1) {
                output_buffer[i * self.settings.channels] += sample_l * left_gain;
            }
            if (self.settings.channels >= 2) {
                output_buffer[i * self.settings.channels + 1] += sample_r * right_gain;
            }

            // Advance playback position
            source.playback_position += pitch / @as(f64, @floatFromInt(self.settings.sample_rate));
        }
    }

    fn mixStreamingSource(self: *Self, source: *StreamingSource, output_buffer: []f32) void {
        // Update streaming buffer if needed
        source.updateBuffer() catch |err| {
            std.log.warn("Failed to update streaming buffer: {}", .{err});
            return;
        };

        const buffer = source.buffers[source.current_buffer];
        const samples_per_channel = output_buffer.len / self.settings.channels;

        // Simple mixing for streaming sources
        for (0..samples_per_channel) |i| {
            if (i >= buffer.data.len) break;

            const sample = buffer.data[i] * source.gain;

            // Mix into output buffer (mono to stereo for simplicity)
            if (self.settings.channels >= 1) {
                output_buffer[i * self.settings.channels] += sample;
            }
            if (self.settings.channels >= 2) {
                output_buffer[i * self.settings.channels + 1] += sample;
            }
        }
    }

    fn updateStats(self: *Self) void {
        var active_sources: u32 = 0;
        for (self.sources.items) |source| {
            if (source.is_playing) active_sources += 1;
        }

        self.stats.active_sources = active_sources;
        self.stats.streaming_sources = @intCast(self.streaming_sources.items.len);
    }

    fn findSource(self: *Self, source_id: u32) ?*AudioSource {
        for (self.sources.items) |source| {
            if (source.id == source_id) return source;
        }
        return null;
    }

    // Public API methods

    pub fn createSource(self: *Self) !*AudioSource {
        const source_id = @as(u32, @intCast(self.sources.items.len));
        const source = try self.allocator.create(AudioSource);
        source.* = AudioSource.init(source_id);
        try self.sources.append(source);
        return source;
    }

    pub fn createBuffer(self: *Self, data: []const f32, sample_rate: u32, channels: u32) !*AudioBuffer {
        const buffer_id = @as(u32, @intCast(self.buffers.items.len));
        const buffer = try AudioBuffer.init(self.allocator, buffer_id, data, sample_rate, channels);
        try self.buffers.append(buffer);
        return buffer;
    }

    pub fn createStreamingSource(self: *Self, file_path: []const u8) !*StreamingSource {
        const source_id = @as(u32, @intCast(self.streaming_sources.items.len));
        const source = try StreamingSource.init(self.allocator, source_id, file_path);
        try self.streaming_sources.append(source);
        return source;
    }

    pub fn setListenerPosition(self: *Self, position: Vec3) void {
        const command = AudioCommand{ .set_listener_position = .{ .position = position } };
        _ = self.audio_queue.push(command);
    }

    pub fn setListenerOrientation(self: *Self, forward: Vec3, up: Vec3) void {
        self.listener.setOrientation(forward, up);
    }

    pub fn playSource(self: *Self, source: *AudioSource) void {
        const command = AudioCommand{ .play_source = .{ .source_id = source.id } };
        _ = self.audio_queue.push(command);
    }

    pub fn stopSource(self: *Self, source: *AudioSource) void {
        const command = AudioCommand{ .stop_source = .{ .source_id = source.id } };
        _ = self.audio_queue.push(command);
    }

    pub fn getStats(self: *Self) AudioStats {
        return self.stats;
    }

    fn loadBufferFromFile(self: *Self, buffer_id: u32, file_path: []const u8) !void {
        // Create decoder for the file
        const decoder = try AudioDecoder.init(self.allocator, file_path);
        defer decoder.deinit();

        // For now, load a fixed-size buffer (in a real implementation, we'd read the file size)
        const buffer_size = 44100 * 2; // 1 second at 44.1kHz stereo
        const temp_buffer = try self.allocator.alloc(f32, buffer_size);
        defer self.allocator.free(temp_buffer);

        // Decode the audio data
        try decoder.decode(temp_buffer);

        // Create audio buffer
        const audio_buffer = try self.createBuffer(temp_buffer, 44100, 2);

        // Store buffer with the specified ID (in a real implementation, we'd have a proper mapping)
        _ = buffer_id;
        _ = audio_buffer;

        std.log.info("Loaded audio buffer from '{s}'", .{file_path});
    }
};
