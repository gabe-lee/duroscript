const A = @import("./Ascii.zig");

const Self = @This();

kind: KIND, //u8
source_key: u16,
row_start: u32,
row_end: u32,
col_start: u32,
col_end: u32,
data_val_or_ptr: u64,
data_len: u32,
data_bool: bool,

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
    MAYBE_NONE, // TL
    TYPE, // T
    FLOAT, // T
    INT, // T
    BOOL, // T
    BYTE, // T
    STRING, // T
    STRUCT, // T
    SLICE, // TL
    ENUM, // T
    UNION, // T
    TUPLE, // T
    FUNC, // T
    REFERENCE, // TL
    // Literals
    LIT_STR,
    LIT_SUB_STR_BEGIN,
    LIT_SUB_STR_MIDDLE,
    LIT_SUB_STR_END,
    LIT_INT,
    LIT_FLT,
    LIT_BOOL, // T
    // Operators
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
    ACCESS_MAYBE_NONE, // TL
    FAT_ARROW, // TL
    // Control Flow
    BRANCH, // T
    WHILE, // T
    FOR, // T
    IN, // T
    BREAK, // T
    NEXT_LOOP, // T
    RETURN, // T
    //
    ILLEGAL_OPERATOR,
    ILLEGAL_BYTE,
    ILLEGAL_ALPHANUM_IN_BINARY,
    ILLEGAL_ALPHANUM_IN_OCTAL,
    ILLEGAL_ALPHANUM_IN_HEX,
    ILLEGAL_ALPHANUM_IN_DECIMAL,
    ILLEGAL_INTEGER_OVERFLOWS_64_BITS,
    ILLEGAL_INTEGER_NO_SIGNIFICANT_BITS,
    ILLEGAL_FLOAT_TOO_MANY_DOTS,
    ILLEGAL_IDENT_TOO_LONG,
    ILLEGAL_NUMBER_TOO_MANY_EXPONENTS,
    ILLEGAL_NUMBER_OVERFLOWS_64_BITS,
};

