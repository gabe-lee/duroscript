const WARN = @import("./Token.zig").WARN;
const ASC = @import("./constants.zig").ASCII;
const std = @import("std");
const assert = std.debug.assert;

pub const UTF8_DecodeResult = struct {
    code: u32,
    code_bytes: [4]u8,
    code_len: u8,
    read_bytes: [4]u8,
    read_len: u8,
    warn: WARN,

    inline fn new(code: u32, code_bytes: [4]u8, code_len: u8, read_bytes: [4]u8, read_len: u8, warn: WARN) UTF8_DecodeResult {
        return UTF8_DecodeResult{
            .code = code,
            .code_bytes = code_bytes,
            .code_len = code_len,
            .read_bytes = read_bytes,
            .read_len = read_len,
            .warn = warn,
        };
    }
};

pub const UTF8_EncodeResult = struct {
    code_bytes: [4]u8,
    code_len: u8,

    inline fn new(code_bytes: [4]u8, code_len: u8) UTF8_EncodeResult {
        return UTF8_EncodeResult{
            .code_bytes = code_bytes,
            .code_len = code_len,
        };
    }
};

pub const REP_CHAR = 0xFFFD;
pub const REP_CHAR_BYTES = [4]u8{ 0xEF, 0xBF, 0xBD, 0 };
pub const REP_CHAR_LEN = 3;

const BYTE_1_OF_1_PRE_MASK = 0b1_0000000;
const BYTE_1_OF_1_PREFIX = 0b0_0000000;
const BYTE_1_OF_1_VAL_MASK = 0b0_1111111;
const BYTE_1_OF_1_MIN = 0b0_0000000;
const BYTE_1_OF_1_MAX = 0b0_1111111;

const CONT_BYTE_PRE_MASK = 0b11_000000;
const CONT_BYTE_PREFIX = 0b10_000000;
const CONT_BYTE_VAL_MASK = 0b00_111111;
const CONT_BYTE_MIN = 0b10_000000;
const CONT_BYTE_MAX = 0b10_111111;

const BYTE_1_OF_2_PRE_MASK = 0b111_00000;
const BYTE_1_OF_2_PREFIX = 0b110_00000;
const BYTE_1_OF_2_VAL_MASK = 0b000_11111;
const BYTE_1_OF_2_MIN = 0b110_00000;
const BYTE_1_OF_2_MAX = 0b110_11111;

const BYTE_1_OF_3_PRE_MASK = 0b1111_0000;
const BYTE_1_OF_3_PREFIX = 0b1110_0000;
const BYTE_1_OF_3_VAL_MASK = 0b0000_1111;
const BYTE_1_OF_3_MIN = 0b1110_0000;
const BYTE_1_OF_3_MAX = 0b1110_1111;

const BYTE_1_OF_4_PRE_MASK = 0b11111_000;
const BYTE_1_OF_4_PREFIX = 0b11110_000;
const BYTE_1_OF_4_VAL_MASK = 0b00000_111;
const BYTE_1_OF_4_MIN = 0b11110_000;
const BYTE_1_OF_4_MAX = 0b11110_111;

pub const MIN_1_BYTE_CODE_POINT = 0x0;
pub const MAX_1_BYTE_CODE_POINT = 0x7F;
pub const MIN_2_BYTE_CODE_POINT = 0x80;
pub const MAX_2_BYTE_CODE_POINT = 0x7FF;
pub const MIN_3_BYTE_CODE_POINT = 0x800;
pub const MAX_3_BYTE_CODE_POINT = 0xFFFF;
pub const MIN_4_BYTE_CODE_POINT = 0x10000;
pub const MAX_4_BYTE_CODE_POINT = 0x10FFFF;

pub const MIN_SURG_PAIR_CODE_POINT = 0xD800;
pub const MAX_SURG_PAIR_CODE_POINT = 0xDFFF;

pub inline fn is_valid_codepoint(code: u32) bool {
    return code < MAX_4_BYTE_CODE_POINT and (code < MIN_SURG_PAIR_CODE_POINT or code > MAX_SURG_PAIR_CODE_POINT);
}

