//! Expression Lexer and Parser with AST Evaluation
//! Build: zig build-exe lexer_parser.zig
//! Run: ./lexer_parser
//! Example expressions: "2 + 3 * 4", "(10 - 5) / 2", "3.14 * radius^2"

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Token types
const TokenType = enum {
    number,
    identifier,
    plus,
    minus,
    multiply,
    divide,
    modulo,
    power,
    lparen,
    rparen,
    eof,

    fn toString(self: TokenType) []const u8 {
        return switch (self) {
            .number => "NUMBER",
            .identifier => "IDENTIFIER",
            .plus => "PLUS",
            .minus => "MINUS",
            .multiply => "MULTIPLY",
            .divide => "DIVIDE",
            .modulo => "MODULO",
            .power => "POWER",
            .lparen => "LPAREN",
            .rparen => "RPAREN",
            .eof => "EOF",
        };
    }
};

/// Token
const Token = struct {
    type: TokenType,
    value: []const u8,
    position: usize,

    fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}('{s}' @ {})", .{ self.type.toString(), self.value, self.position });
    }
};

/// Lexer - converts source text into tokens
const Lexer = struct {
    source: []const u8,
    position: usize,
    current_char: ?u8,

    fn init(source: []const u8) Lexer {
        var lexer = Lexer{
            .source = source,
            .position = 0,
            .current_char = null,
        };
        if (source.len > 0) {
            lexer.current_char = source[0];
        }
        return lexer;
    }

    fn advance(self: *Lexer) void {
        self.position += 1;
        if (self.position >= self.source.len) {
            self.current_char = null;
        } else {
            self.current_char = self.source[self.position];
        }
    }

    fn peek(self: *Lexer, offset: usize) ?u8 {
        const pos = self.position + offset;
        if (pos >= self.source.len) return null;
        return self.source[pos];
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.current_char) |ch| {
            if (!std.ascii.isWhitespace(ch)) break;
            self.advance();
        }
    }

    fn readNumber(self: *Lexer) !Token {
        const start = self.position;
        var has_dot = false;

        while (self.current_char) |ch| {
            if (std.ascii.isDigit(ch)) {
                self.advance();
            } else if (ch == '.' and !has_dot) {
                has_dot = true;
                self.advance();
            } else {
                break;
            }
        }

        return Token{
            .type = .number,
            .value = self.source[start..self.position],
            .position = start,
        };
    }

    fn readIdentifier(self: *Lexer) !Token {
        const start = self.position;

        while (self.current_char) |ch| {
            if (std.ascii.isAlphanumeric(ch) or ch == '_') {
                self.advance();
            } else {
                break;
            }
        }

        return Token{
            .type = .identifier,
            .value = self.source[start..self.position],
            .position = start,
        };
    }

    fn nextToken(self: *Lexer) !Token {
        while (self.current_char) |ch| {
            if (std.ascii.isWhitespace(ch)) {
                self.skipWhitespace();
                continue;
            }

            const position = self.position;

            if (std.ascii.isDigit(ch)) {
                return try self.readNumber();
            }

            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                return try self.readIdentifier();
            }

            self.advance();

            return switch (ch) {
                '+' => Token{ .type = .plus, .value = "+", .position = position },
                '-' => Token{ .type = .minus, .value = "-", .position = position },
                '*' => Token{ .type = .multiply, .value = "*", .position = position },
                '/' => Token{ .type = .divide, .value = "/", .position = position },
                '%' => Token{ .type = .modulo, .value = "%", .position = position },
                '^' => Token{ .type = .power, .value = "^", .position = position },
                '(' => Token{ .type = .lparen, .value = "(", .position = position },
                ')' => Token{ .type = .rparen, .value = ")", .position = position },
                else => error.UnexpectedCharacter,
            };
        }

        return Token{ .type = .eof, .value = "", .position = self.position };
    }

    fn tokenize(self: *Lexer, allocator: Allocator) ![]Token {
        var tokens = std.ArrayList(Token).init(allocator);
        errdefer tokens.deinit();

        while (true) {
            const token = try self.nextToken();
            try tokens.append(token);
            if (token.type == .eof) break;
        }

        return tokens.toOwnedSlice();
    }
};

/// AST Node types
const ASTNode = union(enum) {
    number: f64,
    identifier: []const u8,
    binary_op: *BinaryOp,
    unary_op: *UnaryOp,

    const BinaryOp = struct {
        operator: TokenType,
        left: ASTNode,
        right: ASTNode,
    };

    const UnaryOp = struct {
        operator: TokenType,
        operand: ASTNode,
    };

    fn deinit(self: *ASTNode, allocator: Allocator) void {
        switch (self.*) {
            .binary_op => |op| {
                op.left.deinit(allocator);
                op.right.deinit(allocator);
                allocator.destroy(op);
            },
            .unary_op => |op| {
                op.operand.deinit(allocator);
                allocator.destroy(op);
            },
            else => {},
        }
    }

    fn format(self: ASTNode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .number => |n| try writer.print("{d}", .{n}),
            .identifier => |id| try writer.print("{s}", .{id}),
            .binary_op => |op| try writer.print("({} {} {})", .{ op.left, op.operator.toString(), op.right }),
            .unary_op => |op| try writer.print("({} {})", .{ op.operator.toString(), op.operand }),
        }
    }
};

