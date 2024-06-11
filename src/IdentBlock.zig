const ASC = @import("./Unicode.zig").ASCII;
const std = @import("std");
const WARN = @import("./Token.zig").WARN;
const SourceReader = @import("./SourceReader.zig");
const NoticeManager = @import("./NoticeManager.zig");
const IdentBlock = @import("./IdentBlock.zig");
const NKIND = NoticeManager.KIND;
const nkind_string = NoticeManager.kind_string;

const Self = @This();

data: [6]u64,

pub const IdentParseResult = struct {
    ident: Self,
    illegal: bool,
};

const DIGIT_OFFSET = 1;
const UPPER_OFFSET = 11;
const LOWER_OFFSET = 37;
const UNDERSCORE_OFFSET = 63;
const BLANK = Self{ .data = [6]u8{ 0, 0, 0, 0, 0, 0 } };

pub inline fn eql(self: Self, other: Self) bool {
    return self.data[0] == other.data[0] and
        self.data[1] == self.data[1] and
        self.data[2] == self.data[2] and
        self.data[3] == other.data[3] and
        self.data[4] == self.data[4] and
        self.data[5] == self.data[5];
}

pub fn parse_from_source(source: *SourceReader, comptime notice_kind: NKIND) IdentParseResult {
    var ident = [6]u64{ 0, 0, 0, 0, 0, 0 };
    if (source.is_complete()) {
        source.add_source_end_before_expected_token_notice(notice_kind);
        return IdentParseResult{
            .ident = IdentBlock{
                .data = ident,
            },
            .illegal = true,
        };
    }
    var illegal = false;
    var too_long = false;
    var first_digit = false;
    var bit_idx: u8 = 0;
    var int_idx: u8 = 0;
    const start_pos = source.curr.pos;
    if (source.source[source.curr.pos] >= ASC._0 and source.source[source.curr.pos] <= ASC._9) {
        illegal = true;
        first_digit = true;
    }
    while (!source.is_complete()) {
        const byte = source.read_next_ascii(notice_kind);
        const val = switch (byte) {
            ASC._0...ASC._9 => (byte - ASC._0) + DIGIT_OFFSET,
            ASC.A...ASC.Z => (byte - ASC.A) + UPPER_OFFSET,
            ASC.a...ASC.z => (byte - ASC.a) + LOWER_OFFSET,
            ASC.UNDERSCORE => UNDERSCORE_OFFSET,
            else => {
                source.rollback_position();
                break;
            },
        };
        if (int_idx >= 6) {
            illegal = true;
            too_long = true;
        } else {
            ident[int_idx] |= val << @truncate(bit_idx);
            const last_idx_mask = (int_idx ^ 5);
            const next_idx = int_idx + ((last_idx_mask | last_idx_mask >> 1 | last_idx_mask >> 2) & 1);
            ident[next_idx] |= val >> @truncate(64 - bit_idx);
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
        .illegal = illegal,
    };
}
