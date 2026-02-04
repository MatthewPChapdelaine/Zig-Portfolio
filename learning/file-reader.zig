// File Reader - Read and display file contents
// Compile: zig build-exe file-reader.zig
// Run: ./file-reader <filename> or zig run file-reader.zig -- <filename>

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len != 2) {
        try stdout.print("Usage: {s} <filename>\n", .{args[0]});
        return;
    }
    
    const filename = args[1];
    
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try stdout.print("Error: File '{s}' not found\n", .{filename});
                return;
            },
            error.AccessDenied => {
                try stdout.print("Error: Permission denied to read '{s}'\n", .{filename});
                return;
            },
            else => {
                try stdout.print("Error reading file: {}\n", .{err});
                return;
            },
        }
    };
    defer file.close();
    
    const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(contents);
    
    try stdout.print("=== Contents of {s} ===\n", .{filename});
    try stdout.print("{s}", .{contents});
    try stdout.print("\n=== End of file ({d} characters) ===\n", .{contents.len});
}
