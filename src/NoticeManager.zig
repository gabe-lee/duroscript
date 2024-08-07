const std = @import("std");
const SourceRange = @import("./SourceReader.zig").SourceRange;
const ANSI = @import("./ANSI.zig");
const ASC = @import("./Unicode.zig").ASCII;
const SourceReader = @import("./SourceReader.zig");
const TokenBuilder = @import("./SourceLexer.zig").TokenBuilder;
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");

const Self = @This();
const NoticeBuf = StaticAllocBuffer.define(Notice, &Global.small_block_alloc);

notice_list: NoticeBuf.List,
panic_count: usize = 0,
error_count: usize = 0,
warn_count: usize = 0,
hint_count: usize = 0,
info_count: usize = 0,

pub fn new() Self {
    return Self{
        .notice_list = NoticeBuf.List.create(),
    };
}

pub fn cleanup(self: *Self) void {
    self.notice_list.release();
    self.panic_count = 0;
    self.error_count = 0;
    self.warn_count = 0;
    self.hint_count = 0;
    self.info_count = 0;
}

pub fn clear(self: *Self) void {
    self.notice_list.clear();
    self.panic_count = 0;
    self.error_count = 0;
    self.warn_count = 0;
    self.hint_count = 0;
    self.info_count = 0;
}

pub fn add_notice(self: *Self, notice: Notice) void {
    @setCold(true);
    var idx: usize = undefined;
    switch (notice.severity) {
        SEVERITY.PANIC => {
            idx = self.panic_count;
            self.panic_count += 1;
        },
        SEVERITY.ERROR => {
            idx = self.panic_count + self.error_count;
            self.error_count += 1;
        },
        SEVERITY.WARN => {
            idx = self.panic_count + self.error_count + self.warn_count;
            self.warn_count += 1;
        },
        SEVERITY.HINT => {
            idx = self.panic_count + self.error_count + self.warn_count + self.hint_count;
            self.hint_count += 1;
        },
        SEVERITY.INFO => {
            idx = self.notice_list.len;
            self.info_count += 1;
        },
    }
    self.notice_list.insert(idx, notice);
    if (notice.severity == SEVERITY.PANIC) @panic("DUROSCRIPT ENCOUNTERED AN ERROR THAT CANNOT BE RECOVERED FROM");
    return;
}

pub fn log_all_notices(self: *Self) void {
    @setCold(true);
    var list = Global.U8BufMedium.List.create();
    defer list.release();
    const count_line = self.get_count_line();
    defer count_line.release();
    list.append(ASC.NEWLINE);
    list.append_slice(count_line.slice());
    list.append(ASC.NEWLINE);
    for (self.notice_list.slice(), 0..) |notice, idx| {
        if (idx < self.error_count) {
            list.append_slice(ANSI.LOG_PANIC);
            list.append_slice(PANIC_HEADER);
        } else if (idx < self.warn_count) {
            list.append_slice(ANSI.LOG_ERROR);
            list.append_slice(ERROR_HEADER);
        } else if (idx < self.hint_count) {
            list.append_slice(ANSI.LOG_WARN);
            list.append_slice(WARN_HEADER);
        } else if (idx < self.info_count) {
            list.append_slice(ANSI.LOG_HINT);
            list.append_slice(HINT_HEADER);
        } else {
            list.append_slice(ANSI.LOG_INFO);
            list.append_slice(INFO_HEADER);
        }
        list.append_slice(notice.file);
        list.append_fmt_string(":{d}:{d}\n", .{ notice.range.row_start, notice.range.col_start });
        list.append_slice(ANSI.RESET);
        list.append_slice(NOTICE_MSG[@intFromEnum(notice.kind)]);
        list.append(ASC.NEWLINE);
    }
    list.append_slice(count_line.slice());
    list.append(ASC.NEWLINE);
    var std_err = std.io.getStdErr();
    std_err.writeAll(list.slice()) catch {};
    return;
}

