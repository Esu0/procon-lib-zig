const std = @import("std");
const debug = std.debug;
const assert = debug.assert;

const red_black_tree = @import("root.zig");
const Node = red_black_tree.Node;
pub const ItemNode = struct {
    node: Node = .{},
    size: usize = 1,

    pub fn fromNodePtr(node: *Node) *ItemNode {
        return @fieldParentPtr("node", node);
    }
};

fn update(node: *Node) void {
    const item = ItemNode.fromNodePtr(node);
    item.size = 1;
    inline for (0..2) |i| {
        if (node.children[i]) |child| {
            item.size += ItemNode.fromNodePtr(child).size;
        }
    }
}

const RBTree = red_black_tree.RBTree(update);
const Self = @This();


rbtree: RBTree = .{},

pub fn getEntry(self: *Self, idx: usize) RBTree.OccupiedEntry {
    var len: usize = 0;
    assert(idx < ItemNode.fromNodePtr(self.rbtree.root.?).size);
    const entry = self.rbtree.searchEntry(.{ &len, idx }, struct { fn search(ctx: struct {*usize, usize}, node: *Node) ?u1 {
        const left_size = if (node.children[0]) |left_node| ItemNode.fromNodePtr(left_node).size else 0;
        const i = ctx[1];
        const next_len = ctx[0].* + left_size;
        switch (std.math.order(i, next_len)) {
            .lt => return 0,
            .eq => return null,
            .gt => {
                ctx[0].* = next_len + 1;
                return 1;
            }
        }
    }}.search);
    return entry.occupied;
}

pub fn get(self: *Self, idx: usize) *ItemNode {
    const entry = self.getEntry(idx);
    return ItemNode.fromNodePtr(entry.node);
}

pub fn insert(self: *Self, idx: usize, item: *ItemNode) void {
    var len: usize = 0;
    assert(idx <= self.count());
    const entry = self.rbtree.searchVacantEntry(
        .{ &len, idx },
        struct { fn search(ctx: struct {*usize, usize}, node: *Node) u1 {
            const left_size = if (node.children[0]) |left_node| ItemNode.fromNodePtr(left_node).size else 0;
            const i = ctx[1];
            const next_len = ctx[0].* + left_size;
            // std.debug.print("{d} -> {d}\n", .{ctx[0].*, next_len});
            if (i <= next_len) {
                return 0;
            } else {
                ctx[0].* = next_len + 1;
                return 1;
            }
        }}.search
    );
    _ = entry.insert(&item.node);
}

pub fn remove(self: *Self, idx: usize) *ItemNode {
    return ItemNode.fromNodePtr(self.getEntry(idx).remove());
}

pub fn count(self: Self) usize {
    if (self.rbtree.root) |root| {
        const size = ItemNode.fromNodePtr(root).size;
        assert(size > 0);
        return size;
    } else {
        return 0;
    }
}

test {
    const Item = struct {
        item_node: ItemNode = .{},
        val: u32,

        fn fromNode(nodeptr: *ItemNode) *@This() {
            return @fieldParentPtr("item_node", nodeptr);
        }
    };
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();
    var arr = Self{};
    {
        var i: u32 = 0;
        while (i < 20) : (i += 1) {
            const p = try gpa.create(Item);
            p.* = .{ .val = i };
            arr.insert(arr.count() / 2, &p.item_node);
            try arr.rbtree.checkConstraints();
            // for (0..arr.count()) |j| {
            //     std.debug.print("{d} ", .{Item.fromNode(arr.get(j)).val});
            // }
            // std.debug.print("\n", .{});
            // for (0..arr.count()) |j| {
            //     std.debug.print("{d} ", .{arr.get(j).size});
            // }
            // std.debug.print("\n", .{});
            // std.debug.print("{f}\n", .{arr.rbtree});
        }
    }
    std.debug.print("length: {d}\n", .{arr.count()});
    std.debug.print("tree:\n {f}\n", .{arr.rbtree});
    for (0..arr.count()) |i| {
        std.debug.print("{d} ", .{Item.fromNode(arr.get(i)).val});
    }

    while (arr.count() > 0) gpa.destroy(Item.fromNode(arr.remove(0)));
}
