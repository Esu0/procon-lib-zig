const std = @import("std");
const assert = std.debug.assert;
const INSERTION_THRESHOLD = 16;

pub fn select_nth(
    comptime T: type,
    items: []T,
    index: usize,
    context: anytype,
    comptime lessThanFn: fn (ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) void {
    if (index == items.len) return;
    var array = items;
    var idx = index;
    var limit: u8 = 16;
    var ancestor_pivot: ?T = null;

    while (true) {
        assert(idx < array.len);
        if (idx == 0) {
            const minIdx = argMin(T, array, context, lessThanFn);
            std.mem.swap(T, &array[minIdx], &array[0]);
            return;
        }
        if (idx == array.len - 1) {
            const maxIdx = argMax(T, array, context, lessThanFn);
            std.mem.swap(T, &array[maxIdx], &array[array.len - 1]);
            return;
        }
        if (array.len <= INSERTION_THRESHOLD) {
            std.sort.insertionContext(0, array.len, struct {
                inner: @TypeOf(context),
                items: []T,
                pub fn swap(ctx: @This(), ind1: usize, ind2: usize) void {
                    std.mem.swap(T, &ctx.items[ind1], &ctx.items[ind2]);
                }
                pub fn lessThan(ctx: @This(), ind1: usize, ind2: usize) bool {
                    return lessThanFn(ctx.inner, ctx.items[ind1], ctx.items[ind2]);
                }
            } {
                .inner = context,
                .items = array,
            });
            return;
        }

        var piv: usize = undefined;
        if (limit == 0) {
            piv = medianOfNinthers(T, array, context, lessThanFn);
        } else {
            limit -= 1;
            piv = median3rec(T, array, context, lessThanFn);
        }

        if (ancestor_pivot) |p| {
            if (!lessThanFn(context, p, array[piv])) {
                // p == array[piv]
                const eq_cnt = partition(
                    T,
                    array,
                    piv,
                    context,
                    struct {
                        fn lessThanEq(ctx: @TypeOf(context), lhs: T, rhs: T) bool {
                            return !lessThanFn(ctx, rhs, lhs);
                        }
                    }.lessThanEq
                ) + 1;
                if (idx < eq_cnt) {
                    return;
                }
                array = array[eq_cnt..];
                idx -= eq_cnt;
                ancestor_pivot = null;
                continue;
            }
        }

        const piv_idx = partition(T, array, piv, context, lessThanFn);

        assert(piv_idx < array.len);
        switch (std.math.order(piv_idx, idx)) {
            .lt => {
                ancestor_pivot = array[piv_idx];
                array = array[piv_idx + 1..];
                idx -= piv_idx + 1;
            },
            .eq => return,
            .gt => {
                array = array[0..piv_idx];
            }
        }
    }
}

fn medianOfNinthers(
    comptime T: type,
    array: []T,
    context: anytype,
    comptime lessThanFn: fn (ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) usize {
    const frac = if (array.len <= 1024)
        array.len / 12
    else if (array.len <= 128*1024)
        array.len / 64
    else
        array.len / 1024;

    const piv = frac / 2;
    const lo = array.len / 2 - piv;
    const hi = frac + lo;
    const gap = (array.len - 9 * frac) / 4;
    var a = lo - 4 * frac - gap;
    var b = hi + gap;
    for (lo..hi) |i| {
        ninther(T, array, a, i - frac, b, a + 1, i, b + 1, a + 2, i + frac, b + 2, context, lessThanFn);
        a += 3;
        b += 3;
    }
    select_nth(T, array[lo..lo + frac], piv, context, lessThanFn);
    return lo + piv;
}

fn ninther(
    comptime T: type,
    array: []T,
    a: usize,
    b: usize,
    c: usize,
    d: usize,
    e: usize,
    f: usize,
    g: usize,
    h: usize,
    i: usize,
    context: anytype,
    comptime lessThanFn: fn (ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) void {
    var nb = medianIndex(T, array, a, b, c, context, lessThanFn);
    var nh = medianIndex(T, array, g, h, i, context, lessThanFn);
    if (lessThanFn(context, array[nh], array[nb])) {
        std.mem.swap(usize, &nb, &nh);
    }
    var nf = f;
    var nd = d;
    if (lessThanFn(context, array[nf], array[nd])) {
        std.mem.swap(usize, &nd, &nf);
    }
    if (lessThanFn(context, array[e], array[nd])) {

    } else if (lessThanFn(context, array[nf], array[e])) {
        nd = nf;
    } else {
        if (lessThanFn(context, array[e], array[nb])) {
            std.mem.swap(T, &array[e], &array[nd]);
        } else if (lessThanFn(context, array[nh], array[e])) {
            std.mem.swap(T, &array[nh], &array[e]);
        }
        return;
    }
    if (lessThanFn(context, array[nd], array[nb])) {
        nd = nb;
    } else if (lessThanFn(context, array[nh], array[nd])) {
        nd = nh;
    }
    std.mem.swap(T, &array[nd], &array[e]);
}

inline fn medianIndex(
    comptime T: type,
    array: []const T,
    a: usize,
    b: usize,
    c: usize,
    context: anytype,
    comptime lessThanFn: fn (ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) usize {
    var na = a;
    var nc = c;
    if (lessThanFn(context, array[c], array[a])) {
        std.mem.swap(usize, &na, &nc);
    }
    if (lessThanFn(context, array[nc], array[b])) return nc;
    if (lessThanFn(context, array[b], array[na])) return na;
    return b;
}

fn argMin(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThanFn: fn (ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) usize {
    assert(items.len > 0);
    var min = items[0];
    var idx: usize = 0;
    for (1.., items[1..]) |i, v| {
        if (lessThanFn(context, v, min)) {
            min = v;
            idx = i;
        }
    }
    return idx;
}

fn argMax(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThanFn: fn(ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) usize {
    assert(items.len > 0);
    var max = items[0];
    var idx: usize = 0;
    for (1.., items[1..]) |i, v| {
        if (lessThanFn(context, max, v)) {
            max = v;
            idx = i;
        }
    }
    return idx;
}

pub fn partition(
    comptime T: type,
    items: []T,
    piv_idx: usize,
    context: anytype,
    comptime lessThanFn: fn (ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) usize {
    const piv = items[piv_idx];
    items[piv_idx] = items[0];
    var j: usize = 1;
    for (1..items.len) |i| {
        std.mem.swap(T, &items[i], &items[j]);
        j += @intFromBool(lessThanFn(context, items[j], piv));
    }
    j -= 1;
    assert(j < items.len);
    items[0] = items[j];
    items[j] = piv;
    return j;
}

fn median3rec(
    comptime T: type,
    items: []const T,
    context: anytype,
    comptime lessThanFn: fn (ctx: @TypeOf(context), lhs: T, rhs: T) bool,
) usize {
    if (items.len < 8) return 0;
    const div8 = items.len / 8;
    const items_a = items[0..div8];
    const a = median3rec(T, items_a, context, lessThanFn);
    const items_b = items[div8*4..][0..div8];
    const b = median3rec(T, items_b, context, lessThanFn) + div8 * 4;
    const items_c = items[div8*7..][0..div8];
    const c = median3rec(T, items_c, context, lessThanFn) + div8 * 7;
    return medianIndex(T, items, a, b, c, context, lessThanFn);
}

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const expectEqualSlices = std.testing.expectEqualSlices;
test "partition" {
    var arr = [_]u32{ 3, 1, 4, 1 ,5, 9 };
    const idx = partition(u32, &arr, 0, {}, std.sort.asc(u32));
    try expectEqual(3, arr[idx]);
    try expectEqual(2, idx);
}

test "partition big" {
    const gpa = std.testing.allocator;
    var prng: std.Random.DefaultPrng = .init(std.testing.random_seed);
    const rng = prng.random();
    const arr = try gpa.alloc(u32, 500);
    defer gpa.free(arr);
    for (0..arr.len) |i| arr[i] = rng.intRangeLessThan(u32, 0, 500);

    const arr_sorted = try gpa.dupe(u32, arr);
    defer gpa.free(arr_sorted);
    std.mem.sortUnstable(u32, arr_sorted, {}, std.sort.asc(u32));

    const piv_idx = rng.intRangeLessThan(usize, 0, arr.len);
    const piv = arr[piv_idx];
    const idx = partition(u32, arr, piv_idx, {}, std.sort.asc(u32));
    try expectEqual(piv, arr[idx]);
    for (0..idx) |i| {
        try expect(arr[i] < piv);
    }
    for (idx+1..arr.len) |i| {
        try expect(arr[i] >= piv);
    }
    std.mem.sortUnstable(u32, arr, {}, std.sort.asc(u32));
    try expectEqualSlices(u32, arr_sorted, arr);
}

test "select" {
    const gpa = std.testing.allocator;
    var prng: std.Random.DefaultPrng = .init(std.testing.random_seed);
    const rng = prng.random();
    for (0..100) |_| {
        // random
        const len = rng.intRangeLessThan(usize, 1, 100);
        const arr = try gpa.alloc(u32, len);
        defer gpa.free(arr);
        for (0..len) |i| arr[i] = rng.intRangeLessThan(u32, 0, @intCast(len));

        const arr_sorted = try gpa.dupe(u32, arr);
        defer gpa.free(arr_sorted);
        std.mem.sortUnstable(u32, arr_sorted, {}, std.sort.asc(u32));

        for (0..len) |n| {
            rng.shuffle(u32, arr);
            select_nth(u32, arr, n, {}, std.sort.asc(u32));
            const nth = arr[n];

            std.debug.print("\n", .{});
            for (0..n) |i| {
                try expect(arr[i] <= nth);
            }
            for (n+1..len) |i| {
                try expect(arr[i] >= nth);
            }
            std.mem.sortUnstable(u32, arr, {}, std.sort.asc(u32));
            try expectEqualSlices(u32, arr_sorted, arr);
        }
    }

    for (0..100) |_| {
        // small
        const len = rng.intRangeLessThan(usize, 10, 100);
        const arr = try gpa.alloc(u32, len);
        defer gpa.free(arr);
        for (0..len) |i| arr[i] = rng.intRangeLessThan(u32, 0, @intCast(len / 10));

        const arr_sorted = try gpa.dupe(u32, arr);
        defer gpa.free(arr_sorted);
        std.mem.sortUnstable(u32, arr_sorted, {}, std.sort.asc(u32));

        for (0..len) |n| {
            rng.shuffle(u32, arr);
            select_nth(u32, arr, n, {}, std.sort.asc(u32));
            const nth = arr[n];
            // std.debug.print("{any}\n", .{arr});
            for (0..n) |i| {
                try expect(arr[i] <= nth);
            }
            for (n+1..len) |i| {
                try expect(arr[i] >= nth);
            }
            std.mem.sortUnstable(u32, arr, {}, std.sort.asc(u32));
            try expectEqualSlices(u32, arr_sorted, arr);
        }
    }
}

test "select big" {
    const gpa = std.testing.allocator;
    const arr = try gpa.alloc(u32, 100000);
    defer gpa.free(arr);
    @memset(arr, 0);
    const expected = try gpa.dupe(u32, arr);
    defer gpa.free(expected);

    select_nth(u32, arr, arr.len / 2, {}, std.sort.asc(u32));
    try expectEqualSlices(u32, expected, arr);
}