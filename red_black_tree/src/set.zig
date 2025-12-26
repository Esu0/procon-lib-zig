const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const red_black_tree = @import("root.zig");
const Node = red_black_tree.Node;
const RBTree = red_black_tree.RBTree(null);

fn RBTreeSet(comptime T: type, comptime compareFn: fn (T, T) std.math.Order, comptime reserved: usize) type {
    return struct {
        const Self = @This();
        pub const ItemNode = struct {
            key: T,
            node: Node,

            pub fn fromNodePtr(nodeptr: *Node) *ItemNode {
                return @fieldParentPtr("node", nodeptr);
            }

            pub fn next(node: *ItemNode) ?*ItemNode {
                return fromNodePtr(node.node.nextOnDirection(1) orelse return null);
            }

            pub fn prev(node: *ItemNode) ?*ItemNode {
                return fromNodePtr(node.node.nextOnDirection(0) orelse return null);
            }
        };

        nodes: [reserved]ItemNode = undefined,
        node_last: usize = 0,
        rbtree: RBTree = .{},

        fn searchFn(key: T, node: *Node) ?u1 {
            const item_ptr = ItemNode.fromNodePtr(node);
            return switch (compareFn(key, item_ptr.key)) {
                .eq => null,
                .lt => 0,
                .gt => 1,
            };
        }

        pub fn insert(self: *Self, key: T) ?*ItemNode {
            const entry = self.rbtree.searchEntry(key, searchFn);
            switch (entry) {
                .vacant => |vacant_entry| {
                    const new_node = &self.nodes[self.node_last];
                    self.node_last += 1;
                    new_node.key = key;
                    new_node.node = .{};
                    const inserted = vacant_entry.insert(&new_node.node);
                    assert(inserted.node == &new_node.node);
                    return new_node;
                },
                .occupied => return null,
            }
        }

        pub fn insertNode(self: *Self, node: *ItemNode) bool {
            const entry = self.rbtree.searchEntry(node.key, searchFn);
            switch (entry) {
                .vacant => |vacant_entry| {
                    _ = vacant_entry.insert(&node.node);
                    return true;
                },
                .occupied => return false,
            }
        }

        pub fn contains(self: *Self, key: T) bool {
            return std.meta.activeTag(self.rbtree.searchEntry(key, searchFn)) == .occupied;
        }

        pub fn getNode(self: *Self, key: T) ?*ItemNode {
            const entry = self.rbtree.searchEntry(key, searchFn);
            return switch (entry) {
                .vacant => null,
                .occupied => |occupied_entry| ItemNode.fromNodePtr(occupied_entry.node),
            };
        }

        pub fn remove(self: *Self, key: T) ?*ItemNode {
            const entry = self.rbtree.searchEntry(key, searchFn);
            return switch (entry) {
                .vacant => null,
                .occupied => |occupied_entry| ItemNode.fromNodePtr(occupied_entry.remove()),
            };
        }
    };
}

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;

const SetU32 = RBTreeSet(u32, struct { fn compare(a: u32, b: u32) std.math.Order {
    return std.math.order(a, b);
}}.compare, 100);

test "set test" {
    var set = SetU32{};
    try expect(set.insert(5) != null);
    try expect(set.insert(10) != null);
    try expect(set.insert(20) != null);
    try expect(set.insert(15) != null);
    try expect(set.remove(5) != null);
    try expect(set.remove(6) == null);
    try expect(set.contains(10));
    try expect(!set.contains(5));
    try expect(!set.contains(11));
    try expect(set.insert(5) != null);
    try expect(set.insert(5) == null);

    var cur = set.getNode(5).?;
    try expectEqual(5, cur.key);
    cur = cur.next().?;
    try expectEqual(10, cur.key);
    cur = cur.next().?;
    try expectEqual(15, cur.key);
    cur = cur.next().?;
    try expectEqual(20, cur.key);
    try expectEqual(null, cur.next());
}

test "many entries" {
    var set = SetU32{};

    var i: u32 = 0;
    while (i < 50) : (i += 3) try expect(set.insert(i) != null);
    i = 1;
    while (i < 50) : (i += 3) try expect(set.insert(i) != null);
    i = 2;
    while (i < 50) : (i += 3) try expect(set.insert(i) != null);
    i = 0;
    while (i < 50) : (i += 1) {
        try expect(set.contains(i));
    }

    var cur = set.getNode(0).?;
    i = 0;
    try expectEqual(i, cur.key);
    while (cur.next()) |next| {
        i += 1;
        cur = next;
        try expectEqual(i, cur.key);
    }

    cur = set.getNode(49).?;
    i = 49;
    try expectEqual(i, cur.key);
    while (cur.prev()) |prev| {
        i -= 1;
        cur = prev;
        try expectEqual(i, cur.key);
    }
}
