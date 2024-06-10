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
const NOTICE = NoticeManager.KIND;

const ProgramROM = @import("./ProgramROM.zig").Global;
const ParsingAllocator = @import("./ParsingAllocator.zig").Global;

const Self = @This();

source: SourceReader,
source_key: u32,

pub fn new(source: []u8, source_name: []const u8, source_key: u32) Self {
    return Self{ .source = SourceReader.new(source_name, source), .source_key = source_key };
}

pub fn next_token(self: *Self) Token {
    self.source.skip_whitespace();
    if (self.source.is_complete()) {
        const token = TokenBuilder.new(self.source_key, self.source);
        return self.finish_token_kind_kind(TOK.EOF, token);
    }
    const token = TokenBuilder.new(self.source_key, self.source);
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
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.R_SQUARE => return self.finish_token_kind(TOK.SLICE, token),
                    ASC.PLUS => {
                        if (!self.source.is_complete()) {
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
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.PERIOD => {
                        if (!self.source.is_complete()) {
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
            if (!self.source.is_complete()) {
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
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.LESS_THAN_EQUAL, token),
                    ASC.LESS_THAN => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.SHIFT_L_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        self.finish_token_kind(TOK.SHIFT_L, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.LESS_THAN, token);
        },
        ASC.MORE_THAN => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MORE_THAN_EQUAL, token),
                    ASC.LESS_THAN => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.SHIFT_R_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        self.finish_token_kind(TOK.SHIFT_R, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MORE_THAN, token);
        },
        ASC.EXCLAIM => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.NOT_EQUAL, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.LOGIC_NOT, token);
        },
        ASC.PLUS => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.ADD_ASSIGN, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.ADD, token);
        },
        ASC.MINUS => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.SUB_ASSIGN, token),
                    ASC._0...ASC._9 => self.handle_number_literal(token, true, byte_2),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.SUB, token);
        },
        ASC.ASTERISK => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MULT_ASSIGN, token),
                    ASC.ASTERISK => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.POWER_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        self.finish_token_kind(TOK.POWER, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MULT, token);
        },
        ASC.F_SLASH => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.DIV_ASSIGN, token),
                    ASC.F_SLASH => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.ROOT_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        self.finish_token_kind(TOK.ROOT, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.DIV, token);
        },
        ASC.PERCENT => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MODULO_ASSIGN, token),
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MODULO, token);
        },
        ASC.AMPER => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_AND_ASSIGN, token),
                    ASC.AMPER => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_AND_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        self.finish_token_kind(TOK.LOGIC_AND, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_AND, token);
        },
        ASC.PIPE => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_OR_ASSIGN, token),
                    ASC.PERIOD => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.PERIOD => {
                                    if (!self.source.is_complete()) {
                                        const byte_4 = self.source.read_next_ascii(NOTICE.ERROR);
                                        switch (byte_4) {
                                            ASC.PIPE => return self.finish_token_kind(TOK.RANGE_EXCLUDE_BOTH, token),
                                            else => self.source.rollback_position(),
                                        }
                                    }
                                    self.finish_token_kind(TOK.RANGE_EXCLUDE_BEGIN, token);
                                },
                                else => self.source.rollback_position(),
                            }
                        }
                        return self.finish_token_generic_illegal(token);
                    },
                    ASC.PIPE => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_OR_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        self.finish_token_kind(TOK.LOGIC_OR, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_OR, token);
        },
        ASC.CARET => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_XOR_ASSIGN, token),
                    ASC.CARET => {
                        if (!self.source.is_complete()) {
                            const byte_3 = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_XOR_ASSIGN, token),
                                else => self.source.rollback_position(),
                            }
                        }
                        self.finish_token_kind(TOK.LOGIC_XOR, token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_XOR, token);
        },
        ASC.TILDE => return self.finish_token_kind(TOK.BIT_NOT, token),
        ASC._0...ASC._9 => self.handle_number_literal(token, false, byte_1),
        ASC.A...ASC.UNDERSCORE => {
            self.source.rollback_position();
            const ident_result = IdentBlock.parse_from_source(self.source, NOTICE.ERROR);
            if (ident_result.illegal) return self.finish_token_kind(TOK.ILLEGAL, token);
            ProgramROM.prepare_space_for_write(@sizeOf(IdentBlock), @alignOf(IdentBlock));
            const ptr: u64 = @bitCast(ProgramROM.len);
            ProgramROM.write_single(IdentBlock, ident_result.ident);
            token.set_data(ptr, 1, 0);
            return self.finish_token_kind(TOK.IDENT, token);
        },
        ASC.DOLLAR => {
            if (!self.source.is_complete()) {
                const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
                switch (byte_2) {
                    ASC.DUBL_QUOTE => {
                        const t_string_result = TemplateString.parse_from_source(self.source, NOTICE.ERROR);
                        token.kind = t_string_result.token;
                        token.set_data(t_string_result.ptr, t_string_result.len, 0);
                        return self.finish_token(token);
                    },
                    else => self.source.rollback_position(),
                }
            }
            return self.finish_token_generic_illegal(token);
        },
        else => return self.finish_token_generic_illegal(token),
    }
}

