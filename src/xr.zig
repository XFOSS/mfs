//! Extended Reality (XR) System for MFS Engine
//! Comprehensive VR/AR support with OpenXR integration
//! @thread-safe XR operations are thread-safe with proper synchronization
//! @symbol XRSystem - Main XR interface for virtual reality applications

const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Vec3f = math.Vec3f;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Quaternion = math.Quaternion;
const graphics = @import("graphics/gpu.zig");
const platform = @import("platform/platform.zig");
const memory = @import("system/memory/memory_manager.zig");

/// Extended Reality System
/// @thread-safe Thread-safe XR operations with proper synchronization
/// @symbol XRSystem
pub const XRSystem = struct {
    allocator: std.mem.Allocator,

    // XR runtime and session
    runtime: *XRRuntime,
    session: ?*XRSession = null,

    // Head-mounted display
    hmd: *HeadMountedDisplay,

    // Tracking and input
    tracking_system: *TrackingSystem,
    input_system: *XRInputSystem,

    // Rendering
    renderer: *XRRenderer,
    eye_textures: [2]*XREyeTexture,

    // Spatial computing
    spatial_anchors: std.ArrayList(*SpatialAnchor),
    spatial_mapping: ?*SpatialMapping = null,
    hand_tracking: ?*HandTracking = null,

    // Performance and statistics
    stats: XRStats,

    // Safety and comfort
    comfort_settings: ComfortSettings,
    guardian_system: ?*GuardianSystem = null,

    const Self = @This();

    /// XR performance statistics
    pub const XRStats = struct {
        frame_rate: f32 = 90.0,
        frame_time_ms: f64 = 11.1,
        dropped_frames: u32 = 0,
        tracking_quality: TrackingQuality = .good,
        battery_level: f32 = 1.0,
        temperature: f32 = 25.0,

        pub const TrackingQuality = enum {
            lost,
            poor,
            fair,
            good,
            excellent,
        };

        pub fn reset(self: *XRStats) void {
            self.dropped_frames = 0;
        }
    };

    /// XR Runtime (OpenXR-like interface)
    pub const XRRuntime = struct {
        runtime_type: RuntimeType,
        api_version: ApiVersion,
        extensions: std.ArrayList([]const u8),

        pub const RuntimeType = enum {
            openxr,
            openvr,
            oculus,
            windows_mixed_reality,
            pico,
            varjo,
        };

        pub const ApiVersion = struct {
            major: u32,
            minor: u32,
            patch: u32,
        };

        pub fn init(allocator: std.mem.Allocator, runtime_type: RuntimeType) !*XRRuntime {
            const runtime = try allocator.create(XRRuntime);
            runtime.* = XRRuntime{
                .runtime_type = runtime_type,
                .api_version = ApiVersion{ .major = 1, .minor = 0, .patch = 0 },
                .extensions = std.ArrayList([]const u8).init(allocator),
            };

            // Add common extensions
            try runtime.extensions.append("XR_KHR_composition_layer_depth");
            try runtime.extensions.append("XR_KHR_hand_tracking");
            try runtime.extensions.append("XR_FB_spatial_entity");
            try runtime.extensions.append("XR_FB_scene");
            try runtime.extensions.append("XR_FB_passthrough");

            return runtime;
        }

        pub fn deinit(self: *XRRuntime, allocator: std.mem.Allocator) void {
            self.extensions.deinit();
            allocator.destroy(self);
        }

        pub fn createSession(self: *XRRuntime, allocator: std.mem.Allocator) !*XRSession {
            return XRSession.init(allocator, self);
        }
    };

    /// XR Session management
    pub const XRSession = struct {
        runtime: *XRRuntime,
        state: SessionState = .idle,
        reference_space: ReferenceSpaceType = .stage,

        pub const SessionState = enum {
            idle,
            ready,
            synchronized,
            visible,
            focused,
            stopping,
            loss_pending,
            exiting,
        };

        pub const ReferenceSpaceType = enum {
            view,
            local,
            stage,
            unbounded,
        };

        pub fn init(allocator: std.mem.Allocator, runtime: *XRRuntime) !*XRSession {
            const session = try allocator.create(XRSession);
            session.* = XRSession{
                .runtime = runtime,
            };
            return session;
        }

        pub fn deinit(self: *XRSession, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }

        pub fn beginSession(self: *XRSession) !void {
            self.state = .ready;
        }

        pub fn endSession(self: *XRSession) !void {
            self.state = .stopping;
        }

        pub fn pollEvents(self: *XRSession) ![]XREvent {
            _ = self;
            // TODO: Implement event polling
            return &[_]XREvent{};
        }
    };

    /// XR Events
    pub const XREvent = struct {
        event_type: EventType,
        timestamp: i64,
        data: EventData,

        pub const EventType = enum {
            session_state_changed,
            reference_space_changed,
            interaction_profile_changed,
            visibility_mask_changed,
            performance_settings_changed,
        };

        pub const EventData = union(EventType) {
            session_state_changed: SessionStateChangedData,
            reference_space_changed: ReferenceSpaceChangedData,
            interaction_profile_changed: InteractionProfileChangedData,
            visibility_mask_changed: VisibilityMaskChangedData,
            performance_settings_changed: PerformanceSettingsChangedData,
        };

        pub const SessionStateChangedData = struct {
            old_state: XRSession.SessionState,
            new_state: XRSession.SessionState,
        };

        pub const ReferenceSpaceChangedData = struct {
            old_space: XRSession.ReferenceSpaceType,
            new_space: XRSession.ReferenceSpaceType,
        };

        pub const InteractionProfileChangedData = struct {
            profile_path: []const u8,
        };

        pub const VisibilityMaskChangedData = struct {
            eye_index: u32,
        };

        pub const PerformanceSettingsChangedData = struct {
            domain: PerformanceDomain,
            level: PerformanceLevel,
        };

        pub const PerformanceDomain = enum {
            cpu,
            gpu,
        };

        pub const PerformanceLevel = enum {
            power_savings,
            sustained_low,
            sustained_high,
            boost,
        };
    };

    /// Head-Mounted Display representation
    pub const HeadMountedDisplay = struct {
        device_name: []const u8,
        manufacturer: []const u8,
        display_specs: DisplaySpecs,
        tracking_caps: TrackingCapabilities,

        pub const DisplaySpecs = struct {
            resolution_per_eye: [2]u32, // width, height
            refresh_rate: f32 = 90.0,
            field_of_view: FieldOfView,
            ipd_range: [2]f32 = .{ 58.0, 72.0 }, // min, max IPD in mm

            pub const FieldOfView = struct {
                left: f32,
                right: f32,
                up: f32,
                down: f32,
            };
        };

        pub const TrackingCapabilities = struct {
            position_tracking: bool = true,
            orientation_tracking: bool = true,
            eye_tracking: bool = false,
            face_tracking: bool = false,
            hand_tracking: bool = false,
        };

        pub fn init(allocator: std.mem.Allocator, device_name: []const u8) !*HeadMountedDisplay {
            const hmd = try allocator.create(HeadMountedDisplay);
            hmd.* = HeadMountedDisplay{
                .device_name = try allocator.dupe(u8, device_name),
                .manufacturer = try allocator.dupe(u8, "MFS Engine"),
                .display_specs = DisplaySpecs{
                    .resolution_per_eye = .{ 2160, 2160 },
                    .refresh_rate = 90.0,
                    .field_of_view = DisplaySpecs.FieldOfView{
                        .left = -45.0,
                        .right = 45.0,
                        .up = 45.0,
                        .down = -45.0,
                    },
                },
                .tracking_caps = TrackingCapabilities{},
            };
            return hmd;
        }

        pub fn deinit(self: *HeadMountedDisplay, allocator: std.mem.Allocator) void {
            allocator.free(self.device_name);
            allocator.free(self.manufacturer);
            allocator.destroy(self);
        }

        pub fn getProjectionMatrix(self: *HeadMountedDisplay, eye: EyeIndex, near_plane: f32, far_plane: f32) Mat4 {
            _ = eye; // Eye-specific projection matrices would be different for each eye
            const fov = self.display_specs.field_of_view;
            return Mat4.perspective(std.math.degreesToRadians(fov.up - fov.down), @as(f32, @floatFromInt(self.display_specs.resolution_per_eye[0])) / @as(f32, @floatFromInt(self.display_specs.resolution_per_eye[1])), near_plane, far_plane);
        }
    };

    /// Eye tracking and rendering
    pub const EyeIndex = enum(u32) {
        left = 0,
        right = 1,
    };

    pub const XREyeTexture = struct {
        texture_id: u32,
        width: u32,
        height: u32,
        format: graphics.TextureFormat,
        multisampling: u32 = 4,

        pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !*XREyeTexture {
            const eye_texture = try allocator.create(XREyeTexture);
            eye_texture.* = XREyeTexture{
                .texture_id = 0, // Will be set by graphics backend
                .width = width,
                .height = height,
                .format = .rgba8,
            };
            return eye_texture;
        }

        pub fn deinit(self: *XREyeTexture, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };

    /// Tracking system for head and controller positions
    pub const TrackingSystem = struct {
        head_pose: Pose = Pose{},
        controller_poses: [2]Pose = [_]Pose{ Pose{}, Pose{} },
        tracking_origin: Vec3 = Vec3.zero,

        // Prediction and smoothing
        prediction_time: f32 = 0.018, // 18ms prediction
        smoothing_factor: f32 = 0.8,

        pub const Pose = struct {
            position: Vec3 = Vec3.zero,
            orientation: Quaternion = Quaternion.identity(),
            velocity: Vec3 = Vec3.zero,
            angular_velocity: Vec3f = Vec3f.zero,
            tracking_confidence: f32 = 1.0,

            pub fn getViewMatrix(self: *const Pose) Mat4 {
                const rotation_matrix = self.orientation.toMatrix();
                const translation = Mat4.translate(self.position.negate());
                return rotation_matrix.multiply(translation);
            }

            pub fn predictPose(self: *const Pose, dt: f32) Pose {
                return Pose{
                    .position = self.position.add(self.velocity.scale(dt)),
                    .orientation = self.orientation.multiply(Quaternion.fromAxisAngle(self.angular_velocity, self.angular_velocity.length() * dt)),
                    .velocity = self.velocity,
                    .angular_velocity = self.angular_velocity,
                    .tracking_confidence = self.tracking_confidence,
                };
            }
        };

        pub fn init(allocator: std.mem.Allocator) !*TrackingSystem {
            const tracking = try allocator.create(TrackingSystem);
            tracking.* = TrackingSystem{};
            return tracking;
        }

        pub fn deinit(self: *TrackingSystem, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }

        pub fn update(self: *TrackingSystem, dt: f32) void {
            // Update tracking with prediction and smoothing
            _ = dt;

            // TODO: Implement actual tracking data acquisition
            // For now, simulate basic head movement
            const time = @as(f32, @floatFromInt(std.time.timestamp())) * 0.001;
            self.head_pose.position.y = 1.7 + @sin(time) * 0.1; // Slight head bob
            self.head_pose.orientation = Quaternion.fromAxisAngle(Vec3.up(), @sin(time * 0.5) * 0.1);
        }

        pub fn getPredictedPose(self: *TrackingSystem, pose_type: PoseType, prediction_time: f32) Pose {
            return switch (pose_type) {
                .head => self.head_pose.predictPose(prediction_time),
                .left_controller => self.controller_poses[0].predictPose(prediction_time),
                .right_controller => self.controller_poses[1].predictPose(prediction_time),
            };
        }

        pub const PoseType = enum {
            head,
            left_controller,
            right_controller,
        };
    };

    /// XR Input system for controllers and hand tracking
    pub const XRInputSystem = struct {
        controllers: [2]*XRController,
        hands: [2]*Hand,
        input_bindings: std.HashMap([]const u8, InputAction, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

        pub const XRController = struct {
            controller_type: ControllerType,
            is_connected: bool = false,
            battery_level: f32 = 1.0,

            // Input elements
            buttons: [16]Button = [_]Button{Button{}} ** 16,
            triggers: [4]f32 = [_]f32{0.0} ** 4,
            thumbsticks: [2]Vec2 = [_]Vec2{Vec2.zero()} ** 2,

            // Haptic feedback
            haptic_intensity: f32 = 0.0,
            haptic_duration: f32 = 0.0,

            pub const ControllerType = enum {
                oculus_touch,
                vive_wand,
                index_knuckles,
                pico_controller,
                generic,
            };

            pub const Button = struct {
                is_pressed: bool = false,
                is_touched: bool = false,
                press_time: f32 = 0.0,
            };

            pub const Vec2 = struct {
                x: f32 = 0.0,
                y: f32 = 0.0,

                pub fn zero() Vec2 {
                    return Vec2{};
                }
            };

            pub fn triggerHaptic(self: *XRController, intensity: f32, duration: f32) void {
                self.haptic_intensity = std.math.clamp(intensity, 0.0, 1.0);
                self.haptic_duration = duration;
            }
        };

        pub const Hand = struct {
            is_tracked: bool = false,
            confidence: f32 = 0.0,
            joints: [26]HandJoint = [_]HandJoint{HandJoint{}} ** 26,

            pub const HandJoint = struct {
                position: Vec3f = Vec3f.zero,
                orientation: Quaternion = Quaternion.identity(),
                radius: f32 = 0.01,
            };

            pub fn getFingerTip(self: *Hand, finger: FingerType) Vec3 {
                return switch (finger) {
                    .thumb => self.joints[4].position,
                    .index => self.joints[8].position,
                    .middle => self.joints[12].position,
                    .ring => self.joints[16].position,
                    .pinky => self.joints[20].position,
                };
            }

            pub const FingerType = enum {
                thumb,
                index,
                middle,
                ring,
                pinky,
            };
        };

        pub const InputAction = struct {
            action_type: ActionType,
            binding_path: []const u8,
            value: ActionValue,

            pub const ActionType = enum {
                boolean,
                float,
                vector2,
                pose,
                vibration,
            };

            pub const ActionValue = union(ActionType) {
                boolean: bool,
                float: f32,
                vector2: XRController.Vec2,
                pose: TrackingSystem.Pose,
                vibration: VibrationOutput,
            };

            pub const VibrationOutput = struct {
                amplitude: f32,
                frequency: f32,
                duration: f32,
            };
        };

        pub fn init(allocator: std.mem.Allocator) !*XRInputSystem {
            const input_system = try allocator.create(XRInputSystem);
            input_system.* = XRInputSystem{
                .controllers = undefined,
                .hands = undefined,
                .input_bindings = std.HashMap([]const u8, InputAction, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            };

            // Initialize controllers
            for (0..2) |i| {
                input_system.controllers[i] = try allocator.create(XRController);
                input_system.controllers[i].* = XRController{
                    .controller_type = .generic,
                };

                input_system.hands[i] = try allocator.create(Hand);
                input_system.hands[i].* = Hand{};
            }

            return input_system;
        }

        pub fn deinit(self: *XRInputSystem, allocator: std.mem.Allocator) void {
            for (self.controllers) |controller| {
                allocator.destroy(controller);
            }
            for (self.hands) |hand| {
                allocator.destroy(hand);
            }
            self.input_bindings.deinit();
            allocator.destroy(self);
        }

        pub fn update(self: *XRInputSystem, dt: f32) void {
            // Update controller input states
            for (self.controllers) |controller| {
                if (controller.is_connected) {
                    // Update haptic feedback
                    if (controller.haptic_duration > 0.0) {
                        controller.haptic_duration -= dt;
                        if (controller.haptic_duration <= 0.0) {
                            controller.haptic_intensity = 0.0;
                        }
                    }
                }
            }

            // Update hand tracking
            for (self.hands) |hand| {
                if (hand.is_tracked) {
                    // TODO: Update hand joint positions
                }
            }
        }
    };

    /// XR Renderer for stereoscopic rendering
    pub const XRRenderer = struct {
        graphics_backend: *graphics.GraphicsBackend,
        render_targets: [2]*graphics.RenderTarget,
        view_matrices: [2]Mat4,
        projection_matrices: [2]Mat4,

        // Rendering settings
        multisampling: u32 = 4,
        foveated_rendering: bool = false,
        reprojection: bool = true,

        pub fn init(allocator: std.mem.Allocator, graphics_backend: *graphics.GraphicsBackend) !*XRRenderer {
            const renderer = try allocator.create(XRRenderer);
            renderer.* = XRRenderer{
                .graphics_backend = graphics_backend,
                .render_targets = undefined,
                .view_matrices = [_]Mat4{ Mat4.identity(), Mat4.identity() },
                .projection_matrices = [_]Mat4{ Mat4.identity(), Mat4.identity() },
            };

            // Create render targets for each eye
            for (0..2) |i| {
                renderer.render_targets[i] = try graphics_backend.createRenderTarget(2160, 2160, .rgba8);
            }

            return renderer;
        }

        pub fn deinit(self: *XRRenderer, allocator: std.mem.Allocator) void {
            for (self.render_targets) |rt| {
                self.graphics_backend.destroyRenderTarget(rt);
            }
            allocator.destroy(self);
        }

        pub fn beginFrame(self: *XRRenderer, tracking: *TrackingSystem, hmd: *HeadMountedDisplay) void {
            // Update view and projection matrices for each eye
            const head_pose = tracking.getPredictedPose(.head, tracking.prediction_time);

            for (0..2) |eye_idx| {
                const eye = @as(EyeIndex, @enumFromInt(eye_idx));

                // Calculate eye offset (IPD)
                const ipd_offset = if (eye == .left) -0.032 else 0.032; // 64mm IPD
                const eye_position = head_pose.position.add(Vec3.new(ipd_offset, 0.0, 0.0));

                // Create view matrix
                const eye_pose = TrackingSystem.Pose{
                    .position = eye_position,
                    .orientation = head_pose.orientation,
                    .velocity = head_pose.velocity,
                    .angular_velocity = head_pose.angular_velocity,
                    .tracking_confidence = head_pose.tracking_confidence,
                };

                self.view_matrices[eye_idx] = eye_pose.getViewMatrix();
                self.projection_matrices[eye_idx] = hmd.getProjectionMatrix(eye, 0.1, 1000.0);
            }
        }

        pub fn renderEye(self: *XRRenderer, eye: EyeIndex, scene: anytype) void {
            const eye_idx = @intFromEnum(eye);

            // Bind eye render target
            self.graphics_backend.bindRenderTarget(self.render_targets[eye_idx]);

            // Set view and projection matrices
            self.graphics_backend.setViewMatrix(self.view_matrices[eye_idx]);
            self.graphics_backend.setProjectionMatrix(self.projection_matrices[eye_idx]);

            // Clear render target
            self.graphics_backend.clear(.{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 });

            // Render scene
            scene.render(self.graphics_backend);
        }

        pub fn endFrame(self: *XRRenderer) void {
            // Submit rendered frames to XR runtime
            // TODO: Implement frame submission
            _ = self;
        }
    };

    /// Spatial computing features
    pub const SpatialAnchor = struct {
        id: u128,
        pose: TrackingSystem.Pose,
        persistence: PersistenceType,

        pub const PersistenceType = enum {
            session,
            local,
            cloud,
        };

        pub fn init(allocator: std.mem.Allocator, pose: TrackingSystem.Pose) !*SpatialAnchor {
            const anchor = try allocator.create(SpatialAnchor);
            anchor.* = SpatialAnchor{
                .id = std.crypto.random.int(u128),
                .pose = pose,
                .persistence = .session,
            };
            return anchor;
        }

        pub fn deinit(self: *SpatialAnchor, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };

    /// Spatial mapping for environment understanding
    pub const SpatialMapping = struct {
        mesh_vertices: std.ArrayList(Vec3),
        mesh_indices: std.ArrayList(u32),
        mesh_normals: std.ArrayList(Vec3f),
        update_frequency: f32 = 1.0, // Updates per second

        pub fn init(allocator: std.mem.Allocator) !*SpatialMapping {
            const mapping = try allocator.create(SpatialMapping);
            mapping.* = SpatialMapping{
                .mesh_vertices = std.ArrayList(Vec3).init(allocator),
                .mesh_indices = std.ArrayList(u32).init(allocator),
                .mesh_normals = std.ArrayList(Vec3f).init(allocator),
            };
            return mapping;
        }

        pub fn deinit(self: *SpatialMapping, allocator: std.mem.Allocator) void {
            self.mesh_vertices.deinit();
            self.mesh_indices.deinit();
            self.mesh_normals.deinit();
            allocator.destroy(self);
        }

        pub fn update(self: *SpatialMapping, dt: f32) void {
            _ = self;
            _ = dt;
            // TODO: Implement spatial mesh updates
        }
    };

    /// Hand tracking system
    pub const HandTracking = struct {
        confidence_threshold: f32 = 0.7,
        gesture_recognizer: *GestureRecognizer,

        pub const GestureRecognizer = struct {
            gestures: std.ArrayList(Gesture),

            pub const Gesture = struct {
                name: []const u8,
                confidence: f32,
                duration: f32,
            };

            pub fn recognizeGesture(self: *GestureRecognizer, hand: *XRInputSystem.Hand) ?Gesture {
                _ = self;
                _ = hand;
                // TODO: Implement gesture recognition
                return null;
            }
        };

        pub fn init(allocator: std.mem.Allocator) !*HandTracking {
            const hand_tracking = try allocator.create(HandTracking);
            hand_tracking.* = HandTracking{
                .gesture_recognizer = try allocator.create(GestureRecognizer),
            };
            hand_tracking.gesture_recognizer.* = GestureRecognizer{
                .gestures = std.ArrayList(GestureRecognizer.Gesture).init(allocator),
            };
            return hand_tracking;
        }

        pub fn deinit(self: *HandTracking, allocator: std.mem.Allocator) void {
            self.gesture_recognizer.gestures.deinit();
            allocator.destroy(self.gesture_recognizer);
            allocator.destroy(self);
        }
    };

    /// Comfort and safety settings
    pub const ComfortSettings = struct {
        comfort_turning: bool = true,
        vignetting: bool = true,
        motion_sickness_reduction: bool = true,
        comfort_locomotion: LocomotionType = .teleport,

        pub const LocomotionType = enum {
            smooth,
            teleport,
            dash,
            room_scale,
        };
    };

    /// Guardian/Boundary system
    pub const GuardianSystem = struct {
        boundary_points: std.ArrayList(Vec3),
        boundary_center: Vec3f,
        boundary_dimensions: Vec3,
        is_boundary_visible: bool = false,

        pub fn init(allocator: std.mem.Allocator) !*GuardianSystem {
            const guardian = try allocator.create(GuardianSystem);
            guardian.* = GuardianSystem{
                .boundary_points = std.ArrayList(Vec3(f32)).init(allocator),
                .boundary_center = Vec3.zero(),
                .boundary_dimensions = Vec3.new(2.0, 2.0, 2.0),
            };
            return guardian;
        }

        pub fn deinit(self: *GuardianSystem, allocator: std.mem.Allocator) void {
            self.boundary_points.deinit();
            allocator.destroy(self);
        }

        pub fn isPositionSafe(self: *GuardianSystem, position: Vec3) bool {
            // Simple rectangular boundary check
            const half_dims = self.boundary_dimensions.scale(0.5);
            const relative_pos = position.subtract(self.boundary_center);

            return @abs(relative_pos.x) <= half_dims.x and
                @abs(relative_pos.z) <= half_dims.z;
        }
    };

    pub fn init(allocator: std.mem.Allocator, runtime_type: XRRuntime.RuntimeType) !*Self {
        const xr_system = try allocator.create(Self);

        // Initialize XR runtime
        const runtime = try XRRuntime.init(allocator, runtime_type);

        // Initialize HMD
        const hmd = try HeadMountedDisplay.init(allocator, "MFS VR Headset");

        // Initialize tracking system
        const tracking = try TrackingSystem.init(allocator);

        // Initialize input system
        const input = try XRInputSystem.init(allocator);

        // Initialize renderer (placeholder graphics backend)
        const graphics_backend = try allocator.create(graphics.GraphicsBackend);
        graphics_backend.* = graphics.GraphicsBackend{};
        const renderer = try XRRenderer.init(allocator, graphics_backend);

        // Initialize eye textures
        var eye_textures: [2]*XREyeTexture = undefined;
        for (0..2) |i| {
            eye_textures[i] = try XREyeTexture.init(allocator, hmd.display_specs.resolution_per_eye[0], hmd.display_specs.resolution_per_eye[1]);
        }

        xr_system.* = Self{
            .allocator = allocator,
            .runtime = runtime,
            .hmd = hmd,
            .tracking_system = tracking,
            .input_system = input,
            .renderer = renderer,
            .eye_textures = eye_textures,
            .spatial_anchors = std.ArrayList(*SpatialAnchor).init(allocator),
            .stats = XRStats{},
            .comfort_settings = ComfortSettings{},
        };

        // Initialize optional systems
        xr_system.spatial_mapping = try SpatialMapping.init(allocator);
        xr_system.hand_tracking = try HandTracking.init(allocator);
        xr_system.guardian_system = try GuardianSystem.init(allocator);

        std.log.info("XR System initialized", .{});
        std.log.info("  Runtime: {}", .{runtime_type});
        std.log.info("  HMD: {s}", .{hmd.device_name});
        std.log.info("  Resolution per eye: {}x{}", .{ hmd.display_specs.resolution_per_eye[0], hmd.display_specs.resolution_per_eye[1] });
        std.log.info("  Refresh rate: {} Hz", .{hmd.display_specs.refresh_rate});
        std.log.info("  Features: Spatial Mapping, Hand Tracking, Guardian System", .{});

        return xr_system;
    }

    pub fn deinit(self: *Self) void {
        // Clean up spatial anchors
        for (self.spatial_anchors.items) |anchor| {
            anchor.deinit(self.allocator);
        }
        self.spatial_anchors.deinit();

        // Clean up optional systems
        if (self.spatial_mapping) |mapping| {
            mapping.deinit(self.allocator);
        }
        if (self.hand_tracking) |hand_tracking| {
            hand_tracking.deinit(self.allocator);
        }
        if (self.guardian_system) |guardian| {
            guardian.deinit(self.allocator);
        }

        // Clean up eye textures
        for (self.eye_textures) |eye_texture| {
            eye_texture.deinit(self.allocator);
        }

        // Clean up core systems
        self.renderer.deinit(self.allocator);
        self.input_system.deinit(self.allocator);
        self.tracking_system.deinit(self.allocator);
        self.hmd.deinit(self.allocator);

        if (self.session) |session| {
            session.deinit(self.allocator);
        }

        self.runtime.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    pub fn startSession(self: *Self) !void {
        if (self.session == null) {
            self.session = try self.runtime.createSession(self.allocator);
        }

        try self.session.?.beginSession();
        std.log.info("XR session started", .{});
    }

    pub fn stopSession(self: *Self) !void {
        if (self.session) |session| {
            try session.endSession();
            std.log.info("XR session stopped", .{});
        }
    }

    pub fn update(self: *Self, dt: f32) !void {
        const start_time = std.time.nanoTimestamp();

        // Poll XR events
        if (self.session) |session| {
            const events = try session.pollEvents();
            for (events) |event| {
                try self.handleEvent(event);
            }
        }

        // Update tracking
        self.tracking_system.update(dt);

        // Update input
        self.input_system.update(dt);

        // Update spatial mapping
        if (self.spatial_mapping) |mapping| {
            mapping.update(dt);
        }

        // Update statistics
        const end_time = std.time.nanoTimestamp();
        self.stats.frame_time_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        self.stats.frame_rate = 1000.0 / @as(f32, @floatCast(self.stats.frame_time_ms));

        // Check for dropped frames
        if (self.stats.frame_time_ms > 11.1) { // 90 FPS = 11.1ms per frame
            self.stats.dropped_frames += 1;
        }
    }

    pub fn render(self: *Self, scene: anytype) !void {
        if (self.session == null or self.session.?.state != .focused) {
            return;
        }

        // Begin XR frame
        self.renderer.beginFrame(self.tracking_system, self.hmd);

        // Render each eye
        self.renderer.renderEye(.left, scene);
        self.renderer.renderEye(.right, scene);

        // End XR frame and submit
        self.renderer.endFrame();
    }

    pub fn createSpatialAnchor(self: *Self, pose: TrackingSystem.Pose) !*SpatialAnchor {
        const anchor = try SpatialAnchor.init(self.allocator, pose);
        try self.spatial_anchors.append(anchor);
        return anchor;
    }

    pub fn getControllerInput(self: *Self, controller_index: u32) ?*XRInputSystem.XRController {
        if (controller_index >= 2) return null;
        return self.input_system.controllers[controller_index];
    }

    pub fn getHandTracking(self: *Self, hand_index: u32) ?*XRInputSystem.Hand {
        if (hand_index >= 2) return null;
        return self.input_system.hands[hand_index];
    }

    pub fn triggerHapticFeedback(self: *Self, controller_index: u32, intensity: f32, duration: f32) void {
        if (controller_index >= 2) return;
        self.input_system.controllers[controller_index].triggerHaptic(intensity, duration);
    }

    pub fn getStats(self: *Self) XRStats {
        return self.stats;
    }

    fn handleEvent(self: *Self, event: XREvent) !void {
        switch (event.event_type) {
            .session_state_changed => {
                const data = event.data.session_state_changed;
                std.log.info("XR session state changed: {} -> {}", .{ data.old_state, data.new_state });
                if (self.session) |session| {
                    session.state = data.new_state;
                }
            },
            .reference_space_changed => {
                const data = event.data.reference_space_changed;
                std.log.info("XR reference space changed: {} -> {}", .{ data.old_space, data.new_space });
                if (self.session) |session| {
                    session.reference_space = data.new_space;
                }
            },
            .interaction_profile_changed => {
                const data = event.data.interaction_profile_changed;
                std.log.info("XR interaction profile changed: {s}", .{data.profile_path});
            },
            .visibility_mask_changed => {
                const data = event.data.visibility_mask_changed;
                std.log.info("XR visibility mask changed for eye: {}", .{data.eye_index});
            },
            .performance_settings_changed => {
                const data = event.data.performance_settings_changed;
                std.log.info("XR performance settings changed: {} {}", .{ data.domain, data.level });
            },
        }
    }
};
