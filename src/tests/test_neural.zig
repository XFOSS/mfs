const std = @import("std");

const mfs = @import("mfs");
const neural = mfs.ai.neural_networks;
const math = mfs.math;

test "DenseLayer forward pass" {
    const allocator = std.testing.allocator;

    // Create a simple 2->2 layer with explicit weights for testing
    // However, our init randomizes weights. We should probably add a way to set weights manually or test properties.
    // For now, let's test that it runs without crashing and produces output of correct size.

    var layer = try neural.DenseLayer.init(allocator, 2, 2, .relu);
    defer layer.deinit();

    const input = &[_]f32{ 1.0, 0.5 };
    const output = try layer.forward(input);
    defer allocator.free(output);

    try std.testing.expectEqual(@as(usize, 2), output.len);
}

test "NeuralNetwork end-to-end" {
    const allocator = std.testing.allocator;

    const layers = &[_]u32{ 3, 5, 2 }; // Input 3, Hidden 5, Output 2
    const config = neural.NetworkConfig{
        .layers = layers,
        .activation = .relu,
        .learning_rate = 0.01,
    };

    var net = try neural.NeuralNetwork.init(allocator, config);
    defer net.deinit();

    const input = &[_]f32{ 0.1, 0.2, 0.3 };
    const output = try net.forward(input);
    defer allocator.free(output);

    try std.testing.expectEqual(@as(usize, 2), output.len);
}

test "NeuralNetwork invalid config" {
    const allocator = std.testing.allocator;
    const layers = &[_]u32{10}; // Only 1 layer (need at least 2 for input->output)

    const config = neural.NetworkConfig{
        .layers = layers,
    };

    try std.testing.expectError(error.InvalidNetworkConfiguration, neural.NeuralNetwork.init(allocator, config));
}
