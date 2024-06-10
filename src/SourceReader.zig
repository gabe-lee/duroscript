const std = @import("std");
const assert = std.debug.assert;
const UNI = @import("./Unicode.zig");
const U = UNI;
const ASC = UNI.ASCII;
const NoticeManager = @import("./NoticeManager.zig");
const NOTICE = NoticeManager.KIND;
const nkind_string = NoticeManager.kind_string;

const Self = @This();

source: []const u8,
source_name: []const u8,
curr: SourceIdx,
prev: SourceIdx,
rolled_back_to_prev: bool,
next_utf8: UTF8_Read_Result,

pub const SourceIdx = struct {
    pos: u32,
    col: u32,
    row: u32,

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
    }
};

pub const SourceRange = struct {
    source_name: []const u8,
    start: SourceIdx,
    end: SourceIdx,

    pub fn new(filename: []const u8, start: SourceIdx, end: SourceIdx) SourceRange {
        return SourceRange{
            .filename = filename,
            .start = start,
            .end = end,
        };
    }
};

pub inline fn new(filename: []const u8, source: []const u8) Self {
    return Self{
        .source = source,
        .filename = filename,
        .curr = SourceIdx{
            .pos = 0,
            .col = 0,
            .row = 0,
        },
        .prev = SourceIdx{
            .pos = 0,
            .col = 0,
            .row = 0,
        },
        .rolled_back_to_prev = false,
        .next_utf8_result = UTF8_Read_Result{
            .code = 0,
            .bytes = [4]u8{ 0, 0, 0, 0 },
            .len = 0,
        },
    };
}

inline fn swap_curr_and_prev(self: *Self) void {
    const old_prev = self.prev;
    self.prev = self.curr;
    self.curr = old_prev;
}

pub inline fn is_complete(self: *Self) bool {
    return self.curr.pos >= self.source.len;
}

pub fn skip_until_byte_match(self: *Self, comptime match_byte: u8) void {
    while (self.source.len > self.curr.pos) {
        const byte = self.source[self.curr.pos];
        switch (byte) {
            ASC.NEWLINE => {
                self.curr.pos += 1;
                self.curr.col = 0;
                self.curr.row += 1;
                self.prev_is_next = false;
            },
            else => {
                self.curr.pos += 1;
                self.curr.col += 1;
                self.prev_is_next = false;
            },
        }
        if (byte == match_byte) {
            break;
        }
    }
    return;
}

pub fn skip_whitespace(self: *Self) void {
    while (self.source.len > self.curr.pos) {
        const byte = self.source[self.curr.pos];
        switch (byte) {
            ASC.SPACE, ASC.H_TAB, ASC.CR => {
                self.curr.pos += 1;
                self.curr.col += 1;
                self.prev_is_next = false;
            },
            ASC.NEWLINE => {
                self.curr.pos += 1;
                self.curr.col = 0;
                self.curr.row += 1;
                self.prev_is_next = false;
            },
            else => break,
        }
    }
    return;
}

pub fn skip_whitespace_except_newline(self: *Self) void {
    while (self.source.len > self.curr.pos) {
        const byte = self.source[self.curr.pos];
        switch (byte) {
            ASC.SPACE, ASC.H_TAB, ASC.CR => {
                self.curr.pos += 1;
                self.curr.col += 1;
                self.prev_is_next = false;
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

pub fn add_illegal_string_escape_sequence_notice(self: *Self, comptime notice_kind: NOTICE, code: u32) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid string escape sequence, found unknown escape sequence (possibly a valid escape sequence in an invalid context)
        \\  EXPECTED: escape == '\\n', '\\t', '\\r', '\\o', '\\x', '\\u', '\\U', or context-specific escapes '\\{', '\\}', '\\"', '\\'', '\\`'
        \\  FOUND:    escape == '\\{u}'
    , .{code});
}

pub fn add_illegal_char_multiline_notice(self: *Self, comptime notice_kind: NOTICE, byte: u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid multiline string (newlines have ONLY non-linebreak whitespace before first ` char), found invalid byte before `
        \\  EXPECTED: string == "......
        \\      `........."
        \\  FOUND:    string == "......
        \\      {u}........."
    , .{byte});
}

pub fn add_runaway_multiline_notice(self: *Self, comptime notice_kind: NOTICE) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid multiline string (newlines have ` char before any additional newlines), found second newline before `
        \\  EXPECTED: string == "......
        \\      `
        \\      `......."
        \\  FOUND:    string == "......
        \\      
        \\      .........
    , .{});
}

