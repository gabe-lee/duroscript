const std = @import("std");
const SourceReader = @import("./SourceReader.zig");
const TOK = @import("./Token.zig").KIND;
const ASC = @import("./Unicode.zig").ASCII;

const LARGEST_RAW_VAL_FOR_NEG_I64: u64 = 9223372036854775808;
const MIN_I64: i64 = std.math.minInt(i64);
const TOP_2_MSB_MASK = 0xC000000000000000;
const BITS_PER_BIN = 1;
const BITS_PER_OCT = 3;
const BITS_PER_HEX = 4;
const BITS_IN_U64 = 64;

pub const ParseNumberResult = struct {
    kind: TOK,
    raw: u64,
    neg: bool,
};

pub const BASE = enum(u3) {
    BIN,
    OCT,
    HEX,
};

pub fn handle_negative_integer(raw: u64) ParseNumberResult {
    if (raw > LARGEST_RAW_VAL_FOR_NEG_I64) {
        // FIXME add integer too large to be negative error
        return ParseNumberResult{
            .kind = TOK.ILLEGAL,
            .raw = raw,
            .neg = true,
        };
    }
    const val: i64 = if (raw == LARGEST_RAW_VAL_FOR_NEG_I64) MIN_I64 else -@as(i64, @bitCast(raw));
    return ParseNumberResult{
        .kind = TOK.LIT_INTEGER,
        .raw = @bitCast(val),
        .neg = true,
    };
}

pub fn parse_integer(source: *SourceReader, comptime base: BASE, comptime negative: bool) ParseNumberResult {
    const BITS_PER_DIGIT: comptime_int = switch (base) {
        .BIN => BITS_PER_BIN,
        .OCT => BITS_PER_OCT,
        .HEX => BITS_PER_HEX,
    };
    var val: u64 = 0;
    var bit_offset: u6 = BITS_IN_U64 - BITS_PER_DIGIT;
    var num_too_large: bool = false;
    var illegal_alpha: bool = false;
    var at_least_one_digit: bool = false;
    var power_add: u32 = 1;
    var implicit_power: u32 = 0;
    // var explicit_power: u32 = 0;
    while (source.source.len > source.curr.pos) {
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
    while (source.source.len > source.curr.pos) {
        const next_byte = source.peek_next_byte();
        const next_bits: u64 = switch (base) {
            .HEX => switch (next_byte) {
                ASC.A...ASC.F => @as(u64, next_byte - ASC.A) + 10,
                ASC.a...ASC.f => @as(u64, next_byte - ASC.a) + 10,
                ASC._0...ASC._9 => @as(u64, next_byte - ASC._0),
                ASC.PERIOD => {
                    if (power_add == 0) break;
                    source.curr.advance_one_col(1);
                    power_add = 0;
                    continue;
                },
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
                ASC.PERIOD => {
                    if (power_add == 0) break;
                    source.curr.advance_one_col(1);
                    power_add = 0;
                    continue;
                },
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
                ASC.PERIOD => {
                    if (power_add == 0) break;
                    source.curr.advance_one_col(1);
                    power_add = 0;
                    continue;
                },
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
        implicit_power += power_add;
        val |= next_bits << bit_offset;
        source.curr.advance_one_col(1);
        if (bit_offset == 0) break;
        if (base == BASE.OCT and bit_offset == 1) {
            if (source.source.len > source.curr.pos) {
                const next_oct = source.peek_next_byte();
                if (next_oct >= ASC._0 and next_oct <= ASC._7) {
                    if (val & TOP_2_MSB_MASK != 0) {
                        num_too_large = true;
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
    while (source.source.len > source.curr.pos) {
        const next_byte = source.peek_next_byte();
        switch (base) {
            .HEX => switch (next_byte) {
                ASC._0...ASC._9, ASC.A...ASC.F, ASC.a...ASC.f => {
                    num_too_large = true;
                },
                ASC.G...ASC.Z, ASC.g...ASC.z, ASC.PERIOD => {
                    illegal_alpha = true;
                },
                ASC.UNDERSCORE => {},
                else => break,
            },
            .OCT => switch (next_byte) {
                ASC._0...ASC._7 => {
                    num_too_large = true;
                },
                ASC._8...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => {
                    illegal_alpha = true;
                },
                ASC.UNDERSCORE => {},
                else => break,
            },
            .BIN => switch (next_byte) {
                ASC._0, ASC._1 => {
                    num_too_large = true;
                },
                ASC._2...ASC._9, ASC.A...ASC.Z, ASC.a...ASC.z, ASC.PERIOD => {
                    illegal_alpha = true;
                },
                ASC.UNDERSCORE => {},
                else => break,
            },
        }
        source.curr.advance_one_col(1);
    }
    if (illegal_alpha) {
        //FIXME add hex illegal alpha notice
        return ParseNumberResult{ .kind = TOK.ILLEGAL, .raw = 0, .neg = false };
    }
    if (num_too_large) {
        //FIXME add hex num too large notice
        return ParseNumberResult{ .kind = TOK.ILLEGAL, .raw = 0, .neg = false };
    }
    if (!at_least_one_digit) {
        //FIXME add no sig digits notice
        return ParseNumberResult{ .kind = TOK.ILLEGAL, .raw = 0, .neg = false };
    }
    val >>= bit_offset;
    if (negative) {
        return handle_negative_integer(val);
    }
    return ParseNumberResult{
        .kind = TOK.LIT_INTEGER,
        .raw = val,
        .neg = false,
    };
}
