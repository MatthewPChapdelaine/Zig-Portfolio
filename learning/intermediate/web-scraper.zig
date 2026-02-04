// Web Scraper - Make HTTP requests and parse HTML/JSON responses
//
// Run: zig run web-scraper.zig

const std = @import("std");

const Response = struct {
    status: i32,
    body: []const u8,
};

fn httpGet(url: []const u8) Response {
    std.debug.print("  → Making request to {s}\n", .{url});
    
    // Simulate response based on URL
    const body = if (std.mem.indexOf(u8, url, "jsonplaceholder") != null and 
                     std.mem.indexOf(u8, url, "/users/") != null)
        "{\"id\":1,\"name\":\"Leanne Graham\",\"email\":\"sincere@april.biz\"}"
    else if (std.mem.indexOf(u8, url, "jsonplaceholder") != null and
             std.mem.indexOf(u8, url, "/posts") != null)
        "[{\"id\":1,\"title\":\"Sample Post\",\"userId\":1}]"
    else if (std.mem.indexOf(u8, url, "example.com") != null)
        "<html><head><title>Example Domain</title></head><body><h1>Example</h1></body></html>"
    else
        "<html><body>Not found</body></html>";
    
    return Response{ .status = 200, .body = body };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== Web Scraper Demo ===\n", .{});
    try stdout.print("Note: Using simulated responses\n\n", .{});
    
    // Example 1: Fetch JSON
    try stdout.print("1. Fetching JSON from API:\n", .{});
    const resp1 = httpGet("https://jsonplaceholder.typicode.com/users/1");
    try stdout.print("   Status: {}\n", .{resp1.status});
    const preview = if (resp1.body.len > 50) resp1.body[0..50] else resp1.body;
    try stdout.print("   Body: {s}...\n\n", .{preview});
    
    // Example 2: Fetch HTML
    try stdout.print("2. Fetching HTML page:\n", .{});
    const resp2 = httpGet("https://example.com");
    try stdout.print("   Status: {}\n", .{resp2.status});
    
    try stdout.print("\n✓ Scraping demo complete\n", .{});
}
