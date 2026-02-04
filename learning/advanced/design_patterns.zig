//! Design Patterns in Zig - Demonstrating 5+ patterns adapted to Zig's idioms
//! Build: zig build-exe design_patterns.zig
//! Run: ./design_patterns

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// 1. SINGLETON PATTERN - Using comptime and static variables
// ============================================================================

const Logger = struct {
    const Self = @This();
    
    allocator: Allocator,
    log_level: LogLevel,
    buffer: std.ArrayList(u8),

    const LogLevel = enum { debug, info, warn, err };

    var instance: ?*Self = null;
    var mutex: std.Thread.Mutex = .{};

    /// Get singleton instance
    fn getInstance(allocator: Allocator) !*Self {
        mutex.lock();
        defer mutex.unlock();

        if (instance == null) {
            const new_instance = try allocator.create(Self);
            new_instance.* = .{
                .allocator = allocator,
                .log_level = .info,
                .buffer = std.ArrayList(u8).init(allocator),
            };
            instance = new_instance;
        }
        return instance.?;
    }

    fn log(self: *Self, level: LogLevel, comptime fmt: []const u8, args: anytype) !void {
        mutex.lock();
        defer mutex.unlock();

        const writer = self.buffer.writer();
        try writer.print("[{s}] ", .{@tagName(level)});
        try writer.print(fmt, args);
        try writer.writeByte('\n');
    }

    fn getLog(self: *Self) []const u8 {
        return self.buffer.items;
    }

    fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.allocator.destroy(self);
        instance = null;
    }
};

// ============================================================================
// 2. FACTORY PATTERN - Using tagged unions and comptime
// ============================================================================

const Shape = union(enum) {
    circle: Circle,
    rectangle: Rectangle,
    triangle: Triangle,

    const Circle = struct { radius: f32 };
    const Rectangle = struct { width: f32, height: f32 };
    const Triangle = struct { base: f32, height: f32 };

    fn area(self: Shape) f32 {
        return switch (self) {
            .circle => |c| std.math.pi * c.radius * c.radius,
            .rectangle => |r| r.width * r.height,
            .triangle => |t| 0.5 * t.base * t.height,
        };
    }

    fn perimeter(self: Shape) f32 {
        return switch (self) {
            .circle => |c| 2.0 * std.math.pi * c.radius,
            .rectangle => |r| 2.0 * (r.width + r.height),
            .triangle => |t| t.base + 2.0 * @sqrt(t.height * t.height + (t.base / 2.0) * (t.base / 2.0)),
        };
    }
};

const ShapeFactory = struct {
    /// Factory method using comptime type selection
    fn create(comptime shape_type: std.meta.Tag(Shape), params: anytype) Shape {
        return switch (shape_type) {
            .circle => .{ .circle = .{ .radius = params.radius } },
            .rectangle => .{ .rectangle = .{ .width = params.width, .height = params.height } },
            .triangle => .{ .triangle = .{ .base = params.base, .height = params.height } },
        };
    }
};

// ============================================================================
// 3. OBSERVER PATTERN - Event system with callbacks
// ============================================================================

const Event = union(enum) {
    user_login: []const u8,
    user_logout: []const u8,
    data_changed: i32,
};

const Observer = struct {
    name: []const u8,
    callback: *const fn (observer: *Observer, event: Event) void,

    fn notify(self: *Observer, event: Event) void {
        self.callback(self, event);
    }
};

const Subject = struct {
    allocator: Allocator,
    observers: std.ArrayList(*Observer),

    fn init(allocator: Allocator) Subject {
        return .{
            .allocator = allocator,
            .observers = std.ArrayList(*Observer).init(allocator),
        };
    }

    fn deinit(self: *Subject) void {
        self.observers.deinit();
    }

    fn attach(self: *Subject, observer: *Observer) !void {
        try self.observers.append(observer);
    }

    fn detach(self: *Subject, observer: *Observer) void {
        for (self.observers.items, 0..) |obs, i| {
            if (obs == observer) {
                _ = self.observers.orderedRemove(i);
                break;
            }
        }
    }

    fn notifyAll(self: *Subject, event: Event) void {
        for (self.observers.items) |observer| {
            observer.notify(event);
        }
    }
};

// ============================================================================
// 4. STRATEGY PATTERN - Algorithm selection using interface pattern
// ============================================================================

const SortStrategy = struct {
    const Self = @This();
    
    ptr: *anyopaque,
    sortFn: *const fn (ptr: *anyopaque, data: []i32) void,

    fn sort(self: Self, data: []i32) void {
        self.sortFn(self.ptr, data);
    }
};

