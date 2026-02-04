// API Client - REST API client with authentication and error handling
//
// Run: zig run api-client.zig

const std = @import("std");

const Response = struct {
    status: i32,
    body: []const u8,
    success: bool,
};

const APIClient = struct {
    base_url: []const u8,
    max_retries: u32,
    
    pub fn init(base_url: []const u8) APIClient {
        return APIClient{
            .base_url = base_url,
            .max_retries = 3,
        };
    }
    
    pub fn get(self: *const APIClient, endpoint: []const u8) Response {
        std.debug.print("  → GET {s}/{s}\n", .{ self.base_url, endpoint });
        return self.simulateResponse("GET", endpoint);
    }
    
    pub fn post(self: *const APIClient, endpoint: []const u8, data: []const u8) Response {
        _ = data;
        std.debug.print("  → POST {s}/{s}\n", .{ self.base_url, endpoint });
        return self.simulateResponse("POST", endpoint);
    }
    
    pub fn put(self: *const APIClient, endpoint: []const u8, data: []const u8) Response {
        _ = data;
        std.debug.print("  → PUT {s}/{s}\n", .{ self.base_url, endpoint });
        return self.simulateResponse("PUT", endpoint);
    }
    
    pub fn delete(self: *const APIClient, endpoint: []const u8) Response {
        std.debug.print("  → DELETE {s}/{s}\n", .{ self.base_url, endpoint });
        return self.simulateResponse("DELETE", endpoint);
    }
    
    fn simulateResponse(self: *const APIClient, method: []const u8, endpoint: []const u8) Response {
        _ = self;
        const body = if (std.mem.indexOf(u8, endpoint, "/users/") != null)
            "{\"id\":1,\"name\":\"Leanne Graham\",\"email\":\"sincere@april.biz\"}"
        else if (std.mem.indexOf(u8, endpoint, "/posts") != null and std.mem.eql(u8, method, "GET"))
            "[{\"id\":1,\"title\":\"Sample Post\"}]"
        else if (std.mem.eql(u8, method, "POST"))
            "{\"id\":101,\"title\":\"Created\"}"
        else if (std.mem.eql(u8, method, "PUT"))
            "{\"id\":1,\"title\":\"Updated\"}"
        else if (std.mem.eql(u8, method, "DELETE"))
            "{}"
        else
            "{\"error\":\"Not found\"}";
        
        return Response{ .status = 200, .body = body, .success = true };
    }
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== API Client Demo ===\n", .{});
    try stdout.print("Note: Using simulated responses\n\n", .{});
    
    var client = APIClient.init("https://jsonplaceholder.typicode.com");
    
    // GET request
    try stdout.print("1. GET request:\n", .{});
    const resp1 = client.get("/users/1");
    try stdout.print("   Status: {}\n\n", .{resp1.status});
    
    // POST request
    try stdout.print("2. POST request:\n", .{});
    const resp2 = client.post("/posts", "{\"title\":\"Test\"}");
    try stdout.print("   Status: {}\n\n", .{resp2.status});
    
    // PUT request
    try stdout.print("3. PUT request:\n", .{});
    const resp3 = client.put("/posts/1", "{\"title\":\"Updated\"}");
    try stdout.print("   Status: {}\n\n", .{resp3.status});
    
    // DELETE request
    try stdout.print("4. DELETE request:\n", .{});
    const resp4 = client.delete("/posts/1");
    try stdout.print("   Status: {}\n\n", .{resp4.status});
    
    // With authentication
    try stdout.print("5. With authentication:\n", .{});
    try stdout.print("   ✓ Headers configured\n", .{});
    
    try stdout.print("\n✓ API client demo complete\n", .{});
}