fn get_count_line(self: *Self) Global.U8BufSmall.Slice {
    @setCold(true);
    var count_line = Global.U8BufSmall.List.create();
    if (self.panic_count > 0) {
        count_line.append_slice(ANSI.LOG_PANIC);
        count_line.append_slice("PANICS=1");
        count_line.append_slice(ANSI.RESET);
        count_line.append(ASC.SPACE);
    }
    if (self.error_count > 0) {
        count_line.append_slice(ANSI.LOG_ERROR);
        count_line.append_fmt_string("ERRORS={d} ", .{self.error_count});
        count_line.append_slice(ANSI.RESET);
    }
    if (self.warn_count > 0) {
        count_line.append_slice(ANSI.LOG_WARN);
        count_line.append_fmt_string("WARNS={d} ", .{self.warn_count});
        count_line.append_slice(ANSI.RESET);
    }
    if (self.hint_count > 0) {
        count_line.append_slice(ANSI.LOG_HINT);
        count_line.append_fmt_string("HINTS={d} ", .{self.hint_count});
        count_line.append_slice(ANSI.RESET);
    }
    if (self.info_count > 0) {
        count_line.append_slice(ANSI.LOG_HINT);
        count_line.append_fmt_string("INFOS={d} ", .{self.info_count});
        count_line.append_slice(ANSI.RESET);
    }
    return count_line.downgrade_into_slice_partial();
}

pub fn get_notice_list_kinds(self: *Self) anyerror!Global.U8BufMedium.Slice {
    var list = Global.U8BufMedium.List.create();
    for (self.notice_list.slice()) |notice| {
        list.append_slice(@tagName(notice.kind));
        list.append(ASC.NEWLINE);
    }
    return list.downgrade_into_slice_partial();
}

pub const Notice = struct {
    kind: KIND,
    severity: SEVERITY,
    source_key: u16,
    row: u32,
    row_byte_pos: u32,
    col_start: u32,
    col_end: u32,
    col_infraction: u32,
};

pub const SEVERITY = enum(u8) {
    INFO,
    HINT,
    WARN,
    ERROR,
    PANIC,
};

pub const INFO_HEADER = "INFO: ";
pub const HINT_HEADER = "HINT: ";
pub const WARN_HEADER = "WARN: ";
pub const ERROR_HEADER = "ERROR: ";
pub const PANIC_HEADER = "!! PANIC !! ";

pub const KIND = enum(u16) {
    integer_literal_too_large_to_be_negative,
    illegal_string_escape_sequence,
    non_whitespace_before_backtick_in_multiline_string,
    runaway_multiline_string,
    source_ended_before_string_terminated,
    illegal_ascii_character_in_source,
    utf8_unexpected_continue_byte,
    utf8_missing_or_malformed_continue_byte,
    utf8_illegal_byte,
    utf8_multibyte_char_source_ended_early,
    utf8_illegal_codepoint,
    utf8_overlong_encoding,
    invalid_octal_escape_sequence,
    invalid_short_hexidecimal_escape_sequence,
    invalid_medium_hexidecimal_escape_sequence,
    invalid_long_hexidecimal_escape_sequence,
    expected_another_token_before_end_of_file,
    ident_too_long,
    ident_first_byte_is_digit,
    expected_identifier_here,
    illegal_char_after_template_string_replace_ident,
    generic_illegal_token,
    illegal_char_in_hex_integer_literal,
    illegal_char_in_oct_integer_literal,
    illegal_char_in_bin_integer_literal,
    illegal_char_in_decimal_integer_literal,
    integer_literal_data_overflows_64_bits,
    illegal_integer_literal_no_significant_digits,
};

