const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;
const Vec2 = @import("../math/vec2.zig").Vec2f;
const Vec3 = @import("../math/vec3.zig").Vec3f;
const Vec4 = @import("../math/vec4.zig").Vec4f;
const Mat4 = @import("../math/mat4.zig").Mat4f;
const Quaternion = @import("../math/math.zig").Quaternion(f32);
const vk = @import("../vulkan/vk.zig");
const enhanced_backend = @import("../vulkan/enhanced_backend.zig");
const interface = @import("../graphics/interface.zig");

// Define common types and structures
pub const EntityId = u64;
pub const ComponentTypeId = u32;
pub const SystemId = u32;

// Define Transform structure
pub const Transform = struct {
    position: Vec3,
    rotation: Quaternion,
    scale: Vec3,
    local_matrix: Mat4,
    world_matrix: Mat4,
    dirty: bool,

    pub fn init() Transform {
        return Transform{
            .position = Vec3.init(0, 0, 0),
            .rotation = Quaternion.identity(),
            .scale = Vec3.init(1, 1, 1),
            .local_matrix = Mat4.identity(),
            .world_matrix = Mat4.identity(),
            .dirty = true,
        };
    }

    pub fn setPosition(self: *Transform, pos: Vec3) void {
        self.position = pos;
        self.dirty = true;
    }

    pub fn setRotation(self: *Transform, rot: Quaternion) void {
        self.rotation = rot;
        self.dirty = true;
    }

    pub fn setScale(self: *Transform, s: Vec3) void {
        self.scale = s;
        self.dirty = true;
    }

    pub fn updateMatrices(self: *Transform, parent_world: ?Mat4) void {
        if (self.dirty) {
            self.local_matrix = Mat4.fromTransform(self.position, self.rotation, self.scale);
            self.dirty = false;
        }

        self.world_matrix = if (parent_world) |parent|
            parent.multiply(self.local_matrix)
        else
            self.local_matrix;
    }

    pub fn translate(self: *Transform, delta: Vec3) void {
        self.position = self.position.add(delta);
        self.dirty = true;
    }

    pub fn rotate(self: *Transform, axis: Vec3, angle: f32) void {
        const rot = Quaternion.fromAxisAngle(axis, angle);
        self.rotation = self.rotation.multiply(rot);
        self.dirty = true;
    }

    pub fn lookAt(self: *Transform, target: Vec3, up: Vec3) void {
        const forward = target.sub(self.position).normalize();
        const right = forward.cross(up).normalize();
        const new_up = right.cross(forward);

        self.rotation = Quaternion.fromMatrix(Mat4.lookToLH(Vec3.init(0, 0, 0), forward, new_up));
        self.dirty = true;
    }
};

// Define RenderComponent structure
pub const RenderComponent = struct {
    mesh_id: u32,
    material_id: u32,
    visible: bool,
    cast_shadows: bool,
    receive_shadows: bool,
    layer_mask: u32,
    bounds: BoundingBox,

    pub const BoundingBox = struct {
        min: Vec3,
        max: Vec3,

        pub fn init(min: Vec3, max: Vec3) BoundingBox {
            return BoundingBox{ .min = min, .max = max };
        }

        pub fn center(self: BoundingBox) Vec3 {
            return self.min.add(self.max).scale(0.5);
        }

        pub fn size(self: BoundingBox) Vec3 {
            return self.max.sub(self.min);
        }

        pub fn contains(self: BoundingBox, point: Vec3) bool {
            return point.x >= self.min.x and point.x <= self.max.x and
                point.y >= self.min.y and point.y <= self.max.y and
                point.z >= self.min.z and point.z <= self.max.z;
        }

        pub fn intersects(self: BoundingBox, other: BoundingBox) bool {
            return !(self.max.x < other.min.x or other.max.x < self.min.x or
                self.max.y < other.min.y or other.max.y < self.min.y or
                self.max.z < other.min.z or other.max.z < self.min.z);
        }

        pub fn transform(self: BoundingBox, matrix: Mat4) BoundingBox {
            const corners = [8]Vec3{
                Vec3.init(self.min.x, self.min.y, self.min.z),
                Vec3.init(self.max.x, self.min.y, self.min.z),
                Vec3.init(self.min.x, self.max.y, self.min.z),
                Vec3.init(self.max.x, self.max.y, self.min.z),
                Vec3.init(self.min.x, self.min.y, self.max.z),
                Vec3.init(self.max.x, self.min.y, self.max.z),
                Vec3.init(self.min.x, self.max.y, self.max.z),
                Vec3.init(self.max.x, self.max.y, self.max.z),
            };

            var new_min = matrix.mulVec3(corners[0]);
            var new_max = new_min;

            for (corners[1..]) |corner| {
                const transformed = matrix.mulVec3(corner);
                new_min = Vec3.init(@min(new_min.x, transformed.x), @min(new_min.y, transformed.y), @min(new_min.z, transformed.z));
                new_max = Vec3.init(@max(new_max.x, transformed.x), @max(new_max.y, transformed.y), @max(new_max.z, transformed.z));
            }

            return BoundingBox.init(new_min, new_max);
        }
    };

    pub fn init(mesh_id: u32, material_id: u32) RenderComponent {
        return RenderComponent{
            .mesh_id = mesh_id,
            .material_id = material_id,
            .visible = true,
            .cast_shadows = true,
            .receive_shadows = true,
            .layer_mask = 1,
            .bounds = BoundingBox.init(Vec3.init(-1, -1, -1), Vec3.init(1, 1, 1)),
        };
    }
};

// Define VulkanBackend structure
pub const VulkanBackend = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,

    // Core Vulkan objects
    device: ?enhanced_backend.VulkanDevice = null,
    renderer: ?enhanced_backend.VulkanRenderer = null,
    swapchain: ?enhanced_backend.Swapchain = null,

    // Resource management
    command_pool: ?enhanced_backend.CommandPool = null,
    current_command_buffer: ?vk.VkCommandBuffer = null,

    // Resource caches
    pipelines: std.AutoHashMap(u64, enhanced_backend.Pipeline),
    buffers: std.AutoHashMap(u64, enhanced_backend.Buffer),
    textures: std.AutoHashMap(u64, enhanced_backend.Image),

    // Performance tracking
    frame_count: u64 = 0,
    last_frame_time_ns: u64 = 0,

    const Self = @This();

    const vtable = interface.GraphicsBackend.VTable{
        .deinit = deinitImpl,
        .create_swap_chain = createSwapChainImpl,
        .resize_swap_chain = resizeSwapChainImpl,
        .present = presentImpl,
        .get_current_back_buffer = getCurrentBackBufferImpl,
        .create_texture = createTextureImpl,
        .create_buffer = createBufferImpl,
        .create_shader = createShaderImpl,
        .create_pipeline = createPipelineImpl,
        .create_render_target = createRenderTargetImpl,
        .update_buffer = updateBufferImpl,
        .update_texture = updateTextureImpl,
        .destroy_texture = destroyTextureImpl,
        .destroy_buffer = destroyBufferImpl,
        .destroy_shader = destroyShaderImpl,
        .destroy_render_target = destroyRenderTargetImpl,
        .create_command_buffer = createCommandBufferImpl,
        .begin_command_buffer = beginCommandBufferImpl,
        .end_command_buffer = endCommandBufferImpl,
        .submit_command_buffer = submitCommandBufferImpl,
        .begin_render_pass = beginRenderPassImpl,
        .end_render_pass = endRenderPassImpl,
        .set_viewport = setViewportImpl,
        .set_scissor = setScissorImpl,
        .bind_pipeline = bindPipelineImpl,
        .bind_vertex_buffer = bindVertexBufferImpl,
        .bind_index_buffer = bindIndexBufferImpl,
        .bind_texture = bindTextureImpl,
        .bind_uniform_buffer = bindUniformBufferImpl,
        .draw = drawImpl,
        .draw_indexed = drawIndexedImpl,
        .dispatch = dispatchImpl,
        .copy_buffer = copyBufferImpl,
        .copy_texture = copyTextureImpl,
        .copy_buffer_to_texture = copyBufferToTextureImpl,
        .copy_texture_to_buffer = copyTextureToBufferImpl,
        .resource_barrier = resourceBarrierImpl,
        .get_backend_info = getBackendInfoImpl,
        .set_debug_name = setDebugNameImpl,
        .begin_debug_group = beginDebugGroupImpl,
        .end_debug_group = endDebugGroupImpl,
    };

    /// Initialize the Vulkan backend and required resources
    pub fn init(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        // Create the backend instance
        const backend = try allocator.create(Self);

        // Initialize Vulkan state
        backend.* = Self{
            .allocator = allocator,
            .initialized = false,
            .pipelines = std.AutoHashMap(u64, enhanced_backend.Pipeline).init(allocator),
            .buffers = std.AutoHashMap(u64, enhanced_backend.Buffer).init(allocator),
            .textures = std.AutoHashMap(u64, enhanced_backend.Image).init(allocator),
        };

        // Create core Vulkan objects
        backend.device = try enhanced_backend.VulkanDevice.init(allocator);
        backend.command_pool = try enhanced_backend.CommandPool.init(backend.device.?.device, backend.device.?.graphics_queue_family);

        // Create the interface object
        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .vulkan,
            .vtable = &vtable,
            .impl_data = backend,
            .initialized = true,
        };

        backend.initialized = true;
        std.log.info("Enhanced Vulkan backend initialized", .{});
        return graphics_backend;
    }

    // Implementation of backend interface
    fn deinitImpl(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Clean up resources
        self.pipelines.deinit();
        self.buffers.deinit();
        self.textures.deinit();

        // Clean up core Vulkan objects
        if (self.command_pool) |*cmd_pool| {
            cmd_pool.deinit();
        }

        if (self.renderer) |*renderer| {
            renderer.deinit();
        }

        if (self.swapchain) |*swapchain| {
            swapchain.deinit();
        }

        if (self.device) |*device| {
            device.deinit();
        }

        self.allocator.destroy(self);
    }

    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.swapchain != null) {
            // Clean up existing swapchain
            self.swapchain.?.deinit();
            self.swapchain = null;
        }

        if (self.renderer != null) {
            // Clean up existing renderer
            self.renderer.?.deinit();
            self.renderer = null;
        }

        // Create new swapchain
        if (self.device) |device| {
            // Convert window handle to platform-specific surface
            const surface = try vk.createSurfaceFromHandle(
                device.instance,
                desc.window_handle,
            );

            // Create swapchain
            self.swapchain = try enhanced_backend.Swapchain.init(
                self.allocator,
                device.physical_device,
                device.device,
                surface,
                desc.width,
                desc.height,
                desc.vsync,
            );

            // Create renderer
            self.renderer = try enhanced_backend.VulkanRenderer.init(
                self.allocator,
                device,
                self.swapchain.?,
                self.command_pool.?,
            );

            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.renderer) |*renderer| {
            try renderer.resize(width, height);
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn presentImpl(impl: *anyopaque) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.swapchain) |*swapchain| {
            try swapchain.present();
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }
};

// Define Scene structure
pub const Scene = struct {
    allocator: Allocator,
    entities: AutoHashMap(EntityId, Entity),
    systems: ArrayList(System),
    next_entity_id: EntityId,
    next_system_id: SystemId,
    main_camera: ?EntityId,
    active: bool,
    time_scale: f32,
    physics_gravity: Vec3,

    // Spatial partitioning
    octree: ?*Octree,

    // Event system
    event_handlers: AutoHashMap([]const u8, ArrayList(*const fn (*Scene, []const u8, ?*anyopaque) void)),

    pub const Octree = struct {
        allocator: Allocator,
        bounds: RenderComponent.BoundingBox,
        entities: ArrayList(EntityId),
        children: [8]?*Octree,
        max_entities: u32,
        max_depth: u32,
        current_depth: u32,

        pub fn init(allocator: Allocator, bounds: RenderComponent.BoundingBox, max_entities: u32, max_depth: u32) !*Octree {
            const octree = try allocator.create(Octree);
            octree.* = Octree{
                .allocator = allocator,
                .bounds = bounds,
                .entities = ArrayList(EntityId).init(allocator),
                .children = [_]?*Octree{null} ** 8,
                .max_entities = max_entities,
                .max_depth = max_depth,
                .current_depth = 0,
            };
            return octree;
        }

        pub fn deinit(self: *Octree) void {
            self.entities.deinit();
            for (self.children) |child| {
                if (child) |c| {
                    c.deinit();
                    self.allocator.destroy(c);
                }
            }
            self.allocator.destroy(self);
        }

        pub fn insert(self: *Octree, entity_id: EntityId, bounds: RenderComponent.BoundingBox) !void {
            if (!self.bounds.intersects(bounds)) return;

            if (self.entities.items.len < self.max_entities or self.current_depth >= self.max_depth) {
                try self.entities.append(entity_id);
                return;
            }

            if (self.children[0] == null) {
                try self.subdivide();
            }

            for (self.children) |child| {
                if (child) |c| {
                    try c.insert(entity_id, bounds);
                }
            }
        }

        fn subdivide(self: *Octree) !void {
            const center = self.bounds.center();
            const half_size = self.bounds.size().scale(0.5);

            for (0..8) |i| {
                const offset = Vec3.init(
                    if (i & 1 != 0) half_size.x * 0.5 else -half_size.x * 0.5,
                    if (i & 2 != 0) half_size.y * 0.5 else -half_size.y * 0.5,
                    if (i & 4 != 0) half_size.z * 0.5 else -half_size.z * 0.5,
                );

                const child_center = center.add(offset);
                const child_bounds = RenderComponent.BoundingBox.init(child_center.sub(half_size.scale(0.5)), child_center.add(half_size.scale(0.5)));

                self.children[i] = try Octree.init(self.allocator, child_bounds, self.max_entities, self.max_depth);
                self.children[i].?.current_depth = self.current_depth + 1;
            }
        }

        pub fn query(self: *Octree, query_bounds: RenderComponent.BoundingBox, results: *ArrayList(EntityId)) !void {
            if (!self.bounds.intersects(query_bounds)) return;

            for (self.entities.items) |entity_id| {
                try results.append(entity_id);
            }

            for (self.children) |child| {
                if (child) |c| {
                    try c.query(query_bounds, results);
                }
            }
        }
    };

    pub fn init(allocator: Allocator) !*Scene {
        const scene = try allocator.create(Scene);
        scene.* = Scene{
            .allocator = allocator,
            .entities = AutoHashMap(EntityId, Entity).init(allocator),
            .systems = ArrayList(System).init(allocator),
            .next_entity_id = 1,
            .next_system_id = 1,
            .main_camera = null,
            .active = true,
            .time_scale = 1.0,
            .physics_gravity = Vec3.init(0, -9.81, 0),
            .octree = null,
            .event_handlers = AutoHashMap([]const u8, ArrayList(*const fn (*Scene, []const u8, ?*anyopaque) void)).init(allocator),
        };

        // Initialize octree
        const world_bounds = RenderComponent.BoundingBox.init(Vec3.init(-1000, -1000, -1000), Vec3.init(1000, 1000, 1000));
        scene.octree = try Octree.init(allocator, world_bounds, 10, 6);

        // Register default systems
        try scene.registerDefaultSystems();

        return scene;
    }

    pub fn deinit(self: *Scene) void {
        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.entities.deinit();

        self.systems.deinit();

        if (self.octree) |octree| {
            octree.deinit();
        }

        var event_iter = self.event_handlers.iterator();
        while (event_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.event_handlers.deinit();

        self.allocator.destroy(self);
    }

    pub fn createEntity(self: *Scene, name: []const u8) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;

        var entity = try Entity.init(self.allocator, entity_id, name);

        // All entities have a transform component by default
        try entity.addComponent(Component{ .transform = Transform.init() });

        try self.entities.put(entity_id, entity);
        return entity_id;
    }

    pub fn destroyEntity(self: *Scene, entity_id: EntityId) void {
        if (self.entities.fetchRemove(entity_id)) |entry| {
            var entity = entry.value;

            // Remove from parent
            if (entity.parent) |parent_id| {
                if (self.getEntity(parent_id)) |parent| {
                    parent.removeChild(entity_id);
                }
            }

            // Destroy children
            for (entity.children.items) |child_id| {
                self.destroyEntity(child_id);
            }

            entity.deinit(self.allocator);
        }
    }

    pub fn getEntity(self: *Scene, entity_id: EntityId) ?*Entity {
        return self.entities.getPtr(entity_id);
    }

    pub fn findEntityByName(self: *Scene, name: []const u8) ?*Entity {
        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.name, name)) {
                return entry.value_ptr;
            }
        }
        return null;
    }

    pub fn findEntitiesByTag(self: *Scene, tag: []const u8, results: *ArrayList(EntityId)) !void {
        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.tag, tag)) {
                try results.append(entry.key_ptr.*);
            }
        }
    }

    pub fn addSystem(self: *Scene, name: []const u8, priority: i32, update_fn: *const fn (*System, *Scene, f32) void) !SystemId {
        const system_id = self.next_system_id;
        self.next_system_id += 1;

        const system = System.init(system_id, name, priority, update_fn);
        try self.systems.append(system);

        // Sort systems by priority
        std.sort.heap(System, self.systems.items, {}, systemCompare);

        return system_id;
    }

    fn systemCompare(context: void, a: System, b: System) bool {
        _ = context;
        return a.priority < b.priority;
    }

    pub fn removeSystem(self: *Scene, system_id: SystemId) void {
        for (self.systems.items, 0..) |system, i| {
            if (system.id == system_id) {
                _ = self.systems.swapRemove(i);
                break;
            }
        }
    }

    pub fn update(self: *Scene, delta_time: f32) void {
        if (!self.active) return;

        const scaled_delta = delta_time * self.time_scale;

        // Update systems
        for (self.systems.items) |*system| {
            if (system.enabled) {
                system.update_fn(system, self, scaled_delta);
            }
        }
    }

    pub fn queryEntitiesInBounds(self: *Scene, bounds: RenderComponent.BoundingBox) !ArrayList(EntityId) {
        var results = ArrayList(EntityId).init(self.allocator);

        if (self.octree) |octree| {
            try octree.query(bounds, &results);
        } else {
            // Fallback: brute force search
            var entity_iter = self.entities.iterator();
            while (entity_iter.next()) |entry| {
                const entity = entry.value_ptr;
                if (entity.getComponent(RenderComponent)) |render| {
                    if (entity.getComponent(Transform)) |transform| {
                        const world_bounds = render.bounds.transform(transform.world_matrix);
                        if (bounds.intersects(world_bounds)) {
                            try results.append(entity.id);
                        }
                    }
                }
            }
        }

        return results;
    }

    pub fn rayCast(self: *Scene, ray_origin: Vec3, ray_direction: Vec3, max_distance: f32) ?RaycastHit {
        var closest_hit: ?RaycastHit = null;
        var closest_distance: f32 = max_distance;

        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            const entity = entry.value_ptr;
            if (entity.getComponent(RenderComponent)) |render| {
                if (entity.getComponent(Transform)) |transform| {
                    const world_bounds = render.bounds.transform(transform.world_matrix);

                    if (rayIntersectsBounds(ray_origin, ray_direction, world_bounds)) |distance| {
                        if (distance < closest_distance) {
                            closest_distance = distance;
                            closest_hit = RaycastHit{
                                .entity_id = entity.id,
                                .point = ray_origin.add(ray_direction.scale(distance)),
                                .normal = Vec3.init(0, 1, 0), // Simplified
                                .distance = distance,
                            };
                        }
                    }
                }
            }
        }

        return closest_hit;
    }

    pub const RaycastHit = struct {
        entity_id: EntityId,
        point: Vec3,
        normal: Vec3,
        distance: f32,
    };

    fn rayIntersectsBounds(ray_origin: Vec3, ray_direction: Vec3, bounds: RenderComponent.BoundingBox) ?f32 {
        const inv_dir = Vec3.init(1.0 / ray_direction.x, 1.0 / ray_direction.y, 1.0 / ray_direction.z);

        const t1 = (bounds.min.x - ray_origin.x) * inv_dir.x;
        const t2 = (bounds.max.x - ray_origin.x) * inv_dir.x;
        const t3 = (bounds.min.y - ray_origin.y) * inv_dir.y;
        const t4 = (bounds.max.y - ray_origin.y) * inv_dir.y;
        const t5 = (bounds.min.z - ray_origin.z) * inv_dir.z;
        const t6 = (bounds.max.z - ray_origin.z) * inv_dir.z;

        const tmin = @max(@max(@min(t1, t2), @min(t3, t4)), @min(t5, t6));
        const tmax = @min(@min(@max(t1, t2), @max(t3, t4)), @max(t5, t6));

        if (tmax < 0 or tmin > tmax) {
            return null;
        }

        return if (tmin < 0) tmax else tmin;
    }

    pub fn addEventListener(self: *Scene, event_name: []const u8, handler: *const fn (*Scene, []const u8, ?*anyopaque) void) !void {
        const key = try self.allocator.dupe(u8, event_name);

        if (self.event_handlers.getPtr(key)) |handlers| {
            try handlers.append(handler);
        } else {
            var handlers = ArrayList(*const fn (*Scene, []const u8, ?*anyopaque) void).init(self.allocator);
            try handlers.append(handler);
            try self.event_handlers.put(key, handlers);
        }
    }

    pub fn dispatchEvent(self: *Scene, event_name: []const u8, data: ?*anyopaque) void {
        if (self.event_handlers.get(event_name)) |handlers| {
            for (handlers.items) |handler| {
                handler(self, event_name, data);
            }
        }
    }

    fn registerDefaultSystems(self: *Scene) !void {
        _ = try self.addSystem("Transform", 0, transformSystemUpdate);
        _ = try self.addSystem("Physics", 100, physicsSystemUpdate);
        _ = try self.addSystem("Script", 200, scriptSystemUpdate);
        _ = try self.addSystem("Audio", 300, audioSystemUpdate);
        _ = try self.addSystem("Render", 1000, renderSystemUpdate);
    }

    fn transformSystemUpdate(system: *System, scene: *Scene, delta_time: f32) void {
        _ = system;
        _ = delta_time;

        var entity_iter = scene.entities.iterator();
        while (entity_iter.next()) |entry| {
            const entity = entry.value_ptr;
            if (entity.getComponent(Transform)) |transform| {
                const parent_world = if (entity.parent) |parent_id|
                    if (scene.getEntity(parent_id)) |parent|
                        if (parent.getComponent(Transform)) |parent_transform|
                            parent_transform.world_matrix
                        else
                            null
                    else
                        null
                else
                    null;

                transform.updateMatrices(parent_world);
            }
        }
    }

    fn physicsSystemUpdate(system: *System, scene: *Scene, delta_time: f32) void {
        _ = system;

        var entity_iter = scene.entities.iterator();
        while (entity_iter.next()) |entry| {
            const entity = entry.value_ptr;
            if (entity.getComponent(PhysicsComponent)) |physics| {
                if (entity.getComponent(Transform)) |transform| {
                    updatePhysicsEntity(physics, transform, scene, delta_time);
                }
            }
        }
    }

    fn updatePhysicsEntity(physics: *PhysicsComponent, transform: *Transform, scene: *Scene, delta_time: f32) void {
        _ = scene; // Explicitly ignore the unused parameter
        if (physics.body_type == .static) return;

        // Apply gravity
        if (physics.use_gravity) {
            physics.applyForce(scene.physics_gravity.scale(physics.mass));
        }

        // Apply drag
        const drag_force = physics.velocity.scale(-physics.drag);
        physics.applyForce(drag_force);

        // Update velocity
        if (physics.mass > 0) {
            const acceleration = physics.force.scale(1.0 / physics.mass);
            physics.velocity = physics.velocity.add(acceleration.scale(delta_time));
        }

        // Update position
        if (!physics.is_kinematic) {
            transform.translate(physics.velocity.scale(delta_time));
        }

        // Apply angular drag
        const angular_drag_torque = physics.angular_velocity.scale(-physics.angular_drag);
        physics.applyTorque(angular_drag_torque);

        // Update angular velocity and rotation
        if (!physics.freeze_rotation) {
            physics.angular_velocity = physics.angular_velocity.add(physics.torque.scale(delta_time));
            const angular_delta = physics.angular_velocity.scale(delta_time);
            if (angular_delta.length() > 0) {
                const axis = angular_delta.normalize();
                const angle = angular_delta.length();
                transform.rotate(axis, angle);
            }
        }

        // Reset forces
        physics.force = Vec3.init(0, 0, 0);
        physics.torque = Vec3.init(0, 0, 0);
    }

    fn scriptSystemUpdate(system: *System, scene: *Scene, delta_time: f32) void {
        _ = system;
        _ = delta_time;

        var entity_iter = scene.entities.iterator();
        while (entity_iter.next()) |entry| {
            const entity = entry.value_ptr;
            if (entity.getComponent(ScriptComponent)) |script| {
                if (script.enabled) {
                    // Execute script update function
                    _ = script.executeFunction("update", &[_]ScriptComponent.ScriptValue{
                        ScriptComponent.ScriptValue{ .number = delta_time },
                    }) catch {};
                }
            }
        }
    }

    fn audioSystemUpdate(system: *System, scene: *Scene, delta_time: f32) void {
        _ = system;
        _ = delta_time;

        var entity_iter = scene.entities.iterator();
        while (entity_iter.next()) |entry| {
            const entity = entry.value_ptr;
            if (entity.getComponent(AudioComponent)) |audio| {
                if (entity.getComponent(Transform)) |transform| {
                    updateAudioEntity(audio, transform, scene);
                }
            }
        }
    }

    fn updateAudioEntity(audio: *AudioComponent, transform: *Transform, scene: *Scene) void {
        _ = scene;

        if (audio.playing and audio.spatial) {
            // Update 3D audio position
            // This would interface with the audio system
            _ = transform.position;
        }
    }

    fn renderSystemUpdate(system: *System, scene: *Scene, delta_time: f32) void {
        _ = system;
        _ = delta_time;

        // Update camera matrices
        if (scene.main_camera) |camera_id| {
            if (scene.getEntity(camera_id)) |camera_entity| {
                if (camera_entity.getComponent(CameraComponent)) |camera| {
                    if (camera_entity.getComponent(Transform)) |transform| {
                        camera.updateMatrices(transform);
                    }
                }
            }
        }

        // Update octree with render components
        if (scene.octree) |octree| {
            // Clear and rebuild octree
            octree.entities.clearRetainingCapacity();

            var entity_iter = scene.entities.iterator();
            while (entity_iter.next()) |entry| {
                const entity = entry.value_ptr;
                if (entity.getComponent(RenderComponent)) |render| {
                    if (entity.getComponent(Transform)) |transform| {
                        const world_bounds = render.bounds.transform(transform.world_matrix);
                        octree.insert(entity.id, world_bounds) catch {};
                    }
                }
            }
        }
    }
};

