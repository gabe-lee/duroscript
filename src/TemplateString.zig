const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const List = std.ArrayListUnmanaged;
const IdentBlock = @import("./IdentBlock.zig");
const TOK = @import("./Token.zig").KIND;
const UNI = @import("./Unicode.zig");
const ASC = UNI.ASCII;
const TokenBuilder = @import("./SourceLexer.zig").TokenBuilder;
const SourceReader = @import("./SourceReader.zig");
const NoticeManager = @import("./NoticeManager.zig");
const SEVERITY = NoticeManager.SEVERITY;
const NOTICE = NoticeManager.KIND;
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");
const ProgramROM = @import("./ProgramROM.zig");

const Self = @This();

const IDENT_LIST_OFFSET = @sizeOf(u32) * 6;

ptr: [*]const u8,
segment_count: u32,
ident_count: u32,
replace_list_offset: u32,
const_list_offset: u32,
const_source_offset: u32,
segment_list_offset: u32,

const ReplaceSegment = struct {
    input: u32,
    start: u32,
    end: u32,
    //TODO parse format string when lexing
    // format: FMT.FMT_TYPE,
};

const ConstSegment = struct {
    start: u32,
    end: u32,
};

const ConstSegmentBuf = StaticAllocBuffer.define(ConstSegment, &Global.small_block_alloc);
const ReplaceSegmentBuf = StaticAllocBuffer.define(ReplaceSegment, &Global.small_block_alloc);

