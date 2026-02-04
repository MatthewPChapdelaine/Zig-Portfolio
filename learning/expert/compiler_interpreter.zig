//! Complete interpreter implementation with lexer, parser, AST, symbol tables
//! Demonstrates: comptime, allocators, error handling, hash maps, enums with payloads
//! Features: variables, functions, control flow, arithmetic, REPL

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

/// Token types for lexical analysis
const TokenType = enum {
    // Literals
    number,
    identifier,
    string,

    // Keywords
    let,
    fn_keyword,
    if_keyword,
    else_keyword,
    while_keyword,
    return_keyword,
    print,

    // Operators
    plus,
    minus,
    star,
    slash,
    assign,
    equal,
    not_equal,
    less,
    greater,
    less_equal,
    greater_equal,

    // Delimiters
    lparen,
    rparen,
    lbrace,
    rbrace,
    semicolon,
    comma,

    eof,
};

/// Token with location information for error reporting
const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

/// Lexer for tokenizing source code
const Lexer = struct {
    source: []const u8,
    current: usize = 0,
    line: usize = 1,
    column: usize = 1,

    const Self = @This();

    fn init(source: []const u8) Self {
        return .{ .source = source };
    }

    fn isAtEnd(self: *const Self) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Self) u8 {
        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        }
        return c;
    }

    fn peek(self: *const Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *const Self) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;
        _ = self.advance();
        return true;
    }

    fn skipWhitespace(self: *Self) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t', '\n' => _ = self.advance(),
                '/' => {
                    if (self.peekNext() == '/') {
                        while (!self.isAtEnd() and self.peek() != '\n') {
                            _ = self.advance();
                        }
                    } else return;
                },
                else => return,
            }
        }
    }

    fn scanToken(self: *Self, allocator: Allocator) !Token {
        self.skipWhitespace();

        const start = self.current;
        const start_line = self.line;
        const start_column = self.column;

        if (self.isAtEnd()) {
            return Token{
                .type = .eof,
                .lexeme = "",
                .line = self.line,
                .column = self.column,
            };
        }

        const c = self.advance();

        return switch (c) {
            '(' => self.makeToken(.lparen, start, start_line, start_column),
            ')' => self.makeToken(.rparen, start, start_line, start_column),
            '{' => self.makeToken(.lbrace, start, start_line, start_column),
            '}' => self.makeToken(.rbrace, start, start_line, start_column),
            ';' => self.makeToken(.semicolon, start, start_line, start_column),
            ',' => self.makeToken(.comma, start, start_line, start_column),
            '+' => self.makeToken(.plus, start, start_line, start_column),
            '-' => self.makeToken(.minus, start, start_line, start_column),
            '*' => self.makeToken(.star, start, start_line, start_column),
            '/' => self.makeToken(.slash, start, start_line, start_column),
            '=' => if (self.match('='))
                self.makeToken(.equal, start, start_line, start_column)
            else
                self.makeToken(.assign, start, start_line, start_column),
            '!' => if (self.match('='))
                self.makeToken(.not_equal, start, start_line, start_column)
            else
                error.UnexpectedCharacter,
            '<' => if (self.match('='))
                self.makeToken(.less_equal, start, start_line, start_column)
            else
                self.makeToken(.less, start, start_line, start_column),
            '>' => if (self.match('='))
                self.makeToken(.greater_equal, start, start_line, start_column)
            else
                self.makeToken(.greater, start, start_line, start_column),
            '"' => try self.scanString(start, start_line, start_column, allocator),
            else => {
                if (isDigit(c)) {
                    return try self.scanNumber(start, start_line, start_column);
                } else if (isAlpha(c)) {
                    return try self.scanIdentifier(start, start_line, start_column);
                }
                return error.UnexpectedCharacter;
            },
        };
    }

    fn makeToken(self: *Self, token_type: TokenType, start: usize, line: usize, column: usize) Token {
        return Token{
            .type = token_type,
            .lexeme = self.source[start..self.current],
            .line = line,
            .column = column,
        };
    }

    fn scanString(self: *Self, start: usize, line: usize, column: usize, allocator: Allocator) !Token {
        while (!self.isAtEnd() and self.peek() != '"') {
            _ = self.advance();
        }

        if (self.isAtEnd()) return error.UnterminatedString;

        _ = self.advance(); // Closing "

        // Create unescaped string
        const raw = self.source[start + 1 .. self.current - 1];
        const unescaped = try allocator.dupe(u8, raw);

        return Token{
            .type = .string,
            .lexeme = unescaped,
            .line = line,
            .column = column,
        };
    }

    fn scanNumber(self: *Self, start: usize, line: usize, column: usize) !Token {
        while (isDigit(self.peek())) {
            _ = self.advance();
        }

        if (self.peek() == '.' and isDigit(self.peekNext())) {
            _ = self.advance(); // Consume .
            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return self.makeToken(.number, start, line, column);
    }

    fn scanIdentifier(self: *Self, start: usize, line: usize, column: usize) !Token {
        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }

        const text = self.source[start..self.current];
        const token_type = getKeywordType(text);

        return Token{
            .type = token_type,
            .lexeme = text,
            .line = line,
            .column = column,
        };
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isAlphaNumeric(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }

    fn getKeywordType(text: []const u8) TokenType {
        const keywords = comptime blk: {
            var map = std.ComptimeStringMap(TokenType, .{
                .{ "let", .let },
                .{ "fn", .fn_keyword },
                .{ "if", .if_keyword },
                .{ "else", .else_keyword },
                .{ "while", .while_keyword },
                .{ "return", .return_keyword },
                .{ "print", .print },
            });
            break :blk map;
        };

        return keywords.get(text) orelse .identifier;
    }
};

