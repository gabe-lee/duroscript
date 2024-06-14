const std = @import("std");
const assert = std.debug.assert;
const ListUm = std.ArrayListUnmanaged;
const Token = @import("./Token.zig");
const TOK = Token.KIND;
const UNI = @import("./Unicode.zig");
const ASC = UNI.ASCII;
const F64 = @import("./constants.zig").F64;
const POWER_10_TABLE = @import("./constants.zig").POWER_10_TABLE;
const Float = @import("./ParseFloat.zig");
const IdentBlock = @import("./IdentBlock.zig");
const SourceReader = @import("./SourceReader.zig");
const TemplateString = @import("./TemplateString.zig");
const SlowParseBuffer = Float.SlowParseBuffer;
const NoticeManager = @import("./NoticeManager.zig");
const IdentManager = @import("./IdentManager.zig");
const ParseInteger = @import("./ParseInteger.zig");
const NOTICE = NoticeManager.KIND;

const ProgramROM = @import("./ProgramROM.zig");
const ParsingAllocator = @import("./ParsingAllocator.zig");

const Self = @This();

source: SourceReader,
source_key: u16,

pub fn new(source: []u8, source_name: []const u8, source_key: u16) Self {
    return Self{ .source = SourceReader.new(source_name, source), .source_key = source_key };
}

