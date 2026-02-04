//! Mini HTTP Web Framework with routing and middleware
//! Build: zig build-exe web_framework.zig
//! Run: ./web_framework
//! Test: curl http://localhost:3000/ or curl -X POST http://localhost:3000/api/users -d '{"name":"Alice"}'

const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

/// HTTP Methods
const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,

    fn fromString(s: []const u8) ?Method {
        if (std.mem.eql(u8, s, "GET")) return .GET;
        if (std.mem.eql(u8, s, "POST")) return .POST;
        if (std.mem.eql(u8, s, "PUT")) return .PUT;
        if (std.mem.eql(u8, s, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, s, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, s, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, s, "OPTIONS")) return .OPTIONS;
        return null;
    }
};

/// HTTP Request
const Request = struct {
    method: Method,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    params: std.StringHashMap([]const u8),
    allocator: Allocator,

    fn init(allocator: Allocator) Request {
        return .{
            .method = .GET,
            .path = "/",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .params = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Request) void {
        self.headers.deinit();
        self.params.deinit();
    }

    fn parse(allocator: Allocator, raw_request: []const u8) !Request {
        var req = Request.init(allocator);
        errdefer req.deinit();

        var lines = std.mem.splitScalar(u8, raw_request, '\n');
        
        // Parse request line
        if (lines.next()) |line| {
            var parts = std.mem.splitScalar(u8, line, ' ');
            
            const method_str = std.mem.trimRight(u8, parts.next() orelse return error.InvalidRequest, "\r");
            req.method = Method.fromString(method_str) orelse .GET;
            
            const path = std.mem.trimRight(u8, parts.next() orelse return error.InvalidRequest, "\r");
            req.path = path;
        }

        // Parse headers
        while (lines.next()) |line| {
            const trimmed = std.mem.trimRight(u8, line, "\r");
            if (trimmed.len == 0) break;

            if (std.mem.indexOf(u8, trimmed, ": ")) |colon_pos| {
                const key = trimmed[0..colon_pos];
                const value = trimmed[colon_pos + 2 ..];
                try req.headers.put(key, value);
            }
        }

        // Body is everything after headers
        if (lines.rest().len > 0) {
            req.body = lines.rest();
        }

        return req;
    }
};

/// HTTP Response
const Response = struct {
    status: u16 = 200,
    status_text: []const u8 = "OK",
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8),
    allocator: Allocator,

    fn init(allocator: Allocator) Response {
        return .{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Response) void {
        self.headers.deinit();
        self.body.deinit();
    }

    fn setStatus(self: *Response, status: u16) void {
        self.status = status;
        self.status_text = switch (status) {
            200 => "OK",
            201 => "Created",
            204 => "No Content",
            400 => "Bad Request",
            404 => "Not Found",
            405 => "Method Not Allowed",
            500 => "Internal Server Error",
            else => "Unknown",
        };
    }

    fn setHeader(self: *Response, key: []const u8, value: []const u8) !void {
        try self.headers.put(key, value);
    }

    fn json(self: *Response, data: []const u8) !void {
        try self.setHeader("Content-Type", "application/json");
        try self.body.appendSlice(data);
    }

    fn text(self: *Response, data: []const u8) !void {
        try self.setHeader("Content-Type", "text/plain");
        try self.body.appendSlice(data);
    }

    fn html(self: *Response, data: []const u8) !void {
        try self.setHeader("Content-Type", "text/html");
        try self.body.appendSlice(data);
    }

    fn build(self: *Response) ![]const u8 {
        var response = std.ArrayList(u8).init(self.allocator);
        errdefer response.deinit();

        // Status line
        try response.writer().print("HTTP/1.1 {} {s}\r\n", .{ self.status, self.status_text });

        // Headers
        try response.writer().print("Content-Length: {}\r\n", .{self.body.items.len});
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try response.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Empty line and body
        try response.appendSlice("\r\n");
        try response.appendSlice(self.body.items);

        return response.toOwnedSlice();
    }
};

/// Handler function type
const Handler = *const fn (ctx: *Context) anyerror!void;

/// Middleware function type
const Middleware = *const fn (ctx: *Context, next: Handler) anyerror!void;

/// Request context
const Context = struct {
    request: *Request,
    response: *Response,
    allocator: Allocator,
};

/// Route definition
const Route = struct {
    method: Method,
    path: []const u8,
    handler: Handler,
};

/// Router
const Router = struct {
    routes: std.ArrayList(Route),
    middlewares: std.ArrayList(Middleware),
    allocator: Allocator,

    fn init(allocator: Allocator) Router {
        return .{
            .routes = std.ArrayList(Route).init(allocator),
            .middlewares = std.ArrayList(Middleware).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Router) void {
        self.routes.deinit();
        self.middlewares.deinit();
    }

    fn use(self: *Router, middleware: Middleware) !void {
        try self.middlewares.append(middleware);
    }

    fn get(self: *Router, path: []const u8, handler: Handler) !void {
        try self.addRoute(.GET, path, handler);
    }

    fn post(self: *Router, path: []const u8, handler: Handler) !void {
        try self.addRoute(.POST, path, handler);
    }

    fn put(self: *Router, path: []const u8, handler: Handler) !void {
        try self.addRoute(.PUT, path, handler);
    }

    fn delete(self: *Router, path: []const u8, handler: Handler) !void {
        try self.addRoute(.DELETE, path, handler);
    }

    fn addRoute(self: *Router, method: Method, path: []const u8, handler: Handler) !void {
        try self.routes.append(.{
            .method = method,
            .path = path,
            .handler = handler,
        });
    }

    fn findRoute(self: *Router, method: Method, path: []const u8) ?Route {
        for (self.routes.items) |route| {
            if (route.method == method and std.mem.eql(u8, route.path, path)) {
                return route;
            }
        }
        return null;
    }

    fn handle(self: *Router, ctx: *Context) !void {
        const route = self.findRoute(ctx.request.method, ctx.request.path);
        
        if (route) |r| {
            // Execute middleware chain
            if (self.middlewares.items.len > 0) {
                try self.executeMiddleware(ctx, 0, r.handler);
            } else {
                try r.handler(ctx);
            }
        } else {
            ctx.response.setStatus(404);
            try ctx.response.json("{\"error\": \"Not found\"}");
        }
    }

    fn executeMiddleware(self: *Router, ctx: *Context, index: usize, final_handler: Handler) !void {
        if (index >= self.middlewares.items.len) {
            try final_handler(ctx);
            return;
        }

        const middleware = self.middlewares.items[index];
        const next = struct {
            fn next_handler(c: *Context) !void {
                // This is a bit hacky but demonstrates the concept
                _ = c;
            }
        }.next_handler;

        try middleware(ctx, next);
        try self.executeMiddleware(ctx, index + 1, final_handler);
    }
};

/// Web Application
const App = struct {
    allocator: Allocator,
    router: Router,
    port: u16,

    fn init(allocator: Allocator, port: u16) App {
        return .{
            .allocator = allocator,
            .router = Router.init(allocator),
            .port = port,
        };
    }

    fn deinit(self: *App) void {
        self.router.deinit();
    }

    fn listen(self: *App) !void {
        const address = try net.Address.parseIp("0.0.0.0", self.port);
        var listener = try address.listen(.{ .reuse_address = true });
        defer listener.deinit();

        std.log.info("Server listening on http://localhost:{}", .{self.port});

        while (true) {
            const conn = try listener.accept();
            self.handleConnection(conn) catch |err| {
                std.log.err("Error handling connection: {}", .{err});
            };
        }
    }

    fn handleConnection(self: *App, conn: net.Server.Connection) !void {
        defer conn.stream.close();

        var buffer: [8192]u8 = undefined;
        const bytes_read = try conn.stream.read(&buffer);
        if (bytes_read == 0) return;

        const raw_request = buffer[0..bytes_read];

        var request = try Request.parse(self.allocator, raw_request);
        defer request.deinit();

        var response = Response.init(self.allocator);
        defer response.deinit();

        var ctx = Context{
            .request = &request,
            .response = &response,
            .allocator = self.allocator,
        };

        try self.router.handle(&ctx);

        const response_data = try response.build();
        defer self.allocator.free(response_data);

        _ = try conn.stream.writeAll(response_data);
    }
};

// ============================================================================
// Example handlers and middleware
// ============================================================================

fn loggerMiddleware(ctx: *Context, next: Handler) !void {
    std.log.info("{s} {s}", .{ @tagName(ctx.request.method), ctx.request.path });
    try next(ctx);
}

fn corsMiddleware(ctx: *Context, next: Handler) !void {
    try ctx.response.setHeader("Access-Control-Allow-Origin", "*");
    try next(ctx);
}

fn homeHandler(ctx: *Context) !void {
    try ctx.response.html(
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Zig Web Framework</title></head>
        \\<body>
        \\<h1>Welcome to Zig Web Framework!</h1>
        \\<p>Try these endpoints:</p>
        \\<ul>
        \\  <li>GET /</li>
        \\  <li>GET /api/users</li>
        \\  <li>POST /api/users</li>
        \\  <li>GET /api/health</li>
        \\</ul>
        \\</body>
        \\</html>
    );
}

fn usersGetHandler(ctx: *Context) !void {
    try ctx.response.json(
        \\{"users": [
        \\  {"id": 1, "name": "Alice"},
        \\  {"id": 2, "name": "Bob"}
        \\]}
    );
}

fn usersPostHandler(ctx: *Context) !void {
    ctx.response.setStatus(201);
    const response_json = try std.fmt.allocPrint(
        ctx.allocator,
        "{{\"message\": \"User created\", \"body\": \"{s}\"}}",
        .{ctx.request.body}
    );
    defer ctx.allocator.free(response_json);
    try ctx.response.json(response_json);
}

fn healthHandler(ctx: *Context) !void {
    try ctx.response.json("{\"status\": \"healthy\", \"timestamp\": \"2024-01-01T00:00:00Z\"}");
}

fn notFoundHandler(ctx: *Context) !void {
    ctx.response.setStatus(404);
    try ctx.response.json("{\"error\": \"Endpoint not found\"}");
}

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, 3000);
    defer app.deinit();

    // Register middleware
    try app.router.use(loggerMiddleware);
    try app.router.use(corsMiddleware);

    // Register routes
    try app.router.get("/", homeHandler);
    try app.router.get("/api/users", usersGetHandler);
    try app.router.post("/api/users", usersPostHandler);
    try app.router.get("/api/health", healthHandler);

    std.debug.print("Starting web framework demo...\n", .{});
    std.debug.print("Visit: http://localhost:3000/\n", .{});
    std.debug.print("Press Ctrl+C to stop\n\n", .{});

    try app.listen();
}