pub const TemplateStringBuilder = struct {
    const_source: Global.U8BufSmall.List,
    seg_count: u32,
    seg_list: Global.U8BufSmall.List,
    ident_list: IdentBlock.IdentBlockBufSmall.List,
    const_list: ConstSegmentBuf.List,
    replace_list: ReplaceSegmentBuf.List,

    const SIDX_MASK = 0b11111111_11111111_11111111_11111000;
    const SIDX_SHIFT = 3;
    const SSUB_MASK = 0b111;
    const SERIAL_ALIGN = @max(@max(@max(@alignOf(u32), @alignOf(ConstSegment)), @alignOf(ReplaceSegment)), @alignOf(IdentBlock));

    fn create() TemplateStringBuilder {
        return TemplateStringBuilder{
            .const_source = Global.U8BufSmall.List.create(),
            .seg_count = 0,
            .seg_list = Global.U8BufSmall.List.create(),
            .ident_list = IdentBlock.IdentBlockBufSmall.List.create(),
            .const_list = ConstSegmentBuf.List.create(),
            .replace_list = ReplaceSegmentBuf.List.create(),
        };
    }

    fn cleanup(self: *TemplateStringBuilder) void {
        self.const_source.release();
        self.seg_list.release();
        self.ident_list.release();
        self.const_list.release();
        self.replace_list.release();
        self.seg_count = 0;
    }

    fn push_const_segment(self: *TemplateStringBuilder, bytes: []const u8) void {
        const real_idx = (self.seg_count & SIDX_MASK) >> SIDX_SHIFT;
        if (real_idx == self.seg_list.len) {
            self.seg_list.append(0);
        }
        self.seg_count += 1;
        const start: u32 = @intCast(self.const_source.len);
        self.const_source.append_slice(bytes);
        const end: u32 = @intCast(self.const_source.len);
        self.const_list.append(ConstSegment{ .start = start, .end = end });
    }

    fn push_replace_segment(self: *TemplateStringBuilder, seg: ReplaceSegment) void {
        const real_idx = (self.seg_count & SIDX_MASK) >> SIDX_SHIFT;
        const sub_idx: u8 = @truncate(self.seg_count & SSUB_MASK);
        if (real_idx == self.seg_list.len) {
            self.seg_list.append(0);
        }
        self.seg_list.ptr[real_idx] |= @as(u8, 1) << @intCast(sub_idx);
        self.seg_count += 1;
        self.replace_list.append(seg);
    }

    fn serialize_to_token_rom(self: *TemplateStringBuilder, token: *TokenBuilder) void {
        assert(token.kind == TOK.LIT_STR_TEMPLATE);
        const token_rom = &Global.token_rom;
        const replace_list_len: u32 = @intCast(self.replace_list.len * @sizeOf(ReplaceSegment));
        const const_list_len: u32 = @intCast(self.const_list.len * @sizeOf(ConstSegment));
        const ident_list_len: u32 = @intCast(self.ident_list.len * @sizeOf(IdentBlock));
        const const_source_len: u32 = @intCast(self.const_source.len);
        const switch_list_byte_len: u32 = @intCast(self.seg_list.len);
        const static_len: u32 = IDENT_LIST_OFFSET;
        const len: u32 = static_len +
            ident_list_len +
            replace_list_len +
            const_list_len +
            const_source_len +
            switch_list_byte_len;
        assert(len < std.math.maxInt(u32));
        token_rom.prepare_space_for_write(len, SERIAL_ALIGN);
        const ptr: u64 = @bitCast(token_rom.data.len);
        const replace_list_offset: u32 = IDENT_LIST_OFFSET + ident_list_len;
        const const_list_offset: u32 = replace_list_offset + replace_list_len;
        const const_source_offset: u32 = const_list_offset + const_list_len;
        const seg_list_offset: u32 = const_source_offset + const_source_len;
        token_rom.write_single(u32, self.seg_count);
        token_rom.write_single(u32, @intCast(self.ident_list.len));
        token_rom.write_single(u32, replace_list_offset);
        token_rom.write_single(u32, const_list_offset);
        token_rom.write_single(u32, const_source_offset);
        token_rom.write_single(u32, seg_list_offset);
        token_rom.write_slice(IdentBlock, self.ident_list.slice());
        token_rom.write_slice(ReplaceSegment, self.replace_list.slice());
        token_rom.write_slice(ConstSegment, self.const_list.slice());
        token_rom.write_slice(u8, self.const_source.slice());
        token_rom.write_slice(u8, self.seg_list.slice());
        assert(len == token_rom.data.len - ptr);
        token.data_val_or_ptr = ptr;
        token.data_len = len;
        self.cleanup();
        return;
    }

    pub fn parse_from_source(source: *SourceReader, token: *TokenBuilder) void {
        token.kind = TOK.LIT_STR_TEMPLATE;
        var t_string = TemplateStringBuilder.create();
        var is_escape: bool = false;
        var const_builder = Global.U8BufSmall.List.create();
        defer const_builder.release();
        parseloop: while (source.curr.pos < source.data.len) {
            const char = source.read_next_utf8_char(token);
            switch (is_escape) {
                true => {
                    is_escape = false;
                    switch (char.code) {
                        ASC.n => {
                            const_builder.append(ASC.NEWLINE);
                        },
                        ASC.t => {
                            const_builder.append(ASC.H_TAB);
                        },
                        ASC.r => {
                            const_builder.append(ASC.CR);
                        },
                        ASC.B_SLASH, ASC.DUBL_QUOTE, ASC.BACKTICK, ASC.L_CURLY => {
                            const_builder.append(char.bytes[0]);
                        },
                        ASC.o => {
                            const utf8 = source.read_next_n_bytes_as_octal_escape(3, token);
                            const_builder.append_slice(utf8.bytes[0..utf8.len]);
                        },
                        ASC.x => {
                            const utf8 = source.read_next_n_bytes_as_hex_escape(2, token);
                            const_builder.append_slice(utf8.bytes[0..utf8.len]);
                        },
                        ASC.u => {
                            const utf8 = source.read_next_n_bytes_as_hex_escape(4, token);
                            const_builder.append_slice(utf8.bytes[0..utf8.len]);
                        },
                        ASC.U => {
                            const utf8 = source.read_next_n_bytes_as_hex_escape(8, token);
                            const_builder.append_slice(utf8.bytes[0..utf8.len]);
                        },
                        else => {
                            token.attach_notice_here(NOTICE.illegal_string_escape_sequence, SEVERITY.ERROR, source);
                            token.kind = TOK.ILLEGAL;
                            const_builder.append_slice(UNI.REP_CHAR_BYTES[0..UNI.REP_CHAR_LEN]);
                        },
                    }
                },
                else => {
                    switch (char.code) {
                        ASC.NEWLINE => {
                            const_builder.append(ASC.NEWLINE);
                            source.skip_whitespace_except_newline();
                            if (source.curr.pos < source.data.len) {
                                const next_byte = source.read_next_ascii(token);
                                switch (next_byte) {
                                    ASC.BACKTICK => {},
                                    ASC.NEWLINE => {
                                        if (const_builder.len > 0) {
                                            t_string.push_const_segment(const_builder.slice());
                                            const_builder.clear();
                                        }
                                        token.attach_notice_here(NOTICE.runaway_multiline_string, SEVERITY.ERROR, source);
                                        token.kind = TOK.ILLEGAL;
                                        break :parseloop;
                                    },
                                    else => {
                                        token.attach_notice_here(NOTICE.non_whitespace_before_backtick_in_multiline_string, SEVERITY.ERROR, source);
                                        token.kind = TOK.ILLEGAL;
                                    },
                                }
                            } else {
                                if (const_builder.len > 0) {
                                    t_string.push_const_segment(const_builder.slice());
                                }
                                token.attach_notice_here(NOTICE.source_ended_before_string_terminated, SEVERITY.ERROR, source);
                                token.kind = TOK.ILLEGAL;
                                break :parseloop;
                            }
                        },
                        ASC.B_SLASH => {
                            is_escape = true;
                        },
                        ASC.L_CURLY => {
                            if (const_builder.len > 0) {
                                t_string.push_const_segment(const_builder.slice());
                                const_builder.clear();
                            }
                            source.skip_whitespace();
                            const ident_result = IdentBlock.parse_from_source(source, token, false);

                            var ident_idx: u32 = 0;
                            while (ident_idx < t_string.ident_list.len) {
                                if (IdentBlock.eql(ident_result.ident, t_string.ident_list.ptr[ident_idx])) break;
                                ident_idx += 1;
                            }
                            if (ident_idx == t_string.ident_list.len) {
                                t_string.ident_list.append(ident_result.ident);
                            }
                            source.skip_whitespace();
                            const separator_or_end = source.read_next_ascii(token);
                            const format_start = source.curr.pos;
                            switch (separator_or_end) {
                                ASC.R_CURLY => {},
                                ASC.COLON => {
                                    //HACK actually process format section in the future
                                    source.skip_until_byte_match(ASC.R_CURLY);
                                },
                                else => {
                                    token.attach_notice_here(NOTICE.illegal_char_after_template_string_replace_ident, SEVERITY.ERROR, source);
                                    token.kind = TOK.ILLEGAL;
                                    source.skip_until_byte_match(ASC.R_CURLY);
                                },
                            }
                            t_string.push_replace_segment(ReplaceSegment{
                                .start = format_start,
                                .end = source.curr.pos,
                                .input = ident_idx,
                            });
                        },
                        ASC.DUBL_QUOTE => {
                            if (const_builder.len > 0) {
                                t_string.push_const_segment(const_builder.slice());
                            }
                            break :parseloop;
                        },
                        else => {
                            const_builder.append_slice(char.bytes[0..char.len]);
                        },
                    }
                },
            }
        }
        if (token.kind == TOK.ILLEGAL) {
            t_string.cleanup();
            return;
        }
        return t_string.serialize_to_token_rom(token);
    }
};

