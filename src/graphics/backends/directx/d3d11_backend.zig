//! Direct3D 11 backend implementation for the graphics system
const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const interface = @import("../interface.zig");
const types = @import("../../types.zig");
const common = @import("../common.zig");
// DirectX 11 C bindings
const c = @cImport({
    @cDefine("COBJMACROS", "");
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
    @cInclude("d3d11.h");
    @cInclude("dxgi.h");
    @cInclude("d3dcompiler.h");
});

// Runtime loading of D3DCompile to avoid linking issues
const D3DCompileFunc = *const fn (
    pSrcData: ?*const anyopaque,
    SrcDataSize: usize,
    pSourceName: ?[*:0]const u8,
    pDefines: ?*const c.D3D_SHADER_MACRO,
    pInclude: ?*c.ID3DInclude,
    pEntrypoint: [*:0]const u8,
    pTarget: [*:0]const u8,
    Flags1: c.UINT,
    Flags2: c.UINT,
    ppCode: *?*c.ID3DBlob,
    ppErrorMsgs: ?*?*c.ID3DBlob,
) callconv(.C) c.HRESULT;

var d3dcompiler_dll: ?*anyopaque = null;
var d3d_compile_func: ?D3DCompileFunc = null;

fn loadD3DCompiler() bool {
    if (d3dcompiler_dll != null) return true;

    // Try to load d3dcompiler_47.dll first, then fallback to d3dcompiler_46.dll
    d3dcompiler_dll = c.LoadLibraryA("d3dcompiler_47.dll");
    if (d3dcompiler_dll == null) {
        d3dcompiler_dll = c.LoadLibraryA("d3dcompiler_46.dll");
    }
    if (d3dcompiler_dll == null) {
        d3dcompiler_dll = c.LoadLibraryA("d3dcompiler_43.dll");
    }

    if (d3dcompiler_dll) |dll| {
        const hmodule: c.HMODULE = @ptrCast(@alignCast(dll));
        const proc = c.GetProcAddress(hmodule, "D3DCompile");
        if (proc) |p| {
            d3d_compile_func = @ptrCast(p);
            return true;
        }
    }

    return false;
}

/// Convert engine TextureFormat to DXGI_FORMAT for DirectX 11.
inline fn textureFormatToDxgi(format: types.TextureFormat) c.DXGI_FORMAT {
    return switch (format) {
        .rgba8 => c.DXGI_FORMAT_R8G8B8A8_UNORM,
        .rgba8_unorm => c.DXGI_FORMAT_R8G8B8A8_UNORM,
        .rgba8_unorm_srgb => c.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
        // DirectX does not support 24-bit RGB; promote to RGBA.
        .rgb8 => c.DXGI_FORMAT_R8G8B8A8_UNORM,
        .rgb8_unorm => c.DXGI_FORMAT_R8G8B8A8_UNORM,
        .bgra8 => c.DXGI_FORMAT_B8G8R8A8_UNORM,
        .bgra8_unorm => c.DXGI_FORMAT_B8G8R8A8_UNORM,
        .bgra8_unorm_srgb => c.DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
        .r8_unorm => c.DXGI_FORMAT_R8_UNORM,
        .rg8 => c.DXGI_FORMAT_R8G8_UNORM,
        .rg8_unorm => c.DXGI_FORMAT_R8G8_UNORM,
        .depth24_stencil8 => c.DXGI_FORMAT_D24_UNORM_S8_UINT,
        .depth32f => c.DXGI_FORMAT_D32_FLOAT,
    };
}