/// Abstract Syntax Tree node types
const AstNode = union(enum) {
    number: f64,
    string: []const u8,
    variable: []const u8,
    binary: *BinaryExpr,
    unary: *UnaryExpr,
    assign: *AssignExpr,
    call: *CallExpr,
    block: *BlockStmt,
    if_stmt: *IfStmt,
    while_stmt: *WhileStmt,
    function: *FunctionStmt,
    return_stmt: *ReturnStmt,
    print_stmt: *AstNode,
    expr_stmt: *AstNode,
};

const BinaryExpr = struct {
    left: AstNode,
    operator: TokenType,
    right: AstNode,
};

const UnaryExpr = struct {
    operator: TokenType,
    operand: AstNode,
};

const AssignExpr = struct {
    name: []const u8,
    value: AstNode,
};

const CallExpr = struct {
    callee: []const u8,
    arguments: []AstNode,
};

const BlockStmt = struct {
    statements: []AstNode,
};

const IfStmt = struct {
    condition: AstNode,
    then_branch: AstNode,
    else_branch: ?AstNode,
};

const WhileStmt = struct {
    condition: AstNode,
    body: AstNode,
};

const FunctionStmt = struct {
    name: []const u8,
    params: [][]const u8,
    body: AstNode,
};

const ReturnStmt = struct {
    value: ?AstNode,
};

