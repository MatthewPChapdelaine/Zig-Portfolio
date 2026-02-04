# Zig Real-World Projects

Three high-performance projects showcasing Zig's systems programming power.

## Projects

### 1. Blog Engine (`blog-engine/`)
High-performance blogging with manual memory management.

**Features:**
- Zero-cost abstractions
- Compile-time guarantees
- Manual memory management
- Explicit allocators
- No hidden control flow
- Error unions for safety
- Comptime optimizations

**Tech Stack:**
- std.net - TCP/HTTP
- Manual allocators
- Error unions
- Comptime features

**Run:**
```bash
cd blog-engine
zig build run
```

### 2. Chat Application (`chat-application/`)
Real-time chat with manual threading.

**Features:**
- Manual thread spawning
- Mutex synchronization
- Zero hidden allocations
- TCP socket networking
- Explicit error handling
- Thread-safe state
- Performance-critical design

**Tech Stack:**
- std.Thread - Threading
- std.Mutex - Synchronization
- std.net - Networking
- ArrayList - Collections

**Run:**
```bash
cd chat-application
zig build run
```

### 3. Package Manager (`package-manager/`)
Dependency management with systems programming.

**Features:**
- Manual memory management
- Comptime optimization
- Explicit error handling
- Zero-cost abstractions
- Performance-oriented
- Custom allocators
- Compile-time safety

**Tech Stack:**
- std.json - JSON parsing
- StringHashMap - Registry
- ArrayList - Collections
- Comptime features

**Run:**
```bash
cd package-manager
zig build run -- install
```

## Zig Paradigms Demonstrated

- **Comptime**: Compile-time execution
- **Manual Memory**: Explicit allocators
- **Error Unions**: try/catch patterns
- **No Hidden Control Flow**: Explicit
- **Zero-Cost Abstractions**: Performance
- **Defer**: Resource cleanup
- **Optional Types**: Null safety
- **Build System**: zig build

## Common Setup

All projects require:
- Zig 0.11+

## Learning Path

1. **Package Manager** - Memory and data structures
2. **Blog Engine** - Networking and I/O
3. **Chat Application** - Threading and synchronization

## License

MIT
