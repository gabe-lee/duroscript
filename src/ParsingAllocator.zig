const std = @import("std");
const GpaBuilder = std.heap.GeneralPurposeAllocator;
const GpaConfig = std.heap.GeneralPurposeAllocatorConfig;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const Self = @This();
const CONFIG = GpaConfig{};
const GpaType = GpaBuilder(CONFIG);

gpa: GpaType,
arena: Arena,
alloc: Allocator,

pub fn new() Self {
    var self = Self{
        .gpa = GpaType{},
        .arena = undefined,
        .alloc = undefined,
    };
    self.alloc = self.gpa.allocator();
    return self;
}

pub fn new_arena() Self {
    var self = Self{
        .gpa = undefined,
        .arena = Arena.init(std.heap.page_allocator),
        .alloc = undefined,
    };
    self.alloc = self.arena.allocator();
    return self;
}

pub fn new_page() Self {
    return Self{
        .gpa = undefined,
        .arena = undefined,
        .alloc = std.heap.page_allocator,
    };
}

pub var global: Self = undefined;
