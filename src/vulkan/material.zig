const std = @import("std");
const vk = @import("vk.zig");
const Allocator = std.mem.Allocator;

// Material types
pub const MaterialType = enum {
    basic,
    phong,
    pbr,
    unlit,
};

// Shader stages
pub const ShaderStage = enum {
    vertex,
    fragment,
    geometry,
    tessellation_control,
    tessellation_evaluation,
    compute,
};

// Shader module wrapper
pub const ShaderModule = struct {
    module: vk.VkShaderModule,
    stage: ShaderStage,
    entry_point: []const u8,

    const Self = @This();

    pub fn deinit(self: *Self, device: vk.VkDevice) void {
        _ = device; // Acknowledge device parameter to avoid unused parameter warning
        _ = self.module; // Acknowledge module to avoid unused field warning
        // In real implementation:
        // if (self.module != VK_NULL_HANDLE) {
        //     vkDestroyShaderModule(device, self.module, null);
        // }
    }
};

// Material properties
pub const MaterialProperties = struct {
    albedo: [4]f32,
    metallic: f32,
    roughness: f32,
    emission: [3]f32,
    normal_scale: f32,

    pub fn default() MaterialProperties {
        return MaterialProperties{
            .albedo = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
            .metallic = 0.0,
            .roughness = 0.5,
            .emission = [3]f32{ 0.0, 0.0, 0.0 },
            .normal_scale = 1.0,
        };
    }
};

// Uniform buffer data
pub const MaterialUniforms = struct {
    model: [16]f32,
    view: [16]f32,
    projection: [16]f32,
    properties: MaterialProperties,
    time: f32,

    pub fn default() MaterialUniforms {
        return MaterialUniforms{
            .model = [_]f32{0.0} ** 16,
            .view = [_]f32{0.0} ** 16,
            .projection = [_]f32{0.0} ** 16,
            .properties = MaterialProperties.default(),
            .time = 0.0,
        };
    }
};

// Texture binding
pub const TextureBinding = struct {
    binding: u32,
    image: vk.VkImage,
    image_view: vk.VkImageView,
    sampler: ?*anyopaque, // VkSampler

    const Self = @This();

    pub fn deinit(self: *Self, device: vk.VkDevice) void {
        // Clean up texture resources
        _ = device;
        _ = self;
        // In real implementation would destroy image, image view, and sampler
    }
};

