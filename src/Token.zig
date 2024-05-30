const A = @import("./Ascii.zig");

const Self = @This();

kind: KIND, // u8
warn: WARN, // u8
source_key: u16,
row_start: u32,
row_end: u32,
col_start: u32,
col_end: u32,
data_val_or_ptr: u64,
data_exp_or_len: u32,

pub const KIND = enum(u8) {
    // Meta
    EOF, // TL
    COMMENT, // TL
    STDLIB, // TL
    // Definition
    IMPORT, // T
    CONST, // T
    VAR, // T
    IDENT, // T
    DEFAULT, // T
    AS, // T
    // Types
    NONE, // T
    TYPE, // T
    FLOAT, // T
    U8, // T
    I8, // T
    U16, // T
    I16, // T
    U32, // T
    I32, // T
    U64, // T
    I64, // T
    F32, // T
    F64, // T
    BOOL, // T
    STRING, // T
    STRUCT, // T
    SLICE, // TL
    ENUM, // T
    UNION, // T
    TUPLE, // T
    FUNC, // T
    REFERENCE, // TL
    // Literals
    LIT_STRING,
    LIT_SUB_STR_BEGIN,
    LIT_SUB_STR_MIDDLE,
    LIT_SUB_STR_END,
    LIT_INTEGER,
    LIT_FLOAT,
    LIT_BOOL, // T
    // Operators
    MAYBE, // TL
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
    BIT_NOT_ASSIGN, // TL
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
    RANGE_EXCLUDE_BEGIN,
    RANGE_EXCLUDE_BOTH,
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
    MATCH, // T
    IF, // T
    ELSE, // T
    WHILE, // T
    FOR_EACH, // T
    IN, // T
    BREAK, // T
    NEXT_LOOP, // T
    RETURN, // T
    // Illegal
    ILLEGAL, // TL
};

pub const WARN = enum(u8) {
    NONE,
    WARN_AMBIGUOUS_SATURATION,
    WARN_AMBIGUOUS_ZERO,
    ILLEGAL_OPERATOR,
    ILLEGAL_BYTE,
    ILLEGAL_ALPHANUM_IN_BINARY,
    ILLEGAL_ALPHANUM_IN_OCTAL,
    ILLEGAL_ALPHANUM_IN_HEX,
    ILLEGAL_ALPHANUM_IN_DECIMAL,
    ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS,
    ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS,
    ILLEGAL_INTEGER_LITERAL_LOSS_OF_DATA,
    ILLEGAL_INTEGER_LITERAL_NEG_OVERFLOWS_I64,
    ILLEGAL_FLOAT_LITERAL_TOO_LARGE,
    ILLEGAL_FLOAT_LITERAL_TOO_SMALL,
    ILLEGAL_FLOAT_TOO_MANY_SIG_DIGITS,
    ILLEGAL_NUMBER_TOO_MANY_DOTS,
    ILLEGAL_IDENT_TOO_LONG,
    ILLEGAL_NUMBER_TOO_MANY_EXPONENTS,
    ILLEGAL_NUMBER_PERIOD_IN_EXPONENT,
    ILLEGAL_NUMBER_EXPONENT_TOO_MANY_DIGITS,
};
pub const SMALLEST_WARN: u8 = @intFromEnum(WARN.WARN_AMBIGUOUS_SATURATION);
pub const SMALLEST_ILLEGAL: u8 = @intFromEnum(WARN.ILLEGAL_OPERATOR);

