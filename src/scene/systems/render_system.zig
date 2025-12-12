const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const Entity = @import("../core/entity.zig").Entity;
const Scene = @import("../core/scene.zig").Scene;
const TransformComponent = @import("../components/transform.zig").Transform;
const System = @import("../core/scene.zig").System;
const RenderComponent = @import("../components/render.zig").RenderComponent;
const CameraComponent = @import("../components/camera.zig").CameraComponent;
const LightComponent = @import("../components/light.zig").LightComponent;
const Vec3 = math.Vec3;
const math = @import("math");
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

pub const RenderQueue = struct {
    opaque_queue: ArrayList(Entity),
    transparent: ArrayList(Entity),
    ui: ArrayList(Entity),

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .opaque_queue = ArrayList(Entity).init(allocator),
            .transparent = ArrayList(Entity).init(allocator),
            .ui = ArrayList(Entity).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.opaque_queue.deinit();
        self.transparent.deinit();
        self.ui.deinit();
    }

    pub fn clear(self: *@This()) void {
        self.opaque_queue.clearRetainingCapacity();
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
                try self.render_queue.opaque_queue.append(entity);
            }
        }

        // Sort render queues
        self.sortRenderQueues(camera_transform.position);

        // Render scene
        try self.renderScene(camera);
    }

    fn isVisible(self: *RenderSystem, bounds: RenderComponent.BoundingBox, camera: *CameraComponent) bool {
        _ = self;

        // Basic frustum culling implementation
        // Get camera view matrix and projection matrix
        const view_matrix = camera.view_matrix;
        const proj_matrix = camera.projection_matrix;

        // Create frustum planes from view-projection matrix
        const view_proj = proj_matrix.mul(view_matrix);

        // Extract frustum planes (left, right, bottom, top, near, far)
        const planes = [_]Vec4{
            // Left plane: row4 + row1
            Vec4.init(view_proj.m[3][0] + view_proj.m[0][0], view_proj.m[3][1] + view_proj.m[0][1], view_proj.m[3][2] + view_proj.m[0][2], view_proj.m[3][3] + view_proj.m[0][3]),
            // Right plane: row4 - row1
            Vec4.init(view_proj.m[3][0] - view_proj.m[0][0], view_proj.m[3][1] - view_proj.m[0][1], view_proj.m[3][2] - view_proj.m[0][2], view_proj.m[3][3] - view_proj.m[0][3]),
            // Bottom plane: row4 + row2
            Vec4.init(view_proj.m[3][0] + view_proj.m[1][0], view_proj.m[3][1] + view_proj.m[1][1], view_proj.m[3][2] + view_proj.m[1][2], view_proj.m[3][3] + view_proj.m[1][3]),
            // Top plane: row4 - row2
            Vec4.init(view_proj.m[3][0] - view_proj.m[1][0], view_proj.m[3][1] - view_proj.m[1][1], view_proj.m[3][2] - view_proj.m[1][2], view_proj.m[3][3] - view_proj.m[1][3]),
            // Near plane: row4 + row3
            Vec4.init(view_proj.m[3][0] + view_proj.m[2][0], view_proj.m[3][1] + view_proj.m[2][1], view_proj.m[3][2] + view_proj.m[2][2], view_proj.m[3][3] + view_proj.m[2][3]),
            // Far plane: row4 - row3
            Vec4.init(view_proj.m[3][0] - view_proj.m[2][0], view_proj.m[3][1] - view_proj.m[2][1], view_proj.m[3][2] - view_proj.m[2][2], view_proj.m[3][3] - view_proj.m[2][3]),
        };

        // Test bounding box against each frustum plane
        for (planes) |plane| {
            // Get the positive vertex (farthest from plane)
            const positive_vertex = Vec3.init(if (plane.x >= 0) bounds.max.x else bounds.min.x, if (plane.y >= 0) bounds.max.y else bounds.min.y, if (plane.z >= 0) bounds.max.z else bounds.min.z);

            // Test if positive vertex is outside the plane
            const distance = plane.x * positive_vertex.x + plane.y * positive_vertex.y + plane.z * positive_vertex.z + plane.w;
            if (distance < 0) {
                return false; // Outside frustum
            }
        }

        return true; // Inside or intersecting frustum
    }

    fn sortRenderQueues(self: *RenderSystem, camera_position: Vec3) void {
        // Sort opaque queue by material
        std.sort.insertion(Entity, self.render_queue.opaque_queue.items, self, opaqueCompare);

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

        // Sort by material ID as fallback
        return @intFromPtr(render_a) < @intFromPtr(render_b);
    }

    fn transparentCompare(self: *RenderSystem, a: Entity, b: Entity) bool {
        const render_a = self.scene.getComponent(a, RenderComponent) orelse return false;
        const render_b = self.scene.getComponent(b, RenderComponent) orelse return false;

        // For now, just sort by component pointer since we don't have camera distance calculation
        return @intFromPtr(render_a) > @intFromPtr(render_b);
    }

    fn renderScene(self: *RenderSystem, camera: *CameraComponent) !void {
        // Set viewport
        std.log.debug("Setting viewport to ({d}, {d}, {d}, {d})", .{ self.viewport.x, self.viewport.y, self.viewport.z, self.viewport.w });

        // Clear buffers
        if (camera.clear_flags & CameraComponent.ClearFlags.Color != 0) {
            std.log.debug("Clearing color buffer to ({d}, {d}, {d}, {d})", .{ camera.clear_color.x, camera.clear_color.y, camera.clear_color.z, camera.clear_color.w });
        }
        if (camera.clear_flags & CameraComponent.ClearFlags.Depth != 0) {
            std.log.debug("Clearing depth buffer to {d}", .{camera.clear_depth});
        }
        if (camera.clear_flags & CameraComponent.ClearFlags.Stencil != 0) {
            std.log.debug("Clearing stencil buffer to {d}", .{camera.clear_stencil});
        }

        // Render opaque objects
        for (self.render_queue.opaque_queue.items) |entity| {
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

        // Set shader uniforms and draw mesh
        std.log.debug("Rendering entity {d} with material:", .{entity.id});
        std.log.debug("  World matrix: {any}", .{world_matrix});
        std.log.debug("  View-projection matrix: {any}", .{view_projection});
        std.log.debug("  Diffuse color: ({d}, {d}, {d}, {d})", .{ render.material.diffuse_color.x, render.material.diffuse_color.y, render.material.diffuse_color.z, render.material.diffuse_color.w });
        std.log.debug("  Metallic: {d}, Roughness: {d}", .{ render.material.metallic, render.material.roughness });

        if (render.material.texture_diffuse) |texture| {
            std.log.debug("  Diffuse texture: {s}", .{texture});
        }

        std.log.debug("  Drawing mesh with {} vertices", .{mesh.vertex_count});

        // In a real implementation, this would call the graphics backend to:
        // 1. Set transformation matrices as uniforms
        // 2. Set material properties as uniforms
        // 3. Bind textures
        // 4. Issue draw call for the mesh
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

/// Standalone update function for use with Scene.addSystem
pub fn update(system: *System, scene: *Scene, delta_time: f32) void {
    _ = system;
    _ = scene;
    _ = delta_time;

    // TODO: Implement render system functionality
    // This would typically update render queues and perform culling
}
