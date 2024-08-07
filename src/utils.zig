const std = @import("std");

pub fn readVarint(buf: []const u8) !u64 {
    var result: u64 = 0;
    var shift: u6 = 0;

    for (buf) |byte| {
        result |= @as(u64, byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
        if (shift >= 64) return error.VarintTooLarge;
    }

    return result;
}

pub fn varintSize(value: u64) usize {
    if (value < 128) return 1;
    var size: usize = 1;
    var v = value >> 7;
    while (v > 0) : (v >>= 7) {
        size += 1;
    }
    return size;
}

pub fn hexdump(data: []const u8, bytes_per_line: usize) void {
    for (data, 0..) |byte, i| {
        if (i % bytes_per_line == 0) {
            if (i != 0) {
                std.debug.print("\n", .{});
            }
            std.debug.print("{X:0>4}: ", .{i});
        }
        std.debug.print("{x:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});
}
