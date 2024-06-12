const ASC = @import("./Unicode.zig").ASCII;
const std = @import("std");
const SourceReader = @import("./SourceReader.zig");
const NoticeManager = @import("./NoticeManager.zig");
const IdentBlock = @import("./IdentBlock.zig");
const NKIND = NoticeManager.KIND;
const nkind_string = NoticeManager.kind_string;

const Self = @This();
pub const INNER = [6]u64;
pub const INNER_LEN = @sizeOf(u64) * 6;

data: INNER,

pub const IdentParseResult = struct {
    ident: Self,
    len: usize,
    illegal: bool,
};

const DIGIT_OFFSET = 1;
const UPPER_OFFSET = 11;
const LOWER_OFFSET = 37;
const UNDERSCORE_OFFSET = 63;
const BLANK = Self{ .data = INNER{ 0, 0, 0, 0, 0, 0 } };

pub inline fn eql(self: Self, other: Self) bool {
    return ((self.data[0] ^ other.data[0]) |
        (self.data[1] ^ other.data[1]) |
        (self.data[2] ^ other.data[2]) |
        (self.data[3] ^ other.data[3]) |
        (self.data[4] ^ other.data[4]) |
        (self.data[5] ^ other.data[5])) == 0;
}

pub fn parse_from_string(string: []const u8, comptime notice_kind: NKIND) IdentParseResult {
    var source = SourceReader.new("(STRING)", string);
    return parse_from_source(&source, notice_kind);
}

pub fn parse_from_source(source: *SourceReader, comptime notice_kind: NKIND) IdentParseResult {
    var ident = INNER{ 0, 0, 0, 0, 0, 0 };
    if (source.is_complete()) {
        source.add_source_end_before_expected_token_notice(notice_kind);
        return IdentParseResult{
            .ident = IdentBlock{
                .data = ident,
            },
            .len = 0,
            .illegal = true,
        };
    }
    var illegal = false;
    var too_long = false;
    var first_digit = false;
    var bit_idx: u8 = 0;
    var int_idx: u8 = 0;
    var len: usize = 0;
    const start_pos = source.curr.pos;
    if (source.source[source.curr.pos] >= ASC._0 and source.source[source.curr.pos] <= ASC._9) {
        illegal = true;
        first_digit = true;
    }
    while (source.curr.pos < source.source.len) {
        const byte = source.source[source.curr.pos];
        const val: u64 = switch (byte) {
            ASC._0...ASC._9 => (byte - ASC._0) + DIGIT_OFFSET,
            ASC.A...ASC.Z => (byte - ASC.A) + UPPER_OFFSET,
            ASC.a...ASC.z => (byte - ASC.a) + LOWER_OFFSET,
            ASC.UNDERSCORE => UNDERSCORE_OFFSET,
            else => {
                break;
            },
        };
        source.curr.advance_one_col(1);
        len += 1;
        if (int_idx >= 6) {
            illegal = true;
            too_long = true;
        } else {
            ident[int_idx] |= val << @intCast(bit_idx);
            if (bit_idx != 0 and int_idx < 5) {
                ident[int_idx + 1] |= val >> @intCast(64 - bit_idx);
            }
            bit_idx += 6;
            int_idx += (bit_idx & 64) >> 6;
            bit_idx &= 63;
        }
    }
    if (too_long) {
        const total_len = source.curr.pos - start_pos;
        source.add_ident_too_long_notice(notice_kind, total_len, source.source[start_pos..source.curr.pos]);
    } else if (source.curr.pos == start_pos) {
        source.add_ident_expected_but_not_found_notice(notice_kind);
    }
    if (first_digit) {
        source.add_ident_first_byte_is_digit_notice(notice_kind, source.source[start_pos..source.curr.pos]);
    }
    return IdentParseResult{
        .ident = IdentBlock{
            .data = ident,
        },
        .len = len,
        .illegal = illegal,
    };
}