const CollectStringResult = struct {
    ptr: u64,
    len: u32,
    kind: TOK,
};

fn collect_string(self: *Self, comptime needs_terminal: bool) Token {
    var kind = TOK.LIT_STRING;
    const alloc = ParsingAllocator.allocator();
    var string = ListUm(u8){};
    defer string.deinit(string.alloc);
    var is_escape = false;
    var has_terminal = false;
    parseloop: while (!self.source.is_complete()) {
        const char = self.source.read_next_utf8_char(NOTICE.ERROR);
        switch (is_escape) {
            true => {
                switch (char.code) {
                    ASC.n => {
                        string.append(alloc, ASC.NEWLINE);
                    },
                    ASC.t => {
                        string.append(alloc, ASC.H_TAB);
                    },
                    ASC.r => {
                        string.append(alloc, ASC.CR);
                    },
                    ASC.B_SLASH, ASC.DUBL_QUOTE, ASC.BACKTICK => {
                        string.append(alloc, char.bytes[0]);
                    },
                    ASC.o => {
                        const utf8 = self.source.read_next_n_bytes_as_octal_escape(NOTICE.ERROR, 'o', 3);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]);
                    },
                    ASC.x => {
                        const utf8 = self.source.read_next_n_bytes_as_hex_escape(NOTICE.ERROR, 'x', 2);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]);
                    },
                    ASC.u => {
                        const utf8 = self.source.read_next_n_bytes_as_hex_escape(NOTICE.ERROR, 'u', 4);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]);
                    },
                    ASC.U => {
                        const utf8 = self.source.read_next_n_bytes_as_hex_escape(NOTICE.ERROR, 'U', 8);
                        if (utf8.code == UNI.REP_CHAR) kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, utf8.bytes[0..utf8.len]);
                    },
                    else => {
                        self.source.add_illegal_string_escape_sequence_notice(NOTICE.ERROR, char.code);
                        kind = TOK.ILLEGAL;
                        string.appendSlice(alloc, UNI.REP_CHAR_BYTES[0..UNI.REP_CHAR_LEN]);
                    },
                }
            },
            else => {
                switch (char.code) {
                    ASC.NEWLINE => {
                        string.append(alloc, ASC.NEWLINE);
                        self.source.skip_whitespace_except_newline();
                        if (!self.source.is_complete()) {
                            const next_byte = self.source.read_next_ascii(NOTICE.ERROR);
                            switch (next_byte) {
                                ASC.BACKTICK => {},
                                ASC.NEWLINE => {
                                    self.source.add_runaway_multiline_notice(NOTICE.ERROR);
                                    return CollectStringResult{
                                        .ptr = 0,
                                        .len = 0,
                                        .kind = TOK.ILLEGAL,
                                    };
                                },
                                else => {
                                    self.source.add_illegal_char_multiline_notice(NOTICE.ERROR, next_byte);
                                    kind = TOK.ILLEGAL;
                                },
                            }
                        } else {
                            self.source.add_source_end_before_string_end_notice(NOTICE.ERROR);
                            return CollectStringResult{
                                .ptr = 0,
                                .len = 0,
                                .kind = TOK.ILLEGAL,
                            };
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
                        string.appendSlice(alloc, char.bytes[0..char.len]);
                    },
                }
            },
        }
    }
    if (needs_terminal and !has_terminal) {
        self.source.add_source_end_before_string_end_notice(NOTICE.ERROR);
        return CollectStringResult{
            .ptr = 0,
            .len = 0,
            .kind = TOK.ILLEGAL,
        };
    }
    ProgramROM.prepare_space_for_write(string.items.len, 1);
    const ptr = ProgramROM.len;
    ProgramROM.write_slice(u8, string.items);
    return CollectStringResult{
        .ptr = ptr,
        .len = string.items.len,
        .kind = TOK.LIT_STRING,
    };
}

