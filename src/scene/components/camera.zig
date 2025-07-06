const std = @import("std");
// const math = @import("math");
// Temporary placeholder types
const Vec3 = struct { x: f32, y: f32, z: f32 };
const Vec4 = struct { x: f32, y: f32, z: f32, w: f32 };
const Mat4 = struct { data: [16]f32 };

pub const ProjectionType = enum {
    Perspective,
    Orthographic,
};

pub const CameraComponent = struct {
    projection_type: ProjectionType,
    fov: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32,
    orthographic_size: f32,
    viewport: Vec4,
    clear_color: Vec4,
    clear_depth: f32,
    clear_stencil: i32,
    clear_flags: u32,
    enabled: bool,
    dirty: bool,

    // View matrix cache
    view_matrix: Mat4,
    projection_matrix: Mat4,
    view_projection_matrix: Mat4,

    pub const ClearFlags = struct {
        pub const None: u32 = 0;
        pub const Color: u32 = 1 << 0;
        pub const Depth: u32 = 1 << 1;
        pub const Stencil: u32 = 1 << 2;
        pub const All: u32 = Color | Depth | Stencil;
    };

    pub fn init() CameraComponent {
        return CameraComponent{
            .projection_type = .Perspective,
            .fov = 60.0,
            .aspect_ratio = 16.0 / 9.0,
            .near_plane = 0.1,
            .far_plane = 1000.0,
            .orthographic_size = 5.0,
            .viewport = Vec4.init(0, 0, 1, 1),
            .clear_color = Vec4.init(0.1, 0.1, 0.1, 1),
            .clear_depth = 1.0,
            .clear_stencil = 0,
            .clear_flags = ClearFlags.All,
            .enabled = true,
            .dirty = true,
            .view_matrix = Mat4.identity(),
            .projection_matrix = Mat4.identity(),
            .view_projection_matrix = Mat4.identity(),
        };
    }

    pub fn setProjectionType(self: *CameraComponent, projection_type: ProjectionType) void {
        self.projection_type = projection_type;
        self.dirty = true;
    }

    pub fn setFOV(self: *CameraComponent, fov: f32) void {
        self.fov = fov;
        self.dirty = true;
    }

    pub fn setAspectRatio(self: *CameraComponent, aspect_ratio: f32) void {
        self.aspect_ratio = aspect_ratio;
        self.dirty = true;
    }

    pub fn setNearPlane(self: *CameraComponent, near_plane: f32) void {
        self.near_plane = near_plane;
        self.dirty = true;
    }

    pub fn setFarPlane(self: *CameraComponent, far_plane: f32) void {
        self.far_plane = far_plane;
        self.dirty = true;
    }

    pub fn setOrthographicSize(self: *CameraComponent, size: f32) void {
        self.orthographic_size = size;
        self.dirty = true;
    }

    pub fn setViewport(self: *CameraComponent, viewport: Vec4) void {
        self.viewport = viewport;
        self.dirty = true;
    }

    pub fn setClearColor(self: *CameraComponent, color: Vec4) void {
        self.clear_color = color;
    }

    pub fn setClearDepth(self: *CameraComponent, depth: f32) void {
        self.clear_depth = depth;
    }

    pub fn setClearStencil(self: *CameraComponent, stencil: i32) void {
        self.clear_stencil = stencil;
    }

    pub fn setClearFlags(self: *CameraComponent, flags: u32) void {
        self.clear_flags = flags;
    }

    pub fn updateMatrices(self: *CameraComponent, position: Vec3, rotation: Vec3) void {
        if (!self.dirty) return;

        // Update view matrix
        const forward = Vec3.init(@cos(rotation.y) * @cos(rotation.x), @sin(rotation.x), @sin(rotation.y) * @cos(rotation.x)).normalize();

        const right = Vec3.init(0, 1, 0).cross(forward).normalize();
        const up = forward.cross(right);

        self.view_matrix = Mat4.lookAt(position, position.add(forward), up);

        // Update projection matrix
        switch (self.projection_type) {
            .Perspective => {
                self.projection_matrix = Mat4.perspective(self.fov, self.aspect_ratio, self.near_plane, self.far_plane);
            },
            .Orthographic => {
                const half_size = self.orthographic_size * 0.5;
                const half_width = half_size * self.aspect_ratio;
                self.projection_matrix = Mat4.orthographic(-half_width, half_width, -half_size, half_size, self.near_plane, self.far_plane);
            },
        }

        // Update view-projection matrix
        self.view_projection_matrix = self.projection_matrix.mul(self.view_matrix);
        self.dirty = false;
    }

    pub fn getViewMatrix(self: *const CameraComponent) Mat4 {
        return self.view_matrix;
    }

    pub fn getProjectionMatrix(self: *const CameraComponent) Mat4 {
        return self.projection_matrix;
    }

    pub fn getViewProjectionMatrix(self: *const CameraComponent) Mat4 {
        return self.view_projection_matrix;
    }

    pub fn screenToWorldPoint(self: *const CameraComponent, screen_point: Vec3) Vec3 {
        const clip_space = Vec4.init((screen_point.x * 2.0 - 1.0) * self.viewport.z + self.viewport.x, (1.0 - screen_point.y * 2.0) * self.viewport.w + self.viewport.y, screen_point.z, 1.0);

        const view_projection_inv = self.view_projection_matrix.inverse();
        const world_space = view_projection_inv.transformPoint(clip_space);
        return world_space.scale(1.0 / world_space.w);
    }

    pub fn worldToScreenPoint(self: *const CameraComponent, world_point: Vec3) Vec3 {
        const clip_space = self.view_projection_matrix.transformPoint(world_point);
        const ndc_space = clip_space.scale(1.0 / clip_space.w);

        return Vec3.init((ndc_space.x - self.viewport.x) / self.viewport.z * 0.5 + 0.5, (ndc_space.y - self.viewport.y) / self.viewport.w * 0.5 + 0.5, ndc_space.z);
    }

    pub fn getFrustumCorners(self: *const CameraComponent) [8]Vec3 {
        var corners: [8]Vec3 = undefined;

        switch (self.projection_type) {
            .Perspective => {
                const tan_half_fov = @tan(self.fov * 0.5 * std.math.pi / 180.0);
                const near_height = 2.0 * tan_half_fov * self.near_plane;
                const near_width = near_height * self.aspect_ratio;
                const far_height = 2.0 * tan_half_fov * self.far_plane;
                const far_width = far_height * self.aspect_ratio;

                // Near plane corners
                corners[0] = Vec3.init(-near_width * 0.5, -near_height * 0.5, -self.near_plane);
                corners[1] = Vec3.init(near_width * 0.5, -near_height * 0.5, -self.near_plane);
                corners[2] = Vec3.init(near_width * 0.5, near_height * 0.5, -self.near_plane);
                corners[3] = Vec3.init(-near_width * 0.5, near_height * 0.5, -self.near_plane);

                // Far plane corners
                corners[4] = Vec3.init(-far_width * 0.5, -far_height * 0.5, -self.far_plane);
                corners[5] = Vec3.init(far_width * 0.5, -far_height * 0.5, -self.far_plane);
                corners[6] = Vec3.init(far_width * 0.5, far_height * 0.5, -self.far_plane);
                corners[7] = Vec3.init(-far_width * 0.5, far_height * 0.5, -self.far_plane);
            },
            .Orthographic => {
                const half_size = self.orthographic_size * 0.5;
                const half_width = half_size * self.aspect_ratio;

                // Near plane corners
                corners[0] = Vec3.init(-half_width, -half_size, -self.near_plane);
                corners[1] = Vec3.init(half_width, -half_size, -self.near_plane);
                corners[2] = Vec3.init(half_width, half_size, -self.near_plane);
                corners[3] = Vec3.init(-half_width, half_size, -self.near_plane);

                // Far plane corners
                corners[4] = Vec3.init(-half_width, -half_size, -self.far_plane);
                corners[5] = Vec3.init(half_width, -half_size, -self.far_plane);
                corners[6] = Vec3.init(half_width, half_size, -self.far_plane);
                corners[7] = Vec3.init(-half_width, half_size, -self.far_plane);
            },
        }

        // Transform corners to world space
        const view_inv = self.view_matrix.inverse();
        for (&corners) |*corner| {
            corner.* = view_inv.transformPoint(corner.*);
        }

        return corners;
    }
};
