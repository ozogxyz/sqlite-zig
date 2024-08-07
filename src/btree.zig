const std = @import("std");
const fs = std.fs;
const utils = @import("utils.zig");
const mem = std.mem;

const SQLITE_MAGIC = "SQLite format 3\x00";
const SQLITE_HEADER_SIZE = 100;

pub const PageType = enum(u8) {
    InteriorIndex = 2,
    InteriorTable = 5,
    LeafIndex = 10,
    LeafTable = 13,
};

pub const CellType = union(enum) {
    InteriorIndex: struct {
        left_child_ptr: u32,
        payload_size: u64,
        payload: []const u8,
    },
    InteriorTable: struct {
        left_child_ptr: u32,
        rowid: u64,
    },
    LeafIndex: struct {
        payload_size: u64,
        payload: []const u8,
    },
    LeafTable: struct {
        payload_size: u64,
        rowid: u64,
        payload: []const u8,
    },
};

pub const PageHeader = struct {
    page_type: PageType,
    first_freeblock_offset: u16,
    cell_count: u16,
    cell_content_offset: u16,
    freeblock_count: u8,
    rightmost_ptr: ?u32,
};

pub const SQLiteReader = struct {
    file: fs.File,
    page_size: u16,
    database_size: u32,

    pub fn init(filename: []const u8) !SQLiteReader {
        const file = try fs.cwd().openFile(filename, .{});
        errdefer file.close();

        var header: [100]u8 = undefined;
        _ = try file.readAll(&header);

        if (!std.mem.eql(u8, header[0..16], SQLITE_MAGIC)) {
            return error.InvalidSQLiteHeader;
        }

        const page_size = std.mem.readInt(u16, header[16..18], .big);
        const database_size = std.mem.readInt(u32, header[28..32], .big);

        return SQLiteReader{
            .file = file,
            .page_size = page_size,
            .database_size = database_size,
        };
    }

    pub fn deinit(self: *SQLiteReader) void {
        self.file.close();
    }

    pub fn readPage(self: *SQLiteReader, page_number: u32, alloc: mem.Allocator) ![]u8 {
        const offset = (page_number - 1) * self.page_size;
        try self.file.seekTo(offset);

        const page = try alloc.alloc(u8, self.page_size);
        errdefer alloc.free(page);

        const bytes_read = try self.file.readAll(page);
        if (bytes_read != self.page_size) {
            return error.IncompleteRead;
        }

        return page;
    }

    pub fn parsePageHeader(page: []const u8, comptime is_first_bool: bool) !PageHeader {
        const header_start = if (is_first_bool) SQLITE_HEADER_SIZE else 0;
        if (page.len < header_start + 8) {
            return error.InvalidPageData;
        }

        const page_type = std.meta.intToEnum(PageType, page[header_start]) catch {
            return error.InvalidPageType;
        };

        var header = PageHeader{
            .page_type = page_type,
            .first_freeblock_offset = std.mem.readInt(u16, page[header_start + 1 .. header_start + 3], .big),
            .cell_count = std.mem.readInt(u16, page[header_start + 3 .. header_start + 5], .big),
            .cell_content_offset = std.mem.readInt(u16, page[header_start + 5 .. header_start + 7], .big),
            .freeblock_count = page[7],
            .rightmost_ptr = null,
        };

        if (page_type == .InteriorIndex or page_type == .InteriorTable) {
            if (page.len < 12) {
                return error.InvalidPage;
            }

            header.rightmost_ptr = std.mem.readInt(u32, page[header_start + 8 .. header_start + 12], .big);
        }

        return header;
    }

    pub fn parseCell(page: []const u8, page_type: PageType, cell_offset: u16, alloc: mem.Allocator) !CellType {
        var stream = std.io.fixedBufferStream(page[cell_offset..]);
        var reader = stream.reader();

        switch (page_type) {
            .InteriorIndex => {
                const left_child_ptr = try reader.readInt(u32, .big);
                const payload_size = try utils.readVarint(&reader);
                const payload = try alloc.alloc(u8, @intCast(payload_size));
                _ = try reader.readAll(payload);
                return CellType{
                    .InteriorIndex = .{
                        .left_child_ptr = left_child_ptr,
                        .payload_size = payload_size,
                        .payload = payload,
                    },
                };
            },
            .InteriorTable => {
                const left_child_ptr = try reader.readInt(u32, .big);
                const rowid = try utils.readVarint(&reader);
                return CellType{
                    .InteriorTable = .{
                        .left_child_ptr = left_child_ptr,
                        .rowid = rowid,
                    },
                };
            },
            .LeafIndex => {
                const payload_size = try utils.readVarint(&reader);
                const payload = try alloc.alloc(u8, @intCast(payload_size));
                _ = try reader.readAll(payload);
                return CellType{
                    .LeafIndex = .{
                        .payload_size = payload_size,
                        .payload = payload,
                    },
                };
            },
            .LeafTable => {
                const payload_size = try utils.readVarint(&reader);
                const rowid = try utils.readVarint(&reader);
                const payload = try alloc.alloc(u8, @intCast(payload_size));
                _ = try reader.readAll(payload);
                return CellType{
                    .LeafTable = .{
                        .payload_size = payload_size,
                        .rowid = rowid,
                        .payload = payload,
                    },
                };
            },
        }
    }

    pub fn parseCells(page: []const u8, comptime is_first_page: bool, alloc: mem.Allocator) ![]CellType {
        const header = try SQLiteReader.parsePageHeader(page, is_first_page);
        const cells = try alloc.alloc(CellType, header.cell_count);
        errdefer alloc.free(cells);

        const cell_ptr_arr_offset = if (is_first_page) SQLITE_HEADER_SIZE + 8 else 8;
        var cell_ptr_stream = std.io.fixedBufferStream(page[cell_ptr_arr_offset..]);
        var cell_ptr_reader = cell_ptr_stream.reader();

        for (cells) |*cell| {
            const cell_offset = try cell_ptr_reader.readInt(u16, .big);
            cell.* = try SQLiteReader.parseCell(page, header.page_type, cell_offset, alloc);
        }

        return cells;
    }
};