//CHECKPOINT Finish re-writing below functions to use new api

fn collect_illegal_alphanumeric_string(self: *Self, token_builder: TokenBuilder, warn: TWARN) Token {
    while (!self.source.is_complete()) {
        const next_byte = self.source.read_next_ascii(NOTICE.ERROR);
        switch (next_byte) {
            ASC._0...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE => {},
            else => {
                self.source.rollback_position();
                break;
            },
        }
    }
    return self.finish_token_kind(TOK.ILLEGAL, warn, token_builder);
}

fn collect_illegal_alphanumeric_string_plus_dot(self: *Self, token_builder: TokenBuilder, warn: TWARN) Token {
    while (!self.source.is_complete()) {
        const next_byte = self.source.read_next_ascii(NOTICE.ERROR);
        switch (next_byte) {
            ASC._0...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE, ASC.PERIOD => {},
            else => {
                self.source.rollback_position();
                break;
            },
        }
    }
    return self.finish_token_kind(TOK.ILLEGAL, warn, token_builder);
}

fn handle_number_literal(self: *Self, token_builder: TokenBuilder, negative: bool, byte_1: u8) Token {
    assert(byte_1 >= ASC._0 or byte_1 <= ASC._9);
    if (self.curr_pos == self.source.len) {
        token_builder.set_data(byte_1, 0);
        return self.finish_token_kind(TOK.LIT_INTEGER, TWARN.NONE, token_builder);
    }
    const byte_2 = self.source.read_next_ascii(NOTICE.ERROR);
    if (byte_1 == ASC._0) {
        var data_value: u64 = 0;
        var bit_position: u32 = 0;
        var leading_zeroes = 0;
        switch (byte_2) {
            ASC.b => {
                while (!self.source.is_complete()) {
                    const leading_zero = self.source.read_next_ascii(NOTICE.ERROR);
                    if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
                        self.source.rollback_position();
                        break;
                    } else if (leading_zero == ASC._0) leading_zeroes += 1;
                }
                while (!self.source.is_complete()) {
                    const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
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
                            self.source.rollback_position();
                            break;
                        },
                    }
                }
                data_value >>= (64 - bit_position);
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS, token_builder);
                }
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ASC.o => {
                while (!self.source.is_complete()) {
                    const leading_zero = self.source.read_next_ascii(NOTICE.ERROR);
                    if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
                        self.source.rollback_position();
                        break;
                    } else if (leading_zero == ASC._0) leading_zeroes += 1;
                }
                while (!self.source.is_complete()) {
                    const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
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
                            self.source.rollback_position();
                            break;
                        },
                    }
                }
                data_value >>= (64 - bit_position);
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS, token_builder);
                }
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ASC.x => {
                while (!self.source.is_complete()) {
                    const leading_zero = self.source.read_next_ascii(NOTICE.ERROR);
                    if (leading_zero != ASC._0 or leading_zero != ASC.UNDERSCORE) {
                        self.source.rollback_position();
                        break;
                    } else if (leading_zero == ASC._0) leading_zeroes += 1;
                }
                while (!self.source.is_complete()) {
                    const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
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
                            self.source.rollback_position();
                            break;
                        },
                    }
                }
                if (leading_zeroes == 0 or bit_position == 0) {
                    return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_NO_SIGNIFICANT_BITS, token_builder);
                }
                data_value >>= (64 - bit_position);
                return self.finish_integer_literal_token(token_builder, data_value, negative);
            },
            ASC._0...ASC._9, ASC.PERIOD, ASC.UNDERSCORE, ASC.e, ASC.E => {
                self.source.rollback_position();
            },
            else => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TOK.ILLEGAL_ALPHANUM_IN_DECIMAL),
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
            if (!self.source.is_complete()) {
                const first_exp_byte = self.source.read_next_ascii(NOTICE.ERROR);
                switch (first_exp_byte) {
                    ASC.MINUS => {
                        neg_exp = true;
                    },
                    ASC.PLUS => {},
                    else => self.source.rollback_position(),
                }
            }
        },
        else => {},
    }
    while (!has_exp and !self.source.is_complete()) {
        const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
        switch (byte_x) {
            ASC._0...ASC._9 => {
                sig_int_found = sig_int_found or (byte_x != ASC._0);
                if (sig_int_found) {
                    if (is_float and byte_x == ASC._0) {
                        var trailing_zeroes: i16 = 1;
                        while (!self.source.is_complete()) {
                            const byte_xx = self.source.read_next_ascii(NOTICE.ERROR);
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
                                    self.source.rollback_position();
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
                if (!self.source.is_complete()) {
                    const first_exp_byte = self.source.read_next_ascii(NOTICE.ERROR);
                    switch (first_exp_byte) {
                        ASC.MINUS => {
                            neg_exp = true;
                            slow_parse_buffer[slow_parse_idx] = ASC.MINUS;
                            slow_parse_idx += 1;
                        },
                        ASC.PLUS => {},
                        else => self.source.rollback_position(),
                    }
                }
            },
            ASC.UNDERSCORE => {},
            ASC.A...ASC.Z, ASC.a...ASC.z => return self.collect_illegal_alphanumeric_string_plus_dot(token_builder, TWARN.ILLEGAL_ALPHANUM_IN_DECIMAL),
            else => {
                self.source.rollback_position();
                break;
            },
        }
    }
    var explicit_exp: i64 = 0;
    var exp_sig_digits: u64 = 0;
    var exp_sig_int_found = false;
    while (has_exp and !self.source.is_complete()) {
        const byte_x = self.source.read_next_ascii(NOTICE.ERROR);
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
                self.source.rollback_position();
                break;
            },
        }
    }
    if (!is_float) {
        const exp_mag = @abs(explicit_exp);
        if (explicit_exp > 0) {
            if (explicit_exp > 19 or sig_value > MAX_INT_VALS_FOR_POSITIVE_EXP[exp_mag]) return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_NUMBER_LITERAL_OVERFLOWS_64_BITS, token_builder);
            sig_value *= POWER_10_TABLE[exp_mag];
        } else if (explicit_exp < 0) {
            if (explicit_exp < 19 or sig_value % POWER_10_TABLE[exp_mag] != 0) return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_INTEGER_LITERAL_LOSS_OF_DATA, token_builder);
            sig_value /= POWER_10_TABLE[exp_mag];
        }
        if (negative) {
            if (sig_value > LARGEST_NEG_SIG_VALUE_FOR_I64) return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_INTEGER_LITERAL_NEG_OVERFLOWS_I64, token_builder);
            const ival: i64 = @as(i64, @bitCast(sig_value)) * (-@intFromBool(sig_value != LARGEST_NEG_SIG_VALUE_FOR_I64));
            sig_value = @bitCast(ival);
        }
        token_builder.set_data(sig_value, 0);
        return self.finish_token_kind(TOK.LIT_INTEGER, TWARN.NONE, token_builder);
    } else {
        if (sig_value == 0 or sig_digits == 0) {
            const value: u64 = @bitCast(F64.ZERO);
            token_builder.set_data(value, 0);
            return self.finish_token_kind(TOK.LIT_FLOAT, TWARN.NONE, token_builder);
        }
        const final_exp = implicit_exp + explicit_exp;
        if (sig_digits > F64.MAX_SIG_DIGITS) {
            token_builder.set_data(0, sig_digits);
            return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_FLOAT_TOO_MANY_SIG_DIGITS, token_builder);
        }
        if (final_exp > F64.MAX_EXPONENT or (final_exp == F64.MAX_EXPONENT and sig_value > F64.MAX_SIG_DECIMAL_AT_MAX_EXP)) return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_FLOAT_LITERAL_TOO_LARGE, token_builder);
        if (final_exp < F64.MIN_EXPONENT or (final_exp == F64.MIN_EXPONENT and sig_value < F64.MIN_SIG_DECIMAL_AT_MIN_EXP)) return self.finish_token_kind(TOK.ILLEGAL, TWARN.ILLEGAL_FLOAT_LITERAL_TOO_SMALL, token_builder);
        const value: u64 = @bitCast(Float.parse_float_from_decimal_parts(sig_value, final_exp, negative, slow_parse_buffer, slow_parse_idx));
        token_builder.set_data(value, 0);
        return self.finish_token_kind(TOK.LIT_FLOAT, TWARN.NONE, token_builder);
    }
}

inline fn finish_token(self: *Self, token: TokenBuilder) Token {
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

inline fn finish_token_kind(self: *Self, kind: TOK, token: TokenBuilder) Token {
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

inline fn finish_token_generic_illegal(self: *Self, token: TokenBuilder) Token {
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