// Test the combined scene and render system
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var scene = try Scene.init(allocator);
    defer scene.deinit();

    // Create a test entity with components
    const entity_id = try scene.createEntity("TestCube");
    const entity = scene.getEntity(entity_id).?;

    // Add render component
    const render = RenderComponent.init(1, 1);
    try entity.addComponent(Component{ .render = render });

    // Add physics component
    const physics = PhysicsComponent.init(.dynamic);
    try entity.addComponent(Component{ .physics = physics });

    // Test component retrieval
    try std.testing.expect(entity.hasComponent(Transform));
    try std.testing.expect(entity.hasComponent(RenderComponent));
    try std.testing.expect(entity.hasComponent(PhysicsComponent));

    // Test transform
    if (entity.getComponent(Transform)) |transform| {
        transform.setPosition(Vec3.init(5, 0, 0));
        try std.testing.expect(transform.position.x == 5);
    }

    // Test physics
    if (entity.getComponent(PhysicsComponent)) |phys| {
        phys.applyForce(Vec3.init(10, 0, 0));
        try std.testing.expect(phys.force.x == 10);
    }

    // Test scene update
    scene.update(0.016);

    // Test raycast
    const hit = scene.rayCast(Vec3.init(0, 0, 0), Vec3.init(1, 0, 0), 100);
    try std.testing.expect(hit != null);

    // Test entity destruction
    scene.destroyEntity(entity_id);
    try std.testing.expect(scene.getEntity(entity_id) == null);
}

