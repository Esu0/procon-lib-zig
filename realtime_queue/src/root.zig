const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const assert = debug.assert;

pub fn PersistentQueue(comptime T: type) type {
    return struct {
        const Node = struct {
            next: ?*LazyNode,
            value: T,
        };

        const LazyNode = union(enum) {
            node: Node,
            lazy: Rotate,

            fn force(self: *@This(), gpa: Allocator) Allocator.Error!void {
                switch (self.*) {
                    .lazy => |lazy| {
                        const node = try lazy.eval(gpa);
                        self.* = .{ .node = node };
                    },
                    else => {},
                }
                assert(self.* == .node);
            }
        };

        const Rotate = struct {
            front: ?*LazyNode,
            rear: *LazyNode,
            acc: ?*LazyNode,

            fn eval(self: @This(), gpa: Allocator) Allocator.Error!Node {
                const rear = self.rear.node;
                if (self.front) |front| {
                    try front.force(gpa);
                    var node = front.node;
                    const front2 = node.next;
                    const rear2 = rear.next;
                    const next = try gpa.create(LazyNode);
                    const new_acc = try gpa.create(LazyNode);
                    node.next = next;
                    next.* = .{
                        .lazy = .{
                            .front = front2,
                            .rear = rear2.?,
                            .acc = new_acc,
                        },
                    };

                    new_acc.* = .{
                        .node = .{
                            .value = rear.value,
                            .next = self.acc,
                        },
                    };
                    return node;
                } else {
                    assert(rear.next == null);
                    var node = rear;
                    node.next = self.acc;
                    return node;
                }
            }
        };

        const Self = @This();

        front: ?*LazyNode,
        rear: ?*LazyNode,
        sched: ?*LazyNode,

        pub const init: Self = .{
            .front = null,
            .rear = null,
            .sched = null,
        };

        fn rebalance(self: *Self, gpa: Allocator) Allocator.Error!void {
            if (self.sched) |sched| {
                try sched.force(gpa);
                self.sched = sched.node.next;
            } else {
                assert(self.rear != null);
                const new_lazy = try gpa.create(LazyNode);
                new_lazy.* = .{
                    .lazy = .{
                        .front = self.front,
                        .rear = self.rear.?,
                        .acc = null,
                    },
                };
                self.front = new_lazy;
                self.rear = null;
                self.sched = new_lazy;
            }
        }

        pub fn push(self: Self, gpa: Allocator, value: T) Allocator.Error!Self {
            var new_inst = self;
            const new_node = try gpa.create(LazyNode);
            new_node.* = .{
                .node = .{
                    .value = value,
                    .next = self.rear,
                },
            };
            new_inst.rear = new_node;
            try new_inst.rebalance(gpa);
            return new_inst;
        }

        pub fn getFront(self: Self, gpa: Allocator) Allocator.Error!?T {
            if (self.front) |front| {
                try front.force(gpa);
                return front.node.value;
            } else {
                return null;
            }
        }

        pub fn pop(self: Self, gpa: Allocator) Allocator.Error!?struct { T, Self } {
            if (self.front == null) return null;
            const front = self.front.?;
            try front.force(gpa);
            var new_inst = self;
            new_inst.front = front.node.next;
            try new_inst.rebalance(gpa);
            return .{ front.node.value, new_inst };
        }
    };
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const heap = std.heap;

test "simple" {
    const Queue = PersistentQueue(u32);
    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const a: Queue = .init;
    try expectEqual(null, try a.pop(gpa));
    const b = try a.push(gpa, 1);
    try expectEqual(1, try b.getFront(gpa));
    var c = try b.push(gpa, 2);
    const d = try c.push(gpa, 3);
    const e = try c.push(gpa, 4);
    var val, const f = (try e.pop(gpa)).?;
    try expectEqual(1, val);
    val, const g = (try f.pop(gpa)).?;
    try expectEqual(2, val);
    val, c = (try c.pop(gpa)).?;
    try expectEqual(1, val);
    val, c = (try c.pop(gpa)).?;
    try expectEqual(2, val);
    try expectEqual(null, try c.pop(gpa));
    _ = d;
    _ = g;
}