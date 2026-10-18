const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const assert = debug.assert;

pub const Node = struct {
    value: u32,
    next: ?*Stream,
};

pub const LazyNode = union(enum) {
    concat: ConcatStream,
    reverse: ReverseStream,

    pub fn eval(self: LazyNode, gpa: Allocator) Allocator.Error!Stream {
        return switch (self) {
            .concat => |concat| concat.eval(gpa),
            .reverse => |reverse| reverse.eval(gpa),
        };
    }
};

pub const ConcatStream = struct {
    left: ?*Stream,
    right: *Stream,

    pub fn eval(self: ConcatStream, gpa: Allocator) Allocator.Error!Stream {
        return if (self.left) |left| blk: {
            try left.force(gpa);
            const left2 = left.node.next;
            const new_concat = try gpa.create(Stream);
            new_concat.* = Stream.concat(left2, self.right);
            break :blk .{
                .node = .{
                    .value = left.node.value,
                    .next = new_concat,
                },
            };
        } else self.right.*;
    }
};

pub const ReverseStream = struct {
    stream: *Stream,
    acc: ?*Stream,

    pub fn eval(self: ReverseStream, gpa: Allocator) Allocator.Error!Stream {
        const stream = self.stream;
        try stream.force(gpa);
        const node = stream.node;
        const h = node.value;
        const t = node.next;
        const new_acc: Stream = .{ .node = .{ .value = h, .next = self.acc } };
        if (t) |ts| {
            const new_stream = try gpa.create(Stream);
            new_stream.* = new_acc;
            return Stream.reverse(ts, new_stream);
        } else {
            return new_acc;
        }
    }
};

pub const Stream = union(enum) {
    node: Node,
    lazy: LazyNode,

    inline fn reverse(stream: *Stream, acc: ?*Stream) Stream {
        return .{
            .lazy = .{
                .reverse = .{
                    .stream = stream,
                    .acc = acc,
                },
            },
        };
    }

    inline fn concat(left: ?*Stream, right: *Stream) Stream {
        return .{
            .lazy = .{
                .concat = .{
                    .left = left,
                    .right = right,
                },
            },
        };
    }

    pub fn force(self: *Stream, gpa: Allocator) Allocator.Error!void {
        var stream = self.*;
        while (stream == .lazy) {
            stream = try stream.lazy.eval(gpa);
        }
        assert(stream == .node);
        self.* = stream;
    }
};

pub const Queue = struct {
    const Self = @This();
    front: ?*Stream,
    front_length: usize,
    rear: ?*Stream,
    rear_length: usize,

    pub const empty: Self = .{
        .front = null,
        .front_length = 0,
        .rear = null,
        .rear_length = 0,
    };

    pub fn isEmpty(self: Self) bool {
        return self.front == null;
    }

    fn rebalance(self: *Self, gpa: Allocator) Allocator.Error!void {
        if (self.front_length < self.rear_length) {
            const new_front = try gpa.create(Stream);
            const reverse = try gpa.create(Stream);
            reverse.* = Stream.reverse(self.rear.?, null);
            new_front.* = Stream.concat(self.front, reverse);
            self.front = new_front;
            self.rear = null;
            self.front_length += self.rear_length;
            self.rear_length = 0;
        }
    }

    pub fn push(self: Self, gpa: Allocator, value: u32) Allocator.Error!Self {
        const new_rear = try gpa.create(Stream);
        new_rear.* = .{ .node = .{ .value = value, .next = self.rear } };
        var result = self;
        result.rear = new_rear;
        result.rear_length += 1;
        try result.rebalance(gpa);
        return result;
    }

    pub fn pop(self: Self, gpa: Allocator) Allocator.Error!?struct {u32, Self} {
        if (self.front) |front| {
            try front.force(gpa);
            var result = self;
            result.front_length -= 1;
            result.front = front.node.next;
            const val = front.node.value;
            try result.rebalance(gpa);
            return .{ val, result };
        } else {
            return null;
        }
    }

    pub fn getFront(self: Self, gpa: Allocator) Allocator.Error!?u32 {
        if (self.front) |front| {
            try front.force(gpa);
            return self.front.?.node.value;
        } else {
            return null;
        }
    }
};

const testing = std.testing;
const expectEqual = testing.expectEqual;
const heap = std.heap;

test "simple" {
    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const a: Queue = .empty;
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
