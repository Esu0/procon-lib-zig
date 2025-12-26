const std = @import("std");

/// i番目の要素に入る値:
/// * `string[0..i + 1]`において、それ自身と一致しない接頭辞と接尾辞が一致する最大の長さ
pub fn partialMatchTable(comptime T: type, string: []const T, buffer: []u32) []u32 {
    std.debug.assert(string.len <= buffer.len);
    for (string, 0..) |ci, i| {
        var j = i;
        buffer[i] = blk: while (true) {
            if (j == 0) {
                break :blk 0;
            }
            j = buffer[j - 1];
            if (ci == string[j]) {
                break :blk @intCast(j + 1);
            }
        };
    }
    return buffer[0..string.len];
}

pub fn indexOfPattern(comptime T: type, string: []const T, pattern: []const T, partial_match_table: []const u32) ?u32 {
    return searchPattern(
        T,
        string,
        pattern,
        partial_match_table,
        u32,
        struct { fn do(idx: u32) ?u32 {
            return idx;
        }}.do,
    );
}

pub fn searchPattern(
    comptime T: type,
    string: []const T,
    pattern: []const T,
    partial_match_table: []const u32,
    comptime Return: type,
    comptime do: fn (u32) ?Return,
) ?Return {
    if (pattern.len == 0) {
        var i: u32 = 0;
        while (i <= string.len) : (i += 1) {
            if (do(i)) |retval| return retval;
        }
        return null;
    }
    var j: u32 = 0;
    for (string, 0..) |ci, i| {
        while (true) {
            if (ci == pattern[j]) {
                j += 1;
                break;
            }
            if (j == 0) {
                break;
            }
            j = partial_match_table[j - 1];
        }
        if (j == pattern.len) {
            if (do(@intCast(i + 1 - pattern.len))) |retval| return retval;
            j = partial_match_table[j - 1];
        }
    }
    return null;
}

fn partialMatchTableNaive(comptime T: type, string: []const T, buffer: []u32) []u32 {
    std.debug.assert(string.len <= buffer.len);
    for (0..buffer.len) |i| {
        var j = i + 1;
        while (j > 0) : (j -= 1) {
            if (std.mem.eql(T, string[0..j], string[i - j + 1..i + 1])) {
                buffer[i] = j;
                break;
            }
        }
    }
    return buffer[0..string.len];
}

const testing = std.testing;
const expectEqualSlices = testing.expectEqualSlices;
const expectEqual = testing.expectEqual;

test "partial match table" {
    var buffer: [100]u32 = undefined;
    {
        const string = "abcabcdabcabcdea";
        const b1 = partialMatchTable(u8, string, &buffer);
        const b2 = partialMatchTable(u8, string, buffer[string.len..]);
        try expectEqualSlices(u32, b2, b1);
    }
    {
        const string = "aaaaaaaaaaaaaa";
        const b1 = partialMatchTable(u8, string, &buffer);
        const b2 = partialMatchTable(u8, string, buffer[string.len..]);
        try expectEqualSlices(u32, b2, b1);
    }
}

test "kmp" {
    var buffer: [100]u32 = undefined;
    {
        const s = "aabaabbaaabab";
        const t = "aaaba";
        const table = partialMatchTable(u8, t, &buffer);
        try expectEqual(7, indexOfPattern(u8, s, t, table));
    }
    {
        const s = "aabaabbaaabab";
        const t = "aaabaa";
        const table = partialMatchTable(u8, t, &buffer);
        try expectEqual(null, indexOfPattern(u8, s, t, table));
    }
    {
        const s = "bbaababababaab";
        const t = "abababaab";
        const table = partialMatchTable(u8, t, &buffer);
        try expectEqual(5, indexOfPattern(u8, s, t, table));
    }

    {
        const s = "aaaaabaaaaa";
        const t = "aaa";
        const table = partialMatchTable(u8, t, &buffer);
        const container = struct {
            var buf: [12]u32 = undefined;
            var list: std.ArrayList(u32) = undefined;
            fn do(idx: u32) ?void {
                list.appendAssumeCapacity(idx);
                return null;
            }
        };
        container.list = std.ArrayList(u32).initBuffer(&container.buf);
        _ = searchPattern(u8, s, t, table, void, container.do);
        const expected = [6]u32{0, 1, 2, 6, 7, 8};
        try expectEqualSlices(u32, &expected, container.list.items);
    }
}