// Material definition
pub const Material = struct {
    allocator: Allocator,
    name: []const u8,
    material_type: MaterialType,
    vertex_shader: ?ShaderModule,
    fragment_shader: ?ShaderModule,
    geometry_shader: ?ShaderModule,
    pipeline: ?vk.VkPipeline,
    pipeline_layout: ?vk.VkPipelineLayout,
    descriptor_set_layout: ?vk.VkDescriptorSetLayout,
    descriptor_pool: ?vk.VkDescriptorPool,
    descriptor_set: ?vk.VkDescriptorSet,
    uniform_buffer: ?vk.VkBuffer,
    uniform_buffer_memory: ?vk.VkDeviceMemory,
    uniforms: MaterialUniforms,
    properties: MaterialProperties,
    textures: std.ArrayList(TextureBinding),

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8, material_type: MaterialType) !Self {
        return Self{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .material_type = material_type,
            .vertex_shader = null,
            .fragment_shader = null,
            .geometry_shader = null,
            .pipeline = null,
            .pipeline_layout = null,
            .descriptor_set_layout = null,
            .descriptor_pool = null,
            .descriptor_set = null,
            .uniform_buffer = null,
            .uniform_buffer_memory = null,
            .uniforms = MaterialUniforms.default(),
            .properties = MaterialProperties.default(),
            .textures = std.ArrayList(TextureBinding).init(allocator),
        };
    }

    pub fn deinit(self: *Self, device: vk.VkDevice) void {
        // Clean up shaders
        if (self.vertex_shader) |*shader| shader.deinit(device);
        if (self.fragment_shader) |*shader| shader.deinit(device);
        if (self.geometry_shader) |*shader| shader.deinit(device);

        // Clean up textures
        for (self.textures.items) |*texture| {
            texture.deinit(device);
        }
        self.textures.deinit();

        // Clean up Vulkan resources
        if (self.uniform_buffer_memory) |memory| {
            // vkFreeMemory(device, memory, null);
            _ = memory;
        }
        if (self.uniform_buffer) |buffer| {
            // vkDestroyBuffer(device, buffer, null);
            _ = buffer;
        }
        if (self.descriptor_pool) |pool| {
            // vkDestroyDescriptorPool(device, pool, null);
            _ = pool;
        }
        if (self.descriptor_set_layout) |layout| {
            // vkDestroyDescriptorSetLayout(device, layout, null);
            _ = layout;
        }
        if (self.pipeline) |pipeline| {
            // vkDestroyPipeline(device, pipeline, null);
            _ = pipeline;
        }
        if (self.pipeline_layout) |layout| {
            // vkDestroyPipelineLayout(device, layout, null);
            _ = layout;
        }

        self.allocator.free(self.name);
    }

    pub fn loadShader(self: *Self, device: vk.VkDevice, stage: ShaderStage, spirv_code: []const u8) !void {
        const shader_module = try createShaderModule(device, spirv_code);

        const shader = ShaderModule{
            .module = shader_module,
            .stage = stage,
            .entry_point = "main",
        };

        switch (stage) {
            .vertex => self.vertex_shader = shader,
            .fragment => self.fragment_shader = shader,
            .geometry => self.geometry_shader = shader,
            else => return error.UnsupportedShaderStage,
        }
    }

    pub fn loadShaderFromFile(self: *Self, device: vk.VkDevice, stage: ShaderStage, file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            std.debug.print("Failed to open shader file: {s}\n", .{file_path});
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const spirv_code = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(spirv_code);

        _ = try file.readAll(spirv_code);
        try self.loadShader(device, stage, spirv_code);
    }

    pub fn addTexture(self: *Self, binding: u32, image: vk.VkImage, image_view: vk.VkImageView, sampler: ?*anyopaque) !void {
        const texture = TextureBinding{
            .binding = binding,
            .image = image,
            .image_view = image_view,
            .sampler = sampler,
        };
        try self.textures.append(texture);
    }

    pub fn setProperty(self: *Self, property_name: []const u8, value: anytype) void {
        if (std.mem.eql(u8, property_name, "albedo")) {
            if (@TypeOf(value) == [4]f32) {
                self.properties.albedo = value;
            }
        } else if (std.mem.eql(u8, property_name, "metallic")) {
            if (@TypeOf(value) == f32) {
                self.properties.metallic = value;
            }
        } else if (std.mem.eql(u8, property_name, "roughness")) {
            if (@TypeOf(value) == f32) {
                self.properties.roughness = value;
            }
        } else if (std.mem.eql(u8, property_name, "emission")) {
            if (@TypeOf(value) == [3]f32) {
                self.properties.emission = value;
            }
        }
    }

    pub fn updateUniforms(self: *Self, model: [16]f32, view: [16]f32, projection: [16]f32, time: f32) void {
        self.uniforms.model = model;
        self.uniforms.view = view;
        self.uniforms.projection = projection;
        self.uniforms.properties = self.properties;
        self.uniforms.time = time;
    }

    pub fn createPipeline(self: *Self, device: vk.VkDevice, render_pass: vk.VkRenderPass) !void {
        try self.createDescriptorSetLayout(device);
        try self.createPipelineLayout(device);
        try self.createGraphicsPipeline(device, render_pass);
        try self.createUniformBuffer(device);
        try self.createDescriptorPool(device);
        try self.createDescriptorSet(device);
    }

    fn createShaderModule(device: vk.VkDevice, spirv_code: []const u8) !vk.VkShaderModule {
        // Mock implementation - in real code would use vkCreateShaderModule
        _ = device;
        _ = spirv_code;
        return @ptrFromInt(0x1000);
    }

    fn createDescriptorSetLayout(self: *Self, device: vk.VkDevice) !void {
        // Mock implementation - in real code would create descriptor set layout
        _ = device;
        self.descriptor_set_layout = @ptrFromInt(0x2000);
    }

    fn createPipelineLayout(self: *Self, device: vk.VkDevice) !void {
        // Mock implementation - in real code would create pipeline layout
        _ = device;
        self.pipeline_layout = @ptrFromInt(0x3000);
    }

    fn createGraphicsPipeline(self: *Self, device: vk.VkDevice, render_pass: vk.VkRenderPass) !void {
        // Mock implementation - in real code would create graphics pipeline
        _ = device;
        _ = render_pass;
        self.pipeline = @ptrFromInt(0x4000);
    }

    fn createUniformBuffer(self: *Self, device: vk.VkDevice) !void {
        // Mock implementation - in real code would create uniform buffer
        _ = device;
        self.uniform_buffer = @ptrFromInt(0x5000);
        self.uniform_buffer_memory = @ptrFromInt(0x6000);
    }

    fn createDescriptorPool(self: *Self, device: vk.VkDevice) !void {
        // Mock implementation - in real code would create descriptor pool
        _ = device;
        self.descriptor_pool = @ptrFromInt(0x7000);
    }

    fn createDescriptorSet(self: *Self, device: vk.VkDevice) !void {
        // Mock implementation - in real code would allocate and update descriptor set
        _ = device;
        self.descriptor_set = @ptrFromInt(0x8000);
    }

    pub fn bind(self: *Self, command_buffer: vk.VkCommandBuffer) void {
        // Mock implementation - in real code would bind pipeline and descriptor sets
        _ = command_buffer;
        std.debug.print("Binding material: {s}\n", .{self.name});
    }

    pub fn updateUniformBuffer(self: *Self, device: vk.VkDevice) !void {
        // Mock implementation - in real code would map memory and copy uniform data
        if (self.uniform_buffer != null) {
            // In real implementation:
            // 1. Map uniform buffer memory using device
            // 2. Copy self.uniforms to mapped memory
            // 3. Unmap memory
            _ = device; // Acknowledge device parameter to avoid unused parameter warning
        }
    }
};

