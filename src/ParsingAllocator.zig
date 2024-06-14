const std = @import("std");
const GpaBuilder = std.heap.GeneralPurposeAllocator;
const GpaConfig = std.heap.GeneralPurposeAllocatorConfig;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const Self = @This();
const CONFIG = GpaConfig{};
const GpaType = GpaBuilder(CONFIG);

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
