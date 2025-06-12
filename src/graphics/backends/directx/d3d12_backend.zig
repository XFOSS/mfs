const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const interface = @import("../../interface.zig");
const types = @import("../../types.zig");
const common = @import("../../common.zig");

// DirectX 12 C bindings
const c = @cImport({
    @cDefine("COBJMACROS", "");
    @cDefine("WIN32_LEAN_AND_MEAN", "");
    @cDefine("UNICODE", "");
    @cInclude("windows.h");
    @cInclude("d3d12.h");
    @cInclude("d3dcompiler.h");
    @cInclude("dxgi1_6.h");
});

// Helper constants
const FRAME_COUNT = 3;
const D3D12_COMMAND_LIST_TYPE_DIRECT = 0;
const D3D12_DESCRIPTOR_HEAP_TYPE_RTV = 0;
const D3D12_DESCRIPTOR_HEAP_TYPE_DSV = 1;
const D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV = 2;
const DXGI_FORMAT_R8G8B8A8_UNORM = 28;
const DXGI_FORMAT_D32_FLOAT = 40;
const DXGI_SWAP_EFFECT_FLIP_DISCARD = 4;

pub const D3D12Backend = struct {
    allocator: std.mem.Allocator,
    device: ?*c.ID3D12Device = null,
    command_queue: ?*c.ID3D12CommandQueue = null,
    swap_chain: ?*c.IDXGISwapChain4 = null,
    factory: ?*c.IDXGIFactory6 = null,
    adapter: ?*c.IDXGIAdapter1 = null,
    rtv_heap: ?*c.ID3D12DescriptorHeap = null,
    dsv_heap: ?*c.ID3D12DescriptorHeap = null,
    cbv_srv_uav_heap: ?*c.ID3D12DescriptorHeap = null,
    render_targets: [FRAME_COUNT]?*c.ID3D12Resource = [_]?*c.ID3D12Resource{null} ** FRAME_COUNT,
    depth_stencil: ?*c.ID3D12Resource = null,
    command_allocators: [FRAME_COUNT]?*c.ID3D12CommandAllocator = [_]?*c.ID3D12CommandAllocator{null} ** FRAME_COUNT,
    command_list: ?*c.ID3D12GraphicsCommandList = null,
    fence: ?*c.ID3D12Fence = null,
    fence_values: [FRAME_COUNT]u64 = [_]u64{0} ** FRAME_COUNT,
    fence_event: ?c.HANDLE = null,
    rtv_descriptor_size: u32 = 0,
    dsv_descriptor_size: u32 = 0,
    cbv_srv_uav_descriptor_size: u32 = 0,
    frame_index: u32 = 0,
    window_handle: ?c.HWND = null,
    width: u32 = 0,
    height: u32 = 0,
    buffer_count: u32 = FRAME_COUNT,
    vsync: bool = true,
    initialized: bool = false,
    debug_enabled: bool = false,

    const Self = @This();

    /// Create and initialize a D3D12 backend, returning a pointer to interface.GraphicsBackend.
    /// Returns BackendNotSupported if DirectX 12 is unavailable.
    pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        if (!build_options.d3d12_available) {
            return interface.GraphicsBackendError.BackendNotSupported;
        }

        const backend = try allocator.create(D3D12Backend);
        backend.* = D3D12Backend{ .allocator = allocator };

        // Enable debug layer in debug builds
        if (build_options.build_mode == .Debug) backend.enableDebugLayer();

        try backend.createDevice();
        try backend.createCommandQueue();
        try backend.createDescriptorHeaps();
        try backend.createSyncObjects();

        backend.initialized = true;
        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .d3d12,
            .vtable = &D3D12Backend.vtable,
            .impl_data = backend,
            .initialized = true,
        };
        return graphics_backend;
    }

    fn enableDebugLayer(self: *Self) void {
        var debug_controller: ?*c.ID3D12Debug = null;
        if (c.D3D12GetDebugInterface(&c.IID_ID3D12Debug, @ptrCast(&debug_controller)) == c.S_OK) {
            if (debug_controller) |debug| {
                _ = debug.lpVtbl.*.EnableDebugLayer.?(debug);
                self.debug_enabled = true;
                std.log.info("D3D12 debug layer enabled", .{});
            }
        }
    }

    fn createDevice(self: *Self) !void {
        // Create DXGI factory
        if (c.CreateDXGIFactory2(0, &c.IID_IDXGIFactory6, @ptrCast(&self.factory)) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // Find suitable adapter
        var adapter_index: u32 = 0;
        while (true) {
            if (self.factory.?.lpVtbl.*.EnumAdapters1.?(self.factory.?, adapter_index, &self.adapter) != c.S_OK) {
                break;
            }

            // Try to create device with this adapter
            if (c.D3D12CreateDevice(@ptrCast(self.adapter), c.D3D_FEATURE_LEVEL_11_0, &c.IID_ID3D12Device, @ptrCast(&self.device)) == c.S_OK) {
                // Log adapter info
                var adapter_desc: c.DXGI_ADAPTER_DESC1 = undefined;
                _ = self.adapter.?.lpVtbl.*.GetDesc1.?(self.adapter.?, &adapter_desc);
                std.log.info("D3D12 device created with adapter", .{});
                break;
            }

            // Release failed adapter and try next
            _ = self.adapter.?.lpVtbl.*.Release.?(self.adapter.?);
            self.adapter = null;
            adapter_index += 1;
        }

        if (self.device == null) {
            return interface.GraphicsBackendError.InitializationFailed;
        }
    }

    fn createCommandQueue(self: *Self) !void {
        const queue_desc = c.D3D12_COMMAND_QUEUE_DESC{
            .Type = D3D12_COMMAND_LIST_TYPE_DIRECT,
            .Priority = 0,
            .Flags = 0,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateCommandQueue.?(self.device.?, &queue_desc, &c.IID_ID3D12CommandQueue, @ptrCast(&self.command_queue)) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }
    }

    fn createDescriptorHeaps(self: *Self) !void {
        // RTV heap
        const rtv_heap_desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
            .NumDescriptors = FRAME_COUNT,
            .Flags = 0,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateDescriptorHeap.?(self.device.?, &rtv_heap_desc, &c.IID_ID3D12DescriptorHeap, @ptrCast(&self.rtv_heap)) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        self.rtv_descriptor_size = self.device.?.lpVtbl.*.GetDescriptorHandleIncrementSize.?(self.device.?, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

        // DSV heap
        const dsv_heap_desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = D3D12_DESCRIPTOR_HEAP_TYPE_DSV,
            .NumDescriptors = 1,
            .Flags = 0,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateDescriptorHeap.?(self.device.?, &dsv_heap_desc, &c.IID_ID3D12DescriptorHeap, @ptrCast(&self.dsv_heap)) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // CBV/SRV/UAV heap
        const cbv_heap_desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
            .NumDescriptors = 1000, // Large heap for various resources
            .Flags = c.D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateDescriptorHeap.?(self.device.?, &cbv_heap_desc, &c.IID_ID3D12DescriptorHeap, @ptrCast(&self.cbv_srv_uav_heap)) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }
    }

    fn createSyncObjects(self: *Self) !void {
        if (self.device.?.lpVtbl.*.CreateFence.?(self.device.?, 0, 0, &c.IID_ID3D12Fence, @ptrCast(&self.fence)) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        self.fence_event = c.CreateEventW(null, 0, 0, null);
        if (self.fence_event == null) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // Create command allocators for each frame
        for (0..FRAME_COUNT) |i| {
            if (self.device.?.lpVtbl.*.CreateCommandAllocator.?(self.device.?, D3D12_COMMAND_LIST_TYPE_DIRECT, &c.IID_ID3D12CommandAllocator, @ptrCast(&self.command_allocators[i])) != c.S_OK) {
                return interface.GraphicsBackendError.InitializationFailed;
            }
        }

        // Create command list
        if (self.device.?.lpVtbl.*.CreateCommandList.?(self.device.?, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, self.command_allocators[0].?, null, &c.IID_ID3D12GraphicsCommandList, @ptrCast(&self.command_list)) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // Close command list initially
        _ = self.command_list.?.lpVtbl.*.Close.?(self.command_list.?);
    }

    pub fn deinit(self: *Self) void {
        self.waitForGpu();

        if (self.fence_event) |event| {
            _ = c.CloseHandle(event);
        }

        // Release all resources
        for (0..FRAME_COUNT) |i| {
            if (self.render_targets[i]) |rt| {
                _ = rt.lpVtbl.*.Release.?(rt);
            }
            if (self.command_allocators[i]) |ca| {
                _ = ca.lpVtbl.*.Release.?(ca);
            }
        }

        if (self.depth_stencil) |ds| _ = ds.lpVtbl.*.Release.?(ds);
        if (self.command_list) |cl| _ = cl.lpVtbl.*.Release.?(cl);
        if (self.fence) |f| _ = f.lpVtbl.*.Release.?(f);
        if (self.cbv_srv_uav_heap) |heap| _ = heap.lpVtbl.*.Release.?(heap);
        if (self.dsv_heap) |heap| _ = heap.lpVtbl.*.Release.?(heap);
        if (self.rtv_heap) |heap| _ = heap.lpVtbl.*.Release.?(heap);
        if (self.swap_chain) |sc| _ = sc.lpVtbl.*.Release.?(sc);
        if (self.command_queue) |cq| _ = cq.lpVtbl.*.Release.?(cq);
        if (self.device) |d| _ = d.lpVtbl.*.Release.?(d);
        if (self.adapter) |a| _ = a.lpVtbl.*.Release.?(a);
        if (self.factory) |f| _ = f.lpVtbl.*.Release.?(f);

        self.initialized = false;
    }

    fn waitForGpu(self: *Self) void {
        if (self.command_queue == null or self.fence == null or self.fence_event == null) return;

        const fence_value = self.fence_values[self.frame_index];
        _ = self.command_queue.?.lpVtbl.*.Signal.?(self.command_queue.?, self.fence.?, fence_value);

        if (self.fence.?.lpVtbl.*.GetCompletedValue.?(self.fence.?) < fence_value) {
            _ = self.fence.?.lpVtbl.*.SetEventOnCompletion.?(self.fence.?, fence_value, self.fence_event.?);
            _ = c.WaitForSingleObject(self.fence_event.?, c.INFINITE);
        }
    }

    pub fn createSwapChain(self: *Self, desc: interface.SwapChainDesc) !types.SwapChain {
        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        self.window_handle = @ptrFromInt(desc.window_handle);
        self.width = desc.width;
        self.height = desc.height;
        self.buffer_count = desc.buffer_count;
        self.vsync = desc.vsync;

        // Create swap chain
        const swap_chain_desc = c.DXGI_SWAP_CHAIN_DESC1{
            .Width = desc.width,
            .Height = desc.height,
            .Format = DXGI_FORMAT_R8G8B8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = c.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = FRAME_COUNT,
            .Scaling = c.DXGI_SCALING_STRETCH,
            .SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD,
            .AlphaMode = c.DXGI_ALPHA_MODE_UNSPECIFIED,
            .Flags = 0,
        };

        var temp_swap_chain: ?*c.IDXGISwapChain1 = null;
        if (self.factory.?.lpVtbl.*.CreateSwapChainForHwnd.?(self.factory.?, @ptrCast(self.command_queue.?), self.window_handle.?, &swap_chain_desc, null, null, &temp_swap_chain) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // Query for SwapChain4 interface
        if (temp_swap_chain.?.lpVtbl.*.QueryInterface.?(temp_swap_chain.?, &c.IID_IDXGISwapChain4, @ptrCast(&self.swap_chain)) != c.S_OK) {
            _ = temp_swap_chain.?.lpVtbl.*.Release.?(temp_swap_chain.?);
            return interface.GraphicsBackendError.InitializationFailed;
        }
        _ = temp_swap_chain.?.lpVtbl.*.Release.?(temp_swap_chain.?);

        // Create render target views
        try self.createRenderTargets();

        return types.SwapChain{
            .handle = @intFromPtr(self.swap_chain),
            .width = desc.width,
            .height = desc.height,
            .format = .rgba8_unorm_srgb,
            .buffer_count = FRAME_COUNT,
        };
    }

    fn createRenderTargets(self: *Self) !void {
        var rtv_handle = self.rtv_heap.?.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(self.rtv_heap.?);

        for (0..FRAME_COUNT) |i| {
            if (self.swap_chain.?.lpVtbl.*.GetBuffer.?(self.swap_chain.?, @intCast(i), &c.IID_ID3D12Resource, @ptrCast(&self.render_targets[i])) != c.S_OK) {
                return interface.GraphicsBackendError.InitializationFailed;
            }

            self.device.?.lpVtbl.*.CreateRenderTargetView.?(self.device.?, self.render_targets[i].?, null, rtv_handle);

            rtv_handle.ptr += self.rtv_descriptor_size;
        }
    }

    pub fn resizeSwapChain(self: *Self, width: u32, height: u32) !void {
        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        self.waitForGpu();

        // Release render targets
        for (0..FRAME_COUNT) |i| {
            if (self.render_targets[i]) |rt| {
                _ = rt.lpVtbl.*.Release.?(rt);
                self.render_targets[i] = null;
            }
        }

        // Resize swap chain
        if (self.swap_chain.?.lpVtbl.*.ResizeBuffers.?(self.swap_chain.?, FRAME_COUNT, width, height, DXGI_FORMAT_R8G8B8A8_UNORM, 0) != c.S_OK) {
            return interface.GraphicsBackendError.ResizeFailed;
        }

        self.width = width;
        self.height = height;

        // Recreate render targets
        try self.createRenderTargets();
    }

    pub fn present(self: *Self) !void {
        if (!self.initialized or self.swap_chain == null) {
            return interface.GraphicsBackendError.NotInitialized;
        }

        const sync_interval: u32 = if (self.vsync) 1 else 0;
        if (self.swap_chain.?.lpVtbl.*.Present.?(self.swap_chain.?, sync_interval, 0) != c.S_OK) {
            return interface.GraphicsBackendError.PresentFailed;
        }

        self.moveToNextFrame();
    }

    fn moveToNextFrame(self: *Self) void {
        const current_fence_value = self.fence_values[self.frame_index];
        _ = self.command_queue.?.lpVtbl.*.Signal.?(self.command_queue.?, self.fence.?, current_fence_value);

        self.frame_index = (self.frame_index + 1) % FRAME_COUNT;

        if (self.fence.?.lpVtbl.*.GetCompletedValue.?(self.fence.?) < self.fence_values[self.frame_index]) {
            _ = self.fence.?.lpVtbl.*.SetEventOnCompletion.?(self.fence.?, self.fence_values[self.frame_index], self.fence_event.?);
            _ = c.WaitForSingleObject(self.fence_event.?, c.INFINITE);
        }

        self.fence_values[self.frame_index] = current_fence_value + 1;
    }

    pub fn getCurrentBackBuffer(self: *Self) !types.Texture {
        if (!self.initialized or self.swap_chain == null) {
            return interface.GraphicsBackendError.NotInitialized;
        }

        const current_back_buffer_index = self.swap_chain.?.lpVtbl.*.GetCurrentBackBufferIndex.?(self.swap_chain.?);

        return types.Texture{
            .handle = @intFromPtr(self.render_targets[current_back_buffer_index]),
            .width = self.width,
            .height = self.height,
            .depth = 1,
            .mip_levels = 1,
            .array_layers = 1,
            .format = .rgba8_unorm_srgb,
            .usage = .{ .render_target = true },
            .sample_count = 1,
        };
    }

    pub fn getBackendInfo(self: *Self) interface.BackendInfo {
        var info = interface.BackendInfo{
            .name = "DirectX 12",
            .version = "12.0",
            .vendor = "Microsoft",
            .device_name = "D3D12 Device",
            .api_version = "DirectX 12",
            .driver_version = "Unknown",
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 16384,
            .max_render_targets = 8,
            .max_vertex_attributes = 32,
            .max_uniform_buffer_bindings = 14,
            .max_texture_bindings = 128,
            .supports_compute = true,
            .supports_geometry_shaders = true,
            .supports_tessellation = true,
            .supports_raytracing = true,
            .supports_mesh_shaders = true,
            .supports_variable_rate_shading = true,
            .supports_multiview = true,
        };

        if (self.adapter) |adapter| {
            var adapter_desc: c.DXGI_ADAPTER_DESC1 = undefined;
            if (adapter.lpVtbl.*.GetDesc1.?(adapter, &adapter_desc) == c.S_OK) {
                info.memory_budget = adapter_desc.DedicatedVideoMemory;
            }
        }

        return info;
    }
};

/// Create and initialize a D3D12 backend, returning a pointer to the interface.GraphicsBackend.
pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
    if (!build_options.d3d12_available) {
        return interface.GraphicsBackendError.BackendNotSupported;
    }

    var backend = try allocator.create(D3D12Backend);
    backend.* = D3D12Backend{
        .allocator = allocator,
    };

    // Enable debug layer in debug builds
    if (build_options.build_mode == .Debug) {
        backend.enableDebugLayer();
    }

    try backend.createDevice();
    try backend.createCommandQueue();
    try backend.createDescriptorHeaps();
    try backend.createSyncObjects();

    backend.initialized = true;

    const graphics_backend = try allocator.create(interface.GraphicsBackend);
    graphics_backend.* = interface.GraphicsBackend{
        .allocator = allocator,
        .backend_type = .d3d12,
        .initialized = true,
        .vtable = &D3D12Backend.vtable, // You may need to define this if not present
        .impl_data = backend,
    };
    return graphics_backend;
}

// Stub implementations for unimplemented functions
fn createTextureStub(ptr: *anyopaque, desc: types.TextureDesc) interface.GraphicsBackendError!types.Texture {
    _ = ptr;
    _ = desc;
    return interface.GraphicsBackendError.NotImplemented;
}

fn createBufferStub(ptr: *anyopaque, desc: types.BufferDesc) interface.GraphicsBackendError!types.Buffer {
    _ = ptr;
    _ = desc;
    return interface.GraphicsBackendError.NotImplemented;
}

fn createShaderStub(ptr: *anyopaque, desc: types.ShaderDesc) interface.GraphicsBackendError!types.Shader {
    _ = ptr;
    _ = desc;
    return interface.GraphicsBackendError.NotImplemented;
}

fn createPipelineStub(ptr: *anyopaque, desc: interface.PipelineDesc) interface.GraphicsBackendError!interface.Pipeline {
    _ = ptr;
    _ = desc;
    return interface.GraphicsBackendError.NotImplemented;
}

fn createRenderTargetStub(ptr: *anyopaque, desc: types.RenderTargetDesc) interface.GraphicsBackendError!types.RenderTarget {
    _ = ptr;
    _ = desc;
    return interface.GraphicsBackendError.NotImplemented;
}

fn updateBufferStub(ptr: *anyopaque, buffer: types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = buffer;
    _ = offset;
    _ = data;
    return interface.GraphicsBackendError.NotImplemented;
}

fn updateTextureStub(ptr: *anyopaque, texture: types.Texture, desc: types.TextureUpdateDesc, data: []const u8) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = texture;
    _ = desc;
    _ = data;
    return interface.GraphicsBackendError.NotImplemented;
}

fn destroyTextureStub(ptr: *anyopaque, texture: types.Texture) void {
    _ = ptr;
    _ = texture;
}

fn destroyBufferStub(ptr: *anyopaque, buffer: types.Buffer) void {
    _ = ptr;
    _ = buffer;
}

fn destroyShaderStub(ptr: *anyopaque, shader: types.Shader) void {
    _ = ptr;
    _ = shader;
}

fn destroyRenderTargetStub(ptr: *anyopaque, render_target: types.RenderTarget) void {
    _ = ptr;
    _ = render_target;
}

fn createCommandBufferStub(ptr: *anyopaque) interface.GraphicsBackendError!interface.CommandBuffer {
    _ = ptr;
    return interface.GraphicsBackendError.NotImplemented;
}

fn beginCommandBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    return interface.GraphicsBackendError.NotImplemented;
}

