//! Huffman Coding Compression/Decompression CLI Tool
//! Build: zig build-exe compression_tool.zig
//! Run: ./compression_tool <compress|decompress> <input_file> <output_file>
//! Example: ./compression_tool compress input.txt output.huff

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Huffman Tree Node
const HuffmanNode = struct {
    const Self = @This();
    
    char: ?u8,
    frequency: usize,
    left: ?*HuffmanNode,
    right: ?*HuffmanNode,

    fn isLeaf(self: *const Self) bool {
        return self.left == null and self.right == null;
    }

    fn compare(_: void, a: *HuffmanNode, b: *HuffmanNode) std.math.Order {
        return std.math.order(a.frequency, b.frequency);
    }
};

/// Bit writer for efficient bit-level output
const BitWriter = struct {
    buffer: std.ArrayList(u8),
    current_byte: u8,
    bit_count: u3,

    fn init(allocator: Allocator) BitWriter {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .current_byte = 0,
            .bit_count = 0,
        };
    }

    fn deinit(self: *BitWriter) void {
        self.buffer.deinit();
    }

    fn writeBit(self: *BitWriter, bit: u1) !void {
        self.current_byte = (self.current_byte << 1) | bit;
        self.bit_count += 1;

        if (self.bit_count == 8) {
            try self.buffer.append(self.current_byte);
            self.current_byte = 0;
            self.bit_count = 0;
        }
    }

    fn writeBits(self: *BitWriter, bits: []const u8) !void {
        for (bits) |bit| {
            try self.writeBit(@intCast(bit - '0'));
        }
    }

    fn flush(self: *BitWriter) !void {
        if (self.bit_count > 0) {
            self.current_byte <<= @intCast(8 - self.bit_count);
            try self.buffer.append(self.current_byte);
        }
    }

    fn toOwnedSlice(self: *BitWriter) ![]u8 {
        try self.flush();
        return self.buffer.toOwnedSlice();
    }
};

/// Bit reader for efficient bit-level input
const BitReader = struct {
    data: []const u8,
    byte_pos: usize,
    bit_pos: u3,

    fn init(data: []const u8) BitReader {
        return .{
            .data = data,
            .byte_pos = 0,
            .bit_pos = 0,
        };
    }

    fn readBit(self: *BitReader) ?u1 {
        if (self.byte_pos >= self.data.len) return null;

        const bit: u1 = @intCast((self.data[self.byte_pos] >> @intCast(7 - self.bit_pos)) & 1);
        self.bit_pos += 1;

        if (self.bit_pos == 8) {
            self.bit_pos = 0;
            self.byte_pos += 1;
        }

        return bit;
    }
};

