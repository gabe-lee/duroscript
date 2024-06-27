const std = @import("std");
const assert = std.debug.assert;
const UNI = @import("./Unicode.zig");
const U = UNI;
const ASC = UNI.ASCII;
const TokenBuilder = @import("./SourceLexer.zig").TokenBuilder;
const TOK = @import("./Token.zig").KIND;
const NoticeManager = @import("./NoticeManager.zig");
const SEVERITY = NoticeManager.SEVERITY;
const NOTICE = NoticeManager.KIND;
const debug = std.debug.print;

const Self = @This();

data: []const u8,
key: u16,
curr: SourceIdx,
prev: SourceIdx,
rolled_back_to_prev: bool,
next_utf8: ?UTF8_Read_Result,

pub const SourceIdx = struct {
    pos: u32,
    col: u32,
    row: u32,
    row_pos: u32,

    pub inline fn new() SourceIdx {
        return SourceIdx{
            .pos = 0,
            .col = 1,
            .row = 1,
            .row_pos = 0,
        };
    }

    pub inline fn advance_one_col(self: *SourceIdx, bytes: u32) void {
        self.pos += bytes;
        self.col += 1;
    }

    pub inline fn advance_n_cols(self: *SourceIdx, bytes: u32, cols: u32) void {
        self.pos += bytes;
        self.col += cols;
    }

    pub inline fn advance_newline(self: *SourceIdx) void {
        self.pos += 1;
        self.col = 0;
        self.row += 1;
        self.row_pos = self.pos;
    }
};

pub const SourceRange = struct {
    source_key: u16,
    start: SourceIdx,
    end: SourceIdx,

    pub fn new(source_key: u16, start: SourceIdx, end: SourceIdx) SourceRange {
        return SourceRange{
            .source_key = source_key,
            .start = start,
            .end = end,
        };
    }
};

pub inline fn new(source_key: u16, source: []const u8) Self {
    return Self{
        .data = source,
        .source_key = source_key,
        .curr = SourceIdx.new(),
        .prev = SourceIdx.new(),
        .rolled_back_to_prev = false,
        .next_utf8 = null,
    };
}

inline fn swap_curr_and_prev(self: *Self) void {
    const old_prev = self.prev;
    self.prev = self.curr;
    self.curr = old_prev;
}

pub fn skip_until_byte_match(self: *Self, comptime match_byte: u8) void {
    self.rolled_back_to_prev = false;
    while (self.data.len > self.curr.pos) {
        const byte = self.data[self.curr.pos];
        switch (byte) {
            ASC.NEWLINE => {
                self.curr.pos += 1;
                self.curr.col = 0;
                self.curr.row += 1;
                self.curr.row_pos = self.curr.pos;
            },
            else => {
                self.curr.pos += 1;
                self.curr.col += 1;
            },
        }
        if (byte == match_byte) {
            break;
        }
    }
    return;
}

pub fn skip_alpha_underscore(self: *Self) void {
    self.rolled_back_to_prev = false;
    while (self.data.len > self.curr.pos) {
        const byte = self.data[self.curr.pos];
        switch (byte) {
            ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE => {
                self.curr.pos += 1;
                self.curr.col += 1;
            },
            else => break,
        }
    }
    return;
}

pub fn skip_whitespace(self: *Self) void {
    self.rolled_back_to_prev = false;
    while (self.data.len > self.curr.pos) {
        const byte = self.data[self.curr.pos];
        switch (byte) {
            ASC.SPACE, ASC.H_TAB, ASC.CR => {
                self.curr.pos += 1;
                self.curr.col += 1;
            },
            ASC.NEWLINE => {
                self.curr.pos += 1;
                self.curr.col = 0;
                self.curr.row += 1;
                self.curr.row_pos = self.curr.pos;
            },
            else => break,
        }
    }
    return;
}

pub fn skip_whitespace_except_newline(self: *Self) void {
    self.rolled_back_to_prev = false;
    while (self.data.len > self.curr.pos) {
        const byte = self.data[self.curr.pos];
        switch (byte) {
            ASC.SPACE, ASC.H_TAB, ASC.CR => {
                self.curr.pos += 1;
                self.curr.col += 1;
            },
            else => break,
        }
    }
    return;
}

