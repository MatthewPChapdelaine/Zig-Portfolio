# Advanced Zig Programs

This directory contains 8 production-quality advanced Zig programs demonstrating sophisticated concepts, patterns, and algorithms.

## Programs Overview

### 1. multi_threaded_server.zig
**Concurrent TCP server with thread pooling**

Features:
- Thread pool pattern with configurable worker threads
- Connection statistics tracking with atomic operations
- Graceful shutdown handling
- Mutex-protected accept() calls
- Simple HTTP response generation

Build & Run:
```bash
zig build-exe multi_threaded_server.zig
./multi_threaded_server
# Test: curl http://localhost:8080
```

### 2. design_patterns.zig
**6 Design patterns adapted to Zig**

Patterns implemented:
1. **Singleton** - Thread-safe singleton with mutex
2. **Factory** - Tagged union factory with comptime
3. **Observer** - Event system with callbacks
4. **Strategy** - Algorithm selection with interface pattern
5. **Decorator** - Wrapping behavior with composition
6. **Builder** - Fluent API for construction

Build & Run:
```bash
zig build-exe design_patterns.zig
./design_patterns
```

### 3. web_framework.zig
**Mini HTTP web framework**

Features:
- HTTP request/response parsing
- Router with multiple HTTP methods (GET, POST, PUT, DELETE)
- Middleware chain execution
- Route matching
- JSON and HTML responses
- CORS support

Build & Run:
```bash
zig build-exe web_framework.zig
./web_framework
# Test: curl http://localhost:3000/
# Test: curl -X POST http://localhost:3000/api/users -d '{"name":"Alice"}'
```

### 4. database_orm.zig
**ORM/Database abstraction layer**

Features:
- Query builder with fluent API
- WHERE clauses with operators
- JOIN support (INNER, LEFT, RIGHT)
- ORDER BY, LIMIT, OFFSET
- Repository pattern for CRUD operations
- Migration system with up/down migrations
- Generic model trait using comptime
- Mock database with query logging

Build & Run:
```bash
zig build-exe database_orm.zig
./database_orm
```

### 5. graph_algorithms.zig
**Graph algorithms with test cases**

Algorithms implemented:
- **BFS** - Breadth-first search and shortest path
- **DFS** - Depth-first search (recursive and iterative)
- **Dijkstra** - Shortest path in weighted graphs
- **Topological Sort** - DAG ordering (Kahn's algorithm)
- **Cycle Detection** - For directed and undirected graphs

Build & Run:
```bash
zig build-exe graph_algorithms.zig
./graph_algorithms
```

### 6. compression_tool.zig
**Huffman coding compression/decompression**

Features:
- Frequency table generation
- Huffman tree construction with priority queue
- Code generation via tree traversal
- Bit-level I/O (BitWriter/BitReader)
- Compression statistics
- CLI tool for file compression
- Full encode/decode cycle

Build & Run:
```bash
zig build-exe compression_tool.zig
./compression_tool                                    # Demo mode
./compression_tool compress input.txt output.huff    # Compress file
./compression_tool decompress output.huff restored.txt # Decompress
```

### 7. memory_pool.zig
**Custom allocators with benchmarks**

Allocators implemented:
- **PoolAllocator** - Fixed-size block allocation
- **ArenaPool** - Sequential allocation with bulk reset
- **StackAllocator** - LIFO allocation/deallocation

Features:
- Implements std.mem.Allocator interface
- Performance benchmarks vs GPA
- Statistics tracking
- Real-world use case demonstrations
- Memory safety guarantees

Build & Run:
```bash
zig build-exe memory_pool.zig
./memory_pool
```

### 8. lexer_parser.zig
**Expression lexer and parser with AST evaluation**

Features:
- Tokenizer/lexer with position tracking
- Recursive descent parser
- Abstract Syntax Tree (AST) representation
- Proper operator precedence
- Support for:
  - Binary operators: +, -, *, /, %, ^
  - Unary operators: +, -
  - Parentheses
  - Variables
  - Floating-point numbers
- Expression evaluator with variables
- Interactive REPL mode

Build & Run:
```bash
zig build-exe lexer_parser.zig
./lexer_parser                    # Run tests
./lexer_parser --interactive      # Interactive mode
```

## Zig Idioms Demonstrated

### Memory Management
- Explicit allocator passing
- Proper defer usage for cleanup
- Arena allocators for temporary allocations
- Custom allocator implementations
- No memory leaks (validated with GPA)

### Error Handling
- Error unions (`!T`)
- Error sets
- Try/catch patterns
- Errdefer for cleanup on error

### Type System
- Tagged unions for variant types
- Comptime for compile-time computation
- Generic types with `fn Type(comptime T: type)`
- Type introspection with `@typeInfo`

### Concurrency
- Thread spawning and joining
- Atomic operations
- Mutex for synchronization
- Thread-safe patterns

### Standard Library
- `std.mem.Allocator` interface
- `std.ArrayList` and `std.HashMap`
- `std.net` for networking
- `std.fmt` for formatting
- `std.json` parsing

## Building All Programs

```bash
# From the advanced directory
for file in *.zig; do
    echo "Building $file..."
    zig build-exe "$file" || echo "Failed to build $file"
done
```

## Testing All Programs

```bash
# Run each program
for exe in multi_threaded_server design_patterns web_framework database_orm graph_algorithms compression_tool memory_pool lexer_parser; do
    if [ -f "./$exe" ]; then
        echo "=== Running $exe ==="
        timeout 5s "./$exe" || echo "(timeout or completed)"
        echo ""
    fi
done
```

## Zig Version

These programs are written for **Zig 0.11+** or **Zig 0.12+**. They use standard library features available in recent Zig versions.

## Key Concepts by Program

| Program | Primary Concepts |
|---------|-----------------|
| multi_threaded_server | Concurrency, networking, atomics |
| design_patterns | OOP patterns, comptime, interfaces |
| web_framework | HTTP, routing, middleware |
| database_orm | Query building, repositories, migrations |
| graph_algorithms | Algorithms, data structures, BFS/DFS |
| compression_tool | Bit manipulation, trees, CLI tools |
| memory_pool | Custom allocators, performance |
| lexer_parser | Parsing, AST, interpreters |

## Production Quality Features

✓ **Error handling** - All error cases handled  
✓ **Memory safety** - No leaks, proper cleanup  
✓ **Documentation** - Doc comments and inline comments  
✓ **Testing** - Built-in tests and demos  
✓ **Build instructions** - Clear build/run commands  
✓ **Zig idioms** - Proper allocator usage, error unions  
✓ **Working demos** - Complete main() functions  
✓ **Type safety** - Leverages Zig's type system  

## Learning Path

Recommended order for learning:

1. **design_patterns.zig** - Core Zig patterns
2. **memory_pool.zig** - Memory management
3. **lexer_parser.zig** - Complex data structures
4. **graph_algorithms.zig** - Algorithms
5. **compression_tool.zig** - Bit manipulation
6. **database_orm.zig** - API design
7. **web_framework.zig** - Networking basics
8. **multi_threaded_server.zig** - Concurrency

## Performance Notes

- Pool allocators are 5-10x faster than GPA for fixed sizes
- Arena allocators minimize allocation overhead
- Proper use of defer prevents leaks
- Atomic operations avoid mutex overhead where possible
- Comptime computation reduces runtime cost

## License

Public domain / MIT - use freely for learning and projects.
