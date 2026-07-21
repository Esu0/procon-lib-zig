const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const modulo = @import("../root.zig");
const ModInt = modulo.ModInt;
const RootsPowerOf2 = modulo.convolution.RootsPowerOf2;

fn nttNaive(comptime mod: comptime_int, arr: []const ModInt(mod), dst: []ModInt(mod), roots: RootsPowerOf2(mod)) void {
    assert(std.math.isPowerOfTwo(arr.len));
    assert(arr.len == dst.len);

    const log = std.math.log2_int(usize, arr.len);
    const root = roots.getRoot(log, false);
    var x: ModInt(mod) = .one;
    for (0..dst.len) |i| {
        var v: ModInt(mod) = .zero;
        var p: ModInt(mod) = .one;
        for (arr) |a| {
            v.iadd(a.mul(p));
            p.imul(x);
        }
        x.imul(root);
        dst[i] = v;
    }
}

// pub fn nttInplace(comptime mod: comptime_int, arr: []ModInt(mod), roots: RootsPowerOf2(mod), inv: bool) void {
//     assert(std.math.isPowerOfTwo(arr.len));

//     const log = std.math.log2_int(usize, arr.len);
//     for (0..arr.len) |i| {
//         const rev = @bitReverse(i) >> @intCast(@typeInfo(usize).int.bits - log);
//         if (rev > i) {
//             std.mem.swap(ModInt(mod), &arr[i], &arr[rev]);
//         }
//     }
//     nttInplaceInner(mod, arr, roots, inv, .in);
// }

// fn nttRecursive(comptime mod: comptime_int, arr: []ModInt(mod), root: ModInt(mod)) void {
//     if (arr.len == 1) return;
//     const arr1 = arr[0..arr.len/2];
//     const arr2 = arr[arr.len/2..];
//     var r: ModInt(mod) = .one;
//     for (0..arr.len/2) |i| {
//         const a = arr1[i];
//         const b = arr2[i];
//         arr1[i] = a.add(b);
//         arr2[i] = a.sub(b).mul(r);
//         r.imul(root);
//     }
//     const nr = root.mul(root);
//     nttRecursive(mod, arr1, nr);
//     nttRecursive(mod, arr2, nr);
// }

pub fn bitReverseOrder(comptime T: type, buf: []T) void {
    assert(std.math.isPowerOfTwo(buf.len));
    const log = std.math.log2_int(usize, buf.len);
    for (0..buf.len) |i| {
        const rev = @bitReverse(i) >> @intCast(@typeInfo(usize).int.bits - log);
        if (i < rev) {
            std.mem.swap(T, &buf[i], &buf[rev]);
        }
    }
}

pub const Port = enum {
    in,
    out,
};

pub fn nttInplace(
    comptime mod: comptime_int,
    arr: []ModInt(mod),
    roots: RootsPowerOf2(mod),
    inv: bool,
    comptime bit_reverse_order: Port,
) void {
    assert(std.math.isPowerOfTwo(arr.len));
    var log = std.math.log2_int(usize, arr.len);
    const r4th = roots.getRoot(2, inv);
    switch (bit_reverse_order) {
        .in => {
            const log_r = log;
            if (log % 2 != 0) {
                for (0..arr.len/2) |i| {
                    const x = arr[i*2];
                    const y = arr[i*2+1];
                    arr[i*2] = x.add(y);
                    arr[i*2+1] = x.sub(y);
                }
                log -= 1;
            }

            while (log >= 2) {
                const nlog = log - 2;
                defer log = nlog;
                const sz = arr.len >> log;
                const para = @as(usize, 1) << nlog;
                const rt = roots.getRoot(log_r - nlog, inv);
                for (0..para) |b| {
                    const ofs = b * sz * 4;
                    const blk0 = arr[ofs..][0..sz];
                    const blk1 = arr[ofs+sz..][0..sz];
                    const blk2 = arr[ofs+sz*2..][0..sz];
                    const blk3 = arr[ofs+sz*3..][0..sz];
                    var r: ModInt(mod) = .one;
                    for (0..sz) |i| {
                        const r2 = r.mul(r);
                        const r3 = r2.mul(r);
                        const x = blk0[i];
                        const y = blk1[i].mul(r2);
                        var z = blk2[i].mul(r);
                        var w = blk3[i].mul(r3);
                        blk0[i] = x.add(y).add(z).add(w);
                        blk2[i] = x.add(y).sub(z).sub(w);
                        z.imul(r4th);
                        w.imul(r4th);
                        blk1[i] = x.sub(y).add(z).sub(w);
                        blk3[i] = x.sub(y).sub(z).add(w);
                        r.imul(rt);
                    }
                }
            }
        },
        .out => {
            while (log >= 2) {
                const nlog = log - 2;
                defer log = nlog;
                const para = arr.len >> log;
                const sz = @as(usize, 1) << nlog;
                const rt = roots.getRoot(log, inv);
                for (0..para) |b| {
                    const ofs = b * sz * 4;
                    const blk0 = arr[ofs..][0..sz];
                    const blk1 = arr[ofs+sz..][0..sz];
                    const blk2 = arr[ofs+sz*2..][0..sz];
                    const blk3 = arr[ofs+sz*3..][0..sz];
                    var r: ModInt(mod) = .one;
                    for (0..sz) |i| {
                        const x = blk0[i];
                        var y = blk1[i];
                        const z = blk2[i];
                        var w = blk3[i];
                        const r2 = r.mul(r);
                        const r3 = r2.mul(r);
                        blk0[i] = x.add(y).add(z).add(w);
                        blk1[i] = x.sub(y).add(z).sub(w).mul(r2);
                        y.imul(r4th);
                        w.imul(r4th);
                        blk2[i] = x.add(y).sub(z).sub(w).mul(r);
                        blk3[i] = x.sub(y).sub(z).add(w).mul(r3);
                        r.imul(rt);
                    }
                }
            }

            if (log != 0) {
                assert(log == 1);
                for (0..arr.len / 2) |i| {
                    const x = arr[i*2];
                    const y = arr[i*2+1];
                    arr[i*2] = x.add(y);
                    arr[i*2+1] = x.sub(y);
                }
            }
        },
    }
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;
test "inplace ntt" {
    const MInt = ModInt(998244353);
    var pcg = std.Random.DefaultPrng.init(testing.random_seed);
    const rng = pcg.random();
    const log = 9;
    var arr: [1<<log]MInt = undefined;
    for (0..arr.len) |i| {
        arr[i] = .random(rng);
    }
    var expected: [arr.len]MInt = undefined;
    const roots: RootsPowerOf2(MInt.mod) = .{};
    nttNaive(MInt.mod, &arr, &expected, roots);
    bitReverseOrder(MInt, &arr);
    nttInplace(MInt.mod, &arr, roots, false, .in);
    try expectEqualSlices(MInt, &arr, &expected);
}
