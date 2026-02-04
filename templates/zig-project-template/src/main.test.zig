const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");

test "greet returns greeting for Alice" {
    const allocator = testing.allocator;
    const result = try main.greet(allocator, "Alice");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Hello, Alice!", result);
}

test "greet returns greeting for Bob" {
    const allocator = testing.allocator;
    const result = try main.greet(allocator, "Bob");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Hello, Bob!", result);
}

test "greet with empty string" {
    const allocator = testing.allocator;
    const result = try main.greet(allocator, "");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Hello, !", result);
}
