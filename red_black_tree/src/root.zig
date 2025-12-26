//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const set = @import("set.zig");
const RBTreeArray = @import("RBTreeArray.zig");

comptime {
    _ = set;
    _ = RBTreeArray;
}
const Color = enum {
    red,
    black,

    fn flipped(self: Color) Color {
        return switch (self) {
            .red => .black,
            .black => .red,
        };
    }
};

pub const Node = struct {
    parent: ?*Node = null,
    color: Color = .red,
    children: [2]?*Node = @splat(null),

    fn whichDir(child: *Node, parent: *Node) u1 {
        const dir =  @intFromBool(parent.children[1] == child);
        assert(parent.children[dir] == child);
        return dir;
    }

    fn whichLink(child: *Node, parent: *Node) *?*Node {
        return &parent.children[child.whichDir(parent)];
    }

    fn format_recursive(
        node: Node,
        writer: *std.Io.Writer,
        level: usize,
        is_root: bool,
    ) std.Io.Writer.Error!void {
        if (node.children[0]) |left| {
            const next_level = if (left.color == .black) level + 1 else level;
            try format_recursive(left.*, writer, next_level, false);
        }
        try writer.writeByte(if (is_root) '>' else ' ');
        for (0..level) |_| try writer.writeAll("   ");
        const s: []const u8 = if (node.color == .black) "B\n" else " R\n";
        try writer.writeAll(s);
        if (node.children[1]) |right| {
            const next_level = if (right.color == .black) level + 1 else level;
            try format_recursive(right.*, writer, next_level, false);
        }
    }

    fn rotateAssumeNonRoot(self: *Node, dir: u1) void {
        const child = self.children[1 - dir].?;
        const parent = self.parent.?;
        const adjacent = child.children[dir];

        child.parent = parent;
        child.children[dir] = self;

        self.whichLink(parent).* = child;

        self.parent = child;
        self.children[1 - dir] = adjacent;

        if (adjacent) |adj| {
            assert(adj.parent == child);
            adj.parent = self;
        }
    }

    fn searchNode(node: *Node, context: anytype, comptime searchFn: fn(@TypeOf(context), *Node) u1) *Node {
        var cur = node;
        var dir = searchFn(context, node);
        while (cur.children[dir]) |next| : (cur = next) {
            dir = searchFn(context, next);
        }
        return cur;
    }

    fn edgeNodeSearchFn(dir: u1, _: *Node) u1 {
        return dir;
    }

    pub fn nextOnDirection(node: *Node, direction: u1) ?*Node {
        const opposite = 1 - direction;
        assert(opposite != direction);
        if (node.children[direction]) |child| {
            return child.searchNode(opposite, edgeNodeSearchFn);
        }
        var cur = node;
        while (cur.parent) |parent| : (cur = parent) {
            if (cur.whichDir(parent) == opposite) {
                return parent;
            }
        }
        return null;
    }
};

