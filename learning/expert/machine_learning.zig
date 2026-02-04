//! Machine Learning from scratch: Neural Networks with backpropagation
//! Demonstrates: SIMD operations, manual memory management, numerical computing
//! Features: Dense layers, activation functions, backpropagation, gradient descent

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Random = std.rand.Random;

/// Matrix structure with SIMD-optimized operations
const Matrix = struct {
    data: []f32,
    rows: usize,
    cols: usize,
    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator, rows: usize, cols: usize) !Self {
        const data = try allocator.alloc(f32, rows * cols);
        @memset(data, 0);

        return .{
            .data = data,
            .rows = rows,
            .cols = cols,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    fn clone(self: *const Self) !Self {
        var result = try Self.init(self.allocator, self.rows, self.cols);
        @memcpy(result.data, self.data);
        return result;
    }

    fn get(self: *const Self, row: usize, col: usize) f32 {
        return self.data[row * self.cols + col];
    }

    fn set(self: *Self, row: usize, col: usize, value: f32) void {
        self.data[row * self.cols + col] = value;
    }

    /// Initialize with random values using Xavier/Glorot initialization
    fn randomInit(self: *Self, random: Random) void {
        const scale = @sqrt(2.0 / @as(f32, @floatFromInt(self.rows + self.cols)));
        for (self.data) |*val| {
            val.* = (random.float(f32) * 2.0 - 1.0) * scale;
        }
    }

    /// Matrix multiplication: C = A * B
    fn matmul(a: *const Self, b: *const Self, allocator: Allocator) !Self {
        if (a.cols != b.rows) return error.DimensionMismatch;

        var result = try Self.init(allocator, a.rows, b.cols);

        // SIMD-friendly implementation
        for (0..a.rows) |i| {
            for (0..b.cols) |j| {
                var sum: f32 = 0;

                // Vectorizable inner loop
                for (0..a.cols) |k| {
                    sum += a.get(i, k) * b.get(k, j);
                }

                result.set(i, j, sum);
            }
        }

        return result;
    }

    /// Matrix addition: C = A + B
    fn add(a: *const Self, b: *const Self, allocator: Allocator) !Self {
        if (a.rows != b.rows or a.cols != b.cols) return error.DimensionMismatch;

        var result = try Self.init(allocator, a.rows, a.cols);

        // SIMD-friendly element-wise operation
        const len = a.data.len;
        var i: usize = 0;

        // Process in chunks for better SIMD utilization
        while (i + 4 <= len) : (i += 4) {
            const va: @Vector(4, f32) = a.data[i..][0..4].*;
            const vb: @Vector(4, f32) = b.data[i..][0..4].*;
            const vc = va + vb;
            result.data[i..][0..4].* = vc;
        }

        // Handle remaining elements
        while (i < len) : (i += 1) {
            result.data[i] = a.data[i] + b.data[i];
        }

        return result;
    }

    /// Matrix subtraction: C = A - B
    fn subtract(a: *const Self, b: *const Self, allocator: Allocator) !Self {
        if (a.rows != b.rows or a.cols != b.cols) return error.DimensionMismatch;

        var result = try Self.init(allocator, a.rows, a.cols);

        const len = a.data.len;
        var i: usize = 0;

        while (i + 4 <= len) : (i += 4) {
            const va: @Vector(4, f32) = a.data[i..][0..4].*;
            const vb: @Vector(4, f32) = b.data[i..][0..4].*;
            const vc = va - vb;
            result.data[i..][0..4].* = vc;
        }

        while (i < len) : (i += 1) {
            result.data[i] = a.data[i] - b.data[i];
        }

        return result;
    }

    /// Element-wise multiplication (Hadamard product)
    fn hadamard(a: *const Self, b: *const Self, allocator: Allocator) !Self {
        if (a.rows != b.rows or a.cols != b.cols) return error.DimensionMismatch;

        var result = try Self.init(allocator, a.rows, a.cols);

        const len = a.data.len;
        var i: usize = 0;

        while (i + 4 <= len) : (i += 4) {
            const va: @Vector(4, f32) = a.data[i..][0..4].*;
            const vb: @Vector(4, f32) = b.data[i..][0..4].*;
            const vc = va * vb;
            result.data[i..][0..4].* = vc;
        }

        while (i < len) : (i += 1) {
            result.data[i] = a.data[i] * b.data[i];
        }

        return result;
    }

    /// Transpose matrix
    fn transpose(self: *const Self, allocator: Allocator) !Self {
        var result = try Self.init(allocator, self.cols, self.rows);

        for (0..self.rows) |i| {
            for (0..self.cols) |j| {
                result.set(j, i, self.get(i, j));
            }
        }

        return result;
    }

    /// Scale matrix by scalar
    fn scale(self: *Self, scalar: f32) void {
        const len = self.data.len;
        var i: usize = 0;

        const scalar_vec: @Vector(4, f32) = @splat(scalar);

        while (i + 4 <= len) : (i += 4) {
            const v: @Vector(4, f32) = self.data[i..][0..4].*;
            const scaled = v * scalar_vec;
            self.data[i..][0..4].* = scaled;
        }

        while (i < len) : (i += 1) {
            self.data[i] *= scalar;
        }
    }
};

/// Activation functions
const Activation = enum {
    sigmoid,
    relu,
    tanh,
    softmax,

    fn apply(self: Activation, x: *Matrix) void {
        switch (self) {
            .sigmoid => {
                for (x.data) |*val| {
                    val.* = 1.0 / (1.0 + @exp(-val.*));
                }
            },
            .relu => {
                for (x.data) |*val| {
                    val.* = @max(0, val.*);
                }
            },
            .tanh => {
                for (x.data) |*val| {
                    val.* = @tanh(val.*);
                }
            },
            .softmax => {
                // Apply softmax per row
                for (0..x.rows) |i| {
                    var max_val: f32 = -std.math.inf(f32);
                    for (0..x.cols) |j| {
                        max_val = @max(max_val, x.get(i, j));
                    }

                    var sum: f32 = 0;
                    for (0..x.cols) |j| {
                        const exp_val = @exp(x.get(i, j) - max_val);
                        x.set(i, j, exp_val);
                        sum += exp_val;
                    }

                    for (0..x.cols) |j| {
                        x.set(i, j, x.get(i, j) / sum);
                    }
                }
            },
        }
    }

    fn derivative(self: Activation, x: *const Matrix, allocator: Allocator) !Matrix {
        var result = try Matrix.init(allocator, x.rows, x.cols);

        switch (self) {
            .sigmoid => {
                for (x.data, result.data) |val, *deriv| {
                    const sigmoid_val = 1.0 / (1.0 + @exp(-val));
                    deriv.* = sigmoid_val * (1.0 - sigmoid_val);
                }
            },
            .relu => {
                for (x.data, result.data) |val, *deriv| {
                    deriv.* = if (val > 0) 1.0 else 0.0;
                }
            },
            .tanh => {
                for (x.data, result.data) |val, *deriv| {
                    const tanh_val = @tanh(val);
                    deriv.* = 1.0 - tanh_val * tanh_val;
                }
            },
            .softmax => {
                // Simplified: return ones (softmax derivative is complex)
                @memset(result.data, 1.0);
            },
        }

        return result;
    }
};

/// Dense neural network layer
const DenseLayer = struct {
    weights: Matrix,
    bias: Matrix,
    activation: Activation,

    // Cache for backpropagation
    input: ?Matrix,
    z: ?Matrix,
    output: ?Matrix,

    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator, input_size: usize, output_size: usize, activation: Activation, random: Random) !Self {
        var weights = try Matrix.init(allocator, input_size, output_size);
        weights.randomInit(random);

        var bias = try Matrix.init(allocator, 1, output_size);
        bias.randomInit(random);

        return .{
            .weights = weights,
            .bias = bias,
            .activation = activation,
            .input = null,
            .z = null,
            .output = null,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Self) void {
        self.weights.deinit();
        self.bias.deinit();
        if (self.input) |*inp| inp.deinit();
        if (self.z) |*z_val| z_val.deinit();
        if (self.output) |*out| out.deinit();
    }

    /// Forward pass
    fn forward(self: *Self, input: *const Matrix) !Matrix {
        // Store input for backpropagation
        if (self.input) |*old_input| old_input.deinit();
        self.input = try input.clone();

        // Z = X * W + b
        var z = try Matrix.matmul(input, &self.weights, self.allocator);
        errdefer z.deinit();

        // Add bias to each row
        for (0..z.rows) |i| {
            for (0..z.cols) |j| {
                const val = z.get(i, j) + self.bias.get(0, j);
                z.set(i, j, val);
            }
        }

        if (self.z) |*old_z| old_z.deinit();
        self.z = try z.clone();

        // Apply activation
        var output = try z.clone();
        self.activation.apply(&output);

        if (self.output) |*old_output| old_output.deinit();
        self.output = try output.clone();

        return output;
    }

    /// Backward pass
    fn backward(self: *Self, grad_output: *const Matrix, learning_rate: f32) !Matrix {
        // Compute gradient with respect to activation
        const z_val = self.z orelse return error.NoForwardPass;
        const input_val = self.input orelse return error.NoForwardPass;

        var activation_grad = try self.activation.derivative(&z_val, self.allocator);
        defer activation_grad.deinit();

        var delta = try Matrix.hadamard(grad_output, &activation_grad, self.allocator);
        defer delta.deinit();

        // Gradient with respect to weights: dW = X^T * delta
        var input_t = try input_val.transpose(self.allocator);
        defer input_t.deinit();

        var grad_weights = try Matrix.matmul(&input_t, &delta, self.allocator);
        defer grad_weights.deinit();

        // Gradient with respect to bias: db = sum(delta, axis=0)
        var grad_bias = try Matrix.init(self.allocator, 1, self.bias.cols);
        defer grad_bias.deinit();

        for (0..delta.cols) |j| {
            var sum: f32 = 0;
            for (0..delta.rows) |i| {
                sum += delta.get(i, j);
            }
            grad_bias.set(0, j, sum);
        }

        // Update weights and bias
        grad_weights.scale(learning_rate);
        grad_bias.scale(learning_rate);

        var weights_update = try Matrix.subtract(&self.weights, &grad_weights, self.allocator);
        defer self.weights.deinit();
        self.weights = weights_update;

        var bias_update = try Matrix.subtract(&self.bias, &grad_bias, self.allocator);
        defer self.bias.deinit();
        self.bias = bias_update;

        // Gradient with respect to input: dX = delta * W^T
        var weights_t = try self.weights.transpose(self.allocator);
        defer weights_t.deinit();

        return try Matrix.matmul(&delta, &weights_t, self.allocator);
    }
};

/// Neural network model
const NeuralNetwork = struct {
    layers: ArrayList(DenseLayer),
    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator) Self {
        return .{
            .layers = ArrayList(DenseLayer).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Self) void {
        for (self.layers.items) |*layer| {
            layer.deinit();
        }
        self.layers.deinit();
    }

    fn addLayer(self: *Self, input_size: usize, output_size: usize, activation: Activation, random: Random) !void {
        const layer = try DenseLayer.init(self.allocator, input_size, output_size, activation, random);
        try self.layers.append(layer);
    }

    fn forward(self: *Self, input: *const Matrix) !Matrix {
        var current = try input.clone();

        for (self.layers.items) |*layer| {
            const next = try layer.forward(&current);
            current.deinit();
            current = next;
        }

        return current;
    }

    fn backward(self: *Self, grad_output: *Matrix, learning_rate: f32) !void {
        var current_grad = try grad_output.clone();

        var i = self.layers.items.len;
        while (i > 0) {
            i -= 1;
            const next_grad = try self.layers.items[i].backward(&current_grad, learning_rate);
            current_grad.deinit();
            current_grad = next_grad;
        }

        current_grad.deinit();
    }

    fn train(self: *Self, x_train: *const Matrix, y_train: *const Matrix, epochs: usize, learning_rate: f32) !void {
        for (0..epochs) |epoch| {
            // Forward pass
            var predictions = try self.forward(x_train);
            defer predictions.deinit();

            // Compute loss (MSE)
            var loss: f32 = 0;
            for (0..predictions.rows) |i| {
                for (0..predictions.cols) |j| {
                    const diff = predictions.get(i, j) - y_train.get(i, j);
                    loss += diff * diff;
                }
            }
            loss /= @as(f32, @floatFromInt(predictions.rows * predictions.cols));

            // Compute gradient of loss
            var grad = try Matrix.subtract(&predictions, y_train, self.allocator);
            defer grad.deinit();

            const scale_factor = 2.0 / @as(f32, @floatFromInt(predictions.rows * predictions.cols));
            grad.scale(scale_factor);

            // Backward pass
            try self.backward(&grad, learning_rate);

            if (epoch % 100 == 0) {
                std.debug.print("Epoch {}: Loss = {d:.6}\n", .{ epoch, loss });
            }
        }
    }
};

/// Linear regression model
fn trainLinearRegression(allocator: Allocator) !void {
    std.debug.print("\n=== Linear Regression ===\n", .{});

    var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    // Generate synthetic data: y = 2x + 1 + noise
    const n_samples = 100;
    var x_data = try Matrix.init(allocator, n_samples, 1);
    defer x_data.deinit();

    var y_data = try Matrix.init(allocator, n_samples, 1);
    defer y_data.deinit();

    for (0..n_samples) |i| {
        const x = random.float(f32) * 10.0;
        const y = 2.0 * x + 1.0 + (random.float(f32) - 0.5) * 2.0;
        x_data.set(i, 0, x);
        y_data.set(i, 0, y);
    }

    // Create and train model
    var model = NeuralNetwork.init(allocator);
    defer model.deinit();

    try model.addLayer(1, 1, .relu, random);

    std.debug.print("Training linear regression model...\n", .{});
    try model.train(&x_data, &y_data, 500, 0.001);

    // Test prediction
    var test_x = try Matrix.init(allocator, 1, 1);
    defer test_x.deinit();
    test_x.set(0, 0, 5.0);

    var prediction = try model.forward(&test_x);
    defer prediction.deinit();

    std.debug.print("Prediction for x=5.0: {d:.2} (expected ~11.0)\n", .{prediction.get(0, 0)});
}

/// Binary classification with logistic regression
fn trainLogisticRegression(allocator: Allocator) !void {
    std.debug.print("\n=== Logistic Regression (Binary Classification) ===\n", .{});

    var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    // Generate synthetic data: two classes
    const n_samples = 200;
    var x_data = try Matrix.init(allocator, n_samples, 2);
    defer x_data.deinit();

    var y_data = try Matrix.init(allocator, n_samples, 1);
    defer y_data.deinit();

    for (0..n_samples) |i| {
        if (i < n_samples / 2) {
            // Class 0
            x_data.set(i, 0, random.float(f32) * 2.0);
            x_data.set(i, 1, random.float(f32) * 2.0);
            y_data.set(i, 0, 0.0);
        } else {
            // Class 1
            x_data.set(i, 0, 3.0 + random.float(f32) * 2.0);
            x_data.set(i, 1, 3.0 + random.float(f32) * 2.0);
            y_data.set(i, 0, 1.0);
        }
    }

    // Create and train model
    var model = NeuralNetwork.init(allocator);
    defer model.deinit();

    try model.addLayer(2, 1, .sigmoid, random);

    std.debug.print("Training logistic regression model...\n", .{});
    try model.train(&x_data, &y_data, 1000, 0.01);

    // Test predictions
    var test_cases = [_][2]f32{
        .{ 1.0, 1.0 }, // Should be class 0
        .{ 4.0, 4.0 }, // Should be class 1
    };

    for (test_cases) |test_case| {
        var test_x = try Matrix.init(allocator, 1, 2);
        defer test_x.deinit();
        test_x.set(0, 0, test_case[0]);
        test_x.set(0, 1, test_case[1]);

        var prediction = try model.forward(&test_x);
        defer prediction.deinit();

        std.debug.print("Prediction for ({d:.1}, {d:.1}): {d:.4}\n", .{ test_case[0], test_case[1], prediction.get(0, 0) });
    }
}

/// Multi-layer perceptron for XOR problem
fn trainXOR(allocator: Allocator) !void {
    std.debug.print("\n=== XOR Problem (Multi-layer Perceptron) ===\n", .{});

    var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    // XOR dataset
    var x_data = try Matrix.init(allocator, 4, 2);
    defer x_data.deinit();

    var y_data = try Matrix.init(allocator, 4, 1);
    defer y_data.deinit();

    const xor_data = [_][3]f32{
        .{ 0, 0, 0 },
        .{ 0, 1, 1 },
        .{ 1, 0, 1 },
        .{ 1, 1, 0 },
    };

    for (xor_data, 0..) |data, i| {
        x_data.set(i, 0, data[0]);
        x_data.set(i, 1, data[1]);
        y_data.set(i, 0, data[2]);
    }

    // Create multi-layer model
    var model = NeuralNetwork.init(allocator);
    defer model.deinit();

    try model.addLayer(2, 4, .tanh, random);
    try model.addLayer(4, 1, .sigmoid, random);

    std.debug.print("Training XOR model...\n", .{});
    try model.train(&x_data, &y_data, 2000, 0.1);

    // Test all cases
    std.debug.print("\nXOR Truth Table:\n", .{});
    for (xor_data) |data| {
        var test_x = try Matrix.init(allocator, 1, 2);
        defer test_x.deinit();
        test_x.set(0, 0, data[0]);
        test_x.set(0, 1, data[1]);

        var prediction = try model.forward(&test_x);
        defer prediction.deinit();

        std.debug.print("{d:.0} XOR {d:.0} = {d:.4} (expected {d:.0})\n", .{ data[0], data[1], prediction.get(0, 0), data[2] });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Machine Learning from Scratch ===\n", .{});

    try trainLinearRegression(allocator);
    try trainLogisticRegression(allocator);
    try trainXOR(allocator);

    std.debug.print("\n=== ML Features Demonstrated ===\n", .{});
    std.debug.print("✓ SIMD-optimized matrix operations\n", .{});
    std.debug.print("✓ Forward and backward propagation\n", .{});
    std.debug.print("✓ Multiple activation functions\n", .{});
    std.debug.print("✓ Gradient descent optimization\n", .{});
    std.debug.print("✓ Linear and logistic regression\n", .{});
    std.debug.print("✓ Multi-layer perceptron (XOR)\n", .{});
    std.debug.print("✓ Manual memory management\n", .{});
}
