// Hello World - Basic Zig Program
// Compile: zig build-exe hello-world.zig
// Run: ./hello-world

const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, World!\n", .{});
    try stdout.print("Welcome to Zig programming!\n", .{});
}
