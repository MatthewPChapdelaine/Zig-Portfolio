//! Multi-threaded TCP server with connection pooling and graceful shutdown
//! Build: zig build-exe multi_threaded_server.zig
//! Run: ./multi_threaded_server
//! Test: curl http://localhost:8080 or telnet localhost 8080

const std = @import("std");
const net = std.net;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Atomic = std.atomic.Value;

/// Server configuration
const Config = struct {
    port: u16 = 8080,
    max_connections: usize = 100,
    thread_pool_size: usize = 8,
    buffer_size: usize = 4096,
};

/// Connection state tracking
const ConnectionStats = struct {
    active: Atomic(u32),
    total: Atomic(u64),
    mutex: Mutex,

    fn init() ConnectionStats {
        return .{
            .active = Atomic(u32).init(0),
            .total = Atomic(u64).init(0),
            .mutex = .{},
        };
    }

    fn incrementActive(self: *ConnectionStats) void {
        _ = self.active.fetchAdd(1, .monotonic);
        _ = self.total.fetchAdd(1, .monotonic);
    }

    fn decrementActive(self: *ConnectionStats) void {
        _ = self.active.fetchSub(1, .monotonic);
    }

    fn getStats(self: *ConnectionStats) struct { active: u32, total: u64 } {
        return .{
            .active = self.active.load(.monotonic),
            .total = self.total.load(.monotonic),
        };
    }
};

/// Worker thread context
const Worker = struct {
    thread: Thread,
    server: *Server,
    id: usize,
    running: *Atomic(bool),

    fn run(self: *Worker) void {
        std.log.info("Worker {} started", .{self.id});
        
        while (self.running.load(.monotonic)) {
            if (self.server.acceptConnection()) |conn| {
                self.handleConnection(conn) catch |err| {
                    std.log.err("Worker {} error handling connection: {}", .{ self.id, err });
                };
            } else |err| {
                if (err != error.WouldBlock) {
                    std.log.err("Worker {} accept error: {}", .{ self.id, err });
                }
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
        
        std.log.info("Worker {} stopped", .{self.id});
    }

    fn handleConnection(self: *Worker, stream: net.Stream) !void {
        defer stream.close();
        
        self.server.stats.incrementActive();
        defer self.server.stats.decrementActive();

        var buffer: [4096]u8 = undefined;
        
        // Read request
        const bytes_read = try stream.read(&buffer);
        if (bytes_read == 0) return;

        const request = buffer[0..bytes_read];
        std.log.info("Worker {} received {} bytes", .{ self.id, bytes_read });

        // Simple HTTP response
        const stats = self.server.stats.getStats();
        const response = try std.fmt.allocPrint(
            self.server.allocator,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "Multi-threaded Zig Server\n" ++
            "Worker ID: {}\n" ++
            "Active Connections: {}\n" ++
            "Total Connections: {}\n" ++
            "Request Preview: {s}\n",
            .{ self.id, stats.active, stats.total, request[0..@min(100, request.len)] }
        );
        defer self.server.allocator.free(response);

        _ = try stream.writeAll(response);
    }
};

/// Main server structure
const Server = struct {
    allocator: std.mem.Allocator,
    config: Config,
    listener: net.Server,
    stats: ConnectionStats,
    running: Atomic(bool),
    workers: []Worker,
    accept_mutex: Mutex,

    /// Initialize server
    fn init(allocator: std.mem.Allocator, config: Config) !Server {
        const address = try net.Address.parseIp("0.0.0.0", config.port);
        const listener = try address.listen(.{
            .reuse_address = true,
            .kernel_backlog = 128,
        });

        return Server{
            .allocator = allocator,
            .config = config,
            .listener = listener,
            .stats = ConnectionStats.init(),
            .running = Atomic(bool).init(true),
            .workers = &[_]Worker{},
            .accept_mutex = .{},
        };
    }

    /// Start server with thread pool
    fn start(self: *Server) !void {
        std.log.info("Server starting on port {}", .{self.config.port});
        
        self.workers = try self.allocator.alloc(Worker, self.config.thread_pool_size);
        errdefer self.allocator.free(self.workers);

        // Spawn worker threads
        for (self.workers, 0..) |*worker, i| {
            worker.* = .{
                .thread = undefined,
                .server = self,
                .id = i,
                .running = &self.running,
            };
            worker.thread = try Thread.spawn(.{}, Worker.run, .{worker});
        }

        std.log.info("Server started with {} workers", .{self.config.thread_pool_size});
    }

    /// Accept connection with mutex protection
    fn acceptConnection(self: *Server) !net.Server.Connection {
        self.accept_mutex.lock();
        defer self.accept_mutex.unlock();
        
        return try self.listener.accept();
    }

    /// Graceful shutdown
    fn stop(self: *Server) void {
        std.log.info("Server shutting down...", .{});
        self.running.store(false, .monotonic);

        // Wait for all workers
        for (self.workers) |*worker| {
            worker.thread.join();
        }

        self.allocator.free(self.workers);
        self.listener.deinit();
        
        const stats = self.stats.getStats();
        std.log.info("Server stopped. Total connections served: {}", .{stats.total});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = Config{
        .port = 8080,
        .thread_pool_size = 4,
    };

    var server = try Server.init(allocator, config);
    defer server.stop();

    try server.start();

    std.log.info("Press Ctrl+C to stop server", .{});
    std.log.info("Test with: curl http://localhost:8080", .{});

    // Run for demo (in production, handle signals)
    std.time.sleep(60 * std.time.ns_per_s);
}
