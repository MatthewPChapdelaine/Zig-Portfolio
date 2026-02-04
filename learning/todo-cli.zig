// TODO CLI - Simple task manager
// Compile: zig build-exe todo-cli.zig
// Run: ./todo-cli or zig run todo-cli.zig

const std = @import("std");

const Todo = struct {
    task: []const u8,
    done: bool,
};

const TODO_FILE = "todos.txt";

fn loadTodos(allocator: std.mem.Allocator) !std.ArrayList(Todo) {
    var todos = std.ArrayList(Todo).init(allocator);
    
    const file = std.fs.cwd().openFile(TODO_FILE, .{}) catch {
        return todos;
    };
    defer file.close();
    
    const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(contents);
    
    var lines = std.mem.split(u8, contents, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        
        var parts = std.mem.split(u8, line, "|");
        const done_str = parts.next() orelse continue;
        const task_str = parts.next() orelse continue;
        
        const task = try allocator.dupe(u8, task_str);
        try todos.append(Todo{
            .task = task,
            .done = std.mem.eql(u8, done_str, "1"),
        });
    }
    
    return todos;
}

fn saveTodos(allocator: std.mem.Allocator, todos: std.ArrayList(Todo)) !void {
    const file = try std.fs.cwd().createFile(TODO_FILE, .{});
    defer file.close();
    
    const writer = file.writer();
    
    for (todos.items) |todo| {
        const done_str = if (todo.done) "1" else "0";
        try writer.print("{s}|{s}\n", .{ done_str, todo.task });
    }
}

fn listTodos(todos: std.ArrayList(Todo)) !void {
    const stdout = std.io.getStdOut().writer();
    
    if (todos.items.len == 0) {
        try stdout.print("No tasks yet!\n", .{});
        return;
    }
    
    try stdout.print("\n=== Your Tasks ===\n", .{});
    for (todos.items, 0..) |todo, i| {
        const status = if (todo.done) "X" else " ";
        try stdout.print("{d}. [{s}] {s}\n", .{ i + 1, status, todo.task });
    }
}

fn addTodo(allocator: std.mem.Allocator, todos: *std.ArrayList(Todo), task: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const task_copy = try allocator.dupe(u8, task);
    try todos.append(Todo{ .task = task_copy, .done = false });
    try saveTodos(allocator, todos.*);
    try stdout.print("Added: {s}\n", .{task});
}

fn completeTodo(allocator: std.mem.Allocator, todos: *std.ArrayList(Todo), index: usize) !void {
    const stdout = std.io.getStdOut().writer();
    
    if (index > 0 and index <= todos.items.len) {
        todos.items[index - 1].done = true;
        try saveTodos(allocator, todos.*);
        try stdout.print("Completed: {s}\n", .{todos.items[index - 1].task});
    } else {
        try stdout.print("Invalid task number\n", .{});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    
    var todos = try loadTodos(allocator);
    defer {
        for (todos.items) |todo| {
            allocator.free(todo.task);
        }
        todos.deinit();
    }
    
    var buf: [1000]u8 = undefined;
    
    while (true) {
        try stdout.print("\n=== TODO CLI ===\n", .{});
        try stdout.print("1. List tasks\n", .{});
        try stdout.print("2. Add task\n", .{});
        try stdout.print("3. Complete task\n", .{});
        try stdout.print("4. Exit\n", .{});
        
        try stdout.print("\nChoice: ", .{});
        const choice_str = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse continue;
        const choice = std.mem.trim(u8, choice_str, &std.ascii.whitespace);
        
        if (std.mem.eql(u8, choice, "1")) {
            try listTodos(todos);
        } else if (std.mem.eql(u8, choice, "2")) {
            try stdout.print("Enter task: ", .{});
            const task_str = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse continue;
            const task = std.mem.trim(u8, task_str, &std.ascii.whitespace);
            try addTodo(allocator, &todos, task);
        } else if (std.mem.eql(u8, choice, "3")) {
            try listTodos(todos);
            try stdout.print("Task number to complete: ", .{});
            const num_str = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse continue;
            const num = std.fmt.parseInt(usize, std.mem.trim(u8, num_str, &std.ascii.whitespace), 10) catch {
                try stdout.print("Invalid number\n", .{});
                continue;
            };
            try completeTodo(allocator, &todos, num);
        } else if (std.mem.eql(u8, choice, "4")) {
            try stdout.print("Goodbye!\n", .{});
            break;
        } else {
            try stdout.print("Invalid choice\n", .{});
        }
    }
}
