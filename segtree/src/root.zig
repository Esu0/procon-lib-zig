//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn Segtree(
    comptime T: type,
    comptime Context: type,
    comptime operationFn: fn (Context, T, T) T,
    comptime idFn: fn (Context) T,
) type {
    return struct {
        ctx: Context,
        items: []T,
        log: u6,
        offset: usize,

        const Self = @This();

        fn binOp(self: Self, lhs: T, rhs: T) T {
            return operationFn(self.ctx, lhs, rhs);
        }

        fn id(self: Self) T {
            return idFn(self.ctx);
        }

        fn updateSlice(ctx: Context, slice: []T, idx: usize) void {
            const ch1 = idx * 2;
            const ch2 = idx * 2 + 1;
            slice[idx] = switch (std.math.order(slice.len, ch2)) {
                .lt => idFn(ctx),
                .eq => slice[ch1],
                .gt => operationFn(ctx, slice[ch1], slice[ch2]),
            };
        }

        pub fn fromSliceAlloc(ctx: Context, gpa: std.mem.Allocator, slice: []T) std.mem.Allocator.Error!Self {
            const builder = try Builder.init(gpa, slice.len);
            @memcpy(builder.buffer[builder.offset..builder.offset + slice.len], slice);
            return builder.build(ctx);
        }

        pub fn prod(self: Self, left: usize, right: usize) T {
            var l = left;
            var r = right;
            var lv = self.id();
            var rv = self.id();
            while (r > l) {
                if (l & 1 != 0) {
                    lv = self.binOp(lv, self.items[l]);
                }
                if (r & 1 != 0) {
                    rv = self.binOp(self.items[r-1], rv);
                }
                l >>= 1;
                r >>= 1;
            }
            return self.binOp(lv, rv);
        }

        pub fn set(self: Self, idx: usize, val: T) void {
            var i = idx + self.offset;
            self.items[i] = val;
            while (i > 1) {
                i /= 2;
                updateSlice(self.ctx, self.items, i);
            }
        }

        pub fn getSlice(self: Self) []const T {
            return self.items[self.offset..];
        }

        pub fn maxRight(self: Self, left: usize, context: anytype, comptime pred: fn (@TypeOf(context), T) bool) usize {
            const clz = @clz(left);
            const l = left + self.offset;
            const ctz = @ctz(l);
            var s = l >> ctz;
            var b = self.offset;
            var val = self.id();
            for (0..@bitSizeOf(usize) - @clz(self.offset - left)) |_| {
                if (s & 1 != 0) {
                    const v = self.binOp(val, self.items[s]);
                    if (!pred(context, v)) break;
                    val = v;
                    s += 1;
                }
                s >>= 1;

            }
            while (pred(context, v)) {
                if (v == 1) return self.items.len - self.offset;

            }
        }

        pub const Builder = struct {
            // buffer[0] is invalid
            buffer: []T,
            log: u6,
            offset: usize,
            pub fn init(gpa: std.mem.Allocator, size: usize) std.mem.Allocator.Error!Builder {
                var offset: usize = 1;
                var log: u6 = 0;
                while (offset < size) : (offset *= 2) log += 1;
                const ptr = (try gpa.alloc(T, offset + size - 1)).ptr - 1;
                return .{
                    .buffer = ptr[0..offset + size],
                    .log = log,
                    .offset = offset,
                };
            }

            pub fn set(self: Builder, idx: usize, val: T) void {
                self.buffer[idx+self.offset] = val;
            }

            pub fn build(self: Builder, ctx: Context) Self {
                var i = self.offset - 1;
                while (i > 0) : (i -= 1) {
                    updateSlice(ctx, self.buffer, i);
                }

                return .{
                    .ctx = ctx,
                    .items = self.buffer,
                    .log = self.log,
                    .offset = self.offset,
                };
            }
        };
    };
}