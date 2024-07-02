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
const OpenFlags = std.fs.File.OpenFlags;
const OpenMode = std.fs.File.OpenMode;

const SourceStageBuf = StaticAllocBuffer.define(SourceStage, &Global.g.medium_block_alloc);

const Self = @This();

path_pool: Global.U8BufMedium.List,
path_list: Global.BufLocBufMedium.List,
stage_list: SourceStageBuf.List,

pub fn new() Self {
    return Self{
        .path_pool = Global.U8BufMedium.List.create(),
        .path_list = Global.BufLocBufMedium.List.create(),
        .stage_list = SourceStageBuf.List.create(),
    };
}

pub fn cleanup(self: *Self) void {
    self.path_pool.release();
    self.path_list.release();
    for (self.stage_list.slice()) |source_stage| {
        source_stage.cleanup();
    }
    self.stage_list.release();
}

pub fn get_or_create_source_key(self: *Self, complete_path: []const u8) u16 {
    assert(complete_path.len > 0);
    for (self.path_list.slice(), 0..) |path_loc, idx| {
        const path = self.path_pool.ptr[path_loc.start..path_loc.end];
        if (path.len != complete_path.len) continue;
        var i = path.len - 1;
        while (true) {
            if (path[i] != complete_path[i]) continue;
            if (i == 0) return idx;
            i -= 1;
        }
    }
    assert(self.path_list.len <= std.math.maxInt(u16));
    const new_idx: u16 = @as(u16, self.path_list.len);
    const new_path_loc = BufLoc.new(self.path_pool.len, self.path_pool.len + complete_path.len);
    const new_stage = SourceStage.new(new_path_loc);
    self.path_pool.append_slice(complete_path);
    self.path_list.append(new_path_loc);
    self.stage_list.append(new_stage);
    return new_idx;
}

pub fn advance_source_to_loaded(self: *Self, key: u16) void {
    assert(key < self.stage_list.len);
    const source = self.stage_list.ptr[key];
    if (@intFromEnum(source) >= @intFromEnum(STATE.LOADED)) return;
    const data = source.UNOPENED;
    const file = std.fs.openFileAbsolute(self.path_pool[data.file_path_loc.start..data.file_path_loc.end], OpenFlags{ .mode = OpenMode.read_only }) catch @panic("FAILED TO LOAD FILE");
    defer file.close();
    const file_stat: ?std.fs.File.Stat = file.stat() catch null;
    if (file_stat) |stat| {
        const file_size = stat.size;
        _ = data.file_buffer.ensure_unused_cap(@as(usize, file_size));
        const real_len = file.readAll(data.file_buffer.slice()) catch @panic("FAILED TO READ FILE CONTENTS");
        assert(real_len <= data.file_buffer.cap);
        data.file_buffer.len = real_len;
    } else {
        const block_size = Global.U8BufLarge.alloc.block_size();
        var cont = true;
        while (cont) {
            _ = data.file_buffer.ensure_unused_cap(block_size);
            const read_len = file.read(data.file_buffer.ptr[data.file_buffer.len..data.file_buffer.cap]) catch @panic("FAILED TO READ FILE CONTENTS");
            data.file_buffer.len += read_len;
            cont = read_len != 0;
        }
    }
    const file_slice = data.file_buffer.downgrade_into_slice_partial();
    self.stage_list.ptr[key] = SourceStage{
        .LOADED = .{
            .source = file_slice,
            .source_lexer = SourceLexer.new(file_slice.slice(), key),
        },
    };
    return;
}

pub fn advance_source_to_lexed(self: *Self, key: u16) void {
    assert(key < self.stage_list.len);
    if (@intFromEnum(self.stage_list.ptr[key]) >= @intFromEnum(STATE.LEXED)) return;
    self.advance_source_to_loaded(key);
    const data = self.stage_list.ptr[key].LOADED;
    data.source_lexer.parse_source();
    self.stage_list.ptr[key] = SourceStage{
        .LEXED = .{
            .token_list = data.source_lexer.token_list.downgrade_into_slice_partial(),
            // create ast list
        },
    };
    data.source.release();
    return;
}

pub fn advance_source_to_parsed(self: *Self, key: u16) void {
    assert(key < self.stage_list.len);
    if (@intFromEnum(self.stage_list.ptr[key]) >= @intFromEnum(STATE.PARSED)) return;
    self.advance_source_to_loaded(key);
    self.advance_source_to_lexed(key);
    _ = self.stage_list.ptr[key].LEXED;
    // Do ast parsing process
}

pub fn advance_source_to_bytecode(self: *Self, key: u16) void {
    assert(key < self.stage_list.len);
    if (@intFromEnum(self.stage_list.ptr[key]) >= @intFromEnum(STATE.BYTECODE)) return;
    self.advance_source_to_loaded(key);
    self.advance_source_to_lexed(key);
    self.advance_source_to_parsed(key);
    _ = self.stage_list.ptr[key].PARSED;
    // Do bytcode generation process
}

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
        file_buffer: Global.U8BufLarge.List,
    },
    LOADED: struct {
        source: Global.U8BufLarge.Slice,
        source_lexer: SourceLexer,
    },
    LEXED: struct {
        token_list: Token.TokenBuf.Slice,
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
                stage.file_buffer.release();
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
};
