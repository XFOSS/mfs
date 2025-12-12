//! MFS Engine - Neural Module
//! Neural networks and artificial intelligence system
//! Provides neural network construction, training, and inference capabilities
//! @thread-safe Neural operations can be multi-threaded for performance
//! @performance Optimized with SIMD operations and GPU acceleration where available

const std = @import("std");
const builtin = @import("builtin");

// Core neural components
pub const brain = @import("brain.zig");
pub const activations = @import("activations.zig");

// Re-export main neural types
pub const Brain = brain.NeuralBrain;
pub const NeuralBrain = brain.NeuralBrain;
pub const NeuralNetwork = brain.NeuralBrain.NeuralNetwork;
pub const Layer = brain.NeuralBrain.NeuralNetwork.Layer;
pub const AIAgent = brain.NeuralBrain.AIAgent;
pub const BehaviorTree = brain.NeuralBrain.BehaviorTree;
pub const Neuron = brain.Neuron;

// Activation functions
pub const ActivationFunction = activations.ActivationFunction;
pub const ActivationType = activations.ActivationType;

// Neural network architectures
pub const NetworkArchitecture = enum {
    feedforward,
    convolutional,
    recurrent,
    lstm,
    gru,
    transformer,

    pub fn getName(self: NetworkArchitecture) []const u8 {
        return switch (self) {
            .feedforward => "Feedforward",
            .convolutional => "Convolutional",
            .recurrent => "Recurrent",
            .lstm => "LSTM",
            .gru => "GRU",
            .transformer => "Transformer",
        };
    }
};

// Training algorithms
pub const TrainingAlgorithm = enum {
    gradient_descent,
    adam,
    rmsprop,
    adagrad,

    pub fn getName(self: TrainingAlgorithm) []const u8 {
        return switch (self) {
            .gradient_descent => "Gradient Descent",
            .adam => "Adam",
            .rmsprop => "RMSprop",
            .adagrad => "Adagrad",
        };
    }
};

// Loss functions
pub const LossFunction = enum {
    mean_squared_error,
    cross_entropy,
    binary_cross_entropy,
    huber,

    pub fn getName(self: LossFunction) []const u8 {
        return switch (self) {
            .mean_squared_error => "Mean Squared Error",
            .cross_entropy => "Cross Entropy",
            .binary_cross_entropy => "Binary Cross Entropy",
            .huber => "Huber Loss",
        };
    }
};

// Neural system configuration
pub const NeuralConfig = struct {
    enable_gpu_acceleration: bool = true,
    enable_multithreading: bool = true,
    max_threads: u32 = 0, // 0 = auto-detect
    learning_rate: f32 = 0.001,
    batch_size: u32 = 32,
    max_epochs: u32 = 1000,
    early_stopping_patience: u32 = 10,

    pub fn validate(self: NeuralConfig) !void {
        if (self.learning_rate <= 0.0 or self.learning_rate > 1.0) {
            return error.InvalidParameter;
        }
        if (self.batch_size == 0 or self.batch_size > 10000) {
            return error.InvalidParameter;
        }
        if (self.max_epochs == 0) {
            return error.InvalidParameter;
        }
    }
};

// Initialize neural system
pub fn init(allocator: std.mem.Allocator, config: NeuralConfig) !*Brain {
    try config.validate();
    return try Brain.init(allocator);
}

// Cleanup neural system
pub fn deinit(brain_instance: *Brain) void {
    brain_instance.deinit();
}

// Create a simple feedforward network
pub fn createFeedforwardNetwork(
    allocator: std.mem.Allocator,
    layer_sizes: []const u32,
    activation: ActivationType,
) !*NeuralNetwork {
    return try NeuralNetwork.createFeedforward(allocator, layer_sizes, activation);
}

test "neural module" {
    std.testing.refAllDecls(@This());
}
