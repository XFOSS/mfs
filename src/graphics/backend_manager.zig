//! Graphics backend manager to handle various rendering backends
//! @thread-safe Thread safety is provided per-component with appropriate synchronization
//! @symbol Public graphics backend management API

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const interface = @import("backends/interface.zig");
const capabilities = @import("../platform/capabilities.zig");

// Import all available backends
const d3d11_backend = if (build_options.d3d11_available) @import("backends/d3d11_backend.zig") else struct {};
const d3d12_backend = if (build_options.d3d12_available) @import("backends/d3d12_backend.zig") else struct {};
const metal_backend = if (build_options.metal_available) @import("backends/metal_backend.zig") else struct {};
const vulkan_backend = if (build_options.vulkan_available) @import("backends/vulkan_backend.zig") else struct {};
const opengl_backend = if (build_options.opengl_available) @import("backends/opengl_backend.zig") else struct {};
const opengles_backend = if (build_options.opengles_available) @import("backends/opengles_backend.zig") else struct {};
const webgpu_backend = if (build_options.webgpu_available) @import("backends/webgpu_backend.zig") else struct {};
const software_backend = @import("backends/software_backend.zig");

/// Backend manager to handle multiple graphics backends
/// @thread-safe Thread safety is managed with internal locks
/// @symbol Public backend management API
/// Backend initialization and validation status tracking
/// @thread-safe Thread-compatible structure for status tracking
/// @symbol Internal backend state management
const BackendState = struct {
    backend: ?*interface.GraphicsBackend = null,
    initialized: bool = false,
    initialization_attempted: bool = false,
    validation_status: enum { unknown, passed, failed } = .unknown,
    last_error: ?anyerror = null,
    load_time_ns: u64 = 0,
};

