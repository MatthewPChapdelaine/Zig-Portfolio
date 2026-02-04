//! Simple ORM/Database Abstraction Layer with Query Builder
//! Build: zig build-exe database_orm.zig
//! Run: ./database_orm

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Database error types
const DatabaseError = error{
    ConnectionFailed,
    QueryFailed,
    RecordNotFound,
    DuplicateKey,
    InvalidQuery,
};

/// SQL Operator for where clauses
const Operator = enum {
    eq, // =
    ne, // !=
    gt, // >
    gte, // >=
    lt, // <
    lte, // <=
    like, // LIKE

    fn toString(self: Operator) []const u8 {
        return switch (self) {
            .eq => "=",
            .ne => "!=",
            .gt => ">",
            .gte => ">=",
            .lt => "<",
            .lte => "<=",
            .like => "LIKE",
        };
    }
};

/// Where clause condition
const WhereCondition = struct {
    field: []const u8,
    operator: Operator,
    value: []const u8,
};

/// Join type
const JoinType = enum {
    inner,
    left,
    right,

    fn toString(self: JoinType) []const u8 {
        return switch (self) {
            .inner => "INNER JOIN",
            .left => "LEFT JOIN",
            .right => "RIGHT JOIN",
        };
    }
};

/// Join clause
const JoinClause = struct {
    join_type: JoinType,
    table: []const u8,
    on_condition: []const u8,
};

/// Query Builder - Fluent interface for building SQL queries
const QueryBuilder = struct {
    allocator: Allocator,
    table: ?[]const u8,
    select_fields: std.ArrayList([]const u8),
    where_conditions: std.ArrayList(WhereCondition),
    joins: std.ArrayList(JoinClause),
    order_by_field: ?[]const u8,
    order_by_desc: bool,
    limit_value: ?usize,
    offset_value: ?usize,

    fn init(allocator: Allocator) QueryBuilder {
        return .{
            .allocator = allocator,
            .table = null,
            .select_fields = std.ArrayList([]const u8).init(allocator),
            .where_conditions = std.ArrayList(WhereCondition).init(allocator),
            .joins = std.ArrayList(JoinClause).init(allocator),
            .order_by_field = null,
            .order_by_desc = false,
            .limit_value = null,
            .offset_value = null,
        };
    }

    fn deinit(self: *QueryBuilder) void {
        self.select_fields.deinit();
        self.where_conditions.deinit();
        self.joins.deinit();
    }

    fn from(self: *QueryBuilder, table_name: []const u8) *QueryBuilder {
        self.table = table_name;
        return self;
    }

    fn select(self: *QueryBuilder, fields: []const []const u8) !*QueryBuilder {
        for (fields) |field| {
            try self.select_fields.append(field);
        }
        return self;
    }

    fn where(self: *QueryBuilder, field: []const u8, operator: Operator, value: []const u8) !*QueryBuilder {
        try self.where_conditions.append(.{
            .field = field,
            .operator = operator,
            .value = value,
        });
        return self;
    }

    fn join(self: *QueryBuilder, join_type: JoinType, table_name: []const u8, on_condition: []const u8) !*QueryBuilder {
        try self.joins.append(.{
            .join_type = join_type,
            .table = table_name,
            .on_condition = on_condition,
        });
        return self;
    }

    fn orderBy(self: *QueryBuilder, field: []const u8, desc: bool) *QueryBuilder {
        self.order_by_field = field;
        self.order_by_desc = desc;
        return self;
    }

    fn limit(self: *QueryBuilder, limit_val: usize) *QueryBuilder {
        self.limit_value = limit_val;
        return self;
    }

    fn offset(self: *QueryBuilder, offset_val: usize) *QueryBuilder {
        self.offset_value = offset_val;
        return self;
    }

    fn build(self: *QueryBuilder) ![]const u8 {
        var query = std.ArrayList(u8).init(self.allocator);
        errdefer query.deinit();
        const writer = query.writer();

        // SELECT clause
        try writer.writeAll("SELECT ");
        if (self.select_fields.items.len > 0) {
            for (self.select_fields.items, 0..) |field, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(field);
            }
        } else {
            try writer.writeAll("*");
        }

        // FROM clause
        if (self.table) |t| {
            try writer.print(" FROM {s}", .{t});
        } else {
            return error.InvalidQuery;
        }

        // JOIN clauses
        for (self.joins.items) |join_clause| {
            try writer.print(" {s} {s} ON {s}", .{
                join_clause.join_type.toString(),
                join_clause.table,
                join_clause.on_condition,
            });
        }

        // WHERE clause
        if (self.where_conditions.items.len > 0) {
            try writer.writeAll(" WHERE ");
            for (self.where_conditions.items, 0..) |condition, i| {
                if (i > 0) try writer.writeAll(" AND ");
                try writer.print("{s} {s} '{s}'", .{
                    condition.field,
                    condition.operator.toString(),
                    condition.value,
                });
            }
        }

        // ORDER BY clause
        if (self.order_by_field) |field| {
            try writer.print(" ORDER BY {s}", .{field});
            if (self.order_by_desc) {
                try writer.writeAll(" DESC");
            }
        }

        // LIMIT clause
        if (self.limit_value) |lim| {
            try writer.print(" LIMIT {}", .{lim});
        }

        // OFFSET clause
        if (self.offset_value) |off| {
            try writer.print(" OFFSET {}", .{off});
        }

        return query.toOwnedSlice();
    }
};