/// Parser - converts tokens into AST
/// Grammar (operator precedence):
/// expression := term (('+' | '-') term)*
/// term := factor (('*' | '/' | '%') factor)*
/// factor := base ('^' base)*
/// base := NUMBER | IDENTIFIER | '(' expression ')' | ('-' | '+') base
const Parser = struct {
    allocator: Allocator,
    tokens: []const Token,
    position: usize,

    fn init(allocator: Allocator, tokens: []const Token) Parser {
        return .{
            .allocator = allocator,
            .tokens = tokens,
            .position = 0,
        };
    }

    fn currentToken(self: *Parser) Token {
        if (self.position >= self.tokens.len) {
            return self.tokens[self.tokens.len - 1]; // EOF
        }
        return self.tokens[self.position];
    }

    fn advance(self: *Parser) void {
        if (self.position < self.tokens.len) {
            self.position += 1;
        }
    }

    fn expect(self: *Parser, token_type: TokenType) !Token {
        const token = self.currentToken();
        if (token.type != token_type) {
            std.debug.print("Expected {s}, got {s}\n", .{ token_type.toString(), token.type.toString() });
            return error.UnexpectedToken;
        }
        self.advance();
        return token;
    }

    /// Parse entry point
    fn parse(self: *Parser) !ASTNode {
        const result = try self.expression();
        _ = try self.expect(.eof);
        return result;
    }

    /// expression := term (('+' | '-') term)*
    fn expression(self: *Parser) !ASTNode {
        var left = try self.term();

        while (true) {
            const token = self.currentToken();
            if (token.type != .plus and token.type != .minus) break;

            self.advance();

            const right = try self.term();
            const op = try self.allocator.create(ASTNode.BinaryOp);
            op.* = .{
                .operator = token.type,
                .left = left,
                .right = right,
            };
            left = .{ .binary_op = op };
        }

        return left;
    }

    /// term := factor (('*' | '/' | '%') factor)*
    fn term(self: *Parser) !ASTNode {
        var left = try self.factor();

        while (true) {
            const token = self.currentToken();
            if (token.type != .multiply and token.type != .divide and token.type != .modulo) break;

            self.advance();

            const right = try self.factor();
            const op = try self.allocator.create(ASTNode.BinaryOp);
            op.* = .{
                .operator = token.type,
                .left = left,
                .right = right,
            };
            left = .{ .binary_op = op };
        }

        return left;
    }

    /// factor := base ('^' base)*
    fn factor(self: *Parser) !ASTNode {
        var left = try self.base();

        while (true) {
            const token = self.currentToken();
            if (token.type != .power) break;

            self.advance();

            const right = try self.base();
            const op = try self.allocator.create(ASTNode.BinaryOp);
            op.* = .{
                .operator = token.type,
                .left = left,
                .right = right,
            };
            left = .{ .binary_op = op };
        }

        return left;
    }

    /// base := NUMBER | IDENTIFIER | '(' expression ')' | ('-' | '+') base
    fn base(self: *Parser) !ASTNode {
        const token = self.currentToken();

        switch (token.type) {
            .number => {
                self.advance();
                const value = try std.fmt.parseFloat(f64, token.value);
                return .{ .number = value };
            },
            .identifier => {
                self.advance();
                return .{ .identifier = token.value };
            },
            .lparen => {
                self.advance();
                const expr = try self.expression();
                _ = try self.expect(.rparen);
                return expr;
            },
            .minus, .plus => {
                self.advance();
                const operand = try self.base();
                const op = try self.allocator.create(ASTNode.UnaryOp);
                op.* = .{
                    .operator = token.type,
                    .operand = operand,
                };
                return .{ .unary_op = op };
            },
            else => {
                std.debug.print("Unexpected token: {}\n", .{token});
                return error.UnexpectedToken;
            },
        }
    }
};

