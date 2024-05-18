const assert = @import("std").debug.assert;
const Token = @import("./Token.zig");
const TKIND = Token.KIND;
const ASC = @import("./Ascii.zig");

const Self = @This();

source: []const u8,
source_key: u16,
curr_pos: u32,
curr_col: u32,
curr_row: u32,
complete: bool,
curr_processed: bool,
curr_code: u32,
next_or_prev_pos: u32,
next_or_prev_col: u32,
next_or_prev_row: u32,

pub fn new(source: []u8, source_key: u16) Self {
    return Self{
        .source = source,
        .source_key = source_key,
        .curr_pos = 0,
        .curr_col = 0,
        .curr_row = 0,
        .complete = false,
        .curr_processed = false,
        .curr_code = 0,
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
    var first_char = try self.read_next_utf8_char();
    while (self.is_whitespace(first_char)) {
        token_builder.set_start(self.curr_col, self.curr_row);
        first_char = try self.read_next_utf8_char();
    }
    switch (first_char) {
        ASC.COLON => return self.finish_token(TKIND.COLON, token_builder),
        ASC.AT_SIGN => return self.finish_token(TKIND.REFERENCE, token_builder),
        ASC.DOLLAR => return self.finish_token(TKIND.SUBSTITUTE, token_builder),
        ASC.COMMA => return self.finish_token(TKIND.COMMA, token_builder),
        ASC.SEMICOL => return self.finish_token(TKIND.SEMICOL, token_builder),
        ASC.L_PAREN => return self.finish_token(TKIND.L_PAREN, token_builder),
        ASC.R_PAREN => return self.finish_token(TKIND.R_PAREN, token_builder),
        ASC.L_CURLY => return self.finish_token(TKIND.L_CURLY, token_builder),
        ASC.R_CURLY => return self.finish_token(TKIND.R_CURLY, token_builder),
        ASC.L_SQUARE => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.R_SQUARE => return self.finish_token(TKIND.SLICE_OF, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.L_SQUARE, token_builder);
                },
            }
        },
        ASC.R_SQUARE => return self.finish_token(TKIND.R_SQUARE, token_builder),
        ASC.DOT => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.DOT => return self.finish_token(TKIND.CONCAT, token_builder),
                ASC.AT_SIGN => return self.finish_token(TKIND.DEREREFENCE, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.DOT, token_builder);
                },
            }
        },
        ASC.EQUALS => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.EQUALS, token_builder),
                ASC.MORE_THAN => return self.finish_token(TKIND.FAT_ARROW, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.ASSIGN, token_builder);
                },
            }
        },
        ASC.LESS_THAN => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.LESS_THAN_EQUAL, token_builder),
                ASC.LESS_THAN => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.SHIFT_L_ASSIGN, token_builder),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.SHIFT_L, token_builder);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.LESS_THAN, token_builder);
                },
            }
        },
        ASC.MORE_THAN => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.MORE_THAN_EQUAL, token_builder),
                ASC.MORE_THAN => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.SHIFT_R_ASSIGN, token_builder),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.SHIFT_R, token_builder);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.MORE_THAN, token_builder);
                },
            }
        },
        ASC.EXCLAIM => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.NOT_EQUAL, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.LOGIC_NOT, token_builder);
                },
            }
        },
        ASC.PLUS => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.ADD_ASSIGN, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.ADD, token_builder);
                },
            }
        },
        ASC.MINUS => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.SUB_ASSIGN, token_builder),
                //TODO: Add branch to handle number literals that start with a minus sign
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.SUB, token_builder);
                },
            }
        },
        ASC.ASTERISK => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.MULT_ASSIGN, token_builder),
                ASC.ASTERISK => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.POWER_ASSIGN, token_builder),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.POWER, token_builder);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.MULT, token_builder);
                },
            }
        },
        ASC.F_SLASH => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.DIV_ASSIGN, token_builder),
                ASC.F_SLASH => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.ROOT_ASSIGN, token_builder),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.ROOT, token_builder);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.DIV, token_builder);
                },
            }
        },
        ASC.PERCENT => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.MODULO_ASSIGN, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.MODULO, token_builder);
                },
            }
        },
        ASC.AMPER => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.BIT_AND_ASSIGN, token_builder),
                ASC.AMPER => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.LOGIC_AND_ASSIGN, token_builder),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.LOGIC_AND, token_builder);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.BIT_AND, token_builder);
                },
            }
        },
        ASC.PIPE => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.BIT_OR_ASSIGN, token_builder),
                ASC.PIPE => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.LOGIC_OR_ASSIGN, token_builder),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.LOGIC_OR, token_builder);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.BIT_OR, token_builder);
                },
            }
        },
        ASC.CARET => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.BIT_XOR_ASSIGN, token_builder),
                ASC.CARET => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.LOGIC_XOR_ASSIGN, token_builder),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.LOGIC_XOR, token_builder);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.BIT_XOR, token_builder);
                },
            }
        },
        ASC.TILDE => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.BIT_NOT_ASSIGN, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.BIT_NOT, token_builder);
                },
            }
        },
        // TODO: Move logic to separate function
        ASC.ZERO...ASC.NINE => {
            var is_float = false;
            const second_char = try self.read_next_utf8_char();
            if (first_char == ASC.ZERO) {
                switch (second_char) {
                    ASC.b => {
                        var data_value: u64 = 0;
                        var bit_position: u32 = 0;
                        while (self.curr_pos < self.source.len) {
                            const next_char = try self.read_next_utf8_char();
                            switch (next_char) {
                                ASC.UNDERSCORE => {},
                                ASC.ZERO, ASC.ONE => {
                                    if (bit_position >= 64) {
                                        return LexerError.PARSE_INTEGER_TOO_LARGE;
                                    }
                                    data_value |= (next_char - ASC.ZERO) << (63 - bit_position);
                                    bit_position += 1;
                                },
                                else => {
                                    if (bit_position == 0) {
                                        return LexerError.PARSE_INTEGER_NO_DIGITS;
                                    }
                                    data_value >>= (64 - bit_position);
                                    self.rollback_pos(next_char);
                                    token_builder.set_data(data_value, 1);
                                    return self.finish_token(TKIND.LIT_INT, token_builder);
                                },
                            }
                        }
                        if (bit_position == 0) {
                            return LexerError.PARSE_INTEGER_NO_DIGITS;
                        }
                        token_builder.set_data(data_value, 1);
                        return self.finish_token(TKIND.LIT_INT, token_builder);
                    },
                    ASC.o => {
                        var data_value: u64 = 0;
                        var bit_position: u32 = 0;
                        while (self.curr_pos < self.source.len) {
                            const next_char = try self.read_next_utf8_char();
                            switch (next_char) {
                                ASC.UNDERSCORE => {},
                                ASC.ZERO...ASC.EIGHT => {
                                    if (bit_position >= 64) {
                                        return LexerError.PARSE_INTEGER_TOO_LARGE;
                                    } else if (bit_position == 63) {
                                        if (data_value & 0xC000000000000000 != 0) {
                                            return LexerError.PARSE_INTEGER_TOO_LARGE;
                                        }
                                        data_value = (data_value << 2) | (next_char - ASC.ZERO);
                                    } else {
                                        data_value |= (next_char - ASC.ZERO) << (61 - bit_position);
                                        bit_position += 3;
                                    }
                                },
                                else => {
                                    if (bit_position == 0) {
                                        return LexerError.PARSE_INTEGER_NO_DIGITS;
                                    }
                                    self.rollback_pos(next_char);
                                    token_builder.set_data(data_value, 1);
                                    return self.finish_token(TKIND.LIT_INT, token_builder);
                                },
                            }
                        }
                        if (bit_position == 0) {
                            return LexerError.PARSE_INTEGER_NO_DIGITS;
                        }
                        token_builder.set_data(data_value, 1);
                        return self.finish_token(TKIND.LIT_INT, token_builder);
                    },
                    ASC.x => {
                        var data_value: u64 = 0;
                        var bit_position: u32 = 0;
                        while (self.curr_pos < self.source.len) {
                            const next_char = try self.read_next_utf8_char();
                            switch (next_char) {
                                ASC.UNDERSCORE => {},
                                ASC.ZERO...ASC.NINE => {
                                    if (bit_position >= 64) {
                                        return LexerError.PARSE_INTEGER_TOO_LARGE;
                                    }
                                    data_value |= (next_char - ASC.ZERO) << (60 - bit_position);
                                    bit_position += 4;
                                },
                                ASC.UPPER_A...ASC.UPPER_F => {
                                    if (bit_position >= 64) {
                                        return LexerError.PARSE_INTEGER_TOO_LARGE;
                                    }
                                    data_value |= ((next_char - ASC.UPPER_A) + 10) << (60 - bit_position);
                                    bit_position += 4;
                                },
                                ASC.LOWER_A...ASC.LOWER_F => {
                                    if (bit_position >= 64) {
                                        return LexerError.PARSE_INTEGER_TOO_LARGE;
                                    }
                                    data_value |= ((next_char - ASC.LOWER_A) + 10) << (60 - bit_position);
                                    bit_position += 4;
                                },
                                else => {
                                    if (bit_position == 0) {
                                        return LexerError.PARSE_INTEGER_NO_DIGITS;
                                    }
                                    self.rollback_pos(next_char);
                                    token_builder.set_data(data_value, 1);
                                    return self.finish_token(TKIND.LIT_INT, token_builder);
                                },
                            }
                        }
                        if (bit_position == 0) {
                            return LexerError.PARSE_INTEGER_NO_DIGITS;
                        }
                        token_builder.set_data(data_value, 1);
                        return self.finish_token(TKIND.LIT_INT, token_builder);
                    },
                    ASC.DOT => {
                        is_float = true;
                    },
                    ASC.ZERO...ASC.NINE => {},
                    else => {
                        self.rollback_pos(second_char);
                        return self.finish_token(TKIND.BIT_NOT, token_builder);
                    },
                }
            }
            switch (second_char) {
                ASC.x => return self.finish_token(TKIND.BIT_NOT_ASSIGN, token_builder),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.BIT_NOT, token_builder);
                },
            }
        },
        else => return self.finish_token(TKIND.ILLEGAL, token_builder),
    }
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