pub fn next_token(self: *Self) Token {
    while (self.source.curr.pos < self.source.source.len) {
        const start = self.source.curr.pos;
        if (self.source.source[self.source.curr.pos] == ASC.HASH) {
            self.source.skip_until_byte_match(ASC.NEWLINE);
        }
        self.source.skip_whitespace();
        const end = self.source.curr.pos;
        if (start == end) break;
    }
    if (self.source.curr.pos >= self.source.source.len) {
        var token = TokenBuilder.new(self.source_key, self.source);
        return self.finish_token_kind(TOK.EOF, &token);
    }
    var token_builder = TokenBuilder.new(self.source_key, self.source);
    var token = &token_builder;
    const byte_1 = self.source.read_next_ascii(NOTICE.ERROR);
    switch (byte_1) {
        ASC.COLON => return self.finish_token_kind(TOK.COLON, token),
        ASC.AT_SIGN => return self.finish_token_kind(TOK.REFERENCE, token),
        ASC.COMMA => return self.finish_token_kind(TOK.COMMA, token),
        ASC.SEMICOL => return self.finish_token_kind(TOK.SEMICOL, token),
        ASC.L_PAREN => return self.finish_token_kind(TOK.L_PAREN, token),
        ASC.R_PAREN => return self.finish_token_kind(TOK.R_PAREN, token),
        ASC.L_CURLY => return self.finish_token_kind(TOK.L_CURLY, token),
        ASC.R_CURLY => return self.finish_token_kind(TOK.R_CURLY, token),
        ASC.L_SQUARE => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.R_SQUARE => return self.finish_token_kind(TOK.SLICE, token),
                    ASC.PLUS => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.R_SQUARE => return self.finish_token_kind(TOK.LIST, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_generic_illegal(token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.L_SQUARE, token);
        },
        ASC.R_SQUARE => return self.finish_token_kind(TOK.R_SQUARE, token),
        ASC.QUESTION => return self.finish_token_kind(TOK.MAYBE_NONE, token),
        ASC.PERIOD => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.PERIOD => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.PERIOD => return self.finish_token_kind(TOK.RANGE_INCLUDE_BOTH, token),
                                ASC.PIPE => return self.finish_token_kind(TOK.RANGE_EXCLUDE_END, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_generic_illegal(token);
                    },
                    ASC.AT_SIGN => return self.finish_token_kind(TOK.DEREREFENCE, token),
                    ASC.QUESTION => return self.finish_token_kind(TOK.ACCESS_MAYBE_NONE, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.ACCESS, token);
        },
        ASC.EQUALS => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.EQUALS, token),
                    ASC.MORE_THAN => return self.finish_token_kind(TOK.FAT_ARROW, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.ASSIGN, token);
        },
        ASC.LESS_THAN => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.LESS_THAN_EQUAL, token),
                    ASC.LESS_THAN => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.SHIFT_L_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.SHIFT_L, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.LESS_THAN, token);
        },
        ASC.MORE_THAN => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MORE_THAN_EQUAL, token),
                    ASC.LESS_THAN => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.SHIFT_R_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.SHIFT_R, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MORE_THAN, token);
        },
        ASC.EXCLAIM => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.NOT_EQUAL, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.LOGIC_NOT, token);
        },
        ASC.PLUS => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.ADD_ASSIGN, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.ADD, token);
        },
        ASC.MINUS => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.SUB_ASSIGN, token),
                    ASC._0...ASC._9 => return self.parse_number_literal(token, true),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.SUB, token);
        },
        ASC.ASTERISK => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MULT_ASSIGN, token),
                    ASC.ASTERISK => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.POWER_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.POWER, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MULT, token);
        },
        ASC.F_SLASH => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.DIV_ASSIGN, token),
                    ASC.F_SLASH => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.ROOT_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.ROOT, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.DIV, token);
        },
        ASC.PERCENT => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MODULO_ASSIGN, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MODULO, token);
        },
        ASC.AMPER => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_AND_ASSIGN, token),
                    ASC.AMPER => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_AND_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.LOGIC_AND, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_AND, token);
        },
        ASC.PIPE => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_OR_ASSIGN, token),
                    ASC.PERIOD => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.PERIOD => {
                                    if (self.source.source.len > self.source.curr.pos) {
                                        const byte_4 = self.source.read_next_ascii(NOTICE.ERROR);
                                        switch (byte_4) {
                                            ASC.PIPE => return self.finish_token_kind(TOK.RANGE_EXCLUDE_BOTH, token),
                                            else => self.source.rollback_position(),
                                        }
                                    }
                                    return self.finish_token_kind(TOK.RANGE_EXCLUDE_BEGIN, token);
                                },
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_generic_illegal(token);
                    },
                    ASC.PIPE => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_OR_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.LOGIC_OR, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_OR, token);
        },
        ASC.CARET => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_XOR_ASSIGN, token),
                    ASC.CARET => {
                        if (self.source.source.len > self.source.curr.pos) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_XOR_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.LOGIC_XOR, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_XOR, token);
        },
        ASC.TILDE => return self.finish_token_kind(TOK.BIT_NOT, token),
        ASC._0...ASC._9 => return self.parse_number_literal(token, false),
        ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE => {
            self.source.rollback_position();
            const ident_start = self.source.curr.pos;
            const ident_result = IdentBlock.parse_from_source(&self.source, NOTICE.ERROR);
            const ident_end = self.source.curr.pos;
            if (ident_result.illegal) return self.finish_token_kind(TOK.ILLEGAL, token);
            if (ident_result.len <= Token.LONGEST_KEYWORD) {
                for (Token.KW_U64_SLICES_BY_LEN[ident_result.len], Token.KW_TOKEN_SLICES_BY_LEN[ident_result.len], Token.KW_IMPLICIT_SLICES_BY_LEN[ident_result.len]) |keyword, kind, implicit| {
                    if (ident_result.ident.data[0] == keyword) {
                        token.set_data(implicit, 0, 0);
                        return self.finish_token_kind(kind, token);
                    }
                }
            }
            const ident_key = IdentManager.global.get_ident_index(ident_result.ident, self.source.source[ident_start..ident_end]);
            token.set_data(ident_key, 1, 0);
            return self.finish_token_kind(TOK.IDENT, token);
        },
        ASC.DOLLAR => {
            if (self.source.source.len > self.source.curr.pos) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.DUBL_QUOTE => {
                        const t_string_result = TemplateString.parse_from_source(&self.source, NOTICE.ERROR);
                        token.kind = t_string_result.token;
                        token.set_data(t_string_result.ptr, t_string_result.len, 0);
                        return self.finish_token(token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_generic_illegal(token);
        },
        ASC.DUBL_QUOTE => return self.collect_string(token, true),
        else => return self.finish_token_generic_illegal(token),
    }
}