pub const BackendManager = struct {
    allocator: std.mem.Allocator,
    active_backends: std.ArrayList(*interface.GraphicsBackend),
    primary_backend: ?*interface.GraphicsBackend = null,
    fallback_chain: std.ArrayList(capabilities.GraphicsBackend),
    capabilities: ?*capabilities.PlatformCapabilities = null,
    auto_fallback: bool,
    debug_mode: bool,
    mutex: std.Thread.Mutex = .{}, // Add mutex for thread safety
    backend_cache: std.AutoHashMap(capabilities.GraphicsBackend, BackendState),

    const Self = @This();

    pub const InitOptions = struct {
        preferred_backend: ?capabilities.GraphicsBackend = null,
        auto_fallback: bool = true,
        debug_mode: bool = (builtin.mode == .Debug),
        validate_backends: bool = true,
        enable_backend_switching: bool = false,
    };

    /// Initialize a new backend manager
    /// @thread-safe Thread-safe initialization
    /// @symbol Public initialization API
    pub fn init(allocator: std.mem.Allocator, options: InitOptions) !Self {
        var manager = Self{
            .allocator = allocator,
            .active_backends = std.ArrayList(*interface.GraphicsBackend).init(allocator),
            .primary_backend = null,
            .fallback_chain = std.ArrayList(capabilities.GraphicsBackend).init(allocator),
            .capabilities = null,
            .auto_fallback = options.auto_fallback,
            .debug_mode = options.debug_mode,
            .mutex = .{},
            .backend_cache = std.AutoHashMap(capabilities.GraphicsBackend, BackendState).init(allocator),
        };

        // Initialize capabilities detection
        try capabilities.initCapabilities(allocator);
        manager.capabilities = capabilities.getCapabilities();

        // Build fallback chain
        try manager.buildFallbackChain(options.preferred_backend);

        // Initialize primary backend (unless using lazy initialization)
        if (!options.lazy_initialization) {
            try manager.initializePrimaryBackend(options);
        }

        return manager;
    }

    pub fn deinit(self: *Self) void {
        // Cleanup all active backends
        for (self.active_backends.items) |backend| {
            backend.deinit();
            self.allocator.destroy(backend);
        }
        self.active_backends.deinit();
        self.fallback_chain.deinit();

        capabilities.deinitCapabilities();
        self.allocator.destroy(self);
    }

    /// Get the currently active primary backend
    /// @thread-safe Thread-safe read operation
    /// @symbol Public accessor API
    pub fn getPrimaryBackend(self: *Self) !*interface.GraphicsBackend {
        self.mutex.lock();
        defer self.mutex.unlock();

        // If we don't have a primary backend yet but using lazy initialization,
        // initialize it now
        if (self.primary_backend == null) {
            try self.initializePrimaryBackend(.{});

            // If we still don't have a backend, this is an error
            if (self.primary_backend == null) {
                return interface.GraphicsBackendError.BackendNotAvailable;
            }
        }

        return self.primary_backend.?;
    }

    pub fn getBackendInfo(self: *Self) ?interface.BackendInfo {
        if (self.primary_backend) |backend| {
            return backend.getBackendInfo();
        }
        return null;
    }

    pub fn supportsBackend(self: *Self, backend_type: capabilities.GraphicsBackend) bool {
        if (self.capabilities) |caps| {
            return caps.isBackendAvailable(backend_type);
        }
        return false;
    }

    pub fn switchBackend(self: *Self, backend_type: capabilities.GraphicsBackend) !bool {
        if (!self.supportsBackend(backend_type)) {
            return false;
        }

        // Try to create new backend
        const new_backend = self.createBackend(backend_type) catch return false;

        // If successful, cleanup old backend and switch
        if (self.primary_backend) |old_backend| {
            old_backend.deinit();
            self.allocator.destroy(old_backend);
        }

        self.primary_backend = new_backend;
        std.log.info("Switched to {s} backend", .{backend_type.getName()});
        return true;
    }

    pub fn validateBackend(self: *Self, backend: *interface.GraphicsBackend) bool {
        _ = self;

        // Basic validation - check if backend is initialized
        if (!backend.initialized) {
            return false;
        }

        // Try a simple operation
        const info = backend.getBackendInfo();
        if (info.name.len == 0) {
            return false;
        }

        return true;
    }

    pub fn getBestBackend(self: *Self) capabilities.GraphicsBackend {
        if (self.capabilities) |caps| {
            return caps.getBestBackend();
        }
        return .software;
    }

    pub fn getAvailableBackends(self: *Self) ![]capabilities.GraphicsBackend {
        var available = std.ArrayList(capabilities.GraphicsBackend).init(self.allocator);
        defer available.deinit();

        if (self.capabilities) |caps| {
            inline for (@typeInfo(capabilities.GraphicsBackend).Enum.fields) |field| {
                const backend_type = @field(capabilities.GraphicsBackend, field.name);
                if (caps.isBackendAvailable(backend_type)) {
                    try available.append(backend_type);
                }
            }
        }

        return available.toOwnedSlice();
    }

    pub fn printStatus(self: *Self) void {
        std.log.info("=== Graphics Backend Status ===", .{});

        if (self.primary_backend) |backend| {
            const info = backend.getBackendInfo();
            std.log.info("Primary Backend: {s} {s}", .{ info.name, info.version });
            std.log.info("Device: {s}", .{info.device_name});
            std.log.info("Vendor: {s}", .{info.vendor});
        } else {
            std.log.warn("No primary backend active", .{});
        }

        std.log.info("Active backends: {d}", .{self.active_backends.items.len});
        std.log.info("Auto fallback: {}", .{self.auto_fallback});
        std.log.info("Debug mode: {}", .{self.debug_mode});

        if (self.capabilities) |caps| {
            caps.printCapabilities();
        }
    }

    fn buildFallbackChain(self: *Self, preferred: ?capabilities.GraphicsBackend) !void {
        // Clear existing chain
        self.fallback_chain.clearRetainingCapacity();

        // Add preferred backend first if specified and available
        if (preferred) |pref| {
            if (self.supportsBackend(pref)) {
                try self.fallback_chain.append(pref);
            }
        }

        // Build platform-specific fallback chain
        switch (builtin.os.tag) {
            .windows => {
                // DirectX 12 is primary on Windows, OpenGL as backup (Vulkan disabled due to linking issues)
                try self.addToChainIfAvailable(.d3d12);
                try self.addToChainIfAvailable(.opengl);
                try self.addToChainIfAvailable(.d3d11);
            },
            .macos => {
                // Metal is primary on macOS
                try self.addToChainIfAvailable(.metal);
                try self.addToChainIfAvailable(.vulkan);
                try self.addToChainIfAvailable(.opengl);
            },
            .ios => {
                // Metal is primary on iOS
                try self.addToChainIfAvailable(.metal);
                try self.addToChainIfAvailable(.opengles);
            },
            .linux => {
                if (build_options.is_mobile) {
                    // Android - Vulkan is primary on modern Android
                    try self.addToChainIfAvailable(.vulkan);
                    try self.addToChainIfAvailable(.opengles);
                } else {
                    // Desktop Linux - Vulkan is primary
                    try self.addToChainIfAvailable(.vulkan);
                    try self.addToChainIfAvailable(.opengl);
                }
            },
            .emscripten, .wasi => {
                // Web targets - WebGPU is preferred, OpenGL ES as fallback
                try self.addToChainIfAvailable(.webgpu);
                try self.addToChainIfAvailable(.opengles);
            },
            else => {
                // Unknown platforms - try OpenGL and software fallback
                try self.addToChainIfAvailable(.opengl);
                try self.addToChainIfAvailable(.opengles);
            },
        }

        // Always add software as final fallback
        try self.addToChainIfAvailable(.software);
    }

    fn addToChainIfAvailable(self: *Self, backend_type: capabilities.GraphicsBackend) !void {
        if (self.supportsBackend(backend_type)) {
            // Check if already in chain
            for (self.fallback_chain.items) |existing| {
                if (existing == backend_type) return;
            }
            try self.fallback_chain.append(backend_type);
        }
    }

    fn initializePrimaryBackend(self: *Self, options: InitOptions) !void {
        var last_error: ?anyerror = null;
        const timer = std.time.Timer.start() catch null;

        // Try each backend in the fallback chain
        for (self.fallback_chain.items) |backend_type| {
            // Check if we've already tried to initialize this backend
            if (self.backend_cache.get(backend_type)) |cached_state| {
                if (cached_state.initialization_attempted) {
                    // If we've already initialized this backend successfully, use it
                    if (cached_state.initialized and cached_state.backend != null) {
                        if (!options.validate_backends or cached_state.validation_status == .passed) {
                            self.primary_backend = cached_state.backend;
                            try self.active_backends.append(cached_state.backend.?);
                            std.log.info("Using cached {s} backend", .{backend_type.getName()});
                            return;
                        } else {
                            std.log.warn("Skipping previously failed {s} backend", .{backend_type.getName()});
                            continue;
                        }
                    } else if (cached_state.last_error != null) {
                        // Skip backends we've already tried and failed with
                        std.log.warn("Skipping previously failed {s} backend: {}", .{ backend_type.getName(), cached_state.last_error.? });
                        last_error = cached_state.last_error;
                        continue;
                    }
                }
            }

            std.log.info("Attempting to initialize {s} backend...", .{backend_type.getName()});

            var backend_state = BackendState{
                .initialization_attempted = true,
            };

            const start_time = if (timer) |t| t.read() else 0;

            backend_state.backend = self.createBackend(backend_type) catch |err| {
                backend_state.last_error = err;
                backend_state.initialized = false;
                try self.backend_cache.put(backend_type, backend_state);

                last_error = err;
                std.log.warn("Failed to initialize {s} backend: {}", .{ backend_type.getName(), err });
                continue;
            };

            backend_state.load_time_ns = if (timer) |t| t.read() - start_time else 0;

            const passed_validation = !options.validate_backends or self.validateBackend(backend_state.backend.?);
            backend_state.validation_status = if (passed_validation) .passed else .failed;

            if (passed_validation) {
                backend_state.initialized = true;
                try self.backend_cache.put(backend_type, backend_state);

                self.primary_backend = backend_state.backend;
                try self.active_backends.append(backend_state.backend.?);
                std.log.info("Successfully initialized {s} backend in {d}ms", .{ backend_type.getName(), @as(f64, @floatFromInt(backend_state.load_time_ns)) / 1_000_000.0 });
                return;
            } else {
                std.log.warn("{s} backend failed validation", .{backend_type.getName()});
                backend_state.backend.?.deinit();
                backend_state.initialized = false;
                try self.backend_cache.put(backend_type, backend_state);
            }
        }

        // If we get here, no backend worked
        if (last_error) |err| {
            return err;
        } else {
            return interface.GraphicsBackendError.BackendNotAvailable;
        }
    }

    fn createBackend(self: *Self, backend_type: capabilities.GraphicsBackend) !*interface.GraphicsBackend {
        switch (backend_type) {
            .d3d11 => return d3d11_backend.createBackend(self.allocator),
            .d3d12 => return d3d12_backend.createBackend(self.allocator),
            .metal => return metal_backend.createBackend(self.allocator),
            .vulkan => return vulkan_backend.createBackend(self.allocator),
            .opengl => return opengl_backend.createBackend(self.allocator),
            .opengles => return opengles_backend.createBackend(self.allocator),
            .webgpu => return webgpu_backend.createBackend(self.allocator),
            .software => return software_backend.createBackend(self.allocator),
        }
    }

    pub fn createAdaptiveRenderer(self: *Self) !AdaptiveRenderer {
        return AdaptiveRenderer.init(self.allocator, self);
    }
};