// Define missing identifiers
fn getCurrentBackBufferImpl(impl: *anyopaque) !*vk.VkImage {
    // Implementation details
    return null;
}

fn createTextureImpl(impl: *anyopaque, desc: *const interface.TextureDesc) !*vk.VkImage {
    // Implementation details
    return null;
}

fn createBufferImpl(impl: *anyopaque, desc: *const interface.BufferDesc) !*vk.VkBuffer {
    // Implementation details
    return null;
}

fn createShaderImpl(impl: *anyopaque, desc: *const interface.ShaderDesc) !*vk.VkShaderModule {
    // Implementation details
    return null;
}

fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) !*vk.VkPipeline {
    // Implementation details
    return null;
}

fn createRenderTargetImpl(impl: *anyopaque, desc: *const interface.RenderTargetDesc) !*vk.VkRenderPass {
    // Implementation details
    return null;
}

fn updateBufferImpl(impl: *anyopaque, buffer: *vk.VkBuffer, data: []const u8) !void {
    // Implementation details
}

fn updateTextureImpl(impl: *anyopaque, texture: *vk.VkImage, data: []const u8) !void {
    // Implementation details
}

fn destroyTextureImpl(impl: *anyopaque, texture: *vk.VkImage) !void {
    // Implementation details
}

fn destroyBufferImpl(impl: *anyopaque, buffer: *vk.VkBuffer) !void {
    // Implementation details
}