fn endCommandBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    return interface.GraphicsBackendError.NotImplemented;
}

fn submitCommandBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    return interface.GraphicsBackendError.NotImplemented;
}

fn beginRenderPassStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, desc: interface.RenderPassDesc) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = desc;
    return interface.GraphicsBackendError.NotImplemented;
}

fn endRenderPassStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    return interface.GraphicsBackendError.NotImplemented;
}

fn setViewportStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, viewport: types.Viewport) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = viewport;
    return interface.GraphicsBackendError.NotImplemented;
}

fn setScissorStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, scissor: types.Rect) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = scissor;
    return interface.GraphicsBackendError.NotImplemented;
}

fn bindPipelineStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, pipeline: interface.Pipeline) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = pipeline;
    return interface.GraphicsBackendError.NotImplemented;
}

fn bindVertexBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, slot: u32, buffer: types.Buffer, offset: u64, stride: u32) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = slot;
    _ = buffer;
    _ = offset;
    _ = stride;
    return interface.GraphicsBackendError.NotImplemented;
}

fn bindIndexBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, buffer: types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = buffer;
    _ = offset;
    _ = format;
    return interface.GraphicsBackendError.NotImplemented;
}

fn bindTextureStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, slot: u32, texture: types.Texture) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = slot;
    _ = texture;
    return interface.GraphicsBackendError.NotImplemented;
}

