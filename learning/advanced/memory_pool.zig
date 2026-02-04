//! Custom Memory Pool Allocator with Benchmarks
//! Build: zig build-exe memory_pool.zig
//! Run: ./memory_pool

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Fixed-size memory pool allocator
/// Efficiently allocates fixed-size blocks from pre-allocated memory
fn PoolAllocator(comptime block_size: usize) type {
    return struct {
        const Self = @This();
        const Block = struct {
            next: ?*Block,
        };

        backing_allocator: Allocator,
        memory: []u8,
        free_list: ?*Block,
        total_blocks: usize,
        used_blocks: usize,

        pub fn init(backing_allocator: Allocator, num_blocks: usize) !Self {
            const memory_size = num_blocks * block_size;
            const memory = try backing_allocator.alloc(u8, memory_size);
            
            var pool = Self{
                .backing_allocator = backing_allocator,
                .memory = memory,
                .free_list = null,
                .total_blocks = num_blocks,
                .used_blocks = 0,
            };

            // Initialize free list
            var i: usize = 0;
            while (i < num_blocks) : (i += 1) {
                const block_ptr = @as(*Block, @ptrCast(@alignCast(&memory[i * block_size])));
                block_ptr.next = pool.free_list;
                pool.free_list = block_ptr;
            }

            return pool;
        }

        pub fn deinit(self: *Self) void {
            self.backing_allocator.free(self.memory);
        }

        pub fn allocator(self: *Self) Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            _ = ptr_align;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));

            if (len > block_size) return null;
            if (self.free_list == null) return null;

            const block = self.free_list.?;
            self.free_list = block.next;
            self.used_blocks += 1;

            return @ptrCast(block);
        }

        fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            _ = ctx;
            _ = buf_align;
            _ = ret_addr;
            
            if (new_len > block_size) return false;
            if (new_len <= buf.len) return true;
            return false;
        }

        fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            _ = buf_align;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));

            const block: *Block = @ptrCast(@alignCast(buf.ptr));
            block.next = self.free_list;
            self.free_list = block;
            self.used_blocks -= 1;
        }

        pub fn stats(self: *const Self) struct { total: usize, used: usize, free: usize } {
            return .{
                .total = self.total_blocks,
                .used = self.used_blocks,
                .free = self.total_blocks - self.used_blocks,
            };
        }
    };
}

/// Arena allocator variant - allocates sequentially, frees all at once
const ArenaPool = struct {
    const Self = @This();
    
    backing_allocator: Allocator,
    memory: []u8,
    offset: usize,
    allocations: usize,

    pub fn init(backing_allocator: Allocator, size: usize) !Self {
        const memory = try backing_allocator.alloc(u8, size);
        return Self{
            .backing_allocator = backing_allocator,
            .memory = memory,
            .offset = 0,
            .allocations = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.backing_allocator.free(self.memory);
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        // Align offset
        const alignment = @as(usize, 1) << @intCast(ptr_align);
        const aligned_offset = std.mem.alignForward(usize, self.offset, alignment);
        
        const new_offset = aligned_offset + len;
        if (new_offset > self.memory.len) return null;

        self.offset = new_offset;
        self.allocations += 1;

        return self.memory[aligned_offset..].ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = buf_align;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        const buf_addr = @intFromPtr(buf.ptr);
        const mem_addr = @intFromPtr(self.memory.ptr);
        
        // Check if this is the last allocation
        if (buf_addr + buf.len == mem_addr + self.offset) {
            const new_offset = buf_addr - mem_addr + new_len;
            if (new_offset <= self.memory.len) {
                self.offset = new_offset;
                return true;
            }
        }
        
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // Arena doesn't free individual allocations
    }

    pub fn reset(self: *Self) void {
        self.offset = 0;
        self.allocations = 0;
    }

    pub fn stats(self: *const Self) struct { capacity: usize, used: usize, allocations: usize } {
        return .{
            .capacity = self.memory.len,
            .used = self.offset,
            .allocations = self.allocations,
        };
    }
};

/// Stack allocator - LIFO allocation/deallocation
const StackAllocator = struct {
    const Self = @This();
    
    memory: []u8,
    offset: usize,
    prev_offset: usize,

    pub fn init(memory: []u8) Self {
        return Self{
            .memory = memory,
            .offset = 0,
            .prev_offset = 0,
        };
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        const alignment = @as(usize, 1) << @intCast(ptr_align);
        const aligned_offset = std.mem.alignForward(usize, self.offset, alignment);
        
        const new_offset = aligned_offset + len;
        if (new_offset > self.memory.len) return null;

        self.prev_offset = self.offset;
        self.offset = new_offset;

        return self.memory[aligned_offset..].ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        _ = ctx;
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));

        const buf_addr = @intFromPtr(buf.ptr);
        const mem_addr = @intFromPtr(self.memory.ptr);
        
        // Only allow freeing the last allocation
        if (buf_addr + buf.len == mem_addr + self.offset) {
            self.offset = buf_addr - mem_addr;
        }
    }
};