pub fn skip_illegal_alphanumeric_string(self: *Self) void {
    self.rolled_back_to_prev = false;
    while (self.data.len > self.curr.pos) {
        const byte = self.data[self.curr.pos];
        switch (byte) {
            ASC._0...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE => {
                self.curr.pos += 1;
                self.curr.col += 1;
            },
            else => break,
        }
    }
    return;
}

pub fn skip_illegal_alphanumeric_string_plus_dot(self: *Self) void {
    self.rolled_back_to_prev = false;
    while (self.data.len > self.curr.pos) {
        const byte = self.data[self.curr.pos];
        switch (byte) {
            ASC._0...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.UNDERSCORE, ASC.PERIOD => {
                self.curr.pos += 1;
                self.curr.col += 1;
            },
            else => break,
        }
    }
    return;
}

pub fn rollback_position(self: *Self) void {
    assert(self.curr.pos > self.prev.pos);
    self.swap_curr_and_prev();
    self.rolled_back_to_prev = true;
}

pub fn read_next_byte(self: *Self) u8 {
    assert(self.data.len > self.curr.pos);
    const val: u8 = self.data[self.curr.pos];
    self.rolled_back_to_prev = false;
    self.prev = self.curr;
    if (val == ASC.NEWLINE) {
        self.curr.advance_newline();
    } else {
        self.curr.advance_one_col(1);
    }
    self.next_utf8 = if (val <= ASC.DEL) UTF8_Read_Result.new(val, [4]u8{ val, 0, 0, 0 }, 1) else null;
    return val;
}

pub inline fn peek_next_byte(self: *Self) u8 {
    assert(self.data.len > self.curr.pos);
    return self.data[self.curr.pos];
}

pub fn read_next_ascii(self: *Self, token: *TokenBuilder) u8 {
    assert(self.data.len > self.curr.pos);
    const val: u8 = self.data[self.curr.pos];
    self.rolled_back_to_prev = false;
    self.prev = self.curr;
    if (val > UNI.MAX_1_BYTE_CODE_POINT) {
        token.attach_notice_here(NOTICE.illegal_ascii_character_in_source, SEVERITY.ERROR, self);
        token.kind = TOK.ILLEGAL;
    }
    if (val == ASC.NEWLINE) {
        self.curr.advance_newline();
    } else {
        self.curr.advance_one_col(1);
    }
    self.next_utf8 = if (val <= ASC.DEL) UTF8_Read_Result.new(val, [4]u8{ val, 0, 0, 0 }, 1) else null;
    return val;
}

pub const UTF8_Read_Result = struct {
    code: u32,
    bytes: [4]u8,
    len: u8,

    pub fn new(code: u32, bytes: [4]u8, len: u8) UTF8_Read_Result {
        return UTF8_Read_Result{
            .code = code,
            .bytes = bytes,
            .len = len,
        };
    }

    pub fn replace_char() UTF8_Read_Result {
        return UTF8_Read_Result{
            .code = U.REP_CHAR,
            .bytes = U.REP_CHAR_BYTES,
            .len = U.REP_CHAR_LEN,
        };
    }
};