/// Parser for constructing AST from tokens
const Parser = struct {
    tokens: []Token,
    current: usize = 0,
    allocator: Allocator,

    const Self = @This();

    fn init(tokens: []Token, allocator: Allocator) Self {
        return .{ .tokens = tokens, .allocator = allocator };
    }

    fn parse(self: *Self) ![]AstNode {
        var statements = ArrayList(AstNode).init(self.allocator);
        errdefer statements.deinit();

        while (!self.isAtEnd()) {
            const stmt = try self.declaration();
            try statements.append(stmt);
        }

        return statements.toOwnedSlice();
    }

    fn declaration(self: *Self) !AstNode {
        if (self.match(.let)) return try self.varDeclaration();
        if (self.match(.fn_keyword)) return try self.function();
        return try self.statement();
    }

    fn varDeclaration(self: *Self) !AstNode {
        const name = try self.consume(.identifier, "Expected variable name");
        _ = try self.consume(.assign, "Expected '=' after variable name");
        const initializer = try self.expression();
        _ = try self.consume(.semicolon, "Expected ';' after variable declaration");

        const assign = try self.allocator.create(AssignExpr);
        assign.* = .{ .name = name.lexeme, .value = initializer };
        return AstNode{ .assign = assign };
    }

    fn function(self: *Self) !AstNode {
        const name = try self.consume(.identifier, "Expected function name");

        _ = try self.consume(.lparen, "Expected '(' after function name");
        var params = ArrayList([]const u8).init(self.allocator);
        errdefer params.deinit();

        if (!self.check(.rparen)) {
            while (true) {
                const param = try self.consume(.identifier, "Expected parameter name");
                try params.append(param.lexeme);
                if (!self.match(.comma)) break;
            }
        }

        _ = try self.consume(.rparen, "Expected ')' after parameters");
        _ = try self.consume(.lbrace, "Expected '{' before function body");

        const body = try self.block();

        const func = try self.allocator.create(FunctionStmt);
        func.* = .{
            .name = name.lexeme,
            .params = try params.toOwnedSlice(),
            .body = body,
        };
        return AstNode{ .function = func };
    }

    fn statement(self: *Self) !AstNode {
        if (self.match(.print)) return try self.printStatement();
        if (self.match(.if_keyword)) return try self.ifStatement();
        if (self.match(.while_keyword)) return try self.whileStatement();
        if (self.match(.return_keyword)) return try self.returnStatement();
        if (self.match(.lbrace)) return try self.block();
        return try self.expressionStatement();
    }

    fn printStatement(self: *Self) !AstNode {
        const value = try self.expression();
        _ = try self.consume(.semicolon, "Expected ';' after value");

        const expr = try self.allocator.create(AstNode);
        expr.* = value;
        return AstNode{ .print_stmt = expr };
    }

    fn ifStatement(self: *Self) !AstNode {
        _ = try self.consume(.lparen, "Expected '(' after 'if'");
        const condition = try self.expression();
        _ = try self.consume(.rparen, "Expected ')' after condition");

        const then_branch = try self.statement();
        var else_branch: ?AstNode = null;

        if (self.match(.else_keyword)) {
            else_branch = try self.statement();
        }

        const if_stmt = try self.allocator.create(IfStmt);
        if_stmt.* = .{
            .condition = condition,
            .then_branch = then_branch,
            .else_branch = else_branch,
        };
        return AstNode{ .if_stmt = if_stmt };
    }

    fn whileStatement(self: *Self) !AstNode {
        _ = try self.consume(.lparen, "Expected '(' after 'while'");
        const condition = try self.expression();
        _ = try self.consume(.rparen, "Expected ')' after condition");

        const body = try self.statement();

        const while_stmt = try self.allocator.create(WhileStmt);
        while_stmt.* = .{ .condition = condition, .body = body };
        return AstNode{ .while_stmt = while_stmt };
    }

    fn returnStatement(self: *Self) !AstNode {
        var value: ?AstNode = null;
        if (!self.check(.semicolon)) {
            value = try self.expression();
        }
        _ = try self.consume(.semicolon, "Expected ';' after return value");

        const ret = try self.allocator.create(ReturnStmt);
        ret.* = .{ .value = value };
        return AstNode{ .return_stmt = ret };
    }

    fn block(self: *Self) !AstNode {
        var statements = ArrayList(AstNode).init(self.allocator);
        errdefer statements.deinit();

        while (!self.check(.rbrace) and !self.isAtEnd()) {
            const stmt = try self.declaration();
            try statements.append(stmt);
        }

        _ = try self.consume(.rbrace, "Expected '}' after block");

        const block_stmt = try self.allocator.create(BlockStmt);
        block_stmt.* = .{ .statements = try statements.toOwnedSlice() };
        return AstNode{ .block = block_stmt };
    }

    fn expressionStatement(self: *Self) !AstNode {
        const expr = try self.expression();
        _ = try self.consume(.semicolon, "Expected ';' after expression");

        const expr_stmt = try self.allocator.create(AstNode);
        expr_stmt.* = expr;
        return AstNode{ .expr_stmt = expr_stmt };
    }

    fn expression(self: *Self) !AstNode {
        return try self.assignment();
    }

    fn assignment(self: *Self) !AstNode {
        const expr = try self.equality();

        if (self.match(.assign)) {
            const value = try self.assignment();

            switch (expr) {
                .variable => |name| {
                    const assign = try self.allocator.create(AssignExpr);
                    assign.* = .{ .name = name, .value = value };
                    return AstNode{ .assign = assign };
                },
                else => return error.InvalidAssignmentTarget,
            }
        }

        return expr;
    }

    fn equality(self: *Self) !AstNode {
        var expr = try self.comparison();

        while (self.matchAny(&[_]TokenType{ .equal, .not_equal })) {
            const operator = self.previous().type;
            const right = try self.comparison();

            const binary = try self.allocator.create(BinaryExpr);
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = AstNode{ .binary = binary };
        }

        return expr;
    }

    fn comparison(self: *Self) !AstNode {
        var expr = try self.term();

        while (self.matchAny(&[_]TokenType{ .greater, .greater_equal, .less, .less_equal })) {
            const operator = self.previous().type;
            const right = try self.term();

            const binary = try self.allocator.create(BinaryExpr);
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = AstNode{ .binary = binary };
        }

        return expr;
    }

    fn term(self: *Self) !AstNode {
        var expr = try self.factor();

        while (self.matchAny(&[_]TokenType{ .plus, .minus })) {
            const operator = self.previous().type;
            const right = try self.factor();

            const binary = try self.allocator.create(BinaryExpr);
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = AstNode{ .binary = binary };
        }

        return expr;
    }

    fn factor(self: *Self) !AstNode {
        var expr = try self.unary();

        while (self.matchAny(&[_]TokenType{ .star, .slash })) {
            const operator = self.previous().type;
            const right = try self.unary();

            const binary = try self.allocator.create(BinaryExpr);
            binary.* = .{ .left = expr, .operator = operator, .right = right };
            expr = AstNode{ .binary = binary };
        }

        return expr;
    }

    fn unary(self: *Self) !AstNode {
        if (self.matchAny(&[_]TokenType{.minus})) {
            const operator = self.previous().type;
            const right = try self.unary();

            const unary = try self.allocator.create(UnaryExpr);
            unary.* = .{ .operator = operator, .operand = right };
            return AstNode{ .unary = unary };
        }

        return try self.call();
    }

    fn call(self: *Self) !AstNode {
        var expr = try self.primary();

        if (self.match(.lparen)) {
            const callee = switch (expr) {
                .variable => |name| name,
                else => return error.InvalidCallTarget,
            };

            var arguments = ArrayList(AstNode).init(self.allocator);
            errdefer arguments.deinit();

            if (!self.check(.rparen)) {
                while (true) {
                    try arguments.append(try self.expression());
                    if (!self.match(.comma)) break;
                }
            }

            _ = try self.consume(.rparen, "Expected ')' after arguments");

            const call = try self.allocator.create(CallExpr);
            call.* = .{ .callee = callee, .arguments = try arguments.toOwnedSlice() };
            expr = AstNode{ .call = call };
        }

        return expr;
    }

    fn primary(self: *Self) !AstNode {
        if (self.match(.number)) {
            const value = try std.fmt.parseFloat(f64, self.previous().lexeme);
            return AstNode{ .number = value };
        }

        if (self.match(.string)) {
            return AstNode{ .string = self.previous().lexeme };
        }

        if (self.match(.identifier)) {
            return AstNode{ .variable = self.previous().lexeme };
        }

        if (self.match(.lparen)) {
            const expr = try self.expression();
            _ = try self.consume(.rparen, "Expected ')' after expression");
            return expr;
        }

        return error.UnexpectedToken;
    }

    fn match(self: *Self, token_type: TokenType) bool {
        if (self.check(token_type)) {
            self.advance();
            return true;
        }
        return false;
    }

    fn matchAny(self: *Self, types: []const TokenType) bool {
        for (types) |t| {
            if (self.check(t)) {
                self.advance();
                return true;
            }
        }
        return false;
    }

    fn check(self: *Self, token_type: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == token_type;
    }

    fn advance(self: *Self) void {
        if (!self.isAtEnd()) self.current += 1;
    }

    fn isAtEnd(self: *Self) bool {
        return self.peek().type == .eof;
    }

    fn peek(self: *Self) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *Self) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Self, token_type: TokenType, message: []const u8) !Token {
        if (self.check(token_type)) {
            self.advance();
            return self.previous();
        }
        std.debug.print("Parse error: {s}\n", .{message});
        return error.ParseError;
    }
};

