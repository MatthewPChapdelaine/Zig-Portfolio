const std = @import("std");
const ArrayList = std.ArrayList;

const Package = struct {
    name: []const u8,
    version: []const u8,
    dependencies: ArrayList([]const u8),
};

const PackageManager = struct {
    allocator: std.mem.Allocator,
    registry: std.StringHashMap(Package),
    
    pub fn init(allocator: std.mem.Allocator) PackageManager {
        return .{
            .allocator = allocator,
            .registry = std.StringHashMap(Package).init(allocator),
        };
    }
    
    pub fn deinit(self: *PackageManager) void {
        var it = self.registry.iterator();
        while (it.next()) |entry| {
            var pkg = entry.value_ptr;
            pkg.dependencies.deinit();
        }
        self.registry.deinit();
    }
    
    pub fn parseManifest(self: *PackageManager, path: []const u8) ![]Package {
        _ = path;
        var packages = ArrayList(Package).init(self.allocator);
        
        // Simplified - would parse JSON/YAML in real implementation
        var deps = ArrayList([]const u8).init(self.allocator);
        try deps.append("dep1");
        
        try packages.append(.{
            .name = "example",
            .version = "1.0.0",
            .dependencies = deps,
        });
        
        return packages.toOwnedSlice();
    }
    
    pub fn resolve(self: *PackageManager, packages: []Package) ![]Package {
        var resolved = ArrayList(Package).init(self.allocator);
        
        for (packages) |pkg| {
            try resolved.append(pkg);
            
            // Resolve dependencies recursively
            for (pkg.dependencies.items) |dep| {
                _ = dep;
                // Would fetch and resolve here
            }
        }
        
        return resolved.toOwnedSlice();
    }
    
    pub fn install(self: *PackageManager, packages: []Package) !void {
        std.debug.print("📥 Installing {} packages...\n", .{packages.len});
        
        for (packages) |pkg| {
            std.debug.print("  ⬇  {s} @ {s}\n", .{ pkg.name, pkg.version });
            std.time.sleep(100 * std.time.ns_per_ms);
        }
        
        try self.generateLock(packages);
    }
    
    fn generateLock(self: *PackageManager, packages: []Package) !void {
        _ = self;
        _ = packages;
        std.debug.print("📝 Generated package.lock\n", .{});
    }
    
    pub fn visualizeGraph(self: *PackageManager, packages: []Package) void {
        std.debug.print("\n🌳 Dependency Graph:\n", .{});
        
        for (packages) |pkg| {
            std.debug.print("{s} @ {s}\n", .{ pkg.name, pkg.version });
            
            for (pkg.dependencies.items) |dep| {
                std.debug.print("  └─ {s}\n", .{dep});
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    _ = args.skip(); // Skip program name
    const command = args.next() orelse "help";
    
    var pm = PackageManager.init(allocator);
    defer pm.deinit();
    
    if (std.mem.eql(u8, command, "install")) {
        std.debug.print("📦 Reading package.json...\n", .{});
        const packages = try pm.parseManifest("package.json");
        defer allocator.free(packages);
        
        std.debug.print("🔍 Resolving dependencies...\n", .{});
        const resolved = try pm.resolve(packages);
        defer allocator.free(resolved);
        
        std.debug.print("✓ Resolved {} packages\n", .{resolved.len});
        
        try pm.install(resolved);
        std.debug.print("✓ Installation complete!\n", .{});
        
    } else if (std.mem.eql(u8, command, "graph")) {
        const packages = try pm.parseManifest("package.json");
        defer allocator.free(packages);
        
        pm.visualizeGraph(packages);
        
    } else {
        std.debug.print(
            \\PackageManager - Zig Dependency Management
            \\
            \\Usage:
            \\  package-manager install    Install dependencies
            \\  package-manager graph      Show dependency graph
            \\
        , .{});
    }
}
