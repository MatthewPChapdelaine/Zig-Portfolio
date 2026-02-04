//! Real-time stream processing system with windowing and backpressure
//! Demonstrates: Channel-based communication, windowing, aggregations, transformations
//! Features: Tumbling/sliding windows, stream operators, backpressure handling

const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Condition = Thread.Condition;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Generic event type for stream processing
fn Event(comptime T: type) type {
    return struct {
        timestamp: i64,
        data: T,

        fn init(data: T) @This() {
            return .{
                .timestamp = std.time.milliTimestamp(),
                .data = data,
            };
        }
    };
}

/// Thread-safe bounded channel for backpressure
fn Channel(comptime T: type) type {
    return struct {
        buffer: []T,
        capacity: usize,
        read_idx: usize,
        write_idx: usize,
        count: usize,
        mutex: Mutex,
        not_empty: Condition,
        not_full: Condition,
        closed: bool,

        const Self = @This();

        fn init(allocator: Allocator, capacity: usize) !*Self {
            const channel = try allocator.create(Self);
            const buffer = try allocator.alloc(T, capacity);

            channel.* = .{
                .buffer = buffer,
                .capacity = capacity,
                .read_idx = 0,
                .write_idx = 0,
                .count = 0,
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .closed = false,
            };

            return channel;
        }

        fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.buffer);
            allocator.destroy(self);
        }

        fn send(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait for space (backpressure)
            while (self.count == self.capacity and !self.closed) {
                self.not_full.wait(&self.mutex);
            }

            if (self.closed) return error.ChannelClosed;

            self.buffer[self.write_idx] = item;
            self.write_idx = (self.write_idx + 1) % self.capacity;
            self.count += 1;

            self.not_empty.signal();
        }

        fn receive(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait for data
            while (self.count == 0 and !self.closed) {
                self.not_empty.wait(&self.mutex);
            }

            if (self.count == 0 and self.closed) return error.ChannelClosed;

            const item = self.buffer[self.read_idx];
            self.read_idx = (self.read_idx + 1) % self.capacity;
            self.count -= 1;

            self.not_full.signal();

            return item;
        }

        fn tryReceive(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) return null;

            const item = self.buffer[self.read_idx];
            self.read_idx = (self.read_idx + 1) % self.capacity;
            self.count -= 1;

            self.not_full.signal();

            return item;
        }

        fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.closed = true;
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }

        fn isClosed(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.closed;
        }

        fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.count;
        }
    };
}

/// Window types for stream aggregation
const WindowType = enum {
    tumbling,
    sliding,
};

/// Window configuration
const WindowConfig = struct {
    window_type: WindowType,
    size_ms: i64,
    slide_ms: i64,
};

/// Aggregation functions
fn AggregationFn(comptime T: type) type {
    return *const fn ([]const T, Allocator) anyerror!T;
}

/// Common aggregation functions
const Aggregations = struct {
    fn sum(values: []const f64, allocator: Allocator) !f64 {
        _ = allocator;
        var total: f64 = 0;
        for (values) |v| total += v;
        return total;
    }

    fn avg(values: []const f64, allocator: Allocator) !f64 {
        _ = allocator;
        if (values.len == 0) return 0;
        var total: f64 = 0;
        for (values) |v| total += v;
        return total / @as(f64, @floatFromInt(values.len));
    }

    fn min(values: []const f64, allocator: Allocator) !f64 {
        _ = allocator;
        if (values.len == 0) return 0;
        var minimum = values[0];
        for (values[1..]) |v| {
            if (v < minimum) minimum = v;
        }
        return minimum;
    }

    fn max(values: []const f64, allocator: Allocator) !f64 {
        _ = allocator;
        if (values.len == 0) return 0;
        var maximum = values[0];
        for (values[1..]) |v| {
            if (v > maximum) maximum = v;
        }
        return maximum;
    }

    fn count(values: []const f64, allocator: Allocator) !f64 {
        _ = allocator;
        return @floatFromInt(values.len);
    }
};

/// Stream operator: Map
fn MapOperator(comptime In: type, comptime Out: type) type {
    return struct {
        input: *Channel(Event(In)),
        output: *Channel(Event(Out)),
        transform: *const fn (In) Out,
        thread: ?Thread,
        running: bool,

        const Self = @This();

        fn init(input: *Channel(Event(In)), output: *Channel(Event(Out)), transform: *const fn (In) Out) Self {
            return .{
                .input = input,
                .output = output,
                .transform = transform,
                .thread = null,
                .running = false,
            };
        }

        fn start(self: *Self) !void {
            self.running = true;
            self.thread = try Thread.spawn(.{}, run, .{self});
        }

        fn stop(self: *Self) void {
            self.running = false;
            if (self.thread) |thread| {
                thread.join();
            }
        }

        fn run(self: *Self) void {
            while (self.running) {
                const event = self.input.receive() catch break;
                const transformed = self.transform(event.data);
                const output_event = Event(Out).init(transformed);
                self.output.send(output_event) catch break;
            }
        }
    };
}