pub const NOTICE_MSG = [@typeInfo(KIND).Enum.fields.len][]const u8{
    \\    Negative integer literal is too large for an i64. All negative integer
    \\    literals are treated as the type i64, and the minimum value for i64 is 
    \\    -9223372036854775808 or -0x8000000000000000 or -0o1000000000000000000000
    ,
    \\    Expected valid string escape sequence, found invalid escape sequence 
    \\    (or possibly a valid escape sequence in an invalid context)
    ,
    \\    Multiline strings can only have whitespace before the first ` char
    \\    that begins each new line. Found non-whitespace char before `
    ,
    \\    Runaway multiline string. Every new line must have a ` char before 
    \\    any other non-space characters, including additional newlines
    ,
    \\    Expected string termination before end of source file, reached end of
    \\    source without termination
    ,
    \\    Expected only 1-byte UTF-8 (ASCII) characters in this source code,
    \\    multi-byte UTF-8 not allowed outside of string literals
    ,
    \\    Expected valid UTF-8 first-byte pattern in first byte position, 
    \\    found UTF-8 continuation byte pattern in first byte position
    ,
    \\    Expected valid UTF-8 continue-byte pattern for utf8 multi-byte char, 
    \\    continue byte was missing or malformed
    ,
    \\    Expected valid UTF-8 byte, found byte that cannot exist in any valid
    \\    UTF-8 sequence
    ,
    \\    UTF-8 first byte signaled additional bytes to complete UTF-8 char, 
    \\    but string ended early
    ,
    \\    Found illegal UTF-8 Codepoint. Codepoints between 0xD800 and 0xDFFF
    \\    (inclusive) and codepoints greater than 0x10FFFF are illegal
    ,
    \\    UTF-8 codepoint was encoded using more than the minimum number of bytes
    \\    required to fully encode the codepoint (overlong encoding).
    ,
    \\    Expected valid octal escape (3 chars in range '0'-'7'), found illegal
    \\    character in escape sequence. Value must also resolve to less than 128
    \\    (ASCII)
    ,
    \\    Expected valid short hexidecimal escape (2 chars in range '0'-'9',
    \\    'A'-'F', or 'a'-'f'), found illegal character in escape sequence
    \\    Value must also resolve to less than 128 (ASCII)
    ,
    \\    Expected valid medium hexidecimal escape (4 chars in range '0'-'9',
    \\    'A'-'F', or 'a'-'f'), found illegal character in escape sequence
    \\    Value must also resolve to legal UTF-8 codepoint
    ,
    \\    Expected valid long hexidecimal escape (8 chars in range '0'-'9',
    \\    'A'-'F', or 'a'-'f'), found illegal character in escape sequence
    \\    Value must also resolve to legal UTF-8 codepoint
    ,
    \\    Expected another token before end of source file, but file ended early
    ,
    \\    Identifiers must be less than or equal to 64 bytes (ASCII chars)
    \\    in length, found identifier over 64 bytes
    ,
    \\    Identifiers cannot start with the digits '0'-'9', only 'a'-'z', 'A'-'Z',
    \\    or '_' allowed in first byte (digits may be used in following bytes)
    ,
    \\    Expected identifier in this position, but no character to form a valid
    \\    identifier were found
    ,
    \\    Expected either end of replacement segment or a colon followed by a 
    \\    formating code after the replacement identifier in this template string
    ,
    \\    Expected legal token at this location, found char pattern that does not
    \\    resolve to any legal token
    ,
    \\    Illegal char in hexidecimal integer literal. Only '0'-'9', 'a'-'f', 
    \\    'A'-'F', or '_' allowed in hexidecimal integer literals.
    ,
    \\    Illegal char in octal integer literal. Only '0'-'7'  or '_' allowed in 
    \\    octal integer literals.
    ,
    \\    Illegal char in binary integer literal. Only '0', '1', or '_' allowed in 
    \\    binary integer literals.
    ,
    \\    Illegal char in decimal integer literal. Only '0'-'9' or '_' allowed in 
    \\    decimal integer literals, followed by an optional 'e' and then decimal
    \\    exponent following the same rules (with optional '-' sign at beginning).
    ,
    \\    Illegal integer literal: number represented would overflow 64 bits. All
    \\    integer literals are stored as 64 bit constants (u64/i64).
    ,
    \\    Illegal integer literal has no significant digits. Binary, octal, and
    \\    hexidecimal integer literals must have at least one digit following
    \\    their prefix code ('0b', '0o', '0x')
};
