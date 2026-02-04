//! Graph Algorithms - BFS, DFS, Dijkstra, Topological Sort, Cycle Detection
//! Build: zig build-exe graph_algorithms.zig
//! Run: ./graph_algorithms

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Graph representation using adjacency list
const Graph = struct {
    const Self = @This();
    
    allocator: Allocator,
    vertices: usize,
    adjacency_list: std.ArrayList(std.ArrayList(Edge)),
    is_directed: bool,

    const Edge = struct {
        to: usize,
        weight: i32,
    };

    fn init(allocator: Allocator, vertices: usize, is_directed: bool) !Self {
        var adj_list = std.ArrayList(std.ArrayList(Edge)).init(allocator);
        
        var i: usize = 0;
        while (i < vertices) : (i += 1) {
            try adj_list.append(std.ArrayList(Edge).init(allocator));
        }

        return Self{
            .allocator = allocator,
            .vertices = vertices,
            .adjacency_list = adj_list,
            .is_directed = is_directed,
        };
    }

    fn deinit(self: *Self) void {
        for (self.adjacency_list.items) |*list| {
            list.deinit();
        }
        self.adjacency_list.deinit();
    }

    fn addEdge(self: *Self, from: usize, to: usize, weight: i32) !void {
        try self.adjacency_list.items[from].append(.{ .to = to, .weight = weight });
        if (!self.is_directed) {
            try self.adjacency_list.items[to].append(.{ .to = from, .weight = weight });
        }
    }

    fn getNeighbors(self: *Self, vertex: usize) []const Edge {
        return self.adjacency_list.items[vertex].items;
    }

    fn print(self: *Self) void {
        std.debug.print("Graph (vertices: {}, directed: {}):\n", .{ self.vertices, self.is_directed });
        for (self.adjacency_list.items, 0..) |edges, i| {
            std.debug.print("  {} -> ", .{i});
            for (edges.items, 0..) |edge, j| {
                if (j > 0) std.debug.print(", ", .{});
                std.debug.print("{}(w:{})", .{ edge.to, edge.weight });
            }
            std.debug.print("\n", .{});
        }
    }
};

/// Breadth-First Search (BFS)
const BFS = struct {
    fn search(allocator: Allocator, graph: *Graph, start: usize) !std.ArrayList(usize) {
        var visited = try allocator.alloc(bool, graph.vertices);
        defer allocator.free(visited);
        @memset(visited, false);

        var result = std.ArrayList(usize).init(allocator);
        var queue = std.ArrayList(usize).init(allocator);
        defer queue.deinit();

        try queue.append(start);
        visited[start] = true;

        while (queue.items.len > 0) {
            const vertex = queue.orderedRemove(0);
            try result.append(vertex);

            for (graph.getNeighbors(vertex)) |edge| {
                if (!visited[edge.to]) {
                    visited[edge.to] = true;
                    try queue.append(edge.to);
                }
            }
        }

        return result;
    }

    /// Find shortest path in unweighted graph
    fn shortestPath(allocator: Allocator, graph: *Graph, start: usize, end: usize) !?[]usize {
        var visited = try allocator.alloc(bool, graph.vertices);
        defer allocator.free(visited);
        @memset(visited, false);

        var parent = try allocator.alloc(?usize, graph.vertices);
        defer allocator.free(parent);
        @memset(parent, null);

        var queue = std.ArrayList(usize).init(allocator);
        defer queue.deinit();

        try queue.append(start);
        visited[start] = true;

        while (queue.items.len > 0) {
            const vertex = queue.orderedRemove(0);
            if (vertex == end) break;

            for (graph.getNeighbors(vertex)) |edge| {
                if (!visited[edge.to]) {
                    visited[edge.to] = true;
                    parent[edge.to] = vertex;
                    try queue.append(edge.to);
                }
            }
        }

        if (!visited[end]) return null;

        // Reconstruct path
        var path = std.ArrayList(usize).init(allocator);
        var current: ?usize = end;
        while (current) |c| {
            try path.insert(0, c);
            current = parent[c];
        }

        return path.toOwnedSlice();
    }
};

