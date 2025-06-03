const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu.zig");
const types = @import("types.zig");
const interface = @import("backends/interface.zig");

/// Errors that can occur when working with textures
pub const TextureError = error{
    CreationFailed,
    InvalidFormat,
    InvalidDimensions,
    OutOfMemory,
    EncodingFailed,
    DecodingFailed,
    UnsupportedOperation,
    TextureNull,
};

/// Defines how a texture can be used in the GPU pipeline
pub const TextureUsage = enum {
    sampled,
    storage,
    render_target,
    depth_stencil,
    transfer_src,
    transfer_dst,
};

/// Filtering methods for texture sampling
pub const TextureFilter = enum {
    nearest,
    linear,
    trilinear,
    anisotropic,
};

/// Defines how texture coordinates outside [0,1] are handled
pub const TextureAddressMode = enum {
    clamp_to_edge,
    repeat,
    mirrored_repeat,
    clamp_to_border,
    mirror_clamp_to_edge,
};

/// Texture comparison modes for shadow mapping and similar techniques
pub const TextureCompareMode = enum {
    none,
    compare_ref_to_texture,
};

/// Configuration for how a texture is sampled
pub const TextureSampler = struct {
    min_filter: TextureFilter = .linear,
    mag_filter: TextureFilter = .linear,
    mip_filter: TextureFilter = .linear,
    address_mode_u: TextureAddressMode = .clamp_to_edge,
    address_mode_v: TextureAddressMode = .clamp_to_edge,
    address_mode_w: TextureAddressMode = .clamp_to_edge,
    anisotropy: f32 = 1.0,
    lod_min_clamp: f32 = 0.0,
    lod_max_clamp: f32 = 1000.0,
    compare_mode: TextureCompareMode = .none,
    compare_func: interface.CompareFunc = .always,
    border_color: [4]f32 = [_]f32{ 0, 0, 0, 0 },
};

