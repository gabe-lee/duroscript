const std = @import("std");

const Self = @This();

kind: KIND,
byte_start: u32,
byte_end: u32,
row: u32,
col_start: u32,
col_end: u32,

pub const KIND = enum(u8) {
    // Meta
    ILLEGAL, // TL
    EOF, // TL
    // Definition
    IMPORT, // T
    CONST, // T
    VAR, // T
    FUNC, // T
    IDENT, // T
    STRUCT, // T
    FLOAT, // T
    INT, // T
    BOOL, // T
    BYTE, // T
    STRING, // T
    IGNORE, // T
    AS, // T
    // Literals
    LITERAL_STR,
    LITERAL_INT,
    LITERAL_FLT,
    LITERAL_BOOL,
    // OPERATORS
    ASSIGN, // TL
    EQUALS, // TL
    LESS_THAN, // TL
    MORE_THAN, // TL
    LESS_THAN_EQUAL, // TL
    MORE_THAN_EQUAL, // TL
    NOT_EQUAL, // TL
    ADD,
    SUB,
    MULT,
    DIV,
    MODULO,
    ADD_ASSIGN,
    SUB_ASSIGN,
    MULT_ASSIGN,
    DIV_ASSIGN,
    MODULO_ASSIGN,
    POWER,
    POWER_ASSIGN,
    SHIFT_L, // TL
    SHIFT_R, // TL
    SHIFT_L_ASSIGN, // TL
    SHIFT_R_ASSIGN, // TL
    BIT_AND,
    BIT_OR,
    BIT_NOT,
    BIT_XOR,
    BIT_AND_ASSIGN,
    BIT_OR_ASSIGN,
    BIT_NOT_ASSIGN,
    BIT_XOR_ASSIGN,
    LOGIC_AND,
    LOGIC_OR,
    LOGIC_NOT, // TL
    LOGIC_XOR,
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
    DOT, // TL
    CONCAT, // TL
    PIPE,
    FAT_ARROW, // TL
    // Control Flow
    BRANCH, // T
    WHILE, // T
    FOR, // T
    IN, // T
    BREAK, // T
    GO_NEXT, // T
};

const KEY_LITERALS_1 = [_][1]u8{"_"};
const KEY_TOKENS_1 = [_]KIND{KIND.IGNORE};
const KEY_LITERALS_2 = [_][2]u8{ "as", "in" };
const KEY_TOKENS_2 = [_]KIND{ KIND.AS, KIND.IN };
const KEY_LITERALS_3 = [_][3]u8{ "var", "int", "for" };
const KEY_TOKENS_3 = [_]KIND{ KIND.VAR, KIND.INT, KIND.FOR };
const KEY_LITERALS_4 = [_][4]u8{ "func", "bool", "byte" };
const KEY_TOKENS_4 = [_]KIND{ KIND.FUNC, KIND.BOOL, KIND.BYTE };
const KEY_LITERALS_5 = [_][5]u8{ "const", "float", "while", "break" };
const KEY_TOKENS_5 = [_]KIND{ KIND.CONST, KIND.FLOAT, KIND.WHILE, KIND.BREAK };
const KEY_LITERALS_6 = [_][6]u8{ "struct", "string", "gonext", "branch", "import" };
const KEY_TOKENS_6 = [_]KIND{ KIND.STRUCT, KIND.STRING, KIND.GO_NEXT, KIND.BRANCH, KIND.IMPORT };

pub const KEY_TOKENS_ARRAY = KEY_TOKENS_1 ++ KEY_TOKENS_2 ++ KEY_TOKENS_3 ++ KEY_TOKENS_4 ++ KEY_TOKENS_5 ++ KEY_TOKENS_6;
pub const KEY_TOKENS_ARRAY_OFFSETS_BY_LEN: [7]usize = [7]usize{
    0,
    0,
    KEY_TOKENS_1.len,
    KEY_TOKENS_1.len + KEY_TOKENS_2.len,
    KEY_TOKENS_1.len + KEY_TOKENS_2.len + KEY_TOKENS_3.len,
    KEY_TOKENS_1.len + KEY_TOKENS_2.len + KEY_TOKENS_3.len + KEY_TOKENS_4.len,
    KEY_TOKENS_1.len + KEY_TOKENS_2.len + KEY_TOKENS_3.len + KEY_TOKENS_4.len + KEY_TOKENS_5.len,
};
pub const KEYWORD_COUNTS_BY_LEN: [7]usize = [7]usize{
    0,
    KEY_TOKENS_1.len,
    KEY_TOKENS_2.len,
    KEY_TOKENS_3.len,
    KEY_TOKENS_4.len,
    KEY_TOKENS_5.len,
    KEY_TOKENS_6.len,
};
pub const KEY_LITERALS_ARRAY = comp: {
    const TOTAL_KEYWORDS_LEN = (KEY_LITERALS_1.len * 1) + (KEY_LITERALS_2.len * 2) + (KEY_LITERALS_3.len * 3) + (KEY_LITERALS_4.len * 4) + (KEY_LITERALS_5.len * 5) + (KEY_LITERALS_6.len * 6);
    var array = [TOTAL_KEYWORDS_LEN]u8;
    var i = 0;
    for (KEY_LITERALS_1) |k| {
        for (k) |kc| {
            array[i] = @as(u32, kc);
            i += 1;
        }
    }
    for (KEY_LITERALS_2) |k| {
        for (k) |kc| {
            array[i] = @as(u32, kc);
            i += 1;
        }
    }
    for (KEY_LITERALS_3) |k| {
        for (k) |kc| {
            array[i] = @as(u32, kc);
            i += 1;
        }
    }
    for (KEY_LITERALS_4) |k| {
        for (k) |kc| {
            array[i] = @as(u32, kc);
            i += 1;
        }
    }
    for (KEY_LITERALS_5) |k| {
        for (k) |kc| {
            array[i] = @as(u32, kc);
            i += 1;
        }
    }
    for (KEY_LITERALS_6) |k| {
        for (k) |kc| {
            array[i] = @as(u32, kc);
            i += 1;
        }
    }
    break :comp array;
};
pub const KEY_LITERALS_ARRAY_OFFSETS_BY_LEN = [7]usize{
    0,
    0,
    (KEY_TOKENS_1.len * 1),
    (KEY_TOKENS_1.len * 1) + (KEY_TOKENS_2.len * 2),
    (KEY_TOKENS_1.len * 1) + (KEY_TOKENS_2.len * 2) + (KEY_TOKENS_3.len * 3),
    (KEY_TOKENS_1.len * 1) + (KEY_TOKENS_2.len * 2) + (KEY_TOKENS_3.len * 3) + (KEY_TOKENS_4.len * 4),
    (KEY_TOKENS_1.len * 1) + (KEY_TOKENS_2.len * 2) + (KEY_TOKENS_3.len * 3) + (KEY_TOKENS_4.len * 4) + (KEY_TOKENS_5.len * 5),
};
pub const SHORTEST_KEYWORD = 1;
pub const LONGEST_KEYWORD = 6;