const BubbleSort = struct {
    fn strategy(self: *BubbleSort) SortStrategy {
        return .{
            .ptr = self,
            .sortFn = sortImpl,
        };
    }

    fn sortImpl(ptr: *anyopaque, data: []i32) void {
        _ = ptr;
        var i: usize = 0;
        while (i < data.len) : (i += 1) {
            var j: usize = 0;
            while (j < data.len - i - 1) : (j += 1) {
                if (data[j] > data[j + 1]) {
                    const temp = data[j];
                    data[j] = data[j + 1];
                    data[j + 1] = temp;
                }
            }
        }
    }
};

const QuickSort = struct {
    fn strategy(self: *QuickSort) SortStrategy {
        return .{
            .ptr = self,
            .sortFn = sortImpl,
        };
    }

    fn sortImpl(ptr: *anyopaque, data: []i32) void {
        _ = ptr;
        if (data.len <= 1) return;
        quickSortRecursive(data);
    }

    fn quickSortRecursive(data: []i32) void {
        if (data.len <= 1) return;
        
        const pivot = data[data.len / 2];
        var i: usize = 0;
        var j: usize = data.len - 1;
        
        while (i <= j) {
            while (data[i] < pivot) i += 1;
            while (data[j] > pivot) {
                if (j == 0) break;
                j -= 1;
            }
            
            if (i <= j) {
                const temp = data[i];
                data[i] = data[j];
                data[j] = temp;
                i += 1;
                if (j == 0) break;
                j -= 1;
            }
        }
        
        if (j > 0) quickSortRecursive(data[0..j + 1]);
        if (i < data.len) quickSortRecursive(data[i..]);
    }
};

const Sorter = struct {
    strategy: SortStrategy,

    fn setStrategy(self: *Sorter, strategy: SortStrategy) void {
        self.strategy = strategy;
    }

    fn sort(self: *Sorter, data: []i32) void {
        self.strategy.sort(data);
    }
};

// ============================================================================
// 5. DECORATOR PATTERN - Wrapping behavior
// ============================================================================

const Component = struct {
    const Self = @This();
    
    ptr: *anyopaque,
    operationFn: *const fn (ptr: *anyopaque, allocator: Allocator) Allocator.Error![]const u8,

    fn operation(self: Self, allocator: Allocator) ![]const u8 {
        return self.operationFn(self.ptr, allocator);
    }
};

const ConcreteComponent = struct {
    data: []const u8,

    fn component(self: *ConcreteComponent) Component {
        return .{
            .ptr = self,
            .operationFn = operationImpl,
        };
    }

    fn operationImpl(ptr: *anyopaque, allocator: Allocator) Allocator.Error![]const u8 {
        const self: *ConcreteComponent = @ptrCast(@alignCast(ptr));
        return try std.fmt.allocPrint(allocator, "{s}", .{self.data});
    }
};

const UpperCaseDecorator = struct {
    wrapped: Component,

    fn component(self: *UpperCaseDecorator) Component {
        return .{
            .ptr = self,
            .operationFn = operationImpl,
        };
    }

    fn operationImpl(ptr: *anyopaque, allocator: Allocator) Allocator.Error![]const u8 {
        const self: *UpperCaseDecorator = @ptrCast(@alignCast(ptr));
        const result = try self.wrapped.operation(allocator);
        defer allocator.free(result);
        
        var upper = try allocator.alloc(u8, result.len);
        for (result, 0..) |c, i| {
            upper[i] = std.ascii.toUpper(c);
        }
        return upper;
    }
};

const BracketDecorator = struct {
    wrapped: Component,

    fn component(self: *BracketDecorator) Component {
        return .{
            .ptr = self,
            .operationFn = operationImpl,
        };
    }

    fn operationImpl(ptr: *anyopaque, allocator: Allocator) Allocator.Error![]const u8 {
        const self: *BracketDecorator = @ptrCast(@alignCast(ptr));
        const result = try self.wrapped.operation(allocator);
        defer allocator.free(result);
        return try std.fmt.allocPrint(allocator, "[{s}]", .{result});
    }
};

// ============================================================================
// 6. BUILDER PATTERN - Fluent construction
// ============================================================================

const HttpRequest = struct {
    method: []const u8,
    url: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: Allocator,

    fn deinit(self: *HttpRequest) void {
        self.headers.deinit();
    }
};