fn bindUniformBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, slot: u32, buffer: types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = slot;
    _ = buffer;
    _ = offset;
    _ = size;
    return interface.GraphicsBackendError.NotImplemented;
}

fn drawStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, command: interface.DrawCommand) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = command;
    return interface.GraphicsBackendError.NotImplemented;
}

fn drawIndexedStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, command: interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = command;
    return interface.GraphicsBackendError.NotImplemented;
}

fn dispatchStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, command: interface.DispatchCommand) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = command;
    return interface.GraphicsBackendError.NotImplemented;
}

fn copyBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, src: types.Buffer, dst: types.Buffer, region: interface.BufferCopyRegion) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = src;
    _ = dst;
    _ = region;
    return interface.GraphicsBackendError.NotImplemented;
}

fn copyTextureStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, src: types.Texture, dst: types.Texture, region: interface.TextureCopyRegion) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = src;
    _ = dst;
    _ = region;
    return interface.GraphicsBackendError.NotImplemented;
}

fn copyBufferToTextureStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, src: types.Buffer, dst: types.Texture, region: interface.TextureCopyRegion) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = src;
    _ = dst;
    _ = region;
    return interface.GraphicsBackendError.NotImplemented;
}

fn copyTextureToBufferStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, src: types.Texture, dst: types.Buffer, region: interface.TextureCopyRegion) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = src;
    _ = dst;
    _ = region;
    return interface.GraphicsBackendError.NotImplemented;
}

fn resourceBarrierStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, barrier: interface.ResourceBarrier) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = barrier;
    return interface.GraphicsBackendError.NotImplemented;
}

fn setDebugNameStub(ptr: *anyopaque, resource_type: []const u8, handle: u64, name: []const u8) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = resource_type;
    _ = handle;
    _ = name;
    return interface.GraphicsBackendError.NotImplemented;
}

fn beginDebugGroupStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    _ = name;
    return interface.GraphicsBackendError.NotImplemented;
}

fn endDebugGroupStub(ptr: *anyopaque, cmd_buffer: interface.CommandBuffer) interface.GraphicsBackendError!void {
    _ = ptr;
    _ = cmd_buffer;
    return interface.GraphicsBackendError.NotImplemented;
}