/// Generic Model trait simulation using comptime
fn Model(comptime T: type) type {
    return struct {
        pub fn tableName() []const u8 {
            return if (@hasDecl(T, "table_name")) T.table_name else @typeName(T);
        }

        pub fn fields() []const []const u8 {
            const fields_info = @typeInfo(T).Struct.fields;
            comptime var field_names: [fields_info.len][]const u8 = undefined;
            inline for (fields_info, 0..) |field, i| {
                field_names[i] = field.name;
            }
            return &field_names;
        }
    };
}

/// Repository pattern for CRUD operations
fn Repository(comptime T: type) type {
    return struct {
        const Self = @This();
        
        allocator: Allocator,
        db: *Database,

        pub fn init(allocator: Allocator, db: *Database) Self {
            return .{
                .allocator = allocator,
                .db = db,
            };
        }

        /// Find record by ID
        pub fn findById(self: *Self, id: i64) !?T {
            var qb = QueryBuilder.init(self.allocator);
            defer qb.deinit();

            const id_str = try std.fmt.allocPrint(self.allocator, "{}", .{id});
            defer self.allocator.free(id_str);

            const query = try qb
                .from(Model(T).tableName())
                .where("id", .eq, id_str)
                .limit(1)
                .build();
            defer self.allocator.free(query);

            const results = try self.db.execute(query);
            if (results.len > 0) {
                return self.parseResult(results[0]);
            }
            return null;
        }

        /// Find all records
        pub fn findAll(self: *Self) ![]T {
            var qb = QueryBuilder.init(self.allocator);
            defer qb.deinit();

            const query = try qb.from(Model(T).tableName()).build();
            defer self.allocator.free(query);

            const results = try self.db.execute(query);
            return self.parseResults(results);
        }

        /// Find with conditions
        pub fn find(self: *Self, qb: *QueryBuilder) ![]T {
            const query = try qb.build();
            defer self.allocator.free(query);

            const results = try self.db.execute(query);
            return self.parseResults(results);
        }

        /// Create new record
        pub fn create(self: *Self, record: T) !T {
            const query = try self.buildInsertQuery(record);
            defer self.allocator.free(query);

            _ = try self.db.execute(query);
            return record;
        }

        /// Update record
        pub fn update(self: *Self, id: i64, record: T) !T {
            const query = try self.buildUpdateQuery(id, record);
            defer self.allocator.free(query);

            _ = try self.db.execute(query);
            return record;
        }

        /// Delete record
        pub fn delete(self: *Self, id: i64) !void {
            const id_str = try std.fmt.allocPrint(self.allocator, "{}", .{id});
            defer self.allocator.free(id_str);

            const query = try std.fmt.allocPrint(
                self.allocator,
                "DELETE FROM {s} WHERE id = {s}",
                .{ Model(T).tableName(), id_str }
            );
            defer self.allocator.free(query);

            _ = try self.db.execute(query);
        }

        fn buildInsertQuery(self: *Self, record: T) ![]const u8 {
            _ = record;
            return try std.fmt.allocPrint(
                self.allocator,
                "INSERT INTO {s} (field1, field2) VALUES ('value1', 'value2')",
                .{Model(T).tableName()}
            );
        }

        fn buildUpdateQuery(self: *Self, id: i64, record: T) ![]const u8 {
            _ = record;
            return try std.fmt.allocPrint(
                self.allocator,
                "UPDATE {s} SET field1 = 'value1' WHERE id = {}",
                .{ Model(T).tableName(), id }
            );
        }

        fn parseResult(self: *Self, result: []const u8) !T {
            _ = self;
            _ = result;
            // In a real implementation, parse result into T
            return undefined;
        }

        fn parseResults(self: *Self, results: [][]const u8) ![]T {
            const parsed = try self.allocator.alloc(T, results.len);
            for (results, 0..) |result, i| {
                parsed[i] = try self.parseResult(result);
            }
            return parsed;
        }
    };
}

