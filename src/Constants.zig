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
    pub const ZERO: f64 = 0.0;
};

pub const U64 = struct {
    pub const MAX = 0xFF_FF_FF_FF_FF_FF_FF_FF; // 18446744073709551615
};