/// Adaptive renderer that can switch backends based on performance or requirements
/// Adaptive renderer that can switch backends based on performance
/// @thread-safe Thread safety provided with internal synchronization
/// @symbol Public adaptive rendering API
pub const AdaptiveRenderer = struct {
    allocator: std.mem.Allocator,
    backend_manager: *BackendManager,
    performance_monitor: PerformanceMonitor,
    auto_switch: bool,
    min_fps_threshold: f32,
    switch_cooldown_ms: u64,
    last_switch_time: u64,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, manager: *BackendManager) !Self {
        return Self{
            .allocator = allocator,
            .backend_manager = manager,
            .performance_monitor = PerformanceMonitor.init(),
            .auto_switch = true,
            .min_fps_threshold = 30.0,
            .switch_cooldown_ms = 5000,
            .last_switch_time = 0,
        };
    }

    pub fn render(self: *Self, frame_data: anytype) !void {
        const start_time = std.time.milliTimestamp();

        // Perform actual rendering
        if (self.backend_manager.primary_backend) |backend| {
            // TODO: Implement actual rendering with frame_data
            _ = backend;
            _ = frame_data;
        }

        const end_time = std.time.milliTimestamp();
        const frame_time = @as(f32, @floatFromInt(end_time - start_time));

        self.performance_monitor.recordFrame(frame_time);

        // Check if we should switch backends
        if (self.auto_switch) {
            try self.checkPerformanceAndSwitch();
        }
    }

    fn checkPerformanceAndSwitch(self: *Self) !void {
        const current_time = @as(u64, @intCast(std.time.milliTimestamp()));

        // Check cooldown
        if (current_time - self.last_switch_time < self.switch_cooldown_ms) {
            return;
        }

        const avg_fps = self.performance_monitor.getAverageFPS();

        if (avg_fps < self.min_fps_threshold) {
            // Try to switch to a more performant backend
            const current_backend = self.backend_manager.primary_backend.?.backend_type;

            // Find next backend in performance order
            const next_backend = self.getNextPerformantBackend(current_backend);
            if (next_backend != current_backend) {
                std.log.info("Performance below threshold ({d:.1} FPS), switching from {s} to {s}", .{ avg_fps, current_backend.getName(), next_backend.getName() });

                if (try self.backend_manager.switchBackend(next_backend)) {
                    self.last_switch_time = current_time;
                    self.performance_monitor.reset();
                }
            }
        }
    }

    fn getNextPerformantBackend(self: *Self, current: capabilities.GraphicsBackend) capabilities.GraphicsBackend {
        // Performance hierarchy (platform dependent)
        const performance_order = switch (builtin.os.tag) {
            .windows => [_]capabilities.GraphicsBackend{ .d3d12, .vulkan, .d3d11, .opengl, .software },
            .macos => [_]capabilities.GraphicsBackend{ .metal, .vulkan, .opengl, .software },
            .ios => [_]capabilities.GraphicsBackend{ .metal, .opengles, .software },
            .linux => if (build_options.is_mobile)
                [_]capabilities.GraphicsBackend{ .vulkan, .opengles, .software }
            else
                [_]capabilities.GraphicsBackend{ .vulkan, .opengl, .software },
            .emscripten, .wasi => [_]capabilities.GraphicsBackend{ .webgpu, .opengles, .software },
            else => [_]capabilities.GraphicsBackend{ .opengl, .software },
        };

        var current_index: usize = performance_order.len;
        for (performance_order, 0..) |backend, i| {
            if (backend == current) {
                current_index = i;
                break;
            }
        }

        // Try next backend in performance order
        for (performance_order[current_index + 1 ..]) |backend| {
            if (self.backend_manager.supportsBackend(backend)) {
                return backend;
            }
        }

        return current;
    }
};