fn destroyShaderImpl(impl: *anyopaque, shader: *vk.VkShaderModule) !void {
    // Implementation details
}

fn destroyRenderTargetImpl(impl: *anyopaque, render_target: *vk.VkRenderPass) !void {
    // Implementation details
}

pub const LightComponent = struct {
    light_type: LightType,
    color: Vec3,
    intensity: f32,
    range: f32,
    spot_angle: f32,
    inner_cone_angle: f32,
    cast_shadows: bool,
    shadow_resolution: u32,
    shadow_bias: f32,

    pub const LightType = enum {
        directional,
        point,
        spot,
        area,
    };

    pub fn init(light_type: LightType) LightComponent {
        return LightComponent{
            .light_type = light_type,
            .color = Vec3.init(1, 1, 1),
            .intensity = 1.0,
            .range = 10.0,
            .spot_angle = 45.0,
            .inner_cone_angle = 22.5,
            .cast_shadows = true,
            .shadow_resolution = 1024,
            .shadow_bias = 0.001,
        };
    }
};

pub const ScriptComponent = struct {
    enabled: bool,
    script_data: ?*u8,
    variables: AutoHashMap([]const u8, ScriptValue),
    functions: AutoHashMap([]const u8, ScriptFunction),

    pub const ScriptValue = union(enum) {
        number: f32,
        string: []const u8,
    };

    pub const ScriptFunction = struct {
        name: []const u8,
        body: []const u8,
        parameters: ArrayList([]const u8),
    };

    pub fn deinit(self: *ScriptComponent) void {
        if (self.script_data) |data| {
            self.allocator.free(data);
        }

        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
        }
        self.variables.deinit();

        var func_iter = self.functions.iterator();
        while (func_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            const func = entry.value_ptr.*;
            self.allocator.free(func.name);
            self.allocator.free(func.body);
            for (func.parameters.items) |param| {
                self.allocator.free(param);
            }
            func.parameters.deinit();
        }
        self.functions.deinit();
    }

    pub fn setVariable(self: *ScriptComponent, name: []const u8, value: ScriptValue) !void {
        const key = try self.allocator.dupe(u8, name);
        try self.variables.put(key, value);
    }

    pub fn getVariable(self: *ScriptComponent, name: []const u8) ?ScriptValue {
        return self.variables.get(name);
    }

    pub fn executeFunction(self: *ScriptComponent, name: []const u8, args: []const ScriptValue) !ScriptValue {
        _ = self;
        _ = name;
        _ = args;
        // Script execution would be implemented here
        return ScriptValue{ .number = 0 };
    }
};

pub const AudioComponent = struct {
    source_id: u32,
    volume: f32,
    pitch: f32,
    looping: bool,
    spatial: bool,
    min_distance: f32,
    max_distance: f32,
    rolloff_factor: f32,
    playing: bool,

    pub fn init(source_id: u32) AudioComponent {
        return AudioComponent{
            .source_id = source_id,
            .volume = 1.0,
            .pitch = 1.0,
            .looping = false,
            .spatial = true,
            .min_distance = 1.0,
            .max_distance = 100.0,
            .rolloff_factor = 1.0,
            .playing = false,
        };
    }

    pub fn play(self: *AudioComponent) void {
        self.playing = true;
    }

    pub fn stop(self: *AudioComponent) void {
        self.playing = false;
    }

    pub fn pause(self: *AudioComponent) void {
        self.playing = false;
    }
};

