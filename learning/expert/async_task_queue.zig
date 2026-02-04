//! Production-grade async task queue with priority, retries, and persistence
//! Demonstrates: Multi-threading, synchronization, priority queues, error handling
//! Features: Worker pool, priority scheduling, retry logic, dead-letter queue

const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Condition = Thread.Condition;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

/// Task priority levels
const Priority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,

    fn compare(_: void, a: Priority, b: Priority) std.math.Order {
        return std.math.order(@intFromEnum(b), @intFromEnum(a)); // Higher priority first
    }
};

/// Task status for tracking
const TaskStatus = enum {
    pending,
    running,
    completed,
    failed,
    dead_letter,
};

/// Task payload and metadata
const Task = struct {
    id: u64,
    name: []const u8,
    payload: []const u8,
    priority: Priority,
    status: TaskStatus,
    attempts: u32,
    max_retries: u32,
    created_at: i64,
    scheduled_at: i64,
    allocator: Allocator,

    const Self = @This();

    fn init(
        allocator: Allocator,
        id: u64,
        name: []const u8,
        payload: []const u8,
        priority: Priority,
        max_retries: u32,
    ) !*Self {
        const task = try allocator.create(Self);
        const now = std.time.milliTimestamp();

        task.* = .{
            .id = id,
            .name = try allocator.dupe(u8, name),
            .payload = try allocator.dupe(u8, payload),
            .priority = priority,
            .status = .pending,
            .attempts = 0,
            .max_retries = max_retries,
            .created_at = now,
            .scheduled_at = now,
            .allocator = allocator,
        };

        return task;
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.payload);
        self.allocator.destroy(self);
    }

    fn clone(self: *const Self) !*Self {
        return try Self.init(
            self.allocator,
            self.id,
            self.name,
            self.payload,
            self.priority,
            self.max_retries,
        );
    }
};