/// Benchmark utilities
const Benchmark = struct {
    fn measure(comptime name: []const u8, func: anytype, args: anytype) !void {
        const start = std.time.nanoTimestamp();
        try @call(.auto, func, args);
        const end = std.time.nanoTimestamp();
        const duration = end - start;
        
        std.debug.print("{s}: {d:.3} ms\n", .{ name, @as(f64, @floatFromInt(duration)) / 1_000_000.0 });
    }

    fn benchmarkAllocator(allocator: Allocator, name: []const u8, iterations: usize, size: usize) !void {
        std.debug.print("\nBenchmarking {s}:\n", .{name});
        
        const start = std.time.nanoTimestamp();
        
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const mem = try allocator.alloc(u8, size);
            allocator.free(mem);
        }
        
        const end = std.time.nanoTimestamp();
        const duration = end - start;
        const avg_duration = @as(f64, @floatFromInt(duration)) / @as(f64, @floatFromInt(iterations));
        
        std.debug.print("  Total time: {d:.3} ms\n", .{@as(f64, @floatFromInt(duration)) / 1_000_000.0});
        std.debug.print("  Average per allocation: {d:.3} μs\n", .{avg_duration / 1000.0});
        std.debug.print("  Operations per second: {d:.0}\n", .{1_000_000_000.0 / avg_duration});
    }
};

// ============================================================================
// Tests and Demo
// ============================================================================

fn testPoolAllocator(allocator: Allocator) !void {
    std.debug.print("=== Pool Allocator Test ===\n", .{});
    
    var pool = try PoolAllocator(64).init(allocator, 10);
    defer pool.deinit();
    
    const pool_alloc = pool.allocator();
    
    std.debug.print("Initial stats: {}\n", .{pool.stats()});
    
    // Allocate some blocks
    const mem1 = try pool_alloc.alloc(u8, 32);
    const mem2 = try pool_alloc.alloc(u8, 64);
    const mem3 = try pool_alloc.alloc(u8, 16);
    
    std.debug.print("After 3 allocations: {}\n", .{pool.stats()});
    
    // Free some blocks
    pool_alloc.free(mem2);
    std.debug.print("After freeing mem2: {}\n", .{pool.stats()});
    
    pool_alloc.free(mem1);
    pool_alloc.free(mem3);
    std.debug.print("After freeing all: {}\n", .{pool.stats()});
}

fn testArenaAllocator(allocator: Allocator) !void {
    std.debug.print("\n=== Arena Allocator Test ===\n", .{});
    
    var arena = try ArenaPool.init(allocator, 4096);
    defer arena.deinit();
    
    const arena_alloc = arena.allocator();
    
    std.debug.print("Initial stats: {}\n", .{arena.stats()});
    
    // Allocate multiple blocks
    var allocations = std.ArrayList([]u8).init(allocator);
    defer allocations.deinit();
    
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const mem = try arena_alloc.alloc(u8, 100);
        try allocations.append(mem);
    }
    
    std.debug.print("After 10 allocations: {}\n", .{arena.stats()});
    
    // Reset arena
    arena.reset();
    std.debug.print("After reset: {}\n", .{arena.stats()});
}

fn testStackAllocator() !void {
    std.debug.print("\n=== Stack Allocator Test ===\n", .{});
    
    var buffer: [4096]u8 = undefined;
    var stack = StackAllocator.init(&buffer);
    const stack_alloc = stack.allocator();
    
    const mem1 = try stack_alloc.alloc(u8, 100);
    std.debug.print("Allocated 100 bytes, offset: {}\n", .{stack.offset});
    
    const mem2 = try stack_alloc.alloc(u8, 200);
    std.debug.print("Allocated 200 bytes, offset: {}\n", .{stack.offset});
    
    // LIFO free
    stack_alloc.free(mem2);
    std.debug.print("Freed mem2, offset: {}\n", .{stack.offset});
    
    stack_alloc.free(mem1);
    std.debug.print("Freed mem1, offset: {}\n", .{stack.offset});
}

