const CONST = @import("./constants.zig");
const FAST_F64_POW_10_TABLE = CONST.FAST_F64_POW_10_TABLE;
const POWER_10_TABLE = CONST.POWER_10_TABLE;
const F64 = CONST.F64;
const U64 = CONST.U64;
const std = @import("std");
const math = std.math;
const ASC = @import("./constants.zig").ASCII;
const assert = std.debug.assert;

// ************************************************************************
// below code is copied/converted from zig std source for parsing f64 strings,
// removing unneeded checks and re-working branches and naming conventions
// ************************************************************************
const MIN_EXPONENT_FAST_PATH = -22;
const MAX_EXPONENT_FAST_PATH = 22;
const MAX_EXPONENT_FAST_PATH_DISGUISED = 37;
const MAX_MANTISSA_FAST_PATH = 2 << 52;

const MIN_EXPONENT_EISEL_LEMIRE_MAX_LO_BITS = -27;
const MAX_EXPONENT_EISEL_LEMIRE_MAX_HI_BITS = 55;

const MIN_EXPONENT_ROUND_TO_EVEN_EISEL_LEMIRE = -4;
const MAX_EXPONENT_ROUND_TO_EVEN_EISEL_LEMIRE = 23;

pub const SlowParseBuffer = [26]u8;

const f64_ex = struct {
    lo_bits: u64 = 0,
    hi_bits: u64 = 0,

    fn new(lo_bits: u64, hi_bits: u64) f64_ex {
        return f64_ex{
            .lo_bits = lo_bits,
            .hi_bits = hi_bits,
        };
    }

    fn mul(a: u64, b: u64) f64_ex {
        const x = @as(f64_ex, a) * b;
        return f64_ex{
            .hi_bits = @as(u64, @truncate(x >> 64)),
            .lo_bits = @as(u64, @truncate(x)),
        };
    }
};

pub fn parse_float_from_decimal_parts(mantissa: u64, exponent: i64, negative: bool, slow_buf: SlowParseBuffer, slow_idx: usize) f64 {
    assert(mantissa <= F64.MAX_SIG_VALUE);
    assert(exponent < F64.MAX_EXPONENT or (exponent == F64.MAX_EXPONENT and mantissa <= F64.MAX_SIG_DECIMAL_AT_MAX_EXP));
    assert(exponent > F64.MIN_EXPONENT or (exponent == F64.MIN_EXPONENT and mantissa >= F64.MIN_SIG_DECIMAL_AT_MIN_EXP));

    // fast path
    if (MIN_EXPONENT_FAST_PATH <= exponent and
        exponent <= MAX_EXPONENT_FAST_PATH_DISGUISED and
        mantissa <= MAX_MANTISSA_FAST_PATH)
    {
        var value: f64 = 0.0;
        var can_use_fast_path = true;
        if (exponent <= MAX_EXPONENT_FAST_PATH) {
            // normal fast path
            value = @as(f64, @floatFromInt(mantissa));
            value = if (exponent < 0)
                value / FAST_F64_POW_10_TABLE[@as(usize, @intCast(-exponent)) & 31]
            else
                value * FAST_F64_POW_10_TABLE[@as(usize, @intCast(exponent)) & 31];
        } else {
            // disguised fast path
            const shift = exponent - MAX_EXPONENT_FAST_PATH;
            const shift_mantissa = math.mul(u64, mantissa, POWER_10_TABLE[@as(usize, @intCast(shift))]) catch blk: {
                can_use_fast_path = false;
                break :blk (MAX_MANTISSA_FAST_PATH + 1);
            };
            if (shift_mantissa <= MAX_MANTISSA_FAST_PATH) {
                value = @as(f64, @floatFromInt(shift_mantissa)) * FAST_F64_POW_10_TABLE[MAX_EXPONENT_FAST_PATH];
            }
        }
        if (can_use_fast_path) {
            if (negative) {
                value = -value;
            }
            return value;
        }
    }

    // medium path (Eisel-Lemire)
    if (try_eisel_lemire_path(mantissa, exponent, negative)) |val| {
        return val;
    }

    // slow path
    handle_slow_parse(slow_buf[0..slow_idx], negative);
}

fn try_eisel_lemire_path(mantissa10: u64, exponent10: i64, negative: bool) ?f64 {
    var mantissa2 = mantissa10;

    const leading_zeroes = @clz(@as(u64, @bitCast(mantissa2)));
    mantissa2 = math.shl(u64, mantissa2, leading_zeroes);

    const value_ex = compute_product_approx: {
        const mask = U64.MAX >> (F64.MANTISSA_EXPLICIT_BITS + 3);

        const index = @as(usize, @intCast(exponent10 - @as(i64, @intCast(F64.MIN_EXPONENT))));
        const pow5 = EISEL_LEMIRE_POWERS_OF_FIVE_128[index];

        var first = f64_ex.mul(mantissa2, pow5.lo_bits);

        if (first.hi_bits & mask == mask) {
            const second = f64_ex.mul(mantissa2, pow5.hi_bits);

            first.lo_bits +%= second.hi_bits;
            if (second.hi_bits > first.lo_bits) {
                first.hi_bits += 1;
            }
        }
        break :compute_product_approx f64_ex.new(first.lo_bits, first.hi_bits);
    };
    if (value_ex.lo_bits == U64.MAX and (exponent10 < MIN_EXPONENT_EISEL_LEMIRE_MAX_LO_BITS or exponent10 > MAX_EXPONENT_EISEL_LEMIRE_MAX_HI_BITS)) {
        return null;
    }

    const upper_bit = @as(i32, @intCast(value_ex.hi_bits >> 63));
    mantissa2 = math.shr(u64, value_ex.hi_bits, upper_bit + 64 - @as(i32, @intCast(F64.MANTISSA_EXPLICIT_BITS)) - 3);
    var exponent2 = (((@as(i32, @intCast(exponent10)) *% (217706)) >> 16) + 63) + upper_bit - @as(i32, @intCast(leading_zeroes)) - F64.MIN_EXPONENT;
    if (exponent2 <= 0) {
        if (-exponent2 + 1 >= 64) {
            return F64.ZERO;
        }
        mantissa2 = math.shr(u64, mantissa2, -exponent2 + 1);
        mantissa2 += mantissa2 & 1;
        mantissa2 >>= 1;
        exponent2 = @intFromBool(mantissa2 >= (1 << F64.MANTISSA_EXPLICIT_BITS));
        return assemble_f64_from_base2_parts(mantissa2, exponent2, negative);
    }

    if (value_ex.lo_bits <= 1 and
        exponent10 >= MIN_EXPONENT_ROUND_TO_EVEN_EISEL_LEMIRE and
        exponent10 <= MAX_EXPONENT_ROUND_TO_EVEN_EISEL_LEMIRE and
        mantissa2 & 3 == 1 and
        math.shl(u64, mantissa2, (upper_bit + 64 - @as(i32, @intCast(F64.MANTISSA_EXPLICIT_BITS)) - 3)) == value_ex.hi_bits)
    {
        mantissa2 &= ~@as(u64, 1);
    }

    mantissa2 += mantissa2 & 1;
    mantissa2 >>= 1;
    if (mantissa2 >= 2 << F64.MANTISSA_EXPLICIT_BITS) {
        mantissa2 = 1 << F64.MANTISSA_EXPLICIT_BITS;
        exponent2 += 1;
    }

    mantissa2 &= ~(@as(u64, 1) << F64.MANTISSA_EXPLICIT_BITS);

    //VERIFY unsure if prior preconditions make this check invalid
    if (exponent2 > F64.MAX_FINITE_EXPONENT_BASE_2_UNSIGNED) {
        std.debug.panic("f64 from decimal to base2 produced a base2 exponent\nthat would resolve to an infinite value, even though\ninputs should have been checked to prevent it\nINPUTS:\n\tMantissa: {d}\n\tExponent: {d}\n\tnegative: {}\nRESULTS:\n\tMantissa: {d}\n\tExponent: {d}\n\tnegative: {}", .{ mantissa10, exponent10, negative, mantissa2, exponent2, negative });
    }
    return assemble_f64_from_base2_parts(mantissa2, exponent2, negative);
}

inline fn assemble_f64_from_base2_parts(mantissa_base2: u64, exponent_base2: i32, negative: bool) f64 {
    const bits = mantissa_base2 | (@as(u64, @intCast(exponent_base2)) << F64.MANTISSA_EXPLICIT_BITS) | (@as(u64, @intFromBool(negative)) << 63);
    return @as(f64, @bitCast(@as(u64, @truncate(bits))));
}

// ************************************************************************
// below code is copied/converted from zig std source for parsing f64 strings,
// but remains nearly un-altered except for using concrete types
// ************************************************************************
const max_shift = 60;
const num_powers = 19;
const powers = [_]u8{ 0, 3, 6, 9, 13, 16, 19, 23, 26, 29, 33, 36, 39, 43, 46, 49, 53, 56, 59 };

fn getShift(n: usize) usize {
    return if (n < num_powers) powers[n] else max_shift;
}

fn handle_slow_parse(slow_parse_slice: []const u8, negative: bool) f64 {
    @setCold(true);

    const T = f64;
    const MantissaT = f64;
    const min_exponent = -(1 << (math.floatExponentBits(T) - 1)) + 1;
    const infinite_power = (1 << math.floatExponentBits(T)) - 1;
    const mantissa_explicit_bits = math.floatMantissaBits(T);

    var d = Decimal(T).parse(slow_parse_slice);

    //VERIFY these checks should have been handeled before here
    if (d.num_digits == 0 or d.decimal_point < Decimal(T).min_exponent) {
        std.debug.panic("slow float parse resulted in zero, input = {s}", .{slow_parse_slice});
    } else if (d.decimal_point >= Decimal(T).max_exponent) {
        std.debug.panic("slow float parse resulted in infinity, input = {s}", .{slow_parse_slice});
    }

    var exp2: i32 = 0;

    while (d.decimal_point > 0) {
        const n = @as(usize, @intCast(d.decimal_point));
        const shift = getShift(n);
        d.rightShift(shift);
        //VERIFY this check should be un-needed
        if (d.decimal_point < -Decimal(T).decimal_point_range) {
            std.debug.panic("slow float parse resulted in zero, input = {s}", .{slow_parse_slice});
        }
        exp2 += @as(i32, @intCast(shift));
    }

    while (d.decimal_point <= 0) {
        const shift = blk: {
            if (d.decimal_point == 0) {
                break :blk switch (d.digits[0]) {
                    5...9 => break,
                    0, 1 => @as(usize, 2),
                    else => 1,
                };
            } else {
                const n = @as(usize, @intCast(-d.decimal_point));
                break :blk getShift(n);
            }
        };
        d.leftShift(shift);
        //VERIFY this check should be un-needed
        if (d.decimal_point > Decimal(T).decimal_point_range) {
            std.debug.panic("slow float parse resulted in infinity, input = {s}", .{slow_parse_slice});
        }
        exp2 -= @as(i32, @intCast(shift));
    }

    exp2 -= 1;
    while (min_exponent + 1 > exp2) {
        var n = @as(usize, @intCast((min_exponent + 1) - exp2));
        if (n > max_shift) {
            n = max_shift;
        }
        d.rightShift(n);
        exp2 += @as(i32, @intCast(n));
    }
    //VERIFY this check should be un-needed
    if (exp2 - min_exponent >= infinite_power) {
        std.debug.panic("slow float parse resulted in infinity, input = {s}", .{slow_parse_slice});
    }

    d.leftShift(mantissa_explicit_bits + 1);
    var mantissa = d.round();
    if (mantissa >= (@as(MantissaT, 1) << (mantissa_explicit_bits + 1))) {
        d.rightShift(1);
        exp2 += 1;
        mantissa = d.round();
        //VERIFY this check should be un-needed
        if ((exp2 - min_exponent) >= infinite_power) {
            std.debug.panic("slow float parse resulted in infinity, input = {s}", .{slow_parse_slice});
        }
    }
    var power2 = exp2 - min_exponent;
    if (mantissa < (@as(MantissaT, 1) << mantissa_explicit_bits)) {
        power2 -= 1;
    }

    mantissa &= (@as(MantissaT, 1) << mantissa_explicit_bits) - 1;
    return assemble_f64_from_base2_parts(mantissa, power2, negative);
}

