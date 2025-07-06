const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const math = @import("math");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const DynamicShaderCompiler = @import("dynamic_shader_compiler.zig").DynamicShaderCompiler;
const ShaderType = @import("dynamic_shader_compiler.zig").ShaderType;
const print = std.debug.print;

pub const NodeType = enum {
    // Input nodes
    vertex_input,
    texture_coordinate,
    normal_input,
    position_input,
    time_input,
    camera_position,
    world_position,
    view_direction,
    light_direction,

    // Math nodes
    add,
    subtract,
    multiply,
    divide,
    dot_product,
    cross_product,
    normalize,
    length,
    distance,
    power,
    sqrt,
    sin,
    cos,
    tan,
    asin,
    acos,
    atan,
    atan2,
    floor,
    ceil,
    fract,
    lerp,
    clamp,
    saturate,
    min_node,
    max_node,
    abs_node,
    sign_node,
    step_node,
    smoothstep,

    // Vector operations
    vector_split,
    vector_combine,
    vector_transform,
    matrix_multiply,

    // Texture nodes
    texture_sample,
    texture_sample_lod,
    texture_sample_grad,
    texture_sample_bias,
    texture_size,
    texture_mip_level,

    // Utility nodes
    split,
    combine,
    swizzle,
    constant,
    parameter,
    remap,
    one_minus,

    // Lighting nodes
    lambert,
    phong,
    blinn_phong,
    pbr,
    fresnel,
    reflection,
    refraction,

    // Noise nodes
    perlin_noise,
    simplex_noise,
    voronoi,
    fractal_noise,
    white_noise,

    // Color nodes
    hue_shift,
    saturation,
    brightness,
    contrast,
    gamma_correct,
    color_mix,

    // Output nodes
    vertex_output,
    fragment_output,
    surface_output,
    emission_output,

    // Control flow
    if_node,
    switch_node,
    for_loop,
    while_loop,
    branch,

    // Advanced
    gradient,
    custom_function,
    subgraph,
    macro_node,

    pub fn getDisplayName(self: NodeType) []const u8 {
        return switch (self) {
            .vertex_input => "Vertex Input",
            .texture_coordinate => "Texture Coordinate",
            .normal_input => "Normal",
            .position_input => "Position",
            .time_input => "Time",
            .camera_position => "Camera Position",
            .world_position => "World Position",
            .view_direction => "View Direction",
            .light_direction => "Light Direction",
            .add => "Add",
            .subtract => "Subtract",
            .multiply => "Multiply",
            .divide => "Divide",
            .dot_product => "Dot Product",
            .cross_product => "Cross Product",
            .normalize => "Normalize",
            .length => "Length",
            .distance => "Distance",
            .power => "Power",
            .sqrt => "Square Root",
            .sin => "Sine",
            .cos => "Cosine",
            .tan => "Tangent",
            .asin => "Arc Sine",
            .acos => "Arc Cosine",
            .atan => "Arc Tangent",
            .atan2 => "Arc Tangent 2",
            .floor => "Floor",
            .ceil => "Ceiling",
            .fract => "Fraction",
            .lerp => "Linear Interpolate",
            .clamp => "Clamp",
            .saturate => "Saturate",
            .min_node => "Minimum",
            .max_node => "Maximum",
            .abs_node => "Absolute",
            .sign_node => "Sign",
            .step_node => "Step",
            .smoothstep => "Smooth Step",
            .vector_split => "Vector Split",
            .vector_combine => "Vector Combine",
            .vector_transform => "Vector Transform",
            .matrix_multiply => "Matrix Multiply",
            .texture_sample => "Texture Sample",
            .texture_sample_lod => "Texture Sample LOD",
            .texture_sample_grad => "Texture Sample Grad",
            .texture_sample_bias => "Texture Sample Bias",
            .texture_size => "Texture Size",
            .texture_mip_level => "Texture Mip Level",
            .split => "Split",
            .combine => "Combine",
            .swizzle => "Swizzle",
            .constant => "Constant",
            .parameter => "Parameter",
            .remap => "Remap",
            .one_minus => "One Minus",
            .lambert => "Lambert",
            .phong => "Phong",
            .blinn_phong => "Blinn-Phong",
            .pbr => "PBR",
            .fresnel => "Fresnel",
            .reflection => "Reflection",
            .refraction => "Refraction",
            .perlin_noise => "Perlin Noise",
            .simplex_noise => "Simplex Noise",
            .voronoi => "Voronoi",
            .fractal_noise => "Fractal Noise",
            .white_noise => "White Noise",
            .hue_shift => "Hue Shift",
            .saturation => "Saturation",
            .brightness => "Brightness",
            .contrast => "Contrast",
            .gamma_correct => "Gamma Correct",
            .color_mix => "Color Mix",
            .vertex_output => "Vertex Output",
            .fragment_output => "Fragment Output",
            .surface_output => "Surface Output",
            .emission_output => "Emission Output",
            .if_node => "If",
            .switch_node => "Switch",
            .for_loop => "For Loop",
            .while_loop => "While Loop",
            .branch => "Branch",
            .gradient => "Gradient",
            .custom_function => "Custom Function",
            .subgraph => "Subgraph",
            .macro_node => "Macro",
        };
    }

    pub fn getCategory(self: NodeType) NodeCategory {
        return switch (self) {
            .vertex_input, .texture_coordinate, .normal_input, .position_input, .time_input, .camera_position, .world_position, .view_direction, .light_direction => .input,

            .add, .subtract, .multiply, .divide, .dot_product, .cross_product, .normalize, .length, .distance, .power, .sqrt, .sin, .cos, .tan, .asin, .acos, .atan, .atan2, .floor, .ceil, .fract, .lerp, .clamp, .saturate, .min_node, .max_node, .abs_node, .sign_node, .step_node, .smoothstep => .math,

            .vector_split, .vector_combine, .vector_transform, .matrix_multiply => .vector,

            .texture_sample, .texture_sample_lod, .texture_sample_grad, .texture_sample_bias, .texture_size, .texture_mip_level => .texture,

            .split, .combine, .swizzle, .constant, .parameter, .remap, .one_minus => .utility,

            .lambert, .phong, .blinn_phong, .pbr, .fresnel, .reflection, .refraction => .lighting,

            .perlin_noise, .simplex_noise, .voronoi, .fractal_noise, .white_noise => .noise,

            .hue_shift, .saturation, .brightness, .contrast, .gamma_correct, .color_mix => .color,

            .vertex_output, .fragment_output, .surface_output, .emission_output => .output,

            .if_node, .switch_node, .for_loop, .while_loop, .branch => .control_flow,

            .gradient, .custom_function, .subgraph, .macro_node => .advanced,
        };
    }
};