fn parse_number_literal(self: *Self, token: *TokenBuilder, comptime negative: bool) Token {
    const peek_next = self.source.peek_next_byte();
    var num_result: ParseInteger.ParseNumberResult = undefined;
    switch (peek_next) {
        ASC.b => {
            self.source.curr.advance_one_col(1);
            num_result = ParseInteger.parse_integer(&self.source, ParseInteger.BASE.BIN, negative);
        },
        ASC.o => {
            self.source.curr.advance_one_col(1);
            num_result = ParseInteger.parse_integer(&self.source, ParseInteger.BASE.OCT, negative);
        },
        ASC.x => {
            self.source.curr.advance_one_col(1);
            num_result = ParseInteger.parse_integer(&self.source, ParseInteger.BASE.HEX, negative);
        },
        else => @panic("parsing decimal numbers not imlemented!"), // HACK just deal with the simple cases first
    }
    token.kind = num_result.kind;
    token.set_data(num_result.raw, 0, @as(u8, @intFromBool(num_result.neg)));
    return self.finish_token(token);
}

fn collect_string(self: *Self, token: *TokenBuilder, comptime needs_terminal: bool) Token {
    const program_rom = &ProgramROM.global;
    var kind = TOK.LIT_STRING;
    const alloc = ParsingAllocator.global.alloc;
    var string = ListUm(u8){};
    defer string.deinit(alloc);
    var is_escape = false;
    var has_terminal = false;
    parseloop: while (self.source.source.len > self.source.curr.pos) {
        const char = self.source.read_next_utf8_char(NOTICE.ERROR);
        switch (is_escape) {
            true => {
                is_escape = false;
                switch (char.code) {
                    ASC.n => {
                        string.append(alloc, ASC.NEWLINE) catch unreachable;
                    },
                    ASC.t => {
                        string.append(alloc, ASC.H_TAB) catch unreachable;
                    },
                    ASC.r => {
                        string.append(alloc, ASC.CR) catch unreachable;
                    },
                    ASC.B_SLASH, ASC.DUBL_QUOTE, ASC.BACKTICK => {
                        string.append(alloc, char.bytes[0]) catch unreachable;
                    },
                    ASC.o => {
                        const utf8 = self.source.read_next_n_bytes_as_octal_escape(NOTICE.ERROR, 'o', 3);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]) catch unreachable;
                    },
                    ASC.x => {
                        const utf8 = self.source.read_next_n_bytes_as_hex_escape(NOTICE.ERROR, 'x', 2);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]) catch unreachable;
                    },
                    ASC.u => {
                        const utf8 = self.source.read_next_n_bytes_as_hex_escape(NOTICE.ERROR, 'u', 4);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]) catch unreachable;
                    },
                    ASC.U => {
                        const utf8 = self.source.read_next_n_bytes_as_hex_escape(NOTICE.ERROR, 'U', 8);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]) catch unreachable;
                    },
                    else => {
                        self.source.add_illegal_string_escape_sequence_notice(NOTICE.ERROR, char.code);
                        kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, UNI.REP_CHAR_BYTES[0..UNI.REP_CHAR_LEN]) catch unreachable;
                    },
                }
            },
            else => {
                switch (char.code) {
                    ASC.NEWLINE => {
                        string.append(alloc, ASC.NEWLINE) catch unreachable;
                        self.source.skip_whitespace_except_newline();
                        if (self.source.source.len > self.source.curr.pos) {
                            const next_byte = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (next_byte) {
                                ASC.BACKTICK => {},
                                ASC.NEWLINE => {
                                    self.source.add_runaway_multiline_notice(NOTICE.ERROR);
                                    return self.finish_token_kind(TOK.ILLEGAL, token);
                                },
                                else => {
                                    self.source.add_illegal_char_multiline_notice(NOTICE.ERROR, next_byte);
                                    kind = TOK.ILLEGAL;
                                },
                            }
                        } else {
                            self.source.add_source_end_before_string_end_notice(NOTICE.ERROR);
                            return self.finish_token_kind(TOK.ILLEGAL, token);
                        }
                    },
                    ASC.B_SLASH => {
                        is_escape = true;
                    },
                    ASC.DUBL_QUOTE => {
                        has_terminal = true;
                        break :parseloop;
                    },
                    else => {
                        string.appendSlice(alloc, char.bytes[0..char.len]) catch unreachable;
                    },
                }
            },
        }
    }
    if (needs_terminal and !has_terminal) {
        self.source.add_source_end_before_string_end_notice(NOTICE.ERROR);
        return self.finish_token_kind(TOK.ILLEGAL, token);
    }
    program_rom.prepare_space_for_write(string.items.len, 1);
    const ptr = program_rom.len;
    program_rom.write_slice(u8, string.items);
    token.set_data(ptr, @intCast(string.items.len), 0);
    return self.finish_token_kind(TOK.LIT_STRING, token);
}

