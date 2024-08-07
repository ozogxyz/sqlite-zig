const std = @import("std");

const SQLiteReader = @import("btree.zig").SQLiteReader;
const utils = @import("utils.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        try std.io.getStdErr().writer().print(
            "Usage: {s} <database_file_path> <command>\n",
            .{args[0]},
        );
        return;
    }

    const database_file_path: []const u8 = args[1];
    const command: []const u8 = args[2];

    if (std.mem.eql(u8, command, ".dbinfo")) {
        var file = try std.fs.cwd().openFile(database_file_path, .{});
        defer file.close();

        try std.io.getStdOut().writer().print(
            "Logs from your program will appear here\n",
            .{},
        );

        var reader = try SQLiteReader.init("sample.db");
        defer reader.deinit();

        std.debug.print("Page size: {}\n", .{reader.page_size});
        std.debug.print("Database size: {}\n", .{reader.database_size});

        const page1 = try reader.readPage(1, allocator);
        defer allocator.free(page1);

        std.debug.print("First byte of page 1: {x:0>2}\n", .{page1[0]});
        std.debug.print("Bytes 101-104 of page 1: {x:0>2} {x:0>2} {x:0>2} {x:0>2}\n", .{ page1[100], page1[101], page1[102], page1[103] });

        utils.hexdump(page1, 16);

        const header = try SQLiteReader.parsePageHeader(page1, true);
        std.debug.print("Page type: {}\n", .{header.page_type});
        std.debug.print("Cell count: {}\n", .{header.cell_count});
        std.debug.print("Cell content offset: {}\n", .{header.cell_content_offset});
    }
}
