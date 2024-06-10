const std = @import("std");

var ErrAlloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub fn ErrorOr(comptime T: type) type {
    return union(enum) {
        ERR: []const u8,
        OK: T,

        const Self = @This();
        pub fn new_err(comptime fmt: []const u8, args: anytype) Self {
            const msg: []const u8 = std.fmt.allocPrint(ErrAlloc.allocator(), fmt, args) catch "ERROR (could not alloc space for error message)";
            return Self{ .ERR = msg };
        }

        pub fn pass_err(msg: []const u8) Self {
            return Self{ .ERR = msg };
        }
    };
}