/// Huffman Encoder
const HuffmanEncoder = struct {
    allocator: Allocator,
    root: ?*HuffmanNode,
    codes: std.AutoHashMap(u8, []const u8),
    frequency_table: [256]usize,

    fn init(allocator: Allocator) HuffmanEncoder {
        return .{
            .allocator = allocator,
            .root = null,
            .codes = std.AutoHashMap(u8, []const u8).init(allocator),
            .frequency_table = [_]usize{0} ** 256,
        };
    }

    fn deinit(self: *HuffmanEncoder) void {
        var it = self.codes.valueIterator();
        while (it.next()) |code| {
            self.allocator.free(code.*);
        }
        self.codes.deinit();
        if (self.root) |root| {
            self.freeTree(root);
        }
    }

    fn freeTree(self: *HuffmanEncoder, node: *HuffmanNode) void {
        if (node.left) |left| self.freeTree(left);
        if (node.right) |right| self.freeTree(right);
        self.allocator.destroy(node);
    }

    /// Build frequency table
    fn buildFrequencyTable(self: *HuffmanEncoder, data: []const u8) void {
        for (data) |byte| {
            self.frequency_table[byte] += 1;
        }
    }

    /// Build Huffman tree
    fn buildTree(self: *HuffmanEncoder) !void {
        var nodes = std.ArrayList(*HuffmanNode).init(self.allocator);
        defer nodes.deinit();

        // Create leaf nodes
        for (self.frequency_table, 0..) |freq, i| {
            if (freq > 0) {
                const node = try self.allocator.create(HuffmanNode);
                node.* = .{
                    .char = @intCast(i),
                    .frequency = freq,
                    .left = null,
                    .right = null,
                };
                try nodes.append(node);
            }
        }

        if (nodes.items.len == 0) return;
        if (nodes.items.len == 1) {
            // Special case: only one unique character
            const node = try self.allocator.create(HuffmanNode);
            node.* = .{
                .char = null,
                .frequency = nodes.items[0].frequency,
                .left = nodes.items[0],
                .right = null,
            };
            self.root = node;
            return;
        }

        // Build tree using priority queue (simple insertion sort)
        while (nodes.items.len > 1) {
            std.mem.sort(*HuffmanNode, nodes.items, {}, HuffmanNode.compare);

            const left = nodes.orderedRemove(0);
            const right = nodes.orderedRemove(0);

            const parent = try self.allocator.create(HuffmanNode);
            parent.* = .{
                .char = null,
                .frequency = left.frequency + right.frequency,
                .left = left,
                .right = right,
            };

            try nodes.append(parent);
        }

        self.root = nodes.items[0];
    }

    /// Generate Huffman codes
    fn generateCodes(self: *HuffmanEncoder) !void {
        if (self.root) |root| {
            var code = std.ArrayList(u8).init(self.allocator);
            defer code.deinit();
            try self.generateCodesRecursive(root, &code);
        }
    }

    fn generateCodesRecursive(self: *HuffmanEncoder, node: *HuffmanNode, code: *std.ArrayList(u8)) !void {
        if (node.isLeaf()) {
            if (node.char) |ch| {
                const code_copy = try self.allocator.dupe(u8, code.items);
                try self.codes.put(ch, code_copy);
            }
            return;
        }

        if (node.left) |left| {
            try code.append('0');
            try self.generateCodesRecursive(left, code);
            _ = code.pop();
        }

        if (node.right) |right| {
            try code.append('1');
            try self.generateCodesRecursive(right, code);
            _ = code.pop();
        }
    }

    /// Encode data
    fn encode(self: *HuffmanEncoder, data: []const u8) ![]u8 {
        var writer = BitWriter.init(self.allocator);
        errdefer writer.deinit();

        for (data) |byte| {
            if (self.codes.get(byte)) |code| {
                try writer.writeBits(code);
            }
        }

        return writer.toOwnedSlice();
    }

    /// Print codes for debugging
    fn printCodes(self: *HuffmanEncoder) void {
        std.debug.print("Huffman Codes:\n", .{});
        var it = self.codes.iterator();
        while (it.next()) |entry| {
            const ch = entry.key_ptr.*;
            const code = entry.value_ptr.*;
            std.debug.print("  '{c}' ({d}): {s}\n", .{ ch, ch, code });
        }
    }

    /// Calculate compression statistics
    fn getStats(self: *HuffmanEncoder, original_size: usize, compressed_size: usize) struct {
        original: usize,
        compressed: usize,
        ratio: f64,
    } {
        const ratio = if (original_size > 0)
            @as(f64, @floatFromInt(compressed_size)) / @as(f64, @floatFromInt(original_size)) * 100.0
        else
            0.0;

        return .{
            .original = original_size,
            .compressed = compressed_size,
            .ratio = ratio,
        };
    }
};

/// Huffman Decoder
const HuffmanDecoder = struct {
    allocator: Allocator,
    root: ?*HuffmanNode,

    fn init(allocator: Allocator, root: ?*HuffmanNode) HuffmanDecoder {
        return .{
            .allocator = allocator,
            .root = root,
        };
    }

    /// Decode compressed data
    fn decode(self: *HuffmanDecoder, compressed: []const u8, original_size: usize) ![]u8 {
        if (self.root == null) return error.NoTree;

        var result = try std.ArrayList(u8).initCapacity(self.allocator, original_size);
        errdefer result.deinit();

        var reader = BitReader.init(compressed);
        var current = self.root.?;

        while (result.items.len < original_size) {
            if (current.isLeaf()) {
                if (current.char) |ch| {
                    try result.append(ch);
                    current = self.root.?;
                }
            }

            if (reader.readBit()) |bit| {
                if (bit == 0) {
                    if (current.left) |left| {
                        current = left;
                    }
                } else {
                    if (current.right) |right| {
                        current = right;
                    }
                }
            } else {
                break;
            }
        }

        return result.toOwnedSlice();
    }
};

