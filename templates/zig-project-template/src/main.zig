const std = @import("std");

pub fn greet(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "Hello, {s}!", .{name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Zig Project Template\n", .{});
    
    const greeting = try greet(allocator, "World");
    defer allocator.free(greeting);
    
    try stdout.print("{s}\n", .{greeting});
}
