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
fn find_root(modulo: comptime_int) super.ModInt(modulo) {
    if (modulo == 2) return .one;
    var pcg = std.Random.Pcg.init(3405073802013788547);
    const rng = pcg.random();
}

pub fn Roots(modulo: comptime_int) type {
    const modulo_is_prime = super.isPrime(modulo);
    return struct {
        const Int = super.ModInt(modulo);

    };
}