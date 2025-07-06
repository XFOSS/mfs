//! Vulkan Material System
//! Handles material properties and shader binding for Vulkan backend

const std = @import("std");

/// Material properties for Vulkan rendering
pub const VulkanMaterial = struct {
    /// Diffuse color (RGBA)
    diffuse_color: [4]f32 = [_]f32{ 1.0, 1.0, 1.0, 1.0 },

    /// Specular color (RGB) and shininess (A)
    specular: [4]f32 = [_]f32{ 0.5, 0.5, 0.5, 32.0 },

    /// Emissive color (RGB) and intensity (A)
    emissive: [4]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0 },

    /// Material flags (metallic, roughness, etc.)
    flags: u32 = 0,

    /// Texture indices (-1 if not used)
    diffuse_texture: i32 = -1,
    normal_texture: i32 = -1,
    specular_texture: i32 = -1,
    emissive_texture: i32 = -1,

    pub fn init() VulkanMaterial {
        return VulkanMaterial{};
    }

    pub fn setDiffuseColor(self: *VulkanMaterial, r: f32, g: f32, b: f32, a: f32) void {
        self.diffuse_color = [_]f32{ r, g, b, a };
    }

    pub fn setSpecular(self: *VulkanMaterial, r: f32, g: f32, b: f32, shininess: f32) void {
        self.specular = [_]f32{ r, g, b, shininess };
    }

    pub fn setEmissive(self: *VulkanMaterial, r: f32, g: f32, b: f32, intensity: f32) void {
        self.emissive = [_]f32{ r, g, b, intensity };
    }
};
