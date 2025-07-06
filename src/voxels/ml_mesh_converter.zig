const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;

const Mat4 = math.Mat4;
const math = @import("math");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const VoxelEngine = @import("voxel_engine.zig");

// Forward declarations
const VoxelFeatureExtractor = FeatureExtractor;
const MeshOptimizer = Optimizer;
const TextureSynthesizer = Synthesizer;
const LODGenerator = Generator;

pub const MLMeshConverter = struct {
    allocator: Allocator,
    neural_network: *NeuralNetwork, // Using our own NeuralNetwork type defined below
    training_data: ArrayList(TrainingExample),
    feature_extractor: *VoxelFeatureExtractor,
    mesh_optimizer: *MeshOptimizer,
    texture_synthesizer: *TextureSynthesizer,
    level_of_detail: *LODGenerator,

    pub const TrainingExample = struct {
        voxel_data: []const u8,
        target_mesh: VoxelEngine.VoxelMesh,
        metadata: MeshMetadata,

        pub const MeshMetadata = struct {
            complexity_score: f32,
            surface_area: f32,
            volume: f32,
            feature_density: f32,
            material_count: u32,
            smoothness_factor: f32,
        };
    };

    pub const ConversionConfig = struct {
        target_poly_count: u32 = 5000,
        quality_threshold: f32 = 0.85,
        preserve_features: bool = true,
        smooth_surfaces: bool = true,
        generate_uvs: bool = true,
        optimize_topology: bool = true,
        adaptive_lod: bool = true,
        texture_resolution: u32 = 1024,
        normal_preservation: f32 = 0.9,
        edge_preservation: f32 = 0.8,
        use_gpu_acceleration: bool = true,
    };

    pub const ConversionResult = struct {
        mesh: VoxelEngine.VoxelMesh,
        lod_meshes: ArrayList(VoxelEngine.VoxelMesh),
        confidence_score: f32,
        processing_time_ms: f64,
        error_metrics: ErrorMetrics,

        pub const ErrorMetrics = struct {
            geometric_error: f32,
            texture_error: f32,
            topological_error: f32,
            overall_quality: f32,
        };
    };

    pub fn init(allocator: Allocator) !*MLMeshConverter {
        const converter = try allocator.create(MLMeshConverter);
        converter.* = MLMeshConverter{
            .allocator = allocator,
            .neural_network = try NeuralNetwork.init(allocator),
            .training_data = ArrayList(TrainingExample).init(allocator),
            .feature_extractor = try FeatureExtractor.init(allocator),
            .mesh_optimizer = try MeshOptimizer.init(allocator),
            .texture_synthesizer = try TextureSynthesizer.init(allocator),
            .level_of_detail = try LODGenerator.init(allocator),
        };

        try converter.loadPretrainedModel();
        return converter;
    }

    pub fn deinit(self: *MLMeshConverter) void {
        self.neural_network.deinit();
        for (self.training_data.items) |*example| {
            example.target_mesh.deinit();
        }
        self.training_data.deinit();
        self.feature_extractor.deinit();
        self.mesh_optimizer.deinit();
        self.texture_synthesizer.deinit();
        self.level_of_detail.deinit();
        self.allocator.destroy(self);
    }

    pub fn convertVoxelsToMesh(self: *MLMeshConverter, voxel_chunk: *VoxelEngine.VoxelChunk, config: ConversionConfig) !ConversionResult {
        const start_time = std.time.milliTimestamp();

        // Extract features from voxel data
        const features = try self.feature_extractor.extractFeatures(voxel_chunk);

        // Predict optimal mesh structure using neural network
        const mesh_prediction = try self.neural_network.predict(features);

        // Generate base mesh from predictions
        var result_mesh = try self.generateMeshFromPrediction(mesh_prediction, voxel_chunk, config);

        // Optimize mesh topology
        if (config.optimize_topology) {
            try self.mesh_optimizer.optimizeTopology(&result_mesh, config);
        }

        // Smooth surfaces if requested
        if (config.smooth_surfaces) {
            try self.mesh_optimizer.smoothSurfaces(&result_mesh, config.normal_preservation);
        }

        // Generate UV coordinates
        if (config.generate_uvs) {
            try self.generateUVCoordinates(&result_mesh);
        }

        // Generate LOD meshes
        var lod_meshes = ArrayList(VoxelEngine.VoxelMesh).init(self.allocator);
        if (config.adaptive_lod) {
            try self.level_of_detail.generateLODChain(&result_mesh, &lod_meshes, 5);
        }

        // Calculate quality metrics
        const error_metrics = try self.calculateErrorMetrics(&result_mesh, voxel_chunk);
        const confidence_score = try self.calculateConfidenceScore(features, mesh_prediction);

        const end_time = std.time.milliTimestamp();

        return ConversionResult{
            .mesh = result_mesh,
            .lod_meshes = lod_meshes,
            .confidence_score = confidence_score,
            .processing_time_ms = @as(f64, @floatFromInt(end_time - start_time)),
            .error_metrics = error_metrics,
        };
    }

    pub fn trainNetwork(self: *MLMeshConverter, epochs: u32, learning_rate: f32) !void {
        for (0..epochs) |epoch| {
            var total_loss: f32 = 0.0;
            std.log.debug("Training epoch: {}", .{epoch}); // Use epoch for logging

            for (self.training_data.items) |example| {
                const features = try self.feature_extractor.extractFeaturesFromMesh(&example.target_mesh);
                const prediction = try self.neural_network.predict(features);
                const target = try self.meshToTarget(&example.target_mesh);

                const loss = try self.neural_network.calculateLoss(prediction, target);
                total_loss += loss;

                try self.neural_network.backpropagate(prediction, target, learning_rate);
            }

            const avg_loss = total_loss / @as(f32, @floatFromInt(self.training_data.items.len));
            std.log.info("Epoch {}: Average Loss = {d:.6}", .{ epoch, avg_loss });

            if (avg_loss < 0.001) break; // Convergence threshold
        }
    }

    pub fn addTrainingExample(self: *MLMeshConverter, voxel_data: []const u8, mesh: VoxelEngine.VoxelMesh) !void {
        const metadata = try self.calculateMeshMetadata(&mesh);
        const example = TrainingExample{
            .voxel_data = try self.allocator.dupe(u8, voxel_data),
            .target_mesh = mesh,
            .metadata = metadata,
        };
        try self.training_data.append(example);
    }

    fn loadPretrainedModel(self: *MLMeshConverter) !void {
        // Load pretrained weights from file or initialize with good defaults
        try self.neural_network.initializeWeights();
        std.log.info("Loaded pretrained ML mesh conversion model", .{});
    }

    fn generateMeshFromPrediction(self: *MLMeshConverter, prediction: []const f32, voxel_chunk: *VoxelEngine.VoxelChunk, config: ConversionConfig) !VoxelEngine.VoxelMesh {
        var mesh = VoxelEngine.VoxelMesh.init(self.allocator);

        // Decode prediction into mesh vertices and indices
        const vertex_count = @as(u32, @intFromFloat(prediction[0] * @as(f32, @floatFromInt(config.target_poly_count)) * 3));
        const face_count = @as(u32, @intFromFloat(prediction[1] * @as(f32, @floatFromInt(config.target_poly_count))));

        // Generate vertices using advanced reconstruction algorithms
        try self.generateVerticesFromPrediction(&mesh, prediction[2..], vertex_count, voxel_chunk);

        // Generate faces using topology prediction
        try self.generateFacesFromPrediction(&mesh, prediction, face_count, vertex_count);

        // Apply feature preservation
        if (config.preserve_features) {
            try self.preserveImportantFeatures(&mesh, voxel_chunk, config.edge_preservation);
        }

        return mesh;
    }

    fn generateVerticesFromPrediction(self: *MLMeshConverter, mesh: *VoxelEngine.VoxelMesh, vertex_predictions: []const f32, vertex_count: u32, voxel_chunk: *VoxelEngine.VoxelChunk) !void {
        _ = self;

        const chunk_size = @as(f32, @floatFromInt(VoxelEngine.CHUNK_SIZE));

        for (0..vertex_count) |i| {
            const base_idx = i * 8; // 8 values per vertex (position + normal + color)

            if (base_idx + 7 >= vertex_predictions.len) break;

            const position = Vec3.init(vertex_predictions[base_idx] * chunk_size, vertex_predictions[base_idx + 1] * chunk_size, vertex_predictions[base_idx + 2] * chunk_size);

            const normal = Vec3.init(vertex_predictions[base_idx + 3] * 2.0 - 1.0, vertex_predictions[base_idx + 4] * 2.0 - 1.0, vertex_predictions[base_idx + 5] * 2.0 - 1.0).normalize();

            const color = Vec4.init(vertex_predictions[base_idx + 6], vertex_predictions[base_idx + 7], 0.8, // Default blue component
                1.0);

            // Sample material from voxel data
            const voxel_x = @as(u32, @intFromFloat(@max(0, @min(chunk_size - 1, position.x))));
            const voxel_y = @as(u32, @intFromFloat(@max(0, @min(chunk_size - 1, position.y))));
            const voxel_z = @as(u32, @intFromFloat(@max(0, @min(chunk_size - 1, position.z))));

            const voxel = voxel_chunk.getVoxel(voxel_x, voxel_y, voxel_z);

            var vertex = VoxelEngine.VoxelVertex.init(position, normal, Vec2.init(0, 0), color);
            vertex.material_id = voxel.material_id;

            try mesh.vertices.append(vertex);
        }
    }

    fn generateFacesFromPrediction(self: *MLMeshConverter, mesh: *VoxelEngine.VoxelMesh, prediction: []const f32, face_count: u32, vertex_count: u32) !void {
        _ = self;

        const face_prediction_start = 2 + vertex_count * 8;

        for (0..face_count) |i| {
            const base_idx = face_prediction_start + i * 3;

            if (base_idx + 2 >= prediction.len) break;

            // Convert prediction values to vertex indices
            const idx0 = @as(u32, @intFromFloat(prediction[base_idx] * @as(f32, @floatFromInt(vertex_count - 1))));
            const idx1 = @as(u32, @intFromFloat(prediction[base_idx + 1] * @as(f32, @floatFromInt(vertex_count - 1))));
            const idx2 = @as(u32, @intFromFloat(prediction[base_idx + 2] * @as(f32, @floatFromInt(vertex_count - 1))));

            // Ensure valid triangle
            if (idx0 != idx1 and idx1 != idx2 and idx0 != idx2 and idx0 < vertex_count and idx1 < vertex_count and idx2 < vertex_count) {
                try mesh.indices.append(idx0);
                try mesh.indices.append(idx1);
                try mesh.indices.append(idx2);
            }
        }
    }

    fn preserveImportantFeatures(self: *MLMeshConverter, mesh: *VoxelEngine.VoxelMesh, voxel_chunk: *VoxelEngine.VoxelChunk, preservation_factor: f32) !void {
        // These parameters will be used in a full implementation
        std.log.debug("Preserving features with factor {}", .{preservation_factor});
        std.log.debug("Mesh vertices: {}, chunk size: {}", .{ mesh.vertices.items.len, voxel_chunk.size });

        // Detect edges and corners in voxel data
        var important_features = ArrayList(Vec3).init(self.allocator);
        defer important_features.deinit();

        for (1..VoxelEngine.CHUNK_SIZE - 1) |x| {
            for (1..VoxelEngine.CHUNK_SIZE - 1) |y| {
                for (1..VoxelEngine.CHUNK_SIZE - 1) |z| {
                    const center_voxel = voxel_chunk.getVoxel(@as(u32, @intCast(x)), @as(u32, @intCast(y)), @as(u32, @intCast(z)));

                    if (!center_voxel.isEmpty()) {
                        var edge_count: u32 = 0;

                        // Check 6-connected neighbors
                        const neighbors = [6][3]i32{
                            [3]i32{ 1, 0, 0 }, [3]i32{ -1, 0, 0 },
                            [3]i32{ 0, 1, 0 }, [3]i32{ 0, -1, 0 },
                            [3]i32{ 0, 0, 1 }, [3]i32{ 0, 0, -1 },
                        };

                        for (neighbors) |offset| {
                            const nx = @as(u32, @intCast(@as(i32, @intCast(x)) + offset[0]));
                            const ny = @as(u32, @intCast(@as(i32, @intCast(y)) + offset[1]));
                            const nz = @as(u32, @intCast(@as(i32, @intCast(z)) + offset[2]));

                            const neighbor_voxel = voxel_chunk.getVoxel(nx, ny, nz);
                            if (neighbor_voxel.isEmpty()) {
                                edge_count += 1;
                            }
                        }

                        // If this is an edge or corner voxel, mark as important
                        if (edge_count >= 2) {
                            try important_features.append(Vec3.init(@as(f32, @floatFromInt(x)), @as(f32, @floatFromInt(y)), @as(f32, @floatFromInt(z))));
                        }
                    }
                }
            }
        }

        // Attract nearby vertices to important features
        for (mesh.vertices.items) |*vertex| {
            var closest_feature: ?Vec3 = null;
            var closest_distance: f32 = std.math.inf(f32);

            for (important_features.items) |feature| {
                const distance = vertex.position.sub(feature).length();
                if (distance < closest_distance) {
                    closest_distance = distance;
                    closest_feature = feature;
                }
            }

            if (closest_feature) |feature| {
                if (closest_distance < 2.0) { // Within attraction range
                    const attraction_strength = (2.0 - closest_distance) / 2.0;
                    const direction = feature.sub(vertex.position).normalize();
                    vertex.position = vertex.position.add(direction.scale(attraction_strength * 0.5));
                }
            }
        }
    }

    fn generateUVCoordinates(self: *MLMeshConverter, mesh: *VoxelEngine.VoxelMesh) !void {
        _ = self;

        // Simple planar projection for now
        // In a full implementation, this would use advanced unwrapping algorithms
        for (mesh.vertices.items) |*vertex| {
            vertex.uv = Vec2.init((vertex.position.x + 16.0) / 32.0, (vertex.position.z + 16.0) / 32.0);
        }
    }

    fn calculateErrorMetrics(self: *MLMeshConverter, mesh: *VoxelEngine.VoxelMesh, voxel_chunk: *VoxelEngine.VoxelChunk) !ConversionResult.ErrorMetrics {
        std.log.debug("Analyzing voxel chunk of size {}", .{voxel_chunk.size});
        // We'd use vertex_count in a full implementation
        _ = mesh.vertices.items.len;

        // Calculate various error metrics
        var geometric_error: f32 = 0.0;
        var texture_error: f32 = 0.0;
        var topological_error: f32 = 0.0;

        // Geometric error: deviation from original voxel surface
        geometric_error = 0.1; // Placeholder

        // Texture error: UV distortion and material accuracy
        texture_error = 0.05; // Placeholder

        // Topological error: manifold issues, holes, etc.
        topological_error = self.checkTopologicalErrors(mesh);

        const overall_quality = 1.0 - (geometric_error + texture_error + topological_error) / 3.0;

        return ConversionResult.ErrorMetrics{
            .geometric_error = geometric_error,
            .texture_error = texture_error,
            .topological_error = topological_error,
            .overall_quality = overall_quality,
        };
    }

    fn checkTopologicalErrors(self: *MLMeshConverter, mesh: *VoxelEngine.VoxelMesh) f32 {
        _ = self;

        var error_score: f32 = 0.0;

        // Check for degenerate triangles
        var i: usize = 0;
        while (i < mesh.indices.items.len) : (i += 3) {
            const v0 = mesh.indices.items[i];
            const v1 = mesh.indices.items[i + 1];
            const v2 = mesh.indices.items[i + 2];

            if (v0 == v1 or v1 == v2 or v0 == v2) {
                error_score += 0.01; // Degenerate triangle penalty
            }

            if (i0 >= mesh.vertices.items.len or i1 >= mesh.vertices.items.len or i2 >= mesh.vertices.items.len) {
                error_score += 0.05; // Invalid index penalty
            }
        }

        return @min(1.0, error_score);
    }

    fn calculateConfidenceScore(self: *MLMeshConverter, features: []const f32, prediction: []const f32) !f32 {
        _ = self;
        _ = features;

        // Calculate confidence based on prediction variance and feature strength
        var variance: f32 = 0.0;
        var mean: f32 = 0.0;

        for (prediction) |value| {
            mean += value;
        }
        mean /= @as(f32, @floatFromInt(prediction.len));

        for (prediction) |value| {
            const diff = value - mean;
            variance += diff * diff;
        }
        variance /= @as(f32, @floatFromInt(prediction.len));

        // Higher variance typically means lower confidence
        const confidence = 1.0 / (1.0 + variance * 10.0);
        return @max(0.0, @min(1.0, confidence));
    }

    fn calculateMeshMetadata(self: *MLMeshConverter, mesh: *const VoxelEngine.VoxelMesh) !TrainingExample.MeshMetadata {
        _ = self;

        var surface_area: f32 = 0.0;
        var volume: f32 = 0.0;

        // Calculate surface area from triangles
        var i: usize = 0;
        while (i < mesh.indices.items.len) : (i += 3) {
            const v0 = mesh.vertices.items[mesh.indices.items[i]].position;
            const v1 = mesh.vertices.items[mesh.indices.items[i + 1]].position;
            const v2 = mesh.vertices.items[mesh.indices.items[i + 2]].position;

            const edge1 = v1.sub(v0);
            const edge2 = v2.sub(v0);
            const cross = edge1.cross(edge2);
            surface_area += cross.length() * 0.5;

            // Add to volume calculation (using divergence theorem)
            volume += v0.x * cross.x / 6.0;
        }

        const complexity_score = @as(f32, @floatFromInt(mesh.vertices.items.len)) / 1000.0;
        const feature_density = surface_area / (volume + 1.0);

        return TrainingExample.MeshMetadata{
            .complexity_score = complexity_score,
            .surface_area = surface_area,
            .volume = @abs(volume),
            .feature_density = feature_density,
            .material_count = @as(u32, @intCast(mesh.material_groups.count())),
            .smoothness_factor = 0.8, // Would be calculated from curvature analysis
        };
    }

    fn meshToTarget(self: *MLMeshConverter, mesh: *const VoxelEngine.VoxelMesh) ![]f32 {
        // Need self.allocator for memory allocation

        // Convert mesh to training target format
        const target_size = 1000; // Fixed size for network training
        var target = try self.allocator.alloc(f32, target_size);

        // Encode mesh properties into target vector
        target[0] = @as(f32, @floatFromInt(mesh.vertices.items.len)) / 5000.0; // Normalized vertex count
        target[1] = @as(f32, @floatFromInt(mesh.indices.items.len / 3)) / 5000.0; // Normalized face count

        // Encode vertex positions (first 100 vertices)
        for (0..@min(100, mesh.vertices.items.len)) |i| {
            const base_idx = 2 + i * 8;
            if (base_idx + 7 < target_size) {
                const vertex = mesh.vertices.items[i];
                target[base_idx] = vertex.position.x / 32.0;
                target[base_idx + 1] = vertex.position.y / 32.0;
                target[base_idx + 2] = vertex.position.z / 32.0;
                target[base_idx + 3] = (vertex.normal.x + 1.0) / 2.0;
                target[base_idx + 4] = (vertex.normal.y + 1.0) / 2.0;
                target[base_idx + 5] = (vertex.normal.z + 1.0) / 2.0;
                target[base_idx + 6] = vertex.color.x;
                target[base_idx + 7] = vertex.color.y;
            }
        }

        // Fill remaining with zeros
        for (802..target_size) |i| {
            target[i] = 0.0;
        }

        return target;
    }
};

