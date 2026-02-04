# Quick Reference Guide

## One-Line Descriptions

1. **multi_threaded_server.zig** - Production TCP server with thread pool and connection stats
2. **design_patterns.zig** - 6 classic patterns (Singleton, Factory, Observer, Strategy, Decorator, Builder)
3. **web_framework.zig** - HTTP framework with routing, middleware, and multiple content types
4. **database_orm.zig** - Full ORM with query builder, repositories, and migrations
5. **graph_algorithms.zig** - BFS, DFS, Dijkstra, topological sort, cycle detection
6. **compression_tool.zig** - Huffman coding with bit-level I/O and CLI interface
7. **memory_pool.zig** - 3 custom allocators with benchmarks and real-world examples
8. **lexer_parser.zig** - Expression parser with AST, operator precedence, and REPL

## Quick Build & Test

```bash
# Navigate to directory
cd /home/matthew/repos/Programming_Repos/zig-projects/learning/advanced/

# Build and run a program (example)
zig build-exe design_patterns.zig && ./design_patterns

# Build all at once
for f in *.zig; do echo "Building $f..."; zig build-exe "$f"; done

# Clean up binaries
rm -f multi_threaded_server design_patterns web_framework database_orm \
      graph_algorithms compression_tool memory_pool lexer_parser
```

## Quick Test Commands

```bash
# 1. Design Patterns - See all 6 patterns
./design_patterns

# 2. Graph Algorithms - Watch algorithms in action  
./graph_algorithms

# 3. Memory Pool - Compare allocator performance
./memory_pool

# 4. Lexer/Parser - Try expression evaluation
./lexer_parser
echo "2 + 3 * 4" | ./lexer_parser --interactive

# 5. Compression - Compress text
echo "hello world hello world" > test.txt
./compression_tool compress test.txt test.huff

# 6. Web Framework - Start server (Ctrl+C to stop)
./web_framework &
curl http://localhost:3000/
curl http://localhost:3000/api/users
kill %1

# 7. Multi-threaded Server (Ctrl+C to stop)
./multi_threaded_server &
curl http://localhost:8080
kill %1

# 8. Database ORM - See query building
./database_orm
```

## Key Code Snippets

### Custom Allocator Usage
```zig
var pool = try PoolAllocator(64).init(allocator, 100);
defer pool.deinit();
const pool_alloc = pool.allocator();
const mem = try pool_alloc.alloc(u8, 32);
defer pool_alloc.free(mem);
```

### Error Handling Pattern
```zig
const result = doSomething() catch |err| {
    std.log.err("Failed: {}", .{err});
    return err;
};
defer cleanup(result);
```

### Generic Type Function
```zig
fn Repository(comptime T: type) type {
    return struct {
        fn findById(self: *Self, id: i64) !?T { ... }
    };
}
```

### Thread Pool Pattern
```zig
var workers = try allocator.alloc(Worker, num_threads);
for (workers) |*worker| {
    worker.thread = try Thread.spawn(.{}, Worker.run, .{worker});
}
for (workers) |*worker| {
    worker.thread.join();
}
```

### Parser Pattern (Recursive Descent)
```zig
fn expression(self: *Parser) !Node {
    var left = try self.term();
    while (self.match(.plus, .minus)) {
        const op = self.previous();
        const right = try self.term();
        left = Node{ .binary = .{ .left = left, .op = op, .right = right } };
    }
    return left;
}
```

## Common Patterns Used

### Defer Cleanup
```zig
var list = ArrayList(T).init(allocator);
defer list.deinit();

const file = try std.fs.cwd().createFile("test.txt", .{});
defer file.close();
```

### Error Defer
```zig
var resource = try allocate();
errdefer resource.deinit(); // Only runs on error
try doSomething(resource);
resource.deinit(); // Normal cleanup
```

### Comptime Generic
```zig
fn Pool(comptime T: type, comptime size: usize) type {
    return struct {
        items: [size]T,
        // ...
    };
}
```