pub const NodeCategory = enum {
    input,
    math,
    vector,
    texture,
    utility,
    lighting,
    noise,
    color,
    output,
    control_flow,
    advanced,

    pub fn getDisplayName(self: NodeCategory) []const u8 {
        return switch (self) {
            .input => "Input",
            .math => "Math",
            .vector => "Vector",
            .texture => "Texture",
            .utility => "Utility",
            .lighting => "Lighting",
            .noise => "Noise",
            .color => "Color",
            .output => "Output",
            .control_flow => "Control Flow",
            .advanced => "Advanced",
        };
    }
};

pub const DataType = enum {
    void,
    bool,
    int,
    uint,
    float,
    double,
    vec2,
    vec3,
    vec4,
    ivec2,
    ivec3,
    ivec4,
    uvec2,
    uvec3,
    uvec4,
    bvec2,
    bvec3,
    bvec4,
    mat2,
    mat3,
    mat4,
    mat2x2,
    mat2x3,
    mat2x4,
    mat3x2,
    mat3x3,
    mat3x4,
    mat4x2,
    mat4x3,
    mat4x4,
    sampler1D,
    sampler2D,
    sampler3D,
    samplerCube,
    sampler2DArray,
    samplerCubeArray,
    image1D,
    image2D,
    image3D,
    imageCube,
    image2DArray,
    imageCubeArray,
    custom,
    texture,
    any,

    pub fn getDisplayName(self: DataType) []const u8 {
        return switch (self) {
            .void => "void",
            .bool => "bool",
            .int => "int",
            .uint => "uint",
            .float => "float",
            .double => "double",
            .vec2 => "vec2",
            .vec3 => "vec3",
            .vec4 => "vec4",
            .ivec2 => "ivec2",
            .ivec3 => "ivec3",
            .ivec4 => "ivec4",
            .uvec2 => "uvec2",
            .uvec3 => "uvec3",
            .uvec4 => "uvec4",
            .bvec2 => "bvec2",
            .bvec3 => "bvec3",
            .bvec4 => "bvec4",
            .mat2 => "mat2",
            .mat3 => "mat3",
            .mat4 => "mat4",
            .mat2x2 => "mat2x2",
            .mat2x3 => "mat2x3",
            .mat2x4 => "mat2x4",
            .mat3x2 => "mat3x2",
            .mat3x3 => "mat3x3",
            .mat3x4 => "mat3x4",
            .mat4x2 => "mat4x2",
            .mat4x3 => "mat4x3",
            .mat4x4 => "mat4x4",
            .sampler1D => "sampler1D",
            .sampler2D => "sampler2D",
            .sampler3D => "sampler3D",
            .samplerCube => "samplerCube",
            .sampler2DArray => "sampler2DArray",
            .samplerCubeArray => "samplerCubeArray",
            .image1D => "image1D",
            .image2D => "image2D",
            .image3D => "image3D",
            .imageCube => "imageCube",
            .image2DArray => "image2DArray",
            .imageCubeArray => "imageCubeArray",
            .custom => "custom",
            .texture => "texture",
            .any => "any",
        };
    }

    pub fn getSize(self: DataType) u32 {
        return switch (self) {
            .void => 0,
            .bool, .int, .uint, .float => 4,
            .double => 8,
            .vec2, .ivec2, .uvec2, .bvec2 => 8,
            .vec3, .ivec3, .uvec3, .bvec3 => 12,
            .vec4, .ivec4, .uvec4, .bvec4 => 16,
            .mat2, .mat2x2 => 16,
            .mat3, .mat3x3 => 36,
            .mat4, .mat4x4 => 64,
            .mat2x3 => 24,
            .mat2x4 => 32,
            .mat3x2 => 24,
            .mat3x4 => 48,
            .mat4x2 => 32,
            .mat4x3 => 48,
            else => 0, // Opaque types
        };
    }

    pub fn isCompatible(self: DataType, other: DataType) bool {
        if (self == other) return true;
        if (self == .any or other == .any) return true;

        // Float/vector compatibility
        switch (self) {
            .float => return other == .vec2 or other == .vec3 or other == .vec4,
            .vec2, .vec3, .vec4 => return other == .float,
            .int => return other == .ivec2 or other == .ivec3 or other == .ivec4,
            .ivec2, .ivec3, .ivec4 => return other == .int,
            else => return false,
        }
    }
};

