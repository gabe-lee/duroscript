const assert = @import("std").debug.assert;
const Token = @import("./Token.zig");
const TKIND = Token.KIND;
const TWARN = Token.WARN;
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

pub fn next_token(self: *Self) Token {
    assert(!self.complete);
    var token_builder = TokenBuilder.new(self.source_key, self.curr_col, self.curr_row);
    if (self.curr_pos >= self.source.len) {
        self.complete = true;
        return self.finish_token(TKIND.EOF, TWARN.NONE, token_builder);
    }
    var byte_1 = self.read_next_byte();
    while (self.more_bytes_in_source()) {
        switch (byte_1) {
            ASC.SPACE, ASC.H_TAB => {
                byte_1 = self.read_next_byte();
            },
            ASC.NEWLINE => {
                self.curr_col = 0;
                self.curr_row += 1;
                byte_1 = self.read_next_byte();
            },
            ASC.HASH => {
                token_builder.set_start(self.curr_col, self.curr_row);
                while (self.more_bytes_in_source()) {
                    byte_1 = self.read_next_byte();
                    switch (byte_1) {
                        ASC.NEWLINE => {
                            //TODO output comments to separate list ?
                            self.curr_col = 0;
                            self.curr_row += 1;
                            break;
                        },
                        else => {},
                    }
                }
                //TODO output comments to separate list ?
            },
            else => {},
        }
    }
    if (!self.more_bytes_in_source()) {
        self.complete = true;
        return self.finish_token(TKIND.EOF, TWARN.NONE, token_builder);
    }
    token_builder.set_start(self.curr_col, self.curr_row);
    switch (byte_1) {
        ASC.COLON => return self.finish_token(TKIND.COLON, TWARN.NONE, token_builder),
        ASC.AT_SIGN => return self.finish_token(TKIND.REFERENCE, TWARN.NONE, token_builder),
        ASC.DOLLAR => return self.finish_token(TKIND.SUBSTITUTE, TWARN.NONE, token_builder),
        ASC.COMMA => return self.finish_token(TKIND.COMMA, TWARN.NONE, token_builder),
        ASC.SEMICOL => return self.finish_token(TKIND.SEMICOL, TWARN.NONE, token_builder),
        ASC.L_PAREN => return self.finish_token(TKIND.L_PAREN, TWARN.NONE, token_builder),
        ASC.R_PAREN => return self.finish_token(TKIND.R_PAREN, TWARN.NONE, token_builder),
        ASC.L_CURLY => return self.finish_token(TKIND.L_CURLY, TWARN.NONE, token_builder),
        ASC.R_CURLY => return self.finish_token(TKIND.R_CURLY, TWARN.NONE, token_builder),
        ASC.L_SQUARE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.R_SQUARE => return self.finish_token(TKIND.SLICE, TWARN.NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.L_SQUARE, TWARN.NONE, token_builder);
        },
        ASC.R_SQUARE => return self.finish_token(TKIND.R_SQUARE, TWARN.NONE, token_builder),
        ASC.QUESTION => return self.finish_token(TKIND.MAYBE, TWARN.NONE, token_builder),
        ASC.PERIOD => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.PERIOD => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.PERIOD => return self.finish_token(TKIND.RANGE_INCLUDE_BOTH, TWARN.NONE, token_builder),
                                ASC.PIPE => return self.finish_token(TKIND.RANGE_EXCLUDE_END, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_OPERATOR, TWARN.NONE, token_builder);
                    },
                    ASC.AT_SIGN => return self.finish_token(TKIND.DEREREFENCE, TWARN.NONE, token_builder),
                    ASC.QUESTION => return self.finish_token(TKIND.ACCESS_MAYBE_NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ACCESS, TWARN.NONE, token_builder);
        },
        ASC.EQUALS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.EQUALS, TWARN.NONE, token_builder),
                    ASC.MORE_THAN => return self.finish_token(TKIND.FAT_ARROW, TWARN.NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ASSIGN, TWARN.NONE, token_builder);
        },
        ASC.LESS_THAN => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.LESS_THAN_EQUAL, TWARN.NONE, token_builder),
                    ASC.LESS_THAN => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.SHIFT_L_ASSIGN, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.SHIFT_L, TWARN.NONE, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.LESS_THAN, TWARN.NONE, token_builder);
        },
        ASC.MORE_THAN => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.MORE_THAN_EQUAL, TWARN.NONE, token_builder),
                    ASC.LESS_THAN => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.SHIFT_R_ASSIGN, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.SHIFT_R, TWARN.NONE, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.MORE_THAN, TWARN.NONE, token_builder);
        },
        ASC.EXCLAIM => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.NOT_EQUAL, TWARN.NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.LOGIC_NOT, TWARN.NONE, token_builder);
        },
        ASC.PLUS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.ADD_ASSIGN, TWARN.NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.ADD, TWARN.NONE, token_builder);
        },
        ASC.MINUS => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.SUB_ASSIGN, TWARN.NONE, token_builder),
                    ASC._0...ASC._9 => self.handle_number_literal(token_builder, true, byte_2),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.SUB, TWARN.NONE, token_builder);
        },
        ASC.ASTERISK => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.MULT_ASSIGN, TWARN.NONE, token_builder),
                    ASC.ASTERISK => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.POWER_ASSIGN, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.POWER, TWARN.NONE, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.MULT, TWARN.NONE, token_builder);
        },
        ASC.F_SLASH => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.DIV_ASSIGN, TWARN.NONE, token_builder),
                    ASC.F_SLASH => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.ROOT_ASSIGN, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.ROOT, TWARN.NONE, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.DIV, TWARN.NONE, token_builder);
        },
        ASC.PERCENT => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.MODULO_ASSIGN, TWARN.NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.MODULO, TWARN.NONE, token_builder);
        },
        ASC.AMPER => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_AND_ASSIGN, TWARN.NONE, token_builder),
                    ASC.AMPER => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.LOGIC_AND_ASSIGN, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.LOGIC_AND, TWARN.NONE, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_AND, TWARN.NONE, token_builder);
        },
        ASC.PIPE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_OR_ASSIGN, TWARN.NONE, token_builder),
                    ASC.PERIOD => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.PERIOD => {
                                    if (self.more_bytes_in_source()) {
                                        const byte_4 = self.read_next_byte();
                                        switch (byte_4) {
                                            ASC.PIPE => return self.finish_token(TKIND.RANGE_EXCLUDE_BOTH, TWARN.NONE, token_builder),
                                            else => {
                                                self.rollback_one_byte();
                                                return self.finish_token(TKIND.RANGE_EXCLUDE_BEGIN, TWARN.NONE, token_builder);
                                            },
                                        }
                                    }
                                    self.finish_token(TKIND.RANGE_EXCLUDE_BEGIN, TWARN.NONE, token_builder);
                                },
                                else => {
                                    self.rollback_one_byte();
                                    return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_OPERATOR, token_builder);
                                },
                            }
                        }
                        return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_OPERATOR, token_builder);
                    },
                    ASC.PIPE => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.LOGIC_OR_ASSIGN, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.LOGIC_OR, TWARN.NONE, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_OR, TWARN.NONE, token_builder);
        },
        ASC.CARET => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_XOR_ASSIGN, TWARN.NONE, token_builder),
                    ASC.CARET => {
                        if (self.more_bytes_in_source()) {
                            const byte_3 = self.read_next_byte();
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token(TKIND.LOGIC_XOR_ASSIGN, TWARN.NONE, token_builder),
                                else => self.rollback_one_byte(),
                            }
                        }
                        self.finish_token(TKIND.LOGIC_XOR, TWARN.NONE, token_builder);
                    },
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_XOR, TWARN.NONE, token_builder);
        },
        ASC.TILDE => {
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token(TKIND.BIT_NOT_ASSIGN, TWARN.NONE, token_builder),
                    else => self.rollback_one_byte(),
                }
            }
            return self.finish_token(TKIND.BIT_NOT, TWARN.NONE, token_builder);
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
                        return self.finish_token(TKIND.IDENT, TWARN.NONE, token_builder);
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
            return self.finish_token(TKIND.IDENT, TWARN.NONE, token_builder);
        },
        ASC.DOLLAR => {
            //FIXME rethink formatting/substitution string syntax
            if (self.more_bytes_in_source()) {
                const byte_2 = self.read_next_byte();
                switch (byte_2) {
                    ASC.DUBL_QUOTE => {
                        if (self.more_bytes_in_source()) {
                            return self.collect_string(token_builder);
                        }
                        return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_STRING_NO_END_QUOTE, token_builder);
                    },
                    else => {
                        self.rollback_one_byte();
                        return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_OPERATOR, token_builder);
                    },
                }
            }
            return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_OPERATOR, token_builder);
        },
        ASC.EXCLAIM...ASC.TILDE => return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_FIRST_CHAR_FOR_TOKEN, token_builder),
        else => return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_BYTE, token_builder),
    }
}

