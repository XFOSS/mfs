//! Metal backend implementation for macOS and iOS using the Metal API
const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const interface = @import("interface.zig");
const types = @import("../types.zig");
const common = @import("common.zig");

/// Metal backend is only available on macOS and iOS
const is_metal_platform = (builtin.os.tag == .macos or builtin.os.tag == .ios);

// Check for Apple Silicon architecture
const is_apple_silicon = (builtin.cpu.arch == .aarch64) and
    (builtin.os.tag == .macos or builtin.os.tag == .ios);

// Define all Metal and related frameworks
// Function pointer types for Metal API
const MTLCreateSystemDefaultDeviceFn = *const fn () callconv(.C) ?*anyopaque;
const MTKViewClassFn = *const fn () callconv(.C) ?*anyopaque;

const MetalFramework = struct {
    handle: ?std.DynLib = null,
    metalkit_handle: ?std.DynLib = null,
    accelerate_handle: ?std.DynLib = null, // For vector/math optimizations
    core_image_handle: ?std.DynLib = null, // For image processing

    // Function pointers
    createSystemDefaultDevice: ?MTLCreateSystemDefaultDeviceFn = null,
    mtkViewClass: ?MTKViewClassFn = null,

    fn load() !MetalFramework {
        var framework = MetalFramework{};

        if (!is_metal_platform) {
            return error.UnsupportedPlatform;
        }

        // Load Metal framework
        const metal_path = if (builtin.os.tag == .macos)
            "/System/Library/Frameworks/Metal.framework/Metal"
        else
            "/System/Library/Frameworks/Metal.framework/Metal";

        framework.handle = std.DynLib.open(metal_path) catch |err| {
            std.log.err("Failed to open Metal framework: {}", .{err});
            return error.FrameworkLoadFailed;
        };

        // Load MetalKit framework
        const metalkit_path = if (builtin.os.tag == .macos)
            "/System/Library/Frameworks/MetalKit.framework/MetalKit"
        else
            "/System/Library/Frameworks/MetalKit.framework/MetalKit";

        framework.metalkit_handle = std.DynLib.open(metalkit_path) catch |err| {
            std.log.err("Failed to open MetalKit framework: {}", .{err});
            // Non-critical, continue without MetalKit
        };

        // Load Accelerate framework for performance optimizations
        const accelerate_path = if (builtin.os.tag == .macos)
            "/System/Library/Frameworks/Accelerate.framework/Accelerate"
        else
            "/System/Library/Frameworks/Accelerate.framework/Accelerate";

        framework.accelerate_handle = std.DynLib.open(accelerate_path) catch |err| {
            std.log.err("Failed to open Accelerate framework: {}", .{err});
            // Non-critical, continue without Accelerate
        };

        // Load function pointers
        framework.createSystemDefaultDevice = @ptrCast(framework.handle.?.lookup("MTLCreateSystemDefaultDevice") orelse {
            std.log.err("Failed to load MTLCreateSystemDefaultDevice", .{});
            return error.SymbolLookupFailed;
        });

        // Load MetalKit functions (optional)
        if (framework.metalkit_handle) |handle| {
            framework.mtkViewClass = @ptrCast(handle.lookup("MTKViewClass") orelse {
                std.log.warn("Failed to load MTKViewClass, MetalKit view features will be unavailable", .{});
                // Non-critical, continue without MTKView support
            });
        }

        return framework;
    }

    fn close(self: *MetalFramework) void {
        if (self.core_image_handle) |handle| {
            handle.close();
            self.core_image_handle = null;
        }

        if (self.accelerate_handle) |handle| {
            handle.close();
            self.accelerate_handle = null;
        }

        if (self.metalkit_handle) |handle| {
            handle.close();
            self.metalkit_handle = null;
        }

        if (self.handle) |handle| {
            handle.close();
            self.handle = null;
        }

        self.createSystemDefaultDevice = null;
        self.mtkViewClass = null;
    }
};

// Metal frameworks
var metal_framework: ?MetalFramework = null;

const c = if (is_metal_platform)
blk: {
    break :blk @cImport({
        // Core Metal frameworks
        @cInclude("Metal/Metal.h");
        @cInclude("MetalKit/MetalKit.h");
        @cInclude("QuartzCore/CAMetalLayer.h");

        // Additional Apple frameworks for GPU optimizations
        @cInclude("MetalPerformanceShaders/MetalPerformanceShaders.h");

        // For computational tasks
        @cInclude("Accelerate/Accelerate.h");

        // For image processing
        @cInclude("CoreImage/CoreImage.h");

        // Platform-specific includes
        if (builtin.os.tag == .macos) {
            @cInclude("Cocoa/Cocoa.h");
            @cInclude("AppKit/AppKit.h"); // For NSView
        } else if (builtin.os.tag == .ios) {
            @cInclude("UIKit/UIKit.h");
        }

        // Objective-C runtime for better interop
        @cInclude("objc/runtime.h");
        @cInclude("objc/message.h");
    });
} else struct {};