pub const SocketDirection = enum {
    input,
    output,
};

pub const Socket = struct {
    id: u32,
    name: []const u8,
    data_type: DataType,
    direction: SocketDirection,
    connected: bool = false,
    connection_id: ?u32 = null,
    default_value: SocketValue = .{ .none = {} },
    position: Vec2 = Vec2{ .x = 0.0, .y = 0.0 },

    pub const SocketValue = union(enum) {
        none: void,
        bool_val: bool,
        int_val: i32,
        uint_val: u32,
        float_val: f32,
        double_val: f64,
        vec2_val: Vec2,
        vec3_val: Vec3,
        vec4_val: Vec4,
        string_val: []const u8,
    };

    pub fn init(id: u32, name: []const u8, data_type: DataType, direction: SocketDirection) Socket {
        return Socket{
            .id = id,
            .name = name,
            .data_type = data_type,
            .direction = direction,
        };
    }

    pub fn isCompatibleWith(self: *const Socket, other: *const Socket) bool {
        if (self.direction == other.direction) return false;
        return self.data_type.isCompatible(other.data_type);
    }
};

pub const Connection = struct {
    id: u32,
    from_node: u32,
    from_socket: u32,
    to_node: u32,
    to_socket: u32,
    data_type: DataType,

    pub fn init(id: u32, from_node: u32, from_socket: u32, to_node: u32, to_socket: u32, data_type: DataType) Connection {
        return Connection{
            .id = id,
            .from_node = from_node,
            .from_socket = from_socket,
            .to_node = to_node,
            .to_socket = to_socket,
            .data_type = data_type,
        };
    }
};

pub const NodeParameter = struct {
    name: []const u8,
    data_type: DataType,
    default_value: Socket.SocketValue,
    min_value: ?Socket.SocketValue = null,
    max_value: ?Socket.SocketValue = null,
    step: ?f32 = null,
    description: []const u8 = "",

    pub fn init(name: []const u8, data_type: DataType, default_value: Socket.SocketValue) NodeParameter {
        return NodeParameter{
            .name = name,
            .data_type = data_type,
            .default_value = default_value,
        };
    }
};

