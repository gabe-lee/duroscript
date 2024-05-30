const std = @import("std");

pub const POWER_10_TABLE = [20]u64{
    1,
    10,
    100,
    1000,
    10000,
    100000,
    1000000,
    10000000,
    100000000,
    1000000000,
    10000000000,
    100000000000,
    1000000000000,
    10000000000000,
    100000000000000,
    1000000000000000,
    10000000000000000,
    100000000000000000,
    1000000000000000000,
    10000000000000000000,
};

pub const FAST_F64_POW_10_TABLE = [32]f64{
    1e0,  1e1,  1e2,  1e3,  1e4,  1e5,  1e6,  1e7,
    1e8,  1e9,  1e10, 1e11, 1e12, 1e13, 1e14, 1e15,
    1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22, 0,
    0,    0,    0,    0,    0,    0,    0,    0,
};

pub const F64 = struct {
    // pub const MAX_MANTISSA_BIN = 9007199254740991;
    pub const MANTISSA_EXPLICIT_BITS = 52;
    pub const MANTISSA_TOTAL_BITS = MANTISSA_EXPLICIT_BITS + 1;
    pub const MAX_SIG_DECIMAL = 99999999999999999;
    pub const MAX_SIG_DECIMAL_AT_MAX_EXP = 17976931348623157;
    pub const MIN_SIG_DECIMAL_AT_MIN_EXP = 49406564584124654;
    pub const MAX_EXPONENT = 308;
    pub const MIN_EXPONENT = -324;
    pub const MAX_SIG_DIGITS = 17;
    pub const MAX_FINITE_EXPONENT_BASE_2_UNSIGNED = 2046;
    pub const EXPONENT_BIAS_BASE_2 = 1023;

    pub const POS_INF = std.math.inf(f64);
    pub const NEG_INF = -POS_INF;
    pub const ZERO = 0.0;
};

pub const U64 = struct {
    pub const MAX = 0xFF_FF_FF_FF_FF_FF_FF_FF; // 18446744073709551615
};

// 31415962583755275
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
