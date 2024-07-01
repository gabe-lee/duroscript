const std = @import("std");
const assert = std.debug.assert;
const APPEND_PANIC_MSG = @import("./Constants.zig").APPEND_PANIC_MSG;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArenaState = ArenaAllocator.State;
const ArenaResetMode = ArenaAllocator.ResetMode;
const SourceLexer = @import("./SourceLexer.zig");
const List = std.ArrayListUnmanaged;
const IdentBlock = @import("./IdentBlock.zig");
const Token = @import("./Token.zig");

const Self = @This();

pub var global: Self = undefined;

alloc: Allocator,
path_list: List([]const u8),
data_list: List(SourceData),

pub const STATE = enum(u8) {
    UNOPENED,
    LOADED,
    LEXED,
    PARSED,
    BYTECODE,
};

pub const SourceDataStaticUnion = union(STATE) {
    UNOPENED: void,
    LOADED: []const u8,
    LEXED: []const Token,
    PARSED: void, // TODO
    BYTECODE: void, // TODO
};

pub const SourceDataWorkingUnion = union(STATE) {
    UNOPENED: void,
    LOADED: List(u8),
    LEXED: SourceLexer,
    PARSED: void, // TODO
    CRUNCHED: void, // TODO

    pub fn make_static(self: SourceDataWorkingUnion) SourceDataStaticUnion {
        return switch (self) {
            .UNOPENED => SourceDataStaticUnion{ .UNOPENED = void{} },
            .LOADED => |list| SourceDataStaticUnion{ .LOADED = list.items },
            .LEXED => |lexer| SourceDataStaticUnion{ .LEXED = lexer.token_list.items },
            .PARSED => SourceDataStaticUnion{ .PARSED = void{} }, // TODO
            .BYTECODE => SourceDataStaticUnion{ .BYTECODE = void{} }, // TODO
        };
    }
};

//CHECKPOINT Fix this and any other *Manager classes for new BlockAllocator + StaticAllocBuffer API
pub const SourceData = struct {
    arenas: [2]ArenaState = [2]ArenaState{ ArenaState{}, ArenaState{} },
    arena_static: usize = 0,
    arena_working: usize = 1,
    data_static: SourceDataStaticUnion = SourceDataStaticUnion{ .UNOPENED = void{} },
    data_working: SourceDataWorkingUnion = SourceDataWorkingUnion{ .UNOPENED = void{} },

    pub fn cleanup(self: *SourceData) void {
        self.arenas[0].promote(global.alloc).reset(ArenaResetMode.free_all);
        self.arenas[1].promote(global.alloc).reset(ArenaResetMode.free_all);
        self.data_static = SourceDataStaticUnion{ .UNOPENED = void{} };
    }

    pub fn reset_working_allocation(self: *SourceData) void {
        self.arenas[self.arena_working].promote(global.alloc).reset(ArenaResetMode.retain_capacity);
    }

    pub inline fn swap_arenas(self: *SourceData) void {
        self.arena_static = self.arena_working ^ self.arena_static;
        self.arena_working = self.arena_static ^ self.arena_working;
        self.arena_static = self.arena_working ^ self.arena_static;
    }
};

pub fn new(alloc: Allocator) Self {
    return Self{
        .alloc = alloc,
        .path_list = List([]const u8){},
    };
}

pub fn cleanup(self: *Self) void {
    self.path_list.deinit(self.alloc);
    return;
}

pub fn get_source_key(self: *Self, complete_path: []const u8) u16 {
    assert(complete_path.len > 0);
    check_existing: for (self.path_list.items, 0..) |src, idx| {
        if (src.len != complete_path.len) continue :check_existing;
        var i = src.len - 1;
        while (true) {
            if (src[i] != complete_path[i]) continue :check_existing;
            if (i == 0) return idx;
            i -= 1;
        }
    }
    assert(self.path_list.items.len <= std.math.maxInt(u16));
    const new_idx: u16 = @truncate(self.path_list.items.len);
    self.path_list.append(self.alloc, complete_path) catch @panic(APPEND_PANIC_MSG);
    return new_idx;
}

//CHECKPOINT
// pub fn load_file(self: *Self, source_key: u16) []const u8 {}