// fn finish_integer_literal_token(self: *Self, val: u64, negative: bool, token: *TokenBuilder) Token {
//     if (negative and val > MAX_NEGATIVE_I64_AS_U64) {
//         // FIXME add number too large to be negative error
//         return self.finish_token_kind(TOK.ILLEGAL, token);
//     }
//     const true_val: u64 = if (negative) @bitCast(-@as(i64, @intCast(val))) else val;
//     token.set_data(true_val, 0, @intFromBool(negative));
//     return self.finish_token_kind(TOK.LIT_INTEGER, token);
// }

// fn handle_number_literal(self: *Self, token: *TokenBuilder, negative: bool, byte_1: u8) Token {
//     assert(byte_1 >= ASC._0 or byte_1 <= ASC._9);
//     if (self.source.curr.pos >= self.source.source.len) {
//         const val: u64 = if (negative) @bitCast(-@as(i64, @intCast(byte_1))) else @as(u64, @intCast(byte_1));
//         token.set_data(val, 0, 0);
//         return self.finish_token_kind(TOK.LIT_INTEGER, token);
//     }
//     const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
//     if (byte_1 == ASC._0) {
//         var data_value: u64 = 0;
//         var bit_position: u32 = 0;
//         var leading_zeroes: u8 = 0;
//         switch (byte_2) {
//             ASC.b => {
//                 while (self.source.source.len > self.source.curr.pos) {
//                     const leading_zero = self.source.read_next_ascii(NOTICE.ERROR);
//                     if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
//                         self.source.rollback_position();
//                         break;
//                     } else if (leading_zero == ASC._0) leading_zeroes += 1;
//                 }
//                 while (self.source.source.len > self.source.curr.pos) {
//                     const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
//                     switch (byte_x) {
//                         ASC._0...ASC._1 => {
//                             if (bit_position >= 64) {
//                                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                                 // FIXME as iilegal number overflows 64 bits error
//                                 return self.finish_token_kind(TOK.ILLEGAL, token);
//                             }
//                             data_value |= @as(u64, byte_x - ASC._0) << @truncate(BIN_MSB_SHIFT - bit_position);
//                             bit_position += 1;
//                         },
//                         ASC.UNDERSCORE => {},
//                         ASC._2...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => {
//                             self.source.skip_illegal_alphanumeric_string_plus_dot();
//                             // FIXME as illegal alphanum in binary error
//                             return self.finish_token_kind(TOK.ILLEGAL, token);
//                         },
//                         else => {
//                             self.source.rollback_position();
//                             break;
//                         },
//                     }
//                 }
//                 data_value >>= @truncate(64 - bit_position);
//                 if (leading_zeroes == 0 or bit_position == 0) {
//                     // FIXME as illegal number literal no significant bits error
//                     return self.finish_token_kind(TOK.ILLEGAL, token);
//                 }
//                 return self.finish_integer_literal_token(data_value, negative, token);
//             },
//             ASC.o => {
//                 while (self.source.source.len > self.source.curr.pos) {
//                     const leading_zero = self.source.read_next_ascii(NOTICE.ERROR);
//                     if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
//                         self.source.rollback_position();
//                         break;
//                     } else if (leading_zero == ASC._0) leading_zeroes += 1;
//                 }
//                 while (self.source.source.len > self.source.curr.pos) {
//                     const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
//                     switch (byte_x) {
//                         ASC._0...ASC._7 => {
//                             if (bit_position >= 64) {
//                                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                                 // FIXME as illegal number overflows 64 bits error
//                                 return self.finish_token_kind(TOK.ILLEGAL, token);
//                             } else if (bit_position == 63) {
//                                 if (data_value & 0xC000000000000000 != 0) {
//                                     self.source.skip_illegal_alphanumeric_string_plus_dot();
//                                     // FIXME as illegal number overflows 64 bits error
//                                     return self.finish_token_kind(TOK.ILLEGAL, token);
//                                 }
//                                 data_value = (data_value << 2) | @as(u64, byte_x - ASC._0);
//                             } else {
//                                 data_value |= @as(u64, byte_x - ASC._0) << @truncate(OCT_MSB_SHIFT - bit_position);
//                                 bit_position += 3;
//                             }
//                         },
//                         ASC.UNDERSCORE => {},
//                         ASC._8...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => {
//                             self.source.skip_illegal_alphanumeric_string_plus_dot();
//                             // FIXME as illegal alphanum in octal error
//                             return self.finish_token_kind(TOK.ILLEGAL, token);
//                         },
//                         else => {
//                             self.source.rollback_position();
//                             break;
//                         },
//                     }
//                 }
//                 data_value >>= @truncate(64 - bit_position);
//                 if (leading_zeroes == 0 or bit_position == 0) {
//                     // FIXME as illegal number literal no significant bits error
//                     return self.finish_token_kind(TOK.ILLEGAL, token);
//                 }
//                 return self.finish_integer_literal_token(data_value, negative, token);
//             },
//             ASC.x => {
//                 while (self.source.source.len > self.source.curr.pos) {
//                     const leading_zero = self.source.read_next_ascii(NOTICE.ERROR);
//                     if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
//                         self.source.rollback_position();
//                         break;
//                     } else if (leading_zero == ASC._0) leading_zeroes += 1;
//                 }
//                 while (self.source.source.len > self.source.curr.pos) {
//                     const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
//                     switch (byte_x) {
//                         ASC._0...ASC._9 => {
//                             if (bit_position >= 64) {
//                                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                                 // FIXME as illegal number overflows 64 bits error
//                                 return self.finish_token_kind(TOK.ILLEGAL, token);
//                             }
//                             data_value |= @as(u64, byte_x - ASC._0) << @truncate(HEX_MSB_SHIFT - bit_position);
//                             bit_position += 4;
//                         },
//                         ASC.A...ASC.F => {
//                             if (bit_position >= 64) {
//                                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                                 // FIXME as illegal number overflows 64 bits error
//                                 return self.finish_token_kind(TOK.ILLEGAL, token);
//                             }
//                             data_value |= @as(u64, byte_x - ASC.A) << @truncate(HEX_MSB_SHIFT - bit_position);
//                             bit_position += 4;
//                         },
//                         ASC.a...ASC.f => {
//                             if (bit_position >= 64) {
//                                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                                 // FIXME as illegal number overflows 64 bits error
//                                 return self.finish_token_kind(TOK.ILLEGAL, token);
//                             }
//                             data_value |= @as(u64, byte_x - ASC.a) << @truncate(HEX_MSB_SHIFT - bit_position);
//                             bit_position += 4;
//                         },
//                         ASC.UNDERSCORE => {},
//                         ASC.G...ASC.Z, ASC.g...ASC.z, ASC.PERIOD => {
//                             self.source.skip_illegal_alphanumeric_string_plus_dot();
//                             // FIXME as illegal alphanum in hex error
//                             return self.finish_token_kind(TOK.ILLEGAL, token);
//                         },
//                         else => {
//                             self.source.rollback_position();
//                             break;
//                         },
//                     }
//                 }
//                 if (leading_zeroes == 0 or bit_position == 0) {
//                     // FIXME as illegal number literal no significant bits error
//                     return self.finish_token_kind(TOK.ILLEGAL, token);
//                 }
//                 data_value >>= @truncate(64 - bit_position);
//                 return self.finish_integer_literal_token(data_value, negative, token);
//             },
//             ASC._0...ASC._9, ASC.PERIOD, ASC.UNDERSCORE, ASC.e, ASC.E => {
//                 self.source.rollback_position();
//             },
//             else => {
//                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                 // FIXME as illegal alphanum in number error
//                 return self.finish_token_kind(TOK.ILLEGAL, token);
//             },
//         }
//     }
//     var slow_parse_buffer: SlowParseBuffer = [1]u8{0} ** 26;
//     var slow_parse_idx: usize = 0;
//     var sig_value: u64 = 0;
//     var sig_digits: u64 = 0;
//     var implicit_exp: i64 = 0;
//     var is_float = false;
//     var flt_exp_sub: i16 = 0;
//     var has_exp = false;
//     var neg_exp = false;
//     var sig_int_found = byte_1 != ASC._0;
//     if (sig_int_found) {
//         slow_parse_buffer[slow_parse_idx] = byte_1;
//         slow_parse_idx += 1;
//         sig_value = byte_1;
//         sig_digits += 1;
//     }
//     switch (byte_2) {
//         ASC._0...ASC._9 => {
//             sig_int_found = sig_int_found or (byte_2 != ASC._0);
//             if (sig_int_found) {
//                 slow_parse_buffer[slow_parse_idx] = byte_2;
//                 slow_parse_idx += 1;
//                 sig_value = (sig_value *% 10) + @as(u64, byte_2 - ASC._0);
//                 sig_digits += 1;
//             }
//         },
//         ASC.PERIOD => {
//             slow_parse_buffer[slow_parse_idx] = byte_2;
//             slow_parse_idx += 1;
//             is_float = true;
//             flt_exp_sub = 1;
//         },
//         ASC.e, ASC.E => {
//             slow_parse_buffer[slow_parse_idx] = ASC.e;
//             slow_parse_idx += 1;
//             has_exp = true;
//             if (self.source.source.len > self.source.curr.pos) {
//                 const first_exp_byte = self.source.read_next_ascii(NOTICE.ERROR);
//                 switch (first_exp_byte) {
//                     ASC.MINUS => {
//                         neg_exp = true;
//                     },
//                     ASC.PLUS => {},
//                     else => self.source.rollback_position(),
//                 }
//             }
//         },
//         else => {},
//     }
//     while (!has_exp and self.source.source.len > self.source.curr.pos) {
//         const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
//         switch (byte_x) {
//             ASC._0...ASC._9 => {
//                 sig_int_found = sig_int_found or (byte_x != ASC._0);
//                 if (sig_int_found) {
//                     if (is_float and byte_x == ASC._0) {
//                         var trailing_zeroes: u16 = 1;
//                         while (self.source.source.len > self.source.curr.pos) {
//                             const byte_xx = self.source.read_next_ascii(NOTICE.ERROR);
//                             switch (byte_xx) {
//                                 ASC._0 => {
//                                     trailing_zeroes += 1;
//                                 },
//                                 ASC._1...ASC._9 => {
//                                     sig_value *%= POWER_10_TABLE[trailing_zeroes];
//                                     sig_digits += trailing_zeroes;
//                                     implicit_exp -= trailing_zeroes;
//                                     if (sig_digits > 19 or (sig_digits == 19 and ((byte_x <= ASC._5 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_0_THRU_5) or (byte_x >= ASC._6 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_6_THRU_9)))) {
//                                         self.source.skip_illegal_alphanumeric_string_plus_dot();
//                                         // FIXME as illegal number overflows 64 bits error
//                                         return self.finish_token_kind(TOK.ILLEGAL, token);
//                                     }
//                                     slow_parse_idx += trailing_zeroes;
//                                     slow_parse_buffer[slow_parse_idx] = byte_xx;
//                                     slow_parse_idx += 1;
//                                     sig_digits += 1;
//                                     implicit_exp -= 1;
//                                     sig_value = (sig_value *% 10) + @as(u64, byte_xx - ASC._0);
//                                     break;
//                                 },
//                                 else => {
//                                     self.source.rollback_position();
//                                     break;
//                                 },
//                             }
//                         }
//                     } else {
//                         if (sig_digits > 19 or (sig_digits == 19 and ((byte_x <= ASC._5 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_0_THRU_5) or (byte_x >= ASC._6 and sig_value > LARGEST_19_DIGIT_INTEGER_THAT_CAN_ACCEPT_6_THRU_9)))) {
//                             self.source.skip_illegal_alphanumeric_string_plus_dot();
//                             // FIXME as illegal number overflows 64 bits error
//                             return self.finish_token_kind(TOK.ILLEGAL, token);
//                         }
//                         slow_parse_buffer[slow_parse_idx] = byte_x;
//                         slow_parse_idx += 1;
//                         sig_value = (sig_value *% 10) + @as(u64, byte_x - ASC._0);
//                         sig_digits += 1;
//                         implicit_exp -= flt_exp_sub;
//                     }
//                 }
//             },
//             ASC.PERIOD => {
//                 if (is_float) {
//                     self.source.skip_illegal_alphanumeric_string_plus_dot();
//                     // FIXME as illegal float too many dots error
//                     return self.finish_token_kind(TOK.ILLEGAL, token);
//                 }
//                 slow_parse_buffer[slow_parse_idx] = byte_x;
//                 slow_parse_idx += 1;
//                 is_float = true;
//             },
//             ASC.E, ASC.e => {
//                 if (has_exp) {
//                     self.source.skip_illegal_alphanumeric_string_plus_dot();
//                     // FIXME as illegal number too many exponents error
//                     return self.finish_token_kind(TOK.ILLEGAL, token);
//                 }
//                 slow_parse_buffer[slow_parse_idx] = ASC.e;
//                 slow_parse_idx += 1;
//                 has_exp = true;
//                 if (self.source.source.len > self.source.curr.pos) {
//                     const first_exp_byte = self.source.read_next_ascii(NOTICE.ERROR);
//                     switch (first_exp_byte) {
//                         ASC.MINUS => {
//                             neg_exp = true;
//                             slow_parse_buffer[slow_parse_idx] = ASC.MINUS;
//                             slow_parse_idx += 1;
//                         },
//                         ASC.PLUS => {},
//                         else => self.source.rollback_position(),
//                     }
//                 }
//             },
//             ASC.UNDERSCORE => {},
//             ASC.A...ASC.D, ASC.F...ASC.Z, ASC.a...ASC.d, ASC.f...ASC.z => {
//                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                 // FIXME as illegal alphanum in number error
//                 return self.finish_token_kind(TOK.ILLEGAL, token);
//             },
//             else => {
//                 self.source.rollback_position();
//                 break;
//             },
//         }
//     }
//     var explicit_exp: i64 = 0;
//     var exp_sig_digits: u64 = 0;
//     var exp_sig_int_found = false;
//     while (has_exp and self.source.source.len > self.source.curr.pos) {
//         const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
//         switch (byte_x) {
//             ASC._0...ASC._9 => {
//                 exp_sig_int_found = exp_sig_int_found or (byte_x != ASC._0);
//                 if (exp_sig_int_found) {
//                     if (exp_sig_digits == 4) return {
//                         self.source.skip_illegal_alphanumeric_string_plus_dot();
//                         // FIXME as illegal number too many digits in exponent
//                         return self.finish_token_kind(TOK.ILLEGAL, token);
//                     };
//                     slow_parse_buffer[slow_parse_idx] = byte_x;
//                     slow_parse_idx += 1;
//                     explicit_exp = (explicit_exp *% 10) + @as(i64, byte_x - ASC._0);
//                     exp_sig_digits += 1;
//                 }
//             },
//             ASC.PERIOD => {
//                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                 // FIXME as illegal float period in exponent
//                 return self.finish_token_kind(TOK.ILLEGAL, token);
//             },
//             ASC.E, ASC.e => {
//                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                 // FIXME as illegal alphanum too many exponents
//                 return self.finish_token_kind(TOK.ILLEGAL, token);
//             },
//             ASC.UNDERSCORE => {},
//             ASC.A...ASC.D, ASC.F...ASC.Z, ASC.a...ASC.d, ASC.f...ASC.z => {
//                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                 // FIXME as illegal alphanum in exponent error
//                 return self.finish_token_kind(TOK.ILLEGAL, token);
//             },
//             else => {
//                 self.source.rollback_position();
//                 break;
//             },
//         }
//     }
//     if (!is_float) {
//         const exp_mag = @abs(explicit_exp);
//         if (explicit_exp > 0) {
//             if (explicit_exp > 19 or sig_value > MAX_INT_VALS_FOR_POSITIVE_EXP[exp_mag]) {
//                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                 // FIXME as illegal integer overflows 64 bits error
//                 return self.finish_token_kind(TOK.ILLEGAL, token);
//             }
//             sig_value *= POWER_10_TABLE[exp_mag];
//         } else if (explicit_exp < 0) {
//             if (explicit_exp < 19 or sig_value % POWER_10_TABLE[exp_mag] != 0) {
//                 self.source.skip_illegal_alphanumeric_string_plus_dot();
//                 // FIXME as illegal integer loss of data
//                 return self.finish_token_kind(TOK.ILLEGAL, token);
//             }
//             sig_value /= POWER_10_TABLE[exp_mag];
//         }
//         return self.finish_integer_literal_token(sig_value, negative, token);
//     } else {
//         if (sig_value == 0 or sig_digits == 0) {
//             const value: u64 = @bitCast(F64.ZERO);
//             token.set_data(value, 0, 0);
//             return self.finish_token_kind(TOK.LIT_FLOAT, token);
//         }
//         const final_exp = implicit_exp + explicit_exp;
//         if (sig_digits > F64.MAX_SIG_DIGITS) {
//             // FIXME as illegal float too many sig digits
//             return self.finish_token_kind(TOK.ILLEGAL, token);
//         }
//         if (final_exp > F64.MAX_EXPONENT or (final_exp == F64.MAX_EXPONENT and sig_value > F64.MAX_SIG_DECIMAL_AT_MAX_EXP)) {
//             // FIXME as illegal float too large
//             return self.finish_token_kind(TOK.ILLEGAL, token);
//         }
//         if (final_exp < F64.MIN_EXPONENT or (final_exp == F64.MIN_EXPONENT and sig_value < F64.MIN_SIG_DECIMAL_AT_MIN_EXP)) {
//             // FIXME as illegal float too small
//             return self.finish_token_kind(TOK.ILLEGAL, token);
//         }
//         const value: u64 = @bitCast(Float.parse_float_from_decimal_parts(sig_value, final_exp, negative, slow_parse_buffer, slow_parse_idx));
//         token.set_data(value, 0, 0);
//         return self.finish_token_kind(TOK.LIT_FLOAT, token);
//     }
// }

