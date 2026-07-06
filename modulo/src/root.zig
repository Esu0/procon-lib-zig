//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const mem = std.mem;
pub const convolution = @import("convolution.zig");

comptime {
    _ = convolution;
}
fn requiringBits(val: comptime_int) comptime_int {
    var cur = val;
    var count = 0;
    while (cur > 0) : (cur >>= 1) count += 1;
    return count;
}

pub fn isPrime(number: comptime_int) bool {
    if (number <= 0) @compileError("Modulo must be positive");
    if (number > 100_000_000_000) @compileError("Cannot check primary of modulo");
    @setEvalBranchQuota(1_000_000);
    comptime var is_prime = false;
    if (number >= 2) {
        var i = 2;
        is_prime = true;
        while (i * i <= number) : (i += 1) {
            if (number % i == 0) {
                is_prime = false;
                break;
            }
        }
    }
    return is_prime;
}

pub fn ModInt(modulo: comptime_int) type {
    return ModIntEx(modulo, isPrime(modulo));
}

pub fn PrimeModInt(modulo: comptime_int) type {
    return ModIntEx(modulo, true);
}

pub fn ModIntEx(modulo: comptime_int, comptime modulo_is_prime: bool) type {
    if (modulo <= 0) @compileError("Modulo must be positive");
    return struct {
        const Self = @This();
        pub const Int = std.meta.Int(.unsigned, requiringBits(modulo - 1));
        pub const Extended = std.meta.Int(.unsigned, requiringBits(modulo - 1) + 1);
        value: Int,
        pub const zero: Self = .{ .value = 0 };
        pub const one: Self = .{ .value = 1 };

        pub fn add(self: Self, other: Self) Self {
            const a: Extended = self.value;
            const b: Extended = other.value;
            return .{
                .value = @intCast((a + b) % modulo),
            };
        }

        pub fn iadd(self: *Self, other: Self) void {
            self.* = self.add(other);
        }

        pub fn sub(self: Self, other: Self) Self {
            const a: Extended = self.value;
            const b: Extended = other.value;
            return .{
                .value = @intCast((a + modulo - b) % modulo),
            };
        }

        pub fn isub(self: *Self, other: Self) void {
            self.* = self.sub(other);
        }

        pub fn mul(self: Self, other: Self) Self {
            const prod = std.math.mulWide(Int, self.value, other.value);
            return .{
                .value = @intCast(prod % modulo),
            };
        }

        pub fn imul(self: *Self, other: Self) void {
            self.* = self.mul(other);
        }

        pub fn pow(self: Self, exp: anytype) Self {
            var base = self;
            var result = Self.one;
            switch (@typeInfo(@TypeOf(exp))) {
                .int => |int| {
                    if (int.signedness == .signed) {
                        @compileError("Signed int is not allowed");
                    }
                    var exp_cur = exp;
                    while (exp_cur > 0) : (exp_cur >>= 1) {
                        if (exp_cur % 2 != 0) result = result.mul(base);
                        base = base.mul(base);
                    }
                },
                .comptime_int => {
                    comptime var exp_cur = exp;
                    inline while (exp_cur > 0) : (exp_cur >>= 1) {
                        if (exp_cur % 2 != 0) result = result.mul(base);
                        base = base.mul(base);
                    }
                },
                else => {
                    @compileError("Only int or comptime_int allowed for exponent");
                },
            }
            return result;
        }

        pub fn powSignedExp(self: Self, exp: anytype) Self {
            switch (@typeInfo(@TypeOf(exp))) {
                .int, .comptime_int => {},
                else => @compileError("Only int or comptime_int allowed for exponent"),
            }
            const base = if (exp < 0) self.inv() else self;
            return base.pow(@abs(exp));
        }

        pub fn inv(self: Self) Self {
            if (!modulo_is_prime) @compileError("Non-prime modulo integer is not support inverse operation");
            return self.pow(modulo - 2);
        }

        pub fn fromRaw(value: Int) Self {
            return .{ .value = value };
        }

        pub fn init(value: anytype) Self {
            const info = @typeInfo(@TypeOf(value));
            switch (info) {
                .int, .comptime_int => {},
                else => {
                    @compileError("Only int or comptime_int allowed to initialize ModInt");
                },
            }
            return .{ .value = @intCast(@mod(value, modulo)) };
        }

        pub fn format(self: Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            return w.print("{d}", .{self.value});
        }

        pub fn random(rng: std.Random) Self {
            const value = rng.uintLessThan(Int, modulo - 1);
            std.debug.assert(value < modulo);
            return .{
                .value = value,
            };
        }

        pub const Combination = struct {
            factorial: []Self,
            factorial_inv: []Self,

            pub fn init(n: usize, gpa: mem.Allocator) mem.Allocator.Error!Combination {
                const fact = try gpa.alloc(Self, n + 1);
                errdefer gpa.free(fact);
                const fact_i = try gpa.alloc(Self, n + 1);
                fact[0] = .one;
                for (1..n + 1) |i| {
                    fact[i] = Self.init(i).mul(fact[i - 1]);
                }
                fact_i[n] = fact[n].inv();
                var i = n;
                while (i > 0) : (i -= 1) {
                    fact_i[i - 1] = Self.init(i).mul(fact_i[i]);
                }
                return .{
                    .factorial = fact,
                    .factorial_inv = fact_i,
                };
            }

            pub fn deinit(self: Combination, gpa: mem.Allocator) void {
                gpa.free(self.factorial);
                gpa.free(self.factorial_inv);
            }

            /// `n`個の中から`k`個選ぶときの組み合わせ数を返す
            pub fn combi(self: Combination, n: usize, k: usize) Self {
                return if (k > n) .zero else self.factorial[n].mul(self.factorial_inv[k]).mul(self.factorial_inv[n - k]);
            }
        };
    };
}

const testing = std.testing;
const expectEqual = testing.expectEqual;

test "ModInt" {
    const MInt = ModInt(998244353);
    const a = MInt.init(-1);
    const b = MInt.init(-1);
    try expectEqual(a.mul(b), MInt.init(1));
    try expectEqual(a.add(b), MInt.init(-2));
    try expectEqual(a.sub(b), MInt.init(0));
}

test "pow" {
    const MInt = ModInt(998244353);
    const a = MInt.init(100);
    const b = a.inv();
    try expectEqual(MInt.init(10000), a.pow(2));
    try expectEqual(MInt.init(1), a.mul(b));
}

test "non-prime pow" {
    const MInt = ModInt(100000);
    const a = MInt.init(2);
    try expectEqual(MInt.init(1 << 40), a.pow(40));
    try expectEqual(MInt.init(1 << 39), a.powSignedExp(39));
    var e: u32 = 38;
    _ = &e;
    try expectEqual(MInt.init(1 << 38), a.powSignedExp(e));
}

test "combination" {
    const MInt = ModInt(1000000007);
    const c = try MInt.Combination.init(20, testing.allocator);
    defer c.deinit(testing.allocator);
    try expectEqual(MInt.init(3628800), c.factorial[10]);
    try expectEqual(MInt.init(3628800).inv(), c.factorial_inv[10]);
    try expectEqual(MInt.init(252), c.combi(10, 5));
    try expectEqual(MInt.init(210), c.combi(10, 6));
    try expectEqual(MInt.one, c.combi(10, 10));
    try expectEqual(MInt.one, c.combi(10, 0));
    try expectEqual(MInt.zero, c.combi(10, 20));
}
