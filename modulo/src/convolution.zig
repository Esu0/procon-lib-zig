const std = @import("std");
const super = @import("root.zig");


// impl Pcg32 {
//     const fn new(state: u64, seq: u64) -> Self {
//         let mut rng = Self { state: 0, inc: (seq << 1) | 1 };
//         rng.next();
//         rng.state = rng.state.wrapping_add(state);
//         rng.next();
//         rng
//     }

//     const fn next(&mut self) -> u32 {
//         let old = self.state;
//         self.state = old.wrapping_mul(6364136223846793005).wrapping_mul(self.inc);
//         let xorshifted = (((old >> 18) ^ old) >> 27) as u32;
//         let rot = (old >> 59) as u32;
//         xorshifted.rotate_right(rot)
//     }

//     const fn rand(&mut self, bound: u32) -> u32 {
//         let threshold = bound.wrapping_neg() % bound;
//         loop {
//             let r = self.next();
//             if r >= threshold {
//                 return r % bound;
//             }
//         }
//     }
// }
const Pcg32 = struct {
    const Self = @This();
    state: u64,
    inc: u64,

    pub fn init(state: u64, seq: u64) Self {
        var rng: Self = .{ .state = state, .inc = (seq << 1) | 1 };
        _ = rng.next();
        rng.state +%= rng.state;
        _ = rng.next();
        return rng;
    }

    pub fn next(self: *Self) u32 {
        const old = self.state;
        self.state = old *% 6364136223846793005 +% self.inc;

        const xor_s: u32 = @truncate(((old >> 18) ^ old) >> 27);
        const rot: u32 = @intCast(old >> 59);

        return (xor_s >> @as(u5, @intCast(rot))) | (xor_s << @as(u5, @intCast((0 -% rot) & 31)));
    }

    

};

fn comptimeCtz(x: comptime_int) comptime_int {
    var val = x;
    var cnt = 0;
    while (val % 2 == 0) : (val /= 2) cnt += 1;
    return cnt;
}

fn find_root(modulo: comptime_int) super.ModInt(modulo) {
    if (modulo == 2) return .one;
    const MInt = super.ModInt(modulo);
    if (modulo == 2) return .one;
    var pcg = std.Random.Pcg.init(3405073802013788547);
    const rng = pcg.random();
    const pows2 = comptimeCtz(modulo - 1);
    const p = (modulo - 1) >> pows2;
    while (true) {
        const r = MInt.fromRaw(rng.uintAtMost(MInt.Int, modulo - 2) + 1).pow(p);
        var k = r;
        comptime var i = 0;
        inline while (i < pows2 - 1) : (i += 1) {
            k.imul(k);
        }
        if (k.value != 1) {
            return r;
        }
    }
}

pub fn RootsPowerOf2(modulo: comptime_int) type {
    const modulo_is_prime = super.isPrime(modulo);
    if (!modulo_is_prime) {
        @compileError("Modulo must be prime.");
    }
    const log = comptimeCtz(modulo - 1);
    const r = find_root(modulo);
    return struct {
        const MInt = super.ModInt(modulo);
        const Self = @This();
        pub const root = blk: {
            var t = r;
            var buf: [log+1]MInt = undefined;
            var i = 0;
            while (i < log) : (i += 1) {
                buf[i] = t;
                std.debug.assert(t.value != 1);
                t.imul(t);
            }
            buf[i] = t;
            std.debug.assert(t.value == 1);
            break :blk buf;
        };
        pub const invd: [log+1]MInt = blk: {
            var t = r.inv();
            var buf: [log+1]MInt = undefined;
            var i = 0;
            while (i < log) : (i += 1) {
                buf[i] = t;
                std.debug.assert(t.value != 1);
                t.imul(t);
            }
            buf[i] = t;
            std.debug.assert(t.value == 1);
            // @compileLog(t);
            break :blk buf;
        };
    };
}

const testing = std.testing;
test "find root" {
    const gpa = testing.allocator;
    {
        const r = find_root(113);
        var set: std.AutoHashMap(u32, void) = .init(gpa);
        defer set.deinit();
        var t = @TypeOf(r).one;
        for (0..16) |_| {
            _ = try set.getOrPut(t.value);
            t.imul(r);
        }
        try testing.expectEqual(1, t.value);
        try testing.expectEqual(16, set.count());
    }
    {
        const r = comptime find_root(137);
        var set: std.AutoHashMap(u32, void) = .init(gpa);
        defer set.deinit();
        var t = @TypeOf(r).one;
        for (0..8) |_| {
            _ = try set.getOrPut(t.value);
            t.imul(r);
        }
        try testing.expectEqual(1, t.value);
        try testing.expectEqual(8, set.count());
    }
}

test "Calculate Root" {
    const primes = [_]comptime_int{2, 3, 5, 7, 11, 13, 998244353};
    inline for (primes) |p| {
        const R = RootsPowerOf2(p);
        _ = R.root;
        _ = R.invd;
    }
}