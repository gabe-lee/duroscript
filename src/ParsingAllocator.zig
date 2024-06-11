const std = @import("std");
const GpaBuilder = std.heap.GeneralPurposeAllocator;
const GpaConfig = std.heap.GeneralPurposeAllocatorConfig;
const Allocator = std.mem.Allocator;

const Self = @This();
const CONFIG = GpaConfig{};
const GpaType = GpaBuilder(CONFIG);

gpa: GpaType,
alloc: Allocator,

pub fn new() Self {
    var self = Self{
        .gpa = GpaType{},
        .alloc = undefined,
    };
    self.alloc = self.gpa.allocator();
    return self;
}

pub var global: Self = undefined;
