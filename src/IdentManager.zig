const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const IdentBlock = @import("./IdentBlock.zig");

const Self = @This();

alloc: Allocator,
ident_names: List([]const u8),
ident_blocks: List(IdentBlock),

pub fn new(alloc: Allocator) Self {
    return Self{
        .alloc = alloc,
        .ident_names = List([]const u8){},
        .ident_blocks = List(IdentBlock){},
    };
}

pub fn cleanup(self: *Self) void {
    self.ident_blocks.deinit(self.alloc);
    self.ident_names.deinit(self.alloc);
    return;
}

pub fn get_ident_index(self: *Self, ident_block: IdentBlock, ident_name: []const u8) u64 {
    for (self.ident_blocks.items, 0..) |known_block, idx| {
        if (IdentBlock.eql(ident_block, known_block)) return idx;
    }
    const idx: u64 = self.ident_names.items.len;
    self.ident_names.append(self.alloc, ident_name) catch @panic("FAILED TO ALLOCATE SPACE FOR NEW ENTRY IN IDENT NAMES LIST");
    self.ident_blocks.append(self.alloc, ident_block) catch @panic("FAILED TO ALLOCATE SPACE FOR NEW ENTRY IN IDENT BLOCKS LIST");
    return idx;
}
