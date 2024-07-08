const std = @import("std");
const SourceReader = @import("./SourceReader.zig");
const TOK = @import("./Token.zig").TOK;
const ASC = @import("./Unicode.zig").ASCII;
const NoticeManager = @import("./NoticeManager.zig");
const NOTICE = NoticeManager.KIND;
const SEVERITY = NoticeManager.SEVERITY;
const TokenBuilder = @import("./SourceLexer.zig").TokenBuilder;

const LARGEST_RAW_VAL_FOR_NEG_I64: u64 = 9223372036854775808;
const MIN_I64: i64 = std.math.minInt(i64);
const TOP_2_MSB_MASK = 0xC000000000000000;
const BITS_PER_BIN = 1;
const BITS_PER_OCT = 3;
const BITS_PER_HEX = 4;
const BITS_IN_U64 = 64;

// pub const ParseNumberResult = struct {
//     kind: TOK,
//     raw: u64,
//     neg: bool,
// };

pub const BASE = enum(u3) {
    BIN,
    OCT,
    HEX,
};

fn handle_negative_integer(raw: u64, source: *SourceReader, token: *TokenBuilder) void {
    if (raw > LARGEST_RAW_VAL_FOR_NEG_I64) {
        token.kind = TOK.ILLEGAL;
        token.attach_notice_here(NOTICE.integer_literal_too_large_to_be_negative, SEVERITY.ERROR, source);
        return;
    }
    const val: i64 = if (raw == LARGEST_RAW_VAL_FOR_NEG_I64) MIN_I64 else -@as(i64, @bitCast(raw));
    token.set_data(@bitCast(val), 0, 1);
    return;
}

pub fn parse_base2_compatable_integer(comptime base: BASE, comptime negative: bool, source: *SourceReader, token: *TokenBuilder) void {
    token.kind = TOK.LIT_INTEGER;
    const BITS_PER_DIGIT: comptime_int = switch (base) {
        .BIN => BITS_PER_BIN,
        .OCT => BITS_PER_OCT,
        .HEX => BITS_PER_HEX,
    };
    var val: u64 = 0;
    var bit_offset: u6 = BITS_IN_U64 - BITS_PER_DIGIT;
    var at_least_one_digit: bool = false;
    while (source.data.len > source.curr.pos) {
        const next_byte = source.peek_next_byte();
        switch (next_byte) {
            ASC._0 => {
                at_least_one_digit = true;
            },
            ASC.UNDERSCORE => {},
            else => break,
        }
        source.curr.advance_one_col(1);
    }
    while (source.data.len > source.curr.pos) {
        const next_byte = source.peek_next_byte();
        const next_bits: u64 = switch (base) {
            .HEX => switch (next_byte) {
                ASC.A...ASC.F => @as(u64, next_byte - ASC.A) + 10,
                ASC.a...ASC.f => @as(u64, next_byte - ASC.a) + 10,
                ASC._0...ASC._9 => @as(u64, next_byte - ASC._0),
                ASC.UNDERSCORE => {
                    source.curr.advance_one_col(1);
                    continue;
                },
                else => {
                    if (bit_offset < BITS_IN_U64 - BITS_PER_DIGIT) {
                        bit_offset += BITS_PER_DIGIT;
                    }
                    break;
                },
            },
            .OCT => switch (next_byte) {
                ASC._0...ASC._7 => @as(u64, next_byte - ASC._0),
                ASC.UNDERSCORE => {
                    source.curr.advance_one_col(1);
                    continue;
                },
                else => {
                    if (bit_offset < BITS_IN_U64 - BITS_PER_DIGIT) {
                        bit_offset += BITS_PER_DIGIT;
                    }
                    break;
                },
            },
            .BIN => switch (next_byte) {
                ASC._0 => 0,
                ASC._1 => 1,
                ASC.UNDERSCORE => {
                    source.curr.advance_one_col(1);
                    continue;
                },
                else => {
                    if (bit_offset < BITS_IN_U64 - BITS_PER_DIGIT) {
                        bit_offset += BITS_PER_DIGIT;
                    }
                    break;
                },
            },
        };
        at_least_one_digit = true;
        val |= next_bits << bit_offset;
        source.curr.advance_one_col(1);
        if (bit_offset == 0) break;
        if (base == BASE.OCT and bit_offset == 1) {
            if (source.data.len > source.curr.pos) {
                const next_oct = source.peek_next_byte();
                if (next_oct >= ASC._0 and next_oct <= ASC._7) {
                    if (val & TOP_2_MSB_MASK != 0) {
                        token.attach_notice_here(NOTICE.integer_literal_data_overflows_64_bits, SEVERITY.ERROR, source);
                        token.kind = TOK.ILLEGAL;
                        break;
                    }
                    val <<= 2;
                    bit_offset = 0;
                    continue;
                }
            }
            break;
        } else {
            bit_offset -= BITS_PER_DIGIT;
        }
    }
    while (source.data.len > source.curr.pos) {
        const next_byte = source.peek_next_byte();
        switch (base) {
            .HEX => switch (next_byte) {
                ASC._0...ASC._9, ASC.A...ASC.F, ASC.a...ASC.f => {
                    token.attach_notice_here(NOTICE.integer_literal_data_overflows_64_bits, SEVERITY.ERROR, source);
                    token.kind = TOK.ILLEGAL;
                },
                ASC.G...ASC.Z, ASC.g...ASC.z, ASC.PERIOD => {
                    token.attach_notice_here(NOTICE.illegal_char_in_hex_integer_literal, SEVERITY.ERROR, source);
                    token.kind = TOK.ILLEGAL;
                },
                ASC.UNDERSCORE => {},
                else => break,
            },
            .OCT => switch (next_byte) {
                ASC._0...ASC._7 => {
                    token.attach_notice_here(NOTICE.integer_literal_data_overflows_64_bits, SEVERITY.ERROR, source);
                    token.kind = TOK.ILLEGAL;
                },
                ASC._8...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => {
                    token.attach_notice_here(NOTICE.illegal_char_in_oct_integer_literal, SEVERITY.ERROR, source);
                    token.kind = TOK.ILLEGAL;
                },
                ASC.UNDERSCORE => {},
                else => break,
            },
            .BIN => switch (next_byte) {
                ASC._0, ASC._1 => {
                    token.attach_notice_here(NOTICE.integer_literal_data_overflows_64_bits, SEVERITY.ERROR, source);
                    token.kind = TOK.ILLEGAL;
                },
                ASC._2...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => {
                    token.attach_notice_here(NOTICE.illegal_char_in_bin_integer_literal, SEVERITY.ERROR, source);
                    token.kind = TOK.ILLEGAL;
                },
                ASC.UNDERSCORE => {},
                else => break,
            },
        }
        source.curr.advance_one_col(1);
    }
    if (!at_least_one_digit) {
        token.attach_notice_here(NOTICE.illegal_integer_literal_no_significant_digits, SEVERITY.ERROR, source);
        token.kind = TOK.ILLEGAL;
        return;
    }
    val >>= bit_offset;
    if (negative) {
        return handle_negative_integer(val, source, token);
    }
    token.set_data(val, 0, 0);
    return;
}
