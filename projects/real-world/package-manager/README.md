# Package Manager - Zig Edition

Dependency management with Zig's systems programming.

## Features

- **Manual Memory**: Explicit allocators
- **Zero-Cost Abstractions**: Comptime optimization
- **Error Handling**: Explicit error unions
- **Performance**: C-level speed
- **Safety**: Compile-time checks

## Build & Run

```bash
zig build run -- install
zig build run -- graph
```

## Commands

```bash
zig build run -- install  # Install dependencies
zig build run -- graph    # Show dependency graph
```

## Example

```json
{
  "name": "my-project",
  "version": "1.0.0",
  "dependencies": {
    "zig-network": "^0.1.0"
  }
}
```

## Architecture

- **Comptime**: Type-level programming
- **Allocators**: Explicit memory management
- **Error Unions**: try/catch patterns
- **ArrayList**: Dynamic arrays

## License

MIT