/// Represents a 2D texture resource
pub const Texture2D = struct {
    allocator: Allocator,
    texture: ?*gpu.Texture = null,
    width: u32,
    height: u32,
    format: gpu.TextureFormat,
    usage: TextureUsage,
    mip_levels: u32,
    sampler: TextureSampler,
    owns_texture: bool = true,

    const Self = @This();

    /// Initialize a new 2D texture with the specified parameters
    pub fn init(allocator: Allocator, width: u32, height: u32, format: gpu.TextureFormat, usage: TextureUsage) !*Self {
        if (width == 0 or height == 0) return TextureError.InvalidDimensions;

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .width = width,
            .height = height,
            .format = format,
            .usage = usage,
            .mip_levels = 1,
            .sampler = TextureSampler{},
        };
        return self;
    }

    /// Initialize a texture by wrapping an existing GPU texture
    pub fn initFromGpuTexture(allocator: Allocator, texture: *gpu.Texture, usage: TextureUsage) !*Self {
        if (texture == null) return TextureError.TextureNull;

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .texture = texture,
            .width = texture.width,
            .height = texture.height,
            .format = texture.format,
            .usage = usage,
            .mip_levels = texture.mip_levels,
            .sampler = TextureSampler{},
            .owns_texture = false,
        };
        return self;
    }

    /// Initialize an empty texture resource
    pub fn initEmptyTexture(self: *Self) !void {
        if (self.texture != null) {
            if (self.owns_texture) {
                self.texture.?.deinit();
            }
            self.texture = null;
        }

        self.texture = try gpu.createTexture(
            self.width,
            self.height,
            self.format,
            .texture_2d,
            null,
        );
    }

    /// Initialize a texture from RGBA pixel data
    pub fn initFromRgbaPixels(self: *Self, pixels: []const u8) !void {
        if (self.format != .rgba8) {
            return TextureError.InvalidFormat;
        }

        const expected_size = @as(usize, self.width) * @as(usize, self.height) * 4;
        if (pixels.len < expected_size) {
            return TextureError.InvalidDimensions;
        }

        if (self.texture != null) {
            if (self.owns_texture) {
                self.texture.?.deinit();
            }
            self.texture = null;
        }

        self.texture = try gpu.createTexture(
            self.width,
            self.height,
            self.format,
            .texture_2d,
            pixels,
        );
    }

    /// Initialize a texture from RGB pixel data
    pub fn initFromRgbPixels(self: *Self, pixels: []const u8) !void {
        if (self.format != .rgb8) {
            return TextureError.InvalidFormat;
        }

        const expected_size = @as(usize, self.width) * @as(usize, self.height) * 3;
        if (pixels.len < expected_size) {
            return TextureError.InvalidDimensions;
        }

        if (self.texture != null) {
            if (self.owns_texture) {
                self.texture.?.deinit();
            }
            self.texture = null;
        }

        self.texture = try gpu.createTexture(
            self.width,
            self.height,
            self.format,
            .texture_2d,
            pixels,
        );
    }

    /// Load texture data from a file
    pub fn loadFromFile(self: *Self, path: []const u8) !void {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const max_size = 16 * 1024 * 1024; // 16MB limit for texture data
        const data = try file.readToEndAlloc(self.allocator, max_size);
        defer self.allocator.free(data);

        try self.loadFromMemory(data);
    }

    /// Load texture data from memory
    pub fn loadFromMemory(self: *Self, data: []const u8) !void {
        if (data.len < 8) return TextureError.InvalidDimensions;

        // Check file signature for common formats
        if (isPng(data)) {
            try self.loadPng(data);
        } else if (isJpeg(data)) {
            try self.loadJpeg(data);
        } else if (isBmp(data)) {
            try self.loadBmp(data);
        } else if (isGif(data)) {
            try self.loadGif(data);
        } else if (isTga(data)) {
            try self.loadTga(data);
        } else {
            return TextureError.UnsupportedOperation;
        }
    }

    fn isPng(data: []const u8) bool {
        const png_signature = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        return data.len >= png_signature.len and std.mem.eql(u8, data[0..png_signature.len], &png_signature);
    }

    fn isJpeg(data: []const u8) bool {
        return data.len >= 2 and data[0] == 0xFF and data[1] == 0xD8;
    }

    fn isBmp(data: []const u8) bool {
        return data.len >= 2 and data[0] == 0x42 and data[1] == 0x4D;
    }

    fn isGif(data: []const u8) bool {
        return data.len >= 6 and std.mem.eql(u8, data[0..3], "GIF") and
            (std.mem.eql(u8, data[3..6], "87a") or std.mem.eql(u8, data[3..6], "89a"));
    }

    fn isTga(data: []const u8) bool {
        // TGA doesn't have a clear signature, this is a simplified check
        return data.len >= 18;
    }

    fn loadPng(self: *Self, data: []const u8) !void {
        // In a real implementation, this would use a PNG decoder library
        _ = data;
        const decoded_pixels = try self.allocator.alloc(u8, self.width * self.height * 4);
        defer self.allocator.free(decoded_pixels);

        // Placeholder for PNG decoding
        std.mem.set(u8, decoded_pixels, 0xFF); // Set to white

        try self.initFromRgbaPixels(decoded_pixels);
    }

    fn loadJpeg(self: *Self, data: []const u8) !void {
        // In a real implementation, this would use a JPEG decoder library
        _ = data;
        const decoded_pixels = try self.allocator.alloc(u8, self.width * self.height * 4);
        defer self.allocator.free(decoded_pixels);

        // Placeholder for JPEG decoding
        std.mem.set(u8, decoded_pixels, 0xFF); // Set to white

        try self.initFromRgbaPixels(decoded_pixels);
    }

    fn loadBmp(self: *Self, data: []const u8) !void {
        // In a real implementation, this would use a BMP decoder
        _ = data;
        const decoded_pixels = try self.allocator.alloc(u8, self.width * self.height * 4);
        defer self.allocator.free(decoded_pixels);

        // Placeholder for BMP decoding
        std.mem.set(u8, decoded_pixels, 0xFF); // Set to white

        try self.initFromRgbaPixels(decoded_pixels);
    }

    fn loadGif(self: *Self, data: []const u8) !void {
        // In a real implementation, this would use a GIF decoder
        _ = data;
        const decoded_pixels = try self.allocator.alloc(u8, self.width * self.height * 4);
        defer self.allocator.free(decoded_pixels);

        // Placeholder for GIF decoding
        std.mem.set(u8, decoded_pixels, 0xFF); // Set to white

        try self.initFromRgbaPixels(decoded_pixels);
    }

    fn loadTga(self: *Self, data: []const u8) !void {
        // In a real implementation, this would use a TGA decoder
        _ = data;
        const decoded_pixels = try self.allocator.alloc(u8, self.width * self.height * 4);
        defer self.allocator.free(decoded_pixels);

        // Placeholder for TGA decoding
        std.mem.set(u8, decoded_pixels, 0xFF); // Set to white

        try self.initFromRgbaPixels(decoded_pixels);
    }

    /// Clean up texture resources
    pub fn deinit(self: *Self) void {
        if (self.texture != null and self.owns_texture) {
            self.texture.?.deinit();
            self.texture = null;
        }

        self.allocator.destroy(self);
    }

    /// Update a region of the texture with new pixel data
    pub fn updateRegion(self: *Self, cmd: *gpu.CommandBuffer, x: u32, y: u32, width: u32, height: u32, pixels: []const u8) !void {
        if (self.texture == null) return TextureError.TextureNull;
        if (x + width > self.width or y + height > self.height) return TextureError.InvalidDimensions;
        _ = cmd; // Command buffer may be used in future implementations

        const region = interface.TextureCopyRegion{
            .src_offset = .{ .x = 0, .y = 0, .z = 0 },
            .dst_offset = .{ .x = x, .y = y, .z = 0 },
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .src_mip_level = 0,
            .dst_mip_level = 0,
            .src_array_slice = 0,
            .dst_array_slice = 0,
            .array_layer_count = 1,
        };

        try gpu.updateTexture(self.texture.?, &region, pixels);
    }

    /// Generate mipmaps for the texture
    pub fn generateMipmaps(self: *Self, cmd: *gpu.CommandBuffer) !void {
        if (self.texture == null) return TextureError.TextureNull;
        if (self.mip_levels <= 1) return;

        // Try to use hardware mipmap generation if available
        if (gpu.supportsHardwareMipmapGeneration()) {
            try gpu.generateMipmaps(cmd, self.texture.?);
            return;
        }

        // Fallback: Simplified mipmap generation using software scaling
        var src_width = self.width;
        var src_height = self.height;

        for (1..self.mip_levels) |level| {
            const dst_width = std.math.max(1, src_width / 2);
            const dst_height = std.math.max(1, src_height / 2);

            // Set up region for copying with scaling
            const region = interface.TextureCopyRegion{
                .src_offset = .{ .x = 0, .y = 0, .z = 0 },
                .dst_offset = .{ .x = 0, .y = 0, .z = 0 },
                .extent = .{ .width = dst_width, .height = dst_height, .depth = 1 },
                .src_mip_level = level - 1,
                .dst_mip_level = @intCast(level),
                .src_array_slice = 0,
                .dst_array_slice = 0,
                .array_layer_count = 1,
            };

            // In a real implementation, we would set up a shader to perform proper filtering
            try gpu.copyTexture(cmd, self.texture.?, self.texture.?, &region);

            src_width = dst_width;
            src_height = dst_height;
        }
    }
};