inline fn rollback_pos(self: *Self, code: u32) void {
    assert(self.curr_pos > 0);
    assert(self.curr_pos >= self.next_or_prev_pos);
    const tmp_pos = self.next_or_prev_pos;
    const tmp_col = self.next_or_prev_col;
    const tmp_row = self.next_or_prev_row;
    self.next_or_prev_pos = self.curr_pos;
    self.next_or_prev_col = self.curr_col;
    self.next_or_prev_row = self.curr_row;
    self.curr_pos = tmp_pos;
    self.curr_col = tmp_col;
    self.curr_row = tmp_row;
    self.curr_processed = true;
    self.curr_code = code;
    return;
}

inline fn is_whitespace(code: u32) bool {
    return (code <= ASC.SPACE) or (code == ASC.DEL);
}

inline fn is_valid_ident_char_first(code: u8) bool {
    return (code == ASC.UNDERSCORE) or ((code >= ASC.LOWER_A) and (code <= ASC.LOWER_Z)) or ((code >= ASC.UPPER_A) and (code <= ASC.LOWER_Z));
}

inline fn is_valid_ident_char_rest(code: u8) bool {
    return (code == ASC.UNDERSCORE) or ((code >= ASC.LOWER_A) and (code <= ASC.LOWER_Z)) or ((code >= ASC.UPPER_A) and (code <= ASC.LOWER_Z)) or ((code >= ASC.ZERO) and (code <= ASC.NINE));
}

inline fn scan_over_utf8_until_next_char_match(self: *Self, match_code: u32, include_match_in_token: bool) LexerError!bool {
    var found = false;
    while (self.curr_pos < self.source.len and !found) {
        const next_code = try self.read_next_utf8_char();
        found = next_code == match_code;
    }
    if (!include_match_in_token and found) {
        self.rollback_pos(match_code);
    }
    return found;
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
        else => return LexerError.UTF8_INVALID_FIRST_BYTE,
    };
    if (self.curr_pos + utf8_len > self.source.len) {
        return LexerError.UTF8_BUFFER_ENDED_EARLY;
    }
    switch (utf8_len) {
        1 => {
            if (self.source[self.curr_pos] == ASC.NEWLINE) {
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
    UTF8_INVALID_FIRST_BYTE,
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
