const assert = @import("std").debug.assert;
const Token = @import("./Token.zig");
const TKIND = Token.KIND;
const TWARN = Token.WARN;
// const ASC = @import("./ByteRemap.zig").ASC;
const ASC = @import("./constants.zig").ASCII;
const F64 = @import("./constants.zig").F64;
const POWER_10_TABLE = @import("./constants.zig").POWER_10_TABLE;
const Float = @import("./Float.zig");
const SlowParseBuffer = Float.SlowParseBuffer;

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
last_was_newline: bool,

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
        .last_was_newline = false,
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
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.R_SQUARE => return self.finish_token(TKIND.SLICE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.L_SQUARE, token_builder);
        },
        ASC.R_SQUARE => return self.finish_token(TKIND.R_SQUARE, token_builder),
        ASC.QUESTION => return self.finish_token(TKIND.MAYBE, token_builder),
        ASC.PERIOD => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.PERIOD => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.PERIOD => return self.finish_token(TKIND.RANGE_INCLUDE_BOTH, token_builder),
                                ASC.PIPE => return self.finish_token(TKIND.RANGE_EXCLUDE_END, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_OPERATOR, token_builder);
                    },
                    ASC.AT_SIGN => return self.finish_token(TKIND.DEREREFENCE, token_builder),
                    ASC.QUESTION => return self.finish_token(TKIND.ACCESS_MAYBE_NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ACCESS, token_builder);
        },
        ASC.EQUALS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.EQUALS, token_builder),
                    ASC.MORE_THAN => return self.finish_token(TKIND.FAT_ARROW, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ASSIGN, token_builder);
        },
        ASC.LESS_THAN => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.LESS_THAN_EQUAL, token_builder),
                    ASC.LESS_THAN => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.SHIFT_L_ASSIGN, token_builder),
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
        ASC.MORE_THAN => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.MORE_THAN_EQUAL, token_builder),
                    ASC.LESS_THAN => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.SHIFT_R_ASSIGN, token_builder),
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
        ASC.EXCLAIM => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.NOT_EQUAL, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.LOGIC_NOT, token_builder);
        },
        ASC.PLUS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.ADD_ASSIGN, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ADD, token_builder);
        },
        ASC.MINUS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.SUB_ASSIGN, token_builder),
                    ASC._0...ASC._9 => self.handle_number_literal(token_builder, true, byte_2),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.SUB, token_builder);
        },
        ASC.ASTERISK => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.MULT_ASSIGN, token_builder),
                    ASC.ASTERISK => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.POWER_ASSIGN, token_builder),
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
        ASC.F_SLASH => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.DIV_ASSIGN, token_builder),
                    ASC.F_SLASH => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.ROOT_ASSIGN, token_builder),
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
        ASC.PERCENT => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.MODULO_ASSIGN, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.MODULO, token_builder);
        },
        ASC.AMPER => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_AND_ASSIGN, token_builder),
                    ASC.AMPER => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.LOGIC_AND_ASSIGN, token_builder),
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
        ASC.PIPE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_OR_ASSIGN, token_builder),
                    ASC.PIPE => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.LOGIC_OR_ASSIGN, token_builder),
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
        ASC.CARET => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_XOR_ASSIGN, token_builder),
                    ASC.CARET => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.LOGIC_XOR_ASSIGN, token_builder),
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
        ASC.TILDE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_NOT_ASSIGN, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_NOT, token_builder);
        },
        ASC._0...ASC._9 => self.handle_number_literal(token_builder, false, byte_1),
        ASC.A...ASC.UNDERSCORE => {
            var ident_block = BLANK_IDENT;
            var idx = 0;
            var offset: u8 = 56;
            var len: u8 = 1;
            var idx_add: u8 = 1;
            ident_block[idx] |= byte_1 << offset;
            offset -= 8;
            while (self.more_bytes_in_source()) {
                const byte_x = self.read_next_byte();
                switch (byte_x) {
                    ASC._0...ASC.UNDERSCORE => {
                        if (len >= 64) {
                            while (self.more_bytes_in_source()) {
                                const byte_over = self.read_next_byte();
                                switch (byte_over) {
                                    ASC._0...ASC.UNDERSCORE => {},
                                    else => {
                                        self.rollback_one_byte();
                                        return self.finish_token(TKIND.ILLEGAL_IDENT_TOO_LONG, token_builder);
                                    },
                                }
                            }
                            return self.finish_token(TKIND.ILLEGAL_IDENT_TOO_LONG, token_builder);
                        }
                        ident_block[idx] |= byte_x << offset;
                        offset = ((offset | 64) - 8) & 63;
                        len += 1;
                        idx_add += 1;
                        idx += idx_add >> 3;
                        idx_add &= 0b0111;
                    },
                    else => {
                        self.rollback_one_byte();
                        if (len <= 8) {
                            const possible_keywords = Token.KEYWORD_U64_SLICES_BY_LEN[len];
                            const possible_tokens = Token.KEYWORD_TOKEN_SLICES_BY_LEN[len];
                            for (possible_keywords, possible_tokens) |kw, tok| {
                                if (kw == ident_block[0]) return self.finish_token(tok, token_builder);
                            }
                        }
                        //FIXME save actual keyword to ROM and give token pointer to it
                        return self.finish_token(TKIND.IDENT, token_builder);
                    },
                }
            }
            if (len <= 8) {
                const possible_keywords = Token.KEYWORD_U64_SLICES_BY_LEN[len];
                const possible_tokens = Token.KEYWORD_TOKEN_SLICES_BY_LEN[len];
                for (possible_keywords, possible_tokens) |kw, tok| {
                    if (kw == ident_block[0]) return self.finish_token(tok, token_builder);
                }
            }
            //FIXME save actual keyword to ROM and give token pointer to it
            return self.finish_token(TKIND.IDENT, token_builder);
        },
        ASC._0...ASC.COMMA => return self.finish_token(TKIND.ILLEGAL_OPERATOR, token_builder),
        else => return self.finish_token(TKIND.ILLEGAL_BYTE, token_builder),
    }
}