/// Mock Database implementation
const Database = struct {
    allocator: Allocator,
    connected: bool,
    query_log: std.ArrayList([]const u8),

    fn init(allocator: Allocator) Database {
        return .{
            .allocator = allocator,
            .connected = false,
            .query_log = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Database) void {
        for (self.query_log.items) |query| {
            self.allocator.free(query);
        }
        self.query_log.deinit();
    }

    fn connect(self: *Database, _connection_string: []const u8) !void {
        self.connected = true;
        std.log.info("Database connected", .{});
    }

    fn disconnect(self: *Database) void {
        self.connected = false;
        std.log.info("Database disconnected", .{});
    }

    fn execute(self: *Database, query: []const u8) ![][]const u8 {
        if (!self.connected) return error.ConnectionFailed;

        // Log query
        const query_copy = try self.allocator.dupe(u8, query);
        try self.query_log.append(query_copy);
        
        std.log.info("Executing query: {s}", .{query});

        // Mock result
        const result = try self.allocator.alloc([]const u8, 0);
        return result;
    }

    fn getQueryLog(self: *Database) [][]const u8 {
        return self.query_log.items;
    }
};

/// Example entity models
const User = struct {
    pub const table_name = "users";
    
    id: i64,
    name: []const u8,
    email: []const u8,
    age: u32,
    created_at: []const u8,
};

const Post = struct {
    pub const table_name = "posts";
    
    id: i64,
    user_id: i64,
    title: []const u8,
    content: []const u8,
    published: bool,
};

/// Migration system
const Migration = struct {
    version: []const u8,
    up_sql: []const u8,
    down_sql: []const u8,
};

const Migrator = struct {
    allocator: Allocator,
    db: *Database,
    migrations: std.ArrayList(Migration),

    fn init(allocator: Allocator, db: *Database) Migrator {
        return .{
            .allocator = allocator,
            .db = db,
            .migrations = std.ArrayList(Migration).init(allocator),
        };
    }

    fn deinit(self: *Migrator) void {
        self.migrations.deinit();
    }

    fn addMigration(self: *Migrator, version: []const u8, up_sql: []const u8, down_sql: []const u8) !void {
        try self.migrations.append(.{
            .version = version,
            .up_sql = up_sql,
            .down_sql = down_sql,
        });
    }

    fn migrate(self: *Migrator) !void {
        std.log.info("Running {} migrations...", .{self.migrations.items.len});
        for (self.migrations.items) |migration| {
            std.log.info("Applying migration: {s}", .{migration.version});
            _ = try self.db.execute(migration.up_sql);
        }
    }

    fn rollback(self: *Migrator) !void {
        if (self.migrations.items.len == 0) return;
        
        const last_migration = self.migrations.items[self.migrations.items.len - 1];
        std.log.info("Rolling back migration: {s}", .{last_migration.version});
        _ = try self.db.execute(last_migration.down_sql);
    }
};

// ============================================================================
// Demo
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Database ORM Demo ===\n\n", .{});

    // Initialize database
    var db = Database.init(allocator);
    defer db.deinit();
    try db.connect("postgresql://localhost:5432/mydb");
    defer db.disconnect();

    // Query Builder examples
    std.debug.print("1. Query Builder Examples:\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // Simple SELECT
    var qb1 = QueryBuilder.init(allocator);
    defer qb1.deinit();
    const query1 = try qb1
        .from("users")
        .select(&[_][]const u8{ "id", "name", "email" })
        .build();
    defer allocator.free(query1);
    std.debug.print("Query 1: {s}\n\n", .{query1});

    // SELECT with WHERE
    var qb2 = QueryBuilder.init(allocator);
    defer qb2.deinit();
    const query2 = try qb2
        .from("users")
        .where("age", .gte, "18")
        .where("name", .like, "John%")
        .orderBy("created_at", true)
        .limit(10)
        .build();
    defer allocator.free(query2);
    std.debug.print("Query 2: {s}\n\n", .{query2});

    // SELECT with JOIN
    var qb3 = QueryBuilder.init(allocator);
    defer qb3.deinit();
    const query3 = try qb3
        .from("users")
        .select(&[_][]const u8{ "users.name", "posts.title" })
        .join(.inner, "posts", "users.id = posts.user_id")
        .where("posts.published", .eq, "true")
        .orderBy("posts.created_at", true)
        .limit(5)
        .offset(10)
        .build();
    defer allocator.free(query3);
    std.debug.print("Query 3: {s}\n\n", .{query3});

    // Repository pattern
    std.debug.print("2. Repository Pattern (Mock):\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var user_repo = Repository(User).init(allocator, &db);
    
    const new_user = User{
        .id = 1,
        .name = "Alice Johnson",
        .email = "alice@example.com",
        .age = 30,
        .created_at = "2024-01-01",
    };

    _ = try user_repo.create(new_user);
    std.debug.print("Created user: {s}\n", .{new_user.name});

    // Migrations
    std.debug.print("\n3. Migration System:\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var migrator = Migrator.init(allocator, &db);
    defer migrator.deinit();

    try migrator.addMigration(
        "001_create_users_table",
        "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(255), email VARCHAR(255), age INT, created_at TIMESTAMP)",
        "DROP TABLE users"
    );

    try migrator.addMigration(
        "002_create_posts_table",
        "CREATE TABLE posts (id SERIAL PRIMARY KEY, user_id INT, title VARCHAR(255), content TEXT, published BOOLEAN)",
        "DROP TABLE posts"
    );

    try migrator.migrate();

    // Show query log
    std.debug.print("\n4. Query Log:\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    const queries = db.getQueryLog();
    for (queries, 0..) |query, i| {
        std.debug.print("{}. {s}\n", .{ i + 1, query });
    }

    std.debug.print("\n=== ORM Demo Complete ===\n", .{});
}
