const assert = @import("std").debug.assert;
const Token = @import("./Token.zig");
const TKIND = Token.KIND;
const ENC = @import("./ByteRemap.zig").ENC;
const std = @import("std");

const Self = @This();

source: []const u8,
source_key: u16,
curr_pos: u32,
curr_col: u32,
curr_row: u32,
complete: bool,
prev_pos: u32,
prev_col: u32,
prev_row: u32,

pub fn new(source: []u8, source_key: u16) Self {
    return Self{
        .source = source,
        .source_key = source_key,
        .curr_pos = 0,
        .curr_col = 0,
        .curr_row = 0,
        .complete = false,
        .prev_pos = 0,
        .prev_col = 0,
        .prev_row = 0,
    };
}

pub fn next_token(self: *Self) LexerError!Token {
    assert(!self.complete);
    var token_builder = TokenBuilder.new(self.source_key, self.curr_col, self.curr_row);
    if (self.curr_pos >= self.source.len) {
        self.complete = true;
        return self.finish_token(TKIND.EOF, token_builder);
    }
    var byte_1 = self.read_next_byte();
    while (self.is_whitespace(byte_1) and self.more_bytes_in_source()) {
        //FIXME Handle comment tokens here and output to separate list or ignore
        token_builder.set_start(self.curr_col, self.curr_row);
        byte_1 = self.read_next_byte();
    }
    if (!self.more_bytes_in_source()) {
        self.complete = true;
        return self.finish_token(TKIND.EOF, token_builder);
    }
    switch (byte_1) {
        ENC.COLON => return self.finish_token(TKIND.COLON, token_builder),
        ENC.AT_SIGN => return self.finish_token(TKIND.REFERENCE, token_builder),
        ENC.DOLLAR => return self.finish_token(TKIND.SUBSTITUTE, token_builder),
        ENC.COMMA => return self.finish_token(TKIND.COMMA, token_builder),
        ENC.SEMICOL => return self.finish_token(TKIND.SEMICOL, token_builder),
        ENC.L_PAREN => return self.finish_token(TKIND.L_PAREN, token_builder),
        ENC.R_PAREN => return self.finish_token(TKIND.R_PAREN, token_builder),
        ENC.L_CURLY => return self.finish_token(TKIND.L_CURLY, token_builder),
        ENC.R_CURLY => return self.finish_token(TKIND.R_CURLY, token_builder),
        ENC.L_SQUARE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.R_SQUARE => return self.finish_token(TKIND.SLICE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.L_SQUARE, token_builder);
        },
        ENC.R_SQUARE => return self.finish_token(TKIND.R_SQUARE, token_builder),
        ENC.QUESTION => return self.finish_token(TKIND.MAYBE_NONE, token_builder),
        ENC.PERIOD => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.PERIOD => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.PERIOD => return self.finish_token(TKIND.RANGE_INCLUDE_BOTH, token_builder),
                                ENC.PIPE => return self.finish_token(TKIND.RANGE_EXCLUDE_END, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        return self.finish_token(TKIND.ILLEGAL, token_builder);
                    },
                    ENC.AT_SIGN => return self.finish_token(TKIND.DEREREFENCE, token_builder),
                    ENC.QUESTION => return self.finish_token(TKIND.ACCESS_MAYBE_NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ACCESS, token_builder);
        },
        ENC.EQUALS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.EQUALS, token_builder),
                    ENC.MORE_THAN => return self.finish_token(TKIND.FAT_ARROW, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ASSIGN, token_builder);
        },
        ENC.LESS_THAN => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.LESS_THAN_EQUAL, token_builder),
                    ENC.LESS_THAN => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.EQUALS => return self.finish_token(TKIND.SHIFT_L_ASSIGN, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.SHIFT_L, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.LESS_THAN, token_builder);
        },
        ENC.MORE_THAN => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.MORE_THAN_EQUAL, token_builder),
                    ENC.LESS_THAN => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.EQUALS => return self.finish_token(TKIND.SHIFT_R_ASSIGN, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.SHIFT_R, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.MORE_THAN, token_builder);
        },
        ENC.EXCLAIM => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.NOT_EQUAL, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.LOGIC_NOT, token_builder);
        },
        ENC.PLUS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.ADD_ASSIGN, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ADD, token_builder);
        },
        ENC.MINUS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.SUB_ASSIGN, token_builder),
                    ENC._0...ENC._9 => self.handle_number_literal(token_builder, true, byte_2),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.SUB, token_builder);
        },
        ENC.ASTERISK => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.MULT_ASSIGN, token_builder),
                    ENC.ASTERISK => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.EQUALS => return self.finish_token(TKIND.POWER_ASSIGN, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.POWER, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.MULT, token_builder);
        },
        ENC.F_SLASH => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.DIV_ASSIGN, token_builder),
                    ENC.F_SLASH => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.EQUALS => return self.finish_token(TKIND.ROOT_ASSIGN, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.ROOT, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.DIV, token_builder);
        },
        ENC.PERCENT => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.MODULO_ASSIGN, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.MODULO, token_builder);
        },
        ENC.AMPER => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.BIT_AND_ASSIGN, token_builder),
                    ENC.AMPER => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.EQUALS => return self.finish_token(TKIND.LOGIC_AND_ASSIGN, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.LOGIC_AND, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_AND, token_builder);
        },
        ENC.PIPE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.BIT_OR_ASSIGN, token_builder),
                    ENC.PIPE => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.EQUALS => return self.finish_token(TKIND.LOGIC_OR_ASSIGN, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.LOGIC_OR, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_OR, token_builder);
        },
        ENC.CARET => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.BIT_XOR_ASSIGN, token_builder),
                    ENC.CARET => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ENC.EQUALS => return self.finish_token(TKIND.LOGIC_XOR_ASSIGN, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.LOGIC_XOR, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_XOR, token_builder);
        },
        ENC.TILDE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ENC.EQUALS => return self.finish_token(TKIND.BIT_NOT_ASSIGN, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_NOT, token_builder);
        },
        ENC._0...ENC._9 => self.handle_number_literal(token_builder, false, byte_1),
        ENC.A...ENC.UNDERSCORE => {
            //FIXME handle identifier/keyword tokens
        },
        ENC._0...ENC.COMMA => return self.finish_token(TKIND.ILLEGAL_OPERATOR, token_builder),
        else => return self.finish_token(TKIND.ILLEGAL_BYTE, token_builder),
    }
}

