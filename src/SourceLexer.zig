const std = @import("std");
const assert = std.debug.assert;
const List = std.ArrayListUnmanaged;
const Token = @import("./Token.zig");
const TOK = Token.KIND;
const UNI = @import("./Unicode.zig");
const ASC = UNI.ASCII;
const F64 = @import("./Constants.zig").F64;
const POWER_10_TABLE = @import("./Constants.zig").POWER_10_TABLE;
const Float = @import("./ParseFloat.zig");
const IdentBlock = @import("./IdentBlock.zig");
const SourceReader = @import("./SourceReader.zig");
const SourceIdx = SourceReader.SourceIdx;
const TemplateString = @import("./TemplateString.zig");
const SlowParseBuffer = Float.SlowParseBuffer;
const NoticeManager = @import("./NoticeManager.zig");
const Notice = NoticeManager.Notice;
const IdentManager = @import("./IdentManager.zig");
const ParseInteger = @import("./ParseInteger.zig");
const SourceManager = @import("./SourceManager.zig");
const SEVERITY = NoticeManager.SEVERITY;
const NOTICE = NoticeManager.KIND;

const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");

const ProgramROM = @import("./ProgramROM.zig");

const Self = @This();

reader: SourceReader,
source_key: u16,
token_list: Token.TokenBuf.List,

pub fn new(source: []const u8, source_key: u16) Self {
    return Self{
        .source_key = source_key,
        .reader = SourceReader.new(source_key, source),
        .token_list = Token.TokenBuf.List.create(),
    };
}

pub fn parse_source(self: *Self) void {
    var cont = true;
    while (cont) {
        const token = self.next_token();
        if (token.kind == TOK.EOF) cont = false;
        self.token_list.append(token);
    }
}