pub const ShaderNode = struct {
    allocator: Allocator,
    id: u32,
    node_type: NodeType,
    name: []const u8,
    position: Vec2,
    size: Vec2,
    inputs: ArrayList(Socket),
    outputs: ArrayList(Socket),
    parameters: ArrayList(NodeParameter),
    enabled: bool = true,
    collapsed: bool = false,
    color: Vec4 = Vec4{ .x = 0.2, .y = 0.3, .z = 0.8, .w = 1.0 },
    custom_code: ?[]const u8 = null,

    pub fn init(allocator: Allocator, id: u32, node_type: NodeType, position: Vec2) !ShaderNode {
        var node = ShaderNode{
            .allocator = allocator,
            .id = id,
            .node_type = node_type,
            .name = try allocator.dupe(u8, node_type.getDisplayName()),
            .position = position,
            .size = Vec2{ .x = 150.0, .y = 100.0 },
            .inputs = ArrayList(Socket).init(allocator),
            .outputs = ArrayList(Socket).init(allocator),
            .parameters = ArrayList(NodeParameter).init(allocator),
        };

        try node.setupDefaultSockets();
        try node.setupDefaultParameters();
        return node;
    }

    pub fn deinit(self: *ShaderNode) void {
        self.allocator.free(self.name);
        self.inputs.deinit();
        self.outputs.deinit();
        for (self.parameters.items) |param| {
            self.allocator.free(param.name);
            if (param.description.len > 0) {
                self.allocator.free(param.description);
            }
        }
        self.parameters.deinit();
        if (self.custom_code) |code| {
            self.allocator.free(code);
        }
    }

    pub fn addInput(self: *ShaderNode, name: []const u8, data_type: DataType) !void {
        const socket_id = @as(u32, @intCast(self.inputs.items.len));
        const owned_name = try self.allocator.dupe(u8, name);
        const socket = Socket.init(socket_id, owned_name, data_type, .input);
        try self.inputs.append(socket);
    }

    pub fn addOutput(self: *ShaderNode, name: []const u8, data_type: DataType) !void {
        const socket_id = @as(u32, @intCast(self.outputs.items.len));
        const owned_name = try self.allocator.dupe(u8, name);
        const socket = Socket.init(socket_id, owned_name, data_type, .output);
        try self.outputs.append(socket);
    }

    pub fn getInputSocket(self: *ShaderNode, index: u32) ?*Socket {
        if (index >= self.inputs.items.len) return null;
        return &self.inputs.items[index];
    }

    pub fn getOutputSocket(self: *ShaderNode, index: u32) ?*Socket {
        if (index >= self.outputs.items.len) return null;
        return &self.outputs.items[index];
    }

    pub fn generateCode(self: *const ShaderNode, connections: []const Connection) ![]const u8 {
        _ = connections;
        var code = ArrayList(u8).init(self.allocator);
        defer code.deinit();

        try code.appendSlice("// Node: ");
        try code.appendSlice(self.name);
        try code.appendSlice("\n");

        switch (self.node_type) {
            .add => {
                try code.appendSlice("const result = input_a + input_b;\n");
            },
            .multiply => {
                try code.appendSlice("const result = input_a * input_b;\n");
            },
            .normalize => {
                try code.appendSlice("const result = normalize(input);\n");
            },
            .dot_product => {
                try code.appendSlice("const result = dot(input_a, input_b);\n");
            },
            .texture_sample => {
                try code.appendSlice("const result = texture(sampler, uv);\n");
            },
            .constant => {
                if (self.parameters.items.len > 0) {
                    const param = self.parameters.items[0];
                    try code.appendSlice("const result = ");
                    switch (param.default_value) {
                        .float_val => |val| {
                            const value_str = try std.fmt.allocPrint(self.allocator, "{d}", .{val});
                            defer self.allocator.free(value_str);
                            try code.appendSlice(value_str);
                        },
                        .vec3_val => |val| {
                            const value_str = try std.fmt.allocPrint(self.allocator, "vec3({d}, {d}, {d})", .{ val.x, val.y, val.z });
                            defer self.allocator.free(value_str);
                            try code.appendSlice(value_str);
                        },
                        else => try code.appendSlice("0.0"),
                    }
                    try code.appendSlice(";\n");
                }
            },
            .custom_function => {
                if (self.custom_code) |custom| {
                    try code.appendSlice(custom);
                } else {
                    try code.appendSlice("// Custom function code here\n");
                }
            },
            else => {
                try code.appendSlice("// Node implementation not defined\n");
            },
        }

        return self.allocator.dupe(u8, code.items);
    }

    fn setupDefaultSockets(self: *ShaderNode) !void {
        switch (self.node_type) {
            .vertex_input => {
                try self.addOutput("Position", .vec4);
                try self.addOutput("Normal", .vec3);
                try self.addOutput("UV", .vec2);
                try self.addOutput("Color", .vec4);
            },
            .texture_coordinate => {
                try self.addOutput("UV", .vec2);
                try self.addOutput("UV2", .vec2);
            },
            .normal_input => {
                try self.addOutput("Normal", .vec3);
            },
            .position_input => {
                try self.addOutput("Position", .vec3);
            },
            .time_input => {
                try self.addOutput("Time", .float);
            },
            .add => {
                try self.addInput("A", .any);
                try self.addInput("B", .any);
                try self.addOutput("Result", .any);
            },
            .subtract => {
                try self.addInput("A", .any);
                try self.addInput("B", .any);
                try self.addOutput("Result", .any);
            },
            .multiply => {
                try self.addInput("A", .any);
                try self.addInput("B", .any);
                try self.addOutput("Result", .any);
            },
            .divide => {
                try self.addInput("A", .any);
                try self.addInput("B", .any);
                try self.addOutput("Result", .any);
            },
            .dot_product => {
                try self.addInput("A", .vec3);
                try self.addInput("B", .vec3);
                try self.addOutput("Result", .float);
            },
            .cross_product => {
                try self.addInput("A", .vec3);
                try self.addInput("B", .vec3);
                try self.addOutput("Result", .vec3);
            },
            .normalize => {
                try self.addInput("Vector", .vec3);
                try self.addOutput("Result", .vec3);
            },
            .length => {
                try self.addInput("Vector", .any);
                try self.addOutput("Length", .float);
            },
            .lerp => {
                try self.addInput("A", .any);
                try self.addInput("B", .any);
                try self.addInput("T", .float);
                try self.addOutput("Result", .any);
            },
            .texture_sample => {
                try self.addInput("Texture", .sampler2D);
                try self.addInput("UV", .vec2);
                try self.addOutput("Color", .vec4);
                try self.addOutput("Alpha", .float);
            },
            .constant => {
                try self.addOutput("Value", .any);
            },
            .split => {
                try self.addInput("Vector", .vec4);
                try self.addOutput("X", .float);
                try self.addOutput("Y", .float);
                try self.addOutput("Z", .float);
                try self.addOutput("W", .float);
            },
            .combine => {
                try self.addInput("X", .float);
                try self.addInput("Y", .float);
                try self.addInput("Z", .float);
                try self.addInput("W", .float);
                try self.addOutput("Vector", .vec4);
            },
            .fragment_output => {
                try self.addInput("Color", .vec4);
                try self.addInput("Alpha", .float);
            },
            .vertex_output => {
                try self.addInput("Position", .vec4);
                try self.addInput("Normal", .vec3);
                try self.addInput("UV", .vec2);
            },
            .pbr => {
                try self.addInput("Albedo", .vec3);
                try self.addInput("Metallic", .float);
                try self.addInput("Roughness", .float);
                try self.addInput("Normal", .vec3);
                try self.addInput("AO", .float);
                try self.addOutput("Color", .vec3);
            },
            .perlin_noise => {
                try self.addInput("UV", .vec2);
                try self.addInput("Scale", .float);
                try self.addInput("Octaves", .int);
                try self.addOutput("Noise", .float);
            },
            else => {
                // Default case - add basic input/output
                try self.addInput("Input", .any);
                try self.addOutput("Output", .any);
            },
        }
    }

    fn setupDefaultParameters(self: *ShaderNode) !void {
        switch (self.node_type) {
            .constant => {
                const param = NodeParameter.init("Value", .float, .{ .float_val = 1.0 });
                try self.parameters.append(param);
            },
            .lerp => {
                const param = NodeParameter.init("T", .float, .{ .float_val = 0.5 });
                try self.parameters.append(param);
            },
            .perlin_noise => {
                const scale_param = NodeParameter.init("Scale", .float, .{ .float_val = 1.0 });
                try self.parameters.append(scale_param);

                const octaves_param = NodeParameter.init("Octaves", .int, .{ .int_val = 4 });
                try self.parameters.append(octaves_param);
            },
            .pbr => {
                const metallic_param = NodeParameter.init("Metallic", .float, .{ .float_val = 0.0 });
                try self.parameters.append(metallic_param);

                const roughness_param = NodeParameter.init("Roughness", .float, .{ .float_val = 0.5 });
                try self.parameters.append(roughness_param);
            },
            else => {},
        }
    }
};