/// Represents a texture that can be used as a render target
pub const RenderTexture = struct {
    allocator: Allocator,
    texture: *Texture2D,
    render_target: *gpu.RenderTarget,
    width: u32,
    height: u32,
    has_depth: bool,

    const Self = @This();

    /// Initialize a new render texture
    pub fn init(allocator: Allocator, width: u32, height: u32, format: gpu.TextureFormat) !*Self {
        if (width == 0 or height == 0) return TextureError.InvalidDimensions;

        var texture = try Texture2D.init(allocator, width, height, format, .render_target);
        errdefer texture.deinit();

        try texture.initEmptyTexture();

        var render_target = try gpu.createRenderTarget(width, height);
        errdefer render_target.deinit();

        // Attach the texture
        render_target.color_texture = texture.texture;

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .texture = texture,
            .render_target = render_target,
            .width = width,
            .height = height,
            .has_depth = false,
        };

        return self;
    }

    /// Initialize a render texture with a depth buffer
    pub fn initWithDepth(allocator: Allocator, width: u32, height: u32, color_format: gpu.TextureFormat, depth_format: gpu.TextureFormat) !*Self {
        var self = try Self.init(allocator, width, height, color_format);
        errdefer self.deinit();

        // Create depth texture
        const depth_texture = try gpu.createTexture(width, height, depth_format, .texture_2d, null);
        self.render_target.depth_texture = depth_texture;
        self.has_depth = true;

        return self;
    }

    /// Clean up render texture resources
    pub fn deinit(self: *Self) void {
        self.texture.deinit();
        self.render_target.deinit();
        self.allocator.destroy(self);
    }

    /// Begin rendering to this texture
    pub fn begin(self: *const Self, cmd: *gpu.CommandBuffer, clear_color: ?gpu.ClearColor, clear_depth: ?f32) !void {
        const options = gpu.RenderPassOptions{
            .color_targets = &[_]*gpu.Texture{self.texture.texture.?},
            .depth_target = self.render_target.depth_texture,
            .clear_color = clear_color,
            .clear_depth = clear_depth,
            .clear_stencil = null,
        };

        try gpu.beginRenderPass(cmd, options);

        // Set default viewport and scissor to match the render texture size
        const viewport = gpu.Viewport{
            .x = 0,
            .y = 0,
            .width = self.width,
            .height = self.height,
        };

        try gpu.setViewport(cmd, &viewport);
        try gpu.setScissor(cmd, &viewport);
    }

    /// End rendering to this texture
    pub fn end(self: *const Self, cmd: *gpu.CommandBuffer) !void {
        _ = self;
        try gpu.endRenderPass(cmd);
    }

    /// Resize the render texture
    pub fn resize(self: *Self, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return TextureError.InvalidDimensions;
        if (width == self.width and height == self.height) return;

        // Create new texture with new dimensions
        var new_texture = try Texture2D.init(self.allocator, width, height, self.texture.format, .render_target);
        try new_texture.initEmptyTexture();

        // Create new render target
        var new_render_target = try gpu.createRenderTarget(width, height);
        new_render_target.color_texture = new_texture.texture;

        // Create new depth texture if needed
        if (self.has_depth) {
            const depth_format = self.render_target.depth_texture.?.format;
            const new_depth = try gpu.createTexture(width, height, depth_format, .texture_2d, null);
            new_render_target.depth_texture = new_depth;
        }

        // Clean up old resources
        self.texture.deinit();
        self.render_target.deinit();

        // Update self
        self.texture = new_texture;
        self.render_target = new_render_target;
        self.width = width;
        self.height = height;
    }
};