inline fn finish_integer_literal_token(self: *Self, token_builder: TokenBuilder, value: u64, negative: bool) LexerError!Token {
    if ((!negative and value > MAX_POSITIVE_I64) or (negative and value > MAX_NEGATIVE_I64)) {
        return LexerError.PARSE_INTEGER_TOO_LARGE;
    }
    var ival: i64 = @bitCast(value);
    if (negative and value != MAX_NEGATIVE_I64) {
        ival = -ival;
    }
    token_builder.set_data(@bitCast(ival), 1);
    return self.finish_token(TKIND.LIT_INT, token_builder);
}

inline fn collect_illegal_alphanumeric_string(self: *Self, token_builder: TokenBuilder, illegal_kind: TKIND) Token {
    while (self.curr_pos < self.source.len) {
        const next_byte = self.read_next_byte();
        switch (next_byte) {
            ENC._0...ENC.UNDERSCORE => {},
            else => {
                self.rollback_one_byte();
                return self.finish_token(illegal_kind, token_builder);
            },
        }
    }
    return self.finish_token(illegal_kind, token_builder);
}

inline fn collect_illegal_alphanumeric_string_plus_dot(self: *Self, token_builder: TokenBuilder, illegal_kind: TKIND) Token {
    while (self.curr_pos < self.source.len) {
        const next_byte = self.read_next_byte();
        switch (next_byte) {
            ENC._0...ENC.UNDERSCORE, ENC.PERIOD => {},
            else => {
                self.rollback_one_byte();
                return self.finish_token(illegal_kind, token_builder);
            },
        }
    }
    return self.finish_token(illegal_kind, token_builder);
}