pub const ShaderGraph = struct {
    allocator: Allocator,
    nodes: HashMap(u32, ShaderNode, std.hash_map.AutoContext(u32)),
    connections: HashMap(u32, Connection, std.hash_map.AutoContext(u32)),
    next_node_id: u32 = 1,
    next_connection_id: u32 = 1,
    shader_type: ShaderType,
    name: []const u8,
    dirty: bool = true,

    pub fn init(allocator: Allocator, name: []const u8, shader_type: ShaderType) !ShaderGraph {
        return ShaderGraph{
            .allocator = allocator,
            .nodes = HashMap(u32, ShaderNode, std.hash_map.AutoContext(u32)).init(allocator),
            .connections = HashMap(u32, Connection, std.hash_map.AutoContext(u32)).init(allocator),
            .shader_type = shader_type,
            .name = try allocator.dupe(u8, name),
        };
    }

    pub fn deinit(self: *ShaderGraph) void {
        var node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.nodes.deinit();
        self.connections.deinit();
        self.allocator.free(self.name);
    }

    pub fn addNode(self: *ShaderGraph, node_type: NodeType, position: Vec2) !u32 {
        const node_id = self.next_node_id;
        self.next_node_id += 1;

        const node = try ShaderNode.init(self.allocator, node_id, node_type, position);
        try self.nodes.put(node_id, node);

        self.dirty = true;
        return node_id;
    }

    pub fn removeNode(self: *ShaderGraph, node_id: u32) !void {
        // Remove all connections to/from this node
        var connections_to_remove = ArrayList(u32).init(self.allocator);
        defer connections_to_remove.deinit();

        var connection_iterator = self.connections.iterator();
        while (connection_iterator.next()) |entry| {
            const connection = entry.value_ptr;
            if (connection.from_node == node_id or connection.to_node == node_id) {
                try connections_to_remove.append(connection.id);
            }
        }

        for (connections_to_remove.items) |conn_id| {
            _ = self.connections.remove(conn_id);
        }

        if (self.nodes.getPtr(node_id)) |node| {
            node.deinit();
            _ = self.nodes.remove(node_id);
        }
        self.dirty = true;
    }

    pub fn connectNodes(self: *ShaderGraph, from_node: u32, from_socket: u32, to_node: u32, to_socket: u32) !bool {
        const from_node_ptr = self.nodes.getPtr(from_node) orelse return false;
        const to_node_ptr = self.nodes.getPtr(to_node) orelse return false;

        const from_socket_ptr = from_node_ptr.getOutputSocket(from_socket) orelse return false;
        const to_socket_ptr = to_node_ptr.getInputSocket(to_socket) orelse return false;

        if (!from_socket_ptr.isCompatibleWith(to_socket_ptr)) return false;

        // Remove existing connection to input socket
        var existing_connection: ?u32 = null;
        var connection_iterator = self.connections.iterator();
        while (connection_iterator.next()) |entry| {
            const connection = entry.value_ptr;
            if (connection.to_node == to_node and connection.to_socket == to_socket) {
                existing_connection = connection.id;
                break;
            }
        }

        if (existing_connection) |conn_id| {
            _ = self.connections.remove(conn_id);
        }

        const connection_id = self.next_connection_id;
        self.next_connection_id += 1;

        const connection = Connection.init(connection_id, from_node, from_socket, to_node, to_socket, from_socket_ptr.data_type);
        try self.connections.put(connection_id, connection);

        // Update socket connection state
        from_socket_ptr.connected = true;
        from_socket_ptr.connection_id = connection_id;
        to_socket_ptr.connected = true;
        to_socket_ptr.connection_id = connection_id;

        self.dirty = true;
        return true;
    }

    pub fn disconnectNodes(self: *ShaderGraph, connection_id: u32) void {
        if (self.connections.getPtr(connection_id)) |connection| {
            // Update socket connection state
            if (self.nodes.getPtr(connection.from_node)) |from_node| {
                if (from_node.getOutputSocket(connection.from_socket)) |socket| {
                    socket.connected = false;
                    socket.connection_id = null;
                }
            }
            if (self.nodes.getPtr(connection.to_node)) |to_node| {
                if (to_node.getInputSocket(connection.to_socket)) |socket| {
                    socket.connected = false;
                    socket.connection_id = null;
                }
            }

            _ = self.connections.remove(connection_id);
            self.dirty = true;
        }
    }

    pub fn getNode(self: *ShaderGraph, node_id: u32) ?*ShaderNode {
        return self.nodes.getPtr(node_id);
    }

    pub fn generateShaderCode(self: *ShaderGraph, compiler: *DynamicShaderCompiler) ![]const u8 {
        var code = ArrayList(u8).init(self.allocator);
        defer code.deinit();

        // Generate header
        try code.appendSlice("const std = @import(\"std\");\n");
        try code.appendSlice("const math = std.math;\n\n");

        // Generate shader input/output structures based on type
        switch (self.shader_type) {
            .vertex => {
                try code.appendSlice("const VertexInput = struct {\n");
                try code.appendSlice("    position: @Vector(4, f32),\n");
                try code.appendSlice("    normal: @Vector(3, f32),\n");
                try code.appendSlice("    uv: @Vector(2, f32),\n");
                try code.appendSlice("};\n\n");

                try code.appendSlice("const VertexOutput = struct {\n");
                try code.appendSlice("    position: @Vector(4, f32),\n");
                try code.appendSlice("    world_pos: @Vector(3, f32),\n");
                try code.appendSlice("    normal: @Vector(3, f32),\n");
                try code.appendSlice("    uv: @Vector(2, f32),\n");
                try code.appendSlice("};\n\n");
            },
            .fragment => {
                try code.appendSlice("const FragmentInput = struct {\n");
                try code.appendSlice("    world_pos: @Vector(3, f32),\n");
                try code.appendSlice("    normal: @Vector(3, f32),\n");
                try code.appendSlice("    uv: @Vector(2, f32),\n");
                try code.appendSlice("};\n\n");

                try code.appendSlice("const FragmentOutput = struct {\n");
                try code.appendSlice("    color: @Vector(4, f32),\n");
                try code.appendSlice("};\n\n");
            },
            else => {},
        }

        // Generate main function
        const entry_point = self.shader_type.getDefaultEntryPoint();
        try code.writer().print("pub fn {s}(", .{entry_point});

        switch (self.shader_type) {
            .vertex => try code.appendSlice("input: VertexInput, uniforms: Uniforms) VertexOutput {\n"),
            .fragment => try code.appendSlice("input: FragmentInput, uniforms: Uniforms) FragmentOutput {\n"),
            else => try code.appendSlice("input: ShaderInput) ShaderOutput {\n"),
        }

        try code.appendSlice("    var output: ");
        switch (self.shader_type) {
            .vertex => try code.appendSlice("VertexOutput"),
            .fragment => try code.appendSlice("FragmentOutput"),
            else => try code.appendSlice("ShaderOutput"),
        }
        try code.appendSlice(" = undefined;\n\n");

        // Generate node code in topological order
        var visited = std.AutoHashMap(u32, bool).init(self.allocator);
        defer visited.deinit();

        // Find output nodes
        var output_nodes = ArrayList(u32).init(self.allocator);
        defer output_nodes.deinit();

        var node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            const node = entry.value_ptr;
            switch (node.node_type) {
                .vertex_output, .fragment_output, .surface_output => {
                    try output_nodes.append(node.id);
                },
                else => {},
            }
        }

        // Generate code for each output node (this will traverse dependencies)
        for (output_nodes.items) |output_node_id| {
            try self.generateNodeCodeRecursive(output_node_id, &code, &visited);
        }

        try code.appendSlice("    return output;\n");
        try code.appendSlice("}\n");

        // Register the generated shader with the compiler
        const shader_code = try code.toOwnedSlice();
        try compiler.loadShaderFromString(shader_code, self.name, self.shader_type);

        return shader_code;
    }

    fn generateNodeCodeRecursive(self: *ShaderGraph, node_id: u32, code: *ArrayList(u8), visited: *std.AutoHashMap(u32, bool)) !void {
        if (visited.get(node_id) orelse false) return;
        try visited.put(node_id, true);

        const node = self.nodes.getPtr(node_id) orelse return;

        // First, generate code for all input dependencies
        for (node.inputs.items, 0..) |input_socket, i| {
            if (input_socket.connected) {
                if (self.getInputConnection(node_id, @intCast(i))) |connection| {
                    try self.generateNodeCodeRecursive(connection.from_node, code, visited);
                }
            }
        }

        // Generate this node's code
        const node_code = try node.generateCode(self.connections.values());
        defer self.allocator.free(node_code);

        try code.appendSlice("    ");
        try code.appendSlice(node_code);
        try code.appendSlice("\n");
    }

    fn getInputConnection(self: *ShaderGraph, node_id: u32, socket_index: u32) ?*Connection {
        var connection_iterator = self.connections.iterator();
        while (connection_iterator.next()) |entry| {
            const connection = entry.value_ptr;
            if (connection.to_node == node_id and connection.to_socket == socket_index) {
                return connection;
            }
        }
        return null;
    }

    pub fn validateGraph(self: *ShaderGraph) !bool {
        // Check for cycles using DFS
        var visited = std.AutoHashMap(u32, bool).init(self.allocator);
        defer visited.deinit();

        var recursion_stack = std.AutoHashMap(u32, bool).init(self.allocator);
        defer recursion_stack.deinit();

        var node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            if (!(visited.get(node_id) orelse false)) {
                if (try self.hasCycle(node_id, &visited, &recursion_stack)) {
                    return false; // Cycle detected
                }
            }
        }

        return true;
    }

    fn hasCycle(self: *ShaderGraph, node_id: u32, visited: *std.AutoHashMap(u32, bool), rec_stack: *std.AutoHashMap(u32, bool)) !bool {
        try visited.put(node_id, true);
        try rec_stack.put(node_id, true);

        // Check all nodes connected from this node's outputs
        var connection_iterator = self.connections.iterator();
        while (connection_iterator.next()) |entry| {
            const connection = entry.value_ptr;
            if (connection.from_node == node_id) {
                const target_node_id = connection.to_node;
                if (!(visited.get(target_node_id) orelse false)) {
                    if (try self.hasCycle(target_node_id, visited, rec_stack)) {
                        return true;
                    }
                } else if (rec_stack.get(target_node_id) orelse false) {
                    return true; // Cycle detected
                }
            }
        }

        try rec_stack.put(node_id, false);
        return false;
    }

    pub fn saveToFile(self: *ShaderGraph, file_path: []const u8) !void {
        // Implementation for saving graph to file (JSON format)
        _ = self;
        _ = file_path;
        // TODO: Implement JSON serialization
    }

    pub fn loadFromFile(self: *ShaderGraph, file_path: []const u8) !void {
        // Implementation for loading graph from file
        _ = self;
        _ = file_path;
        // TODO: Implement JSON deserialization
    }
};

