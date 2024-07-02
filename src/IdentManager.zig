const std = @import("std");
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");
const IdentBlock = @import("./IdentBlock.zig");

const Self = @This();

ident_buffer: Global.U8BufMedium.List,
ident_name_locs: Global.BufLocBufMedium.List,
ident_blocks: IdentBlock.IdentBlockBufMed.List,

pub fn new() Self {
    return Self{
        .ident_buffer = Global.U8BufMedium.List.create(),
        .ident_name_locs = Global.BufLocBufMedium.List.create(),
        .ident_blocks = IdentBlock.IdentBlockBufMed.List.create(),
    };
}

pub fn cleanup(self: *Self) void {
    self.ident_buffer.release();
    self.ident_blocks.release();
    self.ident_name_locs.release();
    return;
}

pub fn get_or_create_ident_key(self: *Self, ident_block: IdentBlock, ident_name: []const u8) u64 {
    for (self.ident_blocks.slice(), 0..) |known_block, idx| {
        if (IdentBlock.eql(ident_block, known_block)) return idx;
    }
    const idx: u64 = self.ident_name_locs.len;
    const ident_start = self.ident_buffer.len;
    self.ident_buffer.append_slice(ident_name);
    const ident_end = self.ident_buffer.len;
    self.ident_name_locs.append(Global.BufLoc.new_usize(ident_start, ident_end));
    self.ident_blocks.append(ident_block);
    return idx;
}