pub fn encode_valid_codepoint(code: u32) UTF8_EncodeResult {
    return switch (code) {
        MIN_1_BYTE_CODE_POINT...MAX_1_BYTE_CODE_POINT => UTF8_EncodeResult.new([4]u4{
            @truncate(code),
            0,
            0,
            0,
        }, 1),
        MIN_2_BYTE_CODE_POINT...MAX_2_BYTE_CODE_POINT => UTF8_EncodeResult.new([4]u4{
            (@as(u8, @truncate(code >> 6)) & BYTE_1_OF_2_VAL_MASK) | BYTE_1_OF_2_PREFIX,
            (@as(u8, @truncate(code)) & CONT_BYTE_VAL_MASK) | CONT_BYTE_PREFIX,
            0,
            0,
        }, 2),
        MIN_3_BYTE_CODE_POINT...MAX_3_BYTE_CODE_POINT => UTF8_EncodeResult.new([4]u4{
            (@as(u8, @truncate(code >> 12)) & BYTE_1_OF_3_VAL_MASK) | BYTE_1_OF_3_PREFIX,
            (@as(u8, @truncate(code >> 6)) & CONT_BYTE_VAL_MASK) | CONT_BYTE_PREFIX,
            (@as(u8, @truncate(code)) & CONT_BYTE_VAL_MASK) | CONT_BYTE_PREFIX,
            0,
        }, 3),
        MIN_4_BYTE_CODE_POINT...MAX_4_BYTE_CODE_POINT => UTF8_EncodeResult.new([4]u4{
            (@as(u8, @truncate(code >> 18)) & BYTE_1_OF_4_VAL_MASK) | BYTE_1_OF_4_PREFIX,
            (@as(u8, @truncate(code >> 12)) & CONT_BYTE_VAL_MASK) | CONT_BYTE_PREFIX,
            (@as(u8, @truncate(code >> 6)) & CONT_BYTE_VAL_MASK) | CONT_BYTE_PREFIX,
            (@as(u8, @truncate(code)) & CONT_BYTE_VAL_MASK) | CONT_BYTE_PREFIX,
        }, 4),
        else => unreachable,
    };
}