fn collect_illegal_alphanumeric_string(self: *Self, token_builder: TokenBuilder, warn: TWARN) Token {
    while (self.more_bytes_in_source()) {
        const next_byte = self.read_next_byte();
        switch (next_byte) {
            ASC._0...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE => {},
            else => {
                self.rollback_one_byte();
                break;
            },
        }
    }
    return self.finish_token(TKIND.ILLEGAL, warn, token_builder);
}

fn collect_illegal_alphanumeric_string_plus_dot(self: *Self, token_builder: TokenBuilder, warn: TWARN) Token {
    while (self.more_bytes_in_source()) {
        const next_byte = self.read_next_byte();
        switch (next_byte) {
            ASC._0...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE, ASC.PERIOD => {},
            else => {
                self.rollback_one_byte();
                break;
            },
        }
    }
    return self.finish_token(TKIND.ILLEGAL, warn, token_builder);
}

inline fn more_bytes_in_source(self: *Self) bool {
    return self.more_bytes_in_source();
}

fn handle_number_literal(self: *Self, token_builder: TokenBuilder, negative: bool, byte_1: u8) Token {
    assert(byte_1 < 10);
    if (self.curr_pos == self.source.len) return self.finish_integer_literal_token(token_builder, byte_1, negative);
    const byte_2 = self.read_next_byte();
    if (byte_1 == ASC._0) {
        var data_value: u64 = 0;
        var bit_position: u32 = 0;
        var leading_zeroes = 0;
        switch (byte_2) {
            ASC.b => {
                while (self.more_bytes_in_source()) {
                    const leading_zero = self.read_next_byte();
                    if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
                        self.rollback_one_byte();
                        break;
                    } else if (leading_zero == ASC._0) leading_zeroes += 1;
                }
                while (self.more_bytes_in_source()) {
                    const byte_x = self.read_next_byte();
                    switch (byte_x) {
                        ASC._0...ASC._1 => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                            }
                            data_value |= (byte_x - ASC._0) << (63 - bit_position);
                            bit_position += 1;
                        },
                        ASC.UNDERSCORE => {},
                        ASC._2...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_ALPHANUM_IN_BINARY),
                        else => {
                            self.rollback_one_byte();
                            break;
                        },
                    }
                }
                data_value >>= (64 - bit_position);
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS, token_builder);
                }
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ASC.o => {
                while (self.more_bytes_in_source()) {
                    const leading_zero = self.read_next_byte();
                    if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
                        self.rollback_one_byte();
                        break;
                    } else if (leading_zero == ASC._0) leading_zeroes += 1;
                }
                while (self.more_bytes_in_source()) {
                    const byte_x = self.read_next_byte();
                    switch (byte_x) {
                        ASC._0...ASC._7 => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                            } else if (bit_position == 63) {
                                if (data_value & 0xC000000000000000 != 0) {
                                    return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                                }
                                data_value = (data_value << 2) | (byte_x - ASC._0);
                            } else {
                                data_value |= (byte_x - ASC._0) << (61 - bit_position);
                                bit_position += 3;
                            }
                        },
                        ASC.UNDERSCORE => {},
                        ASC._8...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_ALPHANUM_IN_OCTAL),
                        else => {
                            self.rollback_one_byte();
                            break;
                        },
                    }
                }
                data_value >>= (64 - bit_position);
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS, token_builder);
                }
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ASC.x => {
                while (self.more_bytes_in_source()) {
                    const leading_zero = self.read_next_byte();
                    if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
                        self.rollback_one_byte();
                        break;
                    } else if (leading_zero == ASC._0) leading_zeroes += 1;
                }
                while (self.more_bytes_in_source()) {
                    const byte_x = self.read_next_byte();
                    switch (byte_x) {
                        ASC._0...ASC._9 => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                            }
                            data_value |= (byte_x - ASC._0) << (60 - bit_position);
                            bit_position += 4;
                        },
                        ASC.A...ASC.F => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                            }
                            data_value |= (byte_x - ASC.A) << (60 - bit_position);
                            bit_position += 4;
                        },
                        ASC.a...ASC.f => {
                            if (bit_position >= 64) {
                                return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                            }
                            data_value |= (byte_x - ASC.a) << (60 - bit_position);
                            bit_position += 4;
                        },
                        ASC.UNDERSCORE => {},
                        ASC.G...ASC.Z, ASC.g...ASC.z, ASC.PERIOD => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_ALPHANUM_IN_HEX),
                        else => {
                            self.rollback_one_byte();
                            break;
                        },
                    }
                }
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS, token_builder);
                }
                data_value >>= (64 - bit_position);
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ASC._0...ASC._9, ASC.PERIOD, ASC.UNDERSCORE, ASC.e, ASC.E => {
                self.rollback_one_byte();
            },
            else => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TKIND.ILLEGAL_ALPHANUM_IN_DECIMAL),
        }
    }
    var slow_parse_buffer: SlowParseBuffer = [1]u8{0} ** 26;
    var slow_parse_idx: usize = 0;
    var sig_value: u64 = 0;
    var sig_digits: u64 = 0;
    var implicit_exp: i64 = 0;
    var is_float = false;
    var flt_exp_sub: i16 = 0;
    var has_exp = false;
    var neg_exp = false;
    var sig_int_found = byte_1 != ASC._0;
    if (sig_int_found) {
        slow_parse_buffer[slow_parse_idx] = byte_1;
        slow_parse_idx += 1;
        sig_value = byte_1;
        sig_digits += 1;
    }
    switch (byte_2) {
        ASC._0...ASC._9 => {
            sig_int_found = sig_int_found or (byte_2 != ASC._0);
            if (sig_int_found) {
                slow_parse_buffer[slow_parse_idx] = byte_2;
                slow_parse_idx += 1;
                sig_value = (sig_value *% 10) + @as(u64, byte_2 - ASC._0);
                sig_digits += 1;
            }
        },
        ASC.PERIOD => {
            slow_parse_buffer[slow_parse_idx] = byte_2;
            slow_parse_idx += 1;
            is_float = true;
            flt_exp_sub = 1;
        },
        ASC.e, ASC.E => {
            slow_parse_buffer[slow_parse_idx] = ASC.e;
            slow_parse_idx += 1;
            has_exp = true;
            if (self.more_bytes_in_source()) {
                const first_exp_byte = self.read_next_byte();
                switch (first_exp_byte) {
                    ASC.MINUS => {
                        neg_exp = true;
                    },
                    ASC.PLUS => {},
                    else => self.rollback_one_byte(),
                }
            }
        },
        else => {},
    }
    while (!has_exp and self.more_bytes_in_source()) {
        const byte_x = self.read_next_byte();
        switch (byte_x) {
            ASC._0...ASC._9 => {
                sig_int_found = sig_int_found or (byte_x != ASC._0);
                if (sig_int_found) {
                    if (is_float and byte_x == ASC._0) {
                        var trailing_zeroes: i16 = 1;
                        while (self.more_bytes_in_source()) {
                            const byte_xx = self.read_next_byte();
                            switch (byte_xx) {
                                ASC._0 => {
                                    trailing_zeroes += 1;
                                },
                                ASC._1...ASC._9 => {
                                    sig_value *%= POWER_10_TABLE[trailing_zeroes];
                                    sig_digits += trailing_zeroes;
                                    implicit_exp -= trailing_zeroes;
                                    if (sig_digits > 19 or (sig_digits == 19 and ((byte_x <= ASC._5 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_0_THRU_5) or (byte_x >= ASC._6 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_6_THRU_9)))) {
                                        return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                                    }
                                    slow_parse_idx += trailing_zeroes;
                                    slow_parse_buffer[slow_parse_idx] = byte_xx;
                                    slow_parse_idx += 1;
                                    sig_digits += 1;
                                    implicit_exp -= 1;
                                    sig_value = (sig_value *% 10) + @as(u64, byte_xx - ASC._0);
                                    break;
                                },
                                else => {
                                    self.rollback_one_byte();
                                    break;
                                },
                            }
                        }
                    } else {
                        if (sig_digits > 19 or (sig_digits == 19 and ((byte_x <= ASC._5 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_0_THRU_5) or (byte_x >= ASC._6 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_6_THRU_9)))) {
                            return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS);
                        }
                        slow_parse_buffer[slow_parse_idx] = byte_x;
                        slow_parse_idx += 1;
                        sig_value = (sig_value *% 10) + @as(u64, byte_x - ASC._0);
                        sig_digits += 1;
                        implicit_exp -= flt_exp_sub;
                    }
                }
            },
            ASC.PERIOD => {
                if (is_float) {
                    return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_TOO_MANY_DOTS);
                }
                slow_parse_buffer[slow_parse_idx] = byte_x;
                slow_parse_idx += 1;
                is_float = true;
            },
            ASC.E, ASC.e => {
                if (has_exp) {
                    return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_TOO_MANY_EXPONENTS);
                }
                slow_parse_buffer[slow_parse_idx] = ASC.e;
                slow_parse_idx += 1;
                has_exp = true;
                if (self.more_bytes_in_source()) {
                    const first_exp_byte = self.read_next_byte();
                    switch (first_exp_byte) {
                        ASC.MINUS => {
                            neg_exp = true;
                            slow_parse_buffer[slow_parse_idx] = ASC.MINUS;
                            slow_parse_idx += 1;
                        },
                        ASC.PLUS => {},
                        else => self.rollback_one_byte(),
                    }
                }
            },
            ASC.UNDERSCORE => {},
            ASC.A...ASC.Z, ASC.a...ASC.z => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_ALPHANUM_IN_DECIMAL),
            else => {
                self.rollback_one_byte();
                break;
            },
        }
    }
    var explicit_exp: i64 = 0;
    var exp_sig_digits: u64 = 0;
    var exp_sig_int_found = false;
    while (has_exp and self.more_bytes_in_source()) {
        const byte_x = self.read_next_byte();
        switch (byte_x) {
            ASC._0...ASC._9 => {
                exp_sig_int_found = exp_sig_int_found or (byte_x != ASC._0);
                if (exp_sig_int_found) {
                    if (exp_sig_digits == 3) return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_EXPONENT_TOO_MANY_DIGITS);
                    slow_parse_buffer[slow_parse_idx] = byte_x;
                    slow_parse_idx += 1;
                    explicit_exp = (explicit_exp *% 10) + @as(u64, byte_x - ASC._0);
                    exp_sig_digits += 1;
                }
            },
            ASC.PERIOD => self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_PERIOD_IN_EXPONENT),
            ASC.E, ASC.e => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_NUMBER_TOO_MANY_EXPONENTS),
            ASC.UNDERSCORE => {},
            ASC.A...ASC.Z, ASC.a...ASC.z => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_ALPHANUM_IN_DECIMAL),
            else => {
                self.rollback_one_byte();
                break;
            },
        }
    }
    if (!is_float) {
        const exp_mag = @abs(explicit_exp);
        if (explicit_exp > 0) {
            if (explicit_exp > 19 or sig_value > MAX_INT_VALS_FOR_POSITIVE_EXP[exp_mag]) return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS, token_builder);
            sig_value *= POWER_10_TABLE[exp_mag];
        } else if (explicit_exp < 0) {
            if (explicit_exp < 19 or sig_value % POWER_10_TABLE[exp_mag] != 0) return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_INTEGER_LITERAL_LOSS_OF_DATA, token_builder);
            sig_value /= POWER_10_TABLE[exp_mag];
        }
        if (negative) {
            if (sig_value > LARGEST_NEG_SIG_VALUE_FOR_I64) return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_INTEGER_LITERAL_NEG_OVERFLOWS_I64, token_builder);
            const ival: i64 = @as(i64, @bitCast(sig_value)) * (-@intFromBool(sig_value != LARGEST_NEG_SIG_VALUE_FOR_I64));
            sig_value = @bitCast(ival);
        }
        token_builder.set_data(sig_value, 1);
        return self.finish_token(TKIND.LIT_INTEGER, TWARN.NONE, token_builder);
    } else {
        const final_exp = implicit_exp + explicit_exp;
        if (sig_digits > F64.MAX_SIG_DIGITS) {
            token_builder.set_data(0, sig_digits);
            return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_FLOAT_TOO_MANY_SIG_DIGITS, token_builder);
        }
        if (final_exp > F64.MAX_EXPONENT or (final_exp == F64.MAX_EXPONENT and sig_value > F64.MAX_SIG_DECIMAL_AT_MAX_EXP)) return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_FLOAT_LITERAL_TOO_LARGE, token_builder);
        if (final_exp < F64.MIN_EXPONENT or (final_exp == F64.MIN_EXPONENT and sig_value < F64.MIN_SIG_DECIMAL_AT_MIN_EXP)) return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_FLOAT_LITERAL_TOO_SMALL, token_builder);
        return Float.parse_float_from_decimal_parts(sig_value, final_exp, negative, slow_parse_buffer, slow_parse_idx);
    }
}