pub fn add_source_end_before_string_end_notice(self: *Self, comptime notice_kind: NOTICE) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected string termination before end of source file, reached end of source without termination
        \\  EXPECTED: string == "......"
        \\  FOUND:    string == "......(EOF)
    , .{});
}

pub fn add_illegal_ascii_notice(self: *Self, comptime notice_kind: NOTICE, byte: u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected only 1-byte UTF-8 (ASCII) characters in this context, multi-byte UTF-8 not allowed
        \\  EXPECTED: byte <= 127 (0x7F)
        \\  FOUND:    byte == {d} ({h})
    , .{ byte, byte });
}

pub fn read_next_ascii(self: *Self, comptime notice_kind: NOTICE) u8 {
    assert(self.source.len > self.curr.pos);
    var val: u8 = self.source[self.curr.pos];
    self.rolled_back_to_prev = false;
    self.prev = self.curr;
    if (val == ASC.NEWLINE) {
        self.curr.advance_newline();
    } else {
        self.curr.advance_one_col(1);
    }
    if (val > UNI.MAX_1_BYTE_CODE_POINT) {
        self.add_illegal_ascii_notice(notice_kind, val);
        val = ASC.DEL;
    }
    self.next_utf8 = UTF8_Read_Result.new(val, [4]u8{ val, 0, 0, 0 }, 1);
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

pub fn add_unexpected_continue_byte_notice(self: *Self, comptime notice_kind: NOTICE, byte: u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid UTF-8 first-byte pattern in first byte position, found UTF-8 continuation byte pattern
        \\  EXPECTED: bits == 0xxxxxxx OR 110xxxxx OR 1110xxxx OR 11110xxx
        \\  FOUND:    bits == 10xxxxxx ({b} = {d})
    , .{ byte, byte });
}

pub fn add_missing_continue_byte_notice(self: *Self, comptime notice_kind: NOTICE, byte: u8, offset: u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid UTF-8 continue-byte pattern at byte offset {d}, found invalid or first-byte pattern
        \\  EXPECTED: bits at offset {d} == 10xxxxxx
        \\  FOUND:    bits at offset {d} == {b} ({d})
    , .{ offset, offset, byte, byte });
}

pub fn add_illegal_utf8_byte_notice(self: *Self, comptime notice_kind: NOTICE, byte: u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid UTF-8 byte, found byte that cannot exist in any valid UTF-8 sequence
        \\  EXPECTED: byte in range: 0...191 OR 194...244
        \\  FOUND:    byte == {d} ({h})
    , .{ byte, byte });
}

pub fn add_utf8_source_too_short_notice(self: *Self, comptime notice_kind: NOTICE, needed: u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected at least {d} bytes left in source to complete UTF-8 char, but source ended early
        \\  EXPECTED: source bytes left >= {d}
        \\  FOUND:    source bytes left == {d}
    , .{ needed, needed, self.source.len - self.prev.pos });
}

pub fn add_illegal_utf8_codepoint_notice(self: *Self, comptime notice_kind: NOTICE, code: u32) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected legal UTF-8 codepoint, found illegal codepoint
        \\  EXPECTED: code < 0xD800 OR (0xDFFF < code < 0x110000)
        \\  FOUND:    code == {h} ({d})
    , .{ code, code });
}

pub fn add_utf8_overlong_encoding_notice(self: *Self, comptime notice_kind: NOTICE, code: u32, bytes: u8, min: u32, max: u32) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected codepoint that cannot be encoded in less than {d} bytes, found overlong encoding
        \\  EXPECTED: {h} <= code <= {h}
        \\  FOUND:    code == {h} ({d})
    , .{ bytes, min, max, code, code });
}