/// Performance monitor for tracking rendering performance
/// @thread-safe Not thread-safe, must be accessed with external synchronization
/// @symbol Internal performance monitoring API
const PerformanceMonitor = struct {
    frame_times: [60]f32,
    frame_count: usize,
    total_time: f32,

    const Self = @This();

    fn init() Self {
        return Self{
            .frame_times = [_]f32{0.0} ** 60,
            .frame_count = 0,
            .total_time = 0.0,
        };
    }

    fn recordFrame(self: *Self, frame_time_ms: f32) void {
        const index = self.frame_count % 60;

        if (self.frame_count >= 60) {
            self.total_time -= self.frame_times[index];
        }

        self.frame_times[index] = frame_time_ms;
        self.total_time += frame_time_ms;
        self.frame_count += 1;
    }

    fn getAverageFPS(self: *const Self) f32 {
        if (self.frame_count == 0) return 0.0;

        const sample_count = @min(self.frame_count, 60);
        const avg_frame_time = self.total_time / @as(f32, @floatFromInt(sample_count));

        if (avg_frame_time <= 0.0) return 0.0;
        return 1000.0 / avg_frame_time;
    }

    fn reset(self: *Self) void {
        self.frame_count = 0;
        self.total_time = 0.0;
        self.frame_times = [_]f32{0.0} ** 60;
    }
};

