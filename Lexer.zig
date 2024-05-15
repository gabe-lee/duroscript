const assert = @import("std").debug.assert;
const Token = @import("./Token.zig");
const TKIND = Token.KIND;
const ASC = @import("./Ascii.zig");

const Self = @This();

source: []const u8,
curr_pos: u32,
curr_col: u32,
curr_row: u32,
complete: bool,
curr_processed: bool,
curr_code: u32,
next_or_prev_pos: u32,
next_or_prev_col: u32,
next_or_prev_row: u32,

pub fn new(source: []u8) LexerError!Self {
    return Self{
        .source = source,
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
    var token_start_pos = self.curr_pos;
    var token_start_col = self.curr_col;
    if (self.curr_pos == self.source.len) {
        self.complete = true;
        return self.finish_token(TKIND.EOF, token_start_pos, token_start_col);
    }
    var first_char = try self.read_next_utf8_char();
    while (self.is_whitespace(first_char)) {
        token_start_pos = self.curr_pos;
        token_start_col = self.curr_col;
        first_char = try self.read_next_utf8_char();
    }
    switch (first_char) {
        ASC.COLON => return self.finish_token(TKIND.COLON, token_start_pos, token_start_col),
        ASC.COMMA => return self.finish_token(TKIND.COMMA, token_start_pos, token_start_col),
        ASC.SEMICOL => return self.finish_token(TKIND.SEMICOL, token_start_pos, token_start_col),
        ASC.L_PAREN => return self.finish_token(TKIND.L_PAREN, token_start_pos, token_start_col),
        ASC.R_PAREN => return self.finish_token(TKIND.R_PAREN, token_start_pos, token_start_col),
        ASC.L_CURLY => return self.finish_token(TKIND.L_CURLY, token_start_pos, token_start_col),
        ASC.R_CURLY => return self.finish_token(TKIND.R_CURLY, token_start_pos, token_start_col),
        ASC.L_SQUARE => return self.finish_token(TKIND.L_SQUARE, token_start_pos, token_start_col),
        ASC.R_SQUARE => return self.finish_token(TKIND.R_SQUARE, token_start_pos, token_start_col),
        ASC.DOT => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.DOT => return self.finish_token(TKIND.CONCAT, token_start_pos, token_start_col),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.DOT, token_start_pos, token_start_col);
                },
            }
        },
        ASC.EQUALS => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.EQUALS, token_start_pos, token_start_col),
                ASC.MORE_THAN => return self.finish_token(TKIND.FAT_ARROW, token_start_pos, token_start_col),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.ASSIGN, token_start_pos, token_start_col);
                },
            }
        },
        ASC.LESS_THAN => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.LESS_THAN_EQUAL, token_start_pos, token_start_col),
                ASC.LESS_THAN => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.SHIFT_L_ASSIGN, token_start_pos, token_start_col),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.SHIFT_L, token_start_pos, token_start_col);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.LESS_THAN, token_start_pos, token_start_col);
                },
            }
        },
        ASC.MORE_THAN => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.MORE_THAN_EQUAL, token_start_pos, token_start_col),
                ASC.MORE_THAN => {
                    const third_char = try self.read_next_utf8_char();
                    switch (third_char) {
                        ASC.EQUALS => return self.finish_token(TKIND.SHIFT_R_ASSIGN, token_start_pos, token_start_col),
                        else => {
                            self.rollback_pos(third_char);
                            return self.finish_token(TKIND.SHIFT_R, token_start_pos, token_start_col);
                        },
                    }
                },
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.MORE_THAN, token_start_pos, token_start_col);
                },
            }
        },
        ASC.EXCLAIM => {
            const second_char = try self.read_next_utf8_char();
            switch (second_char) {
                ASC.EQUALS => return self.finish_token(TKIND.NOT_EQUAL, token_start_pos, token_start_col),
                else => {
                    self.rollback_pos(second_char);
                    return self.finish_token(TKIND.LOGIC_NOT, token_start_pos, token_start_col);
                },
            }
        },
        else => return self.finish_token(TKIND.ILLEGAL, token_start_pos, token_start_col),
    }
}

inline fn finish_token(self: *Self, kind: Token.TokenKind, start_pos: u32, start_col: u32) Token {
    return Token{
        .kind = kind,
        .byte_start = start_pos,
        .byte_end = self.curr_pos,
        .row = self.curr_row,
        .col_start = start_col,
        .col_end = self.curr_col,
    };
}

inline fn rollback_pos(self: *Self, code: u32) void {
    assert(self.curr_pos > 0);
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
    return (code <= 0x20) or (code == 127);
}

inline fn is_valid_ident_char_first(code: u8) bool {
    return (code == 0x5F) or ((code >= 0x61) and (code <= 0x7A)) or ((code >= 0x41) and (code <= 0x5A));
}

inline fn is_valid_ident_char_rest(code: u8) bool {
    return (code == 0x5F) or ((code >= 0x61) and (code <= 0x7A)) or ((code >= 0x41) and (code <= 0x5A)) or ((code >= 0x30) and (code <= 0x39));
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
        else => return LexerError.INVALID_FIRST_BYTE,
    };
    if (self.curr_pos + utf8_len > self.source.len) {
        return LexerError.BUFFER_ENDED_EARLY;
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
            if (self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) return LexerError.INVALID_CONTINUE_BYTE;
            const code: u32 = ((self.source[self.curr_pos] & 0b00011111) << 6) | (self.source[self.curr_pos + 1] & 0b00111111);
            if (code < 0x80) return LexerError.OVERLONG_ENCODING;
            self.curr_col += 1;
            self.curr_pos += 2;
            return code;
        },
        3 => {
            if ((self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 2] & 0b11000000 != 0b10000000)) {
                return LexerError.INVALID_CONTINUE_BYTE;
            }
            const code: u32 = ((self.source[self.curr_pos] & 0b00001111) << 12) | ((self.source[self.curr_pos + 1] & 0b00111111) << 6) | (self.source[self.curr_pos + 2] & 0b00111111);
            if ((code >= 0xD800) || (code <= 0xDFFF)) return LexerError.INVALID_CODEPOINT;
            if (code < 0x800) return LexerError.OVERLONG_ENCODING;
            self.curr_col += 1;
            self.curr_pos += 3;
            return code;
        },
        4 => {
            if ((self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 2] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 3] & 0b11000000 != 0b10000000)) {
                return LexerError.INVALID_CONTINUE_BYTE;
            }
            const code: u32 = ((self.source[self.curr_pos] & 0b00000111) << 18) | ((self.source[self.curr_pos + 1] & 0b00111111) << 12) | ((self.source[self.curr_pos + 2] & 0b00111111) << 6) | (self.source[self.curr_pos + 3] & 0b00111111);
            if (code >= 0x110000) return LexerError.INVALID_CODEPOINT;
            if (code < 0x10000) return LexerError.OVERLONG_ENCODING;
            self.curr_col += 1;
            self.curr_pos += 4;
            return code;
        },
        else => unreachable,
    }
}

const LexerError = error{ INVALID_FIRST_BYTE, BUFFER_ENDED_EARLY, OVERLONG_ENCODING, INVALID_CONTINUE_BYTE, INVALID_CODEPOINT };

pub const NEWLINE = 0x0A;