const RequestBuilder = struct {
    allocator: Allocator,
    method: []const u8 = "GET",
    url: []const u8 = "/",
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8 = null,

    fn init(allocator: Allocator) RequestBuilder {
        return .{
            .allocator = allocator,
            .headers = std.StringHashMap([]const u8).init(allocator),
        };
    }

    fn setMethod(self: *RequestBuilder, method: []const u8) *RequestBuilder {
        self.method = method;
        return self;
    }

    fn setUrl(self: *RequestBuilder, url: []const u8) *RequestBuilder {
        self.url = url;
        return self;
    }

    fn addHeader(self: *RequestBuilder, key: []const u8, value: []const u8) !*RequestBuilder {
        try self.headers.put(key, value);
        return self;
    }

    fn setBody(self: *RequestBuilder, body: []const u8) *RequestBuilder {
        self.body = body;
        return self;
    }

    fn build(self: *RequestBuilder) HttpRequest {
        return .{
            .method = self.method,
            .url = self.url,
            .headers = self.headers,
            .body = self.body,
            .allocator = self.allocator,
        };
    }
};

// ============================================================================
// DEMO
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Design Patterns in Zig ===\n\n", .{});

    // 1. Singleton Pattern
    std.debug.print("1. SINGLETON PATTERN\n", .{});
    const logger = try Logger.getInstance(allocator);
    defer logger.deinit();
    try logger.log(.info, "First log message", .{});
    try logger.log(.warn, "Second log message", .{});
    std.debug.print("Log: {s}\n\n", .{logger.getLog()});

    // 2. Factory Pattern
    std.debug.print("2. FACTORY PATTERN\n", .{});
    const circle = ShapeFactory.create(.circle, .{ .radius = 5.0 });
    const rect = ShapeFactory.create(.rectangle, .{ .width = 4.0, .height = 6.0 });
    std.debug.print("Circle area: {d:.2}, perimeter: {d:.2}\n", .{ circle.area(), circle.perimeter() });
    std.debug.print("Rectangle area: {d:.2}, perimeter: {d:.2}\n\n", .{ rect.area(), rect.perimeter() });

    // 3. Observer Pattern
    std.debug.print("3. OBSERVER PATTERN\n", .{});
    var subject = Subject.init(allocator);
    defer subject.deinit();

    var obs1 = Observer{ .name = "Observer1", .callback = struct {
        fn cb(observer: *Observer, event: Event) void {
            std.debug.print("{s} received: {}\n", .{ observer.name, event });
        }
    }.cb };

    try subject.attach(&obs1);
    subject.notifyAll(.{ .user_login = "Alice" });
    subject.notifyAll(.{ .data_changed = 42 });
    std.debug.print("\n", .{});

    // 4. Strategy Pattern
    std.debug.print("4. STRATEGY PATTERN\n", .{});
    var data1 = [_]i32{ 64, 34, 25, 12, 22, 11, 90 };
    var bubble = BubbleSort{};
    var sorter = Sorter{ .strategy = bubble.strategy() };
    sorter.sort(&data1);
    std.debug.print("Bubble sort: {any}\n", .{data1});

    var data2 = [_]i32{ 64, 34, 25, 12, 22, 11, 90 };
    var quick = QuickSort{};
    sorter.setStrategy(quick.strategy());
    sorter.sort(&data2);
    std.debug.print("Quick sort: {any}\n\n", .{data2});

    // 5. Decorator Pattern
    std.debug.print("5. DECORATOR PATTERN\n", .{});
    var concrete = ConcreteComponent{ .data = "hello world" };
    var uppercase = UpperCaseDecorator{ .wrapped = concrete.component() };
    var bracket = BracketDecorator{ .wrapped = uppercase.component() };
    
    const result = try bracket.component().operation(allocator);
    defer allocator.free(result);
    std.debug.print("Decorated result: {s}\n\n", .{result});

    // 6. Builder Pattern
    std.debug.print("6. BUILDER PATTERN\n", .{});
    var builder = RequestBuilder.init(allocator);
    var request = try builder
        .setMethod("POST")
        .setUrl("/api/users")
        .addHeader("Content-Type", "application/json")
        .addHeader("Authorization", "Bearer token123")
        .setBody("{\"name\": \"Alice\"}")
        .build();
    defer request.deinit();
    
    std.debug.print("Request: {} {s}\n", .{ request.method, request.url });
    std.debug.print("Headers: {} items\n", .{request.headers.count()});
    std.debug.print("Body: {s}\n", .{request.body.?});

    std.debug.print("\n=== All patterns demonstrated successfully! ===\n", .{});
}