/// Metal backend implementation
pub const MetalBackend = struct {
    allocator: std.mem.Allocator,
    device: ?*c.MTLDevice = null,
    command_queue: ?*c.MTLCommandQueue = null,
    layer: ?*c.CAMetalLayer = null,
    mtkview: ?*c.MTKView = null, // Added MTKView support
    current_drawable: ?*c.CAMetalDrawable = null,
    depth_stencil_texture: ?*c.MTLTexture = null,
    render_pass_descriptor: ?*c.MTLRenderPassDescriptor = null,
    library: ?*c.MTLLibrary = null,
    command_buffer: ?*c.MTLCommandBuffer = null,
    render_encoder: ?*c.MTLRenderCommandEncoder = null,
    compute_encoder: ?*c.MTLComputeCommandEncoder = null,
    blit_encoder: ?*c.MTLBlitCommandEncoder = null,
    width: u32 = 0,
    height: u32 = 0,
    pixel_format: c.MTLPixelFormat = c.MTLPixelFormatBGRA8Unorm,
    sample_count: u32 = 1,
    vsync: bool = true,
    initialized: bool = false,
    loaded_libraries: std.StringHashMap(*c.MTLLibrary),
    is_apple_silicon: bool = false,

    // Metal Performance Shaders (MPS)
    mps_image_library: ?*anyopaque = null,

    // CoreImage integration
    ci_context: ?*anyopaque = null,

    const Self = @This();

    /// Virtual function table for the graphics backend interface
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

    /// Create and initialize a Metal backend, returning a pointer to the interface.GraphicsBackend
    pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        if (!build_options.metal_available) {
            return error.BackendNotAvailable;
        }
        if (!is_metal_platform) {
            return error.BackendNotAvailable;
        }

        // Initialize metal framework if not already loaded
        if (metal_framework == null) {
            metal_framework = MetalFramework.load() catch |err| {
                std.log.err("Failed to load Metal framework: {}", .{err});
                return error.BackendNotAvailable;
            };
        }

        const backend = try allocator.create(Self);
        errdefer allocator.destroy(backend);

        backend.* = Self{
            .allocator = allocator,
            .loaded_libraries = std.StringHashMap(*c.MTLLibrary).init(allocator),
            .is_apple_silicon = is_apple_silicon,
        };

        try backend.initializeDevice();

        // Initialize Metal Performance Shaders if available
        if (backend.device != null) {
            backend.initializeMetalPerformanceShaders();
            backend.initializeCoreImage();
        }

        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .metal,
            .vtable = &vtable,
            .impl_data = backend,
            .initialized = true,
        };

        return graphics_backend;
    }

    /// Initialize Metal Performance Shaders
    fn initializeMetalPerformanceShaders(self: *Self) void {
        if (builtin.os.tag == .macos or builtin.os.tag == .ios) {
            // Check if MPS is supported on this device
            if (c.MPSSupportsMTLDevice(self.device.?)) {
                // Initialize MPS image processing library (if needed)
                self.mps_image_library = c.MPSImageKernel.alloc().init();
                std.log.info("Metal Performance Shaders (MPS) initialized successfully", .{});
            } else {
                std.log.warn("Metal Performance Shaders not supported on this device", .{});
            }
        }
    }

    /// Initialize CoreImage integration
    fn initializeCoreImage(self: *Self) void {
        if (builtin.os.tag == .macos or builtin.os.tag == .ios) {
            // Create Core Image context backed by Metal
            const options = c.NSDictionary.dictionary();
            self.ci_context = c.CIContext.contextWithMTLDevice(self.device.?, options);
            if (self.ci_context != null) {
                std.log.info("CoreImage context created successfully", .{});
            }
        }
    }

    /// Initialize Metal device and supporting objects
    fn initializeDevice(self: *Self) !void {
        // Try to get preferred device with better performance characteristics
        if (is_apple_silicon) {
            // On Apple Silicon we prefer the Apple GPU
            const devices = c.MTLCopyAllDevices();
            if (devices != null) {
                const count = c.NSArray.count(devices);
                var best_device: ?*c.MTLDevice = null;
                var highest_perf_score: u32 = 0;

                for (0..count) |i| {
                    const device = @as(*c.MTLDevice, @ptrCast(c.NSArray.objectAtIndex(devices, i)));

                    // Check if this is Apple GPU
                    const is_low_power = c.MTLDevice.isLowPower(device);
                    const perf_score = c.MTLDevice.recommendedMaxWorkingSetSize(device) >> 20; // Rough estimate based on memory

                    if (is_low_power and perf_score > highest_perf_score) {
                        best_device = device;
                        highest_perf_score = perf_score;
                    }
                }

                if (best_device != null) {
                    self.device = best_device;
                    std.log.info("Selected Apple GPU with performance score: {}", .{highest_perf_score});
                }
            }
        }

        // Fall back to default device if we couldn't select one above
        if (self.device == null) {
            // Create Metal device using dynamically loaded function if available
            if (metal_framework != null and metal_framework.?.createSystemDefaultDevice != null) {
                self.device = @ptrCast(metal_framework.?.createSystemDefaultDevice.?());
            } else {
                // Fallback to static linking
                self.device = c.MTLCreateSystemDefaultDevice();
            }
        }

        if (self.device == null) {
            std.log.err("Failed to create Metal device - Metal may not be supported on this system", .{});
            return error.DeviceCreationFailed;
        }

        // Create command queue with optimizations for Apple Silicon
        if (self.is_apple_silicon) {
            // On Apple Silicon, create optimized command queue with larger capacity
            self.command_queue = c.MTLDevice.newCommandQueueWithMaxCommandBufferCount(self.device.?, 64);
        } else {
            // Standard command queue
            self.command_queue = c.MTLDevice.newCommandQueue(self.device.?);
        }

        if (self.command_queue == null) {
            std.log.err("Failed to create Metal command queue", .{});
            return error.InitializationFailed;
        }

        // Create default library (contains built-in shaders)
        self.library = c.MTLDevice.newDefaultLibrary(self.device.?);

        // Create render pass descriptor
        self.render_pass_descriptor = c.MTLRenderPassDescriptor.renderPassDescriptor();
        if (self.render_pass_descriptor == null) {
            std.log.err("Failed to create Metal render pass descriptor", .{});
            return error.InitializationFailed;
        }

        self.initialized = true;
        std.log.info("Metal backend initialized successfully", .{});

        // Log detailed device info
        if (self.device) |device| {
            const device_name = c.MTLDevice.name(device);
            if (device_name != null) {
                const name_str = c.NSString.UTF8String(device_name);
                std.log.info("Metal device: {s}", .{name_str});
            }

            // Log additional device capabilities
            if (builtin.os.tag == .macos) {
                const supports_unified_memory = c.MTLDevice.hasUnifiedMemory(device);
                std.log.info("Unified memory support: {}", .{supports_unified_memory});

                if (c.MTLDevice.respondsToSelector(device, c.sel_getUid("supportsFamily:"))) {
                    const supports_apple3 = c.MTLDevice.supportsFamily(device, c.MTLGPUFamilyApple3);
                    const supports_mac2 = c.MTLDevice.supportsFamily(device, c.MTLGPUFamilyMac2);

                    std.log.info("Apple GPU Family 3 support: {}", .{supports_apple3});
                    std.log.info("Mac GPU Family 2 support: {}", .{supports_mac2});
                }

                if (self.is_apple_silicon) {
                    std.log.info("Running on Apple Silicon - enabling advanced optimizations", .{});

                    // Check for additional Apple Silicon optimizations
                    if (c.MTLDevice.respondsToSelector(device, c.sel_getUid("supportsBCTextureCompression"))) {
                        const supports_bc = c.MTLDevice.supportsBCTextureCompression(device);
                        std.log.info("BC texture compression support: {}", .{supports_bc});
                    }
                }
            }
        }
    }

    /// Load a Metal library from a file using MetalKit's convenience methods
    pub fn loadLibraryFromFile(self: *Self, path: []const u8) !*c.MTLLibrary {
        if (!self.initialized) {
            return error.InvalidOperation;
        }

        // Check if we've already loaded this library
        if (self.loaded_libraries.get(path)) |lib| {
            return lib;
        }

        // Create a URL for the file
        const path_z = try std.fmt.allocPrintZ(self.allocator, "{s}", .{path});
        defer self.allocator.free(path_z);

        const url_string = c.NSString.stringWithUTF8String(path_z.ptr);
        if (url_string == null) {
            return error.ResourceCreationFailed;
        }

        const url = c.NSURL.fileURLWithPath(url_string);
        if (url == null) {
            return error.ResourceCreationFailed;
        }

        // Try using MTKMetalLibrary convenience method first (if available)
        var library: ?*c.MTLLibrary = null;
        var err: ?*c.NSError = null;

        if (c.MTKCreateMetalLibraryWithURL != null) {
            library = c.MTKCreateMetalLibraryWithURL(self.device.?, url, &err);
        }

        // Fall back to standard method if MTK method failed or is unavailable
        if (library == null) {
            library = c.MTLDevice.newLibraryWithURL(self.device.?, url, &err);
        }

        if (library == null or err != null) {
            if (err != null) {
                const error_desc = c.NSError.localizedDescription(err.?);
                if (error_desc != null) {
                    const error_string = c.NSString.UTF8String(error_desc);
                    if (error_string != null) {
                        std.log.err("Failed to load Metal library: {s}", .{error_string});
                    }
                }
            }
            return error.ResourceCreationFailed;
        }

        // Store the library in our cache
        try self.loaded_libraries.put(path, library.?);

        return library.?;
    }

    /// Compile and load a Metal library from source code
    pub fn loadLibraryFromSource(self: *Self, source: []const u8, name: []const u8) !*c.MTLLibrary {
        if (!self.initialized) {
            return error.InvalidOperation;
        }

        // Check if we've already loaded this library by name
        if (self.loaded_libraries.get(name)) |lib| {
            return lib;
        }

        // Create null-terminated string for source
        const source_z = try std.fmt.allocPrintZ(self.allocator, "{s}", .{source});
        defer self.allocator.free(source_z);

        const source_string = c.NSString.stringWithUTF8String(source_z.ptr);
        if (source_string == null) {
            return error.ResourceCreationFailed;
        }

        // Set up optimization options based on hardware
        const compiler_options: ?*c.MTLCompileOptions = c.MTLCompileOptions.alloc().init();
        if (compiler_options != null) {
            // Set language version to latest available
            c.MTLCompileOptions.setLanguageVersion(compiler_options.?, c.MTLLanguageVersion2_4);

            // Enable preprocessor macros
            const defines_dict = c.NSMutableDictionary.dictionary();

            // Add platform-specific defines
            if (self.is_apple_silicon) {
                const value = c.NSNumber.numberWithBool(true);
                const key = c.NSString.stringWithUTF8String("APPLE_SILICON");
                c.NSMutableDictionary.setObjectForKey(defines_dict, value, key);
            }

            c.MTLCompileOptions.setPreprocessorMacros(compiler_options.?, defines_dict);

            if (self.is_apple_silicon) {
                // Enable fastest optimization level for Apple Silicon
                c.MTLCompileOptions.setFastMathEnabled(compiler_options.?, true);
                c.MTLCompileOptions.setOptimizationLevel(compiler_options.?, c.MTLLibraryOptimizationLevelDefault);
            }
        }

        // Try to use MetalKit's shader compilation if available
        var library: ?*c.MTLLibrary = null;
        var compile_error: ?*c.NSError = null;

        if (c.MTKCreateMetalLibraryWithSource != null) {
            library = c.MTKCreateMetalLibraryWithSource(self.device.?, source_string, compiler_options, &compile_error);
        } else {
            // Fall back to standard compilation
            library = c.MTLDevice.newLibraryWithSource(self.device.?, source_string, compiler_options, &compile_error);
        }

        if (library == null or compile_error != null) {
            if (compile_error) {
                const error_desc = c.NSError.localizedDescription(compile_error.?);
                if (error_desc) {
                    const error_string = c.NSString.UTF8String(error_desc);
                    if (error_string) {
                        std.log.err("Failed to compile Metal library: {s}", .{error_string});
                    }
                }
            }
            return error.ResourceCreationFailed;
        }

        // Store the library in our cache
        try self.loaded_libraries.put(name, library.?);

        return library.?;
    }

    /// Implementation of deinit interface
    fn deinitImpl(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.deinitInternal();
    }

    /// Internal method for resource cleanup
    fn deinitInternal(self: *Self) void {
        if (!self.initialized) return;

        // End any active encoders
        self.endAllEncoders();

        // Clear loaded libraries
        self.loaded_libraries.deinit();

        // Release CoreImage context
        if (self.ci_context != null) {
            c.objc_msgSend.?(self.ci_context, c.sel_getUid("release"));
            self.ci_context = null;
        }

        // Release MPS resources
        if (self.mps_image_library != null) {
            c.objc_msgSend.?(self.mps_image_library, c.sel_getUid("release"));
            self.mps_image_library = null;
        }

        // Clear all resources (Metal uses ARC for automatic cleanup)
        self.command_buffer = null;
        self.render_pass_descriptor = null;
        self.depth_stencil_texture = null;
        self.current_drawable = null;
        self.library = null;
        self.mtkview = null;
        self.layer = null;
        self.command_queue = null;
        self.device = null;

        // Close Metal framework if we opened it
        if (metal_framework) |*framework| {
            framework.close();
            metal_framework = null;
        }

        self.initialized = false;
        self.allocator.destroy(self);
    }

    /// End all active command encoders
    fn endAllEncoders(self: *Self) void {
        if (self.render_encoder) |encoder| {
            c.MTLRenderCommandEncoder.endEncoding(encoder);
            self.render_encoder = null;
        }

        if (self.compute_encoder) |encoder| {
            c.MTLComputeCommandEncoder.endEncoding(encoder);
            self.compute_encoder = null;
        }

        if (self.blit_encoder) |encoder| {
            c.MTLBlitCommandEncoder.endEncoding(encoder);
            self.blit_encoder = null;
        }
    }

    /// Create swap chain with MetalKit view for best performance
    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!self.initialized) {
            return error.InvalidOperation;
        }

        if (desc.width == 0 or desc.height == 0) {
            return error.InvalidOperation;
        }

        self.width = desc.width;
        self.height = desc.height;
        self.vsync = desc.vsync;
        self.pixel_format = switch (desc.format) {
            .rgba8 => 70, // MTLPixelFormatRGBA8Unorm
            .rgb8 => 30, // MTLPixelFormatRGB8Unorm
            .bgra8 => 80, // MTLPixelFormatBGRA8Unorm
            .r8 => 10, // MTLPixelFormatR8Unorm
            .rg8 => 20, // MTLPixelFormatRG8Unorm
            .depth24_stencil8 => 255, // MTLPixelFormatDepth24Unorm_Stencil8
            .depth32f => 252, // MTLPixelFormatDepth32Float
        };

        // Try to create an MTKView if MetalKit is available
        var use_mtkview = false;

        if (c.MTKView.class() != null and desc.window_handle != 0) {
            // Create MTKView for optimal Metal rendering
            self.mtkview = c.MTKView.alloc().initWithFrameDevice(c.CGRectMake(0, 0, @floatFromInt(desc.width), @floatFromInt(desc.height)), self.device);

            if (self.mtkview != null) {
                use_mtkview = true;

                // Configure MTKView
                c.MTKView.setFramebufferOnly(self.mtkview.?, true);
                c.MTKView.setColorPixelFormat(self.mtkview.?, self.pixel_format);
                c.MTKView.setDepthStencilPixelFormat(self.mtkview.?, c.MTLPixelFormatDepth32Float);
                c.MTKView.setSampleCount(self.mtkview.?, 1);
                c.MTKView.setEnableSetNeedsDisplay(self.mtkview.?, false);
                c.MTKView.setPaused(self.mtkview.?, true); // We'll control drawing explicitly

                if (builtin.os.tag == .macos) {
                    const nsview = @as(*c.NSView, @ptrCast(self.mtkview));
                    const parent_view = @as(*c.NSView, @ptrFromInt(desc.window_handle));
                    c.NSView.addSubview(parent_view, nsview);
                } else if (builtin.os.tag == .ios) {
                    const uiview = @as(*c.UIView, @ptrCast(self.mtkview));
                    const parent_view = @as(*c.UIView, @ptrFromInt(desc.window_handle));
                    c.UIView.addSubview(parent_view, uiview);
                }

                // Get the layer from MTKView for direct access
                self.layer = @ptrCast(c.MTKView.layer(self.mtkview.?));
                std.log.info("Created MTKView for optimal Metal rendering", .{});
            }
        }

        // Fall back to CAMetalLayer if MTKView creation failed
        if (!use_mtkview) {
            // Create CAMetalLayer directly
            self.layer = c.CAMetalLayer.layer();
            if (self.layer == null) {
                return error.SwapChainCreationFailed;
            }

            c.CAMetalLayer.setDevice(self.layer.?, self.device.?);
            c.CAMetalLayer.setPixelFormat(self.layer.?, self.pixel_format);
            c.CAMetalLayer.setFramebufferOnly(self.layer.?, true);
            c.CAMetalLayer.setDrawableSize(self.layer.?, c.CGSize{ .width = @floatFromInt(desc.width), .height = @floatFromInt(desc.height) });

            // If we have a window handle, try to add the layer to it
            if (desc.window_handle != 0) {
                if (builtin.os.tag == .macos) {
                    const view = @as(*c.NSView, @ptrFromInt(desc.window_handle));
                    c.NSView.setWantsLayer(view, true);
                    c.NSView.setLayer(view, @ptrCast(self.layer));
                } else if (builtin.os.tag == .ios) {
                    const view = @as(*c.UIView, @ptrFromInt(desc.window_handle));
                    c.UIView.setLayer(view, @ptrCast(self.layer));
                }
            }

            std.log.info("Created CAMetalLayer for rendering", .{});
        }

        // Apple Silicon specific optimizations
        if (self.is_apple_silicon) {
            // Allow system to optimize resource allocation
            c.CAMetalLayer.setResourceOptions(self.layer.?, c.MTLResourceStorageModeShared);

            // Ensure Metal can optimize color space handling
            if (builtin.os.tag == .macos) {
                // Enable wide color and HDR when available
                c.CAMetalLayer.setWantsExtendedDynamicRangeContent(self.layer.?, true);
                c.CAMetalLayer.setColorspace(self.layer.?, c.CGColorSpaceCreateWithName(c.kCGColorSpaceExtendedSRGB));
            }
        }

        if (builtin.os.tag == .macos) {
            c.CAMetalLayer.setDisplaySyncEnabled(self.layer.?, desc.vsync);
        }

        try self.createDepthStencilTexture();
    }

    /// Create depth stencil texture for the current dimensions
    fn createDepthStencilTexture(self: *Self) !void {
        if (self.width == 0 or self.height == 0) {
            return error.InvalidOperation;
        }

        // If using MTKView, it manages its own depth buffer
        if (self.mtkview != null) {
            // For MTKView we use its built-in depth buffer
            return;
        }

        const depth_texture_desc = c.MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(c.MTLPixelFormatDepth32Float, self.width, self.height, false);

        c.MTLTextureDescriptor.setUsage(depth_texture_desc, c.MTLTextureUsageRenderTarget);

        // Use optimal storage mode based on architecture
        if (self.is_apple_silicon) {
            c.MTLTextureDescriptor.setStorageMode(depth_texture_desc, c.MTLStorageModeMemoryless);
        } else {
            c.MTLTextureDescriptor.setStorageMode(depth_texture_desc, c.MTLStorageModePrivate);
        }

        self.depth_stencil_texture = c.MTLDevice.newTextureWithDescriptor(self.device.?, depth_texture_desc);
        if (self.depth_stencil_texture == null) {
            return error.ResourceCreationFailed;
        }
    }

    /// Resize the swap chain to new dimensions
    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (width == 0 or height == 0) {
            return error.InvalidOperation;
        }

        self.width = width;
        self.height = height;

        // Resize MTKView if using it
        if (self.mtkview != null) {
            if (builtin.os.tag == .macos) {
                const nsview = @as(*c.NSView, @ptrCast(self.mtkview));
                c.NSView.setFrameSize(nsview, c.NSMakeSize(@floatFromInt(width), @floatFromInt(height)));
            } else if (builtin.os.tag == .ios) {
                const uiview = @as(*c.UIView, @ptrCast(self.mtkview));
                c.UIView.setFrame(uiview, c.CGRectMake(0, 0, @floatFromInt(width), @floatFromInt(height)));
            }
        }

        // Always update layer size regardless of whether using MTKView or CAMetalLayer directly
        if (self.layer != null) {
            c.CAMetalLayer.setDrawableSize(self.layer.?, c.CGSize{ .width = @floatFromInt(width), .height = @floatFromInt(height) });
        }

        // Recreate depth stencil texture with new dimensions
        if (self.mtkview == null) { // Only if not using MTKView
            self.depth_stencil_texture = null;
            try self.createDepthStencilTexture();
        }
    }

    /// Present the current drawable to screen
    fn presentImpl(impl: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.current_drawable != null and self.command_buffer != null) {
            if (self.is_apple_silicon) {
                // On Apple Silicon, schedule presentation with better synchronization
                c.MTLCommandBuffer.presentDrawableAtTime(self.command_buffer.?, self.current_drawable.?, c.CAMetalLayer.nextDrawableTime(self.layer.?));
            } else {
                c.MTLCommandBuffer.presentDrawable(self.command_buffer.?, self.current_drawable.?);
            }
            self.current_drawable = null;
        }
    }

    /// Get current back buffer texture
    fn getCurrentBackBufferImpl(impl: *anyopaque) !*types.Texture {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.mtkview != null) {
            // Get current drawable from MTKView
            self.current_drawable = c.MTKView.currentDrawable(self.mtkview.?);
        } else if (self.layer != null) {
            // Get drawable directly from CAMetalLayer
            self.current_drawable = c.CAMetalLayer.nextDrawable(self.layer.?);
        } else {
            return error.InvalidOperation;
        }

        if (self.current_drawable == null) {
            return error.ResourceCreationFailed;
        }

        const metal_texture = c.CAMetalDrawable.texture(self.current_drawable.?);
        if (metal_texture == null) {
            return error.ResourceCreationFailed;
        }

        const texture = try self.allocator.create(types.Texture);
        texture.* = types.Texture{
            .id = @intFromPtr(metal_texture),
            .width = self.width,
            .height = self.height,
            .depth = 1,
            .format = .bgra8,
            .texture_type = .texture_2d,
            .mip_levels = 1,
            .allocator = self.allocator,
        };

        return texture;
    }

    /// Create a texture resource using optimized paths
    fn createTextureImpl(impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (texture.width == 0 or texture.height == 0) {
            return error.InvalidOperation;
        }

        if (self.device == null) {
            return error.InvalidOperation;
        }

        const metal_format = switch (texture.format) {
            .rgba8 => 70, // MTLPixelFormatRGBA8Unorm
            .rgb8 => 30, // MTLPixelFormatRGB8Unorm
            .bgra8 => 80, // MTLPixelFormatBGRA8Unorm
            .r8 => 10, // MTLPixelFormatR8Unorm
            .rg8 => 20, // MTLPixelFormatRG8Unorm
            .depth24_stencil8 => 255, // MTLPixelFormatDepth24Unorm_Stencil8
            .depth32f => 252, // MTLPixelFormatDepth32Float
        };

        const texture_desc = c.MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(metal_format, texture.width, texture.height, texture.mip_levels > 1);

        c.MTLTextureDescriptor.setMipmapLevelCount(texture_desc, texture.mip_levels);

        // Set texture type
        switch (texture.texture_type) {
            .texture_2d => c.MTLTextureDescriptor.setTextureType(texture_desc, c.MTLTextureType2D),
            .texture_cube => c.MTLTextureDescriptor.setTextureType(texture_desc, c.MTLTextureTypeCube),
            .texture_3d => c.MTLTextureDescriptor.setTextureType(texture_desc, c.MTLTextureType3D),
            .texture_array => c.MTLTextureDescriptor.setTextureType(texture_desc, c.MTLTextureType2DArray),
        }

        // Set usage flags for the texture
        c.MTLTextureDescriptor.setUsage(texture_desc, c.MTLTextureUsageShaderRead | c.MTLTextureUsageRenderTarget);

        // Optimize storage mode for the specific hardware
        if (self.is_apple_silicon) {
            // For textures with initial data, use shared mode for direct CPU access
            if (data != null) {
                c.MTLTextureDescriptor.setStorageMode(texture_desc, c.MTLStorageModeShared);
            } else {
                // For render targets or GPU-only textures, use private for best performance
                c.MTLTextureDescriptor.setStorageMode(texture_desc, c.MTLStorageModePrivate);

                // On Apple GPUs, we can enable specific optimizations
                c.MTLTextureDescriptor.setResourceOptions(texture_desc, c.MTLResourceStorageModePrivate | c.MTLResourceHazardTrackingModeTracked);
            }
        }

        // Create the texture using the descriptor
        var metal_texture: ?*c.MTLTexture = null;

        // Use MetalKit's texture loader if we have initial data (better optimization)
        if (data != null and c.MTKTextureLoader.class() != null) {
            const loader = c.MTKTextureLoader.alloc().initWithDevice(self.device.?);
            if (loader != null) {
                defer c.MTKTextureLoader.release(loader);

                // Create texture options dictionary
                const options_dict = c.NSDictionary.dictionary();

                // Create an NSData object from our data slice
                const ns_data = c.NSData.dataWithBytes(data.?.ptr, data.?.len);
                if (ns_data != null) {
                    var compile_error: ?*c.NSError = null;
                    metal_texture = c.MTKTextureLoader.newTextureWithData(loader, ns_data, options_dict, &compile_error);

                    if (metal_texture == null and compile_error != null) {
                        const error_desc = c.NSError.localizedDescription(compile_error.?);
                        if (error_desc) {
                            const error_string = c.NSString.UTF8String(error_desc);
                            std.log.err("Failed to load texture with MTKTextureLoader: {s}", .{error_string});
                        }
                    }
                }
            }
        }

        // Fall back to standard texture creation if MTKTextureLoader failed or wasn't available
        if (metal_texture == null) {
            metal_texture = c.MTLDevice.newTextureWithDescriptor(self.device.?, texture_desc);
        }

        if (metal_texture == null) {
            return error.ResourceCreationFailed;
        }

        texture.id = @intFromPtr(metal_texture);

        // Upload initial data if provided and we didn't use MTKTextureLoader
        if (data != null and !c.MTKTextureLoader.class() != null) {
            const bytes_per_pixel = switch (texture.format) {
                .rgba8 => 4,
                .rgb8 => 3,
                .bgra8 => 4,
                .r8 => 1,
                .rg8 => 2,
                .depth24_stencil8 => 4,
                .depth32f => 4,
            };
            const bytes_per_row = texture.width * bytes_per_pixel;
            const expected_size = bytes_per_row * texture.height;

            if (data.?.len < expected_size) {
                std.log.err("Texture data size mismatch: expected {}, got {}", .{ expected_size, data.?.len });
                return error.InvalidOperation;
            }

            const region = c.MTLRegion{
                .origin = c.MTLOrigin{ .x = 0, .y = 0, .z = 0 },
                .size = c.MTLSize{ .width = texture.width, .height = texture.height, .depth = 1 },
            };

            c.MTLTexture.replaceRegion(metal_texture, region, 0, data.?.ptr, bytes_per_row);
        }
    }

    /// Create a buffer resource
    fn createBufferImpl(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (buffer.size == 0) {
            return error.InvalidOperation;
        }

        if (self.device == null) {
            return error.InvalidOperation;
        }

        var options = getMetalResourceOptions(buffer.usage);

        // Apply Apple Silicon specific optimizations
        if (self.is_apple_silicon) {
            // For storage buffers on Apple Silicon, use private storage with hazard tracking disabled
            if (buffer.usage == .storage) {
                options |= c.MTLResourceHazardTrackingModeUntracked;
            } else if (buffer.usage == .uniform) {
                // Apple Silicon can use specialized memory for uniform buffers
                options |= c.MTLResourceCPUCacheModeWriteCombined;
            }
        }

        var metal_buffer: ?*c.MTLBuffer = null;

        if (data) |buffer_data| {
            if (buffer_data.len > buffer.size) {
                return error.InvalidOperation;
            }
            metal_buffer = c.MTLDevice.newBufferWithBytes(self.device.?, buffer_data.ptr, buffer_data.len, options);
        } else {
            metal_buffer = c.MTLDevice.newBufferWithLength(self.device.?, buffer.size, options);
        }

        if (metal_buffer == null) {
            return error.ResourceCreationFailed;
        }

        buffer.id = @intFromPtr(metal_buffer);
    }

    /// Get Metal resource options based on buffer usage
    fn getMetalResourceOptions(usage: types.BufferUsage) c.MTLResourceOptions {
        return switch (usage) {
            .vertex, .index => c.MTLResourceStorageModeShared,
            .uniform => c.MTLResourceStorageModeShared | c.MTLResourceCPUCacheModeWriteCombined,
            .storage => c.MTLResourceStorageModePrivate,
            .staging => c.MTLResourceStorageModeShared | c.MTLResourceCPUCacheModeDefaultCache,
        };
    }

    /// Create a shader from source code
    fn createShaderImpl(impl: *anyopaque, shader: *types.Shader) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (shader.source.len == 0) {
            return error.InvalidOperation;
        }

        if (self.device == null) {
            return error.InvalidOperation;
        }

        // Create null-terminated string for C API
        const null_terminated_source = std.fmt.allocPrintZ(self.allocator, "{s}", .{shader.source}) catch {
            return error.ResourceCreationFailed;
        };
        defer self.allocator.free(null_terminated_source);

        // Create NSString from shader source
        const source_string = c.NSString.stringWithUTF8String(null_terminated_source.ptr);
        if (source_string == null) {
            return error.ResourceCreationFailed;
        }

        // Set up shader compilation options
        const compiler_options: ?*c.MTLCompileOptions = c.MTLCompileOptions.alloc().init();
        if (compiler_options != null) {
            // Set language version to latest
            c.MTLCompileOptions.setLanguageVersion(compiler_options.?, c.MTLLanguageVersion2_4);

            // Add platform defines
            const defines_dict = c.NSMutableDictionary.dictionary();
            if (self.is_apple_silicon) {
                const value = c.NSNumber.numberWithBool(true);
                const key = c.NSString.stringWithUTF8String("APPLE_SILICON");
                c.NSMutableDictionary.setObjectForKey(defines_dict, value, key);
            }
            c.MTLCompileOptions.setPreprocessorMacros(compiler_options.?, defines_dict);

            if (self.is_apple_silicon) {
                // Enable optimizations for Apple Silicon
                c.MTLCompileOptions.setFastMathEnabled(compiler_options.?, true);
                c.MTLCompileOptions.setOptimizationLevel(compiler_options.?, c.MTLLibraryOptimizationLevelDefault);
            }
        }

        // Compile library from source
        var compilation_error: ?*c.NSError = null;
        const shader_library = c.MTLDevice.newLibraryWithSource(self.device.?, source_string, compiler_options, &compilation_error);

        if (shader_library == null or compilation_error != null) {
            if (compilation_error != null) {
                const error_desc = c.NSError.localizedDescription(compilation_error.?);
                if (error_desc != null) {
                    const error_string = c.NSString.UTF8String(error_desc);
                    if (error_string != null) {
                        std.log.err("Metal shader compilation failed: {s}", .{error_string});
                    }
                }
            }
            return error.ResourceCreationFailed;
        }

        // Get function by entry point name
        const entry_point = if (shader.entry_point.len > 0) shader.entry_point else "main";
        const entry_point_z = std.fmt.allocPrintZ(self.allocator, "{s}", .{entry_point}) catch {
            return error.ResourceCreationFailed;
        };
        defer self.allocator.free(entry_point_z);

        const function_name = c.NSString.stringWithUTF8String(entry_point_z.ptr);
        const metal_function = c.MTLLibrary.newFunctionWithName(shader_library, function_name);

        if (metal_function == null) {
            std.log.err("Failed to find shader function '{s}'", .{entry_point});
            return error.ResourceCreationFailed;
        }

        shader.id = @intFromPtr(metal_function);
        shader.compiled = true;
    }

    /// Create a graphics pipeline
    fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) !*interface.Pipeline {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device == null) {
            return error.InvalidOperation;
        }

        // Create render pipeline descriptor
        const pipeline_desc = c.MTLRenderPipelineDescriptor.renderPipelineDescriptor();
        if (pipeline_desc == null) {
            return error.ResourceCreationFailed;
        }

        // Set shaders if provided
        if (desc.vertex_shader) |vs| {
            const metal_function: *c.MTLFunction = @ptrFromInt(vs.id);
            c.MTLRenderPipelineDescriptor.setVertexFunction(pipeline_desc, metal_function);
        }

        if (desc.fragment_shader) |fs| {
            const metal_function: *c.MTLFunction = @ptrFromInt(fs.id);
            c.MTLRenderPipelineDescriptor.setFragmentFunction(pipeline_desc, metal_function);
        }

        // Set color format
        const color_attachments = c.MTLRenderPipelineDescriptor.colorAttachments(pipeline_desc);
        const color_attachment = c.MTLRenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments, 0);
        c.MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment, self.pixel_format);

        // Set depth format
        if (self.mtkview != null) {
            c.MTLRenderPipelineDescriptor.setDepthAttachmentPixelFormat(pipeline_desc, c.MTKView.depthStencilPixelFormat(self.mtkview.?));
        } else {
            c.MTLRenderPipelineDescriptor.setDepthAttachmentPixelFormat(pipeline_desc, c.MTLPixelFormatDepth32Float);
        }

        // Set blending if needed
        if (desc.blend_enabled) {
            c.MTLRenderPipelineColorAttachmentDescriptor.setBlendingEnabled(color_attachment, true);

            // Set standard alpha blending
            c.MTLRenderPipelineColorAttachmentDescriptor.setSourceRGBBlendFactor(color_attachment, c.MTLBlendFactorSourceAlpha);
            c.MTLRenderPipelineColorAttachmentDescriptor.setDestinationRGBBlendFactor(color_attachment, c.MTLBlendFactorOneMinusSourceAlpha);
            c.MTLRenderPipelineColorAttachmentDescriptor.setRgbBlendOperation(color_attachment, c.MTLBlendOperationAdd);

            c.MTLRenderPipelineColorAttachmentDescriptor.setSourceAlphaBlendFactor(color_attachment, c.MTLBlendFactorSourceAlpha);
            c.MTLRenderPipelineColorAttachmentDescriptor.setDestinationAlphaBlendFactor(color_attachment, c.MTLBlendFactorOneMinusSourceAlpha);
            c.MTLRenderPipelineColorAttachmentDescriptor.setAlphaBlendOperation(color_attachment, c.MTLBlendOperationAdd);
        }

        // Apple Silicon specific optimizations
        if (self.is_apple_silicon) {
            // Support tile-based deferred rendering on Apple GPUs
            c.MTLRenderPipelineDescriptor.setSupportIndirectCommandBuffers(pipeline_desc, true);

            // Enable specialized hardware tessellation if available
            if (c.MTLDevice.supportsFeatureSet(self.device.?, c.MTLFeatureSet_macOS_GPUFamily2_v1)) {
                c.MTLRenderPipelineDescriptor.setMaxTessellationFactor(pipeline_desc, 16);
            }
        }

        // Create pipeline state
        var pipeline_error: ?*c.NSError = null;
        const metal_pipeline = c.MTLDevice.newRenderPipelineStateWithDescriptor(self.device.?, pipeline_desc, &pipeline_error);

        if (metal_pipeline == null or pipeline_error != null) {
            if (pipeline_error != null) {
                const error_desc = c.NSError.localizedDescription(pipeline_error.?);
                if (error_desc != null) {
                    const error_string = c.NSString.UTF8String(error_desc);
                    if (error_string != null) {
                        std.log.err("Metal pipeline creation failed: {s}", .{error_string});
                    }
                }
            }
            return error.ResourceCreationFailed;
        }

        const pipeline = try self.allocator.create(interface.Pipeline);
        pipeline.* = interface.Pipeline{
            .id = @intFromPtr(metal_pipeline),
            .backend_handle = undefined,
            .allocator = self.allocator,
        };

        return pipeline;
    }

    /// Create a render target (currently unsupported)
    fn createRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) !void {
        _ = impl;
        _ = render_target;
        return error.UnsupportedOperation;
    }

    /// Update buffer contents
    fn updateBufferImpl(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) !void {
        _ = impl;

        if (buffer.id == 0) {
            return error.InvalidOperation;
        }

        if (offset + data.len > buffer.size) {
            return error.InvalidOperation;
        }

        const metal_buffer: *c.MTLBuffer = @ptrFromInt(buffer.id);
        const contents = c.MTLBuffer.contents(metal_buffer);

        if (contents == null) {
            return error.InvalidOperation;
        }

        const dest_ptr: [*]u8 = @ptrCast(contents);
        const dest_slice = dest_ptr[offset .. offset + data.len];
        @memcpy(dest_slice, data);
    }

    /// Update texture contents
    fn updateTextureImpl(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) !void {
        _ = impl;

        if (texture.id == 0) {
            return error.InvalidOperation;
        }

        const metal_texture: *c.MTLTexture = @ptrFromInt(texture.id);
        const bytes_per_pixel = switch (texture.format) {
            .rgba8 => 4,
            .rgb8 => 3,
            .bgra8 => 4,
            .r8 => 1,
            .rg8 => 2,
            .depth24_stencil8 => 4,
            .depth32f => 4,
        };
        const bytes_per_row = region.extent[0] * bytes_per_pixel;
        const expected_size = bytes_per_row * region.extent[1] * region.extent[2];

        if (data.len < expected_size) {
            return error.InvalidOperation;
        }

        const metal_region = c.MTLRegion{
            .origin = c.MTLOrigin{ .x = region.dst_offset[0], .y = region.dst_offset[1], .z = region.dst_offset[2] },
            .size = c.MTLSize{ .width = region.extent[0], .height = region.extent[1], .depth = region.extent[2] },
        };

        c.MTLTexture.replaceRegion(metal_texture, metal_region, region.dst_mip_level, data.ptr, bytes_per_row);
    }

    /// Destroy a texture resource
    fn destroyTextureImpl(impl: *anyopaque, texture: *types.Texture) void {
        _ = impl;
        if (texture.id != 0) {
            // Metal uses ARC, so we don't need to manually release
            texture.id = 0;
        }
    }

    /// Destroy a buffer resource
    fn destroyBufferImpl(impl: *anyopaque, buffer: *types.Buffer) void {
        _ = impl;
        if (buffer.id != 0) {
            // Metal uses ARC, so we don't need to manually release
            buffer.id = 0;
        }
    }

    /// Destroy a shader resource
    fn destroyShaderImpl(impl: *anyopaque, shader: *types.Shader) void {
        _ = impl;
        if (shader.id != 0) {
            // Metal uses ARC, so we don't need to manually release
            shader.id = 0;
        }
    }

    /// Destroy a render target
    fn destroyRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) void {
        _ = impl;
        _ = render_target;
    }

    /// Create a command buffer
    fn createCommandBufferImpl(impl: *anyopaque) !*interface.CommandBuffer {
        const self: *Self = @ptrCast(@alignCast(impl));

        const cmd = try self.allocator.create(interface.CommandBuffer);
        cmd.* = interface.CommandBuffer{
            .id = 0,
            .backend_handle = undefined,
            .allocator = self.allocator,
        };

        return cmd;
    }

    /// Begin recording commands to a command buffer
    fn beginCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.command_queue == null) {
            return error.InvalidOperation;
        }

        // If using MTKView, get its command buffer
        if (self.mtkview != null and c.MTKView.currentRenderPassDescriptor(self.mtkview.?) != null) {
            // Use the render pass descriptor from MTKView
            self.render_pass_descriptor = c.MTKView.currentRenderPassDescriptor(self.mtkview.?);
        }

        // Create a new command buffer
        self.command_buffer = c.MTLCommandQueue.commandBuffer(self.command_queue.?);
        if (self.command_buffer == null) {
            return error.CommandSubmissionFailed;
        }

        // Set a debug label for the command buffer
        const cmd_label = c.NSString.stringWithUTF8String("Main command buffer");
        if (cmd_label != null) {
            c.MTLCommandBuffer.setLabel(self.command_buffer.?, cmd_label);
        }

        cmd.recording = true;
    }

    /// End command buffer recording
    fn endCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) !void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // End any active encoders
        self.endAllEncoders();
        cmd.recording = false;
    }

    /// Submit a command buffer for execution
    fn submitCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.command_buffer != null) {
            // On Apple Silicon, use optimized commit
            if (self.is_apple_silicon) {
                // Add completion handler for better performance tracking
                c.MTLCommandBuffer.addCompletedHandler(self.command_buffer.?, @ptrCast(&finishExecutionHandler));
            }

            c.MTLCommandBuffer.commit(self.command_buffer.?);

            // If we're using MTKView, signal that we're done drawing this frame
            if (self.mtkview != null) {
                c.MTKView.draw(self.mtkview.?);
            }

            self.command_buffer = null;
        }
    }

    // Callback for command buffer completion
    fn finishExecutionHandler(command_buffer: ?*c.MTLCommandBuffer) callconv(.C) void {
        if (command_buffer != null) {
            const status = c.MTLCommandBuffer.status(command_buffer.?);
            if (status == c.MTLCommandBufferStatusError) {
                const compile_error = c.MTLCommandBuffer.get_error(command_buffer.?);
                if (compile_error != null) {
                    const desc = c.NSError.localizedDescription(compile_error.?);
                    if (desc != null) {
                        const err_str = c.NSString.UTF8String(desc);
                        std.log.err("Command buffer execution failed: {s}", .{err_str});
                    }
                }
            }
        }
    }
    /// Begin a render pass
    fn beginRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.command_buffer == null) {
            return error.InvalidOperation;
        }

        // Always end any active encoders before starting a new render pass
        self.endAllEncoders();

        // Get the appropriate render pass descriptor
        var render_pass_desc: ?*c.MTLRenderPassDescriptor = null;

        // If using MTKView, use its render pass descriptor (optimized path)
        if (self.mtkview != null) {
            render_pass_desc = c.MTKView.currentRenderPassDescriptor(self.mtkview.?);
            if (render_pass_desc == null) {
                std.log.warn("Failed to get render pass descriptor from MTKView", .{});
                return error.ResourceCreationFailed;
            }
        } else if (self.render_pass_descriptor != null) {
            render_pass_desc = self.render_pass_descriptor;
        } else {
            std.log.err("No render pass descriptor available", .{});
            return error.InvalidOperation;
        }

        // Set up color attachment
        if (self.current_drawable != null) {
            const color_attachment = c.MTLRenderPassDescriptor.colorAttachments(render_pass_desc)[0];
            const drawable_texture = c.CAMetalDrawable.texture(self.current_drawable.?);

            c.MTLRenderPassColorAttachmentDescriptor.setTexture(color_attachment, drawable_texture);
            c.MTLRenderPassColorAttachmentDescriptor.setLoadAction(color_attachment, c.MTLLoadActionClear);
            c.MTLRenderPassColorAttachmentDescriptor.setStoreAction(color_attachment, c.MTLStoreActionStore);

            // Apply optimized store action for Apple Silicon (if applicable)
            if (self.is_apple_silicon) {
                c.MTLRenderPassColorAttachmentDescriptor.setStoreAction(color_attachment, c.MTLStoreActionStoreAndMultisampleResolve);
            }

            c.MTLRenderPassColorAttachmentDescriptor.setClearColor(color_attachment, c.MTLClearColor{
                .red = desc.clear_color.r,
                .green = desc.clear_color.g,
                .blue = desc.clear_color.b,
                .alpha = desc.clear_color.a,
            });
        }

        // Set up depth attachment
        const depth_attachment = c.MTLRenderPassDescriptor.depthAttachment(render_pass_desc);
        if (depth_attachment != null) {
            if (self.mtkview != null and c.MTKView.depthStencilTexture(self.mtkview.?) != null) {
                // Use MTKView's depth texture (optimal path)
                const depth_tex = c.MTKView.depthStencilTexture(self.mtkview.?);
                c.MTLRenderPassDepthAttachmentDescriptor.setTexture(depth_attachment, depth_tex);
            } else if (self.depth_stencil_texture != null) {
                // Use our custom depth texture
                c.MTLRenderPassDepthAttachmentDescriptor.setTexture(depth_attachment, self.depth_stencil_texture.?);
            }

            // Configure depth attachment
            c.MTLRenderPassDepthAttachmentDescriptor.setLoadAction(depth_attachment, c.MTLLoadActionClear);

            // For Apple Silicon, we can optimize memory usage with memoryless storage
            if (self.is_apple_silicon) {
                c.MTLRenderPassDepthAttachmentDescriptor.setStoreAction(depth_attachment, c.MTLStoreActionDontCare);
            } else {
                c.MTLRenderPassDepthAttachmentDescriptor.setStoreAction(depth_attachment, c.MTLStoreActionDontCare);
            }

            c.MTLRenderPassDepthAttachmentDescriptor.setClearDepth(depth_attachment, desc.clear_depth);
        }

        // Create the render command encoder
        self.render_encoder = c.MTLCommandBuffer.renderCommandEncoderWithDescriptor(self.command_buffer.?, render_pass_desc);

        if (self.render_encoder == null) {
            std.log.err("Failed to create Metal render encoder", .{});
            return error.CommandSubmissionFailed;
        }

        // Set debug label if enabled
        if (desc.label.len > 0) {
            const label = c.NSString.stringWithUTF8String(@ptrCast(desc.label.ptr));
            if (label != null) {
                c.MTLRenderCommandEncoder.setLabel(self.render_encoder.?, label);
            }
        }
    }

    /// End the current render pass
    fn endRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder != null) {
            c.MTLRenderCommandEncoder.endEncoding(self.render_encoder.?);
            self.render_encoder = null;
        }
    }

    /// Set viewport dimensions
    fn setViewportImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder == null) {
            return error.InvalidOperation;
        }

        const metal_viewport = c.MTLViewport{
            .originX = @floatFromInt(viewport.x),
            .originY = @floatFromInt(viewport.y),
            .width = @floatFromInt(viewport.width),
            .height = @floatFromInt(viewport.height),
            .znear = viewport.min_depth,
            .zfar = viewport.max_depth,
        };

        c.MTLRenderCommandEncoder.setViewport(self.render_encoder.?, metal_viewport);
    }

    /// Set scissor rectangle
    fn setScissorImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, scissor: *const types.Scissor) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder == null) {
            return error.InvalidOperation;
        }

        const metal_scissor = c.MTLScissorRect{
            .x = scissor.x,
            .y = scissor.y,
            .width = scissor.width,
            .height = scissor.height,
        };

        c.MTLRenderCommandEncoder.setScissorRect(self.render_encoder.?, metal_scissor);
    }

    /// Bind a pipeline state
    fn bindPipelineImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder == null) {
            return error.InvalidOperation;
        }

        if (pipeline.id == 0) {
            return error.InvalidOperation;
        }

        const metal_pipeline: *c.MTLRenderPipelineState = @ptrFromInt(pipeline.id);
        c.MTLRenderCommandEncoder.setRenderPipelineState(self.render_encoder.?, metal_pipeline);
    }

    /// Bind a vertex buffer
    fn bindVertexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, slot: u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder == null) {
            return error.InvalidOperation;
        }

        if (buffer.id == 0) {
            return error.InvalidOperation;
        }

        const metal_buffer: *c.MTLBuffer = @ptrFromInt(buffer.id);
        c.MTLRenderCommandEncoder.setVertexBuffer(self.render_encoder.?, metal_buffer, offset, slot);
    }

    /// Bind an index buffer
    fn bindIndexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        // Store index buffer info for later use in drawIndexed
        self.index_buffer = @ptrFromInt(buffer.id);
        self.index_buffer_offset = offset;

        // Infer index type based on usage hint or buffer stride if available
        if (buffer.element_size == 2 or buffer.stride == 2) {
            self.index_type = c.MTLIndexTypeUInt16;
        } else {
            self.index_type = c.MTLIndexTypeUInt32;
        }

        if (self.render_encoder == null) {
            return error.InvalidOperation;
        }
    }

    /// Bind a texture
    fn bindTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, texture: *types.Texture, slot: u32, shader_stage: types.ShaderStage) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder == null and shader_stage != .compute) {
            return error.InvalidOperation;
        }

        if (texture.id == 0) {
            return error.InvalidOperation;
        }

        const metal_texture: *c.MTLTexture = @ptrFromInt(texture.id);

        switch (shader_stage) {
            .vertex => c.MTLRenderCommandEncoder.setVertexTexture(self.render_encoder.?, metal_texture, slot),
            .fragment => c.MTLRenderCommandEncoder.setFragmentTexture(self.render_encoder.?, metal_texture, slot),
            .compute => {
                if (self.compute_encoder != null) {
                    c.MTLComputeCommandEncoder.setTexture(self.compute_encoder.?, metal_texture, slot);
                } else {
                    // Lazily create compute encoder if needed
                    if (self.command_buffer != null) {
                        self.compute_encoder = c.MTLCommandBuffer.computeCommandEncoder(self.command_buffer.?);
                        if (self.compute_encoder != null) {
                            c.MTLComputeCommandEncoder.setTexture(self.compute_encoder.?, metal_texture, slot);
                        }
                    }
                }
            },
        }
    }

    /// Bind a uniform buffer
    fn bindUniformBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, size: u64, slot: u32, shader_stage: types.ShaderStage) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;
        _ = size;

        if (buffer.id == 0) {
            return error.InvalidOperation;
        }

        const metal_buffer: *c.MTLBuffer = @ptrFromInt(buffer.id);

        switch (shader_stage) {
            .vertex => {
                if (self.render_encoder != null) {
                    c.MTLRenderCommandEncoder.setVertexBuffer(self.render_encoder.?, metal_buffer, offset, slot);
                } else {
                    return error.InvalidOperation;
                }
            },
            .fragment => {
                if (self.render_encoder != null) {
                    c.MTLRenderCommandEncoder.setFragmentBuffer(self.render_encoder.?, metal_buffer, offset, slot);
                } else {
                    return error.InvalidOperation;
                }
            },
            .compute => {
                if (self.compute_encoder != null) {
                    c.MTLComputeCommandEncoder.setBuffer(self.compute_encoder.?, metal_buffer, offset, slot);
                } else if (self.command_buffer != null) {
                    // Lazily create compute encoder if needed
                    self.compute_encoder = c.MTLCommandBuffer.computeCommandEncoder(self.command_buffer.?);
                    if (self.compute_encoder != null) {
                        c.MTLComputeCommandEncoder.setBuffer(self.compute_encoder.?, metal_buffer, offset, slot);
                    }
                } else {
                    return error.InvalidOperation;
                }
            },
        }
    }

    /// Draw primitives
    fn drawImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder == null) {
            return error.InvalidOperation;
        }

        c.MTLRenderCommandEncoder.drawPrimitives(self.render_encoder.?, c.MTLPrimitiveTypeTriangle, first_vertex, vertex_count, instance_count, first_instance);
    }

    /// Draw indexed primitives
    fn drawIndexedImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder == null) {
            return error.InvalidOperation;
        }

        if (self.index_buffer == null) {
            std.log.err("No index buffer bound for indexed draw call", .{});
            return error.InvalidOperation;
        }

        // Calculate actual buffer offset for first_index
        const index_size: u64 = if (self.index_type == c.MTLIndexTypeUInt16) 2 else 4;
        const offset = self.index_buffer_offset + (first_index * index_size);

        c.MTLRenderCommandEncoder.drawIndexedPrimitives(self.render_encoder.?, c.MTLPrimitiveTypeTriangle, index_count, self.index_type, self.index_buffer, offset, instance_count, vertex_offset, first_instance);
    }

    /// Execute a compute dispatch
    fn dispatchImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, group_size_x: u32, group_size_y: u32, group_size_z: u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.compute_encoder == null) {
            // Begin a compute encoder if we don't have one
            if (self.command_buffer == null) {
                return error.InvalidOperation;
            }

            self.compute_encoder = c.MTLCommandBuffer.computeCommandEncoder(self.command_buffer.?);
            if (self.compute_encoder == null) {
                return error.CommandSubmissionFailed;
            }
        }

        const grid_size = c.MTLSize{ .width = group_size_x, .height = group_size_y, .depth = group_size_z };

        // Optimize thread group size based on hardware
        var thread_group_size: c.MTLSize = undefined;

        if (self.is_apple_silicon) {
            // Apple Silicon optimizes for 32x16 thread groups on M1/M2
            thread_group_size = c.MTLSize{ .width = 32, .height = 16, .depth = 1 };
        } else {
            // Standard size for older hardware
            thread_group_size = c.MTLSize{ .width = 8, .height = 8, .depth = 1 };
        }

        c.MTLComputeCommandEncoder.dispatchThreadgroups(self.compute_encoder.?, grid_size, thread_group_size);
    }

    /// Copy data from one buffer to another
    fn copyBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, src_offset: u64, dst: *types.Buffer, dst_offset: u64, size: u64) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (src.id == 0 or dst.id == 0) {
            return error.InvalidOperation;
        }

        // End any active encoders before starting a blit operation
        self.endAllEncoders();

        // Begin a blit encoder
        if (self.command_buffer == null) {
            return error.InvalidOperation;
        }

        self.blit_encoder = c.MTLCommandBuffer.blitCommandEncoder(self.command_buffer.?);
        if (self.blit_encoder == null) {
            return error.CommandSubmissionFailed;
        }

        const src_buffer: *c.MTLBuffer = @ptrFromInt(src.id);
        const dst_buffer: *c.MTLBuffer = @ptrFromInt(dst.id);

        c.MTLBlitCommandEncoder.copyFromBuffer(self.blit_encoder.?, src_buffer, src_offset, dst_buffer, dst_offset, size);
    }

    /// Copy data from one texture to another
    fn copyTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, src_mip: u32, src_offset: [3]u32, dst: *types.Texture, dst_mip: u32, dst_offset: [3]u32, extent: [3]u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (src.id == 0 or dst.id == 0) {
            return error.InvalidOperation;
        }

        // End any active encoders before starting a blit operation
        self.endAllEncoders();

        // Begin a blit encoder
        if (self.command_buffer == null) {
            return error.InvalidOperation;
        }

        self.blit_encoder = c.MTLCommandBuffer.blitCommandEncoder(self.command_buffer.?);
        if (self.blit_encoder == null) {
            return error.CommandSubmissionFailed;
        }

        const src_texture: *c.MTLTexture = @ptrFromInt(src.id);
        const dst_texture: *c.MTLTexture = @ptrFromInt(dst.id);

        c.MTLBlitCommandEncoder.copyFromTexture(self.blit_encoder.?, src_texture, src_mip, src_offset[0], src_offset[1], dst_texture, dst_mip, dst_offset[0], dst_offset[1], extent[0], extent[1]);
    }

    /// Copy data from a buffer to a texture
    fn copyBufferToTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, bytes_per_row: u32, texture: *types.Texture, mip_level: u32, texture_offset: [3]u32, extent: [3]u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (buffer.id == 0 or texture.id == 0) {
            return error.InvalidOperation;
        }

        // End any active encoders before starting a blit operation
        self.endAllEncoders();

        // Begin a blit encoder
        if (self.command_buffer == null) {
            return error.InvalidOperation;
        }

        self.blit_encoder = c.MTLCommandBuffer.blitCommandEncoder(self.command_buffer.?);
        if (self.blit_encoder == null) {
            return error.CommandSubmissionFailed;
        }

        const src_buffer: *c.MTLBuffer = @ptrFromInt(buffer.id);
        const dst_texture: *c.MTLTexture = @ptrFromInt(texture.id);

        c.MTLBlitCommandEncoder.copyFromBufferToTexture(self.blit_encoder.?, src_buffer, offset, bytes_per_row, bytes_per_row * extent[1], c.MTLSize{ .width = extent[0], .height = extent[1], .depth = extent[2] }, dst_texture, mip_level, texture_offset[0], texture_offset[1], texture_offset[2]);
    }

    /// Copy data from a texture to a buffer
    fn copyTextureToBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, texture: *types.Texture, mip_level: u32, texture_offset: [3]u32, buffer: *types.Buffer, offset: u64, bytes_per_row: u32, extent: [3]u32) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (texture.id == 0 or buffer.id == 0) {
            return error.InvalidOperation;
        }

        // End any active encoders before starting a blit operation
        self.endAllEncoders();

        // Begin a blit encoder
        if (self.command_buffer == null) {
            return error.InvalidOperation;
        }

        self.blit_encoder = c.MTLCommandBuffer.blitCommandEncoder(self.command_buffer.?);
        if (self.blit_encoder == null) {
            return error.CommandSubmissionFailed;
        }

        const src_texture: *c.MTLTexture = @ptrFromInt(texture.id);
        const dst_buffer: *c.MTLBuffer = @ptrFromInt(buffer.id);

        c.MTLBlitCommandEncoder.copyFromTextureToBuffer(self.blit_encoder.?, src_texture, mip_level, texture_offset[0], texture_offset[1], texture_offset[2], dst_buffer, offset, bytes_per_row, bytes_per_row * extent[1], c.MTLSize{ .width = extent[0], .height = extent[1], .depth = extent[2] });
    }

    /// Execute a resource barrier (memory barrier)
    fn resourceBarrierImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, resource_type: interface.ResourceType, resource_state: interface.ResourceState) !void {
        // Metal handles resource transitions automatically, so this is a no-op
        _ = impl;
        _ = cmd;
        _ = resource_type;
        _ = resource_state;
        return;
    }

    /// Get information about the backend
    fn getBackendInfoImpl(impl: *anyopaque) interface.BackendInfo {
        const self: *Self = @ptrCast(@alignCast(impl));

        var device_name: [128]u8 = [_]u8{0} ** 128;

        if (self.device) |device| {
            const name_obj = c.MTLDevice.name(device);
            if (name_obj != null) {
                const name_cstr = c.NSString.UTF8String(name_obj);
                if (name_cstr != null) {
                    const name_len = std.mem.len(name_cstr);
                    @memcpy(device_name[0..@min(name_len, device_name.len - 1)], name_cstr[0..@min(name_len, device_name.len - 1)]);
                }
            }
        }

        return interface.BackendInfo{
            .type = .metal,
            .api_version = "Metal",
            .device_name = device_name,
            .vendor_name = "Apple",
        };
    }

    /// Set debug name for a resource
    fn setDebugNameImpl(impl: *anyopaque, resource_type: interface.ResourceType, resource: *anyopaque, name: []const u8) void {
        _ = impl;

        // Convert name to a null-terminated string for Metal API
        var label_buf: [256]u8 = undefined;
        const label_len = @min(name.len, label_buf.len - 1);
        @memcpy(label_buf[0..label_len], name[0..label_len]);
        label_buf[label_len] = 0;

        const label = c.NSString.stringWithUTF8String(&label_buf[0]);
        if (label == null) return;

        switch (resource_type) {
            .texture => {
                const texture_ptr: *const types.Texture = @ptrCast(@alignCast(resource));
                if (texture_ptr.id != 0) {
                    const metal_texture: *c.MTLTexture = @ptrFromInt(texture_ptr.id);
                    c.MTLTexture.setLabel(metal_texture, label);
                }
            },
            .buffer => {
                const buffer_ptr: *const types.Buffer = @ptrCast(@alignCast(resource));
                if (buffer_ptr.id != 0) {
                    const metal_buffer: *c.MTLBuffer = @ptrFromInt(buffer_ptr.id);
                    c.MTLBuffer.setLabel(metal_buffer, label);
                }
            },
            .pipeline => {
                const pipeline_ptr: *const interface.Pipeline = @ptrCast(@alignCast(resource));
                if (pipeline_ptr.id != 0) {
                    const metal_pipeline: *c.MTLRenderPipelineState = @ptrFromInt(pipeline_ptr.id);
                    c.MTLRenderPipelineState.setLabel(metal_pipeline, label);
                }
            },
            else => {},
        }
    }

    /// Begin a debug group for command tracing
    fn beginDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        // Convert name to a null-terminated string for Metal API
        var label_buf: [256]u8 = undefined;
        const label_len = @min(name.len, label_buf.len - 1);
        @memcpy(label_buf[0..label_len], name[0..label_len]);
        label_buf[label_len] = 0;

        const label = c.NSString.stringWithUTF8String(&label_buf[0]);
        if (label == null) return;

        if (self.render_encoder != null) {
            c.MTLRenderCommandEncoder.pushDebugGroup(self.render_encoder.?, label);
        } else if (self.compute_encoder != null) {
            c.MTLComputeCommandEncoder.pushDebugGroup(self.compute_encoder.?, label);
        } else if (self.blit_encoder != null) {
            c.MTLBlitCommandEncoder.pushDebugGroup(self.blit_encoder.?, label);
        }
    }

    /// End the current debug group
    fn endDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (self.render_encoder != null) {
            c.MTLRenderCommandEncoder.popDebugGroup(self.render_encoder.?);
        } else if (self.compute_encoder != null) {
            c.MTLComputeCommandEncoder.popDebugGroup(self.compute_encoder.?);
        } else if (self.blit_encoder != null) {
            c.MTLBlitCommandEncoder.popDebugGroup(self.blit_encoder.?);
        }
    }

    /// Wait for a fence to be signaled
    fn waitForFenceImpl(impl: *anyopaque, fence: u64, timeout_ns: u64) !void {
        _ = impl;
        _ = fence;
        _ = timeout_ns;
        // Metal doesn't use explicit fences, command buffer completion is handled differently
        return;
    }

    /// Signal a fence
    fn signalFenceImpl(impl: *anyopaque, fence: u64) !void {
        _ = impl;
        _ = fence;
        // Metal doesn't use explicit fences, command buffer completion is handled differently
        return;
    }

    /// Reset a fence to its unsignaled state
    fn resetFenceImpl(impl: *anyopaque, fence: u64) !void {
        _ = impl;
        _ = fence;
        // Metal doesn't use explicit fences, command buffer completion is handled differently
        return;
    }

    /// Create a sampler
    fn createSamplerImpl(impl: *anyopaque, desc: *const types.SamplerDesc) !types.Sampler {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device == null) {
            return error.InvalidOperation;
        }

        const sampler_desc = c.MTLSamplerDescriptor.alloc().init();
        if (sampler_desc == null) {
            return error.ResourceCreationFailed;
        }

        // Local conversion functions
        const convertFilterMode = (struct {
            fn convert(filter: interface.FilterMode) u32 {
                return switch (filter) {
                    .nearest => 0, // MTLSamplerMinMagFilterNearest
                    .linear => 1, // MTLSamplerMinMagFilterLinear
                    else => 1, // Default to linear
                };
            }
        }).convert;

        const convertMipFilterMode = (struct {
            fn convert(filter: interface.FilterMode) u32 {
                return switch (filter) {
                    .nearest => 0, // MTLSamplerMipFilterNearest
                    .linear => 1, // MTLSamplerMipFilterLinear
                    else => 1, // Default to linear
                };
            }
        }).convert;

        const convertAddressMode = (struct {
            fn convert(mode: interface.AddressMode) u32 {
                return switch (mode) {
                    .clamp_to_edge => 0, // MTLSamplerAddressModeClampToEdge
                    .repeat => 1, // MTLSamplerAddressModeRepeat
                    .mirrored_repeat => 2, // MTLSamplerAddressModeMirrorRepeat
                    .clamp_to_border => 3, // MTLSamplerAddressModeClampToBorderColor
                    else => 0, // Default to clamp to edge
                };
            }
        }).convert;

        // Convert sampler properties
        c.MTLSamplerDescriptor.setMinFilter(sampler_desc, convertFilterMode(desc.min_filter));
        c.MTLSamplerDescriptor.setMagFilter(sampler_desc, convertFilterMode(desc.mag_filter));
        c.MTLSamplerDescriptor.setMipFilter(sampler_desc, convertMipFilterMode(desc.mip_filter));

        c.MTLSamplerDescriptor.setSAddressMode(sampler_desc, convertAddressMode(desc.address_u));
        c.MTLSamplerDescriptor.setTAddressMode(sampler_desc, convertAddressMode(desc.address_v));
        c.MTLSamplerDescriptor.setRAddressMode(sampler_desc, convertAddressMode(desc.address_w));

        c.MTLSamplerDescriptor.setMaxAnisotropy(sampler_desc, desc.max_anisotropy);
        c.MTLSamplerDescriptor.setNormalizedCoordinates(sampler_desc, true);

        // Apply Apple Silicon specific optimizations
        if (self.is_apple_silicon) {
            c.MTLSamplerDescriptor.setSupportArgumentBuffers(sampler_desc, true);
        }

        const metal_sampler = c.MTLDevice.newSamplerStateWithDescriptor(self.device.?, sampler_desc);
        if (metal_sampler == null) {
            return error.ResourceCreationFailed;
        }

        return types.Sampler{
            .id = @intFromPtr(metal_sampler),
            .desc = desc.*,
        };
    }

    /// Destroy a sampler
    fn destroySamplerImpl(impl: *anyopaque, sampler: *types.Sampler) void {
        _ = impl;
        // Metal uses ARC, so we just need to clear the ID
        sampler.id = 0;
    }

    /// Bind a sampler to a shader
    fn bindSamplerImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, sampler: *types.Sampler, slot: u32, shader_stage: types.ShaderStage) !void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (sampler.id == 0) {
            return error.InvalidOperation;
        }

        const metal_sampler: *c.MTLSamplerState = @ptrFromInt(sampler.id);

        switch (shader_stage) {
            .vertex => {
                if (self.render_encoder != null) {
                    c.MTLRenderCommandEncoder.setVertexSamplerState(self.render_encoder.?, metal_sampler, slot);
                }
            },
            .fragment => {
                if (self.render_encoder != null) {
                    c.MTLRenderCommandEncoder.setFragmentSamplerState(self.render_encoder.?, metal_sampler, slot);
                }
            },
            .compute => {
                if (self.compute_encoder != null) {
                    c.MTLComputeCommandEncoder.setSamplerState(self.compute_encoder.?, metal_sampler, slot);
                }
            },
        }
    }
};