// ************************************************************************
// below code is copied/converted from zig std source for parsing f64 strings,
// but remains nearly un-altered except for using concrete types
// ************************************************************************
const Decimal = struct {
    const Self = @This();
    const MantissaT = u64;
    pub const max_digits = if (MantissaT == u64) 768 else 11564;
    pub const max_digits_without_overflow = if (MantissaT == u64) 19 else 38;
    pub const decimal_point_range = if (MantissaT == u64) 2047 else 32767;
    pub const min_exponent = if (MantissaT == u64) -324 else -4966;
    pub const max_exponent = if (MantissaT == u64) 310 else 4934;
    pub const max_decimal_digits = if (MantissaT == u64) 18 else 37;

    num_digits: usize,
    decimal_point: i32,
    truncated: bool,
    digits: [max_digits]u8,

    pub fn new() Self {
        return .{
            .num_digits = 0,
            .decimal_point = 0,
            .truncated = false,
            .digits = [_]u8{0} ** max_digits,
        };
    }

    pub fn tryAddDigit(self: *Self, digit: u8) void {
        if (self.num_digits < max_digits) {
            self.digits[self.num_digits] = digit;
        }
        self.num_digits += 1;
    }

    pub fn trim(self: *Self) void {
        std.debug.assert(self.num_digits <= max_digits);
        while (self.num_digits != 0 and self.digits[self.num_digits - 1] == 0) {
            self.num_digits -= 1;
        }
    }

    pub fn round(self: *Self) MantissaT {
        if (self.num_digits == 0 or self.decimal_point < 0) {
            return 0;
        } else if (self.decimal_point > max_decimal_digits) {
            return math.maxInt(MantissaT);
        }

        const dp = @as(usize, @intCast(self.decimal_point));
        var n: MantissaT = 0;

        var i: usize = 0;
        while (i < dp) : (i += 1) {
            n *= 10;
            if (i < self.num_digits) {
                n += @as(MantissaT, self.digits[i]);
            }
        }

        var round_up = false;
        if (dp < self.num_digits) {
            round_up = self.digits[dp] >= 5;
            if (self.digits[dp] == 5 and dp + 1 == self.num_digits) {
                round_up = self.truncated or ((dp != 0) and (1 & self.digits[dp - 1] != 0));
            }
        }
        if (round_up) {
            n += 1;
        }
        return n;
    }

    pub fn leftShift(self: *Self, shift: usize) void {
        if (self.num_digits == 0) {
            return;
        }
        const num_new_digits = self.numberOfDigitsLeftShift(shift);
        var read_index = self.num_digits;
        var write_index = self.num_digits + num_new_digits;
        var n: MantissaT = 0;
        while (read_index != 0) {
            read_index -= 1;
            write_index -= 1;
            n += math.shl(MantissaT, self.digits[read_index], shift);

            const quotient = n / 10;
            const remainder = n - (10 * quotient);
            if (write_index < max_digits) {
                self.digits[write_index] = @as(u8, @intCast(remainder));
            } else if (remainder > 0) {
                self.truncated = true;
            }
            n = quotient;
        }
        while (n > 0) {
            write_index -= 1;

            const quotient = n / 10;
            const remainder = n - (10 * quotient);
            if (write_index < max_digits) {
                self.digits[write_index] = @as(u8, @intCast(remainder));
            } else if (remainder > 0) {
                self.truncated = true;
            }
            n = quotient;
        }

        self.num_digits += num_new_digits;
        if (self.num_digits > max_digits) {
            self.num_digits = max_digits;
        }
        self.decimal_point += @as(i32, @intCast(num_new_digits));
        self.trim();
    }

    pub fn rightShift(self: *Self, shift: usize) void {
        var read_index: usize = 0;
        var write_index: usize = 0;
        var n: MantissaT = 0;
        while (math.shr(MantissaT, n, shift) == 0) {
            if (read_index < self.num_digits) {
                n = (10 * n) + self.digits[read_index];
                read_index += 1;
            } else if (n == 0) {
                return;
            } else {
                while (math.shr(MantissaT, n, shift) == 0) {
                    n *= 10;
                    read_index += 1;
                }
                break;
            }
        }

        self.decimal_point -= @as(i32, @intCast(read_index)) - 1;
        if (self.decimal_point < -decimal_point_range) {
            self.num_digits = 0;
            self.decimal_point = 0;
            self.truncated = false;
            return;
        }

        const mask = math.shl(MantissaT, 1, shift) - 1;
        while (read_index < self.num_digits) {
            const new_digit = @as(u8, @intCast(math.shr(MantissaT, n, shift)));
            n = (10 * (n & mask)) + self.digits[read_index];
            read_index += 1;
            self.digits[write_index] = new_digit;
            write_index += 1;
        }
        while (n > 0) {
            const new_digit = @as(u8, @intCast(math.shr(MantissaT, n, shift)));
            n = 10 * (n & mask);
            if (write_index < max_digits) {
                self.digits[write_index] = new_digit;
                write_index += 1;
            } else if (new_digit > 0) {
                self.truncated = true;
            }
        }
        self.num_digits = write_index;
        self.trim();
    }

    pub fn parse(s: []const u8) Self {
        var d = Self.new();
        var stream = FloatStream.init(s);

        stream.skipChars2('0', '_');
        while (stream.scanDigit(10)) |digit| {
            d.tryAddDigit(digit);
        }

        if (stream.firstIs('.')) {
            stream.advance(1);
            const marker = stream.offsetTrue();

            if (d.num_digits == 0) {
                stream.skipChars('0');
            }

            while (stream.hasLen(8) and d.num_digits + 8 < max_digits) {
                const v = stream.readU64Unchecked();
                if (!common_is_eight_digits(v)) {
                    break;
                }
                std.mem.writeInt(u64, d.digits[d.num_digits..][0..8], v - 0x3030_3030_3030_3030, .little);
                d.num_digits += 8;
                stream.advance(8);
            }

            while (stream.scanDigit(10)) |digit| {
                d.tryAddDigit(digit);
            }
            d.decimal_point = @as(i32, @intCast(marker)) - @as(i32, @intCast(stream.offsetTrue()));
        }
        if (d.num_digits != 0) {
            var n_trailing_zeros: usize = 0;
            var i = stream.offsetTrue() - 1;
            while (true) {
                if (s[i] == '0') {
                    n_trailing_zeros += 1;
                } else if (s[i] != '.') {
                    break;
                }

                i -= 1;
                if (i == 0) break;
            }
            d.decimal_point += @as(i32, @intCast(n_trailing_zeros));
            d.num_digits -= n_trailing_zeros;
            d.decimal_point += @as(i32, @intCast(d.num_digits));
            if (d.num_digits > max_digits) {
                d.truncated = true;
                d.num_digits = max_digits;
            }
        }
        if (stream.firstIsLower('e')) {
            stream.advance(1);
            var neg_exp = false;
            if (stream.firstIs('-')) {
                neg_exp = true;
                stream.advance(1);
            } else if (stream.firstIs('+')) {
                stream.advance(1);
            }
            var exp_num: i32 = 0;
            while (stream.scanDigit(10)) |digit| {
                if (exp_num < 0x10000) {
                    exp_num = 10 * exp_num + digit;
                }
            }
            d.decimal_point += if (neg_exp) -exp_num else exp_num;
        }

        var i = d.num_digits;
        while (i < max_digits_without_overflow) : (i += 1) {
            d.digits[i] = 0;
        }

        return d;
    }

    pub fn numberOfDigitsLeftShift(self: *Self, shift: usize) usize {
        const ShiftCutoff = struct {
            delta: u8,
            cutoff: []const u8,
        };

        const pow2_to_pow5_table = [_]ShiftCutoff{
            .{ .delta = 0, .cutoff = "" },
            .{ .delta = 1, .cutoff = "5" }, // 2
            .{ .delta = 1, .cutoff = "25" }, // 4
            .{ .delta = 1, .cutoff = "125" }, // 8
            .{ .delta = 2, .cutoff = "625" }, // 16
            .{ .delta = 2, .cutoff = "3125" }, // 32
            .{ .delta = 2, .cutoff = "15625" }, // 64
            .{ .delta = 3, .cutoff = "78125" }, // 128
            .{ .delta = 3, .cutoff = "390625" }, // 256
            .{ .delta = 3, .cutoff = "1953125" }, // 512
            .{ .delta = 4, .cutoff = "9765625" }, // 1024
            .{ .delta = 4, .cutoff = "48828125" }, // 2048
            .{ .delta = 4, .cutoff = "244140625" }, // 4096
            .{ .delta = 4, .cutoff = "1220703125" }, // 8192
            .{ .delta = 5, .cutoff = "6103515625" }, // 16384
            .{ .delta = 5, .cutoff = "30517578125" }, // 32768
            .{ .delta = 5, .cutoff = "152587890625" }, // 65536
            .{ .delta = 6, .cutoff = "762939453125" }, // 131072
            .{ .delta = 6, .cutoff = "3814697265625" }, // 262144
            .{ .delta = 6, .cutoff = "19073486328125" }, // 524288
            .{ .delta = 7, .cutoff = "95367431640625" }, // 1048576
            .{ .delta = 7, .cutoff = "476837158203125" }, // 2097152
            .{ .delta = 7, .cutoff = "2384185791015625" }, // 4194304
            .{ .delta = 7, .cutoff = "11920928955078125" }, // 8388608
            .{ .delta = 8, .cutoff = "59604644775390625" }, // 16777216
            .{ .delta = 8, .cutoff = "298023223876953125" }, // 33554432
            .{ .delta = 8, .cutoff = "1490116119384765625" }, // 67108864
            .{ .delta = 9, .cutoff = "7450580596923828125" }, // 134217728
            .{ .delta = 9, .cutoff = "37252902984619140625" }, // 268435456
            .{ .delta = 9, .cutoff = "186264514923095703125" }, // 536870912
            .{ .delta = 10, .cutoff = "931322574615478515625" }, // 1073741824
            .{ .delta = 10, .cutoff = "4656612873077392578125" }, // 2147483648
            .{ .delta = 10, .cutoff = "23283064365386962890625" }, // 4294967296
            .{ .delta = 10, .cutoff = "116415321826934814453125" }, // 8589934592
            .{ .delta = 11, .cutoff = "582076609134674072265625" }, // 17179869184
            .{ .delta = 11, .cutoff = "2910383045673370361328125" }, // 34359738368
            .{ .delta = 11, .cutoff = "14551915228366851806640625" }, // 68719476736
            .{ .delta = 12, .cutoff = "72759576141834259033203125" }, // 137438953472
            .{ .delta = 12, .cutoff = "363797880709171295166015625" }, // 274877906944
            .{ .delta = 12, .cutoff = "1818989403545856475830078125" }, // 549755813888
            .{ .delta = 13, .cutoff = "9094947017729282379150390625" }, // 1099511627776
            .{ .delta = 13, .cutoff = "45474735088646411895751953125" }, // 2199023255552
            .{ .delta = 13, .cutoff = "227373675443232059478759765625" }, // 4398046511104
            .{ .delta = 13, .cutoff = "1136868377216160297393798828125" }, // 8796093022208
            .{ .delta = 14, .cutoff = "5684341886080801486968994140625" }, // 17592186044416
            .{ .delta = 14, .cutoff = "28421709430404007434844970703125" }, // 35184372088832
            .{ .delta = 14, .cutoff = "142108547152020037174224853515625" }, // 70368744177664
            .{ .delta = 15, .cutoff = "710542735760100185871124267578125" }, // 140737488355328
            .{ .delta = 15, .cutoff = "3552713678800500929355621337890625" }, // 281474976710656
            .{ .delta = 15, .cutoff = "17763568394002504646778106689453125" }, // 562949953421312
            .{ .delta = 16, .cutoff = "88817841970012523233890533447265625" }, // 1125899906842624
            .{ .delta = 16, .cutoff = "444089209850062616169452667236328125" }, // 2251799813685248
            .{ .delta = 16, .cutoff = "2220446049250313080847263336181640625" }, // 4503599627370496
            .{ .delta = 16, .cutoff = "11102230246251565404236316680908203125" }, // 9007199254740992
            .{ .delta = 17, .cutoff = "55511151231257827021181583404541015625" }, // 18014398509481984
            .{ .delta = 17, .cutoff = "277555756156289135105907917022705078125" }, // 36028797018963968
            .{ .delta = 17, .cutoff = "1387778780781445675529539585113525390625" }, // 72057594037927936
            .{ .delta = 18, .cutoff = "6938893903907228377647697925567626953125" }, // 144115188075855872
            .{ .delta = 18, .cutoff = "34694469519536141888238489627838134765625" }, // 288230376151711744
            .{ .delta = 18, .cutoff = "173472347597680709441192448139190673828125" }, // 576460752303423488
            .{ .delta = 19, .cutoff = "867361737988403547205962240695953369140625" }, // 1152921504606846976
            .{ .delta = 19, .cutoff = "4336808689942017736029811203479766845703125" }, // 2305843009213693952
            .{ .delta = 19, .cutoff = "21684043449710088680149056017398834228515625" }, // 4611686018427387904
            .{ .delta = 19, .cutoff = "108420217248550443400745280086994171142578125" }, // 9223372036854775808
            .{ .delta = 20, .cutoff = "542101086242752217003726400434970855712890625" }, // 18446744073709551616
            .{ .delta = 20, .cutoff = "2710505431213761085018632002174854278564453125" }, // 36893488147419103232
            .{ .delta = 20, .cutoff = "13552527156068805425093160010874271392822265625" }, // 73786976294838206464
            .{ .delta = 21, .cutoff = "67762635780344027125465800054371356964111328125" }, // 147573952589676412928
            .{ .delta = 21, .cutoff = "338813178901720135627329000271856784820556640625" }, // 295147905179352825856
            .{ .delta = 21, .cutoff = "1694065894508600678136645001359283924102783203125" }, // 590295810358705651712
            .{ .delta = 22, .cutoff = "8470329472543003390683225006796419620513916015625" }, // 1180591620717411303424
            .{ .delta = 22, .cutoff = "42351647362715016953416125033982098102569580078125" }, // 2361183241434822606848
            .{ .delta = 22, .cutoff = "211758236813575084767080625169910490512847900390625" }, // 4722366482869645213696
            .{ .delta = 22, .cutoff = "1058791184067875423835403125849552452564239501953125" }, // 9444732965739290427392
            .{ .delta = 23, .cutoff = "5293955920339377119177015629247762262821197509765625" }, // 18889465931478580854784
            .{ .delta = 23, .cutoff = "26469779601696885595885078146238811314105987548828125" }, // 37778931862957161709568
            .{ .delta = 23, .cutoff = "132348898008484427979425390731194056570529937744140625" }, // 75557863725914323419136
            .{ .delta = 24, .cutoff = "661744490042422139897126953655970282852649688720703125" }, // 151115727451828646838272
            .{ .delta = 24, .cutoff = "3308722450212110699485634768279851414263248443603515625" }, // 302231454903657293676544
            .{ .delta = 24, .cutoff = "16543612251060553497428173841399257071316242218017578125" }, // 604462909807314587353088
            .{ .delta = 25, .cutoff = "82718061255302767487140869206996285356581211090087890625" }, // 1208925819614629174706176
            .{ .delta = 25, .cutoff = "413590306276513837435704346034981426782906055450439453125" }, // 2417851639229258349412352
            .{ .delta = 25, .cutoff = "2067951531382569187178521730174907133914530277252197265625" }, // 4835703278458516698824704
            .{ .delta = 25, .cutoff = "10339757656912845935892608650874535669572651386260986328125" }, // 9671406556917033397649408
            .{ .delta = 26, .cutoff = "51698788284564229679463043254372678347863256931304931640625" }, // 19342813113834066795298816
            .{ .delta = 26, .cutoff = "258493941422821148397315216271863391739316284656524658203125" }, // 38685626227668133590597632
            .{ .delta = 26, .cutoff = "1292469707114105741986576081359316958696581423282623291015625" }, // 77371252455336267181195264
            .{ .delta = 27, .cutoff = "6462348535570528709932880406796584793482907116413116455078125" }, // 154742504910672534362390528
            .{ .delta = 27, .cutoff = "32311742677852643549664402033982923967414535582065582275390625" }, // 309485009821345068724781056
            .{ .delta = 27, .cutoff = "161558713389263217748322010169914619837072677910327911376953125" }, // 618970019642690137449562112
            .{ .delta = 28, .cutoff = "807793566946316088741610050849573099185363389551639556884765625" }, // 1237940039285380274899124224
            .{ .delta = 28, .cutoff = "4038967834731580443708050254247865495926816947758197784423828125" }, // 2475880078570760549798248448
            .{ .delta = 28, .cutoff = "20194839173657902218540251271239327479634084738790988922119140625" }, // 4951760157141521099596496896
            .{ .delta = 28, .cutoff = "100974195868289511092701256356196637398170423693954944610595703125" }, // 9903520314283042199192993792
            .{ .delta = 29, .cutoff = "504870979341447555463506281780983186990852118469774723052978515625" }, // 19807040628566084398385987584
            .{ .delta = 29, .cutoff = "2524354896707237777317531408904915934954260592348873615264892578125" }, // 39614081257132168796771975168
            .{ .delta = 29, .cutoff = "12621774483536188886587657044524579674771302961744368076324462890625" }, // 79228162514264337593543950336
            .{ .delta = 30, .cutoff = "63108872417680944432938285222622898373856514808721840381622314453125" }, // 158456325028528675187087900672
            .{ .delta = 30, .cutoff = "315544362088404722164691426113114491869282574043609201908111572265625" }, // 316912650057057350374175801344
            .{ .delta = 30, .cutoff = "1577721810442023610823457130565572459346412870218046009540557861328125" }, // 633825300114114700748351602688
            .{ .delta = 31, .cutoff = "7888609052210118054117285652827862296732064351090230047702789306640625" }, // 1267650600228229401496703205376
            .{ .delta = 31, .cutoff = "39443045261050590270586428264139311483660321755451150238513946533203125" }, // 2535301200456458802993406410752
            .{ .delta = 31, .cutoff = "197215226305252951352932141320696557418301608777255751192569732666015625" }, // 5070602400912917605986812821504
            .{ .delta = 32, .cutoff = "986076131526264756764660706603482787091508043886278755962848663330078125" }, // 10141204801825835211973625643008
            .{ .delta = 32, .cutoff = "4930380657631323783823303533017413935457540219431393779814243316650390625" }, // 20282409603651670423947251286016
            .{ .delta = 32, .cutoff = "24651903288156618919116517665087069677287701097156968899071216583251953125" }, // 40564819207303340847894502572032
            .{ .delta = 32, .cutoff = "123259516440783094595582588325435348386438505485784844495356082916259765625" }, // 81129638414606681695789005144064
            .{ .delta = 33, .cutoff = "616297582203915472977912941627176741932192527428924222476780414581298828125" }, // 162259276829213363391578010288128
            .{ .delta = 33, .cutoff = "3081487911019577364889564708135883709660962637144621112383902072906494140625" }, // 324518553658426726783156020576256
            .{ .delta = 33, .cutoff = "15407439555097886824447823540679418548304813185723105561919510364532470703125" }, // 649037107316853453566312041152512
            .{ .delta = 34, .cutoff = "77037197775489434122239117703397092741524065928615527809597551822662353515625" }, // 1298074214633706907132624082305024
            .{ .delta = 34, .cutoff = "385185988877447170611195588516985463707620329643077639047987759113311767578125" }, // 2596148429267413814265248164610048
            .{ .delta = 34, .cutoff = "1925929944387235853055977942584927318538101648215388195239938795566558837890625" }, // 5192296858534827628530496329220096
            .{ .delta = 35, .cutoff = "9629649721936179265279889712924636592690508241076940976199693977832794189453125" }, // 10384593717069655257060992658440192
            .{ .delta = 35, .cutoff = "48148248609680896326399448564623182963452541205384704880998469889163970947265625" }, // 20769187434139310514121985316880384
            .{ .delta = 35, .cutoff = "240741243048404481631997242823115914817262706026923524404992349445819854736328125" }, // 41538374868278621028243970633760768
            .{ .delta = 35, .cutoff = "1203706215242022408159986214115579574086313530134617622024961747229099273681640625" }, // 83076749736557242056487941267521536
            .{ .delta = 36, .cutoff = "6018531076210112040799931070577897870431567650673088110124808736145496368408203125" }, // 166153499473114484112975882535043072
            .{ .delta = 36, .cutoff = "30092655381050560203999655352889489352157838253365440550624043680727481842041015625" }, // 332306998946228968225951765070086144
            .{ .delta = 36, .cutoff = "150463276905252801019998276764447446760789191266827202753120218403637409210205078125" }, // 664613997892457936451903530140172288
            .{ .delta = 37, .cutoff = "752316384526264005099991383822237233803945956334136013765601092018187046051025390625" }, // 1329227995784915872903807060280344576
            .{ .delta = 37, .cutoff = "3761581922631320025499956919111186169019729781670680068828005460090935230255126953125" }, // 2658455991569831745807614120560689152
            .{ .delta = 37, .cutoff = "18807909613156600127499784595555930845098648908353400344140027300454676151275634765625" }, // 5316911983139663491615228241121378304
            .{ .delta = 38, .cutoff = "94039548065783000637498922977779654225493244541767001720700136502273380756378173828125" }, // 10633823966279326983230456482242756608
            .{ .delta = 38, .cutoff = "470197740328915003187494614888898271127466222708835008603500682511366903781890869140625" }, // 21267647932558653966460912964485513216
            .{ .delta = 38, .cutoff = "2350988701644575015937473074444491355637331113544175043017503412556834518909454345703125" }, // 42535295865117307932921825928971026432
            .{ .delta = 38, .cutoff = "11754943508222875079687365372222456778186655567720875215087517062784172594547271728515625" }, // 85070591730234615865843651857942052864
            .{ .delta = 39, .cutoff = "58774717541114375398436826861112283890933277838604376075437585313920862972736358642578125" }, // 170141183460469231731687303715884105728
        };

        std.debug.assert(shift < pow2_to_pow5_table.len);
        const x = pow2_to_pow5_table[shift];

        for (x.cutoff, 0..) |p5, i| {
            if (i >= self.num_digits) {
                return x.delta - 1;
            } else if (self.digits[i] == p5 - '0') {
                continue;
            } else if (self.digits[i] < p5 - '0') {
                return x.delta - 1;
            } else {
                return x.delta;
            }
            return x.delta;
        }
        return x.delta;
    }
};

