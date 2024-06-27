// const A = @import("./Ascii.zig");
const IdentBlock = @import("./IdentBlock.zig");
const std = @import("std");
const ProgramROM = @import("./ProgramROM.zig");
const NOTICE = @import("./NoticeManager.zig").SEVERITY;
const SourceReader = @import("./SourceReader.zig");
const IdentManager = @import("./IdentManager.zig");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

const Self = @This();

kind: KIND,
source_key: u16,
row_start: u32,
row_end: u32,
col_start: u32,
col_end: u32,
data_val_or_ptr: u64,
data_len: u32,
data_extra: u8,

pub const KIND = enum(u8) {
    // Meta
    EOF, // TL
    COMMENT, // TL
    STDLIB, // TL
    // Definition
    IMPORT, // TL
    CONST, // TL
    VAR, // TL
    IDENT, // TL
    DEFAULT, // TL
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

// pub const WARN = enum(u8) {
//     NONE,
//     WARN_AMBIGUOUS_SATURATION,
//     WARN_AMBIGUOUS_ZERO,
//     WARN_UTF8_ILLEGAL_FIRST_BYTE,
//     WARN_UTF8_MISSING_CONTINUATION_BYTE,
//     WARN_UTF8_UNEXPECTED_CONTINUATION_BYTE,
//     WARN_UTF8_ILLEGAL_CHAR_CODE,
//     WARN_UTF8_SOURCE_ENDED_EARLY,
//     WARN_UTF8_OVERLONG_ENCODING,
//     ILLEGAL_OPERATOR,
//     ILLEGAL_BYTE,
//     ILLEGAL_FIRST_CHAR_FOR_TOKEN,
//     ILLEGAL_ALPHANUM_IN_BINARY,
//     ILLEGAL_ALPHANUM_IN_OCTAL,
//     ILLEGAL_ALPHANUM_IN_HEX,
//     ILLEGAL_ALPHANUM_IN_DECIMAL,
//     ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS,
//     ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS,
//     ILLEGAL_INTEGER_LITERAL_LOSS_OF_DATA,
//     ILLEGAL_INTEGER_LITERAL_NEG_OVERFLOWS_I64,
//     ILLEGAL_FLOAT_LITERAL_TOO_LARGE,
//     ILLEGAL_FLOAT_LITERAL_TOO_SMALL,
//     ILLEGAL_FLOAT_TOO_MANY_SIG_DIGITS,
//     ILLEGAL_NUMBER_TOO_MANY_DOTS,
//     ILLEGAL_IDENT_TOO_LONG,
//     ILLEGAL_IDENT_BEGINS_WITH_DIGIT,
//     ILLEGAL_NUMBER_TOO_MANY_EXPONENTS,
//     ILLEGAL_NUMBER_PERIOD_IN_EXPONENT,
//     ILLEGAL_NUMBER_EXPONENT_TOO_MANY_DIGITS,
//     ILLEGAL_STRING_NO_END_QUOTE,
//     ILLEGAL_STRING_ESCAPE_SEQUENCE,
//     ILLEGAL_STRING_MULTILINE_NON_WHITESPACE_BEFORE_BACKTICK,
//     ILLEGAL_STRING_FILE_ENDED_BEFORE_TERMINAL_CHAR,
//     ILLEGAL_STRING_OCTAL_ESCAPE,
//     ILLEGAL_STRING_HEX_ESCAPE,
//     ILLEGAL_STRING_SHORT_UNICODE_ESCAPE,
//     ILLEGAL_STRING_LONG_UNICODE_ESCAPE,
//     ILLEGAL_STRING_MULTILINE_NEVER_TERMINATES,
//     ILLEGAL_STRING_MULTI_R_CURLY_MUST_ESCAPE,
// };
// pub const SMALLEST_WARN: u8 = @intFromEnum(WARN.WARN_AMBIGUOUS_SATURATION);
// pub const SMALLEST_ILLEGAL: u8 = @intFromEnum(WARN.ILLEGAL_OPERATOR);

pub const LONGEST_KEYWORD = 8;
const KW_TUPLE_1 = struct { id: *const [1:0]u8, k: KIND, v: u64 };
const KW_TUPLE_2 = struct { id: *const [2:0]u8, k: KIND, v: u64 };
const KW_TUPLE_3 = struct { id: *const [3:0]u8, k: KIND, v: u64 };
const KW_TUPLE_4 = struct { id: *const [4:0]u8, k: KIND, v: u64 };
const KW_TUPLE_5 = struct { id: *const [5:0]u8, k: KIND, v: u64 };
const KW_TUPLE_6 = struct { id: *const [6:0]u8, k: KIND, v: u64 };
const KW_TUPLE_7 = struct { id: *const [7:0]u8, k: KIND, v: u64 };
const KW_TUPLE_8 = struct { id: *const [8:0]u8, k: KIND, v: u64 };

pub const KW_TABLE_1 = [_]KW_TUPLE_1{
    .{ .id = "_", .k = KIND.DEFAULT, .v = 0 },
};
pub const KW_TABLE_2 = [_]KW_TUPLE_2{
    .{ .id = "as", .k = KIND.AS, .v = 0 },
    .{ .id = "in", .k = KIND.IN, .v = 0 },
    .{ .id = "u8", .k = KIND.U8, .v = 0 },
    .{ .id = "i8", .k = KIND.I8, .v = 0 },
    .{ .id = "if", .k = KIND.IF, .v = 0 },
};
pub const KW_TABLE_3 = [_]KW_TUPLE_3{
    .{ .id = "var", .k = KIND.VAR, .v = 0 },
    .{ .id = "std", .k = KIND.STDLIB, .v = 0 },
    .{ .id = "u16", .k = KIND.U16, .v = 0 },
    .{ .id = "i16", .k = KIND.I16, .v = 0 },
    .{ .id = "u32", .k = KIND.U32, .v = 0 },
    .{ .id = "i32", .k = KIND.I32, .v = 0 },
    .{ .id = "u64", .k = KIND.U64, .v = 0 },
    .{ .id = "i64", .k = KIND.I64, .v = 0 },
    .{ .id = "f32", .k = KIND.F32, .v = 0 },
    .{ .id = "f64", .k = KIND.F64, .v = 0 },
};
pub const KW_TABLE_4 = [_]KW_TUPLE_4{
    .{ .id = "func", .k = KIND.FUNC, .v = 0 },
    .{ .id = "bool", .k = KIND.BOOL, .v = 0 },
    .{ .id = "type", .k = KIND.TYPE, .v = 0 },
    .{ .id = "true", .k = KIND.LIT_BOOL, .v = 1 },
    .{ .id = "none", .k = KIND.NONE, .v = 0 },
    .{ .id = "enum", .k = KIND.ENUM, .v = 0 },
    .{ .id = "else", .k = KIND.ELSE, .v = 0 },
};
pub const KW_TABLE_5 = [_]KW_TUPLE_5{
    .{ .id = "const", .k = KIND.CONST, .v = 0 },
    .{ .id = "while", .k = KIND.WHILE, .v = 0 },
    .{ .id = "break", .k = KIND.BREAK, .v = 0 },
    .{ .id = "false", .k = KIND.LIT_BOOL, .v = 0 },
    .{ .id = "union", .k = KIND.UNION, .v = 0 },
    .{ .id = "tuple", .k = KIND.TUPLE, .v = 0 },
    .{ .id = "match", .k = KIND.MATCH, .v = 0 },
    .{ .id = "flags", .k = KIND.FLAGS, .v = 0 },
};
pub const KW_TABLE_6 = [_]KW_TUPLE_6{
    .{ .id = "import", .k = KIND.IMPORT, .v = 0 },
    .{ .id = "return", .k = KIND.RETURN, .v = 0 },
    .{ .id = "struct", .k = KIND.STRUCT, .v = 0 },
    .{ .id = "string", .k = KIND.STRING, .v = 0 },
};
pub const KW_TABLE_7 = [_]KW_TUPLE_7{
    .{ .id = "foreach", .k = KIND.FOR_EACH, .v = 0 },
};
pub const KW_TABLE_8 = [_]KW_TUPLE_8{
    .{ .id = "nextloop", .k = KIND.NEXT_LOOP, .v = 0 },
    .{ .id = "template", .k = KIND.TEMPLATE, .v = 0 },
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
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    for (KW_TABLE_2) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48);
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    for (KW_TABLE_3) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40);
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    for (KW_TABLE_4) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32);
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    for (KW_TABLE_5) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24);
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    for (KW_TABLE_6) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16);
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    for (KW_TABLE_7) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16) | (str[6] << 8);
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    for (KW_TABLE_8) |kw| {
        // const str = kw[0];
        // out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16) | (str[6] << 8) | str[7];
        out[i] = IdentBlock.parse_from_string(kw.id, NOTICE.ERROR).ident.data[0];
        i += 1;
    }
    break :eval out;
};