// pub fn read_next_utf8_char(source: []const u8) UTF8_DecodeResult {
//     assert(source.len > 0);
//     const utf8_len: u8 = switch (source[0]) {
//         BYTE_1_OF_1_MIN...BYTE_1_OF_1_MAX => 1,
//         BYTE_1_OF_2_MIN...BYTE_1_OF_2_MAX => 2,
//         BYTE_1_OF_3_MIN...BYTE_1_OF_3_MAX => 3,
//         BYTE_1_OF_4_MIN...BYTE_1_OF_4_MAX => 4,
//         CONT_BYTE_MIN...CONT_BYTE_MAX => return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, [4]u8{ source[0], 0, 0, 0 }, 1, WARN.WARN_UTF8_UNEXPECTED_CONTINUATION_BYTE),
//         else => return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, [4]u8{ source[0], 0, 0, 0 }, 1, WARN.WARN_UTF8_ILLEGAL_FIRST_BYTE),
//     };
//     switch (utf8_len) {
//         1 => {
//             return UTF8_DecodeResult.new(source[0], [4]u8{ source[0], 0, 0, 0 }, 1, [4]u8{ source[0], 0, 0, 0 }, 1, WARN.NONE);
//         },
//         2 => {
//             var bytes = [4]u8{ source[0], 0, 0, 0 };
//             if (source.len < 2)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 1, WARN.WARN_UTF8_SOURCE_ENDED_EARLY);
//             bytes[1] = source[1];
//             if (source[1] & CONT_BYTE_PRE_MASK != CONT_BYTE_PREFIX)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 1, WARN.WARN_UTF8_MISSING_CONTINUATION_BYTE);
//             const code: u32 =
//                 ((source[0] & BYTE_1_OF_2_VAL_MASK) << 6) |
//                 (source[1] & CONT_BYTE_VAL_MASK);
//             if (code < MIN_2_BYTE_CODE_POINT)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 2, WARN.WARN_UTF8_OVERLONG_ENCODING);
//             return UTF8_DecodeResult.new(code, bytes, 2, bytes, 2, WARN.NONE);
//         },
//         3 => {
//             var bytes = [4]u8{ source[0], 0, 0, 0 };
//             if (source.len < 2)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 1, WARN.WARN_UTF8_SOURCE_ENDED_EARLY);
//             bytes[1] = source[1];
//             if (source[1] & CONT_BYTE_PRE_MASK != CONT_BYTE_PREFIX)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 1, WARN.WARN_UTF8_MISSING_CONTINUATION_BYTE);
//             if (source.len < 3)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 2, WARN.WARN_UTF8_SOURCE_ENDED_EARLY);
//             bytes[2] = source[2];
//             if (source[2] & CONT_BYTE_PRE_MASK != CONT_BYTE_PREFIX)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 2, WARN.WARN_UTF8_MISSING_CONTINUATION_BYTE);
//             const code: u32 =
//                 ((source[0] & BYTE_1_OF_3_VAL_MASK) << 12) |
//                 ((source[1] & CONT_BYTE_VAL_MASK) << 6) |
//                 (source[2] & CONT_BYTE_VAL_MASK);
//             if ((code >= MIN_SURG_PAIR_CODE_POINT) or (code <= MAX_SURG_PAIR_CODE_POINT))
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 3, WARN.WARN_UTF8_ILLEGAL_CHAR_CODE);
//             if (code < MIN_3_BYTE_CODE_POINT)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 3, WARN.WARN_UTF8_OVERLONG_ENCODING);
//             return UTF8_DecodeResult.new(code, bytes, 3, bytes, 3, WARN.NONE);
//         },
//         4 => {
//             var bytes = [4]u8{ source[0], 0, 0, 0 };
//             if (source.len < 2) {
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 1, WARN.WARN_UTF8_SOURCE_ENDED_EARLY);
//             }
//             bytes[1] = source[1];
//             if (source[1] & CONT_BYTE_PRE_MASK != CONT_BYTE_PREFIX) {
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 1, WARN.WARN_UTF8_MISSING_CONTINUATION_BYTE);
//             }
//             if (source.len < 3) {
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 2, WARN.WARN_UTF8_SOURCE_ENDED_EARLY);
//             }
//             bytes[2] = source[2];
//             if (source[2] & CONT_BYTE_PRE_MASK != CONT_BYTE_PREFIX) {
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 2, WARN.WARN_UTF8_MISSING_CONTINUATION_BYTE);
//             }
//             if (source.len < 4) {
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 3, WARN.WARN_UTF8_SOURCE_ENDED_EARLY);
//             }
//             bytes[3] = source[3];
//             if (source[3] & CONT_BYTE_PRE_MASK != CONT_BYTE_PREFIX) {
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 3, WARN.WARN_UTF8_MISSING_CONTINUATION_BYTE);
//             }
//             const code: u32 =
//                 ((source[0] & BYTE_1_OF_3_VAL_MASK) << 18) |
//                 ((source[1] & CONT_BYTE_VAL_MASK) << 12) |
//                 ((source[2] & CONT_BYTE_VAL_MASK) << 6) |
//                 (source[3] & CONT_BYTE_VAL_MASK);
//             if (code > MAX_4_BYTE_CODE_POINT)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 4, WARN.WARN_UTF8_ILLEGAL_CHAR_CODE);
//             if (code < MIN_4_BYTE_CODE_POINT)
//                 return UTF8_DecodeResult.new(REP_CHAR, REP_CHAR_BYTES, REP_CHAR_LEN, bytes, 4, WARN.WARN_UTF8_OVERLONG_ENCODING);
//             return UTF8_DecodeResult.new(code, bytes, 4, bytes, 4, WARN.NONE);
//         },
//         else => unreachable,
//     }
// }

