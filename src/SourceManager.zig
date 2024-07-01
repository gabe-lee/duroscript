const std = @import("std");
const assert = std.debug.assert;
const APPEND_PANIC_MSG = @import("./Constants.zig").APPEND_PANIC_MSG;
const Allocator = std.mem.Allocator;
const SourceLexer = @import("./SourceLexer.zig");
const IdentBlock = @import("./IdentBlock.zig");
const Token = @import("./Token.zig");
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");
const BufLoc = Global.BufLoc;

const PathLocBuf = StaticAllocBuffer.define(BufLoc, &Global.g.medium_block_alloc);
const SourceStageBuf = StaticAllocBuffer.define(SourceStage, &Global.g.medium_block_alloc);
const TokenBuf = StaticAllocBuffer.define(Token, &Global.g.small_block_alloc);

const Self = @This();

//CHECKPOINT Fix this and any other *Manager classes for new BlockAllocator + StaticAllocBuffer API

path_pool: Global.U8BufMedium.List,
path_list: PathLocBuf.List,
stage_list: SourceStageBuf.List,

// pub fn get_source_key(self: *Self, complete_path: []const u8) u16 {
//     assert(complete_path.len > 0);
//     check_existing: for (self.path_list.items, 0..) |src, idx| {
//         if (src.len != complete_path.len) continue :check_existing;
//         var i = src.len - 1;
//         while (true) {
//             if (src[i] != complete_path[i]) continue :check_existing;
//             if (i == 0) return idx;
//             i -= 1;
//         }
//     }
//     assert(self.path_list.items.len <= std.math.maxInt(u16));
//     const new_idx: u16 = @truncate(self.path_list.items.len);
//     self.path_list.append(self.alloc, complete_path) catch @panic(APPEND_PANIC_MSG);
//     return new_idx;
// }

pub const STATE = enum(u8) {
    UNOPENED = 0,
    LOADED = 1,
    LEXED = 2,
    PARSED = 3,
    BYTECODE = 4,
};

pub const SourceStage = union(STATE) {
    UNOPENED: struct {
        file_path_loc: BufLoc,
        file_reader: Global.U8BufLarge.List,
    },
    LOADED: struct {
        source: Global.U8BufLarge.Slice,
        source_lexer: SourceLexer,
    },
    LEXED: struct {
        token_list: TokenBuf.Slice,
        //TODO AST
    },
    PARSED: void, // TODO
    BYTECODE: void, // TODO

    pub fn new(file_path_loc: BufLoc) SourceStage {
        return SourceStage{ .UNOPENED = .{
            .file_path_loc = file_path_loc,
            .file_reader = Global.U8BufLarge.List.create(),
        } };
    }

    pub fn cleanup(self: SourceStage) void {
        switch (self) {
            .UNOPENED => |stage| {
                stage.file_reader.release();
            },
            .LOADED => |stage| {
                stage.source.release();
                stage.source_lexer.token_list.release();
            },
            .LEXED => |stage| {
                stage.token_list.release();
                // release ast builder
            },
            .PARSED => |_| {
                // release ast
                // release bytecode builder
            },
            .BYTECODE => |_| {
                // release bytecode buffer
            },
        }
    }

    pub fn advance_to_loaded(self: *SourceStage) void {
        if (@intFromEnum(self) >= @intFromEnum(STATE.LOADED)) return;
        // Do load process
    }

    pub fn advance_to_lexed(self: *SourceStage) void {
        if (@intFromEnum(self) >= @intFromEnum(STATE.LEXED)) return;
        self.advance_to_loaded();
        // Do lexing process
    }

    pub fn advance_to_parsed(self: *SourceStage) void {
        if (@intFromEnum(self) >= @intFromEnum(STATE.PARSED)) return;
        self.advance_to_loaded();
        self.advance_to_lexed();
        // Do ast parsing process
    }

    pub fn advance_to_bytecode(self: *SourceStage) void {
        if (@intFromEnum(self) >= @intFromEnum(STATE.BYTECODE)) return;
        self.advance_to_loaded();
        self.advance_to_lexed();
        self.advance_to_parsed();
        // Do bytcode generation process
    }
};