// Material manager
pub const MaterialManager = struct {
    allocator: Allocator,
    materials: std.HashMap(u32, Material, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    next_id: u32,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .materials = std.HashMap(u32, Material, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .next_id = 1,
        };
    }

    pub fn deinit(self: *Self, device: vk.VkDevice) void {
        var iterator = self.materials.valueIterator();
        while (iterator.next()) |material| {
            material.deinit(device);
        }
        self.materials.deinit();
    }

    pub fn createMaterial(self: *Self, name: []const u8, material_type: MaterialType) !u32 {
        const material_id = self.next_id;
        self.next_id += 1;

        const material = try Material.init(self.allocator, name, material_type);
        try self.materials.put(material_id, material);

        return material_id;
    }

    pub fn getMaterial(self: *Self, material_id: u32) ?*Material {
        return self.materials.getPtr(material_id);
    }

    pub fn removeMaterial(self: *Self, device: vk.VkDevice, material_id: u32) void {
        if (self.materials.getPtr(material_id)) |material| {
            material.deinit(device);
            _ = self.materials.remove(material_id);
        }
    }

    pub fn loadDefaultMaterials(self: *Self, device: vk.VkDevice, render_pass: vk.VkRenderPass) !void {
        // Create basic unlit material
        const basic_id = try self.createMaterial("basic", .unlit);
        if (self.getMaterial(basic_id)) |basic_material| {
            // Load embedded shaders (in real implementation would load from files)
            try basic_material.createPipeline(device, render_pass);

            // Set default properties
            basic_material.setProperty("albedo", [4]f32{ 0.8, 0.8, 0.8, 1.0 });
        }

        // Create PBR material
        const pbr_id = try self.createMaterial("pbr", .pbr);
        if (self.getMaterial(pbr_id)) |pbr_material| {
            try pbr_material.createPipeline(device, render_pass);

            // Set PBR properties
            pbr_material.setProperty("albedo", [4]f32{ 0.7, 0.3, 0.3, 1.0 });
            pbr_material.setProperty("metallic", @as(f32, 0.2));
            pbr_material.setProperty("roughness", @as(f32, 0.4));
        }

        std.debug.print("✅ Default materials loaded\n", .{});
    }
};

// Utility functions for shader compilation
pub fn compileShaderFromSource(allocator: Allocator, source: []const u8, stage: ShaderStage) ![]u8 {
    // Mock implementation - in real code would use glslc or shaderc
    _ = allocator;
    _ = source;
    _ = stage;

    // Return mock SPIR-V bytecode
    const mock_spirv = [_]u8{ 0x03, 0x02, 0x23, 0x07 }; // SPIR-V magic number
    return mock_spirv[0..];
}

pub fn loadShaderFromFile(allocator: Allocator, file_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const shader_code = try allocator.alloc(u8, file_size);
    _ = try file.readAll(shader_code);

    return shader_code;
}

// Predefined materials
pub fn createBasicCubeMaterial(allocator: Allocator) !Material {
    var material = try Material.init(allocator, "BasicCube", .unlit);

    // Set colorful properties for the spinning cube
    material.setProperty("albedo", [4]f32{ 1.0, 0.5, 0.2, 1.0 }); // Orange

    return material;
}

pub fn createMetallicCubeMaterial(allocator: Allocator) !Material {
    var material = try Material.init(allocator, "MetallicCube", .pbr);

    // Set metallic properties
    material.setProperty("albedo", [4]f32{ 0.8, 0.8, 0.9, 1.0 }); // Light blue
    material.setProperty("metallic", @as(f32, 0.8));
    material.setProperty("roughness", @as(f32, 0.2));

    return material;
}