pub fn RBTree(comptime updateFn: ?fn (*Node) void) type {
    return struct {
        const Self = @This();
        root: ?*Node = null,

        const CheckError = error {
            StreakRed,
            DifferentBlackHeight,
        };

        pub fn checkConstraints(self: Self) CheckError!void {
            if (self.root) |root| _ = try checkConstraintsInner(root);
        }

        fn checkConstraintsInner(root: *Node) CheckError!u16 {
            var hs: [2]u16 = @splat(0);
            for (0.., root.children) |i, child| {
                if (child) |next_root| {
                    if (root.color == .red and next_root.color == .red) return CheckError.StreakRed;
                    hs[i] = try checkConstraintsInner(next_root);
                }
            }
            if (hs[0] != hs[1]) {
                return CheckError.DifferentBlackHeight;
            }
            return if (root.color == .black) hs[0] + 1 else hs[0];
        }

        pub fn format(
            self: Self,
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            if (self.root) |root| {
                try root.format_recursive(writer, 0, true);
            } else {
                try writer.writeAll("(empty)");
            }
        }

        // direction == 0: rotate left
        // direction == 1: rotate right
        inline fn rotate(self: *Self, node: *Node, direction: u1) void {
            const child = node.children[1 - direction].?;
            const parent = node.parent;
            const adjacent = child.children[direction];

            child.children[direction] = node;
            child.parent = parent;
            node.children[1 - direction] = adjacent;
            node.parent = child;

            if (adjacent) |adj| adj.parent = node;

            const link = if (parent) |p| node.whichLink(p) else &self.root;
            assert(link.* == node);
            link.* = child;
        }

        fn getParentLink(self: *Self, node: *Node) *?*Node {
            const link = if (node.parent) |parent| node.whichLink(parent) else &self.root;
            assert(link.* == node);
            return link;
        }

        fn swapLink(self: *Self, node1: *Node, node2: *Node) void {
            if (node1 == node2) return;
            assert(node1.parent != node2.parent);
            // parent link
            const plink1 = self.getParentLink(node1);
            const plink2 = self.getParentLink(node2);
            assert(plink1 != plink2);
            std.mem.swap(?*Node, plink1, plink2);
            std.mem.swap(?*Node, &node1.parent, &node2.parent);

            // child link
            std.mem.swap([2]?*Node, &node1.children, &node2.children);
            inline for ([2]*Node{node1, node2}) |node| {
                inline for (node.children) |child| {
                    if (child) |ch| {
                        ch.parent = node;
                    }
                }
            }
        }

        fn update(node: *Node) void {
            if (updateFn) |upd| upd(node);
        }

        fn updateAncestors(node: *Node) void {
            if (updateFn) |upd| {
                upd(node);
                var cur = node;
                while (cur.parent) |parent| : (cur = parent) upd(parent);
            }
        }

        fn rebalanceRed(self: *Self, node: *Node) void {
            assert(node.color == .red);
            if (node.parent == null) return;
            const parent = node.parent.?;
            if (parent.color == .black) return;
            if (parent.parent == null) {
                parent.color = .black;
                return;
            }
            const grandparent = parent.parent.?;
            assert(grandparent.color == .black);
            const parent_dir = parent.whichDir(grandparent);
            const uncle = grandparent.children[1 - parent_dir];
            if (uncle == null or uncle.?.color == .black) {
                grandparent.color = .red;
                if (parent.children[parent_dir] != node) {
                    assert(parent.children[1 - parent_dir] == node);
                    parent.rotateAssumeNonRoot(parent_dir);
                    update(parent);
                    node.color = .black;
                } else {
                    parent.color = .black;
                }
                self.rotate(grandparent, 1 - parent_dir);
                update(grandparent);
                return;
            }
            uncle.?.color = .black;
            parent.color = .black;
            grandparent.color = .red;
            self.rebalanceRed(grandparent);
        }

        fn rebalanceBlack(self: *Self, parent_node: *Node, dir: u1) void {
            const parent = parent_node;
            const node = parent.children[dir];
            assert(node == null or node.?.color == .black);
            var sibling = parent.children[1 - dir].?;

            if (sibling.color == .red) {
                assert(parent.color == .black);
                const c1 = sibling.children[0];
                const c2 = sibling.children[1];
                assert(c1 == null or c1.?.color == .black);
                assert(c2 == null or c2.?.color == .black);
                sibling.color = .black;
                parent.color = .red;
                self.rotate(parent, dir);
                sibling = parent.children[1 - dir].?;
            }
            assert(sibling.color == .black);
            var d = sibling.children[1 - dir];
            if (d == null or d.?.color == .black) {
                const c = sibling.children[dir];
                if (c != null and c.?.color == .red) {
                    assert(sibling.parent == parent);
                    sibling.rotateAssumeNonRoot(1 - dir);
                    update(sibling);
                    sibling = c.?;
                    d = sibling;
                } else {
                    sibling.color = .red;
                    if (parent.color == .black) {
                        if (parent.parent) |gp| {
                            self.rebalanceBlack(gp, parent.whichDir(gp));
                        }
                    } else {
                        parent.color = .black;
                    }
                    return;
                }
            }
            // siblingのupdateはここまで遅延
            // siblingのpushは済んでいる
            assert(d != null);
            assert(d.?.color == .red);
            sibling.color = parent.color;
            parent.color = .black;
            d.?.color = .black;
            self.rotate(parent, dir);
        }

        fn insertNode(
            self: *Self,
            cursor: *Node,
            direction: u1,
            new_node: *Node,
        ) void {
            new_node.color = .red;
            assert(cursor.children[direction] == null);
            cursor.children[direction] = new_node;
            new_node.parent = cursor;
            self.rebalanceRed(new_node);
            updateAncestors(new_node);
        }

        fn removeNode(self: *Self, node: *Node) void {
            assert(self.root != null);
            if (node.children[0]) |left| {
                if (node.children[1]) |right| {
                    const most_left = right.searchNode(@as(u1, 0), Node.edgeNodeSearchFn);
                    self.swapLink(node, most_left);
                    std.mem.swap(Color, &node.color, &most_left.color);
                    // updateAncestors(most_left);
                } else {
                    assert(node.color == .black);
                    assert(left.color == .red);
                    left.color = .black;
                    self.getParentLink(node).* = left;
                    left.parent = node.parent;
                    assert(left.children[0] == null);
                    assert(left.children[1] == null);
                    node.children[0] = null;
                    node.parent = null;
                    updateAncestors(left);
                    return;
                }
            }
            assert(node.children[0] == null);
            if (node.children[1]) |right| {
                assert(node.color == .black);
                assert(right.color == .red);
                right.color = .black;
                self.getParentLink(node).* = right;
                right.parent = node.parent;
                assert(right.children[0] == null);
                assert(right.children[1] == null);
                node.parent = null;
                node.children[1] = null;
                updateAncestors(right);
                return;
            }
            if (node.parent) |parent| {
                const dir = node.whichDir(parent);
                assert(parent.children[dir] == node);
                parent.children[dir] = null;
                if (node.color == .black) self.rebalanceBlack(parent, dir);
                updateAncestors(parent);
                node.parent = null;
            } else {
                self.root = null;
            }
        }

        pub const VacantEntry = struct {
            rbtree: *Self,
            parent: ?*Node,
            direction: u1,

            fn fromEmptyTree(rbtree: *Self) VacantEntry {
                assert(rbtree.root == null);
                return .{
                    .rbtree = rbtree,
                    .parent = null,
                    .direction = undefined,
                };
            }

            pub fn insert(entry: VacantEntry, node: *Node) OccupiedEntry {
                if (entry.parent) |parent| {
                    entry.rbtree.insertNode(parent, entry.direction, node);
                } else {
                    assert(entry.rbtree.root == null);
                    entry.rbtree.root = node;
                }
                return .{
                    .rbtree = entry.rbtree,
                    .node = node,
                };
            }

            pub fn adjacentOccupied(entry: VacantEntry, direction: u1) ?OccupiedEntry {
                const node = entry.parent orelse return null;
                return .{
                    .rbtree = entry.rbtree,
                    .node = if (entry.direction == direction) node.nextOnDirection(direction) orelse return null else node,
                };
            }
        };

        pub fn vacantEntryFromNode(self: *Self, node: *Node, direction: u1) VacantEntry {
            return if (node.children[direction]) |child| .{
                .rbtree = self,
                .parent = child.searchNode(1 - direction, Node.edgeNodeSearchFn),
                .direction = 1 - direction,
            } else .{
                .rbtree = self,
                .parent = node,
                .direction = direction,
            };
        }

        pub const OccupiedEntry = struct {
            rbtree: *Self,
            node: *Node,

            pub fn get(entry: OccupiedEntry) *Node {
                return entry.node;
            }

            pub fn remove(entry: OccupiedEntry) *Node {
                entry.rbtree.removeNode(entry.node);
                return entry.node;
            }

            /// 最後フラグと削除したノードを返す。最後フラグが立った場合、`entry`は無効となる。
            pub fn removeAndNext(entry: *OccupiedEntry) struct { bool, *Node } {
                const next = entry.node.nextOnDirection(1);
                const node = entry.remove();
                entry.node = next orelse return .{ true, node };
                return .{ false, node };
            }

            pub fn adjacentVacant(entry: OccupiedEntry, direction: u1) VacantEntry {
                return entry.rbtree.vacantEntryFromNode(entry.node, direction);
            }
        };

        pub const Entry = union(enum) {
            vacant: VacantEntry,
            occupied: OccupiedEntry,

            pub fn get(entry: Entry) ?*Node {
                return switch (entry) {
                    .vacant => null,
                    .occupied => |occupied_entry| occupied_entry.get(),
                };
            }

            pub fn getOrInsert(entry: Entry, node: *Node) OccupiedEntry {
                return switch (entry) {
                    .vacant => |vacant_entry| vacant_entry.insert(node),
                    .occupied => |occupied_entry| occupied_entry,
                };
            }
        };

        pub fn searchVacantEntry(self: *Self, ctx: anytype, comptime searchFn: fn (@TypeOf(ctx), *Node) u1) VacantEntry {
            var parent = self.root orelse return .{
                .rbtree = self,
                .parent = null,
                .direction = undefined,
            };
            var dir = searchFn(ctx, parent);
            while (parent.children[dir]) |node| {
                parent = node;
                dir = searchFn(ctx, parent);
            }
            return .{
                .rbtree = self,
                .parent = parent,
                .direction = dir,
            };
        }

        pub fn searchEntry(self: *Self, ctx: anytype, comptime searchFn: fn (@TypeOf(ctx), *Node) ?u1) Entry {
            var cur = self.root orelse return .{
                .vacant = VacantEntry.fromEmptyTree(self),
            };
            while (searchFn(ctx, cur)) |dir| {
                cur = cur.children[dir] orelse return .{
                    .vacant = .{
                        .rbtree = self,
                        .parent = cur,
                        .direction = dir,
                    }
                };
            }
            return .{
                .occupied = .{
                    .rbtree = self,
                    .node = cur,
                },
            };
        }
    };
}

