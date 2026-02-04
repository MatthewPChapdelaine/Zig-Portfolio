# Chat Application - Zig Edition

Real-time chat with Zig's threading and mutexes.

## Features

- **Manual Threading**: Explicit thread management
- **Mutex Synchronization**: Thread-safe state
- **Zero Allocations**: Controlled memory usage
- **TCP Sockets**: Low-level networking
- **Explicit Errors**: Error union types

## Build & Run

```bash
zig build run
```

Server: Port `4001`

## Usage

```bash
telnet localhost 4001
```

Enter username and start chatting!

## Architecture

- **Threads**: Manual thread spawning
- **Mutexes**: Explicit synchronization
- **Allocators**: Custom memory management
- **Error Unions**: Explicit error handling

## License

MIT