/// Stream operator: Filter
fn FilterOperator(comptime T: type) type {
    return struct {
        input: *Channel(Event(T)),
        output: *Channel(Event(T)),
        predicate: *const fn (T) bool,
        thread: ?Thread,
        running: bool,

        const Self = @This();

        fn init(input: *Channel(Event(T)), output: *Channel(Event(T)), predicate: *const fn (T) bool) Self {
            return .{
                .input = input,
                .output = output,
                .predicate = predicate,
                .thread = null,
                .running = false,
            };
        }

        fn start(self: *Self) !void {
            self.running = true;
            self.thread = try Thread.spawn(.{}, run, .{self});
        }

        fn stop(self: *Self) void {
            self.running = false;
            if (self.thread) |thread| {
                thread.join();
            }
        }

        fn run(self: *Self) void {
            while (self.running) {
                const event = self.input.receive() catch break;
                if (self.predicate(event.data)) {
                    self.output.send(event) catch break;
                }
            }
        }
    };
}

/// Stream operator: Window aggregation
fn WindowOperator(comptime T: type) type {
    return struct {
        input: *Channel(Event(T)),
        output: *Channel(Event(T)),
        config: WindowConfig,
        aggregate: AggregationFn(T),
        allocator: Allocator,
        thread: ?Thread,
        running: bool,

        const Self = @This();

        fn init(
            allocator: Allocator,
            input: *Channel(Event(T)),
            output: *Channel(Event(T)),
            config: WindowConfig,
            aggregate: AggregationFn(T),
        ) Self {
            return .{
                .input = input,
                .output = output,
                .config = config,
                .aggregate = aggregate,
                .allocator = allocator,
                .thread = null,
                .running = false,
            };
        }

        fn start(self: *Self) !void {
            self.running = true;
            self.thread = try Thread.spawn(.{}, run, .{self});
        }

        fn stop(self: *Self) void {
            self.running = false;
            if (self.thread) |thread| {
                thread.join();
            }
        }

        fn run(self: *Self) void {
            var window_buffer = ArrayList(Event(T)).init(self.allocator);
            defer window_buffer.deinit();

            var window_start = std.time.milliTimestamp();

            while (self.running) {
                // Try to receive events without blocking too long
                const event = self.input.receive() catch break;

                const now = event.timestamp;
                const window_end = window_start + self.config.size_ms;

                // Check if we need to process the current window
                if (now >= window_end) {
                    self.processWindow(window_buffer.items) catch {};

                    // Move window forward
                    switch (self.config.window_type) {
                        .tumbling => {
                            window_buffer.clearRetainingCapacity();
                            window_start = now;
                        },
                        .sliding => {
                            // Remove events outside the new window
                            const new_start = window_start + self.config.slide_ms;
                            var i: usize = 0;
                            while (i < window_buffer.items.len) {
                                if (window_buffer.items[i].timestamp < new_start) {
                                    _ = window_buffer.orderedRemove(i);
                                } else {
                                    i += 1;
                                }
                            }
                            window_start = new_start;
                        },
                    }
                }

                // Add event to window
                window_buffer.append(event) catch {};
            }

            // Process final window
            if (window_buffer.items.len > 0) {
                self.processWindow(window_buffer.items) catch {};
            }
        }

        fn processWindow(self: *Self, events: []const Event(T)) !void {
            if (events.len == 0) return;

            // Extract data values
            var values = try self.allocator.alloc(T, events.len);
            defer self.allocator.free(values);

            for (events, 0..) |event, i| {
                values[i] = event.data;
            }

            // Apply aggregation
            const result = try self.aggregate(values, self.allocator);
            const output_event = Event(T).init(result);

            try self.output.send(output_event);
        }
    };
}

/// Stream source: Generate events
fn SourceOperator(comptime T: type) type {
    return struct {
        output: *Channel(Event(T)),
        generator: *const fn (u64) T,
        count: u64,
        delay_ms: u64,
        thread: ?Thread,
        running: bool,

        const Self = @This();

        fn init(output: *Channel(Event(T)), generator: *const fn (u64) T, count: u64, delay_ms: u64) Self {
            return .{
                .output = output,
                .generator = generator,
                .count = count,
                .delay_ms = delay_ms,
                .thread = null,
                .running = false,
            };
        }

        fn start(self: *Self) !void {
            self.running = true;
            self.thread = try Thread.spawn(.{}, run, .{self});
        }

        fn stop(self: *Self) void {
            self.running = false;
            if (self.thread) |thread| {
                thread.join();
            }
        }

        fn run(self: *Self) void {
            var i: u64 = 0;
            while (self.running and i < self.count) : (i += 1) {
                const data = self.generator(i);
                const event = Event(T).init(data);
                self.output.send(event) catch break;

                if (self.delay_ms > 0) {
                    std.time.sleep(self.delay_ms * std.time.ns_per_ms);
                }
            }
            self.output.close();
        }
    };
}