pub fn next_token(self: *Self) Token {
    while (self.reader.curr.pos < self.reader.data.len) {
        const start = self.reader.curr.pos;
        if (self.reader.data[self.reader.curr.pos] == ASC.HASH) {
            self.reader.skip_until_byte_match(ASC.NEWLINE);
        }
        self.reader.skip_whitespace();
        const end = self.reader.curr.pos;
        if (start == end) break;
    }
    if (self.reader.curr.pos >= self.reader.data.len) {
        var token = TokenBuilder.new(self.source_key, &self.reader);
        return self.finish_token_kind(TOK.EOF, &token);
    }
    var token_builder = TokenBuilder.new(self.source_key, &self.reader);
    var token = &token_builder;
    const byte_1 = self.reader.read_next_ascii(token);
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
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.R_SQUARE => return self.finish_token_kind(TOK.SLICE, token),
                    ASC.PLUS => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.R_SQUARE => return self.finish_token_kind(TOK.LIST, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_generic_illegal(token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.L_SQUARE, token);
        },
        ASC.R_SQUARE => return self.finish_token_kind(TOK.R_SQUARE, token),
        ASC.QUESTION => return self.finish_token_kind(TOK.MAYBE_NONE, token),
        ASC.PERIOD => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.PERIOD => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.PERIOD => return self.finish_token_kind(TOK.RANGE_INCLUDE_BOTH, token),
                                ASC.PIPE => return self.finish_token_kind(TOK.RANGE_EXCLUDE_END, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_generic_illegal(token);
                    },
                    ASC.AT_SIGN => return self.finish_token_kind(TOK.DEREREFENCE, token),
                    ASC.QUESTION => return self.finish_token_kind(TOK.ACCESS_MAYBE_NONE, token),
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.ACCESS, token);
        },
        ASC.EQUALS => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.EQUALS, token),
                    ASC.MORE_THAN => return self.finish_token_kind(TOK.FAT_ARROW, token),
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.ASSIGN, token);
        },
        ASC.LESS_THAN => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.LESS_THAN_EQUAL, token),
                    ASC.LESS_THAN => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.SHIFT_L_ASSIGN, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.SHIFT_L, token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.LESS_THAN, token);
        },
        ASC.MORE_THAN => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MORE_THAN_EQUAL, token),
                    ASC.LESS_THAN => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.SHIFT_R_ASSIGN, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.SHIFT_R, token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MORE_THAN, token);
        },
        ASC.EXCLAIM => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.NOT_EQUAL, token),
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.LOGIC_NOT, token);
        },
        ASC.PLUS => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.ADD_ASSIGN, token),
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.ADD, token);
        },
        ASC.MINUS => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.SUB_ASSIGN, token),
                    ASC._0...ASC._9 => return self.parse_number_literal(token, true),
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.SUB, token);
        },
        ASC.ASTERISK => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MULT_ASSIGN, token),
                    ASC.ASTERISK => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.POWER_ASSIGN, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.POWER, token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MULT, token);
        },
        ASC.F_SLASH => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.DIV_ASSIGN, token),
                    ASC.F_SLASH => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.ROOT_ASSIGN, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.ROOT, token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.DIV, token);
        },
        ASC.PERCENT => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.MODULO_ASSIGN, token),
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.MODULO, token);
        },
        ASC.AMPER => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_AND_ASSIGN, token),
                    ASC.AMPER => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_AND_ASSIGN, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.LOGIC_AND, token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_AND, token);
        },
        ASC.PIPE => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_OR_ASSIGN, token),
                    ASC.PERIOD => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.PERIOD => {
                                    if (self.reader.data.len > self.reader.curr.pos) {
                                        const byte_4 = self.reader.read_next_ascii(token);
                                        switch (byte_4) {
                                            ASC.PIPE => return self.finish_token_kind(TOK.RANGE_EXCLUDE_BOTH, token),
                                            else => self.reader.rollback_position(),
                                        }
                                    }
                                    return self.finish_token_kind(TOK.RANGE_EXCLUDE_BEGIN, token);
                                },
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_generic_illegal(token);
                    },
                    ASC.PIPE => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_OR_ASSIGN, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.LOGIC_OR, token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_OR, token);
        },
        ASC.CARET => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.EQUALS => return self.finish_token_kind(TOK.BIT_XOR_ASSIGN, token),
                    ASC.CARET => {
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const byte_3 = self.reader.read_next_ascii(token);
                            switch (byte_3) {
                                ASC.EQUALS => return self.finish_token_kind(TOK.LOGIC_XOR_ASSIGN, token),
                                else => self.reader.rollback_position(),
                            }
                        }
                        return self.finish_token_kind(TOK.LOGIC_XOR, token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_kind(TOK.BIT_XOR, token);
        },
        ASC.TILDE => return self.finish_token_kind(TOK.BIT_NOT, token),
        ASC._0...ASC._9 => return self.parse_number_literal(token, false),
        ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE => {
            self.reader.rollback_position();
            const ident_start = self.reader.curr.pos;
            const ident_result = IdentBlock.parse_from_source(&self.reader, token, false);
            const ident_end = self.reader.curr.pos;
            if (token.kind == TOK.ILLEGAL) return self.finish_token(token);
            if (ident_result.len <= Token.LONGEST_KEYWORD) {
                for (Token.KW_U64_SLICES_BY_LEN[ident_result.len], Token.KW_TOKEN_SLICES_BY_LEN[ident_result.len], Token.KW_IMPLICIT_SLICES_BY_LEN[ident_result.len]) |keyword, kind, implicit| {
                    if (ident_result.ident.data[0] == keyword) {
                        token.set_data(implicit, 0, 0);
                        return self.finish_token_kind(kind, token);
                    }
                }
            }
            const ident_key = Global.ident_manager.get_or_create_ident_key(ident_result.ident, self.reader.data[ident_start..ident_end]);
            token.set_data(ident_key, 1, 0);
            return self.finish_token_kind(TOK.IDENT, token);
        },
        ASC.DOLLAR => {
            if (self.reader.data.len > self.reader.curr.pos) {
                const byte_2 = self.reader.read_next_ascii(token);
                switch (byte_2) {
                    ASC.DUBL_QUOTE => {
                        TemplateString.TemplateStringBuilder.parse_from_source(&self.reader, token);
                        return self.finish_token(token);
                    },
                    else => self.reader.rollback_position(),
                }
            }
            return self.finish_token_generic_illegal(token);
        },
        ASC.DUBL_QUOTE => return self.collect_string(token, true),
        else => return self.finish_token_generic_illegal(token),
    }
}

fn parse_number_literal(self: *Self, token: *TokenBuilder, comptime negative: bool) Token {
    const peek_next = self.reader.peek_next_byte();
    switch (peek_next) {
        ASC.b => {
            self.reader.curr.advance_one_col(1);
            ParseInteger.parse_base2_compatable_integer(ParseInteger.BASE.BIN, negative, &self.reader, token);
        },
        ASC.o => {
            self.reader.curr.advance_one_col(1);
            ParseInteger.parse_base2_compatable_integer(ParseInteger.BASE.OCT, negative, &self.reader, token);
        },
        ASC.x => {
            self.reader.curr.advance_one_col(1);
            ParseInteger.parse_base2_compatable_integer(ParseInteger.BASE.HEX, negative, &self.reader, token);
        },
        else => @panic("parsing decimal numbers not imlemented!"), // HACK just deal with the simple cases first
    }
    return self.finish_token(token);
}