/// Depth-First Search (DFS)
const DFS = struct {
    fn search(allocator: Allocator, graph: *Graph, start: usize) !std.ArrayList(usize) {
        var visited = try allocator.alloc(bool, graph.vertices);
        defer allocator.free(visited);
        @memset(visited, false);

        var result = std.ArrayList(usize).init(allocator);
        try searchRecursive(graph, start, visited, &result);
        return result;
    }

    fn searchRecursive(graph: *Graph, vertex: usize, visited: []bool, result: *std.ArrayList(usize)) !void {
        visited[vertex] = true;
        try result.append(vertex);

        for (graph.getNeighbors(vertex)) |edge| {
            if (!visited[edge.to]) {
                try searchRecursive(graph, edge.to, visited, result);
            }
        }
    }

    fn searchIterative(allocator: Allocator, graph: *Graph, start: usize) !std.ArrayList(usize) {
        var visited = try allocator.alloc(bool, graph.vertices);
        defer allocator.free(visited);
        @memset(visited, false);

        var result = std.ArrayList(usize).init(allocator);
        var stack = std.ArrayList(usize).init(allocator);
        defer stack.deinit();

        try stack.append(start);

        while (stack.items.len > 0) {
            const vertex = stack.pop();
            
            if (!visited[vertex]) {
                visited[vertex] = true;
                try result.append(vertex);

                // Add neighbors in reverse order for correct DFS order
                var i = graph.getNeighbors(vertex).len;
                while (i > 0) {
                    i -= 1;
                    const edge = graph.getNeighbors(vertex)[i];
                    if (!visited[edge.to]) {
                        try stack.append(edge.to);
                    }
                }
            }
        }

        return result;
    }
};

/// Dijkstra's Shortest Path Algorithm
const Dijkstra = struct {
    const PathResult = struct {
        distances: []i32,
        previous: []?usize,
        allocator: Allocator,

        fn deinit(self: *PathResult) void {
            self.allocator.free(self.distances);
            self.allocator.free(self.previous);
        }

        fn getPath(self: *PathResult, target: usize) !?[]usize {
            if (self.distances[target] == std.math.maxInt(i32)) return null;

            var path = std.ArrayList(usize).init(self.allocator);
            var current: ?usize = target;
            
            while (current) |c| {
                try path.insert(0, c);
                current = self.previous[c];
            }

            return path.toOwnedSlice();
        }
    };

    fn shortestPath(allocator: Allocator, graph: *Graph, start: usize) !PathResult {
        var distances = try allocator.alloc(i32, graph.vertices);
        var previous = try allocator.alloc(?usize, graph.vertices);
        var visited = try allocator.alloc(bool, graph.vertices);
        defer allocator.free(visited);

        @memset(distances, std.math.maxInt(i32));
        @memset(previous, null);
        @memset(visited, false);
        distances[start] = 0;

        var i: usize = 0;
        while (i < graph.vertices) : (i += 1) {
            // Find minimum distance vertex
            var min_dist = std.math.maxInt(i32);
            var min_vertex: ?usize = null;

            for (0..graph.vertices) |v| {
                if (!visited[v] and distances[v] < min_dist) {
                    min_dist = distances[v];
                    min_vertex = v;
                }
            }

            if (min_vertex == null) break;
            const u = min_vertex.?;
            visited[u] = true;

            // Update distances
            for (graph.getNeighbors(u)) |edge| {
                if (!visited[edge.to]) {
                    const new_dist = distances[u] + edge.weight;
                    if (new_dist < distances[edge.to]) {
                        distances[edge.to] = new_dist;
                        previous[edge.to] = u;
                    }
                }
            }
        }

        return PathResult{
            .distances = distances,
            .previous = previous,
            .allocator = allocator,
        };
    }
};