pub const KW_TOKEN_TABLE: [TOTAL_KW_COUNT]KIND = eval: {
    var out: [TOTAL_KW_COUNT]KIND = undefined;
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
pub const KW_TOKEN_SLICES_BY_LEN = [9][]const KIND{
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

pub const KIND_NAME: [@typeInfo(KIND).Enum.fields.len][]const u8 = compute: {
    var table: [@typeInfo(KIND).Enum.fields.len][]const u8 = undefined;
    for (@typeInfo(KIND).Enum.fields, 0..) |f, i| {
        table[i] = f.name;
    }
    break :compute table;
};

pub fn create_token_output_file(alloc: Allocator, working_dir: *const std.fs.Dir, path: []const u8, list: *List(Self)) !std.fs.File {
    const out_file = try working_dir.createFile(path, std.fs.File.CreateFlags{
        .read = true,
        .exclusive = false,
        .truncate = true,
    });
    var row: u32 = 0;
    for (list.items) |token| {
        const name = KIND_NAME[@intFromEnum(token.kind)];
        while (token.row_start > row) {
            row += 1;
            _ = try out_file.write("\n");
        }
        switch (token.kind) {
            KIND.LIT_INTEGER,
            => {
                if (token.data_extra == 1) { // negative
                    _ = try out_file.write(try std.fmt.allocPrint(alloc, "{s}({d}) ", .{ name, -@as(i64, @bitCast(token.data_val_or_ptr)) }));
                } else {
                    _ = try out_file.write(try std.fmt.allocPrint(alloc, "{s}({d}) ", .{ name, token.data_val_or_ptr }));
                }
            },
            KIND.LIT_FLOAT => {
                _ = try out_file.write(try std.fmt.allocPrint(alloc, "{s}({d}) ", .{ name, @as(f64, @bitCast(token.data_val_or_ptr)) }));
            },
            KIND.LIT_BOOL => {
                _ = try out_file.write(try std.fmt.allocPrint(alloc, "{s}({any}) ", .{ name, @as(bool, @bitCast(@as(u1, @truncate(token.data_val_or_ptr)))) }));
            },
            KIND.LIT_STRING, KIND.LIT_STR_TEMPLATE => {
                _ = try out_file.write(try std.fmt.allocPrint(alloc, "{s}({s}) ", .{ name, ProgramROM.global.ptr[token.data_val_or_ptr .. token.data_val_or_ptr + token.data_len] }));
            },
            KIND.IDENT => {
                _ = try out_file.write(try std.fmt.allocPrint(alloc, "{s}({s}) ", .{ name, IdentManager.global.ident_names.items[token.data_val_or_ptr] }));
            },
            else => {
                _ = try out_file.write(try std.fmt.allocPrint(alloc, "{s} ", .{name}));
            },
        }
    }
    try out_file.seekTo(0);
    return out_file;
}