fn collect_string(self: *Self, token: *TokenBuilder, comptime needs_terminal: bool) Token {
    const token_rom = &Global.token_rom;
    var kind = TOK.LIT_STRING;
    var string = Global.U8BufSmall.List.create();
    defer string.release();
    var is_escape = false;
    var has_terminal = false;
    parseloop: while (self.reader.data.len > self.reader.curr.pos) {
        const char = self.reader.read_next_utf8_char(token);
        switch (is_escape) {
            true => {
                is_escape = false;
                switch (char.code) {
                    ASC.n => {
                        string.append(ASC.NEWLINE);
                    },
                    ASC.t => {
                        string.append(ASC.H_TAB);
                    },
                    ASC.r => {
                        string.append(ASC.CR);
                    },
                    ASC.B_SLASH, ASC.DUBL_QUOTE, ASC.BACKTICK => {
                        string.append(char.bytes[0]);
                    },
                    ASC.o => {
                        const utf8 = self.reader.read_next_n_bytes_as_octal_escape(3, token);
                        string.append_slice(utf8.bytes[0..utf8.len]);
                    },
                    ASC.x => {
                        const utf8 = self.reader.read_next_n_bytes_as_hex_escape(2, token);
                        string.append_slice(utf8.bytes[0..utf8.len]);
                    },
                    ASC.u => {
                        const utf8 = self.reader.read_next_n_bytes_as_hex_escape(4, token);
                        string.append_slice(utf8.bytes[0..utf8.len]);
                    },
                    ASC.U => {
                        const utf8 = self.reader.read_next_n_bytes_as_hex_escape(8, token);
                        string.append_slice(utf8.bytes[0..utf8.len]);
                    },
                    else => {
                        token.attach_notice_here(NOTICE.illegal_string_escape_sequence, SEVERITY.ERROR, &self.reader);
                        kind = TOK.ILLEGAL;
                        string.append_slice(UNI.REP_CHAR_BYTES[0..UNI.REP_CHAR_LEN]);
                    },
                }
            },
            else => {
                switch (char.code) {
                    ASC.NEWLINE => {
                        string.append(ASC.NEWLINE);
                        self.reader.skip_whitespace_except_newline();
                        if (self.reader.data.len > self.reader.curr.pos) {
                            const next_byte = self.reader.read_next_ascii(token);
                            switch (next_byte) {
                                ASC.BACKTICK => {},
                                ASC.NEWLINE => {
                                    token.attach_notice_here(NOTICE.runaway_multiline_string, SEVERITY.ERROR, &self.reader);
                                    return self.finish_token_kind(TOK.ILLEGAL, token);
                                },
                                else => {
                                    token.attach_notice_here(NOTICE.non_whitespace_before_backtick_in_multiline_string, SEVERITY.ERROR, &self.reader);
                                    kind = TOK.ILLEGAL;
                                },
                            }
                        } else {
                            token.attach_notice_here(NOTICE.source_ended_before_string_terminated, SEVERITY.ERROR, &self.reader);
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
                        string.append_slice(char.bytes[0..char.len]);
                    },
                }
            },
        }
    }
    if (needs_terminal and !has_terminal) {
        token.attach_notice_here(NOTICE.source_ended_before_string_terminated, SEVERITY.ERROR, &self.reader);
        return self.finish_token_kind(TOK.ILLEGAL, token);
    }
    token_rom.prepare_space_for_write(string.len, 1);
    const ptr = token_rom.data.len;
    token_rom.write_slice(u8, string.slice());
    token.set_data(ptr, @intCast(string.len), 0);
    return self.finish_token_kind(TOK.LIT_STRING, token);
}

fn finish_token(self: *Self, token: *TokenBuilder) Token {
    if (token.has_notice) {
        const notice = token.extract_notice(&self.reader);
        Global.notice_manager.add_notice(notice);
    }
    return Token{
        .kind = token.kind,
        .source_key = token.source_key,
        .row_start = token.start_loc.row,
        .row_end = self.reader.curr.row,
        .col_start = token.start_loc.col,
        .col_end = self.reader.curr.col,
        .data_val_or_ptr = token.data_val_or_ptr,
        .data_len = token.data_len,
        .data_extra = token.data_extra,
    };
}

fn finish_token_kind(self: *Self, kind: TOK, token: *TokenBuilder) Token {
    if (token.has_notice) {
        const notice = token.extract_notice(&self.reader);
        Global.notice_manager.add_notice(notice);
    }
    return Token{
        .kind = kind,
        .source_key = token.source_key,
        .row_start = token.start_loc.row,
        .row_end = self.reader.curr.row,
        .col_start = token.start_loc.col,
        .col_end = self.reader.curr.col,
        .data_val_or_ptr = token.data_val_or_ptr,
        .data_len = token.data_len,
        .data_extra = token.data_extra,
    };
}

fn finish_token_generic_illegal(self: *Self, token: *TokenBuilder) Token {
    token.kind = TOK.ILLEGAL;
    token.attach_notice_here(NOTICE.generic_illegal_token, SEVERITY.ERROR, &self.reader);
    const notice = token.extract_notice(&self.reader);
    Global.notice_manager.add_notice(notice);
    return Token{
        .kind = token.kind,
        .source_key = token.source_key,
        .row_start = token.start_loc.row,
        .row_end = self.reader.curr.row,
        .col_start = token.start_loc.col,
        .col_end = self.reader.curr.col,
        .data_val_or_ptr = token.data_val_or_ptr,
        .data_len = token.data_len,
        .data_extra = token.data_extra,
    };
}

pub const TokenBuilder = struct {
    source_key: u16,
    kind: TOK,
    start_loc: SourceIdx,
    data_val_or_ptr: u64,
    data_len: u32,
    data_extra: u8,
    //
    has_notice: bool,
    notice_row: u32,
    notice_row_pos: u32,
    notice_kind: NOTICE,
    notice_severity: SEVERITY,
    notice_infraction_col: u32,

    pub fn new(source_key: u16, source: *const SourceReader) TokenBuilder {
        return TokenBuilder{
            .source_key = source_key,
            .kind = TOK.ILLEGAL,
            .start_loc = source.curr,
            .data_val_or_ptr = 0,
            .data_len = 0,
            .data_extra = 0,
            //
            .has_notice = false,
            .notice_row = 0,
            .notice_row_pos = 0,
            .notice_kind = NOTICE.generic_illegal_token,
            .notice_severity = SEVERITY.INFO,
            .notice_infraction_col = 0,
        };
    }

    pub fn blank() TokenBuilder {
        return TokenBuilder{
            .source_key = 0,
            .kind = TOK.ILLEGAL,
            .start_loc = 0,
            .data_val_or_ptr = 0,
            .data_len = 0,
            .data_extra = 0,
            //
            .has_notice = false,
            .notice_row = 0,
            .notice_row_pos = 0,
            .notice_kind = NOTICE.generic_illegal_token,
            .notice_severity = SEVERITY.INFO,
            .notice_infraction_col = 0,
        };
    }

    pub inline fn set_start(self: *TokenBuilder, source: *const SourceReader) void {
        self.start_loc = source.curr;
    }

    pub inline fn set_data(self: *TokenBuilder, val_or_ptr: u64, len: u32, extra: u8) void {
        self.data_val_or_ptr = val_or_ptr;
        self.data_len = len;
        self.data_extra = extra;
    }

    pub fn attach_notice_here(self: *TokenBuilder, notice: NOTICE, severity: SEVERITY, source: *const SourceReader) void {
        if (self.has_notice and @intFromEnum(self.notice_severity) >= @intFromEnum(severity)) return;
        self.has_notice = true;
        self.notice_row = source.curr.row;
        self.notice_row_pos = source.curr.row_pos;
        self.notice_kind = notice;
        self.notice_severity = severity;
        self.notice_infraction_col = source.curr.col;
    }

    pub fn attach_notice_at_token_start(self: *TokenBuilder, notice: NOTICE, severity: SEVERITY) void {
        if (self.has_notice and @intFromEnum(self.notice_severity) >= @intFromEnum(severity)) return;
        self.has_notice = true;
        self.notice_row = self.start_loc.row;
        self.notice_row_pos = self.start_loc.row_pos;
        self.notice_kind = notice;
        self.notice_severity = severity;
        self.notice_infraction_col = self.start_loc.col;
    }

    pub fn extract_notice(self: *const TokenBuilder, source: *const SourceReader) Notice {
        return Notice{
            .kind = self.notice_kind,
            .severity = self.notice_severity,
            .row = self.notice_row,
            .row_byte_pos = self.notice_row_pos,
            .source_key = self.source_key,
            .col_start = if (self.notice_row == self.start_loc.row) self.start_loc.col else 0,
            .col_infraction = self.notice_infraction_col,
            .col_end = if (self.notice_row == source.curr.row) source.curr.col else 0,
        };
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