/// Runtime value types
const Value = union(enum) {
    number: f64,
    string: []const u8,
    function: Function,
    nil: void,

    fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .number => |n| try writer.print("{d}", .{n}),
            .string => |s| try writer.print("{s}", .{s}),
            .function => |f| try writer.print("<fn {s}>", .{f.name}),
            .nil => try writer.writeAll("nil"),
        }
    }
};

const Function = struct {
    name: []const u8,
    params: [][]const u8,
    body: AstNode,
};

/// Environment for variable and function storage with scoping
const Environment = struct {
    values: StringHashMap(Value),
    enclosing: ?*Environment,
    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator, enclosing: ?*Environment) !*Self {
        const env = try allocator.create(Self);
        env.* = .{
            .values = StringHashMap(Value).init(allocator),
            .enclosing = enclosing,
            .allocator = allocator,
        };
        return env;
    }

    fn deinit(self: *Self) void {
        self.values.deinit();
        self.allocator.destroy(self);
    }

    fn define(self: *Self, name: []const u8, value: Value) !void {
        try self.values.put(name, value);
    }

    fn get(self: *Self, name: []const u8) !Value {
        if (self.values.get(name)) |value| {
            return value;
        }
        if (self.enclosing) |parent| {
            return try parent.get(name);
        }
        std.debug.print("Undefined variable: {s}\n", .{name});
        return error.UndefinedVariable;
    }

    fn assign(self: *Self, name: []const u8, value: Value) !void {
        if (self.values.contains(name)) {
            try self.values.put(name, value);
            return;
        }
        if (self.enclosing) |parent| {
            try parent.assign(name, value);
            return;
        }
        std.debug.print("Undefined variable: {s}\n", .{name});
        return error.UndefinedVariable;
    }
};

