const std = @import("std");
const print = std.debug.print;
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

        // SQLite Header
        var reader = try SQLiteReader.init("sample.db");
        defer reader.deinit();

        print("Page size: {}\n", .{reader.page_size});
        print("Database size: {}\n", .{reader.database_size});

        // Page 1
        const page1 = try reader.readPage(1, allocator);
        defer allocator.free(page1);

        utils.hexdump(page1[100..116], 16);

        const header = try SQLiteReader.parsePageHeader(page1, true);
        print("Page type: {}\n", .{header.page_type});
        print("Cell count: {}\n", .{header.cell_count});
        print("Cell content offset: {}\n", .{header.cell_content_offset});

        // Cell reading
        const cells = try SQLiteReader.parseCells(page1, true, allocator);
        defer {
            for (cells) |cell| {
                switch (cell) {
                    .LeafTable => |c| allocator.free(c.payload),
                    .LeafIndex => |c| allocator.free(c.payload),
                    .InteriorIndex => |c| allocator.free(c.payload),
                    .InteriorTable => {},
                }
            }
            allocator.free(cells);
        }

        print("Number of cells on page 1: {}\n", .{cells.len});
        for (cells, 0..cells.len) |cell, i| {
            print("Cell {}: ", .{i});
            switch (cell) {
                .InteriorIndex => |c| print("InteriorIndex (left child: {}, payload_size: {})\n", .{ c.left_child_ptr, c.payload_size }),
                .InteriorTable => |c| print("InteriorTable (left child: {}, rowid: {})\n", .{ c.left_child_ptr, c.rowid }),
                .LeafIndex => |c| print("LeafIndex (payload_size: {})\n", .{c.payload_size}),
                .LeafTable => |c| print("LeafTable (rowid: {}, payload_size: {})\n", .{ c.rowid, c.payload_size }),
            }
        }
    }
}
