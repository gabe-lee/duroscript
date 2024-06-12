const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const ListUm = std.ArrayListUnmanaged;
const SourceRange = @import("./SourceReader.zig").SourceRange;

var NoticeAlloc = Arena.init(std.heap.page_allocator);

pub const Notice = struct {
    message: []const u8,
    location: SourceRange,

    pub fn string(self: *const Notice) []const u8 {
        return std.fmt.allocPrint(NoticeAlloc.allocator(), "ERROR: {s}:{d}:{d}\n{s}", .{ self.location.source_name, self.location.start.row + 1, self.location.start.col + 1, self.message }) catch "ERROR: COULD NOT PRINT ERROR :(";
    }
};

pub const KIND = enum(u8) {
    ERROR,
    WARN,
    HINT,
};

pub fn kind_string(comptime kind: KIND) []const u8 {
    return switch (kind) {
        KIND.ERROR => "ERROR",
        KIND.WARN => "WARNING",
        KIND.HINT => "HINT",
    };
}

pub const NoticeManager = struct {
    error_list: ListUm(Notice),
    warn_list: ListUm(Notice),
    hint_list: ListUm(Notice),

    pub fn add_notice(self: *NoticeManager, comptime kind: KIND, loc: SourceRange, comptime fmt: []const u8, args: anytype) void {
        switch (kind) {
            KIND.ERROR => self.add_error(loc, fmt, args),
            KIND.WARN => self.add_warn(loc, fmt, args),
            KIND.HINT => self.add_hint(loc, fmt, args),
        }
        return;
    }

    pub fn add_error(self: *NoticeManager, loc: SourceRange, comptime fmt: []const u8, args: anytype) void {
        const msg: []const u8 = std.fmt.allocPrint(NoticeAlloc.allocator(), fmt, args) catch "ERROR (could not alloc space for error message)";
        self.error_list.append(NoticeAlloc.allocator(), Notice{
            .location = loc,
            .message = msg,
        }) catch @panic("COULD NOT APPEND TO ERROR LIST");
        return;
    }

    pub fn add_warn(self: *NoticeManager, loc: SourceRange, comptime fmt: []const u8, args: anytype) void {
        const msg: []const u8 = std.fmt.allocPrint(NoticeAlloc.allocator(), fmt, args) catch "WARNING (could not alloc space for warning message)";
        self.error_list.append(NoticeAlloc.allocator(), Notice{
            .location = loc,
            .message = msg,
        }) catch @panic("COULD NOT APPEND TO WARN LIST");
        return;
    }

    pub fn add_hint(self: *NoticeManager, loc: SourceRange, comptime fmt: []const u8, args: anytype) void {
        const msg: []const u8 = std.fmt.allocPrint(NoticeAlloc.allocator(), fmt, args) catch "HINT (could not alloc space for hint message)";
        self.error_list.append(NoticeAlloc.allocator(), Notice{
            .location = loc,
            .message = msg,
        }) catch @panic("COULD NOT APPEND TO HINT LIST");
        return;
    }
};

pub var Notices = NoticeManager{
    .error_list = ListUm(Notice){},
    .warn_list = ListUm(Notice){},
    .hint_list = ListUm(Notice){},
};