/// Evaluator - evaluates AST
const Evaluator = struct {
    variables: std.StringHashMap(f64),
    allocator: Allocator,

    fn init(allocator: Allocator) Evaluator {
        return .{
            .variables = std.StringHashMap(f64).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Evaluator) void {
        self.variables.deinit();
    }

    fn setVariable(self: *Evaluator, name: []const u8, value: f64) !void {
        try self.variables.put(name, value);
    }

    fn eval(self: *Evaluator, node: ASTNode) !f64 {
        return switch (node) {
            .number => |n| n,
            .identifier => |id| self.variables.get(id) orelse {
                std.debug.print("Undefined variable: {s}\n", .{id});
                return error.UndefinedVariable;
            },
            .binary_op => |op| {
                const left = try self.eval(op.left);
                const right = try self.eval(op.right);
                return switch (op.operator) {
                    .plus => left + right,
                    .minus => left - right,
                    .multiply => left * right,
                    .divide => if (right != 0) left / right else error.DivisionByZero,
                    .modulo => @mod(left, right),
                    .power => std.math.pow(f64, left, right),
                    else => error.InvalidOperator,
                };
            },
            .unary_op => |op| {
                const operand = try self.eval(op.operand);
                return switch (op.operator) {
                    .minus => -operand,
                    .plus => operand,
                    else => error.InvalidOperator,
                };
            },
        };
    }
};

// ============================================================================
// Tests and Demo
// ============================================================================

fn testExpression(allocator: Allocator, evaluator: *Evaluator, source: []const u8) !void {
    std.debug.print("\n--- Expression: \"{s}\" ---\n", .{source});

    // Lexer
    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    std.debug.print("Tokens: ", .{});
    for (tokens) |token| {
        if (token.type == .eof) break;
        std.debug.print("{} ", .{token});
    }
    std.debug.print("\n", .{});

    // Parser
    var parser = Parser.init(allocator, tokens);
    var ast = try parser.parse();
    defer ast.deinit(allocator);

    std.debug.print("AST: {}\n", .{ast});

    // Evaluator
    const result = try evaluator.eval(ast);
    std.debug.print("Result: {d}\n", .{result});
}

fn runTests(allocator: Allocator) !void {
    std.debug.print("=== Expression Parser Tests ===\n", .{});

    var evaluator = Evaluator.init(allocator);
    defer evaluator.deinit();

    // Set some variables
    try evaluator.setVariable("pi", 3.14159);
    try evaluator.setVariable("x", 10.0);
    try evaluator.setVariable("radius", 5.0);

    // Test basic arithmetic
    try testExpression(allocator, &evaluator, "2 + 3");
    try testExpression(allocator, &evaluator, "10 - 5");
    try testExpression(allocator, &evaluator, "4 * 5");
    try testExpression(allocator, &evaluator, "20 / 4");

    // Test operator precedence
    try testExpression(allocator, &evaluator, "2 + 3 * 4");
    try testExpression(allocator, &evaluator, "10 - 2 * 3");
    try testExpression(allocator, &evaluator, "2 * 3 + 4 * 5");

    // Test parentheses
    try testExpression(allocator, &evaluator, "(2 + 3) * 4");
    try testExpression(allocator, &evaluator, "((10 - 5) * 2 + 3) / 4");

    // Test power operator
    try testExpression(allocator, &evaluator, "2 ^ 3");
    try testExpression(allocator, &evaluator, "2 ^ 3 ^ 2");

    // Test unary operators
    try testExpression(allocator, &evaluator, "-5 + 3");
    try testExpression(allocator, &evaluator, "-(5 + 3)");
    try testExpression(allocator, &evaluator, "+5 - -3");

    // Test variables
    try testExpression(allocator, &evaluator, "x + 5");
    try testExpression(allocator, &evaluator, "pi * radius ^ 2");
    try testExpression(allocator, &evaluator, "2 * pi * radius");

    // Test complex expressions
    try testExpression(allocator, &evaluator, "3 + 4 * 2 / (1 - 5) ^ 2");
    try testExpression(allocator, &evaluator, "(x + 5) * (x - 5)");
}

fn interactiveMode(allocator: Allocator) !void {
    std.debug.print("\n=== Interactive Expression Evaluator ===\n", .{});
    std.debug.print("Enter expressions to evaluate (or 'quit' to exit)\n", .{});
    std.debug.print("Variables: pi=3.14159, e=2.71828\n\n", .{});

    var evaluator = Evaluator.init(allocator);
    defer evaluator.deinit();

    try evaluator.setVariable("pi", 3.14159);
    try evaluator.setVariable("e", 2.71828);

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("> ", .{});
        
        if (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            
            if (trimmed.len == 0) continue;
            if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) break;

            testExpression(allocator, &evaluator, trimmed) catch |err| {
                std.debug.print("Error: {}\n", .{err});
            };
        } else {
            break;
        }
    }

    std.debug.print("\nGoodbye!\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Run automated tests
    try runTests(allocator);

    // Check if we should run interactive mode
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // skip program name
    
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--interactive") or std.mem.eql(u8, arg, "-i")) {
            try interactiveMode(allocator);
        }
    } else {
        std.debug.print("\n=== Tests Complete ===\n", .{});
        std.debug.print("Run with --interactive for interactive mode\n", .{});
    }
}