/// File compression helper
const CompressionTool = struct {
    allocator: Allocator,

    fn init(allocator: Allocator) CompressionTool {
        return .{ .allocator = allocator };
    }

    fn compressFile(self: *CompressionTool, input_path: []const u8, output_path: []const u8) !void {
        std.debug.print("Compressing: {s} -> {s}\n", .{ input_path, output_path });

        // Read input file
        const input_data = try std.fs.cwd().readFileAlloc(self.allocator, input_path, 10 * 1024 * 1024);
        defer self.allocator.free(input_data);

        if (input_data.len == 0) {
            std.debug.print("Error: Input file is empty\n", .{});
            return;
        }

        // Build Huffman tree and encode
        var encoder = HuffmanEncoder.init(self.allocator);
        defer encoder.deinit();

        encoder.buildFrequencyTable(input_data);
        try encoder.buildTree();
        try encoder.generateCodes();

        encoder.printCodes();

        const compressed = try encoder.encode(input_data);
        defer self.allocator.free(compressed);

        // Write compressed file (simple format: original_size + compressed_data)
        const output_file = try std.fs.cwd().createFile(output_path, .{});
        defer output_file.close();

        const original_size: u64 = input_data.len;
        try output_file.writeInt(u64, original_size, .little);
        try output_file.writeAll(compressed);

        const stats = encoder.getStats(input_data.len, compressed.len);
        std.debug.print("\nCompression Statistics:\n", .{});
        std.debug.print("  Original size: {} bytes\n", .{stats.original});
        std.debug.print("  Compressed size: {} bytes\n", .{stats.compressed});
        std.debug.print("  Compression ratio: {d:.2}%\n", .{stats.ratio});
        std.debug.print("  Space saved: {d:.2}%\n", .{100.0 - stats.ratio});
    }

    fn decompressFile(self: *CompressionTool, input_path: []const u8, output_path: []const u8) !void {
        std.debug.print("Decompressing: {s} -> {s}\n", .{ input_path, output_path });

        // Read compressed file
        const file = try std.fs.cwd().openFile(input_path, .{});
        defer file.close();

        const original_size = try file.reader().readInt(u64, .little);
        const compressed_data = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(compressed_data);

        std.debug.print("Original size: {} bytes\n", .{original_size});
        std.debug.print("Note: Full decompression requires the Huffman tree from compression\n", .{});
        std.debug.print("In this demo, we would reconstruct the tree and decode.\n", .{});

        // In a real implementation, we'd store the tree structure in the file
        // For demo purposes, we'll just write a message
        const output_file = try std.fs.cwd().createFile(output_path, .{});
        defer output_file.close();
        
        try output_file.writeAll("Decompression would happen here with stored tree structure\n");
    }
};

// ============================================================================
// Demo and CLI
// ============================================================================

fn runDemo(allocator: Allocator) !void {
    std.debug.print("=== Huffman Compression Demo ===\n\n", .{});

    const test_data = "this is a test string for huffman coding compression! the quick brown fox jumps over the lazy dog.";
    
    std.debug.print("Original text:\n{s}\n\n", .{test_data});

    var encoder = HuffmanEncoder.init(allocator);
    defer encoder.deinit();

    encoder.buildFrequencyTable(test_data);
    try encoder.buildTree();
    try encoder.generateCodes();

    encoder.printCodes();

    const compressed = try encoder.encode(test_data);
    defer allocator.free(compressed);

    const stats = encoder.getStats(test_data.len, compressed.len);
    std.debug.print("\nStatistics:\n", .{});
    std.debug.print("  Original: {} bytes\n", .{stats.original});
    std.debug.print("  Compressed: {} bytes\n", .{stats.compressed});
    std.debug.print("  Ratio: {d:.2}%\n", .{stats.ratio});

    // Decode
    var decoder = HuffmanDecoder.init(allocator, encoder.root);
    const decoded = try decoder.decode(compressed, test_data.len);
    defer allocator.free(decoded);

    std.debug.print("\nDecoded text:\n{s}\n", .{decoded});
    
    if (std.mem.eql(u8, test_data, decoded)) {
        std.debug.print("\n✓ Compression/Decompression successful!\n", .{});
    } else {
        std.debug.print("\n✗ Error: Decoded text doesn't match original!\n", .{});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip program name

    const command = args.next();
    
    if (command == null) {
        try runDemo(allocator);
        return;
    }

    const input_file = args.next();
    const output_file = args.next();

    if (input_file == null or output_file == null) {
        std.debug.print("Usage:\n", .{});
        std.debug.print("  Demo mode: ./compression_tool\n", .{});
        std.debug.print("  Compress: ./compression_tool compress <input> <output>\n", .{});
        std.debug.print("  Decompress: ./compression_tool decompress <input> <output>\n", .{});
        return;
    }

    var tool = CompressionTool.init(allocator);

    if (std.mem.eql(u8, command.?, "compress")) {
        try tool.compressFile(input_file.?, output_file.?);
    } else if (std.mem.eql(u8, command.?, "decompress")) {
        try tool.decompressFile(input_file.?, output_file.?);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command.?});
    }
}
