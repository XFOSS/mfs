const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const interface = @import("../interface.zig");
const types = @import("../../types.zig");
const common = @import("../common.zig");

// DirectX 12 C bindings
const c = @cImport({
    @cDefine("COBJMACROS", "");
    @cDefine("WIN32_LEAN_AND_MEAN", "");
    @cInclude("windows.h");
    @cInclude("d3d12.h");
    @cInclude("dxgi1_4.h");
    @cInclude("d3dcompiler.h");
});

// DirectX 12 Ray Tracing constants (may not be defined in older headers)
const D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE: c_uint = 0x01;
const D3D12_RAYTRACING_INSTANCE_FLAG_TRIANGLE_FRONT_COUNTERCLOCKWISE: c_uint = 0x01;
const D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE: c_uint = 0x02;

// Helper constants
const FRAME_COUNT = 3;
const D3D12_COMMAND_LIST_TYPE_DIRECT = 0;
const D3D12_DESCRIPTOR_HEAP_TYPE_RTV = 0;
const D3D12_DESCRIPTOR_HEAP_TYPE_DSV = 1;
const D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV = 2;
const DXGI_FORMAT_R8G8B8A8_UNORM = 28;
const DXGI_FORMAT_D32_FLOAT = 40;
const DXGI_SWAP_EFFECT_FLIP_DISCARD = 4;

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