const FMT = struct {
    // Number formatting
    const DEFAULT = 0;
    const DECIMAL = 1; // d
    const BINARY = 2; // b
    const OCTAL = 3; // o
    const HEXLOWER = 4; // h
    const HEXUPPER = 5; // H
    const UNICODE = 6; // u
    const UNICODE_LOWER = 7; // a
    const UNICODE_UPPER = 8; // A
    const BASE_32 = 9; // x32
    const BASE_58 = 10; // x58
    const BASE_64 = 11; // x64
    const BASE_64_WEB = 12; // x64W
    const BASE_85 = 13; // x85
    const BASE_94 = 14; // x94
    const BASE_128 = 15; // x128
    const NUMBER_FMT_MASK = 0b1111;
    const NUMBER_FMT_BITS = 4;

    // List formatting
    const LIST_FMT_OFFSET = NUMBER_FMT_BITS;
    const LIST_DEFAULT = 0 << LIST_FMT_OFFSET;
    const LIST_INDIVIDUAL = 1 << LIST_FMT_OFFSET; // i
    const LIST_BYTE_STREAM = 2 << LIST_FMT_OFFSET; // s
    const LIST_TYPE_STREAM = 3 << LIST_FMT_OFFSET; // S
    const LIST_FMT_MASK = 0b11 << LIST_FMT_OFFSET;
    const LIST_FMT_BITS = 2;

    // Object formatting
    const OBJECT_FMT_OFFSET = LIST_FMT_OFFSET + LIST_FMT_BITS;
    const OBJECT_PUNCTUATION = 1 << 0 + OBJECT_FMT_OFFSET;
    const OBJECT_LABEL = 1 << 1 + OBJECT_FMT_OFFSET;
    const OBJECT_ALIGN = 1 << 2 + OBJECT_FMT_OFFSET;
    const OBJECT_STACK_SIZE = 1 << 3 + OBJECT_FMT_OFFSET;
    const OBJECT_TYPE = 1 << 4 + OBJECT_FMT_OFFSET;
    const OBJECT_FIELD_OFFSET = 1 << 5 + OBJECT_FMT_OFFSET;
    const OBJECT_HEAP_SIZE = 1 << 6 + OBJECT_FMT_OFFSET;
    const OBJECT_TOTAL_SIZE = 1 << 7 + OBJECT_FMT_OFFSET;
    const OBJECT_EXPAND_PTRS = 1 << 8 + OBJECT_FMT_OFFSET;
    const OBJECT_EXPAND_SUB_LISTS = 1 << 9 + OBJECT_FMT_OFFSET;
    const OBJECT_EXPAND_SUB_OBJECTS = 1 << 10 + OBJECT_FMT_OFFSET;
    const OBJECT_PADDING = 1 << 11 + OBJECT_FMT_OFFSET;
    const OBJECT_FMT_BITS = 12;

    const OBJECT_LEVEL_0 = 0; // L0
    const OBJECT_LEVEL_1 = OBJECT_LEVEL_0 | OBJECT_PUNCTUATION;
    const OBJECT_LEVEL_2 = OBJECT_LEVEL_1 | OBJECT_TYPE;
    const OBJECT_LEVEL_3 = OBJECT_LEVEL_2 | OBJECT_LABEL;

    // Align formatting
    const ALIGN_FMT_OFFSET = OBJECT_FMT_OFFSET + OBJECT_FMT_BITS;
    const ALIGN_LEFT = 0 << ALIGN_FMT_OFFSET; // <
    const ALIGN_CENTER = 1 << ALIGN_FMT_OFFSET; // ^
    const ALIGN_RIGHT = 2 << ALIGN_FMT_OFFSET; // >
    const ALIGN_JUSTIFY = 3 << ALIGN_FMT_OFFSET; // ~
    const ALIGN_EQUAL = 4 << ALIGN_FMT_OFFSET; // =
    // const ALIGN_UNUSED = 5->7 << ALIGN_FMT_OFFSET;
    const ALIGN_FMT_MASK = 0b111 << LIST_FMT_OFFSET;
    const ALIGN_FMT_BITS = 3;

    // Dump raw memory bytes
    const DUMP_RAW_OFFSET = ALIGN_FMT_OFFSET + ALIGN_FMT_BITS;
    const DUMP_RAW = 1 << DUMP_RAW_OFFSET;
    const FMT_TOTAL_BITS = DUMP_RAW_OFFSET + 1;
    const FMT_TYPE = switch (FMT_TOTAL_BITS) {
        0...8 => u8,
        9...16 => u16,
        17...32 => u32,
        33...64 => u64,
        else => unreachable,
    };
};