pub const D3D11Backend = struct {
    /// Shared base struct with profiler and error logger
    base: common.BackendBase,
    allocator: std.mem.Allocator,
    device: ?*c.ID3D11Device = null,
    context: ?*c.ID3D11DeviceContext = null,
    swap_chain: ?*c.IDXGISwapChain = null,
    factory: ?*c.IDXGIFactory = null,
    adapter: ?*c.IDXGIAdapter = null,
    back_buffer: ?*c.ID3D11Texture2D = null,
    back_buffer_rtv: ?*c.ID3D11RenderTargetView = null,
    depth_stencil_buffer: ?*c.ID3D11Texture2D = null,
    depth_stencil_view: ?*c.ID3D11DepthStencilView = null,
    feature_level: c.D3D_FEATURE_LEVEL = c.D3D_FEATURE_LEVEL_11_0,
    window_handle: ?c.HWND = null,
    width: u32 = 0,
    height: u32 = 0,
    vsync: bool = true,
    initialized: bool = false,

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

    /// Create and initialize a D3D11 backend, returning a pointer to interface.GraphicsBackend.
    /// Returns BackendNotSupported if DirectX 11 is unavailable.
    pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        if (!build_options.d3d11_available) {
            return interface.GraphicsBackendError.BackendNotSupported;
        }

        const backend = try allocator.create(D3D11Backend);
        // Initialize shared base functionality
        const debug_mode = (builtin.mode == .Debug);
        const base = try common.BackendBase.init(allocator, debug_mode);
        backend.* = D3D11Backend{
            .base = base,
            .allocator = allocator,
        };

        // Initialize D3D11 device and context
        try backend.initializeDevice();

        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .d3d11,
            .vtable = &D3D11Backend.vtable,
            .impl_data = backend,
            .initialized = true,
        };
        return graphics_backend;
    }

    fn initializeDevice(self: *Self) !void {
        var device_flags: c.UINT = 0;
        if (builtin.mode == .Debug) {
            device_flags |= c.D3D11_CREATE_DEVICE_DEBUG;
        }

        const feature_levels = [_]c.D3D_FEATURE_LEVEL{
            c.D3D_FEATURE_LEVEL_11_1,
            c.D3D_FEATURE_LEVEL_11_0,
            c.D3D_FEATURE_LEVEL_10_1,
            c.D3D_FEATURE_LEVEL_10_0,
        };

        var hr = c.D3D11CreateDevice(
            null, // adapter
            c.D3D_DRIVER_TYPE_HARDWARE,
            null, // software
            device_flags,
            &feature_levels[0],
            feature_levels.len,
            c.D3D11_SDK_VERSION,
            &self.device,
            &self.feature_level,
            &self.context,
        );

        if (c.FAILED(hr)) {
            std.log.err("Failed to create D3D11 device: 0x{X}", .{hr});
            return interface.GraphicsBackendError.DeviceCreationFailed;
        }

        // Create DXGI factory
        hr = c.CreateDXGIFactory(&c.IID_IDXGIFactory, @ptrCast(&self.factory));
        if (c.FAILED(hr)) {
            std.log.err("Failed to create DXGI factory: 0x{X}", .{hr});
            return interface.GraphicsBackendError.InitializationFailed;
        }

        self.initialized = true;
        std.log.info("D3D11 backend initialized successfully", .{});
        std.log.info("Feature level: 0x{X}", .{self.feature_level});
    }

    // Implementation functions
    fn deinitImpl(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.deinitInternal();
    }

    fn deinitInternal(self: *Self) void {
        if (!self.initialized) return;

        if (self.depth_stencil_view) |dsv| {
            _ = dsv.lpVtbl.*.Release.?(dsv);
        }
        if (self.depth_stencil_buffer) |dsb| {
            _ = dsb.lpVtbl.*.Release.?(dsb);
        }
        if (self.back_buffer_rtv) |rtv| {
            _ = rtv.lpVtbl.*.Release.?(rtv);
        }
        if (self.back_buffer) |bb| {
            _ = bb.lpVtbl.*.Release.?(bb);
        }
        if (self.swap_chain) |sc| {
            _ = sc.lpVtbl.*.Release.?(sc);
        }
        if (self.context) |ctx| {
            _ = ctx.lpVtbl.*.Release.?(ctx);
        }
        if (self.device) |dev| {
            _ = dev.lpVtbl.*.Release.?(dev);
        }
        if (self.adapter) |adapter| {
            _ = adapter.lpVtbl.*.Release.?(adapter);
        }
        if (self.factory) |factory| {
            _ = factory.lpVtbl.*.Release.?(factory);
        }

        self.initialized = false;
        self.allocator.destroy(self);
    }

    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        self.window_handle = @ptrCast(@alignCast(desc.window_handle orelse return interface.GraphicsBackendError.InvalidOperation));
        self.width = desc.width;
        self.height = desc.height;
        self.vsync = desc.vsync;

        var swap_chain_desc = std.mem.zeroes(c.DXGI_SWAP_CHAIN_DESC);
        swap_chain_desc.BufferCount = desc.buffer_count;
        swap_chain_desc.BufferDesc.Width = desc.width;
        swap_chain_desc.BufferDesc.Height = desc.height;
        swap_chain_desc.BufferDesc.Format = textureFormatToDxgi(desc.format);
        swap_chain_desc.BufferDesc.RefreshRate.Numerator = 60;
        swap_chain_desc.BufferDesc.RefreshRate.Denominator = 1;
        swap_chain_desc.BufferUsage = c.DXGI_USAGE_RENDER_TARGET_OUTPUT;
        swap_chain_desc.OutputWindow = self.window_handle.?;
        swap_chain_desc.SampleDesc.Count = 1;
        swap_chain_desc.SampleDesc.Quality = 0;
        swap_chain_desc.Windowed = c.TRUE;
        swap_chain_desc.SwapEffect = c.DXGI_SWAP_EFFECT_DISCARD;

        const hr = self.factory.?.lpVtbl.*.CreateSwapChain.?(
            self.factory.?,
            @ptrCast(self.device.?),
            &swap_chain_desc,
            &self.swap_chain,
        );

        if (c.FAILED(hr)) {
            std.log.err("Failed to create swap chain: 0x{X}", .{hr});
            return interface.GraphicsBackendError.SwapChainCreationFailed;
        }

        try self.createBackBufferResources();
    }

    fn createBackBufferResources(self: *Self) !void {
        // Get back buffer
        var hr = self.swap_chain.?.lpVtbl.*.GetBuffer.?(
            self.swap_chain.?,
            0,
            &c.IID_ID3D11Texture2D,
            @ptrCast(&self.back_buffer),
        );

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        // Create render target view
        hr = self.device.?.lpVtbl.*.CreateRenderTargetView.?(
            self.device.?,
            @ptrCast(self.back_buffer.?),
            null,
            &self.back_buffer_rtv,
        );

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        // Create depth stencil buffer
        var depth_desc = std.mem.zeroes(c.D3D11_TEXTURE2D_DESC);
        depth_desc.Width = self.width;
        depth_desc.Height = self.height;
        depth_desc.MipLevels = 1;
        depth_desc.ArraySize = 1;
        depth_desc.Format = c.DXGI_FORMAT_D24_UNORM_S8_UINT;
        depth_desc.SampleDesc.Count = 1;
        depth_desc.SampleDesc.Quality = 0;
        depth_desc.Usage = c.D3D11_USAGE_DEFAULT;
        depth_desc.BindFlags = c.D3D11_BIND_DEPTH_STENCIL;

        hr = self.device.?.lpVtbl.*.CreateTexture2D.?(
            self.device.?,
            &depth_desc,
            null,
            &self.depth_stencil_buffer,
        );

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        // Create depth stencil view
        hr = self.device.?.lpVtbl.*.CreateDepthStencilView.?(
            self.device.?,
            @ptrCast(self.depth_stencil_buffer.?),
            null,
            &self.depth_stencil_view,
        );

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        // Set render targets
        const render_targets = [_]?*c.ID3D11RenderTargetView{self.back_buffer_rtv};
        self.context.?.lpVtbl.*.OMSetRenderTargets.?(
            self.context.?,
            1,
            &render_targets[0],
            self.depth_stencil_view,
        );

        // Set viewport
        var viewport = c.D3D11_VIEWPORT{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(self.width),
            .Height = @floatFromInt(self.height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };

        self.context.?.lpVtbl.*.RSSetViewports.?(self.context.?, 1, &viewport);
    }

    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        self.width = width;
        self.height = height;

        // Release back buffer resources
        if (self.depth_stencil_view) |dsv| {
            _ = dsv.lpVtbl.*.Release.?(dsv);
            self.depth_stencil_view = null;
        }
        if (self.depth_stencil_buffer) |dsb| {
            _ = dsb.lpVtbl.*.Release.?(dsb);
            self.depth_stencil_buffer = null;
        }
        if (self.back_buffer_rtv) |rtv| {
            _ = rtv.lpVtbl.*.Release.?(rtv);
            self.back_buffer_rtv = null;
        }
        if (self.back_buffer) |bb| {
            _ = bb.lpVtbl.*.Release.?(bb);
            self.back_buffer = null;
        }

        // Resize swap chain
        const hr = self.swap_chain.?.lpVtbl.*.ResizeBuffers.?(
            self.swap_chain.?,
            0, // Keep current buffer count
            width,
            height,
            c.DXGI_FORMAT_UNKNOWN, // Keep current format
            0,
        );

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.SwapChainCreationFailed;
        }

        try self.createBackBufferResources();
    }

    fn presentImpl(impl: *anyopaque) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        const sync_interval: c.UINT = if (self.vsync) 1 else 0;
        const hr = self.swap_chain.?.lpVtbl.*.Present.?(self.swap_chain.?, sync_interval, 0);

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.CommandSubmissionFailed;
        }
    }

    fn getCurrentBackBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Create a wrapper texture for the back buffer
        const texture = try self.allocator.create(types.Texture);
        texture.* = types.Texture{
            .id = @intFromPtr(self.back_buffer.?),
            .width = self.width,
            .height = self.height,
            .depth = 1,
            .format = .rgba8,
            .texture_type = .texture_2d,
            .mip_levels = 1,
            .array_layers = 1,
            .usage = .{ .render_target = true },
            .sample_count = 1,
        };

        return texture;
    }

    fn createTextureImpl(impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        var desc = std.mem.zeroes(c.D3D11_TEXTURE2D_DESC);
        desc.Width = texture.width;
        desc.Height = texture.height;
        desc.MipLevels = texture.mip_levels;
        desc.ArraySize = if (texture.texture_type == .texture_array) texture.depth else 1;
        desc.Format = textureFormatToDxgi(texture.format);
        desc.SampleDesc.Count = 1;
        desc.SampleDesc.Quality = 0;
        desc.Usage = c.D3D11_USAGE_DEFAULT;
        desc.BindFlags = c.D3D11_BIND_SHADER_RESOURCE;
        desc.CPUAccessFlags = 0;

        var d3d_texture: ?*c.ID3D11Texture2D = null;
        var init_data: ?*c.D3D11_SUBRESOURCE_DATA = null;
        var subresource_data: c.D3D11_SUBRESOURCE_DATA = undefined;

        if (data) |texture_data| {
            subresource_data = c.D3D11_SUBRESOURCE_DATA{
                .pSysMem = texture_data.ptr,
                .SysMemPitch = texture.width * common.getBytesPerPixel(texture.format),
                .SysMemSlicePitch = 0,
            };
            init_data = &subresource_data;
        }

        const hr = self.device.?.lpVtbl.*.CreateTexture2D.?(
            self.device.?,
            &desc,
            init_data,
            &d3d_texture,
        );

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        texture.id = @intFromPtr(d3d_texture.?);
    }

    fn createBufferImpl(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        var desc = std.mem.zeroes(c.D3D11_BUFFER_DESC);
        desc.ByteWidth = @intCast(buffer.size);
        desc.Usage = c.D3D11_USAGE_DEFAULT;
        desc.BindFlags = switch (buffer.usage) {
            .vertex => c.D3D11_BIND_VERTEX_BUFFER,
            .index => c.D3D11_BIND_INDEX_BUFFER,
            .uniform => c.D3D11_BIND_CONSTANT_BUFFER,
            .storage => c.D3D11_BIND_UNORDERED_ACCESS,
            .staging => 0,
        };
        desc.CPUAccessFlags = if (buffer.usage == .staging) c.D3D11_CPU_ACCESS_READ | c.D3D11_CPU_ACCESS_WRITE else 0;

        var d3d_buffer: ?*c.ID3D11Buffer = null;
        var init_data: ?*c.D3D11_SUBRESOURCE_DATA = null;
        var subresource_data: c.D3D11_SUBRESOURCE_DATA = undefined;

        if (data) |buffer_data| {
            subresource_data = c.D3D11_SUBRESOURCE_DATA{
                .pSysMem = buffer_data.ptr,
                .SysMemPitch = 0,
                .SysMemSlicePitch = 0,
            };
            init_data = &subresource_data;
        }

        const hr = self.device.?.lpVtbl.*.CreateBuffer.?(
            self.device.?,
            &desc,
            init_data,
            &d3d_buffer,
        );

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        buffer.id = @intFromPtr(d3d_buffer.?);
    }

    fn createShaderImpl(impl: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Compile shader from source
        var blob: ?*c.ID3DBlob = null;
        var error_blob: ?*c.ID3DBlob = null;

        const target = switch (shader.shader_type) {
            .vertex => "vs_5_0",
            .fragment => "ps_5_0",
            .geometry => "gs_5_0",
            .compute => "cs_5_0",
            else => return interface.GraphicsBackendError.UnsupportedFormat,
        };

        // Try to load D3DCompiler at runtime
        if (!loadD3DCompiler()) {
            std.log.err("D3DCompiler not available - shader compilation disabled", .{});
            return interface.GraphicsBackendError.UnsupportedOperation;
        }

        var hr = d3d_compile_func.?(
            shader.source.ptr,
            shader.source.len,
            null, // source name
            null, // defines
            null, // includes
            "main", // entry point
            target.ptr,
            c.D3DCOMPILE_ENABLE_STRICTNESS,
            0,
            &blob,
            &error_blob,
        );

        if (c.FAILED(hr)) {
            if (error_blob) |err| {
                const error_msg = @as([*:0]const u8, @ptrCast(err.lpVtbl.*.GetBufferPointer.?(err)));
                std.log.err("Shader compilation failed: {s}", .{error_msg});
                _ = err.lpVtbl.*.Release.?(err);
            }
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        // Create shader object
        switch (shader.shader_type) {
            .vertex => {
                var vs: ?*c.ID3D11VertexShader = null;
                hr = self.device.?.lpVtbl.*.CreateVertexShader.?(
                    self.device.?,
                    blob.?.lpVtbl.*.GetBufferPointer.?(blob.?),
                    blob.?.lpVtbl.*.GetBufferSize.?(blob.?),
                    null,
                    &vs,
                );
                shader.id = @intFromPtr(vs.?);
            },
            .fragment => {
                var ps: ?*c.ID3D11PixelShader = null;
                hr = self.device.?.lpVtbl.*.CreatePixelShader.?(
                    self.device.?,
                    blob.?.lpVtbl.*.GetBufferPointer.?(blob.?),
                    blob.?.lpVtbl.*.GetBufferSize.?(blob.?),
                    null,
                    &ps,
                );
                shader.id = @intFromPtr(ps.?);
            },
            .geometry => {
                var gs: ?*c.ID3D11GeometryShader = null;
                hr = self.device.?.lpVtbl.*.CreateGeometryShader.?(
                    self.device.?,
                    blob.?.lpVtbl.*.GetBufferPointer.?(blob.?),
                    blob.?.lpVtbl.*.GetBufferSize.?(blob.?),
                    null,
                    &gs,
                );
                shader.id = @intFromPtr(gs.?);
            },
            .compute => {
                var cs: ?*c.ID3D11ComputeShader = null;
                hr = self.device.?.lpVtbl.*.CreateComputeShader.?(
                    self.device.?,
                    blob.?.lpVtbl.*.GetBufferPointer.?(blob.?),
                    blob.?.lpVtbl.*.GetBufferSize.?(blob.?),
                    null,
                    &cs,
                );
                shader.id = @intFromPtr(cs.?);
            },
            else => return interface.GraphicsBackendError.UnsupportedFormat,
        }

        if (blob) |b| {
            _ = b.lpVtbl.*.Release.?(b);
        }

        if (c.FAILED(hr)) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        shader.compiled = true;
    }

    // Stub implementations for remaining functions
    fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        _ = impl;
        _ = desc;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn createRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        _ = impl;
        _ = render_target;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn updateBufferImpl(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = buffer;
        _ = offset;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn updateTextureImpl(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = texture;
        _ = region;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn destroyTextureImpl(impl: *anyopaque, texture: *types.Texture) void {
        _ = impl;
        if (texture.id != 0) {
            const d3d_texture: *c.ID3D11Texture2D = @ptrFromInt(texture.id);
            _ = d3d_texture.lpVtbl.*.Release.?(d3d_texture);
            texture.id = 0;
        }
    }

    fn destroyBufferImpl(impl: *anyopaque, buffer: *types.Buffer) void {
        _ = impl;
        if (buffer.id != 0) {
            const d3d_buffer: *c.ID3D11Buffer = @ptrFromInt(buffer.id);
            _ = d3d_buffer.lpVtbl.*.Release.?(d3d_buffer);
            buffer.id = 0;
        }
    }

    fn destroyShaderImpl(impl: *anyopaque, shader: *types.Shader) void {
        _ = impl;
        if (shader.id != 0) {
            const d3d_shader: *c.IUnknown = @ptrFromInt(shader.id);
            _ = d3d_shader.lpVtbl.*.Release.?(d3d_shader);
            shader.id = 0;
        }
    }

    fn destroyRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) void {
        _ = impl;
        _ = render_target;
    }

    fn createCommandBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*interface.CommandBuffer {
        const self: *Self = @ptrCast(@alignCast(impl));
        const cmd = try self.allocator.create(interface.CommandBuffer);
        cmd.* = interface.CommandBuffer{
            .id = 0,
            .backend_handle = self.context.?,
            .allocator = self.allocator,
        };
        return cmd;
    }

    fn beginCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        cmd.recording = true;
    }

    fn endCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        cmd.recording = false;
    }

    fn submitCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        // D3D11 commands are executed immediately
    }

    fn beginRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        // Clear render targets
        if (self.back_buffer_rtv) |rtv| {
            const clear_color = [_]f32{ desc.clear_color.r, desc.clear_color.g, desc.clear_color.b, desc.clear_color.a };
            self.context.?.lpVtbl.*.ClearRenderTargetView.?(self.context.?, rtv, &clear_color);
        }

        if (self.depth_stencil_view) |dsv| {
            self.context.?.lpVtbl.*.ClearDepthStencilView.?(
                self.context.?,
                dsv,
                c.D3D11_CLEAR_DEPTH | c.D3D11_CLEAR_STENCIL,
                desc.clear_depth,
                @intCast(desc.clear_stencil),
            );
        }
    }

    fn endRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
    }

    fn setViewportImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        var d3d_viewport = c.D3D11_VIEWPORT{
            .TopLeftX = viewport.x,
            .TopLeftY = viewport.y,
            .Width = viewport.width,
            .Height = viewport.height,
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };

        self.context.?.lpVtbl.*.RSSetViewports.?(self.context.?, 1, &d3d_viewport);
    }

    fn setScissorImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        var scissor_rect = c.D3D11_RECT{
            .left = @as(i32, @intFromFloat(rect.x)),
            .top = @as(i32, @intFromFloat(rect.y)),
            .right = @as(i32, @intFromFloat(rect.x)) + @as(i32, @intFromFloat(rect.width)),
            .bottom = @as(i32, @intFromFloat(rect.y)) + @as(i32, @intFromFloat(rect.height)),
        };

        self.context.?.lpVtbl.*.RSSetScissorRects.?(self.context.?, 1, &scissor_rect);
    }

    fn bindPipelineImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = pipeline;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindVertexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        const d3d_buffer: *c.ID3D11Buffer = @ptrFromInt(buffer.id);
        const stride: u32 = 32; // TODO: Get actual stride from vertex layout
        const offset32: u32 = @intCast(offset);

        self.context.?.lpVtbl.*.IASetVertexBuffers.?(
            self.context.?,
            slot,
            1,
            &d3d_buffer,
            &stride,
            &offset32,
        );
    }

    fn bindIndexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        const d3d_buffer: *c.ID3D11Buffer = @ptrFromInt(buffer.id);
        const dxgi_format = switch (format) {
            .uint16 => c.DXGI_FORMAT_R16_UINT,
            .uint32 => c.DXGI_FORMAT_R32_UINT,
        };

        self.context.?.lpVtbl.*.IASetIndexBuffer.?(
            self.context.?,
            d3d_buffer,
            @as(c_uint, @intCast(dxgi_format)),
            @intCast(offset),
        );
    }

    fn bindTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = texture;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindUniformBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;
        _ = offset;
        _ = size;

        const d3d_buffer: *c.ID3D11Buffer = @ptrFromInt(buffer.id);

        self.context.?.lpVtbl.*.VSSetConstantBuffers.?(self.context.?, slot, 1, &d3d_buffer);
        self.context.?.lpVtbl.*.PSSetConstantBuffers.?(self.context.?, slot, 1, &d3d_buffer);
    }

    fn drawImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (draw_cmd.instance_count > 1) {
            self.context.?.lpVtbl.*.DrawInstanced.?(
                self.context.?,
                draw_cmd.vertex_count,
                draw_cmd.instance_count,
                draw_cmd.first_vertex,
                draw_cmd.first_instance,
            );
        } else {
            self.context.?.lpVtbl.*.Draw.?(
                self.context.?,
                draw_cmd.vertex_count,
                draw_cmd.first_vertex,
            );
        }
    }

    fn drawIndexedImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        if (draw_cmd.instance_count > 1) {
            self.context.?.lpVtbl.*.DrawIndexedInstanced.?(
                self.context.?,
                draw_cmd.index_count,
                draw_cmd.instance_count,
                draw_cmd.first_index,
                draw_cmd.vertex_offset,
                draw_cmd.first_instance,
            );
        } else {
            self.context.?.lpVtbl.*.DrawIndexed.?(
                self.context.?,
                draw_cmd.index_count,
                draw_cmd.first_index,
                draw_cmd.vertex_offset,
            );
        }
    }

    fn dispatchImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = cmd;

        self.context.?.lpVtbl.*.Dispatch.?(
            self.context.?,
            dispatch_cmd.group_count_x,
            dispatch_cmd.group_count_y,
            dispatch_cmd.group_count_z,
        );
    }

    fn copyBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const interface.BufferCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyBufferToTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn copyTextureToBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn resourceBarrierImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = barriers;
        // D3D11 doesn't have explicit resource barriers
    }

    fn getBackendInfoImpl(impl: *anyopaque) interface.BackendInfo {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = self;

        return interface.BackendInfo{
            .name = "DirectX 11",
            .version = "11.0",
            .vendor = "Microsoft",
            .device_name = "D3D11 Device",
            .api_version = 11,
            .driver_version = 0,
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 16384,
            .max_render_targets = 8,
            .max_vertex_attributes = 16,
            .max_uniform_buffer_bindings = 14,
            .max_texture_bindings = 16,
            .supports_compute = true,
            .supports_geometry_shaders = true,
            .supports_tessellation = true,
            .supports_raytracing = false,
            .supports_mesh_shaders = false,
            .supports_variable_rate_shading = false,
            .supports_multiview = false,
        };
    }

    fn setDebugNameImpl(impl: *anyopaque, resource: interface.ResourceHandle, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = resource;
        _ = name;
        // TODO: Implement debug naming using ID3D11DeviceChild::SetPrivateData
    }

    fn beginDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = name;
        // TODO: Implement debug groups using D3D11 debug annotations
    }

    fn endDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        // TODO: Implement debug groups using D3D11 debug annotations
    }
};

/// Create a D3D11 backend instance (module-level wrapper for D3D11Backend.createBackend)
pub fn create(allocator: std.mem.Allocator, config: anytype) !*interface.GraphicsBackend {
    _ = config; // Config not used yet but may be in the future
    return D3D11Backend.createBackend(allocator);
}