inline fn more_bytes_in_source(self: *Self) bool {
    return self.curr_pos < self.source.len;
}

inline fn handle_number_literal(self: *Self, token_builder: TokenBuilder, negative: bool, byte_1: u8) LexerError!Token {
    assert(byte_1 < 10);
    if (self.curr_pos == self.source.len) return self.finish_integer_literal_token(token_builder, byte_1, negative);
    const byte_2 = self.read_next_byte();
    if (byte_1 == 0) {
        switch (byte_2) {
            ENC.b => {
                var data_value: u64 = 0;
                var bit_position: u32 = 0;
                var leading_zeroes = 0;
                while (self.curr_pos < self.source.len) {
                    const leading_zero = self.read_next_byte();
                    if (leading_zero != ENC._0 or leading_zero != ENC.UNDERSCORE) {
                        self.rollback_one_byte();
                        break;
                    } else if (leading_zero == ENC._0) leading_zeroes += 1;
                }
                while (self.curr_pos < self.source.len) {
                    const byte_x = self.read_next_byte();
                    switch (byte_x) {
                        ENC._0...ENC._1 => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string(token_builder, TKIND.ILLEGAL_INTEGER_OVERFLOWS_64_BITS);
                            }
                            data_value |= byte_x << (63 - bit_position);
                            bit_position += 1;
                        },
                        ENC.UNDERSCORE => {},
                        ENC._2...ENC.z => return self.collect_illegal_alphanumeric_string(token_builder, TKIND.ILLEGAL_ALPHANUM_IN_BINARY),
                        else => {
                            if (leading_zeroes == 0 or bit_position == 0) {
                                return self.finish_token(TKIND.ILLEGAL_INTEGER_NO_SIGNIFICANT_BITS, token_builder);
                            }
                            data_value >>= (64 - bit_position);
                            self.rollback_one_byte();
                            return self.finish_integer_literal_token(token_builder, data_value, negative);
                        },
                    }
                }
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token(TKIND.ILLEGAL_INTEGER_NO_SIGNIFICANT_BITS, token_builder);
                }
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ENC.o => {
                var data_value: u64 = 0;
                var bit_position: u32 = 0;
                var leading_zeroes = 0;
                while (self.curr_pos < self.source.len) {
                    const leading_zero = self.read_next_byte();
                    if (leading_zero != ENC._0 or leading_zero != ENC.UNDERSCORE) {
                        self.rollback_one_byte();
                        break;
                    } else if (leading_zero == ENC._0) leading_zeroes += 1;
                }
                while (self.curr_pos < self.source.len) {
                    const byte_x = self.read_next_byte();
                    switch (byte_x) {
                        ENC._0...ENC._7 => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string(token_builder, TKIND.ILLEGAL_INTEGER_OVERFLOWS_64_BITS);
                            } else if (bit_position == 63) {
                                if (data_value & 0xC000000000000000 != 0) {
                                    return self.collect_illegal_alphanumeric_string(token_builder, TKIND.ILLEGAL_INTEGER_OVERFLOWS_64_BITS);
                                }
                                data_value = (data_value << 2) | byte_x;
                            } else {
                                data_value |= byte_x << (61 - bit_position);
                                bit_position += 3;
                            }
                        },
                        ENC.UNDERSCORE => {},
                        ENC._8...ENC.z => return self.collect_illegal_alphanumeric_string(token_builder, TKIND.ILLEGAL_ALPHANUM_IN_OCTAL),
                        else => {
                            if (leading_zeroes == 0 or bit_position == 0) {
                                return self.finish_token(TKIND.ILLEGAL_INTEGER_NO_SIGNIFICANT_BITS, token_builder);
                            }
                            data_value >>= (64 - bit_position);
                            self.rollback_one_byte();
                            return self.finish_integer_literal_token(token_builder, data_value, negative);
                        },
                    }
                }
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token(TKIND.ILLEGAL_INTEGER_NO_SIGNIFICANT_BITS, token_builder);
                }
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ENC.x => {
                var data_value: u64 = 0;
                var bit_position: u32 = 0;
                var leading_zeroes = 0;
                while (self.curr_pos < self.source.len) {
                    const leading_zero = self.read_next_byte();
                    if (leading_zero != ENC._0 or leading_zero != ENC.UNDERSCORE) {
                        self.rollback_one_byte();
                        break;
                    } else if (leading_zero == ENC._0) leading_zeroes += 1;
                }
                while (self.curr_pos < self.source.len) {
                    const byte_x = ENC.LEXBYTE_TO_HEX[self.read_next_byte()];
                    switch (byte_x) {
                        ENC._0...ENC._F => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string(token_builder, TKIND.ILLEGAL_INTEGER_OVERFLOWS_64_BITS);
                            }
                            data_value |= byte_x << (60 - bit_position);
                            bit_position += 4;
                        },
                        ENC.UNDERSCORE => {},
                        ENC._G...ENC.z => return self.collect_illegal_alphanumeric_string(token_builder, TKIND.ILLEGAL_ALPHANUM_IN_HEX),
                        else => {
                            if (leading_zeroes == 0 or bit_position == 0) {
                                return self.finish_token(TKIND.ILLEGAL_INTEGER_NO_SIGNIFICANT_BITS, token_builder);
                            }
                            data_value >>= (64 - bit_position);
                            self.rollback_one_byte();
                            return self.finish_integer_literal_token(token_builder, data_value, negative);
                        },
                    }
                }
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token(TKIND.ILLEGAL_INTEGER_NO_SIGNIFICANT_BITS, token_builder);
                }
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ENC._0...ENC._9, ENC.PERIOD, ENC.UNDERSCORE => {
                self.rollback_one_byte();
            },
            else => {
                self.rollback_one_byte();
                return self.finish_integer_literal_token(token_builder, 0, negative);
            },
        }
    }
    var data: [2]u64 = [2]u64{ @as(u64, byte_1), 0 };
    var data_part: usize = 0;
    switch (byte_2) {
        ENC._0...ENC._9 => {
            data[data_part] = (data[data_part] * 10) + @as(u64, byte_2);
        },
        ENC.PERIOD => {
            data_part = 1;
        },
        _ => {},
    }
    while (self.curr_pos < self.source.len) {
        const byte_x = self.read_next_byte();
        switch (byte_x) {
            ENC._0...ENC._9 => {
                data[data_part] = (data[data_part] * 10) + @as(u64, byte_2);
            },
            ENC.PERIOD => {
                if (data_part == 1) {
                    return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TKIND.ILLEGAL_FLOAT_TOO_MANY_DOTS);
                }
                data_part = 1;
            },
            ENC.UNDERSCORE => {},
            else => {
                self.rollback_one_byte();
                if (data_part == 0) return self.finish_integer_literal_token(token_builder, data[0], negative);
                @panic("float literals not implemented"); //FIXME Handle floating point numbers somehow
            },
        }
    }
    if (data_part == 0) return self.finish_integer_literal_token(token_builder, data[0], negative);
    @panic("float literals not implemented"); //FIXME Handle floating point numbers somehow
}