/// Stream sink: Consume and print events
fn SinkOperator(comptime T: type) type {
    return struct {
        input: *Channel(Event(T)),
        name: []const u8,
        thread: ?Thread,
        running: bool,

        const Self = @This();

        fn init(input: *Channel(Event(T)), name: []const u8) Self {
            return .{
                .input = input,
                .name = name,
                .thread = null,
                .running = false,
            };
        }

        fn start(self: *Self) !void {
            self.running = true;
            self.thread = try Thread.spawn(.{}, run, .{self});
        }

        fn stop(self: *Self) void {
            self.running = false;
            if (self.thread) |thread| {
                thread.join();
            }
        }

        fn run(self: *Self) void {
            while (self.running) {
                const event = self.input.receive() catch break;
                std.debug.print("[{s}] Event at {}: {d:.2}\n", .{ self.name, event.timestamp, event.data });
            }
        }
    };
}

/// Example: Temperature sensor data processing
fn temperatureGenerator(i: u64) f64 {
    var prng = std.rand.DefaultPrng.init(i + 42);
    const random = prng.random();
    return 20.0 + random.float(f64) * 10.0; // 20-30°C
}

fn celsiusToFahrenheit(celsius: f64) f64 {
    return celsius * 9.0 / 5.0 + 32.0;
}

fn isHighTemp(fahrenheit: f64) bool {
    return fahrenheit > 80.0;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Real-Time Stream Processing System ===\n\n", .{});

    // Create channels with backpressure (bounded)
    const channel_capacity = 10;
    var source_to_map = try Channel(Event(f64)).init(allocator, channel_capacity);
    defer source_to_map.deinit(allocator);

    var map_to_filter = try Channel(Event(f64)).init(allocator, channel_capacity);
    defer map_to_filter.deinit(allocator);

    var filter_to_window = try Channel(Event(f64)).init(allocator, channel_capacity);
    defer filter_to_window.deinit(allocator);

    var window_to_sink = try Channel(Event(f64)).init(allocator, channel_capacity);
    defer window_to_sink.deinit(allocator);

    // Build stream processing pipeline
    std.debug.print("Building pipeline: Source -> Map -> Filter -> Window -> Sink\n\n", .{});

    // Source: Generate temperature readings
    var source = SourceOperator(f64).init(source_to_map, &temperatureGenerator, 50, 100);

    // Map: Convert Celsius to Fahrenheit
    var map = MapOperator(f64, f64).init(source_to_map, map_to_filter, &celsiusToFahrenheit);

    // Filter: Only high temperatures
    var filter = FilterOperator(f64).init(map_to_filter, filter_to_window, &isHighTemp);

    // Window: 2-second tumbling window with average
    var window = WindowOperator(f64).init(
        allocator,
        filter_to_window,
        window_to_sink,
        .{ .window_type = .tumbling, .size_ms = 2000, .slide_ms = 0 },
        &Aggregations.avg,
    );

    // Sink: Print results
    var sink = SinkOperator(f64).init(window_to_sink, "HighTempAvg");

    // Start all operators
    std.debug.print("Starting stream processing...\n\n", .{});

    try source.start();
    try map.start();
    try filter.start();
    try window.start();
    try sink.start();

    // Wait for processing to complete
    std.time.sleep(6 * std.time.ns_per_s);

    // Stop all operators
    std.debug.print("\nStopping pipeline...\n", .{});

    source.stop();
    map.stop();
    filter.stop();
    window.stop();
    sink.stop();

    std.debug.print("\n=== Stream Processing Features Demonstrated ===\n", .{});
    std.debug.print("✓ Channel-based communication with backpressure\n", .{});
    std.debug.print("✓ Map operator (data transformation)\n", .{});
    std.debug.print("✓ Filter operator (predicate filtering)\n", .{});
    std.debug.print("✓ Window operator (tumbling windows)\n", .{});
    std.debug.print("✓ Aggregation functions (avg, sum, min, max)\n", .{});
    std.debug.print("✓ Source and sink operators\n", .{});
    std.debug.print("✓ Multi-threaded parallel processing\n", .{});
    std.debug.print("✓ Thread-safe bounded channels\n", .{});

    std.debug.print("\nAdditional features available:\n", .{});
    std.debug.print("- Sliding windows (implemented)\n", .{});
    std.debug.print("- Multiple aggregation functions\n", .{});
    std.debug.print("- Composable stream operators\n", .{});
    std.debug.print("- Backpressure handling\n", .{});
}