pub const NodeShaderEditor = struct {
    allocator: Allocator,
    graphs: HashMap([]const u8, ShaderGraph, std.hash_map.AutoContext([]const u8)),
    active_graph: ?[]const u8,
    compiler: *DynamicShaderCompiler,
    node_library: ArrayList(NodeType),

    pub fn init(allocator: Allocator, compiler: *DynamicShaderCompiler) !NodeShaderEditor {
        var editor = NodeShaderEditor{
            .allocator = allocator,
            .graphs = HashMap([]const u8, ShaderGraph, std.hash_map.AutoContext([]const u8)).init(allocator),
            .active_graph = null,
            .compiler = compiler,
            .node_library = ArrayList(NodeType).init(allocator),
        };

        // Initialize node library
        try editor.initializeNodeLibrary();
        return editor;
    }

    pub fn deinit(self: *NodeShaderEditor) void {
        var graph_iterator = self.graphs.iterator();
        while (graph_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.graphs.deinit();
        self.node_library.deinit();

        if (self.active_graph) |name| {
            self.allocator.free(name);
        }
    }

    pub fn createGraph(self: *NodeShaderEditor, name: []const u8, shader_type: ShaderType) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        var graph = try ShaderGraph.init(self.allocator, owned_name, shader_type);

        // Add default input and output nodes
        const input_pos = Vec2{ .x = 50.0, .y = 100.0 };
        const output_pos = Vec2{ .x = 400.0, .y = 100.0 };

        switch (shader_type) {
            .vertex => {
                _ = try graph.addNode(.vertex_input, input_pos);
                _ = try graph.addNode(.vertex_output, output_pos);
            },
            .fragment => {
                _ = try graph.addNode(.texture_coordinate, input_pos);
                _ = try graph.addNode(.fragment_output, output_pos);
            },
            .compute => {
                _ = try graph.addNode(.constant, input_pos);
            },
            else => {},
        }

        try self.graphs.put(owned_name, graph);

        if (self.active_graph) |old_name| {
            self.allocator.free(old_name);
        }
        self.active_graph = try self.allocator.dupe(u8, owned_name);
    }

    pub fn getActiveGraph(self: *NodeShaderEditor) ?*ShaderGraph {
        if (self.active_graph) |name| {
            return self.graphs.getPtr(name);
        }
        return null;
    }

    pub fn setActiveGraph(self: *NodeShaderEditor, name: []const u8) !void {
        if (self.graphs.contains(name)) {
            if (self.active_graph) |old_name| {
                self.allocator.free(old_name);
            }
            self.active_graph = try self.allocator.dupe(u8, name);
        }
    }

    pub fn compileActiveGraph(self: *NodeShaderEditor) ![]const u8 {
        if (self.getActiveGraph()) |graph| {
            return try graph.generateShaderCode(self.compiler);
        }
        return error.NoActiveGraph;
    }

    pub fn getNodeTypes(self: *NodeShaderEditor, category: ?NodeCategory) []const NodeType {
        if (category) |cat| {
            // Filter by category
            var filtered = ArrayList(NodeType).init(self.allocator);
            defer filtered.deinit();

            for (self.node_library.items) |node_type| {
                if (node_type.getCategory() == cat) {
                    filtered.append(node_type) catch {};
                }
            }
            return filtered.toOwnedSlice() catch &[_]NodeType{};
        }
        return self.node_library.items;
    }

    fn initializeNodeLibrary(self: *NodeShaderEditor) !void {
        // Add all available node types to the library
        const all_nodes = [_]NodeType{
            .vertex_input,    .texture_coordinate, .normal_input,    .position_input,
            .time_input,      .camera_position,    .world_position,  .view_direction,
            .light_direction, .add,                .subtract,        .multiply,
            .divide,          .dot_product,        .cross_product,   .normalize,
            .length,          .distance,           .power,           .sqrt,
            .sin,             .cos,                .tan,             .lerp,
            .clamp,           .saturate,           .min_node,        .max_node,
            .texture_sample,  .texture_sample_lod, .split,           .combine,
            .constant,        .lambert,            .phong,           .blinn_phong,
            .pbr,             .fresnel,            .perlin_noise,    .simplex_noise,
            .voronoi,         .vertex_output,      .fragment_output, .surface_output,
            .if_node,         .custom_function,
        };

        for (all_nodes) |node_type| {
            try self.node_library.append(node_type);
        }
    }
};