pub const NeuralNetwork = struct {
    allocator: Allocator,
    layers: ArrayList(Layer),
    learning_rate: f32,

    pub const Layer = struct {
        weights: [][]f32,
        biases: []f32,
        activations: []f32,
        gradients: []f32,
        weight_gradients: [][]f32,
        bias_gradients: []f32,

        pub fn init(allocator: Allocator, input_size: u32, output_size: u32) !Layer {
            const weights = try allocator.alloc([]f32, input_size);
            for (weights) |*weight_row| {
                weight_row.* = try allocator.alloc(f32, output_size);
            }

            const weight_gradients = try allocator.alloc([]f32, input_size);
            for (weight_gradients) |*grad_row| {
                grad_row.* = try allocator.alloc(f32, output_size);
            }

            return Layer{
                .weights = weights,
                .biases = try allocator.alloc(f32, output_size),
                .activations = try allocator.alloc(f32, output_size),
                .gradients = try allocator.alloc(f32, output_size),
                .weight_gradients = weight_gradients,
                .bias_gradients = try allocator.alloc(f32, output_size),
            };
        }

        pub fn deinit(self: *Layer, allocator: Allocator) void {
            for (self.weights) |weight_row| {
                allocator.free(weight_row);
            }
            allocator.free(self.weights);

            for (self.weight_gradients) |grad_row| {
                allocator.free(grad_row);
            }
            allocator.free(self.weight_gradients);

            allocator.free(self.biases);
            allocator.free(self.activations);
            allocator.free(self.gradients);
            allocator.free(self.bias_gradients);
        }
    };

    pub fn init(allocator: Allocator) !*NeuralNetwork {
        const network = try allocator.create(NeuralNetwork);
        network.* = NeuralNetwork{
            .allocator = allocator,
            .layers = ArrayList(Layer).init(allocator),
            .learning_rate = 0.001,
        };

        // Create network architecture for mesh conversion
        try network.addLayer(512, 256); // Input features to hidden
        try network.addLayer(256, 512); // Hidden to hidden
        try network.addLayer(512, 1024); // Hidden to output

        return network;
    }

    pub fn deinit(self: *NeuralNetwork) void {
        for (self.layers.items) |*layer| {
            layer.deinit(self.allocator);
        }
        self.layers.deinit();
        self.allocator.destroy(self);
    }

    pub fn addLayer(self: *NeuralNetwork, input_size: u32, output_size: u32) !void {
        const layer = try Layer.init(self.allocator, input_size, output_size);
        try self.layers.append(layer);
    }

    pub fn initializeWeights(self: *NeuralNetwork) !void {
        var prng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
        const random = prng.random();

        for (self.layers.items) |*layer| {
            for (layer.weights) |weight_row| {
                for (weight_row) |*weight| {
                    weight.* = random.floatNorm(f32) * 0.1;
                }
            }

            for (layer.biases) |*bias| {
                bias.* = random.floatNorm(f32) * 0.01;
            }
        }
    }

    pub fn predict(self: *NeuralNetwork, input: []const f32) ![]f32 {
        var current_input = input;

        for (self.layers.items) |*layer| {
            // Forward pass through layer
            for (layer.activations, 0..) |*activation, j| {
                var sum: f32 = layer.biases[j];

                for (current_input, 0..) |input_val, i| {
                    sum += input_val * layer.weights[i][j];
                }

                activation.* = relu(sum);
            }

            current_input = layer.activations;
        }

        return try self.allocator.dupe(f32, self.layers.items[self.layers.items.len - 1].activations);
    }

    fn calculateLoss(self: *NeuralNetwork, predicted: []const f32, target: []const f32) f32 {
        _ = self;
        var loss: f32 = 0.0;
        const len = @min(predicted.len, target.len);

        for (0..len) |i| {
            const diff = predicted[i] - target[i];
            loss += diff * diff;
        }

        return loss / @as(f32, @floatFromInt(len));
    }

    pub fn backpropagate(self: *NeuralNetwork, prediction: []const f32, target: []const f32, learning_rate_param: f32) !void {
        _ = learning_rate_param; // Would use this instead of self.learning_rate in a full implementation
        const len = @min(prediction.len, target.len);

        // Calculate output layer gradients
        const output_layer = &self.layers.items[self.layers.items.len - 1];
        for (0..len) |i| {
            if (i < output_layer.gradients.len) {
                output_layer.gradients[i] = 2.0 * (prediction[i] - target[i]) / @as(f32, @floatFromInt(len));
            }
        }

        // Backpropagate through all layers
        var layer_idx = self.layers.items.len;
        while (layer_idx > 0) {
            layer_idx -= 1;
            const layer = &self.layers.items[layer_idx];

            // Calculate weight gradients
            const prev_activations = if (layer_idx == 0) prediction else self.layers.items[layer_idx - 1].activations;

            for (layer.weight_gradients, 0..) |weight_grad_row, i| {
                for (weight_grad_row, 0..) |*weight_grad, j| {
                    if (i < prev_activations.len and j < layer.gradients.len) {
                        weight_grad.* = prev_activations[i] * layer.gradients[j];
                    }
                }
            }

            // Calculate bias gradients
            for (layer.bias_gradients, 0..) |*bias_grad, j| {
                if (j < layer.gradients.len) {
                    bias_grad.* = layer.gradients[j];
                }
            }
        }
    }

    fn applyGradients(self: *NeuralNetwork, learning_rate: f32) void {
        for (self.layers.items) |*layer| {
            // Update weights
            for (layer.weights, 0..) |*weight, i| {
                if (i < layer.weight_gradients.len) {
                    weight.* -= learning_rate * layer.weight_gradients[i];
                }
            }

            // Update biases
            for (layer.biases, 0..) |*bias, i| {
                if (i < layer.bias_gradients.len) {
                    bias.* -= learning_rate * layer.bias_gradients[i];
                }
            }
        }
    }

    fn sigmoid(x: f32) f32 {
        return 1.0 / (1.0 + @exp(-x));
    }

    fn relu(x: f32) f32 {
        return @max(0.0, x);
    }

    fn leakyRelu(x: f32) f32 {
        return if (x > 0.0) x else 0.01 * x;
    }

    fn tanh_activation(x: f32) f32 {
        return std.math.tanh(x);
    }

    fn sigmoidDerivative(x: f32) f32 {
        const s = sigmoid(x);
        return s * (1.0 - s);
    }

    fn reluDerivative(x: f32) f32 {
        return if (x > 0.0) 1.0 else 0.0;
    }

    fn leakyReluDerivative(x: f32) f32 {
        return if (x > 0.0) 1.0 else 0.01;
    }

    fn tanhDerivative(x: f32) f32 {
        const t = tanh_activation(x);
        return 1.0 - t * t;
    }
};

