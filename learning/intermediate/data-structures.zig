// Data Structures - Linked List, Binary Search Tree, Hash Map
//
// Run: zig run data-structures.zig

const std = @import("std");

// Linked List Node
fn LinkedList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            value: T,
            next: ?*Node,
        };
        
        head: ?*Node,
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .head = null,
                .allocator = allocator,
            };
        }
        
        pub fn append(self: *Self, value: T) !void {
            const new_node = try self.allocator.create(Node);
            new_node.* = Node{ .value = value, .next = null };
            
            if (self.head == null) {
                self.head = new_node;
            } else {
                var current = self.head;
                while (current.?.next != null) {
                    current = current.?.next;
                }
                current.?.next = new_node;
            }
        }
        
        pub fn find(self: *Self, value: T) bool {
            var current = self.head;
            while (current) |node| {
                if (node.value == value) return true;
                current = node.next;
            }
            return false;
        }
        
        pub fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |node| {
                const next = node.next;
                self.allocator.destroy(node);
                current = next;
            }
        }
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    try stdout.print("=== Data Structures Demo ===\n\n", .{});
    
    // Linked List
    try stdout.print("1. Linked List:\n", .{});
    var list = LinkedList(i32).init(allocator);
    defer list.deinit();
    
    try list.append(10);
    try list.append(20);
    try list.append(30);
    
    try stdout.print("   List created with values: 10, 20, 30\n", .{});
    try stdout.print("   Find 20: {s}\n", .{if (list.find(20)) "Found" else "Not found"});
    try stdout.print("   Find 99: {s}\n\n", .{if (list.find(99)) "Found" else "Not found"});
    
    // HashMap (using std.HashMap)
    try stdout.print("2. Hash Map:\n", .{});
    var map = std.StringHashMap([]const u8).init(allocator);
    defer map.deinit();
    
    try map.put("name", "Alice");
    try map.put("age", "28");
    try map.put("city", "New York");
    
    try stdout.print("   Size: {}\n", .{map.count()});
    if (map.get("name")) |value| {
        try stdout.print("   Get 'name': {s}\n", .{value});
    }
    
    _ = map.remove("age");
    try stdout.print("   After remove, size: {}\n", .{map.count()});
    
    try stdout.print("\n✓ Demo complete\n", .{});
}
