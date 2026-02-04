// CLI Calculator - Perform basic arithmetic operations
// Compile: zig build-exe cli-calculator.zig
// Run: ./cli-calculator or zig run cli-calculator.zig

const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    
    var buf: [100]u8 = undefined;
    
    try stdout.print("=== CLI Calculator ===\n", .{});
    try stdout.print("Operations: +, -, *, /\n", .{});
    
    try stdout.print("Enter first number: ", .{});
    const num1_str = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse return;
    const num1 = std.fmt.parseFloat(f64, std.mem.trim(u8, num1_str, &std.ascii.whitespace)) catch {
        try stdout.print("Error: Invalid number input\n", .{});
        return;
    };
    
    try stdout.print("Enter operator (+, -, *, /): ", .{});
    const operator_str = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse return;
    const operator = std.mem.trim(u8, operator_str, &std.ascii.whitespace);
    
    try stdout.print("Enter second number: ", .{});
    const num2_str = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse return;
    const num2 = std.fmt.parseFloat(f64, std.mem.trim(u8, num2_str, &std.ascii.whitespace)) catch {
        try stdout.print("Error: Invalid number input\n", .{});
        return;
    };
    
    var result: f64 = 0;
    
    if (std.mem.eql(u8, operator, "+")) {
        result = num1 + num2;
    } else if (std.mem.eql(u8, operator, "-")) {
        result = num1 - num2;
    } else if (std.mem.eql(u8, operator, "*")) {
        result = num1 * num2;
    } else if (std.mem.eql(u8, operator, "/")) {
        if (num2 == 0) {
            try stdout.print("Error: Cannot divide by zero\n", .{});
            return;
        }
        result = num1 / num2;
    } else {
        try stdout.print("Error: Invalid operator\n", .{});
        return;
    }
    
    try stdout.print("Result: {d} {s} {d} = {d}\n", .{ num1, operator, num2, result });
}
