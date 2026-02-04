// Sorting Algorithms - QuickSort, MergeSort, BubbleSort
//
// Run: zig run sorting-algorithms.zig

const std = @import("std");

fn bubbleSort(arr: []i32) void {
    const n = arr.len;
    var i: usize = 0;
    while (i < n - 1) : (i += 1) {
        var swapped = false;
        var j: usize = 0;
        while (j < n - i - 1) : (j += 1) {
            if (arr[j] > arr[j + 1]) {
                const temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
                swapped = true;
            }
        }
        if (!swapped) break;
    }
}

fn isSorted(arr: []const i32) bool {
    var i: usize = 0;
    while (i < arr.len - 1) : (i += 1) {
        if (arr[i] > arr[i + 1]) return false;
    }
    return true;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== Sorting Algorithms Demo ===\n\n", .{});
    
    // Small array test
    var small = [_]i32{ 64, 34, 25, 12, 22, 11, 90 };
    try stdout.print("1. Small Array Test:\n", .{});
    try stdout.print("   Original: ", .{});
    for (small) |val| {
        try stdout.print("{} ", .{val});
    }
    try stdout.print("\n", .{});
    
    bubbleSort(&small);
    try stdout.print("   BubbleSort: ", .{});
    for (small) |val| {
        try stdout.print("{} ", .{val});
    }
    try stdout.print("\n", .{});
    
    try stdout.print("   Is sorted: {s}\n", .{if (isSorted(&small)) "✓" else "✗"});
    
    try stdout.print("\n✓ Sorting demo complete\n", .{});
}