pub fn read_next_utf8_char(self: *Self, comptime notice_kind: NOTICE) UTF8_Read_Result {
    if (self.rolled_back_to_prev) {
        self.rolled_back_to_prev = false;
        self.swap_curr_and_prev();
        return self.next_utf8;
    }
    assert(self.source.len > self.curr.pos);
    self.prev = self.curr;
    const utf8_len: u8 = switch (self.source[self.curr.pos]) {
        U.BYTE_1_OF_1_MIN...U.BYTE_1_OF_1_MAX => 1,
        U.BYTE_1_OF_2_MIN...U.BYTE_1_OF_2_MAX => 2,
        U.BYTE_1_OF_3_MIN...U.BYTE_1_OF_3_MAX => 3,
        U.BYTE_1_OF_4_MIN...U.BYTE_1_OF_4_MAX => 4,
        U.CONT_BYTE_MIN...U.CONT_BYTE_MAX => {
            self.curr.advance_one_col(1);
            self.add_unexpected_continue_byte_notice(notice_kind, self.source[self.prev.pos]);
            self.next_utf8 = UTF8_Read_Result.replace_char();
            return self.next_utf8;
        },
        else => {
            self.curr.advance_one_col(1);
            self.add_illegal_utf8_byte_notice(notice_kind, self.source[self.prev.pos]);
            self.next_utf8 = UTF8_Read_Result.replace_char();
            return self.next_utf8;
        },
    };
    switch (utf8_len) {
        1 => {
            if (self.source[self.curr.pos] == ASC.NEWLINE) {
                self.curr.advance_newline();
            } else {
                self.curr.advance_one_col(1);
            }
            const bytes = [4]u8{ self.source[self.prev.pos], 0, 0, 0 };
            self.next_utf8 = UTF8_Read_Result.new(bytes[0], bytes, 1);
            return self.next_utf8;
        },
        2 => {
            if (self.source.len - self.curr.pos < 2) {
                self.curr.advance_one_col(1);
                self.add_utf8_source_too_short_notice(notice_kind, 2);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.source[self.curr.pos + 1] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(1);
                self.add_missing_continue_byte_notice(notice_kind, self.source[self.curr.pos + 1], 1);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const code: u32 =
                ((self.source[self.curr.pos] & U.BYTE_1_OF_2_VAL_MASK) << 6) |
                (self.source[self.curr.pos + 1] & U.CONT_BYTE_VAL_MASK);
            if (code < U.MIN_2_BYTE_CODE_POINT) {
                self.curr.advance_one_col(2);
                self.add_utf8_overlong_encoding_notice(notice_kind, code, 2, U.MIN_2_BYTE_CODE_POINT, U.MAX_2_BYTE_CODE_POINT);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const bytes = [4]u8{ self.source[self.curr.pos], self.source[self.curr.pos + 1], 0, 0 };
            self.next_utf8 = UTF8_Read_Result.new(code, bytes, 2);
            return self.next_utf8;
        },
        3 => {
            if (self.source.len - self.curr.pos < 3) {
                self.curr.advance_one_col(1);
                self.add_utf8_source_too_short_notice(notice_kind, 3);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.source[self.curr.pos + 1] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(1);
                self.add_missing_continue_byte_notice(notice_kind, self.source[self.curr.pos + 1], 1);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.source[self.curr.pos + 2] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(2);
                self.add_missing_continue_byte_notice(notice_kind, self.source[self.curr.pos + 2], 2);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const code: u32 =
                ((self.source[self.curr.pos] & U.BYTE_1_OF_3_VAL_MASK) << 12) |
                ((self.source[self.curr.pos + 1] & U.CONT_BYTE_VAL_MASK) << 6) |
                (self.source[self.curr.pos + 2] & U.CONT_BYTE_VAL_MASK);
            if ((code >= U.MIN_SURG_PAIR_CODE_POINT) or (code <= U.MAX_SURG_PAIR_CODE_POINT)) {
                self.curr.advance_one_col(3);
                self.add_illegal_utf8_codepoint_notice(notice_kind, code);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (code < U.MIN_3_BYTE_CODE_POINT) {
                self.curr.advance_one_col(3);
                self.add_utf8_overlong_encoding_notice(notice_kind, code, 3, U.MIN_3_BYTE_CODE_POINT, U.MAX_3_BYTE_CODE_POINT);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const bytes = [4]u8{ self.source[self.curr.pos], self.source[self.curr.pos + 1], self.source[self.curr.pos + 2], 0 };
            self.next_utf8 = UTF8_Read_Result.new(code, bytes, 3);
            return self.next_utf8;
        },
        4 => {
            if (self.source.len - self.curr.pos < 4) {
                self.curr.advance_one_col(1);
                self.add_utf8_source_too_short_notice(notice_kind, 4);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.source[self.curr.pos + 1] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(1);
                self.add_missing_continue_byte_notice(notice_kind, self.source[self.curr.pos + 1], 1);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.source[self.curr.pos + 2] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(2);
                self.add_missing_continue_byte_notice(notice_kind, self.source[self.curr.pos + 2], 2);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (self.source[self.curr.pos + 3] & U.CONT_BYTE_PRE_MASK != U.CONT_BYTE_PREFIX) {
                self.curr.advance_one_col(3);
                self.add_missing_continue_byte_notice(notice_kind, self.source[self.curr.pos + 3], 3);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const code: u32 =
                ((self.source[self.curr.pos] & U.BYTE_1_OF_3_VAL_MASK) << 18) |
                ((self.source[self.curr.pos + 1] & U.CONT_BYTE_VAL_MASK) << 12) |
                ((self.source[self.curr.pos + 2] & U.CONT_BYTE_VAL_MASK) << 6) |
                (self.source[self.curr.pos + 3] & U.CONT_BYTE_VAL_MASK);
            if (code > U.MAX_4_BYTE_CODE_POINT) {
                self.curr.advance_one_col(4);
                self.add_illegal_utf8_codepoint_notice(notice_kind, code);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            if (code < U.MIN_4_BYTE_CODE_POINT) {
                self.curr.advance_one_col(4);
                self.add_utf8_overlong_encoding_notice(notice_kind, code, 4, U.MIN_4_BYTE_CODE_POINT, U.MAX_4_BYTE_CODE_POINT);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            }
            const bytes = [4]u8{ self.source[self.curr.pos], self.source[self.curr.pos + 1], self.source[self.curr.pos + 2], self.source[self.curr.pos + 3] };
            self.next_utf8 = UTF8_Read_Result.new(code, bytes, 4);
            return self.next_utf8;
        },
        else => unreachable,
    }
}

pub fn add_illegal_octal_escape_notice(self: *Self, comptime notice_kind: NOTICE, escape: []const u8, comptime e_char: u8, comptime n: comptime_int) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid octal escape (all chars in range '0'-'7'), found illegal byte for octal escape
        \\  EXPECTED: "\\{u}{s}" to "\\{u}{s}"
        \\  FOUND:    "{s}"
    , .{ e_char, "0" ** n, e_char, "7" ** n, escape });
}

pub fn read_next_n_bytes_as_octal_escape(self: *Self, comptime notice_kind: NOTICE, comptime e_char: u8, comptime n: comptime_int) UTF8_Read_Result {
    self.rolled_back_to_prev = false;
    self.prev = self.curr;
    if (self.source.len - self.curr.pos < n) {
        self.add_utf8_source_too_short_notice(notice_kind, n);
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    var code: u8 = 0;
    var bit: u8 = (n - 1) * 3;
    for (0..n) |i| {
        const byte = self.source[self.curr.pos + i];
        const val = switch (byte) {
            ASC._0...ASC._7 => byte - ASC._0,
            else => {
                const escape = self.source[self.curr.pos - 2 .. self.curr.pos + n];
                self.curr.advance_n_cols(i, i);
                self.add_illegal_octal_escape_notice(notice_kind, escape, e_char, n);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            },
        };
        code |= val << bit;
        bit -= 3;
    }
    if (!U.is_valid_codepoint(code)) {
        self.curr.advance_n_cols(n, n);
        self.add_illegal_utf8_codepoint_notice(notice_kind, code);
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    const utf8 = U.encode_valid_codepoint(code);
    self.curr.advance_n_cols(n, n);
    self.next_utf8 = UTF8_Read_Result.new(code, utf8.code_bytes, utf8.code_len);
    return self.next_utf8;
}

pub fn add_illegal_hex_escape_notice(self: *Self, comptime notice_kind: NOTICE, escape: []const u8, comptime e_char: u8, comptime n: comptime_int) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected valid hexidecimal escape (all chars in range '0'-'9', 'a'-'f', or 'A'-'F'), found illegal byte for hexidecimal escape
        \\  EXPECTED: "\\{u}{s}" to "\\{u}{s}"
        \\  FOUND:    "{s}"
    , .{ e_char, "0" ** n, e_char, "F" ** n, escape });
}

pub fn read_next_n_bytes_as_hex_escape(self: *Self, comptime notice_kind: NOTICE, comptime e_char: u8, comptime n: comptime_int) UTF8_Read_Result {
    self.rolled_back_to_prev = false;
    self.prev = self.curr;
    if (self.source.len - self.curr.pos < n) {
        self.add_utf8_source_too_short_notice(notice_kind, n);
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    var code: u8 = 0;
    var bit: u8 = (n - 1) * 4;
    for (0..n) |i| {
        const byte = self.source[self.curr.pos + i];
        const val = switch (byte) {
            ASC._0...ASC._9 => byte - ASC._0,
            ASC.A...ASC.F => (byte - ASC.A) + 10,
            ASC.a...ASC.f => (byte - ASC.a) + 10,
            else => {
                const escape = self.source[self.curr.pos - 2 .. self.curr.pos + n];
                self.curr.advance_n_cols(i, i);
                self.add_illegal_hex_escape_notice(notice_kind, escape, e_char, n);
                self.next_utf8 = UTF8_Read_Result.replace_char();
                return self.next_utf8;
            },
        };
        code |= val << bit;
        bit -= 4;
    }
    if (!U.is_valid_codepoint(code)) {
        self.curr.advance_n_cols(n, n);
        self.add_illegal_utf8_codepoint_notice(notice_kind, code);
        self.next_utf8 = UTF8_Read_Result.replace_char();
        return self.next_utf8;
    }
    const utf8 = U.encode_valid_codepoint(code);
    self.curr.advance_n_cols(n, n);
    self.next_utf8 = UTF8_Read_Result.new(code, utf8.code_bytes, utf8.code_len);
    return self.next_utf8;
}

pub fn add_source_end_before_expected_token_notice(self: *Self, comptime notice_kind: NOTICE) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected another token before end of source, but source ended early
        \\  EXPECTED: (token)...(EOF)
        \\  FOUND:    (EOF)
    , .{});
}

pub fn add_ident_too_long_notice(self: *Self, comptime notice_kind: NOTICE, len: u32, ident: []const u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Identifiers must be less than or equal to 64 bytes in length, found identifier over 64 bytes
        \\  EXPECTED: ident length <= 64
        \\  FOUND:    ident length == {d} ({s})
    , .{ len, ident });
}

pub fn add_ident_first_byte_is_digit_notice(self: *Self, comptime notice_kind: NOTICE, ident: []const u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Identifiers must not start with the digits '0'-'9', only 'a'-'z', 'A'-'Z', or '_' allowed in first byte
        \\  EXPECTED: ident with non-numeric first byte
        \\  FOUND:    ident == {s}
    , .{ident});
}

pub fn add_ident_expected_but_not_found_notice(self: *Self, comptime notice_kind: NOTICE) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected identifier in this position, but no valid identifier was found
        \\  EXPECTED: bytes in range 'a'-'z', 'A'-'Z', '0'-'9', or '_'
        \\  FOUND:    no bytes that can form an identifier
    , .{});
}

pub fn add_illegal_char_after_template_string_replace_ident(self: *Self, comptime notice_kind: NOTICE, replace_slice: []const u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected either end of replacement segment or a colon followed by a formating code after the identifier
        \\  EXPECTED: "...\{identifier : format\}..." or "...\{identifier\}..."
        \\  FOUND:    "...\{{s}\}..."
    , .{replace_slice});
}

pub fn add_generic_illegal_token_notice(self: *Self, comptime notice_kind: NOTICE, pattern: []const u8) void {
    NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
        \\  Expected legal token at this location, found char pattern that does not resolve to any legal token
        \\  ILLEGAL PATTERN: {s}
    , .{pattern});
}

// pub fn add_generic_illegal_token_notice(self: *Self, comptime notice_kind: NOTICE, pattern: []const u8) void {
//     NoticeManager.Notices.add_notice(notice_kind, SourceRange.new(self.source_name, self.prev, self.curr),
//         \\  Expected legal token at this location, found char pattern that does not resolve to any legal token
//         \\  ILLEGAL PATTERN: {s}
//     , .{pattern});
// }
