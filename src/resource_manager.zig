//! Asset-level Resource Manager (textures, models, sounds …)
//! --------------------------------------------------------
//! This sits one level above the GPU-only resource managers found in
//! `graphics/resource_manager.zig`.  It handles:
//!   • Loading assets from disk (blocking for now, async later)
//!   • Reference-counted caching so the same file isn't decoded twice
//!   • Generic handles that point to the underlying subsystem (GPU texture,
//!     audio buffer, etc.)
//!   • Hot-reload stubs (file-watcher will plug in down the road).
//!
//! It is deliberately simple for the first cut – enough for the engine and
//! tests to start sharing textures and meshes.

const std = @import("std");
const gfx = @import("graphics/mod.zig");
const audio = @import("audio/mod.zig");

const Allocator = std.mem.Allocator;

pub const ResourceManager = struct {
    allocator: Allocator,

    // Maps absolute / canonicalised path → resource record
    textures: std.StringHashMap(*gfx.Texture),
    models: std.StringHashMap(*Model),
    sounds: std.StringHashMap(*audio.AudioBuffer),

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        var mgr = try allocator.create(Self);
        mgr.* = .{
            .allocator = allocator,
            .textures = std.StringHashMap(*gfx.Texture).init(allocator),
            .models = std.StringHashMap(*Model).init(allocator),
            .sounds = std.StringHashMap(*audio.AudioBuffer).init(allocator),
        };
        return mgr;
    }

    pub fn deinit(self: *Self) void {
        // NOTE: We don't destroy the underlying GPU/audio resources here –
        // ownership is shared with their respective subsystems and will be
        // cleaned up when their ref-count drops to zero.  For the prototype we
        // simply clear the hash-maps.
        self.textures.deinit();
        self.models.deinit();
        self.sounds.deinit();
        self.allocator.destroy(self);
    }

    // ---------------------------------------------------------------------
    // Texture API
    // ---------------------------------------------------------------------

    pub fn loadTexture(self: *Self, path: []const u8, gfx_sys: *gfx.GraphicsSystem) !*gfx.Texture {
        if (self.textures.get(path)) |tex| return tex;

        // Simplified loader: only supports PNG via std.image for now.
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const img = try std.image.PNG.read(self.allocator, file.reader(), .{});
        defer img.deinit();

        const tex_desc = gfx.TextureDesc{
            .width = img.width,
            .height = img.height,
            .format = .rgba8_unorm,
            .usage = .{ .shader_resource = true },
        };

        var texture = try gfx_sys.createTexture(tex_desc);
        // For the prototype we ignore upload; software backend doesn't render.
        _ = texture;

        try self.textures.put(path, texture);
        return texture;
    }

    // ---------------------------------------------------------------------
    // Sound API
    // ---------------------------------------------------------------------

    pub fn loadSound(self: *Self, path: []const u8, audio_sys: *audio.AudioSystem) !*audio.AudioBuffer {
        if (self.sounds.get(path)) |buf| return buf;

        // audio.AudioDecoder can infer format from extension.
        const buf = try audio_sys.load(path);
        try self.sounds.put(path, buf);
        return buf;
    }

    // ---------------------------------------------------------------------
    // Model API – placeholder
    // ---------------------------------------------------------------------
    pub const Model = struct { vertices: []f32, indices: []u32 };

    pub fn loadModel(self: *Self, path: []const u8) !*Model {
        if (self.models.get(path)) |m| return m;
        // TODO: real model decoding (GLTF etc.)
        const model = try self.allocator.create(Model);
        model.* = .{ .vertices = &[_]f32{}, .indices = &[_]u32{} };
        try self.models.put(path, model);
        return model;
    }
};

/// Global singleton (optional – convenient for quick prototypes)
var g_res_mgr: ?*ResourceManager = null;

pub fn get() !*ResourceManager {
    return g_res_mgr orelse error.ResourceManagerNotInitialised;
}

pub fn initGlobal(alloc: Allocator) !void {
    if (g_res_mgr == null) {
        g_res_mgr = try ResourceManager.init(alloc);
    }
}

pub fn deinitGlobal() void {
    if (g_res_mgr) |mgr| {
        mgr.deinit();
        g_res_mgr = null;
    }
}