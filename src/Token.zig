// const A = @import("./Ascii.zig");
const IdentBlock = @import("./IdentBlock.zig");
const std = @import("std");
const builtin = @import("builtin");
const ProgramROM = @import("./ProgramROM.zig");
const NOTICE = @import("./NoticeManager.zig").SEVERITY;
const SourceReader = @import("./SourceReader.zig");
const IdentManager = @import("./IdentManager.zig");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");

pub const TokenBuf = StaticAllocBuffer.define(Self, &Global.medium_block_alloc);

const Self = @This();

kind: TOK,
source_key: u16,
row_start: u32,
row_end: u32,
col_start: u32,
col_end: u32,
data_val_or_ptr: u64,
data_len: u32,
data_extra: u8,
byte_start: if (builtin.mode == .Debug) usize else void,
byte_end: if (builtin.mode == .Debug) usize else void,

pub const TOK = enum(u8) {
    // Meta
    EOF, // TL
    COMMENT, // TL
    STDLIB, // TL
    // Definition
    IMPORT, // TL
    CONST, // TL
    VAR, // TL
    IDENT, // TL
    IGNORE, // TL
    AS, // TL
    // Types
    NONE, // TL
    TYPE, // TL
    U8, // TL
    I8, // TL
    U16, // TL
    I16, // TL
    U32, // TL
    I32, // TL
    U64, // TL
    I64, // TL
    F32, // TL
    F64, // TL
    BOOL, // TL
    STRING, // TL
    TEMPLATE, // TL
    STRUCT, // TL
    SLICE, // TL
    MAP, // TL
    ARRAY, // TL
    PACKED, // TL
    LIST, // TL
    ENUM, // TL
    FLAGS, // TL
    UNION, // TL
    TUPLE, // TL
    FUNC, // TL
    REFERENCE, // TL
    MAYBE_NONE, // TL
    // Literals
    LIT_STRING,
    LIT_INTEGER, // TL
    LIT_FLOAT, // TL
    LIT_BOOL, // TL
    LIT_STR_TEMPLATE, // TL
    // Operators
    ACCESS_MAYBE_NONE, // TL
    SUBSTITUTE, // TL
    DEREREFENCE, // TL
    ASSIGN, // TL
    EQUALS, // TL
    LESS_THAN, // TL
    MORE_THAN, // TL
    LESS_THAN_EQUAL, // TL
    MORE_THAN_EQUAL, // TL
    NOT_EQUAL, // TL
    ADD, // TL
    SUB, // TL
    MULT, // TL
    DIV, // TL
    MODULO, // TL
    POWER, // TL
    ROOT, // TL
    ADD_ASSIGN, // TL
    SUB_ASSIGN, // TL
    MULT_ASSIGN, // TL
    DIV_ASSIGN, // TL
    MODULO_ASSIGN, // TL
    POWER_ASSIGN, // TL
    ROOT_ASSIGN, // TL
    SHIFT_L, // TL
    SHIFT_R, // TL
    SHIFT_L_ASSIGN, // TL
    SHIFT_R_ASSIGN, // TL
    BIT_AND, // TL
    BIT_OR, // TL
    BIT_NOT, // TL
    BIT_XOR, // TL
    BIT_AND_ASSIGN, // TL
    BIT_OR_ASSIGN, // TL
    BIT_XOR_ASSIGN, // TL
    LOGIC_AND, // TL
    LOGIC_OR, // TL
    LOGIC_NOT, // TL
    LOGIC_XOR, // TL
    LOGIC_AND_ASSIGN, // TL
    LOGIC_OR_ASSIGN, // TL
    LOGIC_XOR_ASSIGN, // TL
    // Range operators
    RANGE_INCLUDE_BOTH, // TL
    RANGE_EXCLUDE_END, // TL
    RANGE_EXCLUDE_BEGIN, // TL
    RANGE_EXCLUDE_BOTH, // TL
    // Delimiters
    COMMA, // TL
    COLON, // TL
    SEMICOL, // TL
    L_PAREN, // TL
    R_PAREN, // TL
    L_CURLY, // TL
    R_CURLY, // TL
    L_SQUARE, // TL
    R_SQUARE, // TL
    ACCESS, // TL
    FAT_ARROW, // TL
    // Control Flow
    MATCH, // TL
    IF, // TL
    ELSE, // TL
    WHILE, // TL
    FOR_EACH, // TL
    IN, // TL
    BREAK, // TL
    NEXT_LOOP, // TL
    RETURN, // TL
    // Illegal
    ILLEGAL, // TL
};

pub const LONGEST_KEYWORD = 8;
const KW_TUPLE_1 = struct { id: *const [1:0]u8, k: TOK, v: u64 };
const KW_TUPLE_2 = struct { id: *const [2:0]u8, k: TOK, v: u64 };
const KW_TUPLE_3 = struct { id: *const [3:0]u8, k: TOK, v: u64 };
const KW_TUPLE_4 = struct { id: *const [4:0]u8, k: TOK, v: u64 };
const KW_TUPLE_5 = struct { id: *const [5:0]u8, k: TOK, v: u64 };
const KW_TUPLE_6 = struct { id: *const [6:0]u8, k: TOK, v: u64 };
const KW_TUPLE_7 = struct { id: *const [7:0]u8, k: TOK, v: u64 };
const KW_TUPLE_8 = struct { id: *const [8:0]u8, k: TOK, v: u64 };

pub const KW_TABLE_1 = [_]KW_TUPLE_1{
    .{ .id = "_", .k = TOK.IGNORE, .v = 0 },
};
pub const KW_TABLE_2 = [_]KW_TUPLE_2{
    .{ .id = "as", .k = TOK.AS, .v = 0 },
    .{ .id = "in", .k = TOK.IN, .v = 0 },
    .{ .id = "u8", .k = TOK.U8, .v = 0 },
    .{ .id = "i8", .k = TOK.I8, .v = 0 },
    .{ .id = "if", .k = TOK.IF, .v = 0 },
};
pub const KW_TABLE_3 = [_]KW_TUPLE_3{
    .{ .id = "var", .k = TOK.VAR, .v = 0 },
    .{ .id = "u16", .k = TOK.U16, .v = 0 },
    .{ .id = "i16", .k = TOK.I16, .v = 0 },
    .{ .id = "u32", .k = TOK.U32, .v = 0 },
    .{ .id = "i32", .k = TOK.I32, .v = 0 },
    .{ .id = "u64", .k = TOK.U64, .v = 0 },
    .{ .id = "i64", .k = TOK.I64, .v = 0 },
    .{ .id = "f32", .k = TOK.F32, .v = 0 },
    .{ .id = "f64", .k = TOK.F64, .v = 0 },
    .{ .id = "map", .k = TOK.MAP, .v = 0 },
};
pub const KW_TABLE_4 = [_]KW_TUPLE_4{
    .{ .id = "func", .k = TOK.FUNC, .v = 0 },
    .{ .id = "bool", .k = TOK.BOOL, .v = 0 },
    .{ .id = "type", .k = TOK.TYPE, .v = 0 },
    .{ .id = "true", .k = TOK.LIT_BOOL, .v = 1 },
    .{ .id = "none", .k = TOK.NONE, .v = 0 },
    .{ .id = "enum", .k = TOK.ENUM, .v = 0 },
    .{ .id = "else", .k = TOK.ELSE, .v = 0 },
};
pub const KW_TABLE_5 = [_]KW_TUPLE_5{
    .{ .id = "const", .k = TOK.CONST, .v = 0 },
    .{ .id = "while", .k = TOK.WHILE, .v = 0 },
    .{ .id = "break", .k = TOK.BREAK, .v = 0 },
    .{ .id = "false", .k = TOK.LIT_BOOL, .v = 0 },
    .{ .id = "union", .k = TOK.UNION, .v = 0 },
    .{ .id = "tuple", .k = TOK.TUPLE, .v = 0 },
    .{ .id = "match", .k = TOK.MATCH, .v = 0 },
    .{ .id = "flags", .k = TOK.FLAGS, .v = 0 },
    .{ .id = "slice", .k = TOK.SLICE, .v = 0 },
    .{ .id = "array", .k = TOK.ARRAY, .v = 0 },
};
pub const KW_TABLE_6 = [_]KW_TUPLE_6{
    .{ .id = "import", .k = TOK.IMPORT, .v = 0 },
    .{ .id = "return", .k = TOK.RETURN, .v = 0 },
    .{ .id = "struct", .k = TOK.STRUCT, .v = 0 },
    .{ .id = "string", .k = TOK.STRING, .v = 0 },
};
pub const KW_TABLE_7 = [_]KW_TUPLE_7{
    .{ .id = "foreach", .k = TOK.FOR_EACH, .v = 0 },
};
pub const KW_TABLE_8 = [_]KW_TUPLE_8{
    .{ .id = "nextloop", .k = TOK.NEXT_LOOP, .v = 0 },
    .{ .id = "template", .k = TOK.TEMPLATE, .v = 0 },
};

pub const TOTAL_KW_COUNT = KW_TABLE_1.len + KW_TABLE_2.len + KW_TABLE_3.len + KW_TABLE_4.len + KW_TABLE_5.len + KW_TABLE_6.len + KW_TABLE_7.len + KW_TABLE_8.len;
pub const KW_SLICE_1_START = 0;
pub const KW_SLICE_2_START = KW_SLICE_1_START + KW_TABLE_1.len;
pub const KW_SLICE_3_START = KW_SLICE_2_START + KW_TABLE_2.len;
pub const KW_SLICE_4_START = KW_SLICE_3_START + KW_TABLE_3.len;
pub const KW_SLICE_5_START = KW_SLICE_4_START + KW_TABLE_4.len;
pub const KW_SLICE_6_START = KW_SLICE_5_START + KW_TABLE_5.len;
pub const KW_SLICE_7_START = KW_SLICE_6_START + KW_TABLE_6.len;
pub const KW_SLICE_8_START = KW_SLICE_7_START + KW_TABLE_7.len;
pub const KW_SLICE_8_END = KW_SLICE_8_START + KW_TABLE_8.len;

pub const KW_U64_TABLE: [TOTAL_KW_COUNT]u64 = eval: {
    var out: [TOTAL_KW_COUNT]u64 = undefined;
    var i = 0;
    for (KW_TABLE_1) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56);
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    for (KW_TABLE_2) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48);
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    for (KW_TABLE_3) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40);
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    for (KW_TABLE_4) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32);
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    for (KW_TABLE_5) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24);
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    for (KW_TABLE_6) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16);
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    for (KW_TABLE_7) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16) | (str[6] << 8);
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    for (KW_TABLE_8) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16) | (str[6] << 8) | str[7];
        out[i] = IdentBlock.compile_keyword(kw.id, false).data[0];
        i += 1;
    }
    break :eval out;
};

pub const KW_TOKEN_TABLE: [TOTAL_KW_COUNT]TOK = eval: {
    var out: [TOTAL_KW_COUNT]TOK = undefined;
    var i = 0;
    for (KW_TABLE_1) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    for (KW_TABLE_2) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    for (KW_TABLE_3) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    for (KW_TABLE_4) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    for (KW_TABLE_5) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    for (KW_TABLE_6) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    for (KW_TABLE_7) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    for (KW_TABLE_8) |kw| {
        out[i] = kw.k;
        i += 1;
    }
    break :eval out;
};

