const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Entity = @import("../core/entity.zig").Entity;
const Scene = @import("../core/scene.zig").Scene;
const TransformComponent = @import("../components/transform.zig").TransformComponent;
const RenderComponent = @import("../components/render.zig").RenderComponent;
const CameraComponent = @import("../components/camera.zig").CameraComponent;
const LightComponent = @import("../components/light.zig").LightComponent;
const Vec3 = @import("../../math/vec3.zig").Vec3f;
const Vec4 = @import("../../math/vec4.zig").Vec4f;
const Mat4 = @import("../../math/mat4.zig").Mat4f;

pub const RenderQueue = struct {
    opaque: ArrayList(Entity),
    transparent: ArrayList(Entity),
    ui: ArrayList(Entity),

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .opaque = ArrayList(Entity).init(allocator),
            .transparent = ArrayList(Entity).init(allocator),
            .ui = ArrayList(Entity).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.opaque.deinit();
        self.transparent.deinit();
        self.ui.deinit();
    }

    pub fn clear(self: *@This()) void {
        self.opaque.clearRetainingCapacity();
        self.transparent.clearRetainingCapacity();
        self.ui.clearRetainingCapacity();
    }
};

pub const RenderSystem = struct {
    allocator: Allocator,
    scene: *Scene,
    active_camera: ?Entity,
    render_queue: RenderQueue,
    viewport: Vec4,
    clear_color: Vec4,
    clear_depth: f32,
    clear_stencil: i32,
    clear_flags: u32,
    enabled: bool,

    pub fn init(allocator: Allocator, scene: *Scene) !RenderSystem {
        return RenderSystem{
            .allocator = allocator,
            .scene = scene,
            .active_camera = null,
            .render_queue = RenderQueue.init(allocator),
            .viewport = Vec4.init(0, 0, 1, 1),
            .clear_color = Vec4.init(0.1, 0.1, 0.1, 1),
            .clear_depth = 1.0,
            .clear_stencil = 0,
            .clear_flags = CameraComponent.ClearFlags.All,
            .enabled = true,
        };
    }

    pub fn deinit(self: *RenderSystem) void {
        self.render_queue.deinit();
    }

    pub fn update(self: *RenderSystem, _: f32) !void {
        if (!self.enabled) return;

        // Find active camera if not set
        if (self.active_camera == null) {
            var it = self.scene.iterator(.{ .camera = true });
            while (it.next()) |entity| {
                const camera = self.scene.getComponent(entity, CameraComponent) orelse continue;
                if (camera.enabled) {
                    self.active_camera = entity;
                    break;
                }
            }
        }

        // Clear render queue
        self.render_queue.clear();

        // Get active camera
        const camera = if (self.active_camera) |entity|
            self.scene.getComponent(entity, CameraComponent) orelse return
        else
            return;

        // Get camera transform
        const camera_transform = if (self.active_camera) |entity|
            self.scene.getComponent(entity, TransformComponent) orelse return
        else
            return;

        // Update camera matrices
        camera.updateMatrices(camera_transform.position, camera_transform.rotation);

        // Find all renderable entities
        var it = self.scene.iterator(.{ .render = true, .transform = true });
        while (it.next()) |entity| {
            const render = self.scene.getComponent(entity, RenderComponent) orelse continue;
            const transform = self.scene.getComponent(entity, TransformComponent) orelse continue;

            // Skip if not visible
            if (!render.visible) continue;

            // Update world bounds
            render.updateWorldBounds(transform.getWorldMatrix());

            // Cull against camera frustum
            if (!self.isVisible(render.world_bounds, camera)) continue;

            // Add to appropriate render queue
            if (render.material.diffuse_color.w < 1.0) {
                try self.render_queue.transparent.append(entity);
            } else {
                try self.render_queue.opaque.append(entity);
            }
        }

        // Sort render queues
        self.sortRenderQueues(camera_transform.position);

        // Render scene
        try self.renderScene(camera);
    }

    fn isVisible(self: *RenderSystem, bounds: RenderComponent.BoundingBox, camera: *CameraComponent) bool {
        // TODO: Implement frustum culling
        _ = self;
        _ = bounds;
        _ = camera;
        return true;
    }

    fn sortRenderQueues(self: *RenderSystem, camera_position: Vec3) void {
        // Sort opaque queue by material
        std.sort.insertion(Entity, self.render_queue.opaque.items, self, opaqueCompare);

        // Sort transparent queue by distance to camera
        std.sort.insertion(Entity, self.render_queue.transparent.items, self, transparentCompare);
        _ = camera_position;
    }

    fn opaqueCompare(self: *RenderSystem, a: Entity, b: Entity) bool {
        const render_a = self.scene.getComponent(a, RenderComponent) orelse return false;
        const render_b = self.scene.getComponent(b, RenderComponent) orelse return false;

        // Sort by material
        if (render_a.material.texture_diffuse) |tex_a| {
            if (render_b.material.texture_diffuse) |tex_b| {
                return std.mem.order(u8, tex_a, tex_b) == .lt;
            }
            return false;
        }
        if (render_b.material.texture_diffuse != null) return true;

        // Sort by shader
        // TODO: Implement shader sorting
        return false;
    }

    fn transparentCompare(self: *RenderSystem, a: Entity, b: Entity) bool {
        const render_a = self.scene.getComponent(a, RenderComponent) orelse return false;
        const render_b = self.scene.getComponent(b, RenderComponent) orelse return false;
        const transform_a = self.scene.getComponent(a, TransformComponent) orelse return false;
        const transform_b = self.scene.getComponent(b, TransformComponent) orelse return false;

        // Sort by distance to camera
        const camera = if (self.active_camera) |entity|
            self.scene.getComponent(entity, TransformComponent) orelse return false
        else
            return false;

        const dist_a = transform_a.position.sub(camera.position).lengthSquared();
        const dist_b = transform_b.position.sub(camera.position).lengthSquared();

        return dist_a > dist_b;
    }

    fn renderScene(self: *RenderSystem, camera: *CameraComponent) !void {
        // Set viewport
        // TODO: Set viewport

        // Clear buffers
        if (camera.clear_flags & CameraComponent.ClearFlags.Color != 0) {
            // TODO: Clear color buffer
            _ = camera.clear_color;
        }
        if (camera.clear_flags & CameraComponent.ClearFlags.Depth != 0) {
            // TODO: Clear depth buffer
            _ = camera.clear_depth;
        }
        if (camera.clear_flags & CameraComponent.ClearFlags.Stencil != 0) {
            // TODO: Clear stencil buffer
            _ = camera.clear_stencil;
        }

        // Render opaque objects
        for (self.render_queue.opaque.items) |entity| {
            try self.renderEntity(entity, camera);
        }

        // Render transparent objects
        for (self.render_queue.transparent.items) |entity| {
            try self.renderEntity(entity, camera);
        }

        // Render UI
        for (self.render_queue.ui.items) |entity| {
            try self.renderEntity(entity, camera);
        }
    }

    fn renderEntity(self: *RenderSystem, entity: Entity, camera: *CameraComponent) !void {
        const render = self.scene.getComponent(entity, RenderComponent) orelse return;
        const transform = self.scene.getComponent(entity, TransformComponent) orelse return;

        // Skip if no mesh
        const mesh = render.mesh orelse return;

        // Get world matrix
        const world_matrix = transform.getWorldMatrix();

        // Get view-projection matrix
        const view_projection = camera.getViewProjectionMatrix();

        // TODO: Set shader uniforms
        _ = world_matrix;
        _ = view_projection;
        _ = render.material;
        _ = mesh;

        // TODO: Draw mesh
    }

    pub fn setViewport(self: *RenderSystem, viewport: Vec4) void {
        self.viewport = viewport;
    }

    pub fn setClearColor(self: *RenderSystem, color: Vec4) void {
        self.clear_color = color;
    }

    pub fn setClearDepth(self: *RenderSystem, depth: f32) void {
        self.clear_depth = depth;
    }

    pub fn setClearStencil(self: *RenderSystem, stencil: i32) void {
        self.clear_stencil = stencil;
    }

    pub fn setClearFlags(self: *RenderSystem, flags: u32) void {
        self.clear_flags = flags;
    }

    pub fn setEnabled(self: *RenderSystem, enabled: bool) void {
        self.enabled = enabled;
    }

    pub fn setActiveCamera(self: *RenderSystem, entity: Entity) !void {
        const camera = self.scene.getComponent(entity, CameraComponent) orelse return;
        if (camera.enabled) {
            self.active_camera = entity;
        }
    }

    pub fn getActiveCamera(self: *RenderSystem) ?Entity {
        return self.active_camera;
    }

    pub fn getRenderQueue(self: *RenderSystem) *RenderQueue {
        return &self.render_queue;
    }
}; 