const std = @import("std");

/// Supported activation kinds.
/// New functions can be added without touching call-sites.
pub const Kind = enum { relu, sigmoid, tanh };

/// Alias for backward compatibility
pub const ActivationType = Kind;

pub fn apply(kind: Kind, x: f32) f32 {
    return switch (kind) {
        .relu => relu(x),
        .sigmoid => sigmoid(x),
        .tanh => tanh(x),
    };
}

/// Derivative *with respect to the activation's input* expressed in terms of
/// the already-computed activation output `y`.  This avoids re-evaluating
/// `exp`, `tanh`, etc. during back-prop.
pub fn grad(kind: Kind, y: f32) f32 {
    return switch (kind) {
        .relu => gradRelu(y),
        .sigmoid => y * (1.0 - y),
        .tanh => 1.0 - y * y,
    };
}

// ---------------------------------------------------------------------------
// Individual activation implementations
// ---------------------------------------------------------------------------

inline fn relu(x: f32) f32 {
    return if (x > 0) x else 0;
}

inline fn gradRelu(y: f32) f32 {
    // For ReLU the gradient depends only on whether the pre-activation value
    // was positive.  Because `y == 0` implies `x <= 0` we can express it via
    // the post-activation output.
    return if (y > 0) 1.0 else 0.0;
}

inline fn sigmoid(x: f32) f32 {
    return 1.0 / (1.0 + @exp(-x));
}

inline fn tanh(x: f32) f32 {
    return std.math.tanh(x);
}