pub const KEYWORD_U64_TABLE = [27]u64{
    (A.UNDERSCORE << 56), // _
    ((A.a << 56) | (A.s << 48)), // as
    ((A.i << 56) | (A.n << 48)), // in
    ((A.v << 56) | (A.a << 48) | (A.r << 40)), // var
    ((A.i << 56) | (A.n << 48) | (A.t << 40)), // int
    ((A.f << 56) | (A.o << 48) | (A.r << 40)), // for
    ((A.s << 56) | (A.t << 48) | (A.d << 40)), // std
    ((A.f << 56) | (A.u << 48) | (A.n << 40) | (A.c << 32)), // func
    ((A.b << 56) | (A.o << 48) | (A.o << 40) | (A.l << 32)), // bool
    ((A.b << 56) | (A.y << 48) | (A.t << 40) | (A.e << 32)), // byte
    ((A.t << 56) | (A.y << 48) | (A.p << 40) | (A.e << 32)), // type
    ((A.t << 56) | (A.r << 48) | (A.u << 40) | (A.e << 32)), // true
    ((A.n << 56) | (A.o << 48) | (A.n << 40) | (A.e << 32)), // none
    ((A.e << 56) | (A.n << 48) | (A.u << 40) | (A.m << 32)), // enum
    ((A.c << 56) | (A.o << 48) | (A.n << 40) | (A.s << 32) | (A.t << 24)), // const
    ((A.f << 56) | (A.l << 48) | (A.o << 40) | (A.a << 32) | (A.t << 24)), // float
    ((A.w << 56) | (A.h << 48) | (A.i << 40) | (A.l << 32) | (A.e << 24)), // while
    ((A.b << 56) | (A.r << 48) | (A.e << 40) | (A.a << 32) | (A.k << 24)), // break
    ((A.f << 56) | (A.a << 48) | (A.l << 40) | (A.s << 32) | (A.e << 24)), // false
    ((A.u << 56) | (A.n << 48) | (A.i << 40) | (A.o << 32) | (A.n << 24)), // union
    ((A.t << 56) | (A.u << 48) | (A.p << 40) | (A.l << 32) | (A.e << 24)), // tuple
    ((A.s << 56) | (A.t << 48) | (A.r << 40) | (A.i << 32) | (A.n << 24) | (A.g << 16)), // string
    ((A.b << 56) | (A.r << 48) | (A.a << 40) | (A.n << 32) | (A.c << 24) | (A.h << 16)), // branch
    ((A.i << 56) | (A.m << 48) | (A.p << 40) | (A.o << 32) | (A.r << 24) | (A.t << 16)), // import
    ((A.r << 56) | (A.e << 48) | (A.t << 40) | (A.u << 32) | (A.r << 24) | (A.n << 16)), // return
    ((A.s << 56) | (A.t << 48) | (A.r << 40) | (A.u << 32) | (A.c << 24) | (A.t << 16)), // struct
    ((A.n << 56) | (A.e << 48) | (A.x << 40) | (A.t << 32) | (A.l << 24) | (A.o << 16) | (A.o << 8) | A.p), // nextloop
};
pub const KEYWORD_U64_SLICES_BY_LEN = [9][]const u64{
    KEYWORD_U64_TABLE[0..0], // 0 char slice
    KEYWORD_U64_TABLE[0..1], // 1 char slice
    KEYWORD_U64_TABLE[1..3], // 2 char slice
    KEYWORD_U64_TABLE[3..7], // 3 char slice
    KEYWORD_U64_TABLE[7..14], // 4 char slice
    KEYWORD_U64_TABLE[14..21], // 5 char slice
    KEYWORD_U64_TABLE[21..26], // 6 char slice
    KEYWORD_U64_TABLE[26..26], // 7 char slice
    KEYWORD_U64_TABLE[26..27], // 8 char slice
};
pub const KEYWORD_TOKEN_TABLE = [27]KIND{
    KIND.DEFAULT, // _
    KIND.AS, // as
    KIND.IN, // in
    KIND.VAR, // var
    KIND.INT, // int
    KIND.FOR, // for
    KIND.STDLIB, // for
    KIND.FUNC, // func
    KIND.BOOL, // bool
    KIND.BYTE, // byte
    KIND.TYPE, // type
    KIND.LIT_BOOL, // true
    KIND.NONE, // none
    KIND.ENUM, // enum
    KIND.CONST, // const
    KIND.FLOAT, // float
    KIND.WHILE, // while
    KIND.BREAK, // break
    KIND.LIT_BOOL, // false
    KIND.UNION, // union
    KIND.TUPLE, // tuple
    KIND.STRING, // string
    KIND.BRANCH, // branch
    KIND.IMPORT, // import
    KIND.RETURN, // return
    KIND.STRUCT, // struct
    KIND.NEXT_LOOP, // nextloop
};
pub const KEYWORD_TOKEN_SLICES_BY_LEN = [9][]const KIND{
    KEYWORD_TOKEN_TABLE[0..0], // 0 char slice
    KEYWORD_TOKEN_TABLE[0..1], // 1 char slice
    KEYWORD_TOKEN_TABLE[1..3], // 2 char slice
    KEYWORD_TOKEN_TABLE[3..7], // 3 char slice
    KEYWORD_TOKEN_TABLE[7..14], // 4 char slice
    KEYWORD_TOKEN_TABLE[14..21], // 5 char slice
    KEYWORD_TOKEN_TABLE[21..26], // 6 char slice
    KEYWORD_TOKEN_TABLE[26..26], // 7 char slice
    KEYWORD_TOKEN_TABLE[26..27], // 8 char slice
};
pub const LITERAL_BOOL_TRUE = KEYWORD_U64_TABLE[11];
