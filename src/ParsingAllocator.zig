const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

alloc: Allocator,

pub fn new() Self {
    return Self{
        .alloc = std.heap.page_allocator,
    };
}

pub fn cleanup(self: *Self) void {
    _ = self;
    return;
}

pub var global: Self = undefined;