inline fn finish_token(self: *Self, token: *TokenBuilder) Token {
    return Token{
        .kind = token.kind,
        .source_key = token.source_key,
        .row_start = token.start_row,
        .row_end = self.source.curr.row,
        .col_start = token.start_col,
        .col_end = self.source.curr.col,
        .data_val_or_ptr = token.data_val_or_ptr,
        .data_len = token.data_len,
        .data_extra = token.data_extra,
    };
}

inline fn finish_token_kind(self: *Self, kind: TOK, token: *TokenBuilder) Token {
    return Token{
        .kind = kind,
        .source_key = token.source_key,
        .row_start = token.start_row,
        .row_end = self.source.curr.row,
        .col_start = token.start_col,
        .col_end = self.source.curr.col,
        .data_val_or_ptr = token.data_val_or_ptr,
        .data_len = token.data_len,
        .data_extra = token.data_extra,
    };
}

inline fn finish_token_generic_illegal(self: *Self, token: *TokenBuilder) Token {
    self.source.add_generic_illegal_token_notice(NOTICE.ERROR, self.source.source[token.start_pos..self.source.curr.pos]);
    return Token{
        .kind = TOK.ILLEGAL,
        .source_key = token.source_key,
        .row_start = token.start_row,
        .row_end = self.source.curr.row,
        .col_start = token.start_col,
        .col_end = self.source.curr.col,
        .data_val_or_ptr = token.data_val_or_ptr,
        .data_len = token.data_len,
        .data_extra = token.data_extra,
    };
}

const TokenBuilder = struct {
    source_key: u16,
    kind: TOK,
    start_pos: u32,
    start_col: u32,
    start_row: u32,
    data_val_or_ptr: u64,
    data_len: u32,
    data_extra: u8,

    inline fn new(source_key: u16, source: SourceReader) TokenBuilder {
        return TokenBuilder{
            .source_key = source_key,
            .kind = TOK.ILLEGAL,
            .start_pos = source.curr.pos,
            .start_col = source.curr.col,
            .start_row = source.curr.row,
            .data_val_or_ptr = 0,
            .data_len = 0,
            .data_extra = 0,
        };
    }

    inline fn set_start(self: *TokenBuilder, source: SourceReader) void {
        self.start_pos = source.curr.pos;
        self.start_col = source.curr.col;
        self.start_row = source.curr.row;
    }

    inline fn set_data(self: *TokenBuilder, val_or_ptr: u64, len: u32, extra: u8) void {
        self.data_val_or_ptr = val_or_ptr;
        self.data_len = len;
        self.data_extra = extra;
    }
};

const MAX_POSITIVE_I64: u64 = std.math.maxInt(isize);
const MAX_NEGATIVE_I64_AS_U64: u64 = MAX_POSITIVE_I64 + 1;

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
