const std = @import("std");
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");
const IdentBlock = @import("./IdentBlock.zig");

const Self = @This();
const IdentNameBuf = StaticAllocBuffer.define([]const u8, &Global.g.small_block_alloc);
const IdentBlockBuf = StaticAllocBuffer.define(IdentBlock, &Global.g.medium_block_alloc);

ident_names: IdentNameBuf.List,
ident_blocks: IdentBlockBuf.List,

pub fn new() Self {
    return Self{
        .ident_names = IdentNameBuf.List.create(),
        .ident_blocks = IdentBlockBuf.List.create(),
    };
}

pub fn cleanup(self: *Self) void {
    self.ident_blocks.release();
    self.ident_names.release();
    return;
}

pub fn get_ident_index(self: *Self, ident_block: IdentBlock, ident_name: []const u8) u64 {
    for (self.ident_blocks.slice(), 0..) |known_block, idx| {
        if (IdentBlock.eql(ident_block, known_block)) return idx;
    }
    const idx: u64 = self.ident_names.len;
    self.ident_names.append(ident_name);
    self.ident_blocks.append(ident_block);
    return idx;
}