/// Priority queue implementation using binary heap
fn PriorityQueue(comptime T: type, comptime Context: type, comptime compareFn: fn (Context, T, T) std.math.Order) type {
    return struct {
        items: ArrayList(T),
        context: Context,

        const Self = @This();

        fn init(allocator: Allocator, context: Context) Self {
            return .{
                .items = ArrayList(T).init(allocator),
                .context = context,
            };
        }

        fn deinit(self: *Self) void {
            self.items.deinit();
        }

        fn insert(self: *Self, item: T) !void {
            try self.items.append(item);
            self.siftUp(self.items.items.len - 1);
        }

        fn extractMax(self: *Self) ?T {
            if (self.items.items.len == 0) return null;

            const result = self.items.items[0];
            const last = self.items.pop();

            if (self.items.items.len > 0) {
                self.items.items[0] = last;
                self.siftDown(0);
            }

            return result;
        }

        fn peek(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        fn isEmpty(self: *Self) bool {
            return self.items.items.len == 0;
        }

        fn siftUp(self: *Self, start_idx: usize) void {
            var idx = start_idx;

            while (idx > 0) {
                const parent_idx = (idx - 1) / 2;

                if (compareFn(self.context, self.items.items[idx], self.items.items[parent_idx]) == .gt) {
                    std.mem.swap(T, &self.items.items[idx], &self.items.items[parent_idx]);
                    idx = parent_idx;
                } else {
                    break;
                }
            }
        }

        fn siftDown(self: *Self, start_idx: usize) void {
            var idx = start_idx;
            const len = self.items.items.len;

            while (true) {
                const left_child = 2 * idx + 1;
                const right_child = 2 * idx + 2;
                var largest = idx;

                if (left_child < len and compareFn(self.context, self.items.items[left_child], self.items.items[largest]) == .gt) {
                    largest = left_child;
                }

                if (right_child < len and compareFn(self.context, self.items.items[right_child], self.items.items[largest]) == .gt) {
                    largest = right_child;
                }

                if (largest != idx) {
                    std.mem.swap(T, &self.items.items[idx], &self.items.items[largest]);
                    idx = largest;
                } else {
                    break;
                }
            }
        }
    };
}

/// Task execution result
const TaskResult = union(enum) {
    success: void,
    failure: []const u8,
    retry_after: i64,
};

/// Worker thread for processing tasks
const Worker = struct {
    id: usize,
    queue: *TaskQueue,
    thread: ?Thread,
    running: bool,

    const Self = @This();

    fn init(id: usize, queue: *TaskQueue) Self {
        return .{
            .id = id,
            .queue = queue,
            .thread = null,
            .running = true,
        };
    }

    fn start(self: *Self) !void {
        self.thread = try Thread.spawn(.{}, workerLoop, .{self});
    }

    fn stop(self: *Self) void {
        self.running = false;
        if (self.thread) |thread| {
            thread.join();
        }
    }

    fn workerLoop(self: *Self) void {
        while (self.running) {
            if (self.queue.dequeue()) |task| {
                self.processTask(task);
            } else {
                // No tasks available, sleep briefly
                std.time.sleep(100 * std.time.ns_per_ms);
            }
        }
    }

    fn processTask(self: *Self, task: *Task) void {
        task.status = .running;
        task.attempts += 1;

        std.debug.print("[Worker {}] Processing task {}: {s}\n", .{ self.id, task.id, task.name });

        // Simulate task execution
        const result = self.executeTask(task);

        switch (result) {
            .success => {
                task.status = .completed;
                self.queue.onTaskCompleted(task);
                std.debug.print("[Worker {}] Task {} completed successfully\n", .{ self.id, task.id });
            },
            .failure => |reason| {
                if (task.attempts < task.max_retries) {
                    std.debug.print("[Worker {}] Task {} failed (attempt {}): {s} - retrying\n", .{
                        self.id,
                        task.id,
                        task.attempts,
                        reason,
                    });
                    task.status = .pending;
                    self.queue.retry(task) catch {
                        task.status = .dead_letter;
                        self.queue.onTaskFailed(task);
                    };
                } else {
                    std.debug.print("[Worker {}] Task {} failed permanently: {s}\n", .{ self.id, task.id, reason });
                    task.status = .dead_letter;
                    self.queue.onTaskFailed(task);
                }
            },
            .retry_after => |delay_ms| {
                std.debug.print("[Worker {}] Task {} scheduled for retry in {}ms\n", .{ self.id, task.id, delay_ms });
                task.status = .pending;
                task.scheduled_at = std.time.milliTimestamp() + delay_ms;
                self.queue.retry(task) catch {
                    task.status = .dead_letter;
                    self.queue.onTaskFailed(task);
                };
            },
        }
    }

    fn executeTask(self: *Self, task: *Task) TaskResult {
        _ = self;

        // Simulate work
        std.time.sleep(100 * std.time.ns_per_ms);

        // Simulate different outcomes based on task name
        if (std.mem.indexOf(u8, task.name, "fail") != null) {
            return TaskResult{ .failure = "Simulated failure" };
        } else if (std.mem.indexOf(u8, task.name, "retry") != null and task.attempts < 2) {
            return TaskResult{ .retry_after = 500 };
        } else {
            return TaskResult.success;
        }
    }
};

/// Main task queue with worker pool
const TaskQueue = struct {
    pending: PriorityQueue(*Task, void, taskPriorityCompare),
    dead_letter: ArrayList(*Task),
    completed: ArrayList(*Task),
    workers: ArrayList(Worker),
    mutex: Mutex,
    condition: Condition,
    allocator: Allocator,
    next_task_id: u64,
    running: bool,

    const Self = @This();

    fn taskPriorityCompare(_: void, a: *Task, b: *Task) std.math.Order {
        // First compare priority
        const priority_order = Priority.compare({}, a.priority, b.priority);
        if (priority_order != .eq) return priority_order;

        // Then compare scheduled time (earlier first)
        return std.math.order(a.scheduled_at, b.scheduled_at);
    }

    fn init(allocator: Allocator, num_workers: usize) !*Self {
        const queue = try allocator.create(Self);

        queue.* = .{
            .pending = PriorityQueue(*Task, void, taskPriorityCompare).init(allocator, {}),
            .dead_letter = ArrayList(*Task).init(allocator),
            .completed = ArrayList(*Task).init(allocator),
            .workers = ArrayList(Worker).init(allocator),
            .mutex = .{},
            .condition = .{},
            .allocator = allocator,
            .next_task_id = 1,
            .running = true,
        };

        // Create worker threads
        for (0..num_workers) |i| {
            var worker = Worker.init(i, queue);
            try queue.workers.append(worker);
        }

        return queue;
    }

    fn deinit(self: *Self) void {
        // Clean up pending tasks
        while (self.pending.extractMax()) |task| {
            task.deinit();
        }
        self.pending.deinit();

        // Clean up completed tasks
        for (self.completed.items) |task| {
            task.deinit();
        }
        self.completed.deinit();

        // Clean up dead-letter tasks
        for (self.dead_letter.items) |task| {
            task.deinit();
        }
        self.dead_letter.deinit();

        self.workers.deinit();
        self.allocator.destroy(self);
    }

    fn start(self: *Self) !void {
        for (self.workers.items) |*worker| {
            try worker.start();
        }
    }

    fn stop(self: *Self) void {
        self.mutex.lock();
        self.running = false;
        self.mutex.unlock();

        self.condition.broadcast();

        for (self.workers.items) |*worker| {
            worker.stop();
        }
    }

    fn enqueue(self: *Self, name: []const u8, payload: []const u8, priority: Priority, max_retries: u32) !u64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const task_id = self.next_task_id;
        self.next_task_id += 1;

        const task = try Task.init(self.allocator, task_id, name, payload, priority, max_retries);
        errdefer task.deinit();

        try self.pending.insert(task);
        self.condition.signal();

        std.debug.print("[Queue] Enqueued task {}: {s} (priority: {s})\n", .{ task_id, name, @tagName(priority) });

        return task_id;
    }

    fn dequeue(self: *Self) ?*Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();

        // Check if the highest priority task is ready
        if (self.pending.peek()) |task| {
            if (task.scheduled_at <= now) {
                return self.pending.extractMax();
            }
        }

        return null;
    }

    fn retry(self: *Self, task: *Task) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Exponential backoff
        const backoff_ms: i64 = @intCast(1000 * (@as(u64, 1) << @intCast(task.attempts - 1)));
        task.scheduled_at = std.time.milliTimestamp() + backoff_ms;

        try self.pending.insert(task);
        self.condition.signal();
    }

    fn onTaskCompleted(self: *Self, task: *Task) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.completed.append(task) catch {
            // If we can't store it, just clean it up
            task.deinit();
        };
    }

    fn onTaskFailed(self: *Self, task: *Task) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.dead_letter.append(task) catch {
            // If we can't store it, just clean it up
            task.deinit();
        };
    }

    fn getStats(self: *Self) struct { pending: usize, completed: usize, dead_letter: usize } {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .pending = self.pending.items.items.len,
            .completed = self.completed.items.len,
            .dead_letter = self.dead_letter.items.len,
        };
    }

    fn persistState(self: *Self, file_path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        const writer = file.writer();

        // Write header
        try writer.print("# Task Queue State Snapshot\n", .{});
        try writer.print("# Timestamp: {}\n\n", .{std.time.milliTimestamp()});

        // Write pending tasks
        try writer.print("[PENDING] Count: {}\n", .{self.pending.items.items.len});
        for (self.pending.items.items) |task| {
            try writer.print("  Task {}: {s} (priority: {s}, attempts: {})\n", .{
                task.id,
                task.name,
                @tagName(task.priority),
                task.attempts,
            });
        }

        // Write completed tasks
        try writer.print("\n[COMPLETED] Count: {}\n", .{self.completed.items.len});
        for (self.completed.items) |task| {
            try writer.print("  Task {}: {s}\n", .{ task.id, task.name });
        }

        // Write dead-letter tasks
        try writer.print("\n[DEAD_LETTER] Count: {}\n", .{self.dead_letter.items.len});
        for (self.dead_letter.items) |task| {
            try writer.print("  Task {}: {s} (attempts: {})\n", .{ task.id, task.name, task.attempts });
        }

        std.debug.print("[Queue] State persisted to {s}\n", .{file_path});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Production Async Task Queue Demo ===\n\n", .{});

    // Create task queue with 3 workers
    const num_workers = 3;
    var queue = try TaskQueue.init(allocator, num_workers);
    defer queue.deinit();

    std.debug.print("Starting {} worker threads...\n\n", .{num_workers});
    try queue.start();
    defer queue.stop();

    // Enqueue various tasks
    _ = try queue.enqueue("process_payment", "user_123:amount_100", .critical, 3);
    _ = try queue.enqueue("send_email", "welcome@example.com", .high, 2);
    _ = try queue.enqueue("generate_report", "monthly_sales", .normal, 1);
    _ = try queue.enqueue("cleanup_temp", "/tmp/cache", .low, 0);
    _ = try queue.enqueue("task_retry", "test_retry_logic", .high, 3);
    _ = try queue.enqueue("task_fail", "test_dead_letter", .normal, 2);
    _ = try queue.enqueue("process_order", "order_456", .critical, 3);
    _ = try queue.enqueue("backup_database", "prod_db", .high, 2);

    std.debug.print("\n", .{});

    // Let tasks process
    std.time.sleep(5 * std.time.ns_per_s);

    // Check statistics
    std.debug.print("\n=== Queue Statistics ===\n", .{});
    const stats = queue.getStats();
    std.debug.print("Pending tasks: {}\n", .{stats.pending});
    std.debug.print("Completed tasks: {}\n", .{stats.completed});
    std.debug.print("Dead-letter tasks: {}\n", .{stats.dead_letter});

    // Persist state to file
    std.debug.print("\n", .{});
    try queue.persistState("/tmp/task_queue_state.txt");

    // Let retry tasks finish
    std.time.sleep(3 * std.time.ns_per_s);

    // Final statistics
    std.debug.print("\n=== Final Statistics ===\n", .{});
    const final_stats = queue.getStats();
    std.debug.print("Pending tasks: {}\n", .{final_stats.pending});
    std.debug.print("Completed tasks: {}\n", .{final_stats.completed});
    std.debug.print("Dead-letter tasks: {}\n", .{final_stats.dead_letter});

    std.debug.print("\n=== Task Queue Features Demonstrated ===\n", .{});
    std.debug.print("✓ Priority-based task scheduling\n", .{});
    std.debug.print("✓ Multi-threaded worker pool\n", .{});
    std.debug.print("✓ Automatic retry logic with exponential backoff\n", .{});
    std.debug.print("✓ Dead-letter queue for failed tasks\n", .{});
    std.debug.print("✓ Thread-safe operations with mutex\n", .{});
    std.debug.print("✓ State persistence to disk\n", .{});
    std.debug.print("✓ Task metadata and tracking\n", .{});
}