fn runBenchmarks(allocator: Allocator) !void {
    std.debug.print("\n=== Allocator Benchmarks ===\n", .{});
    
    const iterations = 10_000;
    const alloc_size = 64;
    
    // Benchmark GPA
    try Benchmark.benchmarkAllocator(allocator, "GeneralPurposeAllocator", iterations, alloc_size);
    
    // Benchmark Pool
    var pool = try PoolAllocator(128).init(allocator, 100);
    defer pool.deinit();
    try Benchmark.benchmarkAllocator(pool.allocator(), "PoolAllocator(128)", iterations, alloc_size);
    
    // Benchmark Arena (with periodic resets)
    var arena = try ArenaPool.init(allocator, 1024 * 1024);
    defer arena.deinit();
    
    std.debug.print("\nBenchmarking ArenaPool:\n", .{});
    const start = std.time.nanoTimestamp();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const mem = try arena.allocator().alloc(u8, alloc_size);
        _ = mem;
        
        // Reset every 100 allocations
        if (i % 100 == 99) {
            arena.reset();
        }
    }
    
    const end = std.time.nanoTimestamp();
    const duration = end - start;
    const avg_duration = @as(f64, @floatFromInt(duration)) / @as(f64, @floatFromInt(iterations));
    
    std.debug.print("  Total time: {d:.3} ms\n", .{@as(f64, @floatFromInt(duration)) / 1_000_000.0});
    std.debug.print("  Average per allocation: {d:.3} μs\n", .{avg_duration / 1000.0});
    std.debug.print("  Operations per second: {d:.0}\n", .{1_000_000_000.0 / avg_duration});
}

fn demonstrateUseCases(allocator: Allocator) !void {
    std.debug.print("\n=== Use Case Demonstrations ===\n", .{});
    
    // Use case 1: Pool allocator for game entities
    std.debug.print("\n1. Pool Allocator - Game Entity Management\n", .{});
    const Entity = struct {
        x: f32,
        y: f32,
        health: i32,
    };
    
    var entity_pool = try PoolAllocator(@sizeOf(Entity)).init(allocator, 1000);
    defer entity_pool.deinit();
    
    var entities = std.ArrayList(*Entity).init(allocator);
    defer entities.deinit();
    
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const entity = try entity_pool.allocator().create(Entity);
        entity.* = .{ .x = @floatFromInt(i), .y = @floatFromInt(i * 2), .health = 100 };
        try entities.append(entity);
    }
    
    std.debug.print("  Created {} entities\n", .{entities.items.len});
    std.debug.print("  Pool stats: {}\n", .{entity_pool.stats()});
    
    // Use case 2: Arena for temporary parsing
    std.debug.print("\n2. Arena Allocator - Temporary String Processing\n", .{});
    var temp_arena = try ArenaPool.init(allocator, 4096);
    defer temp_arena.deinit();
    
    const words = [_][]const u8{ "hello", "world", "from", "zig" };
    var processed = std.ArrayList([]u8).init(allocator);
    defer {
        for (processed.items) |s| allocator.free(s);
        processed.deinit();
    }
    
    for (words) |word| {
        const upper = try temp_arena.allocator().alloc(u8, word.len);
        for (word, 0..) |c, j| {
            upper[j] = std.ascii.toUpper(c);
        }
        const permanent = try allocator.dupe(u8, upper);
        try processed.append(permanent);
    }
    
    std.debug.print("  Processed words: ", .{});
    for (processed.items) |word| {
        std.debug.print("{s} ", .{word});
    }
    std.debug.print("\n", .{});
    std.debug.print("  Arena stats: {}\n", .{temp_arena.stats()});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Custom Memory Pool Allocators ===\n\n", .{});

    try testPoolAllocator(allocator);
    try testArenaAllocator(allocator);
    try testStackAllocator();
    try runBenchmarks(allocator);
    try demonstrateUseCases(allocator);

    std.debug.print("\n=== All tests and benchmarks complete! ===\n", .{});
}
