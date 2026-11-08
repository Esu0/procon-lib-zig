const std = @import("std");
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const assert = debug.assert;
const Error = Allocator.Error;

pub fn BTree(comptime T: type, comptime compareFn: fn (T, T) math.Order, comptime k: usize) type {
    if (k < 3) {
        @compileError("k must be at least 3");
    }

    return struct {
        const Tree = @This();
        const bw = @bitSizeOf(usize) - @clz(k);
        const Count = std.meta.Int(.unsigned, bw);
        const SearchResult = union(enum) {
            found: Count,
            not_found: Count,
        };

        const Node = struct {
            values: [k-1]T,
            children: [k]Tree,
            count: Count,

            fn search(node: *const Node, value: T) SearchResult {
                var i: Count = 0;
                const count = node.count;
                while (i < count) switch(compareFn(value, node.values[i])) {
                    .lt => return .{ .not_found = i },
                    .eq => return .{ .found = i },
                    .gt => i += 1,
                };
                return .{ .not_found = i };
            }

            fn insertTree(node: *Node, gpa: Allocator, idx: Count, value: T, tree: Tree) Error!?struct {T, *Node} {
                const c = node.count;
                assert(idx <= c);
                if (c == k - 1) {
                    const new_node = try gpa.create(Node);
                    const l = k / 2;
                    new_node.count = k - 1 - l;
                    node.count = l;

                    var ret: struct {T, *Node} = undefined;
                    switch (math.order(idx, l)) {
                        .lt => {
                            @memcpy(new_node.values[0..k - 1 - l], node.values[l..k - 1]);
                            @memcpy(new_node.children[0..k - l], node.children[l..k]);
                            ret = .{node.values[l - 1], new_node};
                            @memmove(node.values[idx + 1..l], node.values[idx..l - 1]);
                            @memmove(node.children[idx + 2..l + 1], node.children[idx + 1..l]);
                            node.values[idx] = value;
                            node.children[idx + 1] = tree;
                        },
                        .eq => {
                            ret = .{value, new_node};
                            @memcpy(new_node.values[0..k - 1 - l], node.values[l..k - 1]);
                            new_node.children[0] = tree;
                            @memcpy(new_node.children[1..k - l], node.children[l + 1..k]);
                        },
                        .gt => {
                            ret = .{node.values[l], new_node};
                            @memcpy(new_node.values[0..idx - l - 1], node.values[l + 1..idx]);
                            @memcpy(new_node.children[0..idx - l], node.children[l + 1..idx + 1]);
                            new_node.values[idx - l - 1] = value;
                            new_node.children[idx - l] = tree;
                            @memcpy(new_node.values[idx - l..k - l - 1], node.values[idx..k - 1]);
                            @memcpy(new_node.children[idx - l + 1..k - l], node.children[idx + 1..k]);
                        }
                    }
                    return ret;
                }

                @memmove(node.values[idx + 1..c + 1], node.values[idx..c]);
                @memmove(node.children[idx + 2..c + 2], node.children[idx + 1..c + 1]);
                node.values[idx] = value;
                node.children[idx + 1] = tree;
                node.count = c + 1;
                return null;
            }

            fn toOne(node: *Node, t1: Tree, value: T, t2: Tree) void {
                node.values[0] = value;
                node.children[0] = t1;
                node.children[1] = t2;
                node.count = 1;
            }
        };

        ptr: ?*Node,

        pub const empty: Tree = .{ .ptr = null };

        pub fn insert(self: *Tree, gpa: Allocator, value: T) Error!bool {
            if (self.insertRec(gpa, value) catch |err| switch(err) {
                error.Found => return false,
                else => return @errorCast(err),
            }) |upd| {
                const v, const t = upd;
                const node = try gpa.create(Node);
                node.toOne(self.*, v, t);
                self.ptr = node;
            }
            return true;
        }

        pub fn contains(self: Tree, value: T) bool {
            if (self.ptr == null) return false;
            const ptr = self.ptr.?;
            const res = ptr.search(value);
            return switch (res) {
                .found => true,
                .not_found => |pos| ptr.children[pos].contains(value),
            };
        }

        fn insertRec(self: Tree, gpa: Allocator, value: T) (error{Found} || Error)!?struct {T, Tree} {
            if (self.ptr == null) {
                return .{value, .empty};
            }
            const ptr = self.ptr.?;
            const idx = switch (ptr.search(value)) {
                .found => return error.Found,
                .not_found => |idx| idx,
            };
            if (try ptr.children[idx].insertRec(gpa, value)) |ovf| {
                const v, const t = ovf;
                if (try ptr.insertTree(gpa, idx, v, t)) |res| {
                    return .{ res[0], .{ .ptr = res[1] } };
                }
            }
            return null;
        }

        pub fn deinit(self: Tree, gpa: Allocator) void {
            if (self.ptr == null) return;
            const ptr = self.ptr.?;
            const cnt = ptr.count;
            for (ptr.children[0..cnt+1]) |child| {
                child.deinit(gpa);
            }
            gpa.destroy(ptr);
        }
    };
}

const testing = std.testing;
const Random = std.Random;
const expectEqual = testing.expectEqual;
fn compareU32(lhs: u32, rhs: u32) math.Order {
    return math.order(lhs, rhs);
}

const BTreeSet = BTree(u32, compareU32, 6);
test "random test" {
    var random = Random.DefaultPrng.init(testing.random_seed);
    const rng = random.random();
    const n = 1000;
    var set: std.AutoHashMap(u32, void) = .init(testing.allocator);
    defer set.deinit();
    var btree: BTreeSet = .empty;
    defer btree.deinit(testing.allocator);
    for (0..n) |_| {
        const value = rng.intRangeLessThan(u32, 0, n);
        try expectEqual(set.contains(value), btree.contains(value));
        const res = try set.getOrPut(value);
        const ins_res = try btree.insert(testing.allocator, value);
        try expectEqual(!res.found_existing, ins_res);
    }
}