const FSTR = struct {
    // Integer interpretation
    const DECIMAL = ASC.d;
    const BINARY = ASC.b;
    const OCTAL = ASC.o;
    const HEXLOWER = ASC.h;
    const HEXUPPER = ASC.H;
    const UNICODE = ASC.u;
    const UNICODE_LOWER = ASC.a;
    const UNICODE_UPPER = ASC.A;
    const BASE_N = ASC.x;
    const BASE_2 = 2;
    const BASE_8 = 8;
    const BASE_10 = 10;
    const BASE_16 = 16;
    const BASE_32 = 32;
    const BASE_58 = 58;
    const BASE_64 = 64;
    const WEB_ENC = ASC.W;
    const BASE_64_WEB = 65;
    const BASE_85 = 85;
    const BASE_94 = 94;
    const BASE_128 = 128;
    const FLOAT_PRECISION = ASC.PERIOD;
    const ALIGN_LEFT = ASC.LESS_THAN;
    const ALIGN_CENTER = ASC.CARET;
    const ALIGN_RIGHT = ASC.MORE_THAN;
    const ALIGN_JUSTIFY = ASC.TILDE;
    const ALIGN_EQUAL = ASC.EQUALS;
    const ALIGN_MAGNITUDE = ASC.HASH;
    // Homogenous list interpretation
    const LIST_INDIVIDUAL = ASC.i;
    const LIST_BYTE_STREAM = ASC.s;
    const LIST_TYPE_STREAM = ASC.S;
    const LITTLE_ENDIAN_STREAM = ASC.e;
    const BIG_ENDIAN_STREAM = ASC.E;
    const COL_WIDTH = ASC.c;
    const COL_COUNT = ASC.C;
    const ROW_WIDTH = ASC.r;
    const ROW_COUNT = ASC.R;
    const FILL_CHAR = ASC.f;
    const H_TRUNC_CHAR = ASC.t;
    const V_TRUNC_CHAR = ASC.T;
    const LIST_SEP_CHAR = ASC.l;
};