/// Interpreter for executing AST
const Interpreter = struct {
    allocator: Allocator,
    globals: *Environment,
    environment: *Environment,
    return_value: ?Value = null,

    const Self = @This();

    fn init(allocator: Allocator) !Self {
        const globals = try Environment.init(allocator, null);
        return .{
            .allocator = allocator,
            .globals = globals,
            .environment = globals,
        };
    }

    fn deinit(self: *Self) void {
        self.globals.deinit();
    }

    fn interpret(self: *Self, statements: []AstNode) !void {
        for (statements) |stmt| {
            try self.execute(stmt);
            if (self.return_value != null) break;
        }
    }

    fn execute(self: *Self, node: AstNode) error{ OutOfMemory, UndefinedVariable, DivisionByZero, TypeError, InvalidArguments, Return }!void {
        switch (node) {
            .expr_stmt => |expr| _ = try self.evaluate(expr.*),
            .print_stmt => |expr| {
                const value = try self.evaluate(expr.*);
                std.debug.print("{}\n", .{value});
            },
            .block => |block| {
                const previous = self.environment;
                self.environment = try Environment.init(self.allocator, previous);
                defer {
                    self.environment.deinit();
                    self.environment = previous;
                }

                for (block.statements) |stmt| {
                    try self.execute(stmt);
                    if (self.return_value != null) break;
                }
            },
            .if_stmt => |if_stmt| {
                const condition = try self.evaluate(if_stmt.condition);
                if (self.isTruthy(condition)) {
                    try self.execute(if_stmt.then_branch);
                } else if (if_stmt.else_branch) |else_branch| {
                    try self.execute(else_branch);
                }
            },
            .while_stmt => |while_stmt| {
                while (true) {
                    const condition = try self.evaluate(while_stmt.condition);
                    if (!self.isTruthy(condition)) break;
                    try self.execute(while_stmt.body);
                    if (self.return_value != null) break;
                }
            },
            .function => |func| {
                const value = Value{ .function = .{
                    .name = func.name,
                    .params = func.params,
                    .body = func.body,
                } };
                try self.environment.define(func.name, value);
            },
            .return_stmt => |ret| {
                if (ret.value) |val| {
                    self.return_value = try self.evaluate(val);
                } else {
                    self.return_value = Value{ .nil = {} };
                }
                return error.Return;
            },
            .assign => |assign| {
                const value = try self.evaluate(assign.value);
                if (self.environment.values.contains(assign.name)) {
                    try self.environment.assign(assign.name, value);
                } else {
                    try self.environment.define(assign.name, value);
                }
            },
            else => _ = try self.evaluate(node),
        }
    }

    fn evaluate(self: *Self, node: AstNode) error{ OutOfMemory, UndefinedVariable, DivisionByZero, TypeError, InvalidArguments, Return }!Value {
        switch (node) {
            .number => |n| return Value{ .number = n },
            .string => |s| return Value{ .string = s },
            .variable => |name| return try self.environment.get(name),
            .binary => |binary| {
                const left = try self.evaluate(binary.left);
                const right = try self.evaluate(binary.right);
                return try self.evalBinary(left, binary.operator, right);
            },
            .unary => |unary| {
                const operand = try self.evaluate(unary.operand);
                return try self.evalUnary(unary.operator, operand);
            },
            .assign => |assign| {
                const value = try self.evaluate(assign.value);
                try self.environment.assign(assign.name, value);
                return value;
            },
            .call => |call| {
                const callee = try self.environment.get(call.callee);
                switch (callee) {
                    .function => |func| {
                        if (func.params.len != call.arguments.len) {
                            return error.InvalidArguments;
                        }

                        const previous = self.environment;
                        self.environment = try Environment.init(self.allocator, self.globals);
                        defer {
                            self.environment.deinit();
                            self.environment = previous;
                        }

                        for (func.params, call.arguments) |param, arg| {
                            const value = try self.evaluate(arg);
                            try self.environment.define(param, value);
                        }

                        self.execute(func.body) catch |err| {
                            if (err == error.Return) {
                                const ret_val = self.return_value.?;
                                self.return_value = null;
                                return ret_val;
                            }
                            return err;
                        };

                        if (self.return_value) |ret_val| {
                            self.return_value = null;
                            return ret_val;
                        }

                        return Value{ .nil = {} };
                    },
                    else => return error.TypeError,
                }
            },
            else => return Value{ .nil = {} },
        }
    }

    fn evalBinary(self: *Self, left: Value, op: TokenType, right: Value) !Value {
        _ = self;
        if (left == .number and right == .number) {
            const l = left.number;
            const r = right.number;
            return switch (op) {
                .plus => Value{ .number = l + r },
                .minus => Value{ .number = l - r },
                .star => Value{ .number = l * r },
                .slash => blk: {
                    if (r == 0) return error.DivisionByZero;
                    break :blk Value{ .number = l / r };
                },
                .equal => Value{ .number = if (l == r) 1 else 0 },
                .not_equal => Value{ .number = if (l != r) 1 else 0 },
                .less => Value{ .number = if (l < r) 1 else 0 },
                .less_equal => Value{ .number = if (l <= r) 1 else 0 },
                .greater => Value{ .number = if (l > r) 1 else 0 },
                .greater_equal => Value{ .number = if (l >= r) 1 else 0 },
                else => error.TypeError,
            };
        }
        return error.TypeError;
    }

    fn evalUnary(self: *Self, op: TokenType, operand: Value) !Value {
        _ = self;
        if (operand == .number) {
            return switch (op) {
                .minus => Value{ .number = -operand.number },
                else => error.TypeError,
            };
        }
        return error.TypeError;
    }

    fn isTruthy(self: *Self, value: Value) bool {
        _ = self;
        return switch (value) {
            .nil => false,
            .number => |n| n != 0,
            else => true,
        };
    }
};

