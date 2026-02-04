# Blog Engine - Zig Edition

High-performance blogging platform with Zig's systems programming.

## Features

- **Zero-Cost Abstractions**: Compile-time optimizations
- **Memory Safety**: Explicit allocations
- **Comptime**: Compile-time computation
- **Error Handling**: Explicit error union types
- **Performance**: C-level speed with safety

## Build & Run

```bash
zig build run
```

Server: `http://localhost:4000`

## API

**List Posts**
```bash
curl http://localhost:4000/api/posts
```

## Architecture

- **Manual Memory**: Explicit allocator patterns
- **Comptime**: Type-level programming
- **Error Unions**: Explicit error handling
- **No Hidden Control Flow**: What you see is what you get

## Project Structure

```
src/
└── main.zig           # Full implementation
```

## License

MIT