pub const CameraComponent = struct {
    projection_type: ProjectionType,
    field_of_view: f32,
    orthographic_size: f32,
    near_plane: f32,
    far_plane: f32,
    aspect_ratio: f32,
    view_matrix: Mat4,
    projection_matrix: Mat4,
    viewport: Viewport,
    clear_flags: ClearFlags,
    clear_color: Vec4,
    depth: i32,

    pub const ProjectionType = enum {
        perspective,
        orthographic,
    };

    pub const Viewport = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    };

    pub const ClearFlags = packed struct {
        color: bool = true,
        depth: bool = true,
        stencil: bool = false,
        skybox: bool = false,
    };

    pub fn init() CameraComponent {
        return CameraComponent{
            .projection_type = .perspective,
            .field_of_view = 60.0,
            .orthographic_size = 5.0,
            .near_plane = 0.1,
            .far_plane = 1000.0,
            .aspect_ratio = 16.0 / 9.0,
            .view_matrix = Mat4.identity(),
            .projection_matrix = Mat4.identity(),
            .viewport = Viewport{ .x = 0, .y = 0, .width = 1, .height = 1 },
            .clear_flags = ClearFlags{},
            .clear_color = Vec4.init(0.2, 0.3, 0.4, 1.0),
            .depth = 0,
        };
    }

    pub fn updateMatrices(self: *CameraComponent, transform: *const Transform) void {
        self.view_matrix = transform.world_matrix.inverse();

        switch (self.projection_type) {
            .perspective => {
                const fov_rad = self.field_of_view * std.math.pi / 180.0;
                self.projection_matrix = Mat4.perspective(fov_rad, self.aspect_ratio, self.near_plane, self.far_plane);
            },
            .orthographic => {
                const half_width = self.orthographic_size * self.aspect_ratio * 0.5;
                const half_height = self.orthographic_size * 0.5;
                self.projection_matrix = Mat4.orthographic(-half_width, half_width, -half_height, half_height, self.near_plane, self.far_plane);
            },
        }
    }

    pub fn screenToWorldPoint(self: *const CameraComponent, screen_point: Vec3) Vec3 {
        const ndc = Vec3.init((screen_point.x / self.viewport.width) * 2.0 - 1.0, 1.0 - (screen_point.y / self.viewport.height) * 2.0, screen_point.z * 2.0 - 1.0);

        const view_proj_inv = self.projection_matrix.multiply(self.view_matrix).inverse();
        const world_point = view_proj_inv.mulVec3(ndc);
        return world_point;
    }

    pub fn worldToScreenPoint(self: *const CameraComponent, world_point: Vec3) Vec3 {
        const view_proj = self.projection_matrix.multiply(self.view_matrix);
        const ndc = view_proj.mulVec3(world_point);

        return Vec3.init((ndc.x + 1.0) * 0.5 * self.viewport.width, (1.0 - ndc.y) * 0.5 * self.viewport.height, (ndc.z + 1.0) * 0.5);
    }
};

pub const System = struct {
    id: SystemId,
    name: []const u8,
    priority: i32,
    enabled: bool,
    update_fn: *const fn (*System, *Scene, f32) void,

    pub fn init(id: SystemId, name: []const u8, priority: i32, update_fn: *const fn (*System, *Scene, f32) void) System {
        return System{
            .id = id,
            .name = name,
            .priority = priority,
            .enabled = true,
            .update_fn = update_fn,
        };
    }
};

pub const PhysicsComponent = struct {
    body_type: BodyType,
    mass: f32,
    drag: f32,
    angular_drag: f32,
    use_gravity: bool,
    is_kinematic: bool,
    freeze_rotation: bool,
    velocity: Vec3,
    angular_velocity: Vec3,
    force: Vec3,
    torque: Vec3,

    pub const BodyType = enum {
        static,
        dynamic,
        kinematic,
    };

    pub fn init(body_type: BodyType) PhysicsComponent {
        return PhysicsComponent{
            .body_type = body_type,
            .mass = 1.0,
            .drag = 0.1,
            .angular_drag = 0.05,
            .use_gravity = true,
            .is_kinematic = false,
            .freeze_rotation = false,
            .velocity = Vec3.init(0, 0, 0),
            .angular_velocity = Vec3.init(0, 0, 0),
            .force = Vec3.init(0, 0, 0),
            .torque = Vec3.init(0, 0, 0),
        };
    }

    pub fn applyForce(self: *PhysicsComponent, force: Vec3) void {
        self.force = self.force.add(force);
    }

    pub fn applyTorque(self: *PhysicsComponent, torque: Vec3) void {
        self.torque = self.torque.add(torque);
    }
};

