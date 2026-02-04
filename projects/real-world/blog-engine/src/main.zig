const std = @import("std");
const net = std.net;
const ArrayList = std.ArrayList;

const User = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    role: []const u8,
};

const Post = struct {
    id: u32,
    title: []const u8,
    slug: []const u8,
    content: []const u8,
    published: bool,
    author_id: u32,
};

const Comment = struct {
    id: u32,
    content: []const u8,
    post_id: u32,
    author_name: []const u8,
};

const BlogEngine = struct {
    allocator: std.mem.Allocator,
    posts: ArrayList(Post),
    users: ArrayList(User),
    comments: ArrayList(Comment),
    
    pub fn init(allocator: std.mem.Allocator) BlogEngine {
        return .{
            .allocator = allocator,
            .posts = ArrayList(Post).init(allocator),
            .users = ArrayList(User).init(allocator),
            .comments = ArrayList(Comment).init(allocator),
        };
    }
    
    pub fn deinit(self: *BlogEngine) void {
        self.posts.deinit();
        self.users.deinit();
        self.comments.deinit();
    }
    
    pub fn createPost(self: *BlogEngine, title: []const u8, content: []const u8, author_id: u32) !void {
        const slug = try self.generateSlug(title);
        const post = Post{
            .id = @intCast(self.posts.items.len + 1),
            .title = title,
            .slug = slug,
            .content = content,
            .published = true,
            .author_id = author_id,
        };
        try self.posts.append(post);
    }
    
    fn generateSlug(self: *BlogEngine, title: []const u8) ![]const u8 {
        _ = self;
        return title; // Simplified
    }
};

fn handleRequest(stream: net.Stream, blog: *BlogEngine) !void {
    var buffer: [4096]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    
    if (bytes_read == 0) return;
    
    const request = buffer[0..bytes_read];
    
    // Parse HTTP method and path
    var lines = std.mem.split(u8, request, "\r\n");
    const first_line = lines.next() orelse return;
    
    var parts = std.mem.split(u8, first_line, " ");
    const method = parts.next() orelse return;
    const path = parts.next() orelse return;
    
    _ = method;
    
    if (std.mem.eql(u8, path, "/")) {
        const html =
            \\HTTP/1.1 200 OK
            \\Content-Type: text/html
            \\
            \\<!DOCTYPE html>
            \\<html>
            \\<head><title>Zig Blog Engine</title>
            \\<style>body{font-family:Arial;max-width:800px;margin:0 auto;padding:20px;}h1{color:#f7a41d;}</style>
            \\</head>
            \\<body>
            \\<h1>⚡ Zig Blog Engine</h1>
            \\<p>High-performance blogging with Zig</p>
            \\<h2>Features</h2>
            \\<ul>
            \\<li>Zero-cost abstractions</li>
            \\<li>Compile-time guarantees</li>
            \\<li>Manual memory management</li>
            \\<li>No hidden allocations</li>
            \\<li>Explicit error handling</li>
            \\</ul>
            \\<h2>API Endpoints</h2>
            \\<ul>
            \\<li>GET /api/posts - List posts</li>
            \\<li>POST /api/posts - Create post</li>
            \\<li>GET /api/posts/:id - View post</li>
            \\</ul>
            \\</body>
            \\</html>
        ;
        try stream.writeAll(html);
    } else if (std.mem.eql(u8, path, "/api/posts")) {
        const json = try std.fmt.allocPrint(blog.allocator, 
            \\HTTP/1.1 200 OK
            \\Content-Type: application/json
            \\
            \\{{"posts":[{{"id":1,"title":"Welcome to Zig","content":"Fast and safe!"}}]}}
        , .{});
        defer blog.allocator.free(json);
        try stream.writeAll(json);
    } else {
        const response =
            \\HTTP/1.1 404 Not Found
            \\Content-Type: text/plain
            \\
            \\Not Found
        ;
        try stream.writeAll(response);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var blog = BlogEngine.init(allocator);
    defer blog.deinit();
    
    // Seed data
    try blog.createPost("Welcome to Zig", "# Fast and Safe\n\nZig is awesome!", 1);
    try blog.createPost("Performance Matters", "Zig gives you control", 1);
    
    const address = try net.Address.parseIp("127.0.0.1", 4000);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    
    std.debug.print("⚡ Zig Blog Engine running on http://localhost:4000\n", .{});
    
    while (true) {
        const connection = try listener.accept();
        defer connection.stream.close();
        
        handleRequest(connection.stream, &blog) catch |err| {
            std.debug.print("Error handling request: {}\n", .{err});
        };
    }
}