fn collect_string(self: *Self, token_builder: TokenBuilder, begin_char: u8, end_char: u8, intended_kind: TKIND) Token {
    var kind: TKIND = intended_kind;
    var warn: TWARN = TWARN.NONE;
    var real_len: usize = 1;
    //FIXME Get next ROM ptr and save to const
    const rom_ptr: u64 = 0;
    var last_char: u32 = begin_char;
    while (self.more_bytes_in_source()) {
        const result = self.read_next_utf8_char();
        if (result.warn != TWARN.NONE) {
            warn = result.warn;
            kind = TKIND.ILLEGAL;
        }
        switch (last_char) {
            ASC.B_SLASH => {
                switch (result.code) {
                    ASC.n => {
                        real_len += 1;
                        //FIXME add newline to token ROM
                    },
                    ASC.t => {
                        real_len += 1;
                        //FIXME add h-tab to token ROM
                    },
                    ASC.B_SLASH => {
                        real_len += 1;
                        //FIXME add B_SLASH to token ROM
                    },
                    ASC.DUBL_QUOTE => {
                        real_len += 1;
                        //FIXME add DUBL_QUOTE to token ROM
                    },
                    ASC.BACKTICK => {
                        real_len += 1;
                        //FIXME add BACKTICK to token ROM
                    },
                    ASC.r => {
                        real_len += 1;
                        //FIXME add CR to token ROM
                    },
                    ASC.o => {
                        if (self.source.len - self.curr_pos < 3 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0 or
                            self.source[self.curr_pos + 3] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_OCTAL_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const o1 = self.source[self.curr_pos + 1] - ASC._0;
                        const o2 = self.source[self.curr_pos + 2] - ASC._0;
                        const o3 = self.source[self.curr_pos + 3] - ASC._0;

                        const val: u16 = (o1 << 6) | (o2 << 3) | o3;
                        if (val > ASC.DEL or o1 > 7 or o2 > 7 or o3 > 7) {
                            warn = TWARN.ILLEGAL_STRING_OCTAL_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        self.curr_pos += 3;
                        self.curr_col += 3;
                        real_len += 1;
                        //FIXME add val to token ROM
                    },
                    ASC.x => {
                        if (self.source.len - self.curr_pos < 2 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_HEX_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const h1 = self.source[self.curr_pos + 1] - ASC._0;
                        const h2 = self.source[self.curr_pos + 2] - ASC._0;
                        const val: u16 = (h1 << 4) | h2;
                        if (val > ASC.DEL or h1 > 15 or h2 > 15) {
                            warn = TWARN.ILLEGAL_STRING_HEX_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        self.curr_pos += 2;
                        self.curr_col += 2;
                        real_len += 1;
                        //FIXME add val to token ROM
                    },
                    ASC.u => {
                        if (self.source.len - self.curr_pos < 4 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0 or
                            self.source[self.curr_pos + 3] < ASC._0 or
                            self.source[self.curr_pos + 4] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_SHORT_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const x1 = self.source[self.curr_pos + 1] - ASC._0;
                        const x2 = self.source[self.curr_pos + 2] - ASC._0;
                        const x3 = self.source[self.curr_pos + 3] - ASC._0;
                        const x4 = self.source[self.curr_pos + 4] - ASC._0;
                        if (x1 > 15 or x2 > 15 or x3 > 15 or x4 > 15) {
                            warn = TWARN.ILLEGAL_STRING_SHORT_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        // const code: u32 = (x1 << 12) | (x2 << 8) | (x3 << 4) | x4;
                        // const code_result = encode_valid_codepoint(code);
                        // real_len += code_result.len;
                        //FIXME add code_result.bytes to token ROM
                        self.curr_pos += 4;
                        self.curr_col += 4;
                    },
                    ASC.U => {
                        if (self.source.len - self.curr_pos < 8 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0 or
                            self.source[self.curr_pos + 3] < ASC._0 or
                            self.source[self.curr_pos + 4] < ASC._0 or
                            self.source[self.curr_pos + 5] < ASC._0 or
                            self.source[self.curr_pos + 6] < ASC._0 or
                            self.source[self.curr_pos + 7] < ASC._0 or
                            self.source[self.curr_pos + 8] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_LONG_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const x1 = self.source[self.curr_pos + 1] - ASC._0;
                        const x2 = self.source[self.curr_pos + 2] - ASC._0;
                        const x3 = self.source[self.curr_pos + 3] - ASC._0;
                        const x4 = self.source[self.curr_pos + 4] - ASC._0;
                        const x5 = self.source[self.curr_pos + 5] - ASC._0;
                        const x6 = self.source[self.curr_pos + 6] - ASC._0;
                        const x7 = self.source[self.curr_pos + 7] - ASC._0;
                        const x8 = self.source[self.curr_pos + 8] - ASC._0;
                        const code: u32 = (x1 << 28) | (x2 << 24) | (x3 << 20) | (x4 << 16) | (x5 << 12) | (x6 << 8) | (x7 << 4) | x8;
                        if (code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) or x1 > 15 or x2 > 15 or x3 > 15 or x4 > 15 or x5 > 15 or x6 > 15 or x7 > 15 or x8 > 15) {
                            warn = TWARN.ILLEGAL_STRING_LONG_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        // const code_result = encode_valid_codepoint(code);
                        // real_len += code_result.len;
                        //FIXME add code_result.bytes to token ROM
                        self.curr_pos += 8;
                        self.curr_col += 8;
                    },
                    else => {
                        warn = TWARN.ILLEGAL_STRING_ESCAPE_SEQUENCE;
                        kind = TKIND.ILLEGAL;
                    },
                }
            },
            else => {
                real_len += result.len;
                switch (result.code) {
                    ASC.NEWLINE => {
                        //FIXME add newline to token ROM
                        real_len += 1;
                        self.curr_col = 0;
                        self.curr_row += 1;
                        while (self.more_bytes_in_source()) {
                            const next_char = self.read_next_utf8_char();
                            switch (next_char) {
                                ASC.SPACE, ASC.H_TAB => {},
                                ASC.BACKTICK => break,
                                ASC.NEWLINE => {
                                    self.rollback_one_byte();
                                    warn = TWARN.ILLEGAL_STRING_MULTILINE_NEVER_TERMINATES;
                                    kind = TKIND.ILLEGAL;
                                    token_builder.set_data(rom_ptr, real_len);
                                    return self.finish_token(kind, warn, token_builder);
                                },
                                else => {
                                    warn = TWARN.ILLEGAL_STRING_MULTILINE_NON_WHITESPACE_BEFORE_BACKTICK;
                                    kind = TKIND.ILLEGAL;
                                    token_builder.set_data(rom_ptr, real_len);
                                    return self.finish_token(kind, warn, token_builder);
                                },
                            }
                        }
                    },
                    ASC.B_SLASH => {},
                    else => {
                        //FIXME add result.bytes to token ROM
                        real_len += result.len;
                        if (result.code == end_char) {
                            token_builder.set_data(rom_ptr, real_len);
                            return self.finish_token(kind, warn, token_builder);
                        }
                    },
                }
            },
        }
        last_char = result.code;
    }
    token_builder.set_data(rom_ptr, real_len);
    return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_STRING_FILE_ENDED_BEFORE_TERMINAL_CHAR, token_builder);
}

fn collect_template_string(self: *Self, token_builder: TokenBuilder) Token {
    var kind: TKIND = TKIND.TEMPLATE;
    var warn: TWARN = TWARN.NONE;
    var real_len: usize = 1;
    //FIXME Get next ROM ptr and save to const
    const rom_ptr: u64 = 0;
    var last_char: u32 = 0;
    while (self.more_bytes_in_source()) {
        const result = self.read_next_utf8_char();
        if (result.warn != TWARN.NONE) {
            warn = result.warn;
            kind = TKIND.ILLEGAL;
        }
        switch (last_char) {
            ASC.B_SLASH => {
                switch (result.code) {
                    ASC.n => {
                        real_len += 1;
                        //FIXME add newline to token ROM
                    },
                    ASC.t => {
                        real_len += 1;
                        //FIXME add h-tab to token ROM
                    },
                    ASC.B_SLASH => {
                        real_len += 1;
                        //FIXME add B_SLASH to token ROM
                    },
                    ASC.DUBL_QUOTE => {
                        real_len += 1;
                        //FIXME add DUBL_QUOTE to token ROM
                    },
                    ASC.BACKTICK => {
                        real_len += 1;
                        //FIXME add BACKTICK to token ROM
                    },
                    ASC.r => {
                        real_len += 1;
                        //FIXME add CR to token ROM
                    },
                    ASC.DOLLAR => {
                        real_len += 1;
                        //FIXME add $ to token ROM
                    },
                    ASC.L_CURLY => {
                        real_len += 1;
                        //FIXME add { to token ROM
                    },
                    ASC.R_CURLY => {
                        real_len += 1;
                        //FIXME add } to token ROM
                    },
                    ASC.o => {
                        if (self.source.len - self.curr_pos < 3 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0 or
                            self.source[self.curr_pos + 3] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_OCTAL_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const o1 = self.source[self.curr_pos + 1] - ASC._0;
                        const o2 = self.source[self.curr_pos + 2] - ASC._0;
                        const o3 = self.source[self.curr_pos + 3] - ASC._0;

                        const val: u16 = (o1 << 6) | (o2 << 3) | o3;
                        if (val > ASC.DEL or o1 > 7 or o2 > 7 or o3 > 7) {
                            warn = TWARN.ILLEGAL_STRING_OCTAL_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        self.curr_pos += 3;
                        self.curr_col += 3;
                        real_len += 1;
                        //FIXME add val to token ROM
                    },
                    ASC.x => {
                        if (self.source.len - self.curr_pos < 2 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_HEX_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const h1 = self.source[self.curr_pos + 1] - ASC._0;
                        const h2 = self.source[self.curr_pos + 2] - ASC._0;
                        const val: u16 = (h1 << 4) | h2;
                        if (val > ASC.DEL or h1 > 15 or h2 > 15) {
                            warn = TWARN.ILLEGAL_STRING_HEX_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        self.curr_pos += 2;
                        self.curr_col += 2;
                        real_len += 1;
                        //FIXME add val to token ROM
                    },
                    ASC.u => {
                        if (self.source.len - self.curr_pos < 4 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0 or
                            self.source[self.curr_pos + 3] < ASC._0 or
                            self.source[self.curr_pos + 4] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_SHORT_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const x1 = self.source[self.curr_pos + 1] - ASC._0;
                        const x2 = self.source[self.curr_pos + 2] - ASC._0;
                        const x3 = self.source[self.curr_pos + 3] - ASC._0;
                        const x4 = self.source[self.curr_pos + 4] - ASC._0;
                        if (x1 > 15 or x2 > 15 or x3 > 15 or x4 > 15) {
                            warn = TWARN.ILLEGAL_STRING_SHORT_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        // const code: u32 = (x1 << 12) | (x2 << 8) | (x3 << 4) | x4;
                        // const code_result = encode_valid_codepoint(code);
                        // real_len += code_result.len;
                        //FIXME add code_result.bytes to token ROM
                        self.curr_pos += 4;
                        self.curr_col += 4;
                    },
                    ASC.U => {
                        if (self.source.len - self.curr_pos < 8 or
                            self.source[self.curr_pos + 1] < ASC._0 or
                            self.source[self.curr_pos + 2] < ASC._0 or
                            self.source[self.curr_pos + 3] < ASC._0 or
                            self.source[self.curr_pos + 4] < ASC._0 or
                            self.source[self.curr_pos + 5] < ASC._0 or
                            self.source[self.curr_pos + 6] < ASC._0 or
                            self.source[self.curr_pos + 7] < ASC._0 or
                            self.source[self.curr_pos + 8] < ASC._0)
                        {
                            warn = TWARN.ILLEGAL_STRING_LONG_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        const x1 = self.source[self.curr_pos + 1] - ASC._0;
                        const x2 = self.source[self.curr_pos + 2] - ASC._0;
                        const x3 = self.source[self.curr_pos + 3] - ASC._0;
                        const x4 = self.source[self.curr_pos + 4] - ASC._0;
                        const x5 = self.source[self.curr_pos + 5] - ASC._0;
                        const x6 = self.source[self.curr_pos + 6] - ASC._0;
                        const x7 = self.source[self.curr_pos + 7] - ASC._0;
                        const x8 = self.source[self.curr_pos + 8] - ASC._0;
                        const code: u32 = (x1 << 28) | (x2 << 24) | (x3 << 20) | (x4 << 16) | (x5 << 12) | (x6 << 8) | (x7 << 4) | x8;
                        if (code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) or x1 > 15 or x2 > 15 or x3 > 15 or x4 > 15 or x5 > 15 or x6 > 15 or x7 > 15 or x8 > 15) {
                            warn = TWARN.ILLEGAL_STRING_LONG_UNICODE_ESCAPE;
                            kind = TKIND.ILLEGAL;
                            last_char = result.code;
                            continue;
                        }
                        // const code_result = encode_valid_codepoint(code);
                        // real_len += code_result.len;
                        //FIXME add code_result.bytes to token ROM
                        self.curr_pos += 8;
                        self.curr_col += 8;
                    },
                    else => {
                        warn = TWARN.ILLEGAL_STRING_ESCAPE_SEQUENCE;
                        kind = TKIND.ILLEGAL;
                    },
                }
            },
            else => {
                switch (result.code) {
                    ASC.NEWLINE => {
                        //FIXME add newline to token ROM
                        real_len += 1;
                        self.curr_col = 0;
                        self.curr_row += 1;
                        while (self.more_bytes_in_source()) {
                            const next_char = self.read_next_utf8_char();
                            switch (next_char) {
                                ASC.SPACE, ASC.H_TAB => {},
                                ASC.BACKTICK => break,
                                ASC.NEWLINE => {
                                    self.rollback_one_byte();
                                    warn = TWARN.ILLEGAL_STRING_MULTILINE_NEVER_TERMINATES;
                                    kind = TKIND.ILLEGAL;
                                    token_builder.set_data(rom_ptr, real_len);
                                    return self.finish_token(kind, warn, token_builder);
                                },
                                else => {
                                    warn = TWARN.ILLEGAL_STRING_MULTILINE_NON_WHITESPACE_BEFORE_BACKTICK;
                                    kind = TKIND.ILLEGAL;
                                    token_builder.set_data(rom_ptr, real_len);
                                    return self.finish_token(kind, warn, token_builder);
                                },
                            }
                        }
                    },
                    ASC.B_SLASH => {},
                    ASC.L_CURLY => {
                        //FIXME handle text replacement site
                    },
                    else => {
                        //FIXME add result.bytes to token ROM
                        real_len += result.len;
                        if (result.code == ASC.DUBL_QUOTE) {
                            token_builder.set_data(rom_ptr, real_len);
                            return self.finish_token(kind, warn, token_builder);
                        }
                    },
                }
            },
        }
        last_char = result.code;
    }
    token_builder.set_data(rom_ptr, real_len);
    return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_STRING_FILE_ENDED_BEFORE_TERMINAL_CHAR, token_builder);
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
    assert(byte_1 >= ASC._0 or byte_1 <= ASC._9);
    if (self.curr_pos == self.source.len) {
        token_builder.set_data(byte_1, 0);
        return self.finish_token(TKIND.LIT_INTEGER, TWARN.NONE, token_builder);
    }
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
        token_builder.set_data(sig_value, 0);
        return self.finish_token(TKIND.LIT_INTEGER, TWARN.NONE, token_builder);
    } else {
        if (sig_value == 0 or sig_digits == 0) {
            const value: u64 = @bitCast(F64.ZERO);
            token_builder.set_data(value, 0);
            return self.finish_token(TKIND.LIT_FLOAT, TWARN.NONE, token_builder);
        }
        const final_exp = implicit_exp + explicit_exp;
        if (sig_digits > F64.MAX_SIG_DIGITS) {
            token_builder.set_data(0, sig_digits);
            return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_FLOAT_TOO_MANY_SIG_DIGITS, token_builder);
        }
        if (final_exp > F64.MAX_EXPONENT or (final_exp == F64.MAX_EXPONENT and sig_value > F64.MAX_SIG_DECIMAL_AT_MAX_EXP)) return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_FLOAT_LITERAL_TOO_LARGE, token_builder);
        if (final_exp < F64.MIN_EXPONENT or (final_exp == F64.MIN_EXPONENT and sig_value < F64.MIN_SIG_DECIMAL_AT_MIN_EXP)) return self.finish_token(TKIND.ILLEGAL, TWARN.ILLEGAL_FLOAT_LITERAL_TOO_SMALL, token_builder);
        const value: u64 = @bitCast(Float.parse_float_from_decimal_parts(sig_value, final_exp, negative, slow_parse_buffer, slow_parse_idx));
        token_builder.set_data(value, 0);
        return self.finish_token(TKIND.LIT_FLOAT, TWARN.NONE, token_builder);
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
        .data_len = token_builder.data_len,
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

inline fn is_whitespace(byte: u8) bool {
    return (byte == ASC.SPACE) or (byte == ASC.NEWLINE) or (byte == ASC.H_TAB);
}

inline fn read_next_byte(self: *Self) u8 {
    assert(self.more_bytes_in_source());
    const val = self.source[self.curr_pos];
    self.next_or_prev_pos = self.curr_pos;
    self.next_or_prev_col = self.curr_col;
    self.next_or_prev_row = self.curr_row;
    self.curr_pos += 1;
    self.curr_col += 1;
    return val;
}

const Utf8Result = struct {
    code: u32 = 0,
    warn: TWARN = TWARN.NONE,
    bytes: [4]u8 = [1]u8{ 0, 0, 0, 0 },
    len: u8 = 1,
};

fn encode_valid_codepoint(code: u32) Utf8Result {
    return switch (code) {
        0x000000...0x00007F => Utf8Result{
            .len = 1,
            .bytes = [4]u4{ @truncate(code), 0, 0, 0 },
        },
        0x000080...0x0007FF => Utf8Result{
            .len = 2,
            .bytes = [4]u4{ (@as(u8, @truncate(code >> 6)) & 0b11111) | 0b11000000, (@as(u8, @truncate(code)) & 0b111111) | 0b10000000, 0, 0 },
        },
        0x000800...0x00FFFF => Utf8Result{
            .len = 3,
            .bytes = [4]u4{ (@as(u8, @truncate(code >> 12)) & 0b1111) | 0b11100000, (@as(u8, @truncate(code >> 6)) & 0b111111) | 0b10000000, (@as(u8, @truncate(code)) & 0b111111) | 0b10000000, 0 },
        },
        0x010000...0x10FFFF => Utf8Result{
            .len = 4,
            .bytes = [4]u4{ (@as(u8, @truncate(code >> 18)) & 0b111) | 0b11110000, (@as(u8, @truncate(code >> 12)) & 0b111111) | 0b10000000, (@as(u8, @truncate(code >> 6)) & 0b111111) | 0b10000000, (@as(u8, @truncate(code)) & 0b111111) | 0b10000000 },
        },
        else => unreachable,
    };
}

fn read_next_utf8_char(self: *Self) Utf8Result {
    assert(self.more_bytes_in_source());
    self.next_or_prev_pos = self.curr_pos;
    self.next_or_prev_col = self.curr_col;
    self.next_or_prev_row = self.curr_row;
    const utf8_len: u8 = switch (self.source[self.curr_pos]) {
        0b0000_0000...0b0111_1111 => 1,
        0b1100_0000...0b1101_1111 => 2,
        0b1110_0000...0b1110_1111 => 3,
        0b1111_0000...0b1111_0111 => 4,
        else => {
            self.curr_col += 1;
            self.curr_pos += 1;
            return Utf8Result{ .code = self.source[self.curr_pos], .warn = TWARN.ILLEGAL_UTF8_FIRST_BYTE };
        },
    };
    if (self.curr_pos + utf8_len > self.source.len) {
        self.curr_col += 1;
        self.curr_pos += 1;
        return Utf8Result{ .code = self.source[self.curr_pos], .warn = TWARN.ILLEGAL_UTF8_STRING_ENDED_EARLY };
    }
    switch (utf8_len) {
        1 => {
            self.curr_col += 1;
            self.curr_pos += 1;
            const bytes = [4]u8{ self.source[self.curr_pos], 0, 0, 0 };
            if (self.source[self.curr_pos] == ASC.NEWLINE) {
                self.curr_col = 0;
                self.curr_row += 1;
            }
            return Utf8Result{ .code = self.source[self.curr_pos], .bytes = bytes, .len = 1 };
        },
        2 => {
            self.curr_col += 1;
            self.curr_pos += 2;
            const bytes = [4]u8{ self.source[self.curr_pos], self.source[self.curr_pos + 1], 0, 0 };
            if (self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) {
                return Utf8Result{ .code = self.source[self.curr_pos + 1], .warn = TWARN.ILLEGAL_UTF8_MALFORMED_CONTINUATION_BYTE, .bytes = bytes, .len = 2 };
            }
            const code: u32 = ((self.source[self.curr_pos] & 0b00011111) << 6) | (self.source[self.curr_pos + 1] & 0b00111111);
            if (code < 0x80) return Utf8Result{ .code = code, .warn = TWARN.ILLEGAL_UTF8_OVERLONG_ENCODING, .bytes = bytes, .len = 2 };
            return Utf8Result{ .code = code, .bytes = bytes, .len = 2 };
        },
        3 => {
            self.curr_col += 1;
            self.curr_pos += 3;
            const bytes = [4]u8{ self.source[self.curr_pos], self.source[self.curr_pos + 1], self.source[self.curr_pos + 2], 0 };
            if ((self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) or (self.source[self.curr_pos + 2] & 0b11000000 != 0b10000000)) {
                return Utf8Result{ .code = self.source[self.curr_pos + 2], .warn = TWARN.ILLEGAL_UTF8_MALFORMED_CONTINUATION_BYTE, .bytes = bytes, .len = 3 };
            }
            const code: u32 = ((self.source[self.curr_pos] & 0b00001111) << 12) | ((self.source[self.curr_pos + 1] & 0b00111111) << 6) | (self.source[self.curr_pos + 2] & 0b00111111);
            if ((code >= 0xD800) or (code <= 0xDFFF)) return Utf8Result{ .code = code, .warn = TWARN.ILLEGAL_UTF8_CHAR_CODE, .bytes = bytes, .len = 3 };
            if (code < 0x800) return Utf8Result{ .code = code, .warn = TWARN.ILLEGAL_UTF8_OVERLONG_ENCODING, .bytes = bytes, .len = 3 };
            return Utf8Result{ .code = code, .bytes = bytes, .len = 3 };
        },
        4 => {
            self.curr_col += 1;
            self.curr_pos += 4;
            const bytes = [4]u8{ self.source[self.curr_pos], self.source[self.curr_pos + 1], self.source[self.curr_pos + 2], self.source[self.curr_pos + 3] };
            if ((self.source[self.curr_pos + 1] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 2] & 0b11000000 != 0b10000000) || (self.source[self.curr_pos + 3] & 0b11000000 != 0b10000000)) {
                return Utf8Result{ .code = self.source[self.curr_pos + 4], .warn = TWARN.ILLEGAL_UTF8_MALFORMED_CONTINUATION_BYTE, .bytes = bytes, .len = 4 };
            }
            const code: u32 = ((self.source[self.curr_pos] & 0b00000111) << 18) | ((self.source[self.curr_pos + 1] & 0b00111111) << 12) | ((self.source[self.curr_pos + 2] & 0b00111111) << 6) | (self.source[self.curr_pos + 3] & 0b00111111);
            if (code >= 0x110000) return Utf8Result{ .code = code, .warn = TWARN.ILLEGAL_UTF8_CHAR_CODE, .bytes = bytes, .len = 4 };
            if (code < 0x10000) return Utf8Result{ .code = code, .warn = TWARN.ILLEGAL_UTF8_OVERLONG_ENCODING, .bytes = bytes, .len = 4 };
            return Utf8Result{ .code = code, .bytes = bytes, .len = 4 };
        },
        else => unreachable,
    }
}

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