pub fn read_next_utf8_char(self: *Self, token: *TokenBuilder) UTF8_Read_Result {
    if (self.rolled_back_to_prev and self.next_utf8 != null) {
        self.rolled_back_to_prev = false;
        self.swap_curr_and_prev();
        return self.next_utf8.?;
    }
    assert(self.data.len > self.curr.pos);
    self.prev = self.curr;
    const utf8_len: u8 = switch (self.data[self.curr.pos]) {
        U.BYTE_1_OF_1_MIN...U.BYTE_1_OF_1_MAX => 1,
        U.BYTE_1_OF_2_MIN...U.BYTE_1_OF_2_MAX => 2,
        U.BYTE_1_OF_3_MIN...U.BYTE_1_OF_3_MAX => 3,
        U.BYTE_1_OF_4_MIN...U.BYTE_1_OF_4_MAX => 4,
        U.CONT_BYTE_MIN...U.CONT_BYTE_MAX => {
            self.curr.advance_one_col(1);
            token.attach_notice_here(NOTICE.utf8_unexpected_continue_byte, SEVERITY.ERROR, self);
            token.kind = TOK.ILLEGAL;
            self.next_utf8 = UTF8_Read_Result.replace_char();
            return self.next_utf8;
        },
        else => {
            self.curr.advance_one_col(1);
            token.attach_notice_here(NOTICE.utf8_illegal_byte, SEVERITY.ERROR, self);
            token.kind = TOK.ILLEGAL;
            self.next_utf8 = UTF8_Read_Result.replace_char();
            return self.next_utf8;
        },
    };
    switch (utf8_len) {
        1 => {
            if (self.data[self.curr.pos] == ASC.NEWLINE) {
                self.curr.advance_newline();
            } else {
                self.curr.advance_one_col(1);
            }
            const bytes = [4]u8{ self.data[self.prev.pos], 0, 0, 0 };
            self.next_utf8 = UTF8_Read_Result.new(bytes[0], bytes, 1);
            return self.next_utf8;
        },
        2 => {
            if (self.data.len - self.curr.pos < 2) {
                self.curr.advance_one_col(1);
                token.attach_notice_here(NOTICE.utf8_multibyte_char_source_ended_early, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.data[self.curr.pos + 1] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(1);
                token.attach_notice_here(NOTICE.utf8_missing_or_malformed_continue_byte, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const code: u32 =
                (@as(u32, (self.data[self.curr.pos] & U.BYTE_1_OF_2_VAL_MASK)) << 6) |
                @as(u32, (self.data[self.curr.pos + 1] & U.CONT_BYTE_VAL_MASK));
            if (code < U.MIN_2_BYTE_CODE_POINT) {
                self.curr.advance_one_col(2);
                token.attach_notice_here(NOTICE.utf8_unexpected_continue_byte, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const bytes = [4]u8{ self.data[self.curr.pos], self.data[self.curr.pos + 1], 0, 0 };
            self.next_utf8 = UTF8_Read_Result.new(code, bytes, 2);
            return self.next_utf8;
        },
        3 => {
            if (self.data.len - self.curr.pos < 3) {
                self.curr.advance_one_col(1);
                token.attach_notice_here(NOTICE.utf8_multibyte_char_source_ended_early, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.data[self.curr.pos + 1] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(1);
                token.attach_notice_here(NOTICE.utf8_missing_or_malformed_continue_byte, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.data[self.curr.pos + 2] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(2);
                token.attach_notice_here(NOTICE.utf8_missing_or_malformed_continue_byte, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const code: u32 =
                (@as(u32, (self.data[self.curr.pos] & U.BYTE_1_OF_3_VAL_MASK)) << 12) |
                (@as(u32, (self.data[self.curr.pos + 1] & U.CONT_BYTE_VAL_MASK)) << 6) |
                @as(u32, (self.data[self.curr.pos + 2] & U.CONT_BYTE_VAL_MASK));
            if ((code >= U.MIN_SURG_PAIR_CODE_POINT) or (code <= U.MAX_SURG_PAIR_CODE_POINT)) {
                self.curr.advance_one_col(3);
                token.attach_notice_here(NOTICE.utf8_illegal_codepoint, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (code < U.MIN_3_BYTE_CODE_POINT) {
                self.curr.advance_one_col(3);
                token.attach_notice_here(NOTICE.utf8_overlong_encoding, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const bytes = [4]u8{ self.data[self.curr.pos], self.data[self.curr.pos + 1], self.data[self.curr.pos + 2], 0 };
            self.next_utf8 = UTF8_Read_Result.new(code, bytes, 3);
            return self.next_utf8;
        },
        4 => {
            if (self.data.len - self.curr.pos < 4) {
                self.curr.advance_one_col(1);
                token.attach_notice_here(NOTICE.utf8_multibyte_char_source_ended_early, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.data[self.curr.pos + 1] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(1);
                token.attach_notice_here(NOTICE.utf8_missing_or_malformed_continue_byte, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.data[self.curr.pos + 2] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(2);
                token.attach_notice_here(NOTICE.utf8_missing_or_malformed_continue_byte, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.data[self.curr.pos + 3] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(3);
                token.attach_notice_here(NOTICE.utf8_missing_or_malformed_continue_byte, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const code: u32 =
                (@as(u32, (self.data[self.curr.pos] & U.BYTE_1_OF_3_VAL_MASK)) << 18) |
                (@as(u32, (self.data[self.curr.pos + 1] & U.CONT_BYTE_VAL_MASK)) << 12) |
                (@as(u32, (self.data[self.curr.pos + 2] & U.CONT_BYTE_VAL_MASK)) << 6) |
                @as(u32, (self.data[self.curr.pos + 3] & U.CONT_BYTE_VAL_MASK));
            if (code > U.MAX_4_BYTE_CODE_POINT) {
                self.curr.advance_one_col(4);
                token.attach_notice_here(NOTICE.utf8_illegal_codepoint, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (code < U.MIN_4_BYTE_CODE_POINT) {
                self.curr.advance_one_col(4);
                token.attach_notice_here(NOTICE.utf8_overlong_encoding, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const bytes = [4]u8{ self.data[self.curr.pos], self.data[self.curr.pos + 1], self.data[self.curr.pos + 2], self.data[self.curr.pos + 3] };
            self.next_utf8 = UTF8_Read_Result.new(code, bytes, 4);
            return self.next_utf8;
        },
        else => unreachable,
    }
}

pub fn read_next_n_bytes_as_octal_escape(self: *Self, comptime n: comptime_int, token: *TokenBuilder) UTF8_Read_Result {
    self.rolled_back_to_prev = false;
    self.prev = self.curr;
    if (self.data.len - self.curr.pos < n) {
        token.attach_notice_here(NOTICE.invalid_octal_escape_sequence, SEVERITY.ERROR, self);
        token.kind = TOK.ILLEGAL;
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    var code: u8 = 0;
    var bit: u8 = n * 3;
    for (0..n) |i| {
        bit -= 3;
        const byte = self.data[self.curr.pos + i];
        const val = switch (byte) {
            ASC._0...ASC._7 => byte - ASC._0,
            else => {
                token.attach_notice_here(NOTICE.invalid_octal_escape_sequence, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.curr.advance_n_cols(@intCast(i), @intCast(i));
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            },
        };
        code |= val << @intCast(bit);
    }
    if (!U.is_valid_codepoint(code)) {
        token.attach_notice_here(NOTICE.utf8_illegal_codepoint, SEVERITY.ERROR, self);
        token.kind = TOK.ILLEGAL;
        self.curr.advance_n_cols(n, n);
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    const utf8 = U.encode_valid_codepoint(code);
    self.curr.advance_n_cols(n, n);
    self.next_utf8 = UTF8_Read_Result.new(code, utf8.code_bytes, utf8.code_len);
    return self.next_utf8;
}

pub fn read_next_n_bytes_as_hex_escape(self: *Self, comptime n: comptime_int, token: *TokenBuilder) UTF8_Read_Result {
    self.rolled_back_to_prev = false;
    self.prev = self.curr;
    if (self.data.len - self.curr.pos < n) {
        token.attach_notice_here(NOTICE.invalid_short_hexidecimal_escape_sequence, SEVERITY.ERROR, self);
        token.kind = TOK.ILLEGAL;
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    var code: u32 = 0;
    var bit: u8 = n * 4;
    for (0..n) |i| {
        bit -= 4;
        const byte = self.data[self.curr.pos + i];
        const val: u32 = switch (byte) {
            ASC._0...ASC._9 => byte - ASC._0,
            ASC.A...ASC.F => (byte - ASC.A) + 10,
            ASC.a...ASC.f => (byte - ASC.a) + 10,
            else => {
                token.attach_notice_here(NOTICE.invalid_short_hexidecimal_escape_sequence, SEVERITY.ERROR, self);
                token.kind = TOK.ILLEGAL;
                self.curr.advance_n_cols(@intCast(i), @intCast(i));
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            },
        };
        code |= val << @intCast(bit);
    }
    if (!U.is_valid_codepoint(code)) {
        token.attach_notice_here(NOTICE.utf8_illegal_codepoint, SEVERITY.ERROR, self);
        token.kind = TOK.ILLEGAL;
        self.curr.advance_n_cols(n, n);
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    const utf8 = U.encode_valid_codepoint(code);
    self.curr.advance_n_cols(n, n);
    self.next_utf8 = UTF8_Read_Result.new(code, utf8.code_bytes, utf8.code_len);
    return self.next_utf8;
}