pub const KW_TABLE_1 = [_].{ *const [1:0]u8, KIND, u64 }{
    .{ "_", KIND.DEFAULT, 0 },
};
pub const KW_TABLE_2 = [_].{ *const [2:0]u8, KIND, u64 }{
    .{ "as", KIND.AS, 0 },
    .{ "in", KIND.IN, 0 },
    .{ "u8", KIND.U8, 0 },
    .{ "i8", KIND.I8, 0 },
    .{ "if", KIND.IF, 0 },
};
pub const KW_TABLE_3 = [_].{ *const [3:0]u8, KIND, u64 }{
    .{ "var", KIND.VAR, 0 },
    .{ "str", KIND.STRING, 0 },
    .{ "std", KIND.STDLIB, 0 },
    .{ "u16", KIND.U16, 0 },
    .{ "i16", KIND.I16, 0 },
    .{ "u32", KIND.U32, 0 },
    .{ "i32", KIND.I32, 0 },
    .{ "u64", KIND.U64, 0 },
    .{ "i64", KIND.I64, 0 },
};
pub const KW_TABLE_4 = [_].{ *const [4:0]u8, KIND, u64 }{
    .{ "func", KIND.FUNC, 0 },
    .{ "bool", KIND.BOOL, 0 },
    .{ "type", KIND.TYPE, 0 },
    .{ "true", KIND.LIT_BOOL, 1 },
    .{ "none", KIND.NONE, 0 },
    .{ "enum", KIND.ENUM, 0 },
    .{ "else", KIND.ELSE, 0 },
};
pub const KW_TABLE_5 = [_].{ *const [5:0]u8, KIND, u64 }{
    .{ "const", KIND.CONST, 0 },
    .{ "float", KIND.FLOAT, 0 },
    .{ "while", KIND.WHILE, 0 },
    .{ "break", KIND.BREAK, 0 },
    .{ "false", KIND.LIT_BOOL, 0 },
    .{ "union", KIND.UNION, 0 },
    .{ "tuple", KIND.TUPLE, 0 },
    .{ "match", KIND.MATCH, 0 },
};
pub const KW_TABLE_6 = [_].{ *const [6:0]u8, KIND, u64 }{
    .{ "import", KIND.IMPORT, 0 },
    .{ "return", KIND.RETURN, 0 },
    .{ "struct", KIND.STRUCT, 0 },
};
pub const KW_TABLE_7 = [_].{ *const [7:0]u8, KIND, u64 }{
    .{ "foreach", KIND.FOR_EACH, 0 },
};
pub const KW_TABLE_8 = [_].{ *const [8:0]u8, KIND, u64 }{
    .{ "nextloop", KIND.NEXT_LOOP, 0 },
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
        const str = kw[0];
        out[i] = (str[0] << 56);
        i += 1;
    }
    for (KW_TABLE_2) |kw| {
        const str = kw[0];
        out[i] = (str[0] << 56) | (str[1] << 48);
        i += 1;
    }
    for (KW_TABLE_3) |kw| {
        const str = kw[0];
        out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40);
        i += 1;
    }
    for (KW_TABLE_4) |kw| {
        const str = kw[0];
        out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32);
        i += 1;
    }
    for (KW_TABLE_5) |kw| {
        const str = kw[0];
        out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24);
        i += 1;
    }
    for (KW_TABLE_6) |kw| {
        const str = kw[0];
        out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16);
        i += 1;
    }
    for (KW_TABLE_7) |kw| {
        const str = kw[0];
        out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16) | (str[6] << 8);
        i += 1;
    }
    for (KW_TABLE_8) |kw| {
        const str = kw[0];
        out[i] = (str[0] << 56) | (str[1] << 48) | (str[2] << 40) | (str[3] << 32) | (str[4] << 24) | (str[5] << 16) | (str[6] << 8) | str[7];
        i += 1;
    }
    break :eval out;
};

pub const KW_TOKEN_TABLE: [TOTAL_KW_COUNT]KIND = eval: {
    var out: [TOTAL_KW_COUNT]KIND = undefined;
    var i = 0;
    for (KW_TABLE_1) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    for (KW_TABLE_2) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    for (KW_TABLE_3) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    for (KW_TABLE_4) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    for (KW_TABLE_5) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    for (KW_TABLE_6) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    for (KW_TABLE_7) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    for (KW_TABLE_8) |kw| {
        out[i] = kw[1];
        i += 1;
    }
    break :eval out;
};

pub const KW_IMPLICIT_TABLE: [TOTAL_KW_COUNT]u64 = eval: {
    var out: [TOTAL_KW_COUNT]u64 = undefined;
    var i = 0;
    for (KW_TABLE_1) |kw| {
        out[i] = kw[2];
        i += 1;
    }
    for (KW_TABLE_2) |kw| {
        out[i] = kw[2];
        i += 1;
    }
    for (KW_TABLE_3) |kw| {
        out[i] = kw[2];
        i += 1;
    }
    for (KW_TABLE_4) |kw| {
        out[i] = kw[2];
        i += 1;
    }
    for (KW_TABLE_5) |kw| {
        out[i] = kw[2];
        i += 1;
    }
    for (KW_TABLE_6) |kw| {
        out[i] = kw[2];
        i += 1;
    }
    for (KW_TABLE_7) |kw| {
        out[i] = kw[2];
        i += 1;
    }
    for (KW_TABLE_8) |kw| {
        out[i] = kw[2];
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
pub const KW_TOKEN_SLICES_BY_LEN = [9][]const u64{
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