inline fn finish_token(self: *Self, kind: Token.TokenKind, token_builder: TokenBuilder) Token {
    return Token{
        .kind = kind,
        .source_key = token_builder.source_key,
        .row_start = token_builder.row,
        .row_end = self.curr_row,
        .col_start = token_builder.col,
        .col_end = self.curr_col,
        .data_val_or_ptr = token_builder.data_val_or_ptr,
        .data_len = token_builder.data_len,
    };
}

inline fn rollback_one_byte(self: *Self) void {
    assert(self.curr_pos > 0);
    self.curr_pos -= 1;
    const tmp_pos = self.next_or_prev_pos;
    const tmp_col = self.next_or_prev_col;
    const tmp_row = self.next_or_prev_row;
    self.next_or_prev_pos = self.curr_pos;
    self.next_or_prev_col = self.curr_col;
    self.next_or_prev_row = self.curr_row;
    self.curr_pos = tmp_pos;
    self.curr_col = tmp_col;
    self.curr_row = tmp_row;
    return;
}

// inline fn rollback_pos(self: *Self, code: u32) void {
//     assert(self.curr_pos > 0);
//     assert(self.curr_pos >= self.next_or_prev_pos);
//     const tmp_pos = self.next_or_prev_pos;
//     const tmp_col = self.next_or_prev_col;
//     const tmp_row = self.next_or_prev_row;
//     self.next_or_prev_pos = self.curr_pos;
//     self.next_or_prev_col = self.curr_col;
//     self.next_or_prev_row = self.curr_row;
//     self.curr_pos = tmp_pos;
//     self.curr_col = tmp_col;
//     self.curr_row = tmp_row;
//     self.curr_processed = true;
//     self.curr_code = code;
//     return;
// }