pub const Entity = struct {
    id: EntityId,
    name: []const u8,
    active: bool,
    tag: []const u8,
    layer: u32,
    parent: ?EntityId,
    children: ArrayList(EntityId),
    components: AutoHashMap(ComponentTypeId, Component),

    pub fn init(allocator: Allocator, id: EntityId, name: []const u8) !Entity {
        return Entity{
            .id = id,
            .name = try allocator.dupe(u8, name),
            .active = true,
            .tag = try allocator.dupe(u8, "Untagged"),
            .layer = 0,
            .parent = null,
            .children = ArrayList(EntityId).init(allocator),
            .components = AutoHashMap(ComponentTypeId, Component).init(allocator),
        };
    }

    pub fn deinit(self: *Entity, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.tag);
        self.children.deinit();

        var comp_iter = self.components.iterator();
        while (comp_iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                .script => |*script| script.deinit(),
                else => {},
            }
        }
        self.components.deinit();
    }

    pub fn addComponent(self: *Entity, component: Component) !void {
        try self.components.put(component.getTypeId(), component);
    }

    pub fn getComponent(self: *Entity, comptime T: type) ?*T {
        const type_id = switch (T) {
            Transform => 0,
            RenderComponent => 1,
            PhysicsComponent => 2,
            ScriptComponent => 3,
            AudioComponent => 4,
            LightComponent => 5,
            CameraComponent => 6,
            else => return null,
        };

        if (self.components.getPtr(type_id)) |component| {
            return switch (component.*) {
                inline else => |*comp| if (@TypeOf(comp.*) == T) comp else null,
            };
        }
        return null;
    }

    pub fn hasComponent(self: *Entity, comptime T: type) bool {
        return self.getComponent(T) != null;
    }

    pub fn removeComponent(self: *Entity, comptime T: type) bool {
        const type_id = switch (T) {
            Transform => 0,
            RenderComponent => 1,
            PhysicsComponent => 2,
            ScriptComponent => 3,
            AudioComponent => 4,
            LightComponent => 5,
            CameraComponent => 6,
            else => return false,
        };

        return self.components.remove(type_id);
    }

    pub fn setParent(self: *Entity, parent_id: ?EntityId, scene: *Scene) !void {
        if (self.parent) |old_parent_id| {
            if (scene.getEntity(old_parent_id)) |old_parent| {
                for (old_parent.children.items, 0..) |child_id, i| {
                    if (child_id == self.id) {
                        _ = old_parent.children.swapRemove(i);
                        break;
                    }
                }
            }
        }

        self.parent = parent_id;

        if (parent_id) |new_parent_id| {
            if (scene.getEntity(new_parent_id)) |new_parent| {
                try new_parent.children.append(self.id);
            }
        }
    }

    pub fn addChild(self: *Entity, child_id: EntityId) !void {
        try self.children.append(child_id);
    }

    pub fn removeChild(self: *Entity, child_id: EntityId) void {
        for (self.children.items, 0..) |id, i| {
            if (id == child_id) {
                _ = self.children.swapRemove(i);
                break;
            }
        }
    }
};

pub const Component = union(enum) {
    transform: Transform,
    render: RenderComponent,
    physics: PhysicsComponent,
    script: ScriptComponent,
    audio: AudioComponent,
    light: LightComponent,
    camera: CameraComponent,

    pub fn getTypeId(self: Component) ComponentTypeId {
        return switch (self) {
            .transform => 0,
            .render => 1,
            .physics => 2,
            .script => 3,
            .audio => 4,
            .light => 5,
            .camera => 6,
        };
    }
};

// Define missing identifiers
fn createCommandBufferImpl(impl: *anyopaque, command_pool: *vk.VkCommandPool) !*vk.VkCommandBuffer {
    // Implementation details
    return null;
}

fn beginCommandBufferImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer) !void {
    // Implementation details
}

fn endCommandBufferImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer) !void {
    // Implementation details
}

fn submitCommandBufferImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, queue: *vk.VkQueue) !void {
    // Implementation details
}

fn beginRenderPassImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, render_pass: *vk.VkRenderPass, framebuffer: *vk.VkFramebuffer) !void {
    // Implementation details
}

fn endRenderPassImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer) !void {
    // Implementation details
}

// Handle unused parameter warnings
fn setViewportImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, viewport: *vk.VkViewport) !void {
    // Implementation details
}

fn setScissorImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, scissor: *vk.VkRect2D) !void {
    // Implementation details
}

fn bindPipelineImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, pipeline: *vk.VkPipeline) !void {
    // Implementation details
}

fn bindVertexBufferImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, buffer: *vk.VkBuffer, offset: u64) !void {
    // Implementation details
}

fn bindIndexBufferImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, buffer: *vk.VkBuffer, offset: u64) !void {
    // Implementation details
}

fn bindTextureImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, texture: *vk.VkImage) !void {
    // Implementation details
}

fn bindUniformBufferImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, buffer: *vk.VkBuffer) !void {
    // Implementation details
}

fn drawImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, vertex_count: u32, instance_count: u32) !void {
    // Implementation details
}

fn drawIndexedImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, index_count: u32, instance_count: u32) !void {
    // Implementation details
}

fn dispatchImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, x: u32, y: u32, z: u32) !void {
    // Implementation details
}

fn copyBufferImpl(impl: *anyopaque, src_buffer: *vk.VkBuffer, dst_buffer: *vk.VkBuffer, size: u64) !void {
    // Implementation details
}

fn copyTextureImpl(impl: *anyopaque, src_image: *vk.VkImage, dst_image: *vk.VkImage, region: *vk.VkImageCopy) !void {
    // Implementation details
}

fn copyBufferToTextureImpl(impl: *anyopaque, src_buffer: *vk.VkBuffer, dst_image: *vk.VkImage, region: *vk.VkBufferImageCopy) !void {
    // Implementation details
}

fn copyTextureToBufferImpl(impl: *anyopaque, src_image: *vk.VkImage, dst_buffer: *vk.VkBuffer, region: *vk.VkImageToBufferCopy) !void {
    // Implementation details
}

fn resourceBarrierImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, barriers: []const vk.VkImageMemoryBarrier) !void {
    // Implementation details
}

fn getBackendInfoImpl(impl: *anyopaque) !*vk.VkPhysicalDeviceProperties {
    // Implementation details
    return null;
}

fn setDebugNameImpl(impl: *anyopaque, object: vk.VkObjectType, handle: vk.VkHandle, name: []const u8) !void {
    // Implementation details
}

fn beginDebugGroupImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer, debug_group: *vk.VkDebugMarkerMarkerInfoEXT) !void {
    // Implementation details
}

fn endDebugGroupImpl(impl: *anyopaque, command_buffer: *vk.VkCommandBuffer) !void {
    // Implementation details
}