/// REPL for interactive programming
fn runRepl(allocator: Allocator) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var interpreter = try Interpreter.init(allocator);
    defer interpreter.deinit();

    var buffer: [1024]u8 = undefined;

    try stdout.writeAll("Interactive Interpreter REPL v1.0\n");
    try stdout.writeAll("Type 'exit' to quit\n\n");

    while (true) {
        try stdout.writeAll(">> ");
        if (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;
            if (std.mem.eql(u8, trimmed, "exit")) break;

            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            var lexer = Lexer.init(trimmed);
            var tokens = ArrayList(Token).init(arena_allocator);

            while (true) {
                const token = lexer.scanToken(arena_allocator) catch |err| {
                    try stdout.print("Lexer error: {}\n", .{err});
                    break;
                };
                try tokens.append(token);
                if (token.type == .eof) break;
            }

            var parser = Parser.init(try tokens.toOwnedSlice(), arena_allocator);
            const statements = parser.parse() catch |err| {
                try stdout.print("Parser error: {}\n", .{err});
                continue;
            };

            interpreter.interpret(statements) catch |err| {
                if (err != error.Return) {
                    try stdout.print("Runtime error: {}\n", .{err});
                }
            };
        } else break;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Complete Interpreter Demo ===\n\n", .{});

    // Example program demonstrating all features
    const program =
        \\// Fibonacci function
        \\fn fib(n) {
        \\  if (n <= 1) {
        \\    return n;
        \\  }
        \\  return fib(n - 1) + fib(n - 2);
        \\}
        \\
        \\// Test variables and arithmetic
        \\let x = 10;
        \\let y = 20;
        \\print x + y;
        \\
        \\// Test control flow
        \\let i = 0;
        \\while (i < 5) {
        \\  print fib(i);
        \\  i = i + 1;
        \\}
        \\
        \\// Test factorial
        \\fn factorial(n) {
        \\  if (n <= 1) {
        \\    return 1;
        \\  }
        \\  return n * factorial(n - 1);
        \\}
        \\
        \\print factorial(5);
    ;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Lexical analysis
    var lexer = Lexer.init(program);
    var tokens = ArrayList(Token).init(arena_allocator);

    while (true) {
        const token = try lexer.scanToken(arena_allocator);
        try tokens.append(token);
        if (token.type == .eof) break;
    }

    std.debug.print("Lexed {} tokens\n\n", .{tokens.items.len});

    // Parsing
    var parser = Parser.init(try tokens.toOwnedSlice(), arena_allocator);
    const statements = try parser.parse();

    std.debug.print("Parsed {} statements\n\n", .{statements.len});

    // Interpretation
    std.debug.print("Executing program:\n", .{});
    std.debug.print("==================\n", .{});

    var interpreter = try Interpreter.init(allocator);
    defer interpreter.deinit();

    try interpreter.interpret(statements);

    std.debug.print("\n==================\n\n", .{});

    // Start REPL
    std.debug.print("Starting REPL...\n\n", .{});
    try runRepl(allocator);
}