const FloatStream = struct {
    slice: []const u8,
    offset: usize,
    underscore_count: usize,

    pub fn init(s: []const u8) FloatStream {
        return .{ .slice = s, .offset = 0, .underscore_count = 0 };
    }

    pub fn offsetTrue(self: FloatStream) usize {
        return self.offset - self.underscore_count;
    }

    pub fn reset(self: *FloatStream) void {
        self.offset = 0;
        self.underscore_count = 0;
    }

    pub fn len(self: FloatStream) usize {
        if (self.offset > self.slice.len) {
            return 0;
        }
        return self.slice.len - self.offset;
    }

    pub fn hasLen(self: FloatStream, n: usize) bool {
        return self.offset + n <= self.slice.len;
    }

    pub fn firstUnchecked(self: FloatStream) u8 {
        return self.slice[self.offset];
    }

    pub fn first(self: FloatStream) ?u8 {
        return if (self.hasLen(1))
            return self.firstUnchecked()
        else
            null;
    }

    pub fn isEmpty(self: FloatStream) bool {
        return !self.hasLen(1);
    }

    pub fn firstIs(self: FloatStream, c: u8) bool {
        if (self.first()) |ok| {
            return ok == c;
        }
        return false;
    }

    pub fn firstIsLower(self: FloatStream, c: u8) bool {
        if (self.first()) |ok| {
            return ok | 0x20 == c;
        }
        return false;
    }

    pub fn firstIs2(self: FloatStream, c1: u8, c2: u8) bool {
        if (self.first()) |ok| {
            return ok == c1 or ok == c2;
        }
        return false;
    }

    pub fn firstIs3(self: FloatStream, c1: u8, c2: u8, c3: u8) bool {
        if (self.first()) |ok| {
            return ok == c1 or ok == c2 or ok == c3;
        }
        return false;
    }

    pub fn firstIsDigit(self: FloatStream, comptime base: u8) bool {
        comptime std.debug.assert(base == 10 or base == 16);

        if (self.first()) |ok| {
            return common_is_digit(ok);
        }
        return false;
    }

    pub fn advance(self: *FloatStream, n: usize) void {
        self.offset += n;
    }

    pub fn skipChars(self: *FloatStream, c: u8) void {
        while (self.firstIs(c)) : (self.advance(1)) {}
    }

    pub fn skipChars2(self: *FloatStream, c1: u8, c2: u8) void {
        while (self.firstIs2(c1, c2)) : (self.advance(1)) {}
    }

    pub fn readU64Unchecked(self: FloatStream) u64 {
        return std.mem.readInt(u64, self.slice[self.offset..][0..8], .little);
    }

    pub fn readU64(self: FloatStream) ?u64 {
        if (self.hasLen(8)) {
            return self.readU64Unchecked();
        }
        return null;
    }

    pub fn atUnchecked(self: *FloatStream, i: usize) u8 {
        return self.slice[self.offset + i];
    }

    pub fn scanDigit(self: *FloatStream, comptime base: u8) ?u8 {
        comptime std.debug.assert(base == 10 or base == 16);

        retry: while (true) {
            if (self.first()) |ok| {
                if ('0' <= ok and ok <= '9') {
                    self.advance(1);
                    return ok - '0';
                } else if (base == 16 and 'a' <= ok and ok <= 'f') {
                    self.advance(1);
                    return ok - 'a' + 10;
                } else if (base == 16 and 'A' <= ok and ok <= 'F') {
                    self.advance(1);
                    return ok - 'A' + 10;
                } else if (ok == '_') {
                    self.advance(1);
                    self.underscore_count += 1;
                    continue :retry;
                }
            }
            return null;
        }
    }
};

inline fn common_is_digit(byte: u8) bool {
    return (byte >= ASC._0 and byte <= ASC._9);
}

inline fn common_is_eight_digits(v: u64) bool {
    const a = v +% 0x4646_4646_4646_4646;
    const b = v -% 0x3030_3030_3030_3030;
    return ((a | b) & 0x8080_8080_8080_8080) == 0;
}