/// Topological Sort (for Directed Acyclic Graphs)
const TopologicalSort = struct {
    fn sort(allocator: Allocator, graph: *Graph) !?[]usize {
        if (!graph.is_directed) return null;

        var in_degree = try allocator.alloc(usize, graph.vertices);
        defer allocator.free(in_degree);
        @memset(in_degree, 0);

        // Calculate in-degrees
        for (graph.adjacency_list.items) |edges| {
            for (edges.items) |edge| {
                in_degree[edge.to] += 1;
            }
        }

        var queue = std.ArrayList(usize).init(allocator);
        defer queue.deinit();

        // Add vertices with in-degree 0
        for (in_degree, 0..) |degree, i| {
            if (degree == 0) {
                try queue.append(i);
            }
        }

        var result = std.ArrayList(usize).init(allocator);

        while (queue.items.len > 0) {
            const vertex = queue.orderedRemove(0);
            try result.append(vertex);

            for (graph.getNeighbors(vertex)) |edge| {
                in_degree[edge.to] -= 1;
                if (in_degree[edge.to] == 0) {
                    try queue.append(edge.to);
                }
            }
        }

        // Check for cycle
        if (result.items.len != graph.vertices) {
            result.deinit();
            return null;
        }

        return result.toOwnedSlice();
    }
};

