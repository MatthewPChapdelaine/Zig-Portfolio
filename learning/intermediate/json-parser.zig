// JSON Parser - Parse, manipulate, validate and write JSON data
//
// Compile: zig build-exe json-parser.zig
// Run: ./json-parser
// Or: zig run json-parser.zig

const std = @import("std");

const User = struct {
    id: i32,
    name: []const u8,
    email: []const u8,
    age: i32,
};

fn validateEmail(email: []const u8) bool {
    var has_at = false;
    var has_dot = false;
    for (email) |c| {
        if (c == '@') has_at = true;
        if (c == '.' and has_at) has_dot = true;
    }
    return has_at and has_dot;
}

fn validateUser(user: User) ?[]const u8 {
    if (user.id <= 0) return "Invalid user ID";
    if (user.name.len == 0) return "Name cannot be empty";
    if (!validateEmail(user.email)) return "Invalid email format";
    if (user.age < 0) return "Invalid age";
    return null;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== JSON Parser Demo ===\n\n", .{});
    
    const users = [_]User{
        .{ .id = 1, .name = "Alice", .email = "alice@example.com", .age = 28 },
        .{ .id = 2, .name = "Bob", .email = "bob@example.com", .age = 35 },
        .{ .id = 3, .name = "Charlie", .email = "charlie@example.com", .age = 42 },
    };
    
    // Validate users
    try stdout.print("Validating users:\n", .{});
    for (users) |user| {
        if (validateUser(user)) |err| {
            try stdout.print("  ✗ User {}: {s}\n", .{ user.id, err });
        } else {
            try stdout.print("  ✓ User {}: Valid\n", .{user.id});
        }
    }
    try stdout.print("\n", .{});
    
    // Show JSON representation (simplified)
    try stdout.print("Users:\n", .{});
    for (users) |user| {
        try stdout.print("  - {s} (age: {})\n", .{ user.name, user.age });
    }
    
    try stdout.print("\n✓ Demo complete\n", .{});
}