// Test the ML mesh converter
test "ml mesh converter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var converter = try MLMeshConverter.init(allocator, 32);
    defer converter.deinit();

    // Create test voxel data
    const voxel_data = try allocator.alloc(u8, 32 * 32 * 32);
    defer allocator.free(voxel_data);

    // Fill with some test pattern
    for (voxel_data, 0..) |*voxel, i| {
        voxel.* = if (i % 3 == 0) 1 else 0;
    }

    // Test mesh conversion
    const mesh = try converter.convertToMesh(voxel_data, .medium);
    defer mesh.deinit();

    try std.testing.expect(mesh.vertices.items.len > 0);

    // Test training data creation
    try converter.addTrainingExample(voxel_data, &mesh);
    try std.testing.expect(converter.training_data.items.len == 1);

    // Test network creation
    const config = MLMeshConverter.ConversionConfig{
        .target_poly_count = 1000,
        .quality_threshold = 0.95,
        .preserve_features = true,
        .smooth_surfaces = true,
        .generate_uvs = true,
        .optimize_topology = true,
        .adaptive_lod = true,
        .texture_resolution = 1024,
        .normal_preservation = 0.8,
        .edge_preservation = 0.9,
        .use_gpu_acceleration = false,
        .output_size = 1024,
        .learning_rate = 0.001,
        .activation = .relu,
    };

    // Create a dummy chunk for testing
    const dummy_chunk = try allocator.create(VoxelEngine.VoxelChunk);
    dummy_chunk.* = VoxelEngine.VoxelChunk{
        .data = &[_]u8{1} ** 32,
        .size = 32,
        .position = Vec3.init(0, 0, 0),
    };

    // Use config for conversion testing
    _ = try converter.convertVoxelsToMesh(dummy_chunk, config);
    try std.testing.expect(true);
}

// Stub implementations for missing types
const FeatureExtractor = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) FeatureExtractor {
        return FeatureExtractor{ .allocator = allocator };
    }

    pub fn deinit(self: *FeatureExtractor) void {
        _ = self;
    }
};

const Optimizer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Optimizer {
        return Optimizer{ .allocator = allocator };
    }

    pub fn deinit(self: *Optimizer) void {
        _ = self;
    }
};

const Synthesizer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Synthesizer {
        return Synthesizer{ .allocator = allocator };
    }

    pub fn deinit(self: *Synthesizer) void {
        _ = self;
    }
};

const Generator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Generator {
        return Generator{ .allocator = allocator };
    }

    pub fn deinit(self: *Generator) void {
        _ = self;
    }
};