/// Cycle Detection
const CycleDetection = struct {
    fn hasCycle(allocator: Allocator, graph: *Graph) !bool {
        var visited = try allocator.alloc(bool, graph.vertices);
        defer allocator.free(visited);
        @memset(visited, false);

        if (graph.is_directed) {
            var rec_stack = try allocator.alloc(bool, graph.vertices);
            defer allocator.free(rec_stack);
            @memset(rec_stack, false);

            for (0..graph.vertices) |i| {
                if (!visited[i]) {
                    if (try hasCycleDirectedUtil(graph, i, visited, rec_stack)) {
                        return true;
                    }
                }
            }
        } else {
            for (0..graph.vertices) |i| {
                if (!visited[i]) {
                    if (try hasCycleUndirectedUtil(graph, i, visited, null)) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    fn hasCycleDirectedUtil(graph: *Graph, vertex: usize, visited: []bool, rec_stack: []bool) !bool {
        visited[vertex] = true;
        rec_stack[vertex] = true;

        for (graph.getNeighbors(vertex)) |edge| {
            if (!visited[edge.to]) {
                if (try hasCycleDirectedUtil(graph, edge.to, visited, rec_stack)) {
                    return true;
                }
            } else if (rec_stack[edge.to]) {
                return true;
            }
        }

        rec_stack[vertex] = false;
        return false;
    }

    fn hasCycleUndirectedUtil(graph: *Graph, vertex: usize, visited: []bool, parent: ?usize) !bool {
        visited[vertex] = true;

        for (graph.getNeighbors(vertex)) |edge| {
            if (!visited[edge.to]) {
                if (try hasCycleUndirectedUtil(graph, edge.to, visited, vertex)) {
                    return true;
                }
            } else if (parent == null or edge.to != parent.?) {
                return true;
            }
        }

        return false;
    }
};

// ============================================================================
// Tests and Demo
// ============================================================================

fn testBFS(allocator: Allocator) !void {
    std.debug.print("\n=== BFS Test ===\n", .{});
    
    var graph = try Graph.init(allocator, 6, false);
    defer graph.deinit();

    try graph.addEdge(0, 1, 1);
    try graph.addEdge(0, 2, 1);
    try graph.addEdge(1, 3, 1);
    try graph.addEdge(2, 3, 1);
    try graph.addEdge(2, 4, 1);
    try graph.addEdge(3, 5, 1);
    try graph.addEdge(4, 5, 1);

    graph.print();

    const bfs_result = try BFS.search(allocator, &graph, 0);
    defer bfs_result.deinit();
    std.debug.print("BFS from 0: {any}\n", .{bfs_result.items});

    const path = try BFS.shortestPath(allocator, &graph, 0, 5);
    if (path) |p| {
        defer allocator.free(p);
        std.debug.print("Shortest path 0->5: {any}\n", .{p});
    }
}

fn testDFS(allocator: Allocator) !void {
    std.debug.print("\n=== DFS Test ===\n", .{});
    
    var graph = try Graph.init(allocator, 5, true);
    defer graph.deinit();

    try graph.addEdge(0, 1, 1);
    try graph.addEdge(0, 2, 1);
    try graph.addEdge(1, 3, 1);
    try graph.addEdge(2, 4, 1);
    try graph.addEdge(3, 4, 1);

    graph.print();

    const dfs_result = try DFS.search(allocator, &graph, 0);
    defer dfs_result.deinit();
    std.debug.print("DFS recursive from 0: {any}\n", .{dfs_result.items});

    const dfs_iter = try DFS.searchIterative(allocator, &graph, 0);
    defer dfs_iter.deinit();
    std.debug.print("DFS iterative from 0: {any}\n", .{dfs_iter.items});
}

fn testDijkstra(allocator: Allocator) !void {
    std.debug.print("\n=== Dijkstra Test ===\n", .{});
    
    var graph = try Graph.init(allocator, 5, true);
    defer graph.deinit();

    try graph.addEdge(0, 1, 10);
    try graph.addEdge(0, 2, 3);
    try graph.addEdge(1, 2, 1);
    try graph.addEdge(1, 3, 2);
    try graph.addEdge(2, 1, 4);
    try graph.addEdge(2, 3, 8);
    try graph.addEdge(2, 4, 2);
    try graph.addEdge(3, 4, 7);
    try graph.addEdge(4, 3, 9);

    graph.print();

    var result = try Dijkstra.shortestPath(allocator, &graph, 0);
    defer result.deinit();

    std.debug.print("Shortest distances from 0:\n", .{});
    for (result.distances, 0..) |dist, i| {
        std.debug.print("  0 -> {}: {}\n", .{ i, dist });
    }

    const path = try result.getPath(3);
    if (path) |p| {
        defer allocator.free(p);
        std.debug.print("Shortest path 0->3: {any}\n", .{p});
    }
}

fn testTopologicalSort(allocator: Allocator) !void {
    std.debug.print("\n=== Topological Sort Test ===\n", .{});
    
    var graph = try Graph.init(allocator, 6, true);
    defer graph.deinit();

    try graph.addEdge(5, 2, 1);
    try graph.addEdge(5, 0, 1);
    try graph.addEdge(4, 0, 1);
    try graph.addEdge(4, 1, 1);
    try graph.addEdge(2, 3, 1);
    try graph.addEdge(3, 1, 1);

    graph.print();

    const sorted = try TopologicalSort.sort(allocator, &graph);
    if (sorted) |s| {
        defer allocator.free(s);
        std.debug.print("Topological order: {any}\n", .{s});
    } else {
        std.debug.print("Graph has a cycle!\n", .{});
    }
}

fn testCycleDetection(allocator: Allocator) !void {
    std.debug.print("\n=== Cycle Detection Test ===\n", .{});
    
    // Directed graph with cycle
    var graph1 = try Graph.init(allocator, 4, true);
    defer graph1.deinit();
    try graph1.addEdge(0, 1, 1);
    try graph1.addEdge(1, 2, 1);
    try graph1.addEdge(2, 3, 1);
    try graph1.addEdge(3, 1, 1);

    std.debug.print("Directed graph:\n", .{});
    graph1.print();
    std.debug.print("Has cycle: {}\n", .{try CycleDetection.hasCycle(allocator, &graph1)});

    // Undirected graph without cycle
    var graph2 = try Graph.init(allocator, 3, false);
    defer graph2.deinit();
    try graph2.addEdge(0, 1, 1);
    try graph2.addEdge(1, 2, 1);

    std.debug.print("\nUndirected graph (no cycle):\n", .{});
    graph2.print();
    std.debug.print("Has cycle: {}\n", .{try CycleDetection.hasCycle(allocator, &graph2)});

    // Undirected graph with cycle
    try graph2.addEdge(2, 0, 1);
    std.debug.print("\nUndirected graph (with cycle):\n", .{});
    graph2.print();
    std.debug.print("Has cycle: {}\n", .{try CycleDetection.hasCycle(allocator, &graph2)});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Graph Algorithms Demo ===\n", .{});

    try testBFS(allocator);
    try testDFS(allocator);
    try testDijkstra(allocator);
    try testTopologicalSort(allocator);
    try testCycleDetection(allocator);

    std.debug.print("\n=== All tests completed successfully! ===\n", .{});
}