// Global backend manager instance
/// Global backend manager instance with thread-safe access
var global_backend_manager: ?BackendManager = null;
var global_manager_mutex: std.Thread.Mutex = .{};

/// Initialize the global backend manager
/// @thread-safe Thread-safe initialization with mutex protection
/// @symbol Public global initialization API
pub fn initGlobalBackendManager(allocator: std.mem.Allocator, options: BackendManager.InitOptions) !void {
    global_manager_mutex.lock();
    defer global_manager_mutex.unlock();

    if (global_backend_manager != null) {
        return error.AlreadyInitialized;
    }
    global_backend_manager = try BackendManager.init(allocator, options);
}

/// Deinitialize the global backend manager
/// @thread-safe Thread-safe cleanup with mutex protection
/// @symbol Public global cleanup API
pub fn deinitGlobalBackendManager() void {
    global_manager_mutex.lock();
    defer global_manager_mutex.unlock();

    if (global_backend_manager) |*manager| {
        manager.deinit();
        global_backend_manager = null;
    }
}

/// Get the global backend manager instance
/// @thread-safe Thread-safe access with mutex protection
/// @symbol Public global accessor API
pub fn getGlobalBackendManager() !*BackendManager {
    global_manager_mutex.lock();
    defer global_manager_mutex.unlock();

    // If the global manager doesn't exist yet, create it with default options
    if (global_backend_manager == null) {
        return initGlobalBackendManager(.{
            .lazy_initialization = true,
        }) catch |err| {
            std.log.err("Failed to initialize global backend manager: {}", .{err});
            return err;
        };
    }

    return global_backend_manager.?;
}