pub const KW_IMPLICIT_TABLE: [TOTAL_KW_COUNT]u64 = eval: {
    var out: [TOTAL_KW_COUNT]u64 = undefined;
    var i = 0;
    for (KW_TABLE_1) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    for (KW_TABLE_2) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    for (KW_TABLE_3) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    for (KW_TABLE_4) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    for (KW_TABLE_5) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    for (KW_TABLE_6) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    for (KW_TABLE_7) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    for (KW_TABLE_8) |kw| {
        out[i] = kw.v;
        i += 1;
    }
    break :eval out;
};
pub const KW_U64_SLICES_BY_LEN = [9][]const u64{
    KW_U64_TABLE[0..0], // 0 char slice
    KW_U64_TABLE[KW_SLICE_1_START..KW_SLICE_2_START], // 1 char slice
    KW_U64_TABLE[KW_SLICE_2_START..KW_SLICE_3_START], // 2 char slice
    KW_U64_TABLE[KW_SLICE_3_START..KW_SLICE_4_START], // 3 char slice
    KW_U64_TABLE[KW_SLICE_4_START..KW_SLICE_5_START], // 4 char slice
    KW_U64_TABLE[KW_SLICE_5_START..KW_SLICE_6_START], // 5 char slice
    KW_U64_TABLE[KW_SLICE_6_START..KW_SLICE_7_START], // 6 char slice
    KW_U64_TABLE[KW_SLICE_7_START..KW_SLICE_8_START], // 7 char slice
    KW_U64_TABLE[KW_SLICE_8_START..KW_SLICE_8_END], // 8 char slice
};
pub const KW_TOKEN_SLICES_BY_LEN = [9][]const TOK{
    KW_TOKEN_TABLE[0..0], // 0 char slice
    KW_TOKEN_TABLE[KW_SLICE_1_START..KW_SLICE_2_START], // 1 char slice
    KW_TOKEN_TABLE[KW_SLICE_2_START..KW_SLICE_3_START], // 2 char slice
    KW_TOKEN_TABLE[KW_SLICE_3_START..KW_SLICE_4_START], // 3 char slice
    KW_TOKEN_TABLE[KW_SLICE_4_START..KW_SLICE_5_START], // 4 char slice
    KW_TOKEN_TABLE[KW_SLICE_5_START..KW_SLICE_6_START], // 5 char slice
    KW_TOKEN_TABLE[KW_SLICE_6_START..KW_SLICE_7_START], // 6 char slice
    KW_TOKEN_TABLE[KW_SLICE_7_START..KW_SLICE_8_START], // 7 char slice
    KW_TOKEN_TABLE[KW_SLICE_8_START..KW_SLICE_8_END], // 8 char slice
};
pub const KW_IMPLICIT_SLICES_BY_LEN = [9][]const u64{
    KW_IMPLICIT_TABLE[0..0], // 0 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_1_START..KW_SLICE_2_START], // 1 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_2_START..KW_SLICE_3_START], // 2 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_3_START..KW_SLICE_4_START], // 3 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_4_START..KW_SLICE_5_START], // 4 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_5_START..KW_SLICE_6_START], // 5 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_6_START..KW_SLICE_7_START], // 6 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_7_START..KW_SLICE_8_START], // 7 char slice
    KW_IMPLICIT_TABLE[KW_SLICE_8_START..KW_SLICE_8_END], // 8 char slice
};

// pub const KIND_NAME: [@typeInfo(TOK).Enum.fields.len][]const u8 = compute: {
//     var table: [@typeInfo(TOK).Enum.fields.len][]const u8 = undefined;
//     for (@typeInfo(TOK).Enum.fields, 0..) |f, i| {
//         table[i] = f.name;
//     }
//     break :compute table;
// };

pub fn create_token_output_file(working_dir: *const std.fs.Dir, path: []const u8, tokens: *TokenBuf.Slice) !std.fs.File {
    const out_file = try working_dir.createFile(path, std.fs.File.CreateFlags{
        .read = true,
        .exclusive = false,
        .truncate = true,
    });
    var row: u32 = 0;
    var string_builder = Global.U8BufSmall.List.create();
    defer string_builder.release();
    for (tokens.slice()) |token| {
        const name = @tagName(token.kind);
        while (token.row_start > row) {
            row += 1;
            _ = try out_file.write("\n");
        }
        switch (token.kind) {
            TOK.LIT_INTEGER,
            => {
                if (token.data_extra == 1) { // negative
                    _ = try out_file.write(string_builder.quick_fmt_string("{s}({d}) ", .{ name, -@as(i64, @bitCast(token.data_val_or_ptr)) }));
                } else {
                    _ = try out_file.write(string_builder.quick_fmt_string("{s}({d}) ", .{ name, token.data_val_or_ptr }));
                }
            },
            TOK.LIT_FLOAT => {
                _ = try out_file.write(string_builder.quick_fmt_string("{s}({d}) ", .{ name, @as(f64, @bitCast(token.data_val_or_ptr)) }));
            },
            TOK.LIT_BOOL => {
                _ = try out_file.write(string_builder.quick_fmt_string("{s}({any}) ", .{ name, @as(bool, @bitCast(@as(u1, @truncate(token.data_val_or_ptr)))) }));
            },
            TOK.LIT_STRING, TOK.LIT_STR_TEMPLATE => {
                _ = try out_file.write(string_builder.quick_fmt_string("{s}({s}) ", .{ name, Global.token_rom.data.ptr[token.data_val_or_ptr .. token.data_val_or_ptr + token.data_len] }));
            },
            TOK.IDENT => {
                const ident_loc = Global.ident_manager.ident_name_locs.ptr[token.data_val_or_ptr];
                _ = try out_file.write(string_builder.quick_fmt_string("{s}({s}) ", .{ name, Global.ident_manager.ident_buffer.ptr[ident_loc.start..ident_loc.end] }));
            },
            else => {
                _ = try out_file.write(string_builder.quick_fmt_string("{s} ", .{name}));
            },
        }
    }
    try out_file.seekTo(0);
    return out_file;
}