const testing = std.testing;
const expectError = testing.expectError;

const SimpleTree = RBTree(null);
test "validation test" {
    var rbtree = SimpleTree{};
    try rbtree.checkConstraints();
    var root = Node{
        .color = .black,
    };
    rbtree.root = &root;
    try rbtree.checkConstraints();

    var n1 = Node{};
    var n2 = Node{};
    rbtree.root.?.children[0] = &n1;
    try rbtree.checkConstraints();
    rbtree.root.?.children[1] = &n2;
    try rbtree.checkConstraints();
    var n3 = Node{};
    rbtree.root.?.children[0].?.children[0] = &n3;
    try expectError(error.StreakRed, rbtree.checkConstraints());

    n3.color = .black;
    try expectError(error.DifferentBlackHeight, rbtree.checkConstraints());
}

test "rebalance test" {
    var rbtree = SimpleTree{};
    const root = try testing.allocator.create(Node);
    defer testing.allocator.destroy(root);
    const node1 = try testing.allocator.create(Node);
    defer testing.allocator.destroy(node1);
    const node2 = try testing.allocator.create(Node);
    defer testing.allocator.destroy(node2);

    node2.* = .{.parent = node1};
    node1.* = .{
        .children = .{node2, null},
        .parent = root,
    };
    root.* = .{
        .color = .black,
        .children = .{node1, null},
    };
    rbtree.root = root;
    try expectError(error.StreakRed, rbtree.checkConstraints());
    rbtree.rebalanceRed(node2);
    std.debug.print("{f}\n", .{rbtree});
    try rbtree.checkConstraints();

    const node3 = try testing.allocator.create(Node);
    defer testing.allocator.destroy(node3);

    node3.children = @splat(null);
    rbtree.insertNode(node2, 0, node3);
    std.debug.print("{f}\n", .{rbtree});
    try rbtree.checkConstraints();

    rbtree.root.?.children[1] = null;
    std.debug.print("{f}\n", .{rbtree});
    try expectError(error.DifferentBlackHeight, rbtree.checkConstraints());
    rbtree.rebalanceBlack(rbtree.root.?, 1);
    std.debug.print("{f}\n", .{rbtree});
    try rbtree.checkConstraints();

    var cnt: u32 = 0;
    const node4 = try testing.allocator.create(Node);
    defer testing.allocator.destroy(node4);
    node4.* = .{};
    _ = rbtree.searchVacantEntry(&cnt, struct {fn search(ctx: *u32, _: *Node) u1 {
        ctx.* += 1;
        return @intCast(ctx.* % 2);
    }}.search).insert(node4);
    std.debug.print("{f}\n", .{rbtree});
    try rbtree.checkConstraints();

    var nodes: [10]Node = @splat(.{});
    for (0..10) |i| {
        _ = rbtree.searchVacantEntry(&cnt, struct {fn search(ctx: *u32, _: *Node) u1 {
            ctx.* += 1;
            return @intFromBool(ctx.* % 3 == 0);
        }}.search).insert(&nodes[i]);
    }
    std.debug.print("{f}\n", .{rbtree});
    try rbtree.checkConstraints();
    rbtree.removeNode(&nodes[0]);

    std.debug.print("remove node0:\n{f}\n", .{rbtree});
    try rbtree.checkConstraints();

    for (0..5) |_| {
        rbtree.removeNode(rbtree.root.?);
        std.debug.print("remove root:\n{f}\n", .{rbtree});
        try rbtree.checkConstraints();
    }
    rbtree.removeNode(rbtree.root.?.searchNode({}, struct {fn search(_: void, _: *Node) u1 {
        return 1;
    }}.search));
    std.debug.print("remove most right:\n{f}\n", .{rbtree});
    try rbtree.checkConstraints();
}