inline fn finish_token(self: *Self, kind: TKIND, warn: TWARN, token_builder: TokenBuilder) Token {
    return Token{
        .kind = kind,
        .source_key = token_builder.source_key,
        .row_start = token_builder.row,
        .row_end = self.curr_row,
        .col_start = token_builder.col,
        .col_end = self.curr_col,
        .data_val_or_ptr = token_builder.data_val_or_ptr,
        .data_exp_or_len = token_builder.data_len,
        .warning = warn,
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
    return (byte >= ASC.WHITESPACE_MIN) and (byte <= ASC.WHITESPACE_MAX);
}

// inline fn scan_over_utf8_until_next_char_match(self: *Self, match_code: u32, include_match_in_token: bool) LexerError!bool {
//     var found = false;
//     while (self.more_bytes_in_source() and !found) {
//         const next_code = try self.read_next_utf8_char();
//         found = next_code == match_code;
//     }
//     if (!include_match_in_token and found) {
//         self.rollback_pos(match_code);
//     }
//     return found;
// }

inline fn read_next_byte(self: *Self) u8 {
    assert(self.more_bytes_in_source());
    const val = self.source[self.curr_pos];
    self.next_or_prev_pos = self.curr_pos;
    self.next_or_prev_col = self.curr_col;
    self.next_or_prev_row = self.curr_row;
    self.curr_pos += 1;
    self.curr_col += 1;
    if (self.last_was_newline) {
        self.curr_row += 1;
        self.curr_col = 0;
        self.last_was_newline = false;
    }
    self.last_was_newline = val == ASC.NEWLINE;
    return val;
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
    assert(self.more_bytes_in_source());
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
            if (code < 0x80) return LexerError.UTF8_OVERLONG_ASCODING;
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
            if (code < 0x800) return LexerError.UTF8_OVERLONG_ASCODING;
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
            if (code < 0x10000) return LexerError.UTF8_OVERLONG_ASCODING;
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
    UTF8_OVERLONG_ASCODING,
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
    data_exp_or_len: u32,

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

    inline fn set_data(self: *TokenBuilder, val_or_ptr: u64, exp_or_len: u32) void {
        self.data_val_or_ptr = val_or_ptr;
        self.data_exp_or_len = exp_or_len;
    }
};

const MAX_POSITIVE_I64 = std.math.maxInt(isize);
const MAX_NEGATIVE_I64 = MAX_POSITIVE_I64 + 1;

const IdentBlock = [8]u64;
const BLANK_IDENT: IdentBlock = IdentBlock{ 0, 0, 0, 0, 0, 0, 0, 0 };

const LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_6_THRU_9: u64 = 1844674407370955160;
const LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_0_THRU_5: u64 = 1844674407370955161;

const MAX_INT_VALS_FOR_POSITIVE_EXP = [20]u64{
    std.math.maxInt(u64) / POWER_10_TABLE[0],
    std.math.maxInt(u64) / POWER_10_TABLE[1],
    std.math.maxInt(u64) / POWER_10_TABLE[2],
    std.math.maxInt(u64) / POWER_10_TABLE[3],
    std.math.maxInt(u64) / POWER_10_TABLE[4],
    std.math.maxInt(u64) / POWER_10_TABLE[5],
    std.math.maxInt(u64) / POWER_10_TABLE[6],
    std.math.maxInt(u64) / POWER_10_TABLE[7],
    std.math.maxInt(u64) / POWER_10_TABLE[8],
    std.math.maxInt(u64) / POWER_10_TABLE[9],
    std.math.maxInt(u64) / POWER_10_TABLE[10],
    std.math.maxInt(u64) / POWER_10_TABLE[11],
    std.math.maxInt(u64) / POWER_10_TABLE[12],
    std.math.maxInt(u64) / POWER_10_TABLE[13],
    std.math.maxInt(u64) / POWER_10_TABLE[14],
    std.math.maxInt(u64) / POWER_10_TABLE[15],
    std.math.maxInt(u64) / POWER_10_TABLE[16],
    std.math.maxInt(u64) / POWER_10_TABLE[17],
    std.math.maxInt(u64) / POWER_10_TABLE[18],
    std.math.maxInt(u64) / POWER_10_TABLE[19],
};

pub const NUM_SIG_NEG_FLAG: u32 = 0b10000000_00000000_00000000_00000000;
pub const LARGEST_NEG_SIG_VALUE_FOR_I64: u64 = 9223372036854775808;