const EISEL_LEMIRE_POWERS_OF_FIVE_128 = [_]f64_ex{
    f64_ex.new(0xcf42894a5dce35ea, 0x52064cac828675b9), // 5^-324
    f64_ex.new(0x818995ce7aa0e1b2, 0x7343efebd1940993), // 5^-323
    f64_ex.new(0xa1ebfb4219491a1f, 0x1014ebe6c5f90bf8), // 5^-322
    f64_ex.new(0xca66fa129f9b60a6, 0xd41a26e077774ef6), // 5^-321
    f64_ex.new(0xfd00b897478238d0, 0x8920b098955522b4), // 5^-320
    f64_ex.new(0x9e20735e8cb16382, 0x55b46e5f5d5535b0), // 5^-319
    f64_ex.new(0xc5a890362fddbc62, 0xeb2189f734aa831d), // 5^-318
    f64_ex.new(0xf712b443bbd52b7b, 0xa5e9ec7501d523e4), // 5^-317
    f64_ex.new(0x9a6bb0aa55653b2d, 0x47b233c92125366e), // 5^-316
    f64_ex.new(0xc1069cd4eabe89f8, 0x999ec0bb696e840a), // 5^-315
    f64_ex.new(0xf148440a256e2c76, 0xc00670ea43ca250d), // 5^-314
    f64_ex.new(0x96cd2a865764dbca, 0x380406926a5e5728), // 5^-313
    f64_ex.new(0xbc807527ed3e12bc, 0xc605083704f5ecf2), // 5^-312
    f64_ex.new(0xeba09271e88d976b, 0xf7864a44c633682e), // 5^-311
    f64_ex.new(0x93445b8731587ea3, 0x7ab3ee6afbe0211d), // 5^-310
    f64_ex.new(0xb8157268fdae9e4c, 0x5960ea05bad82964), // 5^-309
    f64_ex.new(0xe61acf033d1a45df, 0x6fb92487298e33bd), // 5^-308
    f64_ex.new(0x8fd0c16206306bab, 0xa5d3b6d479f8e056), // 5^-307
    f64_ex.new(0xb3c4f1ba87bc8696, 0x8f48a4899877186c), // 5^-306
    f64_ex.new(0xe0b62e2929aba83c, 0x331acdabfe94de87), // 5^-305
    f64_ex.new(0x8c71dcd9ba0b4925, 0x9ff0c08b7f1d0b14), // 5^-304
    f64_ex.new(0xaf8e5410288e1b6f, 0x7ecf0ae5ee44dd9), // 5^-303
    f64_ex.new(0xdb71e91432b1a24a, 0xc9e82cd9f69d6150), // 5^-302
    f64_ex.new(0x892731ac9faf056e, 0xbe311c083a225cd2), // 5^-301
    f64_ex.new(0xab70fe17c79ac6ca, 0x6dbd630a48aaf406), // 5^-300
    f64_ex.new(0xd64d3d9db981787d, 0x92cbbccdad5b108), // 5^-299
    f64_ex.new(0x85f0468293f0eb4e, 0x25bbf56008c58ea5), // 5^-298
    f64_ex.new(0xa76c582338ed2621, 0xaf2af2b80af6f24e), // 5^-297
    f64_ex.new(0xd1476e2c07286faa, 0x1af5af660db4aee1), // 5^-296
    f64_ex.new(0x82cca4db847945ca, 0x50d98d9fc890ed4d), // 5^-295
    f64_ex.new(0xa37fce126597973c, 0xe50ff107bab528a0), // 5^-294
    f64_ex.new(0xcc5fc196fefd7d0c, 0x1e53ed49a96272c8), // 5^-293
    f64_ex.new(0xff77b1fcbebcdc4f, 0x25e8e89c13bb0f7a), // 5^-292
    f64_ex.new(0x9faacf3df73609b1, 0x77b191618c54e9ac), // 5^-291
    f64_ex.new(0xc795830d75038c1d, 0xd59df5b9ef6a2417), // 5^-290
    f64_ex.new(0xf97ae3d0d2446f25, 0x4b0573286b44ad1d), // 5^-289
    f64_ex.new(0x9becce62836ac577, 0x4ee367f9430aec32), // 5^-288
    f64_ex.new(0xc2e801fb244576d5, 0x229c41f793cda73f), // 5^-287
    f64_ex.new(0xf3a20279ed56d48a, 0x6b43527578c1110f), // 5^-286
    f64_ex.new(0x9845418c345644d6, 0x830a13896b78aaa9), // 5^-285
    f64_ex.new(0xbe5691ef416bd60c, 0x23cc986bc656d553), // 5^-284
    f64_ex.new(0xedec366b11c6cb8f, 0x2cbfbe86b7ec8aa8), // 5^-283
    f64_ex.new(0x94b3a202eb1c3f39, 0x7bf7d71432f3d6a9), // 5^-282
    f64_ex.new(0xb9e08a83a5e34f07, 0xdaf5ccd93fb0cc53), // 5^-281
    f64_ex.new(0xe858ad248f5c22c9, 0xd1b3400f8f9cff68), // 5^-280
    f64_ex.new(0x91376c36d99995be, 0x23100809b9c21fa1), // 5^-279
    f64_ex.new(0xb58547448ffffb2d, 0xabd40a0c2832a78a), // 5^-278
    f64_ex.new(0xe2e69915b3fff9f9, 0x16c90c8f323f516c), // 5^-277
    f64_ex.new(0x8dd01fad907ffc3b, 0xae3da7d97f6792e3), // 5^-276
    f64_ex.new(0xb1442798f49ffb4a, 0x99cd11cfdf41779c), // 5^-275
    f64_ex.new(0xdd95317f31c7fa1d, 0x40405643d711d583), // 5^-274
    f64_ex.new(0x8a7d3eef7f1cfc52, 0x482835ea666b2572), // 5^-273
    f64_ex.new(0xad1c8eab5ee43b66, 0xda3243650005eecf), // 5^-272
    f64_ex.new(0xd863b256369d4a40, 0x90bed43e40076a82), // 5^-271
    f64_ex.new(0x873e4f75e2224e68, 0x5a7744a6e804a291), // 5^-270
    f64_ex.new(0xa90de3535aaae202, 0x711515d0a205cb36), // 5^-269
    f64_ex.new(0xd3515c2831559a83, 0xd5a5b44ca873e03), // 5^-268
    f64_ex.new(0x8412d9991ed58091, 0xe858790afe9486c2), // 5^-267
    f64_ex.new(0xa5178fff668ae0b6, 0x626e974dbe39a872), // 5^-266
    f64_ex.new(0xce5d73ff402d98e3, 0xfb0a3d212dc8128f), // 5^-265
    f64_ex.new(0x80fa687f881c7f8e, 0x7ce66634bc9d0b99), // 5^-264
    f64_ex.new(0xa139029f6a239f72, 0x1c1fffc1ebc44e80), // 5^-263
    f64_ex.new(0xc987434744ac874e, 0xa327ffb266b56220), // 5^-262
    f64_ex.new(0xfbe9141915d7a922, 0x4bf1ff9f0062baa8), // 5^-261
    f64_ex.new(0x9d71ac8fada6c9b5, 0x6f773fc3603db4a9), // 5^-260
    f64_ex.new(0xc4ce17b399107c22, 0xcb550fb4384d21d3), // 5^-259
    f64_ex.new(0xf6019da07f549b2b, 0x7e2a53a146606a48), // 5^-258
    f64_ex.new(0x99c102844f94e0fb, 0x2eda7444cbfc426d), // 5^-257
    f64_ex.new(0xc0314325637a1939, 0xfa911155fefb5308), // 5^-256
    f64_ex.new(0xf03d93eebc589f88, 0x793555ab7eba27ca), // 5^-255
    f64_ex.new(0x96267c7535b763b5, 0x4bc1558b2f3458de), // 5^-254
    f64_ex.new(0xbbb01b9283253ca2, 0x9eb1aaedfb016f16), // 5^-253
    f64_ex.new(0xea9c227723ee8bcb, 0x465e15a979c1cadc), // 5^-252
    f64_ex.new(0x92a1958a7675175f, 0xbfacd89ec191ec9), // 5^-251
    f64_ex.new(0xb749faed14125d36, 0xcef980ec671f667b), // 5^-250
    f64_ex.new(0xe51c79a85916f484, 0x82b7e12780e7401a), // 5^-249
    f64_ex.new(0x8f31cc0937ae58d2, 0xd1b2ecb8b0908810), // 5^-248
    f64_ex.new(0xb2fe3f0b8599ef07, 0x861fa7e6dcb4aa15), // 5^-247
    f64_ex.new(0xdfbdcece67006ac9, 0x67a791e093e1d49a), // 5^-246
    f64_ex.new(0x8bd6a141006042bd, 0xe0c8bb2c5c6d24e0), // 5^-245
    f64_ex.new(0xaecc49914078536d, 0x58fae9f773886e18), // 5^-244
    f64_ex.new(0xda7f5bf590966848, 0xaf39a475506a899e), // 5^-243
    f64_ex.new(0x888f99797a5e012d, 0x6d8406c952429603), // 5^-242
    f64_ex.new(0xaab37fd7d8f58178, 0xc8e5087ba6d33b83), // 5^-241
    f64_ex.new(0xd5605fcdcf32e1d6, 0xfb1e4a9a90880a64), // 5^-240
    f64_ex.new(0x855c3be0a17fcd26, 0x5cf2eea09a55067f), // 5^-239
    f64_ex.new(0xa6b34ad8c9dfc06f, 0xf42faa48c0ea481e), // 5^-238
    f64_ex.new(0xd0601d8efc57b08b, 0xf13b94daf124da26), // 5^-237
    f64_ex.new(0x823c12795db6ce57, 0x76c53d08d6b70858), // 5^-236
    f64_ex.new(0xa2cb1717b52481ed, 0x54768c4b0c64ca6e), // 5^-235
    f64_ex.new(0xcb7ddcdda26da268, 0xa9942f5dcf7dfd09), // 5^-234
    f64_ex.new(0xfe5d54150b090b02, 0xd3f93b35435d7c4c), // 5^-233
    f64_ex.new(0x9efa548d26e5a6e1, 0xc47bc5014a1a6daf), // 5^-232
    f64_ex.new(0xc6b8e9b0709f109a, 0x359ab6419ca1091b), // 5^-231
    f64_ex.new(0xf867241c8cc6d4c0, 0xc30163d203c94b62), // 5^-230
    f64_ex.new(0x9b407691d7fc44f8, 0x79e0de63425dcf1d), // 5^-229
    f64_ex.new(0xc21094364dfb5636, 0x985915fc12f542e4), // 5^-228
    f64_ex.new(0xf294b943e17a2bc4, 0x3e6f5b7b17b2939d), // 5^-227
    f64_ex.new(0x979cf3ca6cec5b5a, 0xa705992ceecf9c42), // 5^-226
    f64_ex.new(0xbd8430bd08277231, 0x50c6ff782a838353), // 5^-225
    f64_ex.new(0xece53cec4a314ebd, 0xa4f8bf5635246428), // 5^-224
    f64_ex.new(0x940f4613ae5ed136, 0x871b7795e136be99), // 5^-223
    f64_ex.new(0xb913179899f68584, 0x28e2557b59846e3f), // 5^-222
    f64_ex.new(0xe757dd7ec07426e5, 0x331aeada2fe589cf), // 5^-221
    f64_ex.new(0x9096ea6f3848984f, 0x3ff0d2c85def7621), // 5^-220
    f64_ex.new(0xb4bca50b065abe63, 0xfed077a756b53a9), // 5^-219
    f64_ex.new(0xe1ebce4dc7f16dfb, 0xd3e8495912c62894), // 5^-218
    f64_ex.new(0x8d3360f09cf6e4bd, 0x64712dd7abbbd95c), // 5^-217
    f64_ex.new(0xb080392cc4349dec, 0xbd8d794d96aacfb3), // 5^-216
    f64_ex.new(0xdca04777f541c567, 0xecf0d7a0fc5583a0), // 5^-215
    f64_ex.new(0x89e42caaf9491b60, 0xf41686c49db57244), // 5^-214
    f64_ex.new(0xac5d37d5b79b6239, 0x311c2875c522ced5), // 5^-213
    f64_ex.new(0xd77485cb25823ac7, 0x7d633293366b828b), // 5^-212
    f64_ex.new(0x86a8d39ef77164bc, 0xae5dff9c02033197), // 5^-211
    f64_ex.new(0xa8530886b54dbdeb, 0xd9f57f830283fdfc), // 5^-210
    f64_ex.new(0xd267caa862a12d66, 0xd072df63c324fd7b), // 5^-209
    f64_ex.new(0x8380dea93da4bc60, 0x4247cb9e59f71e6d), // 5^-208
    f64_ex.new(0xa46116538d0deb78, 0x52d9be85f074e608), // 5^-207
    f64_ex.new(0xcd795be870516656, 0x67902e276c921f8b), // 5^-206
    f64_ex.new(0x806bd9714632dff6, 0xba1cd8a3db53b6), // 5^-205
    f64_ex.new(0xa086cfcd97bf97f3, 0x80e8a40eccd228a4), // 5^-204
    f64_ex.new(0xc8a883c0fdaf7df0, 0x6122cd128006b2cd), // 5^-203
    f64_ex.new(0xfad2a4b13d1b5d6c, 0x796b805720085f81), // 5^-202
    f64_ex.new(0x9cc3a6eec6311a63, 0xcbe3303674053bb0), // 5^-201
    f64_ex.new(0xc3f490aa77bd60fc, 0xbedbfc4411068a9c), // 5^-200
    f64_ex.new(0xf4f1b4d515acb93b, 0xee92fb5515482d44), // 5^-199
    f64_ex.new(0x991711052d8bf3c5, 0x751bdd152d4d1c4a), // 5^-198
    f64_ex.new(0xbf5cd54678eef0b6, 0xd262d45a78a0635d), // 5^-197
    f64_ex.new(0xef340a98172aace4, 0x86fb897116c87c34), // 5^-196
    f64_ex.new(0x9580869f0e7aac0e, 0xd45d35e6ae3d4da0), // 5^-195
    f64_ex.new(0xbae0a846d2195712, 0x8974836059cca109), // 5^-194
    f64_ex.new(0xe998d258869facd7, 0x2bd1a438703fc94b), // 5^-193
    f64_ex.new(0x91ff83775423cc06, 0x7b6306a34627ddcf), // 5^-192
    f64_ex.new(0xb67f6455292cbf08, 0x1a3bc84c17b1d542), // 5^-191
    f64_ex.new(0xe41f3d6a7377eeca, 0x20caba5f1d9e4a93), // 5^-190
    f64_ex.new(0x8e938662882af53e, 0x547eb47b7282ee9c), // 5^-189
    f64_ex.new(0xb23867fb2a35b28d, 0xe99e619a4f23aa43), // 5^-188
    f64_ex.new(0xdec681f9f4c31f31, 0x6405fa00e2ec94d4), // 5^-187
    f64_ex.new(0x8b3c113c38f9f37e, 0xde83bc408dd3dd04), // 5^-186
    f64_ex.new(0xae0b158b4738705e, 0x9624ab50b148d445), // 5^-185
    f64_ex.new(0xd98ddaee19068c76, 0x3badd624dd9b0957), // 5^-184
    f64_ex.new(0x87f8a8d4cfa417c9, 0xe54ca5d70a80e5d6), // 5^-183
    f64_ex.new(0xa9f6d30a038d1dbc, 0x5e9fcf4ccd211f4c), // 5^-182
    f64_ex.new(0xd47487cc8470652b, 0x7647c3200069671f), // 5^-181
    f64_ex.new(0x84c8d4dfd2c63f3b, 0x29ecd9f40041e073), // 5^-180
    f64_ex.new(0xa5fb0a17c777cf09, 0xf468107100525890), // 5^-179
    f64_ex.new(0xcf79cc9db955c2cc, 0x7182148d4066eeb4), // 5^-178
    f64_ex.new(0x81ac1fe293d599bf, 0xc6f14cd848405530), // 5^-177
    f64_ex.new(0xa21727db38cb002f, 0xb8ada00e5a506a7c), // 5^-176
    f64_ex.new(0xca9cf1d206fdc03b, 0xa6d90811f0e4851c), // 5^-175
    f64_ex.new(0xfd442e4688bd304a, 0x908f4a166d1da663), // 5^-174
    f64_ex.new(0x9e4a9cec15763e2e, 0x9a598e4e043287fe), // 5^-173
    f64_ex.new(0xc5dd44271ad3cdba, 0x40eff1e1853f29fd), // 5^-172
    f64_ex.new(0xf7549530e188c128, 0xd12bee59e68ef47c), // 5^-171
    f64_ex.new(0x9a94dd3e8cf578b9, 0x82bb74f8301958ce), // 5^-170
    f64_ex.new(0xc13a148e3032d6e7, 0xe36a52363c1faf01), // 5^-169
    f64_ex.new(0xf18899b1bc3f8ca1, 0xdc44e6c3cb279ac1), // 5^-168
    f64_ex.new(0x96f5600f15a7b7e5, 0x29ab103a5ef8c0b9), // 5^-167
    f64_ex.new(0xbcb2b812db11a5de, 0x7415d448f6b6f0e7), // 5^-166
    f64_ex.new(0xebdf661791d60f56, 0x111b495b3464ad21), // 5^-165
    f64_ex.new(0x936b9fcebb25c995, 0xcab10dd900beec34), // 5^-164
    f64_ex.new(0xb84687c269ef3bfb, 0x3d5d514f40eea742), // 5^-163
    f64_ex.new(0xe65829b3046b0afa, 0xcb4a5a3112a5112), // 5^-162
    f64_ex.new(0x8ff71a0fe2c2e6dc, 0x47f0e785eaba72ab), // 5^-161
    f64_ex.new(0xb3f4e093db73a093, 0x59ed216765690f56), // 5^-160
    f64_ex.new(0xe0f218b8d25088b8, 0x306869c13ec3532c), // 5^-159
    f64_ex.new(0x8c974f7383725573, 0x1e414218c73a13fb), // 5^-158
    f64_ex.new(0xafbd2350644eeacf, 0xe5d1929ef90898fa), // 5^-157
    f64_ex.new(0xdbac6c247d62a583, 0xdf45f746b74abf39), // 5^-156
    f64_ex.new(0x894bc396ce5da772, 0x6b8bba8c328eb783), // 5^-155
    f64_ex.new(0xab9eb47c81f5114f, 0x66ea92f3f326564), // 5^-154
    f64_ex.new(0xd686619ba27255a2, 0xc80a537b0efefebd), // 5^-153
    f64_ex.new(0x8613fd0145877585, 0xbd06742ce95f5f36), // 5^-152
    f64_ex.new(0xa798fc4196e952e7, 0x2c48113823b73704), // 5^-151
    f64_ex.new(0xd17f3b51fca3a7a0, 0xf75a15862ca504c5), // 5^-150
    f64_ex.new(0x82ef85133de648c4, 0x9a984d73dbe722fb), // 5^-149
    f64_ex.new(0xa3ab66580d5fdaf5, 0xc13e60d0d2e0ebba), // 5^-148
    f64_ex.new(0xcc963fee10b7d1b3, 0x318df905079926a8), // 5^-147
    f64_ex.new(0xffbbcfe994e5c61f, 0xfdf17746497f7052), // 5^-146
    f64_ex.new(0x9fd561f1fd0f9bd3, 0xfeb6ea8bedefa633), // 5^-145
    f64_ex.new(0xc7caba6e7c5382c8, 0xfe64a52ee96b8fc0), // 5^-144
    f64_ex.new(0xf9bd690a1b68637b, 0x3dfdce7aa3c673b0), // 5^-143
    f64_ex.new(0x9c1661a651213e2d, 0x6bea10ca65c084e), // 5^-142
    f64_ex.new(0xc31bfa0fe5698db8, 0x486e494fcff30a62), // 5^-141
    f64_ex.new(0xf3e2f893dec3f126, 0x5a89dba3c3efccfa), // 5^-140
    f64_ex.new(0x986ddb5c6b3a76b7, 0xf89629465a75e01c), // 5^-139
    f64_ex.new(0xbe89523386091465, 0xf6bbb397f1135823), // 5^-138
    f64_ex.new(0xee2ba6c0678b597f, 0x746aa07ded582e2c), // 5^-137
    f64_ex.new(0x94db483840b717ef, 0xa8c2a44eb4571cdc), // 5^-136
    f64_ex.new(0xba121a4650e4ddeb, 0x92f34d62616ce413), // 5^-135
    f64_ex.new(0xe896a0d7e51e1566, 0x77b020baf9c81d17), // 5^-134
    f64_ex.new(0x915e2486ef32cd60, 0xace1474dc1d122e), // 5^-133
    f64_ex.new(0xb5b5ada8aaff80b8, 0xd819992132456ba), // 5^-132
    f64_ex.new(0xe3231912d5bf60e6, 0x10e1fff697ed6c69), // 5^-131
    f64_ex.new(0x8df5efabc5979c8f, 0xca8d3ffa1ef463c1), // 5^-130
    f64_ex.new(0xb1736b96b6fd83b3, 0xbd308ff8a6b17cb2), // 5^-129
    f64_ex.new(0xddd0467c64bce4a0, 0xac7cb3f6d05ddbde), // 5^-128
    f64_ex.new(0x8aa22c0dbef60ee4, 0x6bcdf07a423aa96b), // 5^-127
    f64_ex.new(0xad4ab7112eb3929d, 0x86c16c98d2c953c6), // 5^-126
    f64_ex.new(0xd89d64d57a607744, 0xe871c7bf077ba8b7), // 5^-125
    f64_ex.new(0x87625f056c7c4a8b, 0x11471cd764ad4972), // 5^-124
    f64_ex.new(0xa93af6c6c79b5d2d, 0xd598e40d3dd89bcf), // 5^-123
    f64_ex.new(0xd389b47879823479, 0x4aff1d108d4ec2c3), // 5^-122
    f64_ex.new(0x843610cb4bf160cb, 0xcedf722a585139ba), // 5^-121
    f64_ex.new(0xa54394fe1eedb8fe, 0xc2974eb4ee658828), // 5^-120
    f64_ex.new(0xce947a3da6a9273e, 0x733d226229feea32), // 5^-119
    f64_ex.new(0x811ccc668829b887, 0x806357d5a3f525f), // 5^-118
    f64_ex.new(0xa163ff802a3426a8, 0xca07c2dcb0cf26f7), // 5^-117
    f64_ex.new(0xc9bcff6034c13052, 0xfc89b393dd02f0b5), // 5^-116
    f64_ex.new(0xfc2c3f3841f17c67, 0xbbac2078d443ace2), // 5^-115
    f64_ex.new(0x9d9ba7832936edc0, 0xd54b944b84aa4c0d), // 5^-114
    f64_ex.new(0xc5029163f384a931, 0xa9e795e65d4df11), // 5^-113
    f64_ex.new(0xf64335bcf065d37d, 0x4d4617b5ff4a16d5), // 5^-112
    f64_ex.new(0x99ea0196163fa42e, 0x504bced1bf8e4e45), // 5^-111
    f64_ex.new(0xc06481fb9bcf8d39, 0xe45ec2862f71e1d6), // 5^-110
    f64_ex.new(0xf07da27a82c37088, 0x5d767327bb4e5a4c), // 5^-109
    f64_ex.new(0x964e858c91ba2655, 0x3a6a07f8d510f86f), // 5^-108
    f64_ex.new(0xbbe226efb628afea, 0x890489f70a55368b), // 5^-107
    f64_ex.new(0xeadab0aba3b2dbe5, 0x2b45ac74ccea842e), // 5^-106
    f64_ex.new(0x92c8ae6b464fc96f, 0x3b0b8bc90012929d), // 5^-105
    f64_ex.new(0xb77ada0617e3bbcb, 0x9ce6ebb40173744), // 5^-104
    f64_ex.new(0xe55990879ddcaabd, 0xcc420a6a101d0515), // 5^-103
    f64_ex.new(0x8f57fa54c2a9eab6, 0x9fa946824a12232d), // 5^-102
    f64_ex.new(0xb32df8e9f3546564, 0x47939822dc96abf9), // 5^-101
    f64_ex.new(0xdff9772470297ebd, 0x59787e2b93bc56f7), // 5^-100
    f64_ex.new(0x8bfbea76c619ef36, 0x57eb4edb3c55b65a), // 5^-99
    f64_ex.new(0xaefae51477a06b03, 0xede622920b6b23f1), // 5^-98
    f64_ex.new(0xdab99e59958885c4, 0xe95fab368e45eced), // 5^-97
    f64_ex.new(0x88b402f7fd75539b, 0x11dbcb0218ebb414), // 5^-96
    f64_ex.new(0xaae103b5fcd2a881, 0xd652bdc29f26a119), // 5^-95
    f64_ex.new(0xd59944a37c0752a2, 0x4be76d3346f0495f), // 5^-94
    f64_ex.new(0x857fcae62d8493a5, 0x6f70a4400c562ddb), // 5^-93
    f64_ex.new(0xa6dfbd9fb8e5b88e, 0xcb4ccd500f6bb952), // 5^-92
    f64_ex.new(0xd097ad07a71f26b2, 0x7e2000a41346a7a7), // 5^-91
    f64_ex.new(0x825ecc24c873782f, 0x8ed400668c0c28c8), // 5^-90
    f64_ex.new(0xa2f67f2dfa90563b, 0x728900802f0f32fa), // 5^-89
    f64_ex.new(0xcbb41ef979346bca, 0x4f2b40a03ad2ffb9), // 5^-88
    f64_ex.new(0xfea126b7d78186bc, 0xe2f610c84987bfa8), // 5^-87
    f64_ex.new(0x9f24b832e6b0f436, 0xdd9ca7d2df4d7c9), // 5^-86
    f64_ex.new(0xc6ede63fa05d3143, 0x91503d1c79720dbb), // 5^-85
    f64_ex.new(0xf8a95fcf88747d94, 0x75a44c6397ce912a), // 5^-84
    f64_ex.new(0x9b69dbe1b548ce7c, 0xc986afbe3ee11aba), // 5^-83
    f64_ex.new(0xc24452da229b021b, 0xfbe85badce996168), // 5^-82
    f64_ex.new(0xf2d56790ab41c2a2, 0xfae27299423fb9c3), // 5^-81
    f64_ex.new(0x97c560ba6b0919a5, 0xdccd879fc967d41a), // 5^-80
    f64_ex.new(0xbdb6b8e905cb600f, 0x5400e987bbc1c920), // 5^-79
    f64_ex.new(0xed246723473e3813, 0x290123e9aab23b68), // 5^-78
    f64_ex.new(0x9436c0760c86e30b, 0xf9a0b6720aaf6521), // 5^-77
    f64_ex.new(0xb94470938fa89bce, 0xf808e40e8d5b3e69), // 5^-76
    f64_ex.new(0xe7958cb87392c2c2, 0xb60b1d1230b20e04), // 5^-75
    f64_ex.new(0x90bd77f3483bb9b9, 0xb1c6f22b5e6f48c2), // 5^-74
    f64_ex.new(0xb4ecd5f01a4aa828, 0x1e38aeb6360b1af3), // 5^-73
    f64_ex.new(0xe2280b6c20dd5232, 0x25c6da63c38de1b0), // 5^-72
    f64_ex.new(0x8d590723948a535f, 0x579c487e5a38ad0e), // 5^-71
    f64_ex.new(0xb0af48ec79ace837, 0x2d835a9df0c6d851), // 5^-70
    f64_ex.new(0xdcdb1b2798182244, 0xf8e431456cf88e65), // 5^-69
    f64_ex.new(0x8a08f0f8bf0f156b, 0x1b8e9ecb641b58ff), // 5^-68
    f64_ex.new(0xac8b2d36eed2dac5, 0xe272467e3d222f3f), // 5^-67
    f64_ex.new(0xd7adf884aa879177, 0x5b0ed81dcc6abb0f), // 5^-66
    f64_ex.new(0x86ccbb52ea94baea, 0x98e947129fc2b4e9), // 5^-65
    f64_ex.new(0xa87fea27a539e9a5, 0x3f2398d747b36224), // 5^-64
    f64_ex.new(0xd29fe4b18e88640e, 0x8eec7f0d19a03aad), // 5^-63
    f64_ex.new(0x83a3eeeef9153e89, 0x1953cf68300424ac), // 5^-62
    f64_ex.new(0xa48ceaaab75a8e2b, 0x5fa8c3423c052dd7), // 5^-61
    f64_ex.new(0xcdb02555653131b6, 0x3792f412cb06794d), // 5^-60
    f64_ex.new(0x808e17555f3ebf11, 0xe2bbd88bbee40bd0), // 5^-59
    f64_ex.new(0xa0b19d2ab70e6ed6, 0x5b6aceaeae9d0ec4), // 5^-58
    f64_ex.new(0xc8de047564d20a8b, 0xf245825a5a445275), // 5^-57
    f64_ex.new(0xfb158592be068d2e, 0xeed6e2f0f0d56712), // 5^-56
    f64_ex.new(0x9ced737bb6c4183d, 0x55464dd69685606b), // 5^-55
    f64_ex.new(0xc428d05aa4751e4c, 0xaa97e14c3c26b886), // 5^-54
    f64_ex.new(0xf53304714d9265df, 0xd53dd99f4b3066a8), // 5^-53
    f64_ex.new(0x993fe2c6d07b7fab, 0xe546a8038efe4029), // 5^-52
    f64_ex.new(0xbf8fdb78849a5f96, 0xde98520472bdd033), // 5^-51
    f64_ex.new(0xef73d256a5c0f77c, 0x963e66858f6d4440), // 5^-50
    f64_ex.new(0x95a8637627989aad, 0xdde7001379a44aa8), // 5^-49
    f64_ex.new(0xbb127c53b17ec159, 0x5560c018580d5d52), // 5^-48
    f64_ex.new(0xe9d71b689dde71af, 0xaab8f01e6e10b4a6), // 5^-47
    f64_ex.new(0x9226712162ab070d, 0xcab3961304ca70e8), // 5^-46
    f64_ex.new(0xb6b00d69bb55c8d1, 0x3d607b97c5fd0d22), // 5^-45
    f64_ex.new(0xe45c10c42a2b3b05, 0x8cb89a7db77c506a), // 5^-44
    f64_ex.new(0x8eb98a7a9a5b04e3, 0x77f3608e92adb242), // 5^-43
    f64_ex.new(0xb267ed1940f1c61c, 0x55f038b237591ed3), // 5^-42
    f64_ex.new(0xdf01e85f912e37a3, 0x6b6c46dec52f6688), // 5^-41
    f64_ex.new(0x8b61313bbabce2c6, 0x2323ac4b3b3da015), // 5^-40
    f64_ex.new(0xae397d8aa96c1b77, 0xabec975e0a0d081a), // 5^-39
    f64_ex.new(0xd9c7dced53c72255, 0x96e7bd358c904a21), // 5^-38
    f64_ex.new(0x881cea14545c7575, 0x7e50d64177da2e54), // 5^-37
    f64_ex.new(0xaa242499697392d2, 0xdde50bd1d5d0b9e9), // 5^-36
    f64_ex.new(0xd4ad2dbfc3d07787, 0x955e4ec64b44e864), // 5^-35
    f64_ex.new(0x84ec3c97da624ab4, 0xbd5af13bef0b113e), // 5^-34
    f64_ex.new(0xa6274bbdd0fadd61, 0xecb1ad8aeacdd58e), // 5^-33
    f64_ex.new(0xcfb11ead453994ba, 0x67de18eda5814af2), // 5^-32
    f64_ex.new(0x81ceb32c4b43fcf4, 0x80eacf948770ced7), // 5^-31
    f64_ex.new(0xa2425ff75e14fc31, 0xa1258379a94d028d), // 5^-30
    f64_ex.new(0xcad2f7f5359a3b3e, 0x96ee45813a04330), // 5^-29
    f64_ex.new(0xfd87b5f28300ca0d, 0x8bca9d6e188853fc), // 5^-28
    f64_ex.new(0x9e74d1b791e07e48, 0x775ea264cf55347e), // 5^-27
    f64_ex.new(0xc612062576589dda, 0x95364afe032a819e), // 5^-26
    f64_ex.new(0xf79687aed3eec551, 0x3a83ddbd83f52205), // 5^-25
    f64_ex.new(0x9abe14cd44753b52, 0xc4926a9672793543), // 5^-24
    f64_ex.new(0xc16d9a0095928a27, 0x75b7053c0f178294), // 5^-23
    f64_ex.new(0xf1c90080baf72cb1, 0x5324c68b12dd6339), // 5^-22
    f64_ex.new(0x971da05074da7bee, 0xd3f6fc16ebca5e04), // 5^-21
    f64_ex.new(0xbce5086492111aea, 0x88f4bb1ca6bcf585), // 5^-20
    f64_ex.new(0xec1e4a7db69561a5, 0x2b31e9e3d06c32e6), // 5^-19
    f64_ex.new(0x9392ee8e921d5d07, 0x3aff322e62439fd0), // 5^-18
    f64_ex.new(0xb877aa3236a4b449, 0x9befeb9fad487c3), // 5^-17
    f64_ex.new(0xe69594bec44de15b, 0x4c2ebe687989a9b4), // 5^-16
    f64_ex.new(0x901d7cf73ab0acd9, 0xf9d37014bf60a11), // 5^-15
    f64_ex.new(0xb424dc35095cd80f, 0x538484c19ef38c95), // 5^-14
    f64_ex.new(0xe12e13424bb40e13, 0x2865a5f206b06fba), // 5^-13
    f64_ex.new(0x8cbccc096f5088cb, 0xf93f87b7442e45d4), // 5^-12
    f64_ex.new(0xafebff0bcb24aafe, 0xf78f69a51539d749), // 5^-11
    f64_ex.new(0xdbe6fecebdedd5be, 0xb573440e5a884d1c), // 5^-10
    f64_ex.new(0x89705f4136b4a597, 0x31680a88f8953031), // 5^-9
    f64_ex.new(0xabcc77118461cefc, 0xfdc20d2b36ba7c3e), // 5^-8
    f64_ex.new(0xd6bf94d5e57a42bc, 0x3d32907604691b4d), // 5^-7
    f64_ex.new(0x8637bd05af6c69b5, 0xa63f9a49c2c1b110), // 5^-6
    f64_ex.new(0xa7c5ac471b478423, 0xfcf80dc33721d54), // 5^-5
    f64_ex.new(0xd1b71758e219652b, 0xd3c36113404ea4a9), // 5^-4
    f64_ex.new(0x83126e978d4fdf3b, 0x645a1cac083126ea), // 5^-3
    f64_ex.new(0xa3d70a3d70a3d70a, 0x3d70a3d70a3d70a4), // 5^-2
    f64_ex.new(0xcccccccccccccccc, 0xcccccccccccccccd), // 5^-1
    f64_ex.new(0x8000000000000000, 0x0), // 5^0
    f64_ex.new(0xa000000000000000, 0x0), // 5^1
    f64_ex.new(0xc800000000000000, 0x0), // 5^2
    f64_ex.new(0xfa00000000000000, 0x0), // 5^3
    f64_ex.new(0x9c40000000000000, 0x0), // 5^4
    f64_ex.new(0xc350000000000000, 0x0), // 5^5
    f64_ex.new(0xf424000000000000, 0x0), // 5^6
    f64_ex.new(0x9896800000000000, 0x0), // 5^7
    f64_ex.new(0xbebc200000000000, 0x0), // 5^8
    f64_ex.new(0xee6b280000000000, 0x0), // 5^9
    f64_ex.new(0x9502f90000000000, 0x0), // 5^10
    f64_ex.new(0xba43b74000000000, 0x0), // 5^11
    f64_ex.new(0xe8d4a51000000000, 0x0), // 5^12
    f64_ex.new(0x9184e72a00000000, 0x0), // 5^13
    f64_ex.new(0xb5e620f480000000, 0x0), // 5^14
    f64_ex.new(0xe35fa931a0000000, 0x0), // 5^15
    f64_ex.new(0x8e1bc9bf04000000, 0x0), // 5^16
    f64_ex.new(0xb1a2bc2ec5000000, 0x0), // 5^17
    f64_ex.new(0xde0b6b3a76400000, 0x0), // 5^18
    f64_ex.new(0x8ac7230489e80000, 0x0), // 5^19
    f64_ex.new(0xad78ebc5ac620000, 0x0), // 5^20
    f64_ex.new(0xd8d726b7177a8000, 0x0), // 5^21
    f64_ex.new(0x878678326eac9000, 0x0), // 5^22
    f64_ex.new(0xa968163f0a57b400, 0x0), // 5^23
    f64_ex.new(0xd3c21bcecceda100, 0x0), // 5^24
    f64_ex.new(0x84595161401484a0, 0x0), // 5^25
    f64_ex.new(0xa56fa5b99019a5c8, 0x0), // 5^26
    f64_ex.new(0xcecb8f27f4200f3a, 0x0), // 5^27
    f64_ex.new(0x813f3978f8940984, 0x4000000000000000), // 5^28
    f64_ex.new(0xa18f07d736b90be5, 0x5000000000000000), // 5^29
    f64_ex.new(0xc9f2c9cd04674ede, 0xa400000000000000), // 5^30
    f64_ex.new(0xfc6f7c4045812296, 0x4d00000000000000), // 5^31
    f64_ex.new(0x9dc5ada82b70b59d, 0xf020000000000000), // 5^32
    f64_ex.new(0xc5371912364ce305, 0x6c28000000000000), // 5^33
    f64_ex.new(0xf684df56c3e01bc6, 0xc732000000000000), // 5^34
    f64_ex.new(0x9a130b963a6c115c, 0x3c7f400000000000), // 5^35
    f64_ex.new(0xc097ce7bc90715b3, 0x4b9f100000000000), // 5^36
    f64_ex.new(0xf0bdc21abb48db20, 0x1e86d40000000000), // 5^37
    f64_ex.new(0x96769950b50d88f4, 0x1314448000000000), // 5^38
    f64_ex.new(0xbc143fa4e250eb31, 0x17d955a000000000), // 5^39
    f64_ex.new(0xeb194f8e1ae525fd, 0x5dcfab0800000000), // 5^40
    f64_ex.new(0x92efd1b8d0cf37be, 0x5aa1cae500000000), // 5^41
    f64_ex.new(0xb7abc627050305ad, 0xf14a3d9e40000000), // 5^42
    f64_ex.new(0xe596b7b0c643c719, 0x6d9ccd05d0000000), // 5^43
    f64_ex.new(0x8f7e32ce7bea5c6f, 0xe4820023a2000000), // 5^44
    f64_ex.new(0xb35dbf821ae4f38b, 0xdda2802c8a800000), // 5^45
    f64_ex.new(0xe0352f62a19e306e, 0xd50b2037ad200000), // 5^46
    f64_ex.new(0x8c213d9da502de45, 0x4526f422cc340000), // 5^47
    f64_ex.new(0xaf298d050e4395d6, 0x9670b12b7f410000), // 5^48
    f64_ex.new(0xdaf3f04651d47b4c, 0x3c0cdd765f114000), // 5^49
    f64_ex.new(0x88d8762bf324cd0f, 0xa5880a69fb6ac800), // 5^50
    f64_ex.new(0xab0e93b6efee0053, 0x8eea0d047a457a00), // 5^51
    f64_ex.new(0xd5d238a4abe98068, 0x72a4904598d6d880), // 5^52
    f64_ex.new(0x85a36366eb71f041, 0x47a6da2b7f864750), // 5^53
    f64_ex.new(0xa70c3c40a64e6c51, 0x999090b65f67d924), // 5^54
    f64_ex.new(0xd0cf4b50cfe20765, 0xfff4b4e3f741cf6d), // 5^55
    f64_ex.new(0x82818f1281ed449f, 0xbff8f10e7a8921a4), // 5^56
    f64_ex.new(0xa321f2d7226895c7, 0xaff72d52192b6a0d), // 5^57
    f64_ex.new(0xcbea6f8ceb02bb39, 0x9bf4f8a69f764490), // 5^58
    f64_ex.new(0xfee50b7025c36a08, 0x2f236d04753d5b4), // 5^59
    f64_ex.new(0x9f4f2726179a2245, 0x1d762422c946590), // 5^60
    f64_ex.new(0xc722f0ef9d80aad6, 0x424d3ad2b7b97ef5), // 5^61
    f64_ex.new(0xf8ebad2b84e0d58b, 0xd2e0898765a7deb2), // 5^62
    f64_ex.new(0x9b934c3b330c8577, 0x63cc55f49f88eb2f), // 5^63
    f64_ex.new(0xc2781f49ffcfa6d5, 0x3cbf6b71c76b25fb), // 5^64
    f64_ex.new(0xf316271c7fc3908a, 0x8bef464e3945ef7a), // 5^65
    f64_ex.new(0x97edd871cfda3a56, 0x97758bf0e3cbb5ac), // 5^66
    f64_ex.new(0xbde94e8e43d0c8ec, 0x3d52eeed1cbea317), // 5^67
    f64_ex.new(0xed63a231d4c4fb27, 0x4ca7aaa863ee4bdd), // 5^68
    f64_ex.new(0x945e455f24fb1cf8, 0x8fe8caa93e74ef6a), // 5^69
    f64_ex.new(0xb975d6b6ee39e436, 0xb3e2fd538e122b44), // 5^70
    f64_ex.new(0xe7d34c64a9c85d44, 0x60dbbca87196b616), // 5^71
    f64_ex.new(0x90e40fbeea1d3a4a, 0xbc8955e946fe31cd), // 5^72
    f64_ex.new(0xb51d13aea4a488dd, 0x6babab6398bdbe41), // 5^73
    f64_ex.new(0xe264589a4dcdab14, 0xc696963c7eed2dd1), // 5^74
    f64_ex.new(0x8d7eb76070a08aec, 0xfc1e1de5cf543ca2), // 5^75
    f64_ex.new(0xb0de65388cc8ada8, 0x3b25a55f43294bcb), // 5^76
    f64_ex.new(0xdd15fe86affad912, 0x49ef0eb713f39ebe), // 5^77
    f64_ex.new(0x8a2dbf142dfcc7ab, 0x6e3569326c784337), // 5^78
    f64_ex.new(0xacb92ed9397bf996, 0x49c2c37f07965404), // 5^79
    f64_ex.new(0xd7e77a8f87daf7fb, 0xdc33745ec97be906), // 5^80
    f64_ex.new(0x86f0ac99b4e8dafd, 0x69a028bb3ded71a3), // 5^81
    f64_ex.new(0xa8acd7c0222311bc, 0xc40832ea0d68ce0c), // 5^82
    f64_ex.new(0xd2d80db02aabd62b, 0xf50a3fa490c30190), // 5^83
    f64_ex.new(0x83c7088e1aab65db, 0x792667c6da79e0fa), // 5^84
    f64_ex.new(0xa4b8cab1a1563f52, 0x577001b891185938), // 5^85
    f64_ex.new(0xcde6fd5e09abcf26, 0xed4c0226b55e6f86), // 5^86
    f64_ex.new(0x80b05e5ac60b6178, 0x544f8158315b05b4), // 5^87
    f64_ex.new(0xa0dc75f1778e39d6, 0x696361ae3db1c721), // 5^88
    f64_ex.new(0xc913936dd571c84c, 0x3bc3a19cd1e38e9), // 5^89
    f64_ex.new(0xfb5878494ace3a5f, 0x4ab48a04065c723), // 5^90
    f64_ex.new(0x9d174b2dcec0e47b, 0x62eb0d64283f9c76), // 5^91
    f64_ex.new(0xc45d1df942711d9a, 0x3ba5d0bd324f8394), // 5^92
    f64_ex.new(0xf5746577930d6500, 0xca8f44ec7ee36479), // 5^93
    f64_ex.new(0x9968bf6abbe85f20, 0x7e998b13cf4e1ecb), // 5^94
    f64_ex.new(0xbfc2ef456ae276e8, 0x9e3fedd8c321a67e), // 5^95
    f64_ex.new(0xefb3ab16c59b14a2, 0xc5cfe94ef3ea101e), // 5^96
    f64_ex.new(0x95d04aee3b80ece5, 0xbba1f1d158724a12), // 5^97
    f64_ex.new(0xbb445da9ca61281f, 0x2a8a6e45ae8edc97), // 5^98
    f64_ex.new(0xea1575143cf97226, 0xf52d09d71a3293bd), // 5^99
    f64_ex.new(0x924d692ca61be758, 0x593c2626705f9c56), // 5^100
    f64_ex.new(0xb6e0c377cfa2e12e, 0x6f8b2fb00c77836c), // 5^101
    f64_ex.new(0xe498f455c38b997a, 0xb6dfb9c0f956447), // 5^102
    f64_ex.new(0x8edf98b59a373fec, 0x4724bd4189bd5eac), // 5^103
    f64_ex.new(0xb2977ee300c50fe7, 0x58edec91ec2cb657), // 5^104
    f64_ex.new(0xdf3d5e9bc0f653e1, 0x2f2967b66737e3ed), // 5^105
    f64_ex.new(0x8b865b215899f46c, 0xbd79e0d20082ee74), // 5^106
    f64_ex.new(0xae67f1e9aec07187, 0xecd8590680a3aa11), // 5^107
    f64_ex.new(0xda01ee641a708de9, 0xe80e6f4820cc9495), // 5^108
    f64_ex.new(0x884134fe908658b2, 0x3109058d147fdcdd), // 5^109
    f64_ex.new(0xaa51823e34a7eede, 0xbd4b46f0599fd415), // 5^110
    f64_ex.new(0xd4e5e2cdc1d1ea96, 0x6c9e18ac7007c91a), // 5^111
    f64_ex.new(0x850fadc09923329e, 0x3e2cf6bc604ddb0), // 5^112
    f64_ex.new(0xa6539930bf6bff45, 0x84db8346b786151c), // 5^113
    f64_ex.new(0xcfe87f7cef46ff16, 0xe612641865679a63), // 5^114
    f64_ex.new(0x81f14fae158c5f6e, 0x4fcb7e8f3f60c07e), // 5^115
    f64_ex.new(0xa26da3999aef7749, 0xe3be5e330f38f09d), // 5^116
    f64_ex.new(0xcb090c8001ab551c, 0x5cadf5bfd3072cc5), // 5^117
    f64_ex.new(0xfdcb4fa002162a63, 0x73d9732fc7c8f7f6), // 5^118
    f64_ex.new(0x9e9f11c4014dda7e, 0x2867e7fddcdd9afa), // 5^119
    f64_ex.new(0xc646d63501a1511d, 0xb281e1fd541501b8), // 5^120
    f64_ex.new(0xf7d88bc24209a565, 0x1f225a7ca91a4226), // 5^121
    f64_ex.new(0x9ae757596946075f, 0x3375788de9b06958), // 5^122
    f64_ex.new(0xc1a12d2fc3978937, 0x52d6b1641c83ae), // 5^123
    f64_ex.new(0xf209787bb47d6b84, 0xc0678c5dbd23a49a), // 5^124
    f64_ex.new(0x9745eb4d50ce6332, 0xf840b7ba963646e0), // 5^125
    f64_ex.new(0xbd176620a501fbff, 0xb650e5a93bc3d898), // 5^126
    f64_ex.new(0xec5d3fa8ce427aff, 0xa3e51f138ab4cebe), // 5^127
    f64_ex.new(0x93ba47c980e98cdf, 0xc66f336c36b10137), // 5^128
    f64_ex.new(0xb8a8d9bbe123f017, 0xb80b0047445d4184), // 5^129
    f64_ex.new(0xe6d3102ad96cec1d, 0xa60dc059157491e5), // 5^130
    f64_ex.new(0x9043ea1ac7e41392, 0x87c89837ad68db2f), // 5^131
    f64_ex.new(0xb454e4a179dd1877, 0x29babe4598c311fb), // 5^132
    f64_ex.new(0xe16a1dc9d8545e94, 0xf4296dd6fef3d67a), // 5^133
    f64_ex.new(0x8ce2529e2734bb1d, 0x1899e4a65f58660c), // 5^134
    f64_ex.new(0xb01ae745b101e9e4, 0x5ec05dcff72e7f8f), // 5^135
    f64_ex.new(0xdc21a1171d42645d, 0x76707543f4fa1f73), // 5^136
    f64_ex.new(0x899504ae72497eba, 0x6a06494a791c53a8), // 5^137
    f64_ex.new(0xabfa45da0edbde69, 0x487db9d17636892), // 5^138
    f64_ex.new(0xd6f8d7509292d603, 0x45a9d2845d3c42b6), // 5^139
    f64_ex.new(0x865b86925b9bc5c2, 0xb8a2392ba45a9b2), // 5^140
    f64_ex.new(0xa7f26836f282b732, 0x8e6cac7768d7141e), // 5^141
    f64_ex.new(0xd1ef0244af2364ff, 0x3207d795430cd926), // 5^142
    f64_ex.new(0x8335616aed761f1f, 0x7f44e6bd49e807b8), // 5^143
    f64_ex.new(0xa402b9c5a8d3a6e7, 0x5f16206c9c6209a6), // 5^144
    f64_ex.new(0xcd036837130890a1, 0x36dba887c37a8c0f), // 5^145
    f64_ex.new(0x802221226be55a64, 0xc2494954da2c9789), // 5^146
    f64_ex.new(0xa02aa96b06deb0fd, 0xf2db9baa10b7bd6c), // 5^147
    f64_ex.new(0xc83553c5c8965d3d, 0x6f92829494e5acc7), // 5^148
    f64_ex.new(0xfa42a8b73abbf48c, 0xcb772339ba1f17f9), // 5^149
    f64_ex.new(0x9c69a97284b578d7, 0xff2a760414536efb), // 5^150
    f64_ex.new(0xc38413cf25e2d70d, 0xfef5138519684aba), // 5^151
    f64_ex.new(0xf46518c2ef5b8cd1, 0x7eb258665fc25d69), // 5^152
    f64_ex.new(0x98bf2f79d5993802, 0xef2f773ffbd97a61), // 5^153
    f64_ex.new(0xbeeefb584aff8603, 0xaafb550ffacfd8fa), // 5^154
    f64_ex.new(0xeeaaba2e5dbf6784, 0x95ba2a53f983cf38), // 5^155
    f64_ex.new(0x952ab45cfa97a0b2, 0xdd945a747bf26183), // 5^156
    f64_ex.new(0xba756174393d88df, 0x94f971119aeef9e4), // 5^157
    f64_ex.new(0xe912b9d1478ceb17, 0x7a37cd5601aab85d), // 5^158
    f64_ex.new(0x91abb422ccb812ee, 0xac62e055c10ab33a), // 5^159
    f64_ex.new(0xb616a12b7fe617aa, 0x577b986b314d6009), // 5^160
    f64_ex.new(0xe39c49765fdf9d94, 0xed5a7e85fda0b80b), // 5^161
    f64_ex.new(0x8e41ade9fbebc27d, 0x14588f13be847307), // 5^162
    f64_ex.new(0xb1d219647ae6b31c, 0x596eb2d8ae258fc8), // 5^163
    f64_ex.new(0xde469fbd99a05fe3, 0x6fca5f8ed9aef3bb), // 5^164
    f64_ex.new(0x8aec23d680043bee, 0x25de7bb9480d5854), // 5^165
    f64_ex.new(0xada72ccc20054ae9, 0xaf561aa79a10ae6a), // 5^166
    f64_ex.new(0xd910f7ff28069da4, 0x1b2ba1518094da04), // 5^167
    f64_ex.new(0x87aa9aff79042286, 0x90fb44d2f05d0842), // 5^168
    f64_ex.new(0xa99541bf57452b28, 0x353a1607ac744a53), // 5^169
    f64_ex.new(0xd3fa922f2d1675f2, 0x42889b8997915ce8), // 5^170
    f64_ex.new(0x847c9b5d7c2e09b7, 0x69956135febada11), // 5^171
    f64_ex.new(0xa59bc234db398c25, 0x43fab9837e699095), // 5^172
    f64_ex.new(0xcf02b2c21207ef2e, 0x94f967e45e03f4bb), // 5^173
    f64_ex.new(0x8161afb94b44f57d, 0x1d1be0eebac278f5), // 5^174
    f64_ex.new(0xa1ba1ba79e1632dc, 0x6462d92a69731732), // 5^175
    f64_ex.new(0xca28a291859bbf93, 0x7d7b8f7503cfdcfe), // 5^176
    f64_ex.new(0xfcb2cb35e702af78, 0x5cda735244c3d43e), // 5^177
    f64_ex.new(0x9defbf01b061adab, 0x3a0888136afa64a7), // 5^178
    f64_ex.new(0xc56baec21c7a1916, 0x88aaa1845b8fdd0), // 5^179
    f64_ex.new(0xf6c69a72a3989f5b, 0x8aad549e57273d45), // 5^180
    f64_ex.new(0x9a3c2087a63f6399, 0x36ac54e2f678864b), // 5^181
    f64_ex.new(0xc0cb28a98fcf3c7f, 0x84576a1bb416a7dd), // 5^182
    f64_ex.new(0xf0fdf2d3f3c30b9f, 0x656d44a2a11c51d5), // 5^183
    f64_ex.new(0x969eb7c47859e743, 0x9f644ae5a4b1b325), // 5^184
    f64_ex.new(0xbc4665b596706114, 0x873d5d9f0dde1fee), // 5^185
    f64_ex.new(0xeb57ff22fc0c7959, 0xa90cb506d155a7ea), // 5^186
    f64_ex.new(0x9316ff75dd87cbd8, 0x9a7f12442d588f2), // 5^187
    f64_ex.new(0xb7dcbf5354e9bece, 0xc11ed6d538aeb2f), // 5^188
    f64_ex.new(0xe5d3ef282a242e81, 0x8f1668c8a86da5fa), // 5^189
    f64_ex.new(0x8fa475791a569d10, 0xf96e017d694487bc), // 5^190
    f64_ex.new(0xb38d92d760ec4455, 0x37c981dcc395a9ac), // 5^191
    f64_ex.new(0xe070f78d3927556a, 0x85bbe253f47b1417), // 5^192
    f64_ex.new(0x8c469ab843b89562, 0x93956d7478ccec8e), // 5^193
    f64_ex.new(0xaf58416654a6babb, 0x387ac8d1970027b2), // 5^194
    f64_ex.new(0xdb2e51bfe9d0696a, 0x6997b05fcc0319e), // 5^195
    f64_ex.new(0x88fcf317f22241e2, 0x441fece3bdf81f03), // 5^196
    f64_ex.new(0xab3c2fddeeaad25a, 0xd527e81cad7626c3), // 5^197
    f64_ex.new(0xd60b3bd56a5586f1, 0x8a71e223d8d3b074), // 5^198
    f64_ex.new(0x85c7056562757456, 0xf6872d5667844e49), // 5^199
    f64_ex.new(0xa738c6bebb12d16c, 0xb428f8ac016561db), // 5^200
    f64_ex.new(0xd106f86e69d785c7, 0xe13336d701beba52), // 5^201
    f64_ex.new(0x82a45b450226b39c, 0xecc0024661173473), // 5^202
    f64_ex.new(0xa34d721642b06084, 0x27f002d7f95d0190), // 5^203
    f64_ex.new(0xcc20ce9bd35c78a5, 0x31ec038df7b441f4), // 5^204
    f64_ex.new(0xff290242c83396ce, 0x7e67047175a15271), // 5^205
    f64_ex.new(0x9f79a169bd203e41, 0xf0062c6e984d386), // 5^206
    f64_ex.new(0xc75809c42c684dd1, 0x52c07b78a3e60868), // 5^207
    f64_ex.new(0xf92e0c3537826145, 0xa7709a56ccdf8a82), // 5^208
    f64_ex.new(0x9bbcc7a142b17ccb, 0x88a66076400bb691), // 5^209
    f64_ex.new(0xc2abf989935ddbfe, 0x6acff893d00ea435), // 5^210
    f64_ex.new(0xf356f7ebf83552fe, 0x583f6b8c4124d43), // 5^211
    f64_ex.new(0x98165af37b2153de, 0xc3727a337a8b704a), // 5^212
    f64_ex.new(0xbe1bf1b059e9a8d6, 0x744f18c0592e4c5c), // 5^213
    f64_ex.new(0xeda2ee1c7064130c, 0x1162def06f79df73), // 5^214
    f64_ex.new(0x9485d4d1c63e8be7, 0x8addcb5645ac2ba8), // 5^215
    f64_ex.new(0xb9a74a0637ce2ee1, 0x6d953e2bd7173692), // 5^216
    f64_ex.new(0xe8111c87c5c1ba99, 0xc8fa8db6ccdd0437), // 5^217
    f64_ex.new(0x910ab1d4db9914a0, 0x1d9c9892400a22a2), // 5^218
    f64_ex.new(0xb54d5e4a127f59c8, 0x2503beb6d00cab4b), // 5^219
    f64_ex.new(0xe2a0b5dc971f303a, 0x2e44ae64840fd61d), // 5^220
    f64_ex.new(0x8da471a9de737e24, 0x5ceaecfed289e5d2), // 5^221
    f64_ex.new(0xb10d8e1456105dad, 0x7425a83e872c5f47), // 5^222
    f64_ex.new(0xdd50f1996b947518, 0xd12f124e28f77719), // 5^223
    f64_ex.new(0x8a5296ffe33cc92f, 0x82bd6b70d99aaa6f), // 5^224
    f64_ex.new(0xace73cbfdc0bfb7b, 0x636cc64d1001550b), // 5^225
    f64_ex.new(0xd8210befd30efa5a, 0x3c47f7e05401aa4e), // 5^226
    f64_ex.new(0x8714a775e3e95c78, 0x65acfaec34810a71), // 5^227
    f64_ex.new(0xa8d9d1535ce3b396, 0x7f1839a741a14d0d), // 5^228
    f64_ex.new(0xd31045a8341ca07c, 0x1ede48111209a050), // 5^229
    f64_ex.new(0x83ea2b892091e44d, 0x934aed0aab460432), // 5^230
    f64_ex.new(0xa4e4b66b68b65d60, 0xf81da84d5617853f), // 5^231
    f64_ex.new(0xce1de40642e3f4b9, 0x36251260ab9d668e), // 5^232
    f64_ex.new(0x80d2ae83e9ce78f3, 0xc1d72b7c6b426019), // 5^233
    f64_ex.new(0xa1075a24e4421730, 0xb24cf65b8612f81f), // 5^234
    f64_ex.new(0xc94930ae1d529cfc, 0xdee033f26797b627), // 5^235
    f64_ex.new(0xfb9b7cd9a4a7443c, 0x169840ef017da3b1), // 5^236
    f64_ex.new(0x9d412e0806e88aa5, 0x8e1f289560ee864e), // 5^237
    f64_ex.new(0xc491798a08a2ad4e, 0xf1a6f2bab92a27e2), // 5^238
    f64_ex.new(0xf5b5d7ec8acb58a2, 0xae10af696774b1db), // 5^239
    f64_ex.new(0x9991a6f3d6bf1765, 0xacca6da1e0a8ef29), // 5^240
    f64_ex.new(0xbff610b0cc6edd3f, 0x17fd090a58d32af3), // 5^241
    f64_ex.new(0xeff394dcff8a948e, 0xddfc4b4cef07f5b0), // 5^242
    f64_ex.new(0x95f83d0a1fb69cd9, 0x4abdaf101564f98e), // 5^243
    f64_ex.new(0xbb764c4ca7a4440f, 0x9d6d1ad41abe37f1), // 5^244
    f64_ex.new(0xea53df5fd18d5513, 0x84c86189216dc5ed), // 5^245
    f64_ex.new(0x92746b9be2f8552c, 0x32fd3cf5b4e49bb4), // 5^246
    f64_ex.new(0xb7118682dbb66a77, 0x3fbc8c33221dc2a1), // 5^247
    f64_ex.new(0xe4d5e82392a40515, 0xfabaf3feaa5334a), // 5^248
    f64_ex.new(0x8f05b1163ba6832d, 0x29cb4d87f2a7400e), // 5^249
    f64_ex.new(0xb2c71d5bca9023f8, 0x743e20e9ef511012), // 5^250
    f64_ex.new(0xdf78e4b2bd342cf6, 0x914da9246b255416), // 5^251
    f64_ex.new(0x8bab8eefb6409c1a, 0x1ad089b6c2f7548e), // 5^252
    f64_ex.new(0xae9672aba3d0c320, 0xa184ac2473b529b1), // 5^253
    f64_ex.new(0xda3c0f568cc4f3e8, 0xc9e5d72d90a2741e), // 5^254
    f64_ex.new(0x8865899617fb1871, 0x7e2fa67c7a658892), // 5^255
    f64_ex.new(0xaa7eebfb9df9de8d, 0xddbb901b98feeab7), // 5^256
    f64_ex.new(0xd51ea6fa85785631, 0x552a74227f3ea565), // 5^257
    f64_ex.new(0x8533285c936b35de, 0xd53a88958f87275f), // 5^258
    f64_ex.new(0xa67ff273b8460356, 0x8a892abaf368f137), // 5^259
    f64_ex.new(0xd01fef10a657842c, 0x2d2b7569b0432d85), // 5^260
    f64_ex.new(0x8213f56a67f6b29b, 0x9c3b29620e29fc73), // 5^261
    f64_ex.new(0xa298f2c501f45f42, 0x8349f3ba91b47b8f), // 5^262
    f64_ex.new(0xcb3f2f7642717713, 0x241c70a936219a73), // 5^263
    f64_ex.new(0xfe0efb53d30dd4d7, 0xed238cd383aa0110), // 5^264
    f64_ex.new(0x9ec95d1463e8a506, 0xf4363804324a40aa), // 5^265
    f64_ex.new(0xc67bb4597ce2ce48, 0xb143c6053edcd0d5), // 5^266
    f64_ex.new(0xf81aa16fdc1b81da, 0xdd94b7868e94050a), // 5^267
    f64_ex.new(0x9b10a4e5e9913128, 0xca7cf2b4191c8326), // 5^268
    f64_ex.new(0xc1d4ce1f63f57d72, 0xfd1c2f611f63a3f0), // 5^269
    f64_ex.new(0xf24a01a73cf2dccf, 0xbc633b39673c8cec), // 5^270
    f64_ex.new(0x976e41088617ca01, 0xd5be0503e085d813), // 5^271
    f64_ex.new(0xbd49d14aa79dbc82, 0x4b2d8644d8a74e18), // 5^272
    f64_ex.new(0xec9c459d51852ba2, 0xddf8e7d60ed1219e), // 5^273
    f64_ex.new(0x93e1ab8252f33b45, 0xcabb90e5c942b503), // 5^274
    f64_ex.new(0xb8da1662e7b00a17, 0x3d6a751f3b936243), // 5^275
    f64_ex.new(0xe7109bfba19c0c9d, 0xcc512670a783ad4), // 5^276
    f64_ex.new(0x906a617d450187e2, 0x27fb2b80668b24c5), // 5^277
    f64_ex.new(0xb484f9dc9641e9da, 0xb1f9f660802dedf6), // 5^278
    f64_ex.new(0xe1a63853bbd26451, 0x5e7873f8a0396973), // 5^279
    f64_ex.new(0x8d07e33455637eb2, 0xdb0b487b6423e1e8), // 5^280
    f64_ex.new(0xb049dc016abc5e5f, 0x91ce1a9a3d2cda62), // 5^281
    f64_ex.new(0xdc5c5301c56b75f7, 0x7641a140cc7810fb), // 5^282
    f64_ex.new(0x89b9b3e11b6329ba, 0xa9e904c87fcb0a9d), // 5^283
    f64_ex.new(0xac2820d9623bf429, 0x546345fa9fbdcd44), // 5^284
    f64_ex.new(0xd732290fbacaf133, 0xa97c177947ad4095), // 5^285
    f64_ex.new(0x867f59a9d4bed6c0, 0x49ed8eabcccc485d), // 5^286
    f64_ex.new(0xa81f301449ee8c70, 0x5c68f256bfff5a74), // 5^287
    f64_ex.new(0xd226fc195c6a2f8c, 0x73832eec6fff3111), // 5^288
    f64_ex.new(0x83585d8fd9c25db7, 0xc831fd53c5ff7eab), // 5^289
    f64_ex.new(0xa42e74f3d032f525, 0xba3e7ca8b77f5e55), // 5^290
    f64_ex.new(0xcd3a1230c43fb26f, 0x28ce1bd2e55f35eb), // 5^291
    f64_ex.new(0x80444b5e7aa7cf85, 0x7980d163cf5b81b3), // 5^292
    f64_ex.new(0xa0555e361951c366, 0xd7e105bcc332621f), // 5^293
    f64_ex.new(0xc86ab5c39fa63440, 0x8dd9472bf3fefaa7), // 5^294
    f64_ex.new(0xfa856334878fc150, 0xb14f98f6f0feb951), // 5^295
    f64_ex.new(0x9c935e00d4b9d8d2, 0x6ed1bf9a569f33d3), // 5^296
    f64_ex.new(0xc3b8358109e84f07, 0xa862f80ec4700c8), // 5^297
    f64_ex.new(0xf4a642e14c6262c8, 0xcd27bb612758c0fa), // 5^298
    f64_ex.new(0x98e7e9cccfbd7dbd, 0x8038d51cb897789c), // 5^299
    f64_ex.new(0xbf21e44003acdd2c, 0xe0470a63e6bd56c3), // 5^300
    f64_ex.new(0xeeea5d5004981478, 0x1858ccfce06cac74), // 5^301
    f64_ex.new(0x95527a5202df0ccb, 0xf37801e0c43ebc8), // 5^302
    f64_ex.new(0xbaa718e68396cffd, 0xd30560258f54e6ba), // 5^303
    f64_ex.new(0xe950df20247c83fd, 0x47c6b82ef32a2069), // 5^304
    f64_ex.new(0x91d28b7416cdd27e, 0x4cdc331d57fa5441), // 5^305
    f64_ex.new(0xb6472e511c81471d, 0xe0133fe4adf8e952), // 5^306
    f64_ex.new(0xe3d8f9e563a198e5, 0x58180fddd97723a6), // 5^307
    f64_ex.new(0x8e679c2f5e44ff8f, 0x570f09eaa7ea7648), // 5^308
};