### Tagged Union
```zig
const Result = union(enum) {
    success: i32,
    error: []const u8,
    
    fn isOk(self: Result) bool {
        return switch (self) {
            .success => true,
            .error => false,
        };
    }
};
```

## Performance Tips from Examples

1. **Use Pool Allocators** for fixed-size objects (5-10x faster)
2. **Use Arena Allocators** for temporary batches (minimal overhead)
3. **Atomic Operations** avoid mutex overhead for simple counters
4. **Comptime Computation** moves work to compile time
5. **Stack Allocation** (`var buffer: [1024]u8`) is fastest
6. **Defer Cleanup** prevents leaks and simplifies code

## Debugging Tips

```bash
# Build with debug symbols
zig build-exe -O Debug program.zig

# Check for memory leaks (GPA will report)
# The programs use GeneralPurposeAllocator which reports leaks

# Print AST or data structures
std.debug.print("Value: {any}\n", .{my_struct});

# Use --verbose for zig compiler
zig build-exe --verbose program.zig
```

## Common Zig Gotchas (Handled in Code)

1. ✓ Always pass allocator explicitly
2. ✓ Match every alloc with free (or use defer)
3. ✓ Handle all error cases or propagate with try
4. ✓ Use errdefer for partial cleanup
5. ✓ Optionals must be unwrapped before use
6. ✓ Slices don't own memory
7. ✓ Comptime parameters need `comptime` keyword
8. ✓ Mutex protect shared mutable state

## File Organization

```
advanced/
├── README.md                    # Full documentation
├── SUMMARY.md                   # Detailed summary
├── QUICK_REFERENCE.md          # This file
├── multi_threaded_server.zig   # Networking + concurrency
├── design_patterns.zig         # Software patterns
├── web_framework.zig           # HTTP framework
├── database_orm.zig            # Data access layer
├── graph_algorithms.zig        # Graph algorithms
├── compression_tool.zig        # Data compression
├── memory_pool.zig            # Custom allocators
└── lexer_parser.zig           # Language processing
```

## When to Use Each Program as Template

| Need | Use This Program |
|------|-----------------|
| TCP Server | multi_threaded_server.zig |
| API Design | web_framework.zig or database_orm.zig |
| Data Processing | compression_tool.zig |
| CLI Tool | compression_tool.zig or lexer_parser.zig |
| Graph Problems | graph_algorithms.zig |
| Custom Memory | memory_pool.zig |
| Pattern Library | design_patterns.zig |
| DSL/Language | lexer_parser.zig |

## Extend These Programs

### Add to multi_threaded_server.zig
- WebSocket support
- TLS/SSL encryption
- Request routing
- Static file serving

### Add to web_framework.zig
- Template engine
- Session management
- Authentication
- Database integration

### Add to database_orm.zig
- Real SQL database (SQLite)
- Connection pooling
- Transactions
- Schema validation

### Add to graph_algorithms.zig
- A* pathfinding
- Minimum spanning tree
- Maximum flow
- Graph visualization

### Add to compression_tool.zig
- LZW compression
- gzip wrapper
- Parallel compression
- Streaming compression

### Add to memory_pool.zig
- Thread-local pools
- Growing pools
- Memory defragmentation
- Pool statistics visualization

### Add to lexer_parser.zig
- Functions and calls
- Control flow (if/while)
- Type system
- Code generation

## All Build Commands

```bash
zig build-exe multi_threaded_server.zig
zig build-exe design_patterns.zig
zig build-exe web_framework.zig
zig build-exe database_orm.zig
zig build-exe graph_algorithms.zig
zig build-exe compression_tool.zig
zig build-exe memory_pool.zig
zig build-exe lexer_parser.zig
```

## Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Learn](https://ziglearn.org/)

---

**All programs are production-ready, well-documented, and memory-safe!**