pub const D3D12Backend = struct {
    /// Shared base functionality
    base: common.BackendBase,
    allocator: std.mem.Allocator,
    device: ?*c.ID3D12Device = null,
    command_queue: ?*c.ID3D12CommandQueue = null,
    swap_chain: ?*c.IDXGISwapChain3 = null,
    factory: ?*c.IDXGIFactory4 = null,
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

    // Ray tracing support (DXR)
    rt_device: ?*c.ID3D12Device5 = null,
    rt_command_list: ?*c.ID3D12GraphicsCommandList4 = null,
    rt_pipeline: ?*c.ID3D12StateObject = null,
    rt_blas: ?*c.ID3D12Resource = null, // Bottom-level acceleration structure
    rt_tlas: ?*c.ID3D12Resource = null, // Top-level acceleration structure
    rt_descriptor_heap: ?*c.ID3D12DescriptorHeap = null,
    rt_output_buffer: ?*c.ID3D12Resource = null,
    rt_shader_table: ?*c.ID3D12Resource = null,
    rt_enabled: bool = false,

    const Self = @This();

    // VTable implementation
    pub const vtable = interface.GraphicsBackend.VTable{
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

    /// Create and initialize a D3D12 backend, returning a pointer to interface.GraphicsBackend.
    /// Returns BackendNotSupported if DirectX 12 is unavailable.
    pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        var backend = try allocator.create(D3D12Backend);
        const debug_mode = (builtin.mode == .Debug);
        backend.* = D3D12Backend{
            .base = try common.BackendBase.init(allocator, debug_mode),
            .allocator = allocator,
            .device = null,
            .command_queue = null,
            .swap_chain = null,
            .factory = null,
            .command_list = null,
            .fence = null,
            .fence_event = null,
            .fence_values = [_]u64{0} ** FRAME_COUNT,
            .frame_index = 0,
            .render_targets = [_]?*c.ID3D12Resource{null} ** FRAME_COUNT,
            .rtv_heap = null,
            .rtv_descriptor_size = 0,
            .width = 0,
            .height = 0,
            .vsync = true,
            .initialized = false,
            .rt_enabled = false,
            .rt_device = null,
            .rt_command_list = null,
            .rt_pipeline = null,
            .rt_descriptor_heap = null,
            .rt_blas = null,
            .rt_tlas = null,
        };

        // Initialize D3D12 if available
        if (builtin.os.tag == .windows) {
            backend.enableDebugLayer();
            try backend.createDevice();
            try backend.createCommandQueue();
            try backend.createDescriptorHeaps();
            try backend.createSyncObjects();
            backend.initialized = true;
        } else {
            return interface.GraphicsBackendError.BackendNotAvailable;
        }

        // Create the interface wrapper
        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .d3d12,
            .initialized = true,
            .vtable = &vtable,
            .impl_data = backend,
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
        if (c.CreateDXGIFactory2(0, &c.IID_IDXGIFactory4, @ptrCast(&self.factory)) != c.S_OK) {
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

                // Try to enable ray tracing
                if (self.device) |device| {
                    self.initializeRayTracing(device) catch |err| {
                        std.log.warn("Ray tracing initialization failed: {}", .{err});
                        self.rt_enabled = false;
                    };
                }
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

    fn initializeRayTracing(self: *Self, device: *c.ID3D12Device) !void {
        // Query for ray tracing device interface (ID3D12Device5)
        const hr = device.lpVtbl.*.QueryInterface.?(device, &c.IID_ID3D12Device5, @ptrCast(&self.rt_device));
        if (hr != c.S_OK) {
            return error.RayTracingNotSupported;
        }

        // Check ray tracing tier support
        var rt_options: c.D3D12_FEATURE_DATA_D3D12_OPTIONS5 = undefined;
        const feature_hr = device.lpVtbl.*.CheckFeatureSupport.?(
            device,
            c.D3D12_FEATURE_D3D12_OPTIONS5,
            &rt_options,
            @sizeOf(c.D3D12_FEATURE_DATA_D3D12_OPTIONS5),
        );

        if (feature_hr != c.S_OK or rt_options.RaytracingTier == c.D3D12_RAYTRACING_TIER_NOT_SUPPORTED) {
            return error.RayTracingNotSupported;
        }

        // Upgrade command list to ray tracing version
        if (self.command_list) |cmd_list| {
            const list_hr = cmd_list.lpVtbl.*.QueryInterface.?(cmd_list, &c.IID_ID3D12GraphicsCommandList4, @ptrCast(&self.rt_command_list));
            if (list_hr != c.S_OK) {
                return error.RayTracingCommandListFailed;
            }
        }

        // Create ray tracing descriptor heap
        try self.createRayTracingDescriptorHeap();

        self.rt_enabled = true;
        std.log.info("DirectX Ray Tracing (DXR) initialized successfully", .{});
    }

    fn createRayTracingDescriptorHeap(self: *Self) !void {
        const heap_desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = c.D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
            .NumDescriptors = 3, // For TLAS, output texture, and global root signature
            .Flags = c.D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
            .NodeMask = 0,
        };

        if (self.rt_device.?.lpVtbl.*.CreateDescriptorHeap.?(
            self.rt_device.?,
            &heap_desc,
            &c.IID_ID3D12DescriptorHeap,
            @ptrCast(&self.rt_descriptor_heap),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }
    }

    fn createBottomLevelAS(self: *Self, vertices: []const f32, indices: []const u32) !void {
        if (!self.rt_enabled or self.rt_device == null) return error.RayTracingNotEnabled;

        // Create vertex buffer
        var vertex_buffer: ?*c.ID3D12Resource = null;
        try self.createRayTracingBuffer(vertices.len * @sizeOf(f32), @ptrCast(vertices.ptr), &vertex_buffer);

        // Create index buffer
        var index_buffer: ?*c.ID3D12Resource = null;
        try self.createRayTracingBuffer(indices.len * @sizeOf(u32), @ptrCast(indices.ptr), &index_buffer);

        // Define geometry description
        var geometry_desc: c.D3D12_RAYTRACING_GEOMETRY_DESC = undefined;
        geometry_desc.Type = c.D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES;
        geometry_desc.Flags = D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE;
        geometry_desc.Triangles.VertexBuffer.StartAddress = vertex_buffer.?.lpVtbl.*.GetGPUVirtualAddress.?(vertex_buffer.?);
        geometry_desc.Triangles.VertexBuffer.StrideInBytes = 3 * @sizeOf(f32); // 3 floats per vertex
        geometry_desc.Triangles.VertexFormat = c.DXGI_FORMAT_R32G32B32_FLOAT;
        geometry_desc.Triangles.VertexCount = @intCast(vertices.len / 3);
        geometry_desc.Triangles.IndexBuffer = index_buffer.?.lpVtbl.*.GetGPUVirtualAddress.?(index_buffer.?);
        geometry_desc.Triangles.IndexFormat = c.DXGI_FORMAT_R32_UINT;
        geometry_desc.Triangles.IndexCount = @intCast(indices.len);

        // Get BLAS prebuild info
        var as_inputs: c.D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS = undefined;
        as_inputs.Type = c.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;
        as_inputs.Flags = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;
        as_inputs.NumDescs = 1;
        as_inputs.DescsLayout = c.D3D12_ELEMENTS_LAYOUT_ARRAY;
        as_inputs.pGeometryDescs = &geometry_desc;

        var prebuild_info: c.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO = undefined;
        self.rt_device.?.lpVtbl.*.GetRaytracingAccelerationStructurePrebuildInfo.?(self.rt_device.?, &as_inputs, &prebuild_info);

        // Create BLAS buffer
        try self.createAccelerationStructureBuffer(prebuild_info.ResultDataMaxSizeInBytes, &self.rt_blas);

        // Create scratch buffer for building
        var scratch_buffer: ?*c.ID3D12Resource = null;
        try self.createAccelerationStructureBuffer(prebuild_info.ScratchDataSizeInBytes, &scratch_buffer);
        defer {
            if (scratch_buffer) |buf| {
                _ = buf.lpVtbl.*.Release.?(buf);
            }
        }

        // Build the acceleration structure
        var as_build_desc: c.D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC = undefined;
        as_build_desc.Inputs = as_inputs;
        as_build_desc.ScratchDataSizeInBytes = scratch_buffer.?.lpVtbl.*.GetGPUVirtualAddress.?(scratch_buffer.?);
        as_build_desc.DestAccelerationStructureData = self.rt_blas.?.lpVtbl.*.GetGPUVirtualAddress.?(self.rt_blas.?);

        if (self.rt_command_list) |cmd_list| {
            cmd_list.lpVtbl.*.BuildRaytracingAccelerationStructure.?(cmd_list, &as_build_desc, 0, null);
        }

        // Add UAV barrier for BLAS
        if (self.rt_command_list) |cmd_list| {
            var uav_barrier: c.D3D12_RESOURCE_BARRIER = undefined;
            uav_barrier.Type = c.D3D12_RESOURCE_BARRIER_TYPE_UAV;
            uav_barrier.Flags = c.D3D12_RESOURCE_BARRIER_FLAG_NONE;
            uav_barrier.UAV.pResource = self.rt_blas.?;
            cmd_list.lpVtbl.*.ResourceBarrier.?(cmd_list, 1, &uav_barrier);
        }

        // Cleanup vertex and index buffers
        if (vertex_buffer) |buf| _ = buf.lpVtbl.*.Release.?(buf);
        if (index_buffer) |buf| _ = buf.lpVtbl.*.Release.?(buf);
    }

    fn createTopLevelAS(self: *Self, instance_count: u32) !void {
        if (!self.rt_enabled or self.rt_device == null) return error.RayTracingNotEnabled;

        // Create instance description buffer
        var instance_desc: c.D3D12_RAYTRACING_INSTANCE_DESC = undefined;

        // Identity transform matrix
        const identity_matrix = [_]f32{
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
        };
        @memcpy(&instance_desc.Transform, &identity_matrix);

        instance_desc.InstanceID = 0;
        instance_desc.InstanceMask = 0xFF;
        instance_desc.InstanceContributionToHitGroupIndex = 0;
        instance_desc.Flags = D3D12_RAYTRACING_INSTANCE_FLAG_TRIANGLE_FRONT_COUNTERCLOCKWISE;
        instance_desc.AccelerationStructure = self.rt_blas.?.lpVtbl.*.GetGPUVirtualAddress.?(self.rt_blas.?);

        // Create instance buffer
        var instance_buffer: ?*c.ID3D12Resource = null;
        try self.createRayTracingBuffer(@sizeOf(c.D3D12_RAYTRACING_INSTANCE_DESC), @ptrCast(&instance_desc), &instance_buffer);
        defer {
            if (instance_buffer) |buf| {
                _ = buf.lpVtbl.*.Release.?(buf);
            }
        }

        // Get TLAS prebuild info
        var as_inputs: c.D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS = undefined;
        as_inputs.Type = c.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;
        as_inputs.Flags = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;
        as_inputs.NumDescs = instance_count;
        as_inputs.DescsLayout = c.D3D12_ELEMENTS_LAYOUT_ARRAY;
        as_inputs.InstanceDescs = instance_buffer.?.lpVtbl.*.GetGPUVirtualAddress.?(instance_buffer.?);

        var prebuild_info: c.D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO = undefined;
        self.rt_device.?.lpVtbl.*.GetRaytracingAccelerationStructurePrebuildInfo.?(self.rt_device.?, &as_inputs, &prebuild_info);

        // Create TLAS buffer
        try self.createAccelerationStructureBuffer(prebuild_info.ResultDataMaxSizeInBytes, &self.rt_tlas);

        // Create scratch buffer
        var scratch_buffer: ?*c.ID3D12Resource = null;
        try self.createAccelerationStructureBuffer(prebuild_info.ScratchDataSizeInBytes, &scratch_buffer);
        defer {
            if (scratch_buffer) |buf| {
                _ = buf.lpVtbl.*.Release.?(buf);
            }
        }

        // Build TLAS
        var as_build_desc: c.D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC = undefined;
        as_build_desc.Inputs = as_inputs;
        as_build_desc.ScratchDataSizeInBytes = scratch_buffer.?.lpVtbl.*.GetGPUVirtualAddress.?(scratch_buffer.?);
        as_build_desc.DestAccelerationStructureData = self.rt_tlas.?.lpVtbl.*.GetGPUVirtualAddress.?(self.rt_tlas.?);

        if (self.rt_command_list) |cmd_list| {
            cmd_list.lpVtbl.*.BuildRaytracingAccelerationStructure.?(cmd_list, &as_build_desc, 0, null);
        }
    }

    fn createRayTracingBuffer(self: *Self, size: u64, data: ?*const anyopaque, buffer: **c.ID3D12Resource) !void {
        const heap_props = c.D3D12_HEAP_PROPERTIES{
            .Type = c.D3D12_HEAP_TYPE_UPLOAD,
            .CPUPageProperty = c.D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            .MemoryPoolPreference = c.D3D12_MEMORY_POOL_UNKNOWN,
            .CreationNodeMask = 1,
            .VisibleNodeMask = 1,
        };

        const buffer_desc = c.D3D12_RESOURCE_DESC{
            .Dimension = c.D3D12_RESOURCE_DIMENSION_BUFFER,
            .Alignment = 0,
            .Width = size,
            .Height = 1,
            .DepthOrArraySize = 1,
            .MipLevels = 1,
            .Format = c.DXGI_FORMAT_UNKNOWN,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = c.D3D12_TEXTURE_LAYOUT_ROW_MAJOR,
            .Flags = c.D3D12_RESOURCE_FLAG_NONE,
        };

        if (self.rt_device.?.lpVtbl.*.CreateCommittedResource.?(
            self.rt_device.?,
            &heap_props,
            c.D3D12_HEAP_FLAG_NONE,
            &buffer_desc,
            c.D3D12_RESOURCE_STATE_GENERIC_READ,
            null,
            &c.IID_ID3D12Resource,
            @ptrCast(buffer),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        // Copy data if provided
        if (data) |src_data| {
            var mapped_data: ?*anyopaque = null;
            if (buffer.*.*.lpVtbl.*.Map.?(buffer.*.*, 0, null, &mapped_data) == c.S_OK) {
                @memcpy(@as([*]u8, @ptrCast(mapped_data))[0..size], @as([*]const u8, @ptrCast(src_data))[0..size]);
                buffer.*.*.lpVtbl.*.Unmap.?(buffer.*.*, 0, null);
            }
        }
    }

    fn createAccelerationStructureBuffer(self: *Self, size: u64, buffer: **c.ID3D12Resource) !void {
        const heap_props = c.D3D12_HEAP_PROPERTIES{
            .Type = c.D3D12_HEAP_TYPE_DEFAULT,
            .CPUPageProperty = c.D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            .MemoryPoolPreference = c.D3D12_MEMORY_POOL_UNKNOWN,
            .CreationNodeMask = 1,
            .VisibleNodeMask = 1,
        };

        const buffer_desc = c.D3D12_RESOURCE_DESC{
            .Dimension = c.D3D12_RESOURCE_DIMENSION_BUFFER,
            .Alignment = 0,
            .Width = size,
            .Height = 1,
            .DepthOrArraySize = 1,
            .MipLevels = 1,
            .Format = c.DXGI_FORMAT_UNKNOWN,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = c.D3D12_TEXTURE_LAYOUT_ROW_MAJOR,
            .Flags = c.D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,
        };

        if (self.rt_device.?.lpVtbl.*.CreateCommittedResource.?(
            self.rt_device.?,
            &heap_props,
            c.D3D12_HEAP_FLAG_NONE,
            &buffer_desc,
            c.D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE,
            null,
            &c.IID_ID3D12Resource,
            @ptrCast(buffer),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }
    }

    fn dispatchRays(self: *Self, width: u32, height: u32) !void {
        if (!self.rt_enabled or self.rt_command_list == null) return error.RayTracingNotEnabled;

        // Set ray tracing pipeline and descriptor heaps
        if (self.rt_pipeline) |pipeline| {
            self.rt_command_list.?.lpVtbl.*.SetPipelineState1.?(self.rt_command_list.?, pipeline);
        }

        if (self.rt_descriptor_heap) |heap| {
            const heaps = [_]?*c.ID3D12DescriptorHeap{heap};
            self.rt_command_list.?.lpVtbl.*.SetDescriptorHeaps.?(self.rt_command_list.?, 1, &heaps);
        }

        // Set up dispatch rays description
        var dispatch_desc: c.D3D12_DISPATCH_RAYS_DESC = undefined;

        // Ray generation shader
        if (self.rt_shader_table) |shader_table| {
            dispatch_desc.RayGenerationShaderRecord.StartAddress = shader_table.lpVtbl.*.GetGPUVirtualAddress.?(shader_table);
            dispatch_desc.RayGenerationShaderRecord.SizeInBytes = 32; // Shader identifier size
        }

        // Miss shaders
        dispatch_desc.MissShaderTable.StartAddress = 0;
        dispatch_desc.MissShaderTable.SizeInBytes = 0;
        dispatch_desc.MissShaderTable.StrideInBytes = 0;

        // Hit groups
        dispatch_desc.HitGroupTable.StartAddress = 0;
        dispatch_desc.HitGroupTable.SizeInBytes = 0;
        dispatch_desc.HitGroupTable.StrideInBytes = 0;

        // Callable shaders
        dispatch_desc.CallableShaderTable.StartAddress = 0;
        dispatch_desc.CallableShaderTable.SizeInBytes = 0;
        dispatch_desc.CallableShaderTable.StrideInBytes = 0;

        // Dispatch dimensions
        dispatch_desc.Width = width;
        dispatch_desc.Height = height;
        dispatch_desc.Depth = 1;

        // Dispatch the rays
        self.rt_command_list.?.lpVtbl.*.DispatchRays.?(self.rt_command_list.?, &dispatch_desc);
    }

    fn createCommandQueue(self: *Self) !void {
        const queue_desc = c.D3D12_COMMAND_QUEUE_DESC{
            .Type = D3D12_COMMAND_LIST_TYPE_DIRECT,
            .Priority = 0,
            .Flags = c.D3D12_COMMAND_QUEUE_FLAG_NONE,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateCommandQueue.?(
            self.device.?,
            &queue_desc,
            &c.IID_ID3D12CommandQueue,
            @ptrCast(&self.command_queue),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }
    }

    fn createDescriptorHeaps(self: *Self) !void {
        // Create RTV descriptor heap
        const rtv_heap_desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
            .NumDescriptors = FRAME_COUNT,
            .Flags = c.D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateDescriptorHeap.?(
            self.device.?,
            &rtv_heap_desc,
            &c.IID_ID3D12DescriptorHeap,
            @ptrCast(&self.rtv_heap),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        self.rtv_descriptor_size = self.device.?.lpVtbl.*.GetDescriptorHandleIncrementSize.?(
            self.device.?,
            D3D12_DESCRIPTOR_HEAP_TYPE_RTV,
        );

        // Create DSV descriptor heap
        const dsv_heap_desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = D3D12_DESCRIPTOR_HEAP_TYPE_DSV,
            .NumDescriptors = 1,
            .Flags = c.D3D12_DESCRIPTOR_HEAP_FLAG_NONE,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateDescriptorHeap.?(
            self.device.?,
            &dsv_heap_desc,
            &c.IID_ID3D12DescriptorHeap,
            @ptrCast(&self.dsv_heap),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        self.dsv_descriptor_size = self.device.?.lpVtbl.*.GetDescriptorHandleIncrementSize.?(
            self.device.?,
            D3D12_DESCRIPTOR_HEAP_TYPE_DSV,
        );

        // Create CBV/SRV/UAV descriptor heap
        const cbv_heap_desc = c.D3D12_DESCRIPTOR_HEAP_DESC{
            .Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
            .NumDescriptors = 1000, // Large heap for resources
            .Flags = c.D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
            .NodeMask = 0,
        };

        if (self.device.?.lpVtbl.*.CreateDescriptorHeap.?(
            self.device.?,
            &cbv_heap_desc,
            &c.IID_ID3D12DescriptorHeap,
            @ptrCast(&self.cbv_srv_uav_heap),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        self.cbv_srv_uav_descriptor_size = self.device.?.lpVtbl.*.GetDescriptorHandleIncrementSize.?(
            self.device.?,
            D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
        );
    }

    fn createSyncObjects(self: *Self) !void {
        // Create fence
        if (self.device.?.lpVtbl.*.CreateFence.?(
            self.device.?,
            0,
            c.D3D12_FENCE_FLAG_NONE,
            &c.IID_ID3D12Fence,
            @ptrCast(&self.fence),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // Create fence event
        self.fence_event = c.CreateEventW(null, c.FALSE, c.FALSE, null);
        if (self.fence_event == null) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // Create command allocators
        for (0..FRAME_COUNT) |i| {
            if (self.device.?.lpVtbl.*.CreateCommandAllocator.?(
                self.device.?,
                D3D12_COMMAND_LIST_TYPE_DIRECT,
                &c.IID_ID3D12CommandAllocator,
                @ptrCast(&self.command_allocators[i]),
            ) != c.S_OK) {
                return interface.GraphicsBackendError.InitializationFailed;
            }
        }

        // Create command list
        if (self.device.?.lpVtbl.*.CreateCommandList.?(
            self.device.?,
            0,
            D3D12_COMMAND_LIST_TYPE_DIRECT,
            self.command_allocators[0],
            null,
            &c.IID_ID3D12GraphicsCommandList,
            @ptrCast(&self.command_list),
        ) != c.S_OK) {
            return interface.GraphicsBackendError.InitializationFailed;
        }

        // Close the command list initially
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
        if (self.rt_descriptor_heap) |heap| _ = heap.lpVtbl.*.Release.?(heap);
        if (self.swap_chain) |sc| _ = sc.lpVtbl.*.Release.?(sc);
        if (self.command_queue) |cq| _ = cq.lpVtbl.*.Release.?(cq);
        if (self.device) |d| _ = d.lpVtbl.*.Release.?(d);
        if (self.adapter) |a| _ = a.lpVtbl.*.Release.?(a);
        if (self.factory) |f| _ = f.lpVtbl.*.Release.?(f);

        self.initialized = false;

        // Deinit shared base resources
        self.base.deinit();
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

        self.window_handle = @ptrCast(@alignCast(desc.window_handle));
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

        // Query for SwapChain3 interface
        if (temp_swap_chain.?.lpVtbl.*.QueryInterface.?(temp_swap_chain.?, &c.IID_IDXGISwapChain3, @ptrCast(&self.swap_chain)) != c.S_OK) {
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
            .vsync = self.vsync,
            .window_handle = desc.window_handle,
        };
    }

    fn createRenderTargets(self: *Self) !void {
        var rtv_handle: c.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
        _ = self.rtv_heap.?.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(self.rtv_heap.?, &rtv_handle);

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
            .api_version = 12,
            .driver_version = 0,
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

    // VTable implementation functions
    fn deinitImpl(impl: *anyopaque) void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));
        self.deinit();
    }

    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));
        _ = self.createSwapChain(desc.*) catch |err| switch (err) {
            error.NotInitialized => return interface.GraphicsBackendError.InitializationFailed,
            error.InitializationFailed => return interface.GraphicsBackendError.InitializationFailed,
            else => return interface.GraphicsBackendError.InitializationFailed,
        };
    }

    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));
        return self.resizeSwapChain(width, height);
    }

    fn presentImpl(impl: *anyopaque) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));
        return self.present();
    }

    fn getCurrentBackBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));
        const texture = self.getCurrentBackBuffer() catch |err| switch (err) {
            error.NotInitialized => return interface.GraphicsBackendError.InitializationFailed,
            else => return interface.GraphicsBackendError.InitializationFailed,
        };

        // Allocate texture on heap and return pointer
        const texture_ptr = self.allocator.create(types.Texture) catch return interface.GraphicsBackendError.OutOfMemory;
        texture_ptr.* = texture;
        return texture_ptr;
    }

    fn getBackendInfoImpl(impl: *anyopaque) interface.BackendInfo {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));
        return self.getBackendInfo();
    }

    // Stub implementations for unimplemented functions
    fn createTextureImpl(impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        // Convert texture format to DXGI format
        const dxgi_format = textureFormatToDxgi(texture.format);

        // Create resource description
        var resource_desc = c.D3D12_RESOURCE_DESC{
            .Dimension = c.D3D12_RESOURCE_DIMENSION_TEXTURE2D,
            .Alignment = 0,
            .Width = texture.width,
            .Height = texture.height,
            .DepthOrArraySize = @intCast(texture.depth),
            .MipLevels = @intCast(texture.mip_levels),
            .Format = dxgi_format,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = c.D3D12_TEXTURE_LAYOUT_UNKNOWN,
            .Flags = c.D3D12_RESOURCE_FLAG_NONE,
        };

        // Create heap properties for default heap
        const heap_props = c.D3D12_HEAP_PROPERTIES{
            .Type = c.D3D12_HEAP_TYPE_DEFAULT,
            .CPUPageProperty = c.D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            .MemoryPoolPreference = c.D3D12_MEMORY_POOL_UNKNOWN,
            .CreationNodeMask = 1,
            .VisibleNodeMask = 1,
        };

        var d3d_resource: ?*c.ID3D12Resource = null;
        const hr = self.device.?.lpVtbl.*.CreateCommittedResource.?(
            self.device.?,
            &heap_props,
            c.D3D12_HEAP_FLAG_NONE,
            &resource_desc,
            c.D3D12_RESOURCE_STATE_COPY_DEST,
            null,
            &c.IID_ID3D12Resource,
            @ptrCast(&d3d_resource),
        );

        if (hr != c.S_OK) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        texture.handle = @intFromPtr(d3d_resource.?);

        // Upload data if provided
        if (data) |texture_data| {
            try self.uploadTextureData(d3d_resource.?, texture, texture_data);
        }

        std.log.info("D3D12: Created texture {}x{} format={}", .{ texture.width, texture.height, texture.format });
    }

    fn createBufferImpl(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        // Create resource description
        var resource_desc = c.D3D12_RESOURCE_DESC{
            .Dimension = c.D3D12_RESOURCE_DIMENSION_BUFFER,
            .Alignment = 0,
            .Width = buffer.size,
            .Height = 1,
            .DepthOrArraySize = 1,
            .MipLevels = 1,
            .Format = c.DXGI_FORMAT_UNKNOWN,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = c.D3D12_TEXTURE_LAYOUT_ROW_MAJOR,
            .Flags = getBufferFlags(buffer.usage),
        };

        // Create heap properties
        const heap_type: c_uint = if (buffer.usage == .staging) c.D3D12_HEAP_TYPE_UPLOAD else c.D3D12_HEAP_TYPE_DEFAULT;
        const heap_props = c.D3D12_HEAP_PROPERTIES{
            .Type = heap_type,
            .CPUPageProperty = c.D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            .MemoryPoolPreference = c.D3D12_MEMORY_POOL_UNKNOWN,
            .CreationNodeMask = 1,
            .VisibleNodeMask = 1,
        };

        var d3d_resource: ?*c.ID3D12Resource = null;
        const initial_state: c_uint = if (buffer.usage == .staging) c.D3D12_RESOURCE_STATE_GENERIC_READ else @intCast(getBufferInitialState(buffer.usage));

        const hr = self.device.?.lpVtbl.*.CreateCommittedResource.?(
            self.device.?,
            &heap_props,
            c.D3D12_HEAP_FLAG_NONE,
            &resource_desc,
            initial_state,
            null,
            &c.IID_ID3D12Resource,
            @ptrCast(&d3d_resource),
        );

        if (hr != c.S_OK) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        buffer.handle = @intFromPtr(d3d_resource.?);

        // Upload data if provided
        if (data) |buffer_data| {
            try self.uploadBufferData(d3d_resource.?, buffer_data);
        }

        std.log.info("D3D12: Created buffer size={} usage={}", .{ buffer.size, buffer.usage });
    }

    fn createShaderImpl(impl: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        // Compile shader from source
        var blob: ?*c.ID3DBlob = null;
        var error_blob: ?*c.ID3DBlob = null;

        const target = getShaderTarget(shader.shader_type);
        if (target == null) {
            return interface.GraphicsBackendError.UnsupportedFormat;
        }

        // Try to load D3DCompiler at runtime
        if (!loadD3DCompiler()) {
            std.log.err("D3DCompiler not available - shader compilation disabled", .{});
            return interface.GraphicsBackendError.UnsupportedOperation;
        }

        // Convert target string to null-terminated
        const target_cstr = try std.fmt.allocPrintZ(self.allocator, "{s}", .{target.?});
        defer self.allocator.free(target_cstr);

        const hr = d3d_compile_func.?(
            shader.source.ptr,
            shader.source.len,
            null, // source name
            null, // defines
            null, // includes
            "main", // entry point
            target_cstr.ptr,
            c.D3DCOMPILE_ENABLE_STRICTNESS | c.D3DCOMPILE_OPTIMIZATION_LEVEL3,
            0,
            &blob,
            &error_blob,
        );

        if (hr != c.S_OK) {
            if (error_blob) |err| {
                const error_msg = @as([*:0]const u8, @ptrCast(err.lpVtbl.*.GetBufferPointer.?(err)));
                std.log.err("D3D12 Shader compilation failed: {s}", .{error_msg});
                _ = err.lpVtbl.*.Release.?(err);
            }
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        // Store the compiled shader blob
        shader.handle = @intFromPtr(blob.?);
        shader.compiled = true;

        std.log.info("D3D12: Compiled shader type={}", .{shader.shader_type});
    }

    fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        // Create pipeline object
        const pipeline = self.allocator.create(interface.Pipeline) catch return interface.GraphicsBackendError.OutOfMemory;

        // Create root signature (simplified version)
        var root_signature: ?*c.ID3D12RootSignature = null;
        try self.createRootSignature(&root_signature);

        // Create graphics pipeline state
        var pso_desc = std.mem.zeroes(c.D3D12_GRAPHICS_PIPELINE_STATE_DESC);
        pso_desc.pRootSignature = root_signature;

        // Set shaders
        if (desc.vertex_shader) |vs| {
            const blob = @as(*c.ID3DBlob, @ptrFromInt(vs.handle));
            pso_desc.VS.pShaderBytecode = blob.lpVtbl.*.GetBufferPointer.?(blob);
            pso_desc.VS.BytecodeLength = blob.lpVtbl.*.GetBufferSize.?(blob);
        }

        if (desc.fragment_shader) |ps| {
            const blob = @as(*c.ID3DBlob, @ptrFromInt(ps.handle));
            pso_desc.PS.pShaderBytecode = blob.lpVtbl.*.GetBufferPointer.?(blob);
            pso_desc.PS.BytecodeLength = blob.lpVtbl.*.GetBufferSize.?(blob);
        }

        // Set up input layout
        var input_elements: [16]c.D3D12_INPUT_ELEMENT_DESC = undefined;
        var element_count: u32 = 0;

        for (desc.vertex_layout.attributes) |attr| {
            if (element_count >= 16) break;

            input_elements[element_count] = c.D3D12_INPUT_ELEMENT_DESC{
                .SemanticName = getSemanticName(attr.location),
                .SemanticIndex = 0,
                .Format = vertexFormatToDxgi(attr.format),
                .InputSlot = 0,
                .AlignedByteOffset = attr.offset,
                .InputSlotClass = c.D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            };
            element_count += 1;
        }

        pso_desc.InputLayout.pInputElementDescs = &input_elements;
        pso_desc.InputLayout.NumElements = element_count;

        // Set primitive topology
        pso_desc.PrimitiveTopologyType = switch (desc.primitive_topology) {
            .points => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT,
            .lines => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE,
            .line_strip => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE,
            .triangles => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
            .triangle_strip => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
            .triangle_fan => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
            .lines_adjacency => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE,
            .line_strip_adjacency => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE,
            .triangles_adjacency => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
            .triangle_strip_adjacency => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
            .patches => c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_PATCH,
        };

        // Set render target formats
        pso_desc.NumRenderTargets = @intCast(@min(desc.render_target_formats.len, 8));
        for (desc.render_target_formats, 0..) |format, i| {
            if (i >= 8) break;
            pso_desc.RTVFormats[i] = textureFormatToDxgi(format);
        }

        if (desc.depth_format) |depth_format| {
            pso_desc.DSVFormat = textureFormatToDxgi(depth_format);
        }

        // Set rasterizer state
        pso_desc.RasterizerState = c.D3D12_RASTERIZER_DESC{
            .FillMode = c.D3D12_FILL_MODE_SOLID,
            .CullMode = c.D3D12_CULL_MODE_BACK,
            .FrontCounterClockwise = 0,
            .DepthBias = 0,
            .DepthBiasClamp = 0.0,
            .SlopeScaledDepthBias = 0.0,
            .DepthClipEnable = 1,
            .MultisampleEnable = 0,
            .AntialiasedLineEnable = 0,
            .ForcedSampleCount = 0,
            .ConservativeRaster = c.D3D12_CONSERVATIVE_RASTERIZATION_MODE_OFF,
        };

        // Set blend state
        pso_desc.BlendState = c.D3D12_BLEND_DESC{
            .AlphaToCoverageEnable = 0,
            .IndependentBlendEnable = 0,
            .RenderTarget = [_]c.D3D12_RENDER_TARGET_BLEND_DESC{c.D3D12_RENDER_TARGET_BLEND_DESC{
                .BlendEnable = if (desc.blend_state.enabled) 1 else 0,
                .LogicOpEnable = 0,
                .SrcBlend = blendFactorToD3D12(desc.blend_state.src_color),
                .DestBlend = blendFactorToD3D12(desc.blend_state.dst_color),
                .BlendOp = blendOpToD3D12(desc.blend_state.color_op),
                .SrcBlendAlpha = blendFactorToD3D12(desc.blend_state.src_alpha),
                .DestBlendAlpha = blendFactorToD3D12(desc.blend_state.dst_alpha),
                .BlendOpAlpha = blendOpToD3D12(desc.blend_state.alpha_op),
                .LogicOp = c.D3D12_LOGIC_OP_NOOP,
                .RenderTargetWriteMask = colorMaskToD3D12(desc.blend_state.color_mask),
            }} ** 8,
        };

        // Set depth stencil state
        pso_desc.DepthStencilState = c.D3D12_DEPTH_STENCIL_DESC{
            .DepthEnable = if (desc.depth_stencil_state.depth_test_enabled) 1 else 0,
            .DepthWriteMask = if (desc.depth_stencil_state.depth_write_enabled) c.D3D12_DEPTH_WRITE_MASK_ALL else c.D3D12_DEPTH_WRITE_MASK_ZERO,
            .DepthFunc = compareOpToD3D12(desc.depth_stencil_state.depth_compare),
            .StencilEnable = if (desc.depth_stencil_state.stencil_enabled) 1 else 0,
            .StencilReadMask = desc.depth_stencil_state.stencil_read_mask,
            .StencilWriteMask = desc.depth_stencil_state.stencil_write_mask,
            .FrontFace = c.D3D12_DEPTH_STENCILOP_DESC{
                .StencilFailOp = stencilOpToD3D12(desc.depth_stencil_state.front_face.fail),
                .StencilDepthFailOp = stencilOpToD3D12(desc.depth_stencil_state.front_face.depth_fail),
                .StencilPassOp = stencilOpToD3D12(desc.depth_stencil_state.front_face.pass),
                .StencilFunc = compareOpToD3D12(desc.depth_stencil_state.front_face.compare),
            },
            .BackFace = c.D3D12_DEPTH_STENCILOP_DESC{
                .StencilFailOp = stencilOpToD3D12(desc.depth_stencil_state.back_face.fail),
                .StencilDepthFailOp = stencilOpToD3D12(desc.depth_stencil_state.back_face.depth_fail),
                .StencilPassOp = stencilOpToD3D12(desc.depth_stencil_state.back_face.pass),
                .StencilFunc = compareOpToD3D12(desc.depth_stencil_state.back_face.compare),
            },
        };

        pso_desc.SampleMask = 0xFFFFFFFF;
        pso_desc.SampleDesc.Count = desc.sample_count;
        pso_desc.SampleDesc.Quality = 0;

        var d3d_pipeline: ?*c.ID3D12PipelineState = null;
        const hr = self.device.?.lpVtbl.*.CreateGraphicsPipelineState.?(
            self.device.?,
            &pso_desc,
            &c.IID_ID3D12PipelineState,
            @ptrCast(&d3d_pipeline),
        );

        if (hr != c.S_OK) {
            self.allocator.destroy(pipeline);
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }

        pipeline.* = interface.Pipeline{
            .id = @intFromPtr(d3d_pipeline.?),
            .backend_handle = d3d_pipeline.?,
            .allocator = self.allocator,
        };

        std.log.info("D3D12: Created graphics pipeline", .{});
        return pipeline;
    }

    fn createRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        // Create color texture if needed
        if (render_target.color_texture == null) {
            const color_texture = self.allocator.create(types.Texture) catch return interface.GraphicsBackendError.OutOfMemory;
            color_texture.* = types.Texture{
                .handle = 0,
                .width = render_target.width,
                .height = render_target.height,
                .depth = 1,
                .mip_levels = 1,
                .array_layers = 1,
                .format = .rgba8_unorm_srgb,
                .usage = .{ .render_target = true },
                .sample_count = 1,
            };

            try createTextureImpl(self, color_texture, null);
            render_target.color_texture = color_texture;
        }

        // Create depth texture if needed
        if (render_target.depth_texture == null) {
            const depth_texture = self.allocator.create(types.Texture) catch return interface.GraphicsBackendError.OutOfMemory;
            depth_texture.* = types.Texture{
                .handle = 0,
                .width = render_target.width,
                .height = render_target.height,
                .depth = 1,
                .mip_levels = 1,
                .array_layers = 1,
                .format = .depth32f,
                .usage = .{ .depth_stencil = true },
                .sample_count = 1,
            };

            try createTextureImpl(self, depth_texture, null);
            render_target.depth_texture = depth_texture;
        }

        render_target.handle = render_target.color_texture.?.handle;
        std.log.info("D3D12: Created render target {}x{}", .{ render_target.width, render_target.height });
    }

    fn updateBufferImpl(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        const d3d_resource = @as(*c.ID3D12Resource, @ptrFromInt(buffer.handle));

        // Map the buffer and copy data
        var mapped_data: ?*anyopaque = null;
        const read_range = c.D3D12_RANGE{ .Begin = 0, .End = 0 }; // We're not reading

        const hr = d3d_resource.lpVtbl.*.Map.?(d3d_resource, 0, &read_range, &mapped_data);
        if (hr != c.S_OK) {
            return interface.GraphicsBackendError.InvalidOperation;
        }

        // Copy data to mapped buffer
        const dest_ptr = @as([*]u8, @ptrCast(mapped_data.?)) + offset;
        @memcpy(dest_ptr[0..data.len], data);

        // Unmap the buffer
        const write_range = c.D3D12_RANGE{ .Begin = offset, .End = offset + data.len };
        d3d_resource.lpVtbl.*.Unmap.?(d3d_resource, 0, &write_range);

        std.log.info("D3D12: Updated buffer offset={} size={}", .{ offset, data.len });
    }

    fn updateTextureImpl(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (!self.initialized) return interface.GraphicsBackendError.NotInitialized;

        // For now, we'll implement a simple update that uploads data to the entire texture
        // A full implementation would handle the region parameter properly
        _ = region;

        const d3d_resource = @as(*c.ID3D12Resource, @ptrFromInt(texture.handle));
        try self.uploadTextureData(d3d_resource, texture, data);

        std.log.info("D3D12: Updated texture {}x{}", .{ texture.width, texture.height });
    }

    fn destroyTextureImpl(impl: *anyopaque, texture: *types.Texture) void {
        _ = impl;

        if (texture.handle != 0) {
            const d3d_resource = @as(*c.ID3D12Resource, @ptrFromInt(texture.handle));
            _ = d3d_resource.lpVtbl.*.Release.?(d3d_resource);
            texture.handle = 0;
        }
    }

    fn destroyBufferImpl(impl: *anyopaque, buffer: *types.Buffer) void {
        _ = impl;

        if (buffer.handle != 0) {
            const d3d_resource = @as(*c.ID3D12Resource, @ptrFromInt(buffer.handle));
            _ = d3d_resource.lpVtbl.*.Release.?(d3d_resource);
            buffer.handle = 0;
        }
    }

    fn destroyShaderImpl(impl: *anyopaque, shader: *types.Shader) void {
        _ = impl;

        if (shader.handle != 0) {
            const blob = @as(*c.ID3DBlob, @ptrFromInt(shader.handle));
            _ = blob.lpVtbl.*.Release.?(blob);
            shader.handle = 0;
            shader.compiled = false;
        }
    }

    fn destroyRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) void {
        const self = @as(*D3D12Backend, @ptrCast(@alignCast(impl)));

        if (render_target.color_texture) |color_tex| {
            destroyTextureImpl(self, color_tex);
            self.allocator.destroy(color_tex);
            render_target.color_texture = null;
        }

        if (render_target.depth_texture) |depth_tex| {
            destroyTextureImpl(self, depth_tex);
            self.allocator.destroy(depth_tex);
            render_target.depth_texture = null;
        }

        render_target.handle = 0;
    }

    fn createCommandBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*interface.CommandBuffer {
        _ = impl;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn beginCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn endCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn submitCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn beginRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = desc;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn endRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn setViewportImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = viewport;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn setScissorImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = rect;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindPipelineImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = pipeline;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindVertexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindIndexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = buffer;
        _ = offset;
        _ = format;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = texture;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn bindUniformBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
        _ = size;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn drawImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = draw_cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn drawIndexedImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = draw_cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn dispatchImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = dispatch_cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
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
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn setDebugNameImpl(impl: *anyopaque, resource: interface.ResourceHandle, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = resource;
        _ = name;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn beginDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = name;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn endDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    // Helper functions for DirectX 12 implementation

    fn uploadTextureData(self: *Self, resource: *c.ID3D12Resource, texture: *types.Texture, data: []const u8) !void {
        // Create upload buffer
        const upload_buffer_size = data.len;
        const upload_heap_props = c.D3D12_HEAP_PROPERTIES{
            .Type = c.D3D12_HEAP_TYPE_UPLOAD,
            .CPUPageProperty = c.D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
            .MemoryPoolPreference = c.D3D12_MEMORY_POOL_UNKNOWN,
            .CreationNodeMask = 1,
            .VisibleNodeMask = 1,
        };

        const upload_buffer_desc = c.D3D12_RESOURCE_DESC{
            .Dimension = c.D3D12_RESOURCE_DIMENSION_BUFFER,
            .Alignment = 0,
            .Width = upload_buffer_size,
            .Height = 1,
            .DepthOrArraySize = 1,
            .MipLevels = 1,
            .Format = c.DXGI_FORMAT_UNKNOWN,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Layout = c.D3D12_TEXTURE_LAYOUT_ROW_MAJOR,
            .Flags = c.D3D12_RESOURCE_FLAG_NONE,
        };

        var upload_buffer: ?*c.ID3D12Resource = null;
        const hr = self.device.?.lpVtbl.*.CreateCommittedResource.?(
            self.device.?,
            &upload_heap_props,
            c.D3D12_HEAP_FLAG_NONE,
            &upload_buffer_desc,
            c.D3D12_RESOURCE_STATE_GENERIC_READ,
            null,
            &c.IID_ID3D12Resource,
            @ptrCast(&upload_buffer),
        );

        if (hr != c.S_OK) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }
        defer _ = upload_buffer.?.lpVtbl.*.Release.?(upload_buffer.?);

        // Map upload buffer and copy data
        var mapped_data: ?*anyopaque = null;
        const read_range = c.D3D12_RANGE{ .Begin = 0, .End = 0 };

        const map_hr = upload_buffer.?.lpVtbl.*.Map.?(upload_buffer.?, 0, &read_range, &mapped_data);
        if (map_hr != c.S_OK) {
            return interface.GraphicsBackendError.InvalidOperation;
        }

        @memcpy(@as([*]u8, @ptrCast(mapped_data.?))[0..data.len], data);
        upload_buffer.?.lpVtbl.*.Unmap.?(upload_buffer.?, 0, null);

        // Copy from upload buffer to texture (this would need command list recording)
        // For now, we'll just log that we would do this
        _ = resource;
        _ = texture;

        std.log.info("D3D12: Would copy texture data via upload buffer", .{});
    }

    fn uploadBufferData(_: *Self, resource: *c.ID3D12Resource, data: []const u8) !void {
        // Map the buffer and copy data
        var mapped_data: ?*anyopaque = null;
        const read_range = c.D3D12_RANGE{ .Begin = 0, .End = 0 }; // We're not reading

        const hr = resource.lpVtbl.*.Map.?(resource, 0, &read_range, &mapped_data);
        if (hr != c.S_OK) {
            return interface.GraphicsBackendError.InvalidOperation;
        }

        @memcpy(@as([*]u8, @ptrCast(mapped_data.?))[0..data.len], data);

        const write_range = c.D3D12_RANGE{ .Begin = 0, .End = data.len };
        resource.lpVtbl.*.Unmap.?(resource, 0, &write_range);
    }

    fn createRootSignature(self: *Self, root_signature: *?*c.ID3D12RootSignature) !void {
        // Create a simple root signature with basic parameters
        var root_param = std.mem.zeroes(c.D3D12_ROOT_PARAMETER);
        root_param.ParameterType = c.D3D12_ROOT_PARAMETER_TYPE_CBV;
        // Workaround: Use std.mem.copy to write the descriptor data directly
        // Create the descriptor and copy it to the union location
        const descriptor = c.D3D12_ROOT_DESCRIPTOR{
            .ShaderRegister = 0,
            .RegisterSpace = 0,
        };

        // Copy the descriptor data into the union space (which starts after ParameterType)
        const union_start = @as([*]u8, @ptrCast(&root_param)) + @sizeOf(c.D3D12_ROOT_PARAMETER_TYPE);
        const descriptor_bytes = @as([*]const u8, @ptrCast(&descriptor));
        @memcpy(union_start[0..@sizeOf(c.D3D12_ROOT_DESCRIPTOR)], descriptor_bytes[0..@sizeOf(c.D3D12_ROOT_DESCRIPTOR)]);
        root_param.ShaderVisibility = c.D3D12_SHADER_VISIBILITY_ALL;

        const root_params = [_]c.D3D12_ROOT_PARAMETER{root_param};

        const root_sig_desc = c.D3D12_ROOT_SIGNATURE_DESC{
            .NumParameters = root_params.len,
            .pParameters = &root_params,
            .NumStaticSamplers = 0,
            .pStaticSamplers = null,
            .Flags = c.D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT,
        };

        var signature_blob: ?*c.ID3DBlob = null;
        var error_blob: ?*c.ID3DBlob = null;

        var hr = c.D3D12SerializeRootSignature(
            &root_sig_desc,
            c.D3D_ROOT_SIGNATURE_VERSION_1,
            &signature_blob,
            &error_blob,
        );

        if (hr != c.S_OK) {
            if (error_blob) |err| {
                _ = err.lpVtbl.*.Release.?(err);
            }
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }
        defer _ = signature_blob.?.lpVtbl.*.Release.?(signature_blob.?);

        hr = self.device.?.lpVtbl.*.CreateRootSignature.?(
            self.device.?,
            0,
            signature_blob.?.lpVtbl.*.GetBufferPointer.?(signature_blob.?),
            signature_blob.?.lpVtbl.*.GetBufferSize.?(signature_blob.?),
            &c.IID_ID3D12RootSignature,
            @ptrCast(root_signature),
        );

        if (hr != c.S_OK) {
            return interface.GraphicsBackendError.ResourceCreationFailed;
        }
    }

    // Format conversion functions

    fn textureFormatToDxgi(format: types.TextureFormat) u32 {
        return switch (format) {
            .rgba8, .rgba8_unorm => c.DXGI_FORMAT_R8G8B8A8_UNORM,
            .rgba8_unorm_srgb => c.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
            .bgra8, .bgra8_unorm => c.DXGI_FORMAT_B8G8R8A8_UNORM,
            .bgra8_unorm_srgb => c.DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
            .rgb8, .rgb8_unorm => c.DXGI_FORMAT_R8G8B8A8_UNORM, // No direct RGB8 format, use RGBA8
            .r8_unorm => c.DXGI_FORMAT_R8_UNORM,
            .rg8, .rg8_unorm => c.DXGI_FORMAT_R8G8_UNORM,
            .depth32f => c.DXGI_FORMAT_D32_FLOAT,
            .depth24_stencil8 => c.DXGI_FORMAT_D24_UNORM_S8_UINT,
        };
    }

    fn vertexFormatToDxgi(format: interface.VertexFormat) u32 {
        return switch (format) {
            .float1 => c.DXGI_FORMAT_R32_FLOAT,
            .float2 => c.DXGI_FORMAT_R32G32_FLOAT,
            .float3 => c.DXGI_FORMAT_R32G32B32_FLOAT,
            .float4 => c.DXGI_FORMAT_R32G32B32A32_FLOAT,
            .int1 => c.DXGI_FORMAT_R32_SINT,
            .int2 => c.DXGI_FORMAT_R32G32_SINT,
            .int3 => c.DXGI_FORMAT_R32G32B32_SINT,
            .int4 => c.DXGI_FORMAT_R32G32B32A32_SINT,
            .uint1 => c.DXGI_FORMAT_R32_UINT,
            .uint2 => c.DXGI_FORMAT_R32G32_UINT,
            .uint3 => c.DXGI_FORMAT_R32G32B32_UINT,
            .uint4 => c.DXGI_FORMAT_R32G32B32A32_UINT,
            .byte4_norm => c.DXGI_FORMAT_R8G8B8A8_SNORM,
            .ubyte4_norm => c.DXGI_FORMAT_R8G8B8A8_UNORM,
            .short2_norm => c.DXGI_FORMAT_R16G16_SNORM,
            .ushort2_norm => c.DXGI_FORMAT_R16G16_UNORM,
            .half2 => c.DXGI_FORMAT_R16G16_FLOAT,
            .half4 => c.DXGI_FORMAT_R16G16B16A16_FLOAT,
        };
    }

    fn getShaderTarget(shader_type: types.ShaderType) ?[]const u8 {
        return switch (shader_type) {
            .vertex => "vs_5_0",
            .fragment => "ps_5_0",
            .geometry => "gs_5_0",
            .compute => "cs_5_0",
            .tessellation_control => "hs_5_0",
            .tessellation_evaluation => "ds_5_0",
        };
    }

    fn getBufferFlags(usage: types.BufferUsage) u32 {
        return switch (usage) {
            .vertex, .index => c.D3D12_RESOURCE_FLAG_NONE,
            .uniform => c.D3D12_RESOURCE_FLAG_NONE,
            .storage => c.D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,
            .staging => c.D3D12_RESOURCE_FLAG_NONE,
        };
    }

    fn getBufferInitialState(usage: types.BufferUsage) u32 {
        return switch (usage) {
            .vertex => c.D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER,
            .index => c.D3D12_RESOURCE_STATE_INDEX_BUFFER,
            .uniform => c.D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER,
            .storage => c.D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
            .staging => c.D3D12_RESOURCE_STATE_GENERIC_READ,
        };
    }

    fn getSemanticName(location: u32) [*:0]const u8 {
        return switch (location) {
            0 => "POSITION",
            1 => "NORMAL",
            2 => "TEXCOORD",
            3 => "COLOR",
            else => "ATTR",
        };
    }

    fn blendFactorToD3D12(factor: interface.BlendFactor) u32 {
        return switch (factor) {
            .zero => c.D3D12_BLEND_ZERO,
            .one => c.D3D12_BLEND_ONE,
            .src_color => c.D3D12_BLEND_SRC_COLOR,
            .inv_src_color => c.D3D12_BLEND_INV_SRC_COLOR,
            .src_alpha => c.D3D12_BLEND_SRC_ALPHA,
            .inv_src_alpha => c.D3D12_BLEND_INV_SRC_ALPHA,
            .dst_color => c.D3D12_BLEND_DEST_COLOR,
            .inv_dst_color => c.D3D12_BLEND_INV_DEST_COLOR,
            .dst_alpha => c.D3D12_BLEND_DEST_ALPHA,
            .inv_dst_alpha => c.D3D12_BLEND_INV_DEST_ALPHA,
            .blend_color => c.D3D12_BLEND_BLEND_FACTOR,
            .inv_blend_color => c.D3D12_BLEND_INV_BLEND_FACTOR,
        };
    }

    fn blendOpToD3D12(op: interface.BlendOp) u32 {
        return switch (op) {
            .add => c.D3D12_BLEND_OP_ADD,
            .subtract => c.D3D12_BLEND_OP_SUBTRACT,
            .reverse_subtract => c.D3D12_BLEND_OP_REV_SUBTRACT,
            .min => c.D3D12_BLEND_OP_MIN,
            .max => c.D3D12_BLEND_OP_MAX,
        };
    }

    fn colorMaskToD3D12(mask: interface.ColorMask) u8 {
        var result: u8 = 0;
        if (mask.r) result |= c.D3D12_COLOR_WRITE_ENABLE_RED;
        if (mask.g) result |= c.D3D12_COLOR_WRITE_ENABLE_GREEN;
        if (mask.b) result |= c.D3D12_COLOR_WRITE_ENABLE_BLUE;
        if (mask.a) result |= c.D3D12_COLOR_WRITE_ENABLE_ALPHA;
        return result;
    }

    fn compareOpToD3D12(op: interface.CompareFunc) u32 {
        return switch (op) {
            .never => c.D3D12_COMPARISON_FUNC_NEVER,
            .less => c.D3D12_COMPARISON_FUNC_LESS,
            .equal => c.D3D12_COMPARISON_FUNC_EQUAL,
            .less_equal => c.D3D12_COMPARISON_FUNC_LESS_EQUAL,
            .greater => c.D3D12_COMPARISON_FUNC_GREATER,
            .not_equal => c.D3D12_COMPARISON_FUNC_NOT_EQUAL,
            .greater_equal => c.D3D12_COMPARISON_FUNC_GREATER_EQUAL,
            .always => c.D3D12_COMPARISON_FUNC_ALWAYS,
        };
    }

    fn stencilOpToD3D12(op: interface.StencilAction) u32 {
        return switch (op) {
            .keep => c.D3D12_STENCIL_OP_KEEP,
            .zero => c.D3D12_STENCIL_OP_ZERO,
            .replace => c.D3D12_STENCIL_OP_REPLACE,
            .incr_clamp => c.D3D12_STENCIL_OP_INCR_SAT,
            .decr_clamp => c.D3D12_STENCIL_OP_DECR_SAT,
            .invert => c.D3D12_STENCIL_OP_INVERT,
            .incr_wrap => c.D3D12_STENCIL_OP_INCR,
            .decr_wrap => c.D3D12_STENCIL_OP_DECR,
        };
    }
};

/// Create and initialize a D3D12 backend, returning a pointer to the interface.GraphicsBackend.
pub fn createBackend(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
    if (!build_options.d3d12_available) {
        return interface.GraphicsBackendError.BackendNotAvailable;
    }

    return D3D12Backend.createBackend(allocator);
}

/// Create a D3D12 backend instance (module-level wrapper for D3D12Backend.createBackend)
pub fn create(allocator: std.mem.Allocator, config: anytype) !*interface.GraphicsBackend {
    _ = config; // Config not used yet but may be in the future
    return D3D12Backend.createBackend(allocator);
}