// Test the complete node editor system
test "node shader editor system" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var compiler = try DynamicShaderCompiler.init(allocator, "test_cache", 1024 * 1024);
    defer compiler.deinit();

    var editor = try NodeShaderEditor.init(allocator, &compiler);
    defer editor.deinit();

    // Create a fragment shader graph
    try editor.createGraph("test_material", .fragment);

    const graph = editor.getActiveGraph().?;

    // Add nodes for a simple material
    const texture_node = try graph.addNode(.texture_sample, Vec2{ .x = 150.0, .y = 100.0 });
    const multiply_node = try graph.addNode(.multiply, Vec2{ .x = 300.0, .y = 150.0 });

    // Connect texture coordinate to texture sample
    _ = try graph.connectNodes(1, 0, texture_node, 1); // UV output to texture UV input

    // Connect texture output to multiply
    _ = try graph.connectNodes(texture_node, 0, multiply_node, 0); // Color to multiply A

    // Connect multiply to fragment output
    _ = try graph.connectNodes(multiply_node, 0, 2, 0); // Result to fragment color

    // Validate the graph
    const is_valid = try graph.validateGraph();
    try std.testing.expect(is_valid);

    // Generate shader code
    const shader_code = try editor.compileActiveGraph();
    defer allocator.free(shader_code);

    try std.testing.expect(shader_code.len > 0);
}
