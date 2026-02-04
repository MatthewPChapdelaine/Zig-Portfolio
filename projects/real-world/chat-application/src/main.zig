const std = @import("std");
const net = std.net;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const ArrayList = std.ArrayList;

const Message = struct {
    user: []const u8,
    content: []const u8,
    room: []const u8,
};

const Room = struct {
    name: []const u8,
    clients: ArrayList(*Client),
    messages: ArrayList(Message),
    mutex: Mutex,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) Room {
        return .{
            .name = name,
            .clients = ArrayList(*Client).init(allocator),
            .messages = ArrayList(Message).init(allocator),
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *Room) void {
        self.clients.deinit();
        self.messages.deinit();
    }
    
    pub fn broadcast(self: *Room, message: Message) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.messages.append(message);
        
        for (self.clients.items) |client| {
            const msg = try std.fmt.allocPrint(
                client.allocator,
                "[{s}] {s}: {s}\n",
                .{ message.room, message.user, message.content }
            );
            defer client.allocator.free(msg);
            
            client.stream.writeAll(msg) catch {};
        }
    }
};

const Client = struct {
    stream: net.Stream,
    allocator: std.mem.Allocator,
    username: []const u8,
};

const ChatServer = struct {
    allocator: std.mem.Allocator,
    rooms: std.StringHashMap(Room),
    mutex: Mutex,
    
    pub fn init(allocator: std.mem.Allocator) ChatServer {
        return .{
            .allocator = allocator,
            .rooms = std.StringHashMap(Room).init(allocator),
            .mutex = Mutex{},
        };
    }
    
    pub fn deinit(self: *ChatServer) void {
        var it = self.rooms.iterator();
        while (it.next()) |entry| {
            var room = entry.value_ptr;
            room.deinit();
        }
        self.rooms.deinit();
    }
    
    pub fn createRoom(self: *ChatServer, name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (!self.rooms.contains(name)) {
            const room = Room.init(self.allocator, name);
            try self.rooms.put(name, room);
            std.debug.print("✓ Created room: {s}\n", .{name});
        }
    }
    
    pub fn getRoom(self: *ChatServer, name: []const u8) ?*Room {
        return self.rooms.getPtr(name);
    }
};

fn handleClient(server: *ChatServer, stream: net.Stream, allocator: std.mem.Allocator) !void {
    defer stream.close();
    
    const welcome = "Welcome to Zig Chat! Username: ";
    try stream.writeAll(welcome);
    
    var buffer: [1024]u8 = undefined;
    const bytes = try stream.read(&buffer);
    const username = std.mem.trim(u8, buffer[0..bytes], "\r\n ");
    
    var client = Client{
        .stream = stream,
        .allocator = allocator,
        .username = username,
    };
    
    const room_name = "general";
    if (server.getRoom(room_name)) |room| {
        room.mutex.lock();
        try room.clients.append(&client);
        room.mutex.unlock();
        
        const msg = try std.fmt.allocPrint(allocator, "{s} joined the room\n", .{username});
        defer allocator.free(msg);
        try stream.writeAll(msg);
        
        while (true) {
            const read_bytes = try stream.read(&buffer);
            if (read_bytes == 0) break;
            
            const content = std.mem.trim(u8, buffer[0..read_bytes], "\r\n ");
            
            const message = Message{
                .user = username,
                .content = content,
                .room = room_name,
            };
            
            try room.broadcast(message);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var server = ChatServer.init(allocator);
    defer server.deinit();
    
    try server.createRoom("general");
    try server.createRoom("random");
    
    const address = try net.Address.parseIp("127.0.0.1", 4001);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    
    std.debug.print("💬 Zig Chat running on port 4001\n", .{});
    std.debug.print("Connect with: telnet localhost 4001\n", .{});
    
    while (true) {
        const connection = try listener.accept();
        
        const thread = try Thread.spawn(.{}, handleClient, .{ &server, connection.stream, allocator });
        thread.detach();
    }
}