/// Represents an array of textures with the same dimensions and format
pub const TextureArray = struct {
    allocator: Allocator,
    texture: ?*gpu.Texture = null,
    width: u32,
    height: u32,
    layers: u32,
    format: gpu.TextureFormat,
    mip_levels: u32,

    const Self = @This();

    /// Initialize a new texture array
    pub fn init(allocator: Allocator, width: u32, height: u32, layers: u32, format: gpu.TextureFormat) !*Self {
        if (width == 0 or height == 0 or layers == 0) return TextureError.InvalidDimensions;

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .width = width,
            .height = height,
            .layers = layers,
            .format = format,
            .mip_levels = 1,
        };
        return self;
    }

    /// Initialize an empty texture array
    pub fn initEmptyTexture(self: *Self) !void {
        if (self.texture != null) {
            self.texture.?.deinit();
            self.texture = null;
        }

        self.texture = try gpu.createTexture(
            self.width,
            self.height,
            self.format,
            .texture_array,
            null,
        );
    }

    /// Clean up texture array resources
    pub fn deinit(self: *Self) void {
        if (self.texture != null) {
            self.texture.?.deinit();
            self.texture = null;
        }

        self.allocator.destroy(self);
    }

    /// Set pixel data for a specific layer in the texture array
    pub fn setLayerFromPixels(self: *const Self, layer: u32, pixels: []const u8) !void {
        if (self.texture == null) return TextureError.TextureNull;
        if (layer >= self.layers) return TextureError.InvalidDimensions;

        const bytes_per_pixel = switch (self.format) {
            .rgba8 => 4,
            .rgb8 => 3,
            .r8 => 1,
            .rg8 => 2,
            else => return TextureError.InvalidFormat,
        };

        const expected_size = @as(usize, self.width) * @as(usize, self.height) * bytes_per_pixel;
        if (pixels.len < expected_size) {
            return TextureError.InvalidDimensions;
        }

        const region = interface.TextureCopyRegion{
            .src_offset = .{ .x = 0, .y = 0, .z = 0 },
            .dst_offset = .{ .x = 0, .y = 0, .z = 0 },
            .extent = .{ .width = self.width, .height = self.height, .depth = 1 },
            .src_mip_level = 0,
            .dst_mip_level = 0,
            .src_array_slice = 0,
            .dst_array_slice = layer,
            .array_layer_count = 1,
        };

        try gpu.updateTexture(self.texture.?, &region, pixels);
    }
};
