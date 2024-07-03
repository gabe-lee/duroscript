const ASC = @import("./Unicode.zig").ASCII;
const TOK = @import("./Token.zig").KIND;
const std = @import("std");
const assert = std.debug.assert;
const SourceReader = @import("./SourceReader.zig");
const NoticeManager = @import("./NoticeManager.zig");
const IdentBlock = @import("./IdentBlock.zig");
const TokenBuilder = @import("./SourceLexer.zig").TokenBuilder;
const SEVERITY = NoticeManager.SEVERITY;
const NOTICE = NoticeManager.KIND;
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");

pub const IdentBlockBufMed = StaticAllocBuffer.define(IdentBlock, &Global.medium_block_alloc);
pub const IdentBlockBufSmall = StaticAllocBuffer.define(IdentBlock, &Global.small_block_alloc);

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

pub fn compile_keyword(comptime string: []const u8, comptime is_builtin: bool) IdentBlock {
    var source = SourceReader.new(0, string);
    var token = TokenBuilder.new(0, &source);
    token.kind = TOK.IDENT;
    const ident = parse_from_source(&source, &token, is_builtin);
    if (token.kind == TOK.ILLEGAL or (token.has_notice and (@intFromEnum(token.notice_severity) >= @intFromEnum(SEVERITY.ERROR)))) {
        @compileError("FAILED TO COMPILE DUROSCRIPT KEYWORD");
    }
    return ident.ident;
}

pub fn parse_from_string(string: []const u8, comptime is_builtin: bool) IdentParseResult {
    var reader = SourceReader.new(0, string);
    var token = TokenBuilder.new(0, &reader);
    token.kind = TOK.IDENT;
    return parse_from_source(&reader, &token, is_builtin);
}

pub fn parse_from_source(source: *SourceReader, token: *TokenBuilder, comptime is_builtin: bool) IdentParseResult {
    assert(source.data.len > source.curr.pos);
    var ident_result = IdentParseResult{
        .ident = IdentBlock{
            .data = INNER{ 0, 0, 0, 0, 0, 0 },
        },
        .illegal = false,
        .len = 0,
    };
    var bit_idx: u8 = if (is_builtin) 6 else 0;
    var int_idx: u8 = 0;
    const start_pos = source.curr.pos;
    if (source.data[source.curr.pos] >= ASC._0 and source.data[source.curr.pos] <= ASC._9) {
        token.attach_notice_here(NOTICE.ident_first_byte_is_digit, SEVERITY.ERROR, source);
        token.kind = TOK.ILLEGAL;
        ident_result.illegal = true;
    }
    while (source.curr.pos < source.data.len) {
        const byte = source.data[source.curr.pos];
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
        ident_result.len += 1;
        if (int_idx >= 6) {
            token.attach_notice_here(NOTICE.ident_too_long, SEVERITY.ERROR, source);
            token.kind = TOK.ILLEGAL;
            ident_result.illegal = true;
        } else {
            ident_result.ident.data[int_idx] |= val << @intCast(bit_idx);
            if (bit_idx != 0 and int_idx < 5) {
                ident_result.ident.data[int_idx + 1] |= val >> @intCast(64 - bit_idx);
            }
            bit_idx += 6;
            int_idx += (bit_idx & 64) >> 6;
            bit_idx &= 63;
        }
    }
    if (source.curr.pos == start_pos) {
        token.attach_notice_here(NOTICE.expected_identifier_here, SEVERITY.ERROR, source);
        token.kind = TOK.ILLEGAL;
        ident_result.illegal = true;
    }
    return ident_result;
}
