const std = @import("std");
const Vec3 = @import("../../math/vec3.zig").Vec3f;
const Vec4 = @import("../../math/vec4.zig").Vec4f;
const Mat4 = @import("../../math/mat4.zig").Mat4f;

pub const LightType = enum {
    Directional,
    Point,
    Spot,
    Area,
};

pub const LightComponent = struct {
    light_type: LightType,
    color: Vec4,
    intensity: f32,
    range: f32,
    spot_angle: f32,
    spot_blend: f32,
    cast_shadows: bool,
    shadow_bias: f32,
    shadow_softness: f32,
    shadow_map_size: u32,
    enabled: bool,
    dirty: bool,

    // Directional light specific
    direction: Vec3,
    cascade_levels: u32,
    cascade_splits: [4]f32,

    // Area light specific
    width: f32,
    height: f32,

    pub fn init(light_type: LightType) LightComponent {
        return LightComponent{
            .light_type = light_type,
            .color = Vec4.init(1, 1, 1, 1),
            .intensity = 1.0,
            .range = 10.0,
            .spot_angle = 45.0,
            .spot_blend = 0.1,
            .cast_shadows = false,
            .shadow_bias = 0.005,
            .shadow_softness = 1.0,
            .shadow_map_size = 1024,
            .enabled = true,
            .dirty = true,
            .direction = Vec3.init(0, -1, 0),
            .cascade_levels = 4,
            .cascade_splits = [4]f32{ 0.1, 0.3, 0.6, 1.0 },
            .width = 1.0,
            .height = 1.0,
        };
    }

    pub fn setType(self: *LightComponent, light_type: LightType) void {
        self.light_type = light_type;
        self.dirty = true;
    }

    pub fn setColor(self: *LightComponent, color: Vec4) void {
        self.color = color;
        self.dirty = true;
    }

    pub fn setIntensity(self: *LightComponent, intensity: f32) void {
        self.intensity = intensity;
        self.dirty = true;
    }

    pub fn setRange(self: *LightComponent, range: f32) void {
        self.range = range;
        self.dirty = true;
    }

    pub fn setSpotAngle(self: *LightComponent, angle: f32) void {
        self.spot_angle = angle;
        self.dirty = true;
    }

    pub fn setSpotBlend(self: *LightComponent, blend: f32) void {
        self.spot_blend = blend;
        self.dirty = true;
    }

    pub fn setCastShadows(self: *LightComponent, cast_shadows: bool) void {
        self.cast_shadows = cast_shadows;
        self.dirty = true;
    }

    pub fn setShadowBias(self: *LightComponent, bias: f32) void {
        self.shadow_bias = bias;
        self.dirty = true;
    }

    pub fn setShadowSoftness(self: *LightComponent, softness: f32) void {
        self.shadow_softness = softness;
        self.dirty = true;
    }

    pub fn setShadowMapSize(self: *LightComponent, size: u32) void {
        self.shadow_map_size = size;
        self.dirty = true;
    }

    pub fn setDirection(self: *LightComponent, direction: Vec3) void {
        self.direction = direction.normalize();
        self.dirty = true;
    }

    pub fn setCascadeLevels(self: *LightComponent, levels: u32) void {
        self.cascade_levels = levels;
        self.dirty = true;
    }

    pub fn setCascadeSplits(self: *LightComponent, splits: []const f32) void {
        std.mem.copy(f32, &self.cascade_splits, splits);
        self.dirty = true;
    }

    pub fn setAreaSize(self: *LightComponent, width: f32, height: f32) void {
        self.width = width;
        self.height = height;
        self.dirty = true;
    }

    pub fn getViewProjectionMatrix(self: *const LightComponent, position: Vec3, level: u32) Mat4 {
        switch (self.light_type) {
            .Directional => {
                const view = Mat4.lookAt(position, position.add(self.direction), Vec3.init(0, 1, 0));

                const cascade_far = self.cascade_splits[level];
                const cascade_near = if (level > 0) self.cascade_splits[level - 1] else 0.1;

                // Calculate orthographic projection for the cascade level
                const projection = Mat4.orthographic(-self.range, self.range, -self.range, self.range, cascade_near, cascade_far);

                return projection.mul(view);
            },
            .Point => {
                const view = Mat4.lookAt(position, position.add(self.direction), Vec3.init(0, 1, 0));

                const projection = Mat4.perspective(90.0, 1.0, 0.1, self.range);

                return projection.mul(view);
            },
            .Spot => {
                const view = Mat4.lookAt(position, position.add(self.direction), Vec3.init(0, 1, 0));

                const projection = Mat4.perspective(self.spot_angle * 2.0, 1.0, 0.1, self.range);

                return projection.mul(view);
            },
            .Area => {
                const view = Mat4.lookAt(position, position.add(self.direction), Vec3.init(0, 1, 0));

                const projection = Mat4.orthographic(-self.width * 0.5, self.width * 0.5, -self.height * 0.5, self.height * 0.5, 0.1, self.range);

                return projection.mul(view);
            },
        }
    }
};