pub const ASCII = struct {
    // Control chars
    pub const NUL = 0x00;
    pub const SOH = 0x01;
    pub const STX = 0x02;
    pub const ETX = 0x03;
    pub const EOT = 0x04;
    pub const ENQ = 0x05;
    pub const ACK = 0x06;
    pub const BEL = 0x07;
    pub const BS = 0x08;
    pub const H_TAB = 0x09;
    pub const NEWLINE = 0x0A;
    pub const VT = 0x0B;
    pub const FF = 0x0C;
    pub const CR = 0x0D;
    pub const SO = 0x0E;
    pub const SI = 0x0F;
    pub const DLE = 0x10;
    pub const DC1 = 0x11;
    pub const DC2 = 0x12;
    pub const DC3 = 0x13;
    pub const DC4 = 0x14;
    pub const NAK = 0x15;
    pub const SYN = 0x16;
    pub const ETB = 0x17;
    pub const CAN = 0x18;
    pub const EM = 0x19;
    pub const SUB = 0x1A;
    pub const ESC = 0x1B;
    pub const FS = 0x1C;
    pub const GS = 0x1D;
    pub const RS = 0x1E;
    pub const US = 0x1F;
    // Printable chars
    pub const SPACE = 0x20;
    pub const EXCLAIM = 0x21;
    pub const DUBL_QUOTE = 0x22;
    pub const HASH = 0x23;
    pub const DOLLAR = 0x24;
    pub const PERCENT = 0x25;
    pub const AMPER = 0x26;
    pub const SNGL_QUOTE = 0x27;
    pub const L_PAREN = 0x28;
    pub const R_PAREN = 0x29;
    pub const ASTERISK = 0x2A;
    pub const PLUS = 0x2B;
    pub const COMMA = 0x2C;
    pub const MINUS = 0x2D;
    pub const PERIOD = 0x2E;
    pub const F_SLASH = 0x2F;
    pub const _0 = 0x30;
    pub const _1 = 0x31;
    pub const _2 = 0x32;
    pub const _3 = 0x33;
    pub const _4 = 0x34;
    pub const _5 = 0x35;
    pub const _6 = 0x36;
    pub const _7 = 0x37;
    pub const _8 = 0x38;
    pub const _9 = 0x39;
    pub const COLON = 0x3A;
    pub const SEMICOL = 0x3B;
    pub const LESS_THAN = 0x3C;
    pub const EQUALS = 0x3D;
    pub const MORE_THAN = 0x3E;
    pub const QUESTION = 0x3F;
    pub const AT_SIGN = 0x40;
    pub const A = 0x41;
    pub const B = 0x42;
    pub const C = 0x43;
    pub const D = 0x44;
    pub const E = 0x45;
    pub const F = 0x46;
    pub const G = 0x47;
    pub const H = 0x48;
    pub const I = 0x49;
    pub const J = 0x4A;
    pub const K = 0x4B;
    pub const L = 0x4C;
    pub const M = 0x4D;
    pub const N = 0x4E;
    pub const O = 0x4F;
    pub const P = 0x50;
    pub const Q = 0x51;
    pub const R = 0x52;
    pub const S = 0x53;
    pub const T = 0x54;
    pub const U = 0x55;
    pub const V = 0x56;
    pub const W = 0x57;
    pub const X = 0x58;
    pub const Y = 0x59;
    pub const Z = 0x5A;
    pub const L_SQUARE = 0x5B;
    pub const B_SLASH = 0x5C;
    pub const R_SQUARE = 0x5D;
    pub const CARET = 0x5E;
    pub const UNDERSCORE = 0x5F;
    pub const BACKTICK = 0x60;
    pub const a = 0x61;
    pub const b = 0x62;
    pub const c = 0x63;
    pub const d = 0x64;
    pub const e = 0x65;
    pub const f = 0x66;
    pub const g = 0x67;
    pub const h = 0x68;
    pub const i = 0x69;
    pub const j = 0x6A;
    pub const k = 0x6B;
    pub const l = 0x6C;
    pub const m = 0x6D;
    pub const n = 0x6E;
    pub const o = 0x6F;
    pub const p = 0x70;
    pub const q = 0x71;
    pub const r = 0x72;
    pub const s = 0x73;
    pub const t = 0x74;
    pub const u = 0x75;
    pub const v = 0x76;
    pub const w = 0x77;
    pub const x = 0x78;
    pub const y = 0x79;
    pub const z = 0x7A;
    pub const L_CURLY = 0x7B;
    pub const PIPE = 0x7C;
    pub const R_CURLY = 0x7D;
    pub const TILDE = 0x7E;
    pub const DEL = 0x7F;
};
