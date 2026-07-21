const std = @import("std");
const super = @import("root.zig");
const ntt = @import("convolution/ntt.zig");
const ModInt = super.ModInt;

comptime {
    _ = ntt;
}

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
        const MInt = ModInt(modulo);
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

        /// returns (2^e)th root
        /// 1^(2^-e)
        pub fn getRoot(self: Self, e: u32, inv: bool) MInt {
            _ = self;
            std.debug.assert(e <= log);
            return if (inv) invd[log - e] else root[log - e];
        }

        pub fn nttInplace(self: Self, buf: []MInt, inv: bool, comptime bit_reverse_order: ntt.Port) void {
            ntt.nttInplace(modulo, buf, self, inv, bit_reverse_order);
        }
    };
}

fn convolutionNaive(modulo: comptime_int, a: []const ModInt(modulo), b: []const ModInt(modulo), c: []ModInt(modulo)) void {
    std.debug.assert(a.len == b.len and b.len == c.len);
    for (0..c.len) |i| {
        var sum: ModInt(modulo) = .zero;
        for (0..a.len) |j| {
            const k = (i + a.len - j) % a.len;
            sum.iadd(a[j].mul(b[k]));
        }
        c[i] = sum;
    }
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;

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
        try expectEqual(1, t.value);
        try expectEqual(16, set.count());
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
        try expectEqual(1, t.value);
        try expectEqual(8, set.count());
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

test "convolution" {
    const MInt = ModInt(998244353);
    var xoshiro = std.Random.DefaultPrng.init(testing.random_seed);
    const rng = xoshiro.random();
    const log = 5;
    var a: [1<<log]MInt = undefined;
    var b: [1<<log]MInt = undefined;
    for (0..1<<log) |i| {
        a[i] = .random(rng);
        b[i] = .random(rng);
    }
    var c: [1<<log]MInt = undefined;
    convolutionNaive(MInt.mod, &a, &b, &c);
    const roots = RootsPowerOf2(MInt.mod){};
    roots.nttInplace(&a, false, .out);
    roots.nttInplace(&b, false, .out);
    const sz_inv = MInt.init(1<<log).inv();
    for (0..1<<log) |i| {
        a[i].imul(b[i].mul(sz_inv));
    }
    roots.nttInplace(&a, true, .in);
    try expectEqualSlices(MInt, &c, &a);
}