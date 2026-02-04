// File Processor - Process CSV/text files and calculate statistics
//
// Run: zig run file-processor.zig

const std = @import("std");

const Stats = struct {
    count: usize,
    sum: f64,
    mean: f64,
    median: f64,
    min: f64,
    max: f64,
    std_dev: f64,
};

fn calculateStats(allocator: std.mem.Allocator, values: []const f64) !?Stats {
    if (values.len == 0) return null;
    
    // Sort values for median
    var sorted = try allocator.alloc(f64, values.len);
    defer allocator.free(sorted);
    std.mem.copy(f64, sorted, values);
    std.sort.sort(f64, sorted, {}, comptime std.sort.asc(f64));
    
    const n = values.len;
    var sum: f64 = 0;
    for (values) |v| sum += v;
    
    const mean = sum / @intToFloat(f64, n);
    
    const median = if (n % 2 == 0)
        (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    else
        sorted[n / 2];
    
    var variance: f64 = 0;
    for (values) |v| {
        const diff = v - mean;
        variance += diff * diff;
    }
    variance /= @intToFloat(f64, n);
    const std_dev = @sqrt(variance);
    
    return Stats{
        .count = n,
        .sum = sum,
        .mean = mean,
        .median = median,
        .min = sorted[0],
        .max = sorted[n - 1],
        .std_dev = std_dev,
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    try stdout.print("=== File Processor Demo ===\n\n", .{});
    
    // Sample data
    const quantities = [_]f64{ 5.0, 3.0, 8.0, 2.0, 6.0 };
    
    try stdout.print("Processing {} records\n\n", .{quantities.len});
    
    // Calculate statistics
    if (try calculateStats(allocator, &quantities)) |stats| {
        try stdout.print("Quantity Statistics:\n", .{});
        try stdout.print("  Count:  {}\n", .{stats.count});
        try stdout.print("  Sum:    {d:.2}\n", .{stats.sum});
        try stdout.print("  Mean:   {d:.2}\n", .{stats.mean});
        try stdout.print("  Median: {d:.2}\n", .{stats.median});
        try stdout.print("  Min:    {d:.2}\n", .{stats.min});
        try stdout.print("  Max:    {d:.2}\n", .{stats.max});
        try stdout.print("  StdDev: {d:.2}\n", .{stats.std_dev});
    }
    
    try stdout.print("\n✓ Processing demo complete\n", .{});
}