inline fn is_whitespace(byte: u8) bool {
    return (byte >= ENC.WHITESPACE_MIN) and (byte <= ENC.WHITESPACE_MAX);
}

inline fn is_valid_ident_char_first(code: u8) bool {
    return (code == ENC.UNDERSCORE) or ((code >= ENC.LOWER_A) and (code <= ENC.LOWER_Z)) or ((code >= ENC.UPPER_A) and (code <= ENC.LOWER_Z));
}

inline fn is_valid_ident_char_rest(code: u8) bool {
    return (code == ENC.UNDERSCORE) or ((code >= ENC.LOWER_A) and (code <= ENC.LOWER_Z)) or ((code >= ENC.UPPER_A) and (code <= ENC.LOWER_Z)) or ((code >= ENC.ZERO) and (code <= ENC.NINE));
}

// inline fn scan_over_utf8_until_next_char_match(self: *Self, match_code: u32, include_match_in_token: bool) LexerError!bool {
//     var found = false;
//     while (self.curr_pos < self.source.len and !found) {
//         const next_code = try self.read_next_utf8_char();
//         found = next_code == match_code;
//     }
//     if (!include_match_in_token and found) {
//         self.rollback_pos(match_code);
//     }
//     return found;
// }

inline fn read_next_byte(self: *Self) u8 {
    assert(self.curr_pos < self.source.len);
    const val = self.source[self.curr_pos];
    self.next_or_prev_pos = self.curr_pos;
    self.next_or_prev_col = self.curr_col;
    self.next_or_prev_row = self.curr_row;
    self.curr_pos += 1;
    return ENC.ASCII_TO_LEXBYTE[val];
}

