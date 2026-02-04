# Zig Project Template

A basic Zig project structure with the Zig build system.

## Structure

```
zig-project-template/
├── src/
│   ├── main.zig             # Main application code
│   └── main.test.zig        # Unit tests
├── build.zig                # Build configuration
├── build.zig.zon            # Package metadata
└── README.md               # This file
```

## Setup

```bash
# Install Zig
# https://ziglang.org/download/

# Or use a version manager like zigup:
# zigup master
# zigup 0.11.0

# No additional setup needed - Zig is self-contained
```

## Usage

```bash
# Run the application
zig build run

# Or build and run executable
zig build
./zig-out/bin/zig-project
```

## Testing

```bash
# Run all tests
zig build test

# Run tests with verbose output
zig build test --summary all

# Run tests with leak detection
zig build test -Dtest-leak-check=true
```

## Build

```bash
# Build in debug mode
zig build

# Build in release mode (optimized)
zig build -Doptimize=ReleaseFast

# Build for release (with safety checks)
zig build -Doptimize=ReleaseSafe

# Build for release (small binary)
zig build -Doptimize=ReleaseSmall

# Cross-compile for different target
zig build -Dtarget=x86_64-windows
```

## Development

1. Install Zig (0.11.0 or later recommended)
2. Run `zig build` to compile the project
3. Make your changes in `src/main.zig`
4. Write tests in `src/main.test.zig` or create new test files
5. Run `zig build test` before committing

## Code Formatting

```bash
# Format all Zig files
zig fmt src/
zig fmt build.zig
```

## Clean Build

```bash
# Remove build artifacts
rm -rf zig-out zig-cache
```

## Check Compilation

```bash
# Check without building
zig build --help

# Check for errors without producing output
zig build-exe src/main.zig --check
```

## Language Server

Zig has built-in language server support (zls):
```bash
# Install zls
# https://github.com/zigtools/zls
```
