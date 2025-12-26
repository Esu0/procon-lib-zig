//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn FenwickTree(comptime T: type, comptime binaryOperation: fn (T, T) T) type {
    return struct {
        const Self = @This();
        const Item = T;
        fn binaryAdd(a: Item, b: Item) Item {
            return binaryOperation(a, b);
        }

        items: []Item,

        pub fn init(items: []Item) Self {
            const len = items.len;
            for (0..len) |i| {
                const idx_to = (i + 1) | i;
                if (idx_to < len) {
                    items[idx_to] = binaryAdd(items[i], items[idx_to]);
                }
            }
            return .{
                .items = items,
            };
        }

        pub fn prefixSum(self: *const Self, count: usize) ?Item {
            if (count == 0) {
                return null;
            }
            var cur = self.items[count - 1];
            var remaining = (count - 1) & count;
            while (remaining > 0) : (remaining = (remaining - 1) & remaining){
                cur = binaryAdd(self.items[remaining - 1], cur);
            }
            return cur;
        }

        pub fn add(self: *const Self, idx: usize, val: Item) void {
            std.debug.assert(idx < self.items.len);
            var cur = idx;
            while (cur < self.items.len) : (cur = (cur + 1) | cur) {
                self.items[cur] = binaryAdd(self.items[cur], val);
            }
        }
    };
}

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

fn addU32(a: u32, b: u32) u32 {
    return a + b;
}
const FenwickTreeAdd = FenwickTree(u32, addU32);
test "init" {
    var buf: [5]u32 = .{3, 1, 4, 1, 5};
    const fenwick_tree = FenwickTreeAdd.init(&buf);
    const expected: []const u32 = &.{3, 4, 4, 9, 5};
    try expectEqualSlices(u32, expected, fenwick_tree.items);

    try expectEqual(null, fenwick_tree.prefixSum(0));
    try expectEqual(3, fenwick_tree.prefixSum(1));
    try expectEqual(4, fenwick_tree.prefixSum(2));
    try expectEqual(8, fenwick_tree.prefixSum(3));
    try expectEqual(9, fenwick_tree.prefixSum(4));
    try expectEqual(14, fenwick_tree.prefixSum(5));

    fenwick_tree.add(1, 2);
    try expectEqual(3, fenwick_tree.prefixSum(1));
    try expectEqual(6, fenwick_tree.prefixSum(2));
    try expectEqual(10, fenwick_tree.prefixSum(3));
    try expectEqual(16, fenwick_tree.prefixSum(5));
}