fn read_next_utf8_char(self: *Self) LexerError!u32 {
    if (self.curr_processed) {
        assert(self.next_or_prev_pos > self.curr_pos);
        self.curr_pos = self.next_or_prev_pos;
        self.curr_col = self.next_or_prev_col;
        self.curr_row = self.next_or_prev_row;
        self.curr_processed = false;
        return self.curr_code;
    }
    assert(self.curr_pos < self.source.len);
    self.next_or_prev_pos = self.curr_pos;
    self.next_or_prev_col = self.curr_col;
    self.next_or_prev_row = self.curr_row;
    const utf8_len: u8 = switch (self.source[self.curr_pos]) {
        0b0000_0000...0b0111_1111 => 1,
        0b1100_0000...0b1101_1111 => 2,
        0b1110_0000...0b1110_1111 => 3,
        0b1111_0000...0b1111_0111 => 4,
        else => return LexerError.UTF8_INVALID_byte_1,
    };
    if (self.curr_pos + utf8_len > self.source.len) {
        return LexerError.UTF8_BUFFER_ENDED_EARLY;
    }
    switch (utf8_len) {
        1 => {
            if (self.source[self.curr_pos] == ENC.NEWLINE) {
                self.curr_col = 0;
                self.curr_row += 1;
            } else {
                self.curr_col += 1;
            }
            self.curr_pos += 1;
            return @as(u32, self.source[self.curr_pos]);
        },
        2 => {
            if (self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) return LexerError.UTF8_INVALID_CONTINUE_BYTE;
            const code: u32 = ((self.source[self.curr_pos] & 0b00011111) << 6) | (self.source[self.curr_pos + 1] & 0b00111111);
            if (code < 0x80) return LexerError.UTF8_OVERLONG_ENCODING;
            self.curr_col += 1;
            self.curr_pos += 2;
            return code;
        },
        3 => {
            if ((self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 2] & 0b11000000 != 0b10000000)) {
                return LexerError.UTF8_INVALID_CONTINUE_BYTE;
            }
            const code: u32 = ((self.source[self.curr_pos] & 0b00001111) << 12) | ((self.source[self.curr_pos + 1] & 0b00111111) << 6) | (self.source[self.curr_pos + 2] & 0b00111111);
            if ((code >= 0xD800) || (code <= 0xDFFF)) return LexerError.UTF8_INVALID_CODEPOINT;
            if (code < 0x800) return LexerError.UTF8_OVERLONG_ENCODING;
            self.curr_col += 1;
            self.curr_pos += 3;
            return code;
        },
        4 => {
            if ((self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 2] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 3] & 0b11000000 != 0b10000000)) {
                return LexerError.UTF8_INVALID_CONTINUE_BYTE;
            }
            const code: u32 = ((self.source[self.curr_pos] & 0b00000111) << 18) | ((self.source[self.curr_pos + 1] & 0b00111111) << 12) | ((self.source[self.curr_pos + 2] & 0b00111111) << 6) | (self.source[self.curr_pos + 3] & 0b00111111);
            if (code >= 0x110000) return LexerError.UTF8_INVALID_CODEPOINT;
            if (code < 0x10000) return LexerError.UTF8_OVERLONG_ENCODING;
            self.curr_col += 1;
            self.curr_pos += 4;
            return code;
        },
        else => unreachable,
    }
}

const LexerError = error{
    UTF8_INVALID_byte_1,
    UTF8_BUFFER_ENDED_EARLY,
    UTF8_OVERLONG_ENCODING,
    UTF8_INVALID_CONTINUE_BYTE,
    UTF8_INVALID_CODEPOINT,
    PARSE_INTEGER_NO_DIGITS,
    PARSE_INTEGER_TOO_LARGE,
};

const TokenBuilder = struct {
    source_key: u16,
    start_col: u32,
    start_row: u32,
    data_val_or_ptr: u64,
    data_len: u32,

    inline fn new(source_key: u16, start_col: u32, start_row: u32) TokenBuilder {
        return TokenBuilder{
            .source_key = source_key,
            .start_col = start_col,
            .start_row = start_row,
            .data_val_or_ptr = 0,
            .data_len = 0,
        };
    }

    inline fn set_start(self: *TokenBuilder, col: u32, row: u32) void {
        self.start_col = col;
        self.start_row = row;
    }

    inline fn set_data(self: *TokenBuilder, val_or_ptr: u64, len: u32) void {
        self.data_val_or_ptr = val_or_ptr;
        self.data_len = len;
    }
};

const MAX_POSITIVE_I64 = std.math.maxInt(isize);
const MAX_NEGATIVE_I64 = MAX_POSITIVE_I64 + 1;
