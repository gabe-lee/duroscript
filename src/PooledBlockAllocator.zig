const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocError = std.mem.Allocator.Error;
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;
const BlockAllocator = @import("./BlockAllocator.zig");

/// Used to set in what compile modes safety checks are inserted as `@panic(msg)`
/// as opposed to `unreachable`
///
/// This allows explicit override of the normal safety-checking behavior with more explicit
/// information about the failure, at the cost of not allowing the optimizer to optimize away the checks
/// in modes equal to or 'less optimized' than the supplied mode
///
/// Each choice is in order from 'less optimized' to 'more optimized' and implies safety checks
/// will be inserted as `@panic(msg)` in that mode and all 'less optimized' modes,
/// and inserted as `unreachable` in all 'more optimized' modes
///
/// (for this setting release_fast is considered 'more optimized' than release_small)
/// - NEVER
/// - DUBUG_ONLY
/// - RELEASE_SAFE_AND_BELOW
/// - RELEASE_SMALL_AND_BELOW
/// - RELEASE_FAST_AND_BELOW
/// - ALWAYS
pub const SafetyCheckWithMessage = enum(u8) {
    /// Never trigger failed safety checks
    NEVER = 0,
    /// Only trigger failed safety checks in `debug` modes
    DUBUG_ONLY = 1,
    /// (Default)
    ///
    /// Only trigger failed safety checks in `debug` and `release_safe` modes
    RELEASE_SAFE_AND_BELOW = 2,
    /// Only trigger failed safety checks in `debug`, `release_safe`, and `release_small` modes
    RELEASE_SMALL_AND_BELOW = 3,
    /// Only trigger failed safety checks in `debug`, `release_safe`, `release_small`, and `release_fast` modes
    RELEASE_FAST_AND_BELOW = 4,
    /// Always trigger failed safety checks regardless of compile mode
    ALWAYS = 5,
};

pub const SafetyCheckSeverity = enum(u8) {
    /// Triggered safety checks are logged to stderr
    ///
    /// This may be useful to catch multiple problems at the same time,
    /// but will almost certainly cause undefined and possibly dangerous behavior, use with caution
    LOG = 0,
    /// (Default)
    ///
    /// Triggered safety checks panic immediately
    PANIC = 1,
};

/// Used to set how to handle errors/nulls returned by the backing allocator
pub const AllocErrorBehavior = enum(u8) {
    /// (Default)
    ///
    /// Return the error/null to the caller just like the backing allocator would
    RETURNS = 0,
    /// Panic with a message when given an error/null
    PANICS = 1,
    /// Consider error/null and unreachable condition from the backing allocator (DANGEROUS but may allow compiler optimizations)
    UNREACHABLE = 2,
};

/// Used to set if and when to automatically shrink the retained pool of memory blocks held by this allocator
pub const AutoShrinkBehavior = enum(u8) {
    /// Never automatically shrink allocator, only manually
    NEVER = 0,
    /// (Default)
    ///
    /// Only shrink when above the threshold and a free operation causes its own entire logical allocation to be unused.
    /// Does not worry if the shrink still doesn't drop allocator below threshold.
    SIMPLE = 1,
    /// Shrink when above the threshold by traversing entire free list and releasing all logical allocations that are entirely
    /// unused until the threshold has been met, more processing but always keeps under threshold if possible
    AGGRESSIVE = 2,
};

/// Used to set if and when to automatically shrink the retained pool of memory blocks held by this allocator
pub const ShrinkThreshold = union(enum(u8)) {
    /// Shrink if free memory bytes exceeds this max quantity, but NOT if it would drop free memory bytes below the min quantity
    FLAT_MIN_MAX: struct { min: usize, max: usize },
    /// (Default)
    ///
    /// Shrink if free memory exceeds this percentage of the total, but NOT if it would drop free memory below the min percentage
    PERCENT_MIN_MAX: struct { min: f64, max: f64 },
};

/// Configuration options for generating a concrete PooledBlockAllocator type
pub const Config = struct {
    /// How large each memory block is in bytes
    ///
    /// DEFAULT = `1024`
    ///
    /// MUST adhere to the following rules:
    /// - is a power of 2
    /// - block_size >= 64 (this allocator is not built to handle very small allocation granularity)
    block_size: usize = 1024,
    /// When requesting new memory from the backing allocator, needed bytes will be rounded
    /// up to a multiple of this number.
    ///
    /// DEFAULT = `std.mem.page_size`
    ///
    /// MUST adhere to the following rules:
    /// - is a power of 2
    /// - backing_request_size >= block_size
    /// - backing_request_size >= 64 (this allocator is not built to handle very small allocation granularity)
    ///
    /// This can be used to speculatively allocate additional memory for future allocations,
    /// thereby reducing the number of calls to the backing allocator,
    /// and also to prevent the backing allocator from wasting bytes when you ask for a number of
    /// bytes that is smaller than the smallest size of memory region that allocator
    /// can allocate
    ///
    /// For example, when using the `std.mem.page_allocator` as a backing allocator, if
    /// you ask for a 1024 byte block of memory, it returns a slice of 1024 bytes, but in reality
    /// it allocated an entire page of system memory anywhere from 4096 to 64kib bytes, and all
    /// the remaining memory is wasted. You could instead set this to std.mem.page_size
    /// to ensure you always get the full page back to use and chop it into separate blocks to use
    ///
    /// (The backing allocator SHOULD know how to resize in place, but this setting allows the
    /// PooledBlockAllocator to be agnostic of that behavior)
    ///
    /// Setting this equal to `block_size` effectively disables any speculative allocation
    /// or potential efficiency gains.
    backing_request_size: usize = mem.page_size,
    /// Determines whether or not freed memory is explicitly overwritten with dummy bytes before
    /// being returned to the backing allocator or OS. Takes a bit of additional processing,
    /// but is recomended for sensitive data applications
    ///
    /// DEFAULT = `false`
    ///
    /// The exact byte written to memory is determined by the compiler mode:
    /// - `debug` = `0xAA` to adhere to the conventions expected by `Debug` mode
    /// - (Others) = `0x00`
    ///
    /// Note that if this is set to false the compiler will still
    /// evaluate `@memset(_, undefined)` on the freed memory (this behavior is optimized away
    /// by the comipler in more optimized modes than `debug`)
    secure_wipe_freed_memory: bool = false,
    /// Specifies in what levels of compiler optimization modes safety checks are inserted as `@panic(msg)`/`std.log.err()` or as `unreachable`
    ///
    /// DEFAULT = `.RELEASE_SAFE_AND_BELOW`
    ///
    /// The compiler cannot optimize out the safety checks in this or any 'less optimized' mode, but give better
    /// feedback on failures in those modes
    safety_checks: SafetyCheckWithMessage = SafetyCheckWithMessage.RELEASE_SAFE_AND_BELOW,
    /// Specifies how a triggered safety check message is reported (either as a `@panic(msg)` or `std.log.err()`)
    ///
    /// DEFAULT = `.PANIC`
    ///
    /// The `.LOG` setting may help see multiple errors simultaneously, but will almost certainly allow undefined and possible dangerous
    /// behavior to occur
    safety_check_severity: SafetyCheckSeverity = SafetyCheckSeverity.PANIC,
    /// Whether an error/null returned from the backing allocator should panic,
    /// if it should simply pass on the error/null as normal, or if it should be
    /// considered an unreachable condition
    ///
    /// DEFAULT = `.RETURNS`
    alloc_error_behavior: AllocErrorBehavior = AllocErrorBehavior.RETURNS,
    /// The unsigned integer type used to index individual blocks of memory internally.
    ///
    /// DEFAULT = `u32`
    ///
    /// The max value of this integer type imposes a maximum limit on how many total bytes
    /// can be allocated by each instance of this allocator with this same config (`std.math.maxInt(index_type) * block_size`)
    ///
    /// However, using a smaller type reduces the memory footprint of blocks reserved for internal book-keeping
    /// and reduces bloat when using a small `block_size` setting. It is generally NOT recomended to change this setting
    /// unless you are absolutely sure you need to and understand the tradeoffs.
    index_type: type = u32,
    /// How the allocator should automatically shrink the retained unused memory blocks, if at all
    ///
    /// DEFAULT = `.SIMPLE` (free when the opportunity arises but do not loop entire free list)
    ///
    /// Other options:
    /// - `.NEVER` = Only shrink retained memory manually
    /// - `.AGGRESSIVE` = loop over entire free list and release any allocations possible until below threshold
    auto_shrink: AutoShrinkBehavior = .SIMPLE,
    /// When the allocator should consider releasing unused retained memory
    ///
    /// DEFAULT = `.{ .PERCENT_MIN_MAX = .{ .min = 0.25, .max = 0.5 } }`
    /// (consider releasing if free bytes >= 50% of total bytes, but NOT if it would drop below 25%)
    ///
    /// Other options:
    /// - `.{ .FLAT_MIN_MAX = .{ .min = n, .max = m } }` = consider releasing when free bytes exceed this quantity, but not if it would drop below the minimum
    ///
    /// In any mode you can set `.min` to `0` to effectively ignore the minimum setting
    auto_shrink_threshold: ShrinkThreshold = .{ .PERCENT_MIN_MAX = .{ .min = 0.25, .max = 0.5 } },
};

/// Enum to signal whether a MemSpan is unassigned, assigned to free, or assigned to used
const SpanState = enum(u2) {
    /// MemSpan does not represent any real memory
    UNASSIGNED,
    /// MemSpan represents free memory
    ASSIGNED_FREE,
    /// MemSpan represents used memory
    ASSIGNED_USED,
    /// MemSpan is not in any list (in-between operations)
    NONE,
};

const MAX_ALIGN = std.mem.page_size;
const LOG2_OF_MAX_ALIGN = math.log2_int(comptime_int, MAX_ALIGN);

/// Defines a new concrete PooledBlockAllocator type that uses the provided `Config` struct to build all the necessary constants and safety checks
/// for this allocator.
pub fn define(comptime config: Config) type {
    if (!math.isPowerOfTwo(config.block_size) or config.block_size < 64) @compileError("Config.block_size MUST be a power of 2 and >= 64 (64, 128, 256, 512, 1024, 2048, 4096, ... etc)");
    if (!math.isPowerOfTwo(config.backing_request_size)) @compileError("Config.backing_request_size MUST be a power of 2 and >= 64 (64, 128, 256, 512, 1024, 2048, 4096, ... etc)");
    if (config.backing_request_size < config.block_size) @compileError("Config.backing_request_size MUST be >= Config.block_size");
    if (config.index_type != u64 and config.index_type != u32 and config.index_type != u16 and config.index_type != u8 and config.index_type != usize)
        @compileError("Config.index_type MUST be one of the following types: u8, u16, u32, u64, usize");
    switch (config.auto_shrink_threshold) {
        .PERCENT_MIN_MAX => |val| {
            if (val.min >= val.max or val.max >= 1.0)
                @compileError("Config.auto_shrink_threshold is set to .PERCENT_MIN_MAX, but either min >= max, or max >= 1.0 (will never shrink, just use Config.auto_shrink = .NEVER instead)");
        },
        else => {},
    }
    return struct {
        const Self = @This();
        const BLOCK_SIZE = config.block_size;
        const LOG2_OF_BLOCK_SIZE = math.log2_int(usize, BLOCK_SIZE);
        const BACKING_SIZE = config.backing_request_size;
        const LOG2_OF_BACKING_SIZE = math.log2_int(usize, BACKING_SIZE);
        const BLOCK_BACKING_RATIO = BACKING_SIZE / BLOCK_SIZE;
        const LOG2_OF_BLOCK_BACKING_RATIO = LOG2_OF_BACKING_SIZE - LOG2_OF_BLOCK_SIZE;
        const WIPE_ON_FREE = config.secure_wipe_freed_memory;
        const SAFETY_CHECKS = config.safety_checks;
        const SAFETY_SEVERE = config.safety_check_severity;
        const ALLOC_ERROR = config.alloc_error_behavior;
        const WIPE_MEM_BYTE = if (builtin.mode == .Debug) 0xAA else 0x00;
        const T_IDX: type = config.index_type;
        const MAX_TOTAL_ALLOC_BYTES = (1 << @typeInfo(T_IDX).Int.bits) * BLOCK_SIZE;
        const NO_IDX = math.maxInt(T_IDX);
        const AUTO_SHRINK = config.auto_shrink;
        const AUTO_SHRINK_THRESH = config.auto_shrink_threshold;

        const Bool_or_OptionalBool = if (ALLOC_ERROR == AllocErrorBehavior.RETURNS) ?bool else bool;
        const Void_or_OptionalVoid = if (ALLOC_ERROR == AllocErrorBehavior.RETURNS) ?void else void;
        const T_IDX_or_OptionalT_IDX = if (ALLOC_ERROR == AllocErrorBehavior.RETURNS) ?T_IDX else T_IDX;

        const MemSpanLogical = struct {
            mem_ptr: [*]u8,
            block_len: T_IDX,
        };

        /// A span of contiguous MemBlocks that all point to contiguous real memory and are all being used for the same purpose
        const MemSpan = struct {
            const LOG2_ALIGN = @as(u8, std.math.log2_int(usize, @alignOf(MemSpan)));
            const SIZE = @sizeOf(MemSpan);
            const SIZE_8 = @sizeOf(MemSpan) * 8;

            mem_ptr: [*]u8,
            block_len: T_IDX,
            next_same_state_ll: T_IDX,
            prev_same_state_ll: T_IDX,
            next_logical: T_IDX,
            prev_logical: T_IDX,
            state: SpanState,
        };

        /// The backing allocator used to request memory from
        backing_alloc: Allocator,
        /// A pointer to the portion of allocated MemBlocks that holds the internal book-keeping portion of the allocator
        span_list: [*]MemSpan,
        /// The index of the MemBlock that holds the internal book-keeping portion of the allocator
        span_list_idx: T_IDX,
        /// How many MemBlocks currently exist in total in this allocator
        span_list_len: T_IDX,
        /// How many total MemBlocks can be held in the internal book-keeping memory before book-keeping span must be re-allocated
        span_list_cap: T_IDX,
        /// Index of the first free MemSpan in a linked-list of all free MemSpans
        first_free_span: T_IDX,
        /// Index of the first used MemSpan in a linked-list of all used MemSpans
        first_used_span: T_IDX,
        /// Index of the first unassigned MemSpan in a linked-list of all unassigned MemSpans
        first_unassigned_span: T_IDX,
        /// Total number of blocks allocated from the backing allocator
        total_mem_blocks: T_IDX,
        /// Total number of blocks currently free
        free_mem_blocks: T_IDX,

        /// Makes safety-checked assertions based on the `Config.safety_checks` and `Config.safety_check_severity` settings
        ///
        /// This function is used to safety check values that can be input by the user of this allocator,
        /// for behavior that should be asserted based on internally expected behavior should use `debug_assert()` instead
        inline fn user_assert(condition: bool, msg: []const u8) void {
            switch (SAFETY_CHECKS) {
                .NEVER => if (!condition) unreachable,
                .DUBUG_ONLY => if (builtin.mode == .Debug) {
                    if (!condition) switch (SAFETY_SEVERE) {
                        .PANIC => @panic(msg),
                        .LOG => std.log.err(msg, .{}),
                    };
                } else if (!condition) unreachable,
                .RELEASE_SAFE_AND_BELOW => if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                    if (!condition) switch (SAFETY_SEVERE) {
                        .PANIC => @panic(msg),
                        .LOG => std.log.err(msg, .{}),
                    };
                } else if (!condition) unreachable,
                .RELEASE_SMALL_AND_BELOW => if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe or builtin.mode == .ReleaseSmall) {
                    if (!condition) switch (SAFETY_SEVERE) {
                        .PANIC => @panic(msg),
                        .LOG => std.log.err(msg, .{}),
                    };
                } else if (!condition) unreachable,
                .RELEASE_FAST_AND_BELOW => if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe or builtin.mode == .ReleaseSmall or builtin.mode == .ReleaseFast) {
                    if (!condition) switch (SAFETY_SEVERE) {
                        .PANIC => @panic(msg),
                        .LOG => std.log.err(msg, .{}),
                    };
                } else if (!condition) unreachable,
                .ALWAYS => if (!condition) switch (SAFETY_SEVERE) {
                    .PANIC => @panic(msg),
                    .LOG => std.log.err(msg, .{}),
                },
            }
        }

        inline fn should_user_assert() bool {
            return switch (SAFETY_CHECKS) {
                .NEVER => false,
                .DUBUG_ONLY => builtin.mode == .Debug,
                .RELEASE_SAFE_AND_BELOW => builtin.mode == .Debug or builtin.mode == .ReleaseSafe,
                .RELEASE_SMALL_AND_BELOW => builtin.mode == .Debug or builtin.mode == .ReleaseSafe or builtin.mode == .ReleaseSmall,
                .RELEASE_FAST_AND_BELOW => builtin.mode == .Debug or builtin.mode == .ReleaseSafe or builtin.mode == .ReleaseSmall or builtin.mode == .ReleaseFast,
                .ALWAYS => true,
            };
        }

        inline fn align_bytes_to_blocks(bytes: usize) usize {
            return std.mem.alignForward(usize, bytes, BLOCK_SIZE);
        }

        inline fn align_bytes_to_backing_blocks(bytes: usize) usize {
            return std.mem.alignForward(usize, bytes, BACKING_SIZE);
        }

        inline fn bytes_to_blocks(bytes: usize) T_IDX {
            return @intCast(std.mem.alignForward(usize, bytes, BLOCK_SIZE) >> LOG2_OF_BLOCK_SIZE);
        }

        inline fn blocks_to_bytes(blocks: T_IDX) usize {
            return @as(usize, @intCast(blocks)) << LOG2_OF_BLOCK_SIZE;
        }

        inline fn align_blocks_to_backing_blocks(blocks: T_IDX) T_IDX {
            if (BACKING_SIZE == BLOCK_SIZE) {
                return blocks;
            } else return std.mem.alignForward(T_IDX, blocks, BLOCK_BACKING_RATIO);
        }

        inline fn calculate_fraction_T_IDX(numer: T_IDX, denom: T_IDX) f64 {
            return @as(f64, @floatFromInt(numer)) / @as(f64, @floatFromInt(denom));
        }

        inline fn is_above_max_shrink_threshold(self: *Self) bool {
            switch (AUTO_SHRINK_THRESH) {
                .PERCENT_MIN_MAX => |val| {
                    return calculate_fraction_T_IDX(self.free_mem_blocks, self.total_mem_blocks) >= val.max;
                },
                .FLAT_MIN_MAX => |val| {
                    return (@as(usize, self.free_mem_blocks) << LOG2_OF_BLOCK_SIZE) >= val.max;
                },
            }
        }

        inline fn after_shink_is_above_min_shrink_threshold(self: *Self, removed_blocks: T_IDX) bool {
            switch (AUTO_SHRINK_THRESH) {
                .PERCENT_MIN_MAX => |val| {
                    return calculate_fraction_T_IDX(self.free_mem_blocks - removed_blocks, self.total_mem_blocks - removed_blocks) >= val.min;
                },
                .FLAT_MIN_MAX => |val| {
                    return (@as(usize, self.free_mem_blocks - removed_blocks) << LOG2_OF_BLOCK_SIZE) >= val.min;
                },
            }
        }

        fn is_above_custom_max_shrink_threshold(self: *Self, threshold: ShrinkThreshold) bool {
            @setCold(true);
            switch (threshold) {
                .PERCENT_MIN_MAX => |val| {
                    return calculate_fraction_T_IDX(self.free_mem_blocks, self.total_mem_blocks) >= val.max;
                },
                .FLAT_MIN_MAX => |val| {
                    return (@as(usize, self.free_mem_blocks) << LOG2_OF_BLOCK_SIZE) >= val.max;
                },
            }
        }

        fn after_shink_is_above_custom_min_shrink_threshold(self: *Self, threshold: ShrinkThreshold, removed_blocks: T_IDX) bool {
            @setCold(true);
            switch (threshold) {
                .PERCENT_MIN_MAX => |val| {
                    return calculate_fraction_T_IDX(self.free_mem_blocks - removed_blocks, self.total_mem_blocks - removed_blocks) >= val.min;
                },
                .FLAT_MIN_MAX => |val| {
                    return (@as(usize, self.free_mem_blocks - removed_blocks) << LOG2_OF_BLOCK_SIZE) >= val.min;
                },
            }
        }

        inline fn clear_mem_if_needed(self: *Self, span_to_clear: T_IDX) void {
            debug_assert(span_to_clear < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            const mem_ptr = self.span_list[span_to_clear].mem_ptr;
            const mem_len = @as(usize, self.span_list[span_to_clear].block_len) << LOG2_OF_BLOCK_SIZE;
            if (WIPE_ON_FREE) {
                @memset(@as([]volatile u8, mem_ptr[0..mem_len]), WIPE_MEM_BYTE);
            } else @memset(mem_ptr[0..mem_len], undefined);
        }

        /// creates a new instance of PooledBlockAllocator(Config) using the given backing allocator
        ///
        /// Does not allocate/reserve/retain any memory until the first call to its Allocator.alloc()
        pub fn new(backing_allocator: Allocator) Self {
            return Self{
                .backing_alloc = backing_allocator,
                .span_list = @ptrFromInt(mem.alignBackward(usize, math.maxInt(usize), @alignOf(MemSpan))),
                .span_list_cap = 0,
                .span_list_len = 0,
                .span_list_idx = NO_IDX,
                .first_free_span = NO_IDX,
                .first_used_span = NO_IDX,
                .first_unassigned_span = NO_IDX,
                .free_mem_blocks = 0,
                .total_mem_blocks = 0,
            };
        }

        /// Returns an `Allocator` interface struct for this allocator
        pub fn allocator(self: *Self) Allocator {
            return Allocator{
                .ptr = self,
                .vtable = &Allocator.VTable{
                    .alloc = raw_alloc_ptr_only,
                    .resize = raw_resize_bool_only,
                    .free = raw_free,
                },
            };
        }

        fn block_size() usize {
            return BLOCK_SIZE;
        }

        /// Returns a `BlockAllocator` interface struct for this allocator
        pub fn block_allocator(self: *Self) BlockAllocator {
            return BlockAllocator{
                .interface = .{
                    .self_opaque = self,
                    .alloc = raw_alloc,
                    .resize = raw_resize,
                    .free = raw_free,
                    .block_size = block_size,
                },
            };
        }

        /// Given the supplied shrinking threshold, loop over entire free list and find any allocations that are entirely
        /// unused and release them to the backing allocator or OS, but NOT if it would drop free memory below the min threshold.
        ///
        /// Stops when free memory is below the max threshold or free list is exhausted
        pub fn shrink_if_possible(self: *Self, threshold: ShrinkThreshold) void {
            self.SUPER_DEBUG_trace_open("shrink_if_possible", ""); // DEBUG
            defer self.SUPER_DEBUG_trace_close("shrink_if_possible"); // DEBUG
            @setCold(true);
            var curr_free = self.first_free_span;
            var is_above_threshold = self.is_above_custom_max_shrink_threshold(threshold);
            while (curr_free != NO_IDX and is_above_threshold) {
                debug_assert(curr_free < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                const blocks = self.span_list[curr_free].block_len;
                if (self.span_list[curr_free].prev_logical == NO_IDX and
                    self.span_list[curr_free].next_logical == NO_IDX and
                    self.after_shink_is_above_custom_min_shrink_threshold(threshold, blocks))
                {
                    self.release_span_to_backing_or_os(curr_free);
                }
                curr_free = self.span_list[curr_free].next_same_state_ll;
                is_above_threshold = self.is_above_custom_max_shrink_threshold(threshold);
            }
        }

        /// Loops over all free and used memory and releases it to the backing allocator or OS, invalidating any existing in-use memory pointers
        ///
        /// Attempting to release memory still in-use is safety-checked (dependant on setting of Config.safety_checks_panic),
        /// but full release and any applicable memory wiping will still occur before any potential error message or panic.
        pub fn release_all_memory(self: *Self) void {
            var did_release_used_mem = false;
            var curr_used_span = self.first_used_span;
            while (curr_used_span != NO_IDX) {
                if (curr_used_span == self.span_list_idx) {
                    curr_used_span = self.span_list[curr_used_span].next_same_state_ll;
                    if (curr_used_span == NO_IDX) break;
                }
                did_release_used_mem = true;
                self.free_used_span(curr_used_span, false);
                curr_used_span = self.first_used_span;
            }
            var curr_free_span = self.first_free_span;
            while (curr_free_span != NO_IDX) {
                if (self.span_list[curr_free_span].prev_logical != NO_IDX or self.span_list[curr_free_span].next_logical != NO_IDX) {
                    curr_free_span = self.span_list[curr_free_span].next_same_state_ll;
                    if (curr_free_span == NO_IDX) break;
                }
                self.release_span_to_backing_or_os(curr_free_span);
                curr_used_span = self.first_used_span;
            }
            debug_assert(self.first_used_span == self.span_list_idx, "PooledBlockAllocator.release_all_memory: first used block isnt span_list block");
            debug_assert(self.span_list[self.first_used_span].next_same_state_ll == NO_IDX, "PooledBlockAllocator.release_all_memory: last used block isnt span_list block");
            const last_logical_in_last_allocation = if (self.span_list[self.span_list_idx].next_logical == NO_IDX) self.span_list_idx else self.span_list[self.span_list_idx].next_logical;
            const last_allocation = self.collect_entire_logical_span_from_last(last_logical_in_last_allocation);
            self.clear_mem_if_needed(self.span_list_idx);
            const last_allocation_bytes = (@as(usize, last_allocation.block_len) << LOG2_OF_BLOCK_SIZE);
            self.backing_alloc.rawFree(last_allocation.mem_ptr[0..last_allocation_bytes], LOG2_OF_BLOCK_SIZE, 0);
            self.* = Self{
                .backing_alloc = self.backing_alloc,
                .span_list = @ptrFromInt(mem.alignBackward(usize, math.maxInt(usize), @alignOf(MemSpan))),
                .span_list_cap = 0,
                .span_list_len = 0,
                .span_list_idx = NO_IDX,
                .first_free_span = NO_IDX,
                .first_used_span = NO_IDX,
                .first_unassigned_span = NO_IDX,
                .free_mem_blocks = 0,
                .total_mem_blocks = 0,
            };
            user_assert(!did_release_used_mem, USER_ERROR_RELEASED_USED_MEMORY);
        }

        fn split_free_span(self: *Self, span_idx: T_IDX, first_len: T_IDX) T_IDX_or_OptionalT_IDX {
            self.SUPER_DEBUG_trace_open("split_free_span", prnt_inpt("span_idx: {d}, first_len: {d}", .{ span_idx, first_len })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("split_free_span"); // DEBUG
            debug_assert(span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span_idx].block_len > first_len and first_len > 0, DEBUG_ATTEMPT_TO_SPLIT_SPAN_ONE_WITH_ZERO_BLOCKS);
            self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(span_idx, .ASSIGNED_FREE); //DEBUG
            debug_assert(self.span_list[span_idx].state == .ASSIGNED_FREE, DEBUG_ATTEMPT_TO_SPLIT_SPAN_NOT_FREE);
            const second_idx = if (ALLOC_ERROR == AllocErrorBehavior.RETURNS) (self.claim_unassigned_span() orelse return null) else self.claim_unassigned_span();
            self.span_list[second_idx].prev_logical = span_idx;
            self.span_list[second_idx].next_logical = self.span_list[span_idx].next_logical;
            self.span_list[span_idx].next_logical = second_idx;
            self.span_list[second_idx].mem_ptr = self.span_list[span_idx].mem_ptr + (@as(usize, first_len) << LOG2_OF_BLOCK_SIZE);
            self.span_list[second_idx].block_len = self.span_list[span_idx].block_len - first_len;
            self.span_list[span_idx].block_len = first_len;
            self.add_span_to_begining_of_linked_list(second_idx, .ASSIGNED_FREE);
            return second_idx;
        }

        inline fn update_span_list_cap(self: *Self) void {
            self.update_span_list_cap_manual(self.span_list[self.span_list_idx].block_len);
        }

        inline fn update_span_list_cap_manual(self: *Self, new_span_list_blocks: T_IDX) void {
            self.span_list_cap = @intCast((@as(usize, new_span_list_blocks) << LOG2_OF_BLOCK_SIZE) / @sizeOf(MemSpan));
        }

        fn free_used_span(self: *Self, span_idx: T_IDX, comptime allow_auto_shrink: bool) void {
            self.SUPER_DEBUG_trace_open("free_used_span", prnt_inpt("span_idx: {d}", .{span_idx})); // DEBUG
            defer self.SUPER_DEBUG_trace_close("free_used_span"); // DEBUG
            debug_assert(span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span_idx].state == .ASSIGNED_USED, DEBUG_ATTEMPT_TO_FREE_NON_USED_SPAN);
            // Remove span from used list and add it to free list with free state
            self.free_mem_blocks += self.span_list[span_idx].block_len;
            self.clear_mem_if_needed(span_idx);
            self.remove_span_from_its_linked_list(span_idx, .ASSIGNED_USED);
            self.add_span_to_begining_of_linked_list(span_idx, .ASSIGNED_FREE);
            var root_free = span_idx;
            // If next logical span exists and is also in free state, remove it from the free linked-list, combine its length with current span,
            // and put it in the unassigned linked-list
            const next_logical = self.span_list[span_idx].next_logical;
            debug_assert(next_logical == NO_IDX or next_logical < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            if (next_logical != NO_IDX and self.span_list[next_logical].state == .ASSIGNED_FREE) {
                debug_assert(self.span_list[next_logical].mem_ptr == self.span_list[span_idx].mem_ptr + (@as(usize, self.span_list[span_idx].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
                self.remove_span_from_its_linked_list(next_logical, .ASSIGNED_FREE);
                self.span_list[span_idx].next_logical = self.span_list[next_logical].next_logical;
                self.span_list[span_idx].block_len += self.span_list[next_logical].block_len;
                self.add_span_to_begining_of_linked_list(next_logical, .UNASSIGNED);
            }
            // If prev logical span exists and is also in free state, remove THIS span from the free linked-list, combine its length with prev span,
            // and put it in the unassigned linked-list
            const prev_logical = self.span_list[span_idx].prev_logical;
            debug_assert(prev_logical == NO_IDX or prev_logical < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            if (prev_logical != NO_IDX and self.span_list[prev_logical].state == .ASSIGNED_FREE) {
                debug_assert(self.span_list[span_idx].mem_ptr == self.span_list[prev_logical].mem_ptr + (@as(usize, self.span_list[prev_logical].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
                self.remove_span_from_its_linked_list(span_idx, .ASSIGNED_FREE);
                self.span_list[prev_logical].next_logical = self.span_list[span_idx].next_logical;
                self.span_list[prev_logical].block_len += self.span_list[span_idx].block_len;
                self.add_span_to_begining_of_linked_list(span_idx, .UNASSIGNED);
                root_free = prev_logical;
            }
            if (allow_auto_shrink) {
                switch (AUTO_SHRINK) {
                    .NEVER => {},
                    .SIMPLE => {
                        if (self.is_above_max_shrink_threshold() and self.after_shink_is_above_min_shrink_threshold(self.span_list[root_free].block_len)) {
                            if (self.span_list[root_free].prev_logical == NO_IDX and self.span_list[root_free].next_logical == NO_IDX) {
                                self.release_span_to_backing_or_os(root_free);
                            }
                        }
                    },
                    .AGGRESSIVE => {
                        var curr_free = self.first_free_span;
                        var is_above_threshold = self.is_above_max_shrink_threshold();
                        while (curr_free != NO_IDX and is_above_threshold) {
                            debug_assert(curr_free < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                            const blocks = self.span_list[curr_free].block_len;
                            if (self.span_list[curr_free].prev_logical == NO_IDX and
                                self.span_list[curr_free].next_logical == NO_IDX and
                                self.after_shink_is_above_min_shrink_threshold(blocks))
                            {
                                self.release_span_to_backing_or_os(curr_free);
                            }
                            curr_free = self.span_list[curr_free].next_same_state_ll;
                            is_above_threshold = self.is_above_max_shrink_threshold();
                        }
                    },
                }
            }
        }

        fn add_unassigned_span_but_not_to_list(self: *Self) T_IDX {
            debug_assert(self.span_list_len < self.span_list_cap, DEBUG_NO_CAP_TO_ADD_MEMSPAN);
            self.span_list[self.span_list_len] = MemSpan{
                .mem_ptr = @ptrFromInt(std.math.maxInt(usize)),
                .block_len = 0,
                .next_same_state_ll = NO_IDX,
                .prev_same_state_ll = NO_IDX,
                .next_logical = NO_IDX,
                .prev_logical = NO_IDX,
                .state = .NONE,
            };
            const idx = self.span_list_len;
            self.span_list_len += 1;
            return idx;
        }

        fn add_unassigned_span(self: *Self) T_IDX {
            const idx = self.add_unassigned_span_but_not_to_list();
            self.add_span_to_begining_of_linked_list(idx, .UNASSIGNED);
            return idx;
        }

        fn add_free_span_but_not_to_list(self: *Self, ptr: [*]u8, block_len: T_IDX) T_IDX {
            debug_assert(self.span_list_len < self.span_list_cap, DEBUG_NO_CAP_TO_ADD_MEMSPAN);
            self.span_list[self.span_list_len] = MemSpan{
                .mem_ptr = ptr,
                .block_len = block_len,
                .next_same_state_ll = NO_IDX,
                .prev_same_state_ll = NO_IDX,
                .next_logical = NO_IDX,
                .prev_logical = NO_IDX,
                .state = .NONE,
            };
            const idx = self.span_list_len;
            self.span_list_len += 1;
            return idx;
        }

        fn add_free_span(self: *Self, ptr: [*]u8, block_len: T_IDX) T_IDX {
            const idx = self.add_free_span_but_not_to_list(ptr, block_len);
            self.add_span_to_begining_of_linked_list(idx, .ASSIGNED_FREE);
            return idx;
        }

        fn add_used_span_but_not_to_list(self: *Self, ptr: [*]u8, block_len: T_IDX) T_IDX {
            debug_assert(self.span_list_len < self.span_list_cap, DEBUG_NO_CAP_TO_ADD_MEMSPAN);
            self.span_list[self.span_list_len] = MemSpan{
                .mem_ptr = ptr,
                .block_len = block_len,
                .next_same_state_ll = NO_IDX,
                .prev_same_state_ll = NO_IDX,
                .next_logical = NO_IDX,
                .prev_logical = NO_IDX,
                .state = .NONE,
            };
            const idx = self.span_list_len;
            self.span_list_len += 1;
            return idx;
        }

        fn add_used_span(self: *Self, ptr: [*]u8, block_len: T_IDX) T_IDX {
            const idx = self.add_used_span_but_not_to_list(ptr, block_len);
            self.add_span_to_begining_of_linked_list(idx, .ASSIGNED_USED);
            return idx;
        }

        fn transfer_span_list_to_new_alloc(self: *Self, old_span_list_bytes: usize, new_alloc_ptr: [*]u8, new_span_list_blocks: T_IDX) void {
            const old_span_list_idx = self.span_list_idx;
            if (old_span_list_idx != NO_IDX) {
                const old_mem_slice = self.span_list[old_span_list_idx].mem_ptr[0..old_span_list_bytes];
                @memcpy(new_alloc_ptr, old_mem_slice);
            }
            self.span_list = @ptrCast(@alignCast(new_alloc_ptr));
            self.update_span_list_cap_manual(new_span_list_blocks);
            const new_span_list_idx = self.add_used_span(new_alloc_ptr, new_span_list_blocks);
            self.span_list_idx = new_span_list_idx;
            if (old_span_list_idx != NO_IDX) {
                self.free_used_span(old_span_list_idx, true);
            }
        }

        fn shift_blocks_from_next_logical_free_into_this_used_span(self: *Self, span_idx: T_IDX, count: T_IDX) void {
            debug_assert(span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span_idx].state == .ASSIGNED_USED, DEBUG_SPAN_WASNT_IN_USED_STATE);
            const next_logical = self.span_list[span_idx].next_logical;
            debug_assert(next_logical < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[next_logical].state == .ASSIGNED_FREE, DEBUG_NEXT_LOGICAL_FREE_ISNT_FREE);
            debug_assert(self.span_list[next_logical].prev_logical == span_idx, DEBUG_NEXT_LOGICAL_PREV_LOGICAL_DOESNT_MATCH);
            debug_assert(self.span_list[next_logical].block_len > count, DEBUG_NEXT_LOGICAL_FREE_NOT_ENOUGH_BLOCKS_TO_TAKE);
            debug_assert(self.span_list[next_logical].mem_ptr == self.span_list[span_idx].mem_ptr + (@as(usize, self.span_list[span_idx].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
            self.span_list[span_idx].block_len += count;
            self.span_list[next_logical].block_len -= count;
            self.span_list[next_logical].mem_ptr += (@as(usize, count) << LOG2_OF_BLOCK_SIZE);
            self.free_mem_blocks -= count;
        }

        /// Returns the idx of the old MemSpan that is now 'unassigned' but not in unassigned list
        fn merge_next_logical_free_into_this_used_span(self: *Self, span_idx: T_IDX) T_IDX {
            debug_assert(span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span_idx].state == .ASSIGNED_USED, DEBUG_SPAN_WASNT_IN_USED_STATE);
            const next_logical = self.span_list[span_idx].next_logical;
            debug_assert(next_logical < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[next_logical].state == .ASSIGNED_FREE, DEBUG_NEXT_LOGICAL_FREE_ISNT_FREE);
            debug_assert(self.span_list[next_logical].prev_logical == span_idx, DEBUG_NEXT_LOGICAL_PREV_LOGICAL_DOESNT_MATCH);
            debug_assert(self.span_list[next_logical].mem_ptr == self.span_list[span_idx].mem_ptr + (@as(usize, self.span_list[span_idx].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
            self.span_list[span_idx].block_len += self.span_list[next_logical].block_len;
            self.free_mem_blocks -= self.span_list[next_logical].block_len;
            self.span_list[next_logical].block_len = 0;
            self.span_list[next_logical].mem_ptr = @ptrFromInt(std.math.maxInt(usize));
            const next_next_logical = self.span_list[next_logical].next_logical;
            self.span_list[span_idx].next_logical = next_next_logical;
            if (next_next_logical != NO_IDX) {
                debug_assert(self.span_list[next_next_logical].mem_ptr == self.span_list[span_idx].mem_ptr + (@as(usize, self.span_list[span_idx].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
                self.span_list[next_next_logical].prev_logical = span_idx;
            }
            self.remove_span_from_its_linked_list(next_logical, .ASSIGNED_FREE);
            return next_logical;
        }

        fn release_span_to_backing_or_os(self: *Self, span: T_IDX) void {
            self.SUPER_DEBUG_trace_open("release_span_to_backing_or_os", prnt_inpt("span: {d}", .{span})); // DEBUG
            defer self.SUPER_DEBUG_trace_close("release_span_to_backing_or_os"); // DEBUG
            debug_assert(self.span_list[span].prev_logical == NO_IDX and self.span_list[span].next_logical == NO_IDX, DEBUG_RELEASE_NON_FREE_SPAN);
            debug_assert(self.span_list[span].state == .ASSIGNED_FREE, DEBUG_RELEASE_NON_FREE_SPAN);
            const total_blocks = self.span_list[span].block_len;
            const total_bytes = (@as(usize, total_blocks) << LOG2_OF_BLOCK_SIZE);
            self.backing_alloc.rawFree(self.span_list[span].mem_ptr[0..total_bytes], LOG2_OF_BLOCK_SIZE, 0);
            self.total_mem_blocks -= total_blocks;
            self.free_mem_blocks -= total_blocks;
            self.remove_span_from_its_linked_list(span, .ASSIGNED_FREE);
            self.add_span_to_begining_of_linked_list(span, .UNASSIGNED);
        }

        fn claim_unassigned_span(self: *Self) T_IDX_or_OptionalT_IDX {
            self.SUPER_DEBUG_trace_open("claim_unassigned_span", ""); // DEBUG
            defer self.SUPER_DEBUG_trace_close("claim_unassigned_span"); // DEBUG

            // Use existing unassigned span if possible
            if (self.first_unassigned_span != NO_IDX) {
                debug_assert(self.first_unassigned_span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                const claimed_idx = self.first_unassigned_span;
                self.remove_span_from_its_linked_list(claimed_idx, .UNASSIGNED);
                self.SUPER_DEBUG_trace_extra("took first unassigned span"); // DEBUG
                self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(claimed_idx, .NONE); //DEBUG
                return claimed_idx;
            }
            // Just add a new unassigned span if space in span list exists
            if (self.span_list_len < self.span_list_cap) {
                const claimed_idx = self.add_unassigned_span_but_not_to_list();
                self.SUPER_DEBUG_trace_extra("added new blank span to end of list"); // DEBUG
                self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(claimed_idx, .NONE); //DEBUG
                return claimed_idx;
            }
            // If span_pool is not at end of logical allocation and has a free span after it that can hold the extra needed blocks,
            // extend span_pool.block_len, add a new unassigned span, and return it
            if (self.span_list_idx != NO_IDX) {
                if (self.span_list[self.span_list_idx].next_logical != NO_IDX) {
                    const next_logical = self.span_list[self.span_list_idx].next_logical;
                    debug_assert(next_logical < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                    if (self.span_list[next_logical].state == .ASSIGNED_FREE) {
                        debug_assert(self.span_list[next_logical].block_len != 0, DEBUG_FOUND_FREE_OR_USED_SPAN_WITH_ZERO_BLOCKS);
                        if (self.span_list[next_logical].block_len == 1) {
                            const claimed_idx = self.merge_next_logical_free_into_this_used_span(self.span_list_idx);
                            self.update_span_list_cap();
                            self.SUPER_DEBUG_trace_extra("found next-logical span with 1 free block"); // DEBUG
                            self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(claimed_idx, .NONE); //DEBUG
                            return claimed_idx;
                        } else {
                            self.shift_blocks_from_next_logical_free_into_this_used_span(self.span_list_idx, 1);
                            self.update_span_list_cap();
                            self.SUPER_DEBUG_trace_extra("found next-logical span with >1 free block"); // DEBUG
                            const claimed_idx = self.add_unassigned_span_but_not_to_list();
                            self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(claimed_idx, .NONE); //DEBUG
                            return claimed_idx;
                        }
                    }
                } else {
                    // If span_pool IS at end of logical allocation and backing allocator will let it grow in place,
                    // extend span_pool.block_len, add a new unassigned span, and return it
                    const entire_logical_span = self.collect_entire_logical_span_from_last(self.span_list_idx);
                    const old_total_bytes = blocks_to_bytes(entire_logical_span.block_len);
                    const old_list_bytes = @as(usize, self.span_list_cap) * MemSpan.SIZE;
                    const new_list_bytes = old_list_bytes + MemSpan.SIZE_8;
                    const delta_grow_list_bytes = new_list_bytes - old_total_bytes;
                    const delta_grow_backing_bytes = align_bytes_to_backing_blocks(delta_grow_list_bytes);
                    if (self.backing_alloc.resize(entire_logical_span.mem_ptr[0..old_total_bytes], old_total_bytes + delta_grow_backing_bytes)) {
                        const delta_grow_list_blocks = bytes_to_blocks(delta_grow_list_bytes);
                        const delta_grow_total_blocks = bytes_to_blocks(delta_grow_backing_bytes);
                        self.total_mem_blocks += delta_grow_total_blocks;
                        self.span_list[self.span_list_idx].block_len += delta_grow_list_blocks;
                        self.update_span_list_cap();
                        if (delta_grow_total_blocks > delta_grow_list_blocks) {
                            const extra_free_blocks = delta_grow_total_blocks - delta_grow_list_blocks;
                            const new_free_span = self.add_unassigned_span_but_not_to_list();
                            self.assign_span_to_next_logical(self.span_list_idx, new_free_span, extra_free_blocks);
                            self.add_span_to_begining_of_linked_list(new_free_span, .ASSIGNED_FREE);
                            self.free_mem_blocks += extra_free_blocks;
                        }
                        const claimed_idx = self.add_unassigned_span_but_not_to_list();
                        debug_assert(self.span_list_cap >= self.span_list_len, DEBUG_EXPANDING_SPAN_POOL_MADE_CAP_LESS_THAN_LEN);
                        self.SUPER_DEBUG_trace_extra("expanded pool span IN-PLACE using backing allocator"); // DEBUG
                        self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(claimed_idx, .NONE); //DEBUG
                        return claimed_idx;
                    }
                }
            }
            // Reallocate span_list for additional capacity THEN add new unassigned span
            const old_list_bytes = @as(usize, self.span_list_cap) * MemSpan.SIZE;
            const new_list_bytes = old_list_bytes + MemSpan.SIZE_8;
            const new_span_list_blocks = bytes_to_blocks(new_list_bytes);
            const new_allocation_bytes = align_bytes_to_backing_blocks(new_list_bytes);
            const new_alloc_ptr = self.backing_alloc.rawAlloc(new_allocation_bytes, MemSpan.LOG2_ALIGN, 0) orelse switch (ALLOC_ERROR) {
                .RETURNS => return null,
                .PANICS => @panic("PooledBlockAllocator's backing allocator failed to allocate additional memory"),
                .UNREACHABLE => unreachable,
            };
            const new_total_allocation_blocks = bytes_to_blocks(new_allocation_bytes);
            self.total_mem_blocks += new_total_allocation_blocks;
            self.transfer_span_list_to_new_alloc(old_list_bytes, new_alloc_ptr, new_span_list_blocks);
            if (new_total_allocation_blocks > new_span_list_blocks) {
                const extra_free_blocks = new_total_allocation_blocks - new_span_list_blocks;
                const new_extra_free_blocks_idx = self.add_unassigned_span_but_not_to_list();
                self.assign_span_to_next_logical(self.span_list_idx, new_extra_free_blocks_idx, extra_free_blocks);
                self.add_span_to_begining_of_linked_list(new_extra_free_blocks_idx, .ASSIGNED_FREE);
                self.free_mem_blocks += extra_free_blocks;
            }
            const claimed_idx = self.add_unassigned_span_but_not_to_list();
            debug_assert(self.span_list_cap >= self.span_list_len, DEBUG_EXPANDING_SPAN_POOL_MADE_CAP_LESS_THAN_LEN);
            self.SUPER_DEBUG_trace_extra("allocated a brand new span from the backing allocator"); // DEBUG
            defer self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(claimed_idx, .NONE); //DEBUG
            return claimed_idx;
        }

        fn collect_entire_logical_span_from_last(self: *Self, last_span_idx: T_IDX) MemSpanLogical {
            self.SUPER_DEBUG_trace_open("collect_entire_logical_span_from_last", prnt_inpt("last_span_idx: {d}", .{last_span_idx})); // DEBUG
            defer self.SUPER_DEBUG_trace_close("collect_entire_logical_span_from_last"); // DEBUG
            debug_assert(self.span_list[last_span_idx].next_logical == NO_IDX, DEBUG_COLLECT_LOGICAL_FROM_END_SPAN_WASNT_LAST);
            var total_blocks = self.span_list[last_span_idx].block_len;
            var first_ptr = self.span_list[last_span_idx].mem_ptr;
            var prev_logical = self.span_list[last_span_idx].prev_logical;
            while (prev_logical != NO_IDX) {
                debug_assert(prev_logical < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                debug_assert(self.span_list[prev_logical].mem_ptr == first_ptr - (@as(usize, self.span_list[prev_logical].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
                total_blocks += self.span_list[prev_logical].block_len;
                first_ptr = self.span_list[prev_logical].mem_ptr;
                prev_logical = self.span_list[prev_logical].prev_logical;
            }
            return MemSpanLogical{
                .block_len = total_blocks,
                .mem_ptr = first_ptr,
            };
        }

        fn remove_span_from_its_linked_list(self: *Self, span_idx: T_IDX, comptime list: SpanState) void {
            self.SUPER_DEBUG_trace_open("remove_span_from_its_linked_list", prnt_inpt("span: {d}, list: {s}", .{ span_idx, @tagName(list) })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("remove_span_from_its_linked_list"); // DEBUG
            self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(span_idx, list); //DEBUG
            debug_assert(self.span_list[span_idx].state == list, DEBUG_ATTEMPT_TO_REMOVE_SPAN_NOT_PART_OF_LIST);
            const next_same_state = self.span_list[span_idx].next_same_state_ll;
            debug_assert(next_same_state == NO_IDX or next_same_state < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            if (next_same_state != NO_IDX) {
                self.span_list[next_same_state].prev_same_state_ll = self.span_list[span_idx].prev_same_state_ll;
            }
            const prev_same_state = self.span_list[span_idx].prev_same_state_ll;
            debug_assert(prev_same_state == NO_IDX or prev_same_state < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            if (prev_same_state != NO_IDX) {
                self.span_list[prev_same_state].next_same_state_ll = self.span_list[span_idx].next_same_state_ll;
            } else switch (list) {
                .ASSIGNED_FREE => {
                    debug_assert(self.first_free_span == span_idx, DEBUG_SPAN_WITH_NO_IDX_PREV_ISNT_FIRST_IN_LL);
                    self.first_free_span = self.span_list[span_idx].next_same_state_ll;
                },
                .ASSIGNED_USED => {
                    debug_assert(self.first_used_span == span_idx, DEBUG_SPAN_WITH_NO_IDX_PREV_ISNT_FIRST_IN_LL);
                    self.first_used_span = self.span_list[span_idx].next_same_state_ll;
                },
                .UNASSIGNED => {
                    debug_assert(self.first_unassigned_span == span_idx, DEBUG_SPAN_WITH_NO_IDX_PREV_ISNT_FIRST_IN_LL);
                    self.first_unassigned_span = self.span_list[span_idx].next_same_state_ll;
                },
                .NONE => unreachable,
            }
            self.span_list[span_idx].state = .NONE;
            self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(span_idx, .NONE); //DEBUG
            return;
        }

        fn add_span_to_begining_of_linked_list(self: *Self, span_idx: T_IDX, comptime list: SpanState) void {
            self.SUPER_DEBUG_trace_open("add_span_to_begining_of_linked_list", prnt_inpt("span: {d}, list: {s}", .{ span_idx, @tagName(list) })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("add_span_to_begining_of_linked_list"); // DEBUG
            debug_assert(span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span_idx].state != list, DEBUG_ATTEMPT_TO_ADD_SPAN_ALREADY_PART_OF_LIST);
            debug_assert(self.span_list[span_idx].state == .NONE, DEBUG_ATTEMPT_TO_ADD_SPAN_ALREADY_PART_OF_LIST);
            self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(span_idx, .NONE); //DEBUG

            self.span_list[span_idx].state = list;
            self.span_list[span_idx].prev_same_state_ll = NO_IDX;
            switch (list) {
                .ASSIGNED_FREE => {
                    self.span_list[span_idx].next_same_state_ll = self.first_free_span;
                    if (self.first_free_span != NO_IDX) {
                        self.span_list[self.first_free_span].prev_same_state_ll = span_idx;
                    }
                    self.first_free_span = span_idx;
                },
                .ASSIGNED_USED => {
                    self.span_list[span_idx].next_same_state_ll = self.first_used_span;
                    if (self.first_used_span != NO_IDX) {
                        self.span_list[self.first_used_span].prev_same_state_ll = span_idx;
                    }
                    self.first_used_span = span_idx;
                },
                .UNASSIGNED => {
                    self.span_list[span_idx].next_same_state_ll = self.first_unassigned_span;
                    if (self.first_unassigned_span != NO_IDX) {
                        self.span_list[self.first_unassigned_span].prev_same_state_ll = span_idx;
                    }
                    self.first_unassigned_span = span_idx;
                },
                .NONE => unreachable,
            }
            self.SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(span_idx, list); //DEBUG
        }

        fn assign_span_to_allocation(self: *Self, span: T_IDX, ptr: [*]u8, blocks: T_IDX) void {
            self.SUPER_DEBUG_trace_open("assign_span_to_allocation", prnt_inpt("span: {d}, blocks: {d}", .{ span, blocks })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("assign_span_to_allocation"); // DEBUG
            debug_assert(span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            self.span_list[span].block_len = blocks;
            self.span_list[span].mem_ptr = ptr;
            self.span_list[span].next_logical = NO_IDX;
            self.span_list[span].prev_logical = NO_IDX;
        }

        fn assign_span_to_next_logical(self: *Self, first_span: T_IDX, next_span: T_IDX, next_size: T_IDX) void {
            self.SUPER_DEBUG_trace_open("assign_span_to_next_logical", prnt_inpt("first_span: {d}, next_span: {d}, next_size: {d}", .{ first_span, next_span, next_size })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("assign_span_to_next_logical"); // DEBUG
            debug_assert(first_span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(next_span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            self.span_list[next_span].block_len = next_size;
            self.span_list[next_span].mem_ptr = self.span_list[first_span].mem_ptr + (@as(usize, self.span_list[first_span].block_len) << LOG2_OF_BLOCK_SIZE);
            self.span_list[next_span].next_logical = self.span_list[first_span].next_logical;
            self.span_list[next_span].prev_logical = first_span;
            self.span_list[first_span].next_logical = next_span;
            if (self.span_list[next_span].next_logical != NO_IDX) {
                const next_next_span = self.span_list[next_span].next_logical;
                debug_assert(next_next_span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                debug_assert(self.span_list[next_next_span].mem_ptr == self.span_list[next_span].mem_ptr + (@as(usize, self.span_list[next_span].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
                self.span_list[next_next_span].prev_logical = next_span;
            }
        }

        /// Locates the memory span that contains the base pointer of the slice. Assumes slice WAS allocated from this allocator
        /// AND is in the used span list AND has the same block-length as originally supplied, any other condition is considered
        /// a non-recoverable error (panic/unreachable)
        fn find_used_span_from_ptr(self: *Self, ptr: [*]u8, blocks: T_IDX) T_IDX {
            self.SUPER_DEBUG_trace_open("find_used_span_from_ptr_check_size", ""); // DEBUG
            defer self.SUPER_DEBUG_trace_close("find_used_span_from_ptr_check_size"); // DEBUG
            var curr_used_span = self.first_used_span;
            debug_assert(curr_used_span == NO_IDX or curr_used_span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            while (curr_used_span != NO_IDX) {
                debug_assert(curr_used_span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                if (self.span_list[curr_used_span].mem_ptr == ptr) {
                    user_assert(self.span_list[curr_used_span].block_len >= blocks, USER_ERROR_SUPPLIED_MEM_SLICE_LARGER_SIZE_THAN_ORIGINALLY_GIVEN);
                    return curr_used_span;
                }
                curr_used_span = self.span_list[curr_used_span].next_same_state_ll;
            }
            user_assert(false, USER_ERROR_SUPPLIED_MEM_SLICE_WASNT_ALLOCATED_FROM_THIS_ALLOCATOR);
        }

        /// Traverses free memory spans and locates a span that can hold the needed blocks. Splits over-large spans if needed,
        /// and grows spans in-place from backing allocator if possible and no existing free span was found. Returns
        /// `NO_IDX` if neither option worked
        fn try_claim_free_span(self: *Self, needed_blocks: T_IDX) T_IDX {
            self.SUPER_DEBUG_trace_open("try_claim_free_span", prnt_inpt("needed_blocks: {d}", .{needed_blocks})); // DEBUG
            defer self.SUPER_DEBUG_trace_close("try_claim_free_span"); // DEBUG
            debug_assert(needed_blocks > 0, DEBUG_ATTEMPT_TO_FIND_ZERO_BYTES);
            debug_assert(self.first_free_span == NO_IDX or self.first_free_span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            var curr_free_span_idx = self.first_free_span;
            while (curr_free_span_idx != NO_IDX) {
                debug_assert(curr_free_span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                if (self.span_list[curr_free_span_idx].block_len >= needed_blocks) {
                    if (self.span_list[curr_free_span_idx].block_len > needed_blocks) {
                        _ = self.split_free_span(curr_free_span_idx, needed_blocks);
                    }
                    self.remove_span_from_its_linked_list(curr_free_span_idx, .ASSIGNED_FREE);
                    self.add_span_to_begining_of_linked_list(curr_free_span_idx, .ASSIGNED_USED);
                    self.free_mem_blocks -= self.span_list[curr_free_span_idx].block_len;
                    self.SUPER_DEBUG_trace_extra("found existing free span"); //DEBUG
                    return curr_free_span_idx;
                }
                curr_free_span_idx = self.span_list[curr_free_span_idx].next_same_state_ll;
            }
            // Try to see if any of the existing free spans can be grown in place by the backing allocator
            curr_free_span_idx = self.first_free_span;
            while (curr_free_span_idx != NO_IDX) {
                debug_assert(curr_free_span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                const needed_grow_delta = needed_blocks - self.span_list[curr_free_span_idx].block_len;
                const did_grow_in_place = self.try_grow_free_in_place_backing_alloc(curr_free_span_idx, needed_grow_delta);
                if (did_grow_in_place) {
                    if (self.span_list[curr_free_span_idx].block_len > needed_blocks) {
                        _ = self.split_free_span(curr_free_span_idx, needed_blocks);
                    }
                    self.remove_span_from_its_linked_list(curr_free_span_idx, .ASSIGNED_FREE);
                    self.add_span_to_begining_of_linked_list(curr_free_span_idx, .ASSIGNED_USED);
                    self.free_mem_blocks -= self.span_list[curr_free_span_idx].block_len;
                    self.SUPER_DEBUG_trace_extra("grew free span IN-PLACE using backing allocator"); //DEBUG
                    return curr_free_span_idx;
                }
                curr_free_span_idx = self.span_list[curr_free_span_idx].next_same_state_ll;
            }
            self.SUPER_DEBUG_trace_extra("could not find free span"); //DEBUG
            return NO_IDX;
        }

        fn shrink_used_span(self: *Self, span_idx: T_IDX, new_size: T_IDX) Void_or_OptionalVoid {
            self.SUPER_DEBUG_trace_open("shrink_used_span", prnt_inpt("span_idx: {d}, new_size: {d}", .{ span_idx, new_size })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("shrink_used_span"); // DEBUG
            debug_assert(new_size > 0, DEBUG_SHRINK_USED_TO_ZERO_MEANS_FREE);
            debug_assert(self.span_list[span_idx].block_len >= new_size, DEBUG_SHRINK_ACTUALLY_SAME_OR_GROW);
            debug_assert(span_idx < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            const delta_blocks = self.span_list[span_idx].block_len - new_size;
            self.span_list[span_idx].block_len = new_size;
            if (self.span_list[span_idx].next_logical != NO_IDX) {
                const next_logical = self.span_list[span_idx].next_logical;
                debug_assert(next_logical < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                debug_assert(self.span_list[next_logical].mem_ptr == self.span_list[span_idx].mem_ptr + (@as(usize, self.span_list[span_idx].block_len) << LOG2_OF_BLOCK_SIZE), DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM);
                if (self.span_list[next_logical].state == .ASSIGNED_FREE) {
                    self.span_list[next_logical].block_len += delta_blocks;
                    self.free_mem_blocks += delta_blocks;
                    self.span_list[next_logical].mem_ptr -= (@as(usize, delta_blocks) << LOG2_OF_BLOCK_SIZE);
                    return;
                }
            }
            const new_span = if (ALLOC_ERROR == AllocErrorBehavior.RETURNS) (self.claim_unassigned_span() orelse return null) else self.claim_unassigned_span();
            self.assign_span_to_next_logical(span_idx, new_span, delta_blocks);
            self.free_mem_blocks += delta_blocks;
            return;
        }

        fn try_grow_used_in_place_this_alloc(self: *Self, span: T_IDX, grow_delta: T_IDX) bool {
            self.SUPER_DEBUG_trace_open("try_grow_used_in_place_this_alloc", prnt_inpt("span idx: {d}, grow_blocks: {d}", .{ span, grow_delta })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("try_grow_used_in_place_this_alloc"); // DEBUG
            debug_assert(span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span].state == .ASSIGNED_USED, DEBUG_GROW_FREE_SPAN_IN_HOUSE);
            const next = self.span_list[span].next_logical;
            if (next != NO_IDX) {
                debug_assert(next < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
                if (self.span_list[next].state == .ASSIGNED_FREE) {
                    debug_assert(self.span_list[next].block_len != 0, DEBUG_FOUND_FREE_OR_USED_SPAN_WITH_ZERO_BLOCKS);
                    if (self.span_list[next].block_len == grow_delta) {
                        const old_span = self.merge_next_logical_free_into_this_used_span(span);
                        self.add_span_to_begining_of_linked_list(old_span, .UNASSIGNED);
                        return true;
                    }
                    if (self.span_list[next].block_len > grow_delta) {
                        self.shift_blocks_from_next_logical_free_into_this_used_span(span, grow_delta);
                        return true;
                    }
                }
            }
            return false;
        }

        fn try_grow_free_in_place_backing_alloc(self: *Self, span: T_IDX, grow_delta: T_IDX) bool {
            self.SUPER_DEBUG_trace_open("try_grow_free_in_place_backing_alloc", prnt_inpt("span idx: {d}, grow_blocks: {d}", .{ span, grow_delta })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("try_grow_free_in_place_backing_alloc"); // DEBUG
            debug_assert(span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span].state == .ASSIGNED_FREE, DEBUG_GROW_FREE_FROM_BACKING_NOT_FREE);
            const next = self.span_list[span].next_logical;
            if (next == NO_IDX) {
                const entire_logical_span = self.collect_entire_logical_span_from_last(span);
                const old_total_bytes = blocks_to_bytes(entire_logical_span.block_len);
                const grow_delta_backing = align_blocks_to_backing_blocks(grow_delta);
                const grow_delta_backing_bytes = blocks_to_bytes(grow_delta_backing);
                if (self.backing_alloc.resize(entire_logical_span.mem_ptr[0..old_total_bytes], old_total_bytes + grow_delta_backing_bytes)) {
                    self.span_list[span].block_len += grow_delta_backing;
                    self.free_mem_blocks += grow_delta_backing;
                    self.total_mem_blocks += grow_delta_backing;
                    return true;
                }
            }
            return false;
        }

        fn try_grow_used_in_place_backing_alloc(self: *Self, span: T_IDX, grow_delta: T_IDX) bool {
            self.SUPER_DEBUG_trace_open("try_grow_used_in_place_backing_alloc", prnt_inpt("span idx: {d}, grow_blocks: {d}", .{ span, grow_delta })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("try_grow_used_in_place_backing_alloc"); // DEBUG
            debug_assert(span < self.span_list_len, DEBUG_IDX_OUT_OF_RANGE);
            debug_assert(self.span_list[span].state == .ASSIGNED_USED, DEBUG_GROW_USED_FROM_BACKING_NOT_USED);
            const next = self.span_list[span].next_logical;
            if (next == NO_IDX) {
                const entire_logical_span = self.collect_entire_logical_span_from_last(span);
                const old_total_bytes = blocks_to_bytes(entire_logical_span.block_len);
                const grow_delta_backing = align_blocks_to_backing_blocks(grow_delta);
                const grow_delta_backing_bytes = blocks_to_bytes(grow_delta_backing);
                if (self.backing_alloc.resize(entire_logical_span.mem_ptr[0..old_total_bytes], old_total_bytes + grow_delta_backing_bytes)) {
                    self.total_mem_blocks += grow_delta_backing;
                    self.span_list[span].block_len += grow_delta;
                    if (grow_delta_backing > grow_delta) {
                        const new_span = self.claim_unassigned_span();
                        const extra_free_blocks = grow_delta_backing - grow_delta;
                        self.assign_span_to_next_logical(span, new_span, extra_free_blocks);
                        self.add_span_to_begining_of_linked_list(new_span, .ASSIGNED_FREE);
                        self.free_mem_blocks += extra_free_blocks;
                    }
                    return true;
                }
            }
            return false;
        }

        fn raw_alloc_ptr_only(self_opaque: *anyopaque, bytes: usize, log2_of_align: u8, ret_addr: usize) ?[*]u8 {
            return if (Self.raw_alloc(self_opaque, bytes, log2_of_align, ret_addr)) |slice| slice.ptr else null;
        }

        fn raw_alloc(self_opaque: *anyopaque, bytes: usize, log2_of_align: u8, ret_addr: usize) ?[]u8 {
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            self.SUPER_DEBUG_trace_open("raw_alloc", prnt_inpt("blocks = {d}", .{bytes_to_blocks(bytes)})); // DEBUG
            defer self.SUPER_DEBUG_trace_close("raw_alloc"); // DEBUG
            const blocks = bytes_to_blocks(bytes);
            user_assert(bytes > 0, USER_ERROR_REQUESTED_ALLOCATE_ZERO_BYTES);
            user_assert(self.total_mem_blocks + blocks <= math.maxInt(T_IDX), USER_ERROR_REQUESTED_ALLOCATION_GREATER_THAN_MAX_POSSIBLE);
            user_assert(log2_of_align <= LOG2_OF_BLOCK_SIZE, USER_ERROR_REQUESTED_ALIGNMENT_GREATER_THAN_BLOCK_SIZE);
            const existing_free_span = self.try_claim_free_span(blocks);
            if (existing_free_span != NO_IDX) {
                const real_bytes = blocks_to_bytes(blocks);
                return self.span_list[existing_free_span].mem_ptr[0..real_bytes];
            }
            const new_alloc_span_idx = if (ALLOC_ERROR == AllocErrorBehavior.RETURNS) self.claim_unassigned_span() orelse return null else self.claim_unassigned_span();
            const backing_blocks = align_blocks_to_backing_blocks(blocks);
            const backing_bytes = blocks_to_bytes(backing_blocks);
            user_assert(self.total_mem_blocks + backing_blocks <= std.math.maxInt(T_IDX), USER_ERROR_REQUESTED_ALLOCATION_GREATER_THAN_MAX_POSSIBLE);
            const new_alloc_ptr = self.backing_alloc.rawAlloc(backing_bytes, LOG2_OF_BLOCK_SIZE, 0) orelse switch (ALLOC_ERROR) {
                .RETURNS => {
                    self.add_span_to_begining_of_linked_list(new_alloc_span_idx, .UNASSIGNED);
                    return null;
                },
                .PANICS => @panic("PooledBlockAllocator's backing allocator failed to allocate additional memory"),
                .UNREACHABLE => unreachable,
            };
            self.total_mem_blocks += backing_blocks;
            self.free_mem_blocks += backing_blocks;
            self.assign_span_to_allocation(new_alloc_span_idx, new_alloc_ptr, backing_blocks);
            self.add_span_to_begining_of_linked_list(new_alloc_span_idx, .ASSIGNED_FREE);
            const new_split_free_span = self.try_claim_free_span(blocks);
            debug_assert(new_split_free_span != NO_IDX and new_split_free_span < self.span_list_len, DEBUG_SHOULD_HAVE_HAD_GUARANTEED_FREE_SPAN);
            const real_bytes = blocks_to_bytes(blocks);
            return self.span_list[new_split_free_span].mem_ptr[0..real_bytes];
        }

        fn raw_resize_bool_only(self_opaque: *anyopaque, slice: []u8, log2_of_align: u8, new_size: usize, ret_addr: usize) bool {
            return Self.raw_resize(self_opaque, slice, log2_of_align, new_size, ret_addr) != null;
        }

        fn raw_resize(self_opaque: *anyopaque, slice: []u8, log2_of_align: u8, new_size: usize, ret_addr: usize) ?usize {
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            self.SUPER_DEBUG_trace_open("raw_resize", prnt_inpt("old_blocks = {d}, new_blocks = {d}", .{ bytes_to_blocks(slice.len), bytes_to_blocks(new_size) })); // DEBUG
            defer self.SUPER_DEBUG_trace_close("raw_resize"); // DEBUG
            const old_blocks = bytes_to_blocks(slice.len);
            const new_blocks = bytes_to_blocks(new_size);
            user_assert(new_size > 0, USER_ERROR_REQUESTED_RESIZE_ZERO_BYTES);
            user_assert(log2_of_align <= LOG2_OF_BLOCK_SIZE, USER_ERROR_REQUESTED_ALIGNMENT_GREATER_THAN_BLOCK_SIZE);
            if (!mem.isAlignedLog2(@intFromPtr(slice.ptr), log2_of_align)) return null;
            if (new_blocks == old_blocks) {
                if (should_user_assert()) {
                    _ = self.find_used_span_from_ptr(slice.ptr, old_blocks);
                }
                return blocks_to_bytes(new_blocks);
            }
            const mem_span = self.find_used_span_from_ptr(slice.ptr, old_blocks);
            if (new_blocks < old_blocks) {
                self.shrink_used_span(mem_span, new_blocks);
                return blocks_to_bytes(new_blocks);
            }
            const grow_delta = new_blocks - self.span_list[mem_span].block_len;
            if (self.try_grow_used_in_place_this_alloc(mem_span, grow_delta)) {
                return blocks_to_bytes(new_blocks);
            }
            if (self.try_grow_used_in_place_backing_alloc(mem_span, grow_delta)) {
                return blocks_to_bytes(new_blocks);
            }
            return null;
        }

        fn raw_free(self_opaque: *anyopaque, slice: []u8, log2_of_align: u8, ret_addr: usize) void {
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            self.SUPER_DEBUG_trace_open("raw_free", ""); // DEBUG
            defer self.SUPER_DEBUG_trace_close("raw_free"); // DEBUG
            user_assert(slice.len > 0, USER_ERROR_SUPPLIED_MEM_SLICE_LARGER_SIZE_THAN_ORIGINALLY_GIVEN);
            user_assert(log2_of_align <= LOG2_OF_BLOCK_SIZE, USER_ERROR_REQUESTED_ALIGNMENT_GREATER_THAN_BLOCK_SIZE);
            const slice_blocks = bytes_to_blocks(slice.len);
            const mem_span = self.find_used_span_from_ptr(slice.ptr, slice_blocks);
            self.free_used_span(mem_span, true);
            return;
        }

        fn SUPER_DEBUG_trace_open(self: *const Self, func: []const u8, inputs: []const u8) void { //DEBUG
            _ = self;
            if (!DEBUG_STACK_TRACE) return;
            stack_depth += 1;
            const indent = indent_depth(stack_depth);
            // std.debug.print(
            //     \\
            //     \\{0s}╔══ [{1d}] : {2s} ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
            //     \\{0s}╟─(INPUTS)─
            //     \\{0s}║{11s}
            //     \\{0s}╟─(BEFORE)─
            //     \\{0s}║span_list_idx   = {3d}
            //     \\{0s}║span_list_len   = {4d}
            //     \\{0s}║span_list_cap   = {5d}
            //     \\{0s}║first_free_span = {6d}
            //     \\{0s}║first_used_span = {7d}
            //     \\{0s}║first_unas_span = {8d}
            //     \\{0s}║total_mem_blocks= {9d}
            //     \\{0s}║free_mem_blocks = {10d}
            //     \\{0s}║
            // , .{
            //     indent,
            //     BLOCK_SIZE,
            //     func,
            //     self.span_list_idx,
            //     self.span_list_len,
            //     self.span_list_cap,
            //     self.first_free_span,
            //     self.first_used_span,
            //     self.first_unassigned_span,
            //     self.total_mem_blocks,
            //     self.free_mem_blocks,
            //     inputs,
            // });
            std.debug.print(
                \\
                \\{0s}╔══ [{1d}] : {2s} ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
                \\{0s}╟─(INPUTS)─
                \\{0s}║{3s}
                \\{0s}╟─(BEFORE)─
                \\{0s}║
            , .{
                indent,
                BLOCK_SIZE,
                func,
                inputs,
            });
            // const span_1_prev = if (self.span_list_len > 1) self.span_list[1].prev_same_state_ll else 1;
            // std.debug.print(
            //     \\
            //     \\{0s}╔══ [{1d}] : {2s} ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
            //     \\{0s}╟─(INPUTS)─
            //     \\{0s}║{3s}
            //     \\{0s}╟─(BEFORE)─
            //     \\{0s}║span #1 prev ll = {4d}{5s}
            //     \\{0s}║first_free_span = {6d}
            //     \\{0s}║
            // , .{
            //     indent,
            //     BLOCK_SIZE,
            //     func,
            //     inputs,
            //     span_1_prev,
            //     if (self.span_list_len <= 1) "_doesnt_exist" else "",
            //     self.first_free_span,
            // });
        }

        fn SUPER_DEBUG_trace_extra(self: *const Self, msg: []const u8) void { //DEBUG
            _ = self;
            if (!DEBUG_STACK_TRACE) return;
            std.debug.print(
                \\
                \\{0s}╟─(EXTRA)─
                \\{0s}║{1s}
                \\{0s}║
            , .{ indent_depth(stack_depth), msg });
        }

        fn SUPER_DEBUG_trace_close(self: *const Self, func: []const u8) void { //DEBUG
            _ = self;
            if (!DEBUG_STACK_TRACE) return;
            // std.debug.print(
            //     \\
            //     \\{0s}╟─(AFTER)─
            //     \\{0s}║span_list_idx   = {1d}
            //     \\{0s}║span_list_len   = {2d}
            //     \\{0s}║span_list_cap   = {3d}
            //     \\{0s}║first_free_span = {4d}
            //     \\{0s}║first_used_span = {5d}
            //     \\{0s}║first_unas_span = {6d}
            //     \\{0s}║total_mem_blocks= {7d}
            //     \\{0s}║free_mem_blocks = {8d}
            //     \\{0s}╚══ [{9d}] : {10s} ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
            // , .{
            //     indent_depth(stack_depth),
            //     self.span_list_idx,
            //     self.span_list_len,
            //     self.span_list_cap,
            //     self.first_free_span,
            //     self.first_used_span,
            //     self.first_unassigned_span,
            //     self.total_mem_blocks,
            //     self.free_mem_blocks,
            //     BLOCK_SIZE,
            //     func,
            // });
            std.debug.print(
                \\
                \\{0s}╟─(AFTER)─
                \\{0s}╚══ [{1d}] : {2s} ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
            , .{
                indent_depth(stack_depth),
                BLOCK_SIZE,
                func,
            });
            // const span_1_prev = if (self.span_list_len > 1) self.span_list[1].prev_same_state_ll else 1;
            // std.debug.print(
            //     \\
            //     \\{0s}╟─(AFTER)─
            //     \\{0s}║span #1 prev ll = {1d}{2s}
            //     \\{0s}║first_free_span = {3d}
            //     \\{0s}╚══ [{4d}] : {5s} ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
            // , .{
            //     indent_depth(stack_depth),
            //     span_1_prev,
            //     if (self.span_list_len <= 1) "_doesnt_exist" else "",
            //     self.first_free_span,
            //     BLOCK_SIZE,
            //     func,
            // });
            stack_depth -= 1;
        }

        fn SUPER_DEBUG_assert_idx_in_exactly_one_list_exactly_one_time(self: *Self, idx: T_IDX, comptime list: SpanState) void {
            if (builtin.mode == .Debug) {
                var error_builder = std.ArrayList(u8).init(std.heap.page_allocator);
                const PRINT_LL = true;
                const invert_first_logic = list == .NONE;
                var should_match = switch (list) {
                    .ASSIGNED_FREE => self.first_free_span,
                    .ASSIGNED_USED => self.first_used_span,
                    .UNASSIGNED => self.first_unassigned_span,
                    else => self.first_free_span,
                };
                var good_match: u8 = 0;
                var bad_match_c: u8 = 0;
                if (PRINT_LL) std.fmt.format(error_builder.writer(), "\n{s} List: ", .{@tagName(list)}) catch unreachable;
                while (should_match != NO_IDX) {
                    if (PRINT_LL) std.fmt.format(error_builder.writer(), "{d}({c}) -> ", .{ should_match, state_char(self.span_list[should_match].state) }) catch unreachable;
                    if (invert_first_logic) {
                        if (should_match == idx) {
                            bad_match_c += 1;
                            if (bad_match_c == 2) break;
                        }
                    } else {
                        if (should_match == idx) {
                            good_match += 1;
                            if (good_match == 2) break;
                        }
                    }
                    should_match = self.span_list[should_match].next_same_state_ll;
                }
                const other_lists: struct { a: T_IDX, b: T_IDX, an: []const u8, bn: []const u8 } = switch (list) {
                    .ASSIGNED_FREE => .{ .a = self.first_used_span, .b = self.first_unassigned_span, .an = @tagName(SpanState.ASSIGNED_USED), .bn = @tagName(SpanState.UNASSIGNED) },
                    .ASSIGNED_USED => .{ .a = self.first_free_span, .b = self.first_unassigned_span, .an = @tagName(SpanState.ASSIGNED_FREE), .bn = @tagName(SpanState.UNASSIGNED) },
                    .UNASSIGNED => .{ .a = self.first_free_span, .b = self.first_used_span, .an = @tagName(SpanState.ASSIGNED_FREE), .bn = @tagName(SpanState.ASSIGNED_USED) },
                    .NONE => .{ .a = self.first_used_span, .b = self.first_unassigned_span, .an = @tagName(SpanState.ASSIGNED_USED), .bn = @tagName(SpanState.UNASSIGNED) },
                };
                var bad_match_a: u8 = 0;
                if (PRINT_LL) std.fmt.format(error_builder.writer(), "\n{s} List: ", .{other_lists.an}) catch unreachable;
                var should_not_match = other_lists.a;
                while (should_not_match != NO_IDX) {
                    if (PRINT_LL) std.fmt.format(error_builder.writer(), "{d}({c}) -> ", .{ should_not_match, state_char(self.span_list[should_not_match].state) }) catch unreachable;
                    if (should_not_match == idx) {
                        bad_match_a += 1;
                        if (bad_match_a == 2) break;
                    }
                    should_not_match = self.span_list[should_not_match].next_same_state_ll;
                }
                var bad_match_b: u8 = 0;
                if (PRINT_LL) std.fmt.format(error_builder.writer(), "\n{s} List: ", .{other_lists.bn}) catch unreachable;
                should_not_match = other_lists.b;
                while (should_not_match != NO_IDX) {
                    if (PRINT_LL) std.fmt.format(error_builder.writer(), "{d}({c}) -> ", .{ should_not_match, state_char(self.span_list[should_not_match].state) }) catch unreachable;
                    if (should_not_match == idx) {
                        bad_match_b += 1;
                        if (bad_match_b == 2) break;
                    }
                    should_not_match = self.span_list[should_not_match].next_same_state_ll;
                }
                var has_error = false;
                if (idx >= self.span_list_len) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("idx is out of span_list_len range (len = ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{d})", .{self.span_list_len}) catch unreachable;
                }
                if (self.span_list[idx].state != list) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("state does not match expected (found ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s})", .{@tagName(self.span_list[idx].state)}) catch unreachable;
                }
                if (!invert_first_logic and good_match == 0) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("was not found in the expected list: ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{@tagName(list)}) catch unreachable;
                } else if (!invert_first_logic and good_match > 1) {
                    has_error = true;
                    error_builder.appendSlice("\nIdx ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{d} ", .{idx}) catch unreachable;
                    error_builder.appendSlice("was found in the expected list MULTIPLE TIMES! (cyclic list): ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{@tagName(list)}) catch unreachable;
                }
                if (bad_match_a > 0) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("was found in an UNEXPECTED list: ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{other_lists.an}) catch unreachable;
                }
                if (bad_match_a > 1) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("was found in an UNEXPECTED list MULTIPLE TIMES! (cyclic list): ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{other_lists.an}) catch unreachable;
                }
                if (bad_match_b > 0) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("was found in an UNEXPECTED list: ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{other_lists.bn}) catch unreachable;
                }
                if (bad_match_b > 1) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("was found in an UNEXPECTED list MULTIPLE TIMES! (cyclic list): ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{other_lists.bn}) catch unreachable;
                }
                if (bad_match_c > 0) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("was found in an UNEXPECTED list: ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{other_lists.bn}) catch unreachable;
                }
                if (bad_match_c > 1) {
                    has_error = true;
                    error_builder.appendSlice("\nCheck Idx==List ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "({d}=={s}) ", .{ idx, @tagName(list) }) catch unreachable;
                    error_builder.appendSlice("was found in an UNEXPECTED list MULTIPLE TIMES! (cyclic list): ") catch unreachable;
                    std.fmt.format(error_builder.writer(), "{s}", .{other_lists.bn}) catch unreachable;
                }
                if (has_error) {
                    @panic(error_builder.items);
                }
            }
        }
    };
}

/// Asserts internally expected behavior and allocator state, panics with info message in `debug` mode,
/// considered `unreachable` in other modes.
inline fn debug_assert(condition: bool, msg: []const u8) void {
    if (builtin.mode == .Debug) {
        if (!condition) @panic(msg);
    } else {
        if (!condition) unreachable;
    }
}

// Implementation Error messages
const DEBUG_ATTEMPT_TO_FIND_ZERO_BYTES = "PooledBlockAllocator tried to find a 0-byte memory segment";
const DEBUG_ATTEMPT_TO_SPLIT_SPAN_ONE_WITH_ZERO_BLOCKS = "PooledBlockAllocator attempted to split a MemSpan where one would have zero size";
const DEBUG_ATTEMPT_TO_SPLIT_SPAN_NOT_FREE = "PooledBlockAllocator attempted to split a MemSpan that was not in the .ASSIGNED_FREE state";
const DEBUG_ATTEMPT_TO_FREE_NON_USED_SPAN = "PooledBlockAllocator attempted to free a MemSpan that was not in the .ASSIGNED_USED state";
const DEBUG_IDX_OUT_OF_RANGE = "PooledBlockAllocator tried to find a MemSpan at an index greater than or equal to self.span_list_len";
const DEBUG_SPAN_WITH_NO_IDX_PREV_ISNT_FIRST_IN_LL = "PooledBlockAllocator found a linked-list member with a .prev_state_ll == NO_IDX, but its idx didnt match .first_free_span (broken linked list)";
const DEBUG_EXPANDING_SPAN_POOL_MADE_CAP_LESS_THAN_LEN = "PooledBlockAllocator reallocated the span pool, but the reult was a .span_pool_cap < .span_pool_len";
const DEBUG_LOGICAL_ADJACENT_SPANS_HAVE_DISJOINT_MEM = "PooledBlockAllocator tried to merge free adjacent logical spans, but the mem pointers they held were disjointed";
const DEBUG_NEXT_LOGICAL_FREE_NOT_ENOUGH_BLOCKS_TO_TAKE = "PooledBlockAllocator tried to take blocks from the next logical FREE span, but that span didnt have enough free blocks to take";
const DEBUG_ATTEMPT_TO_REMOVE_SPAN_NOT_PART_OF_LIST = "PooledBlockAllocator tried to remove a MemSpan from a list it wasn't a member of";
const DEBUG_SPAN_NOT_IN_ITS_EXPECTED_LIST = "PooledBlockAllocator found a span that should have been in the same linked list as its marked state, but wasnt";
const DEBUG_SPAN_IN_UNEXPECTED_LIST = "PooledBlockAllocator found a span that should not have been found in a list it wasn't a part of";
const DEBUG_SPAN_STATE_DOESNT_MATCH_LIST = "PooledBlockAllocator found a span in the correct linked list, but whose state didnt match that list";
const DEBUG_SPAN_IN_ITS_LIST_MULTIPLE_TIMES = "PooledBlockAllocator found a span that was in its linked list more than once, creating a cyclic list";
const DEBUG_ATTEMPT_TO_ADD_SPAN_ALREADY_PART_OF_LIST = "PooledBlockAllocator tried to add a MemSpan to a list it was already a member of";
const DEBUG_COLLECT_LOGICAL_FROM_END_SPAN_WASNT_LAST = "PooledBlockAllocator tried to 'collect entire logical span starting from last span', but was supplied a span that wasnt the last logical span";
const DEBUG_FOUND_FREE_OR_USED_SPAN_WITH_ZERO_BLOCKS = "PooledBlockAllocator found a free or used MemSpan that had .block_len == 0";
const DEBUG_SHOULD_HAVE_HAD_GUARANTEED_FREE_SPAN = "PooledBlockAllocator just allocated a new span for request, but .try_claim_free_span() returned NO_IDX";
const DEBUG_SHRINK_USED_TO_ZERO_MEANS_FREE = "PooledBlockAllocator just tried to 'shrink' a used block to zero bytes... just free it if this is correct";
const DEBUG_SHRINK_ACTUALLY_SAME_OR_GROW = "PooledBlockAllocator just tried to 'shrink' a used block to an equal or larger block size";
const DEBUG_GROW_FREE_SPAN_IN_HOUSE = "PooledBlockAllocator just tried to grow a free span in house, but all free spans should already be fully grown to their max in-house size";
const DEBUG_NO_CAP_TO_ADD_MEMSPAN = "PooledBlockAllocator just tried to push another MemSpan to the ensd of the list when .span_pool_len >= .span_pool_cap";
const DEBUG_GROW_FREE_FROM_BACKING_NOT_FREE = "PooledBlockAllocator just tried to grow a 'free' span in place from the backing allocator, but it wasnt in 'free' state";
const DEBUG_GROW_USED_FROM_BACKING_NOT_USED = "PooledBlockAllocator just tried to grow a 'used' span in place from the backing allocator, but it wasnt in 'used' state";
const DEBUG_RELEASE_NON_FREE_SPAN = "PooledBlockAllocator just tried to release a non-free span to the backing allocator or OS";
const DEBUG_NEXT_LOGICAL_PREV_LOGICAL_DOESNT_MATCH = "PooledBlockAllocator found a span with .next_logical span that had a .prev_logical field that didnt match the current span idx";
const DEBUG_NEXT_LOGICAL_FREE_ISNT_FREE = "PooledBlockAllocator tried to take blocks from a .next_logical span that was supposed to be free, but it wasn't free";
const DEBUG_SPAN_WASNT_IN_USED_STATE = "PooledBlockAllocator tried to perform an operation that expected the span_idx to be in the USED state, but it wasn't";
// User Error messages
const USER_ERROR_SUPPLIED_MEM_SLICE_WASNT_ALLOCATED_FROM_THIS_ALLOCATOR = "the memory slice ([]u8) supplied to this PooledBlockAllocator to free, resize, or reallocate does not exist in this allocator";
const USER_ERROR_SUPPLIED_MEM_SLICE_LARGER_SIZE_THAN_ORIGINALLY_GIVEN = "the memory slice ([]u8) supplied to this PooledBlockAllocator to free, resize, or reallocate has a larger block-size than was last handed out";
const USER_ERROR_REQUESTED_ALLOCATE_ZERO_BYTES = "you cannot 'allocate' zero bytes of memory, if you just need an aligned pointer use `std.mem.alignBackward(usize, std.math.maxInt(usize), alignment);`";
const USER_ERROR_REQUESTED_ALIGNMENT_GREATER_THAN_BLOCK_SIZE = "PooledBlockAllocator does not support alignments greater than the value of Config.block_size it was built with";
const USER_ERROR_REQUESTED_ALLOCATION_GREATER_THAN_MAX_POSSIBLE = "requested allocation bytes would cause PooledBlockAllocator to exceed its maximum total (Config.block_size * std.math.maxInt(Config.index_type))";
const USER_ERROR_REQUESTED_RESIZE_ZERO_BYTES = "cannot 'resize' an allocation to 0 bytes, use Allocator.free() or Allocator.destroy() instead";
const USER_ERROR_RELEASED_USED_MEMORY = "PooledBlockAllocator.release_all_memory() reported that some of the memory released was still in-use";

//DEBUG
var stack_depth: usize = 0;
const indent_const = "║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ";
var ibuf: [100]u8 = undefined;
var llbuf: [1000]u8 = undefined;
fn indent_depth(depth: usize) []const u8 {
    return indent_const[0..(depth * 5)];
}
fn prnt_inpt(comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(&ibuf, fmt, args) catch unreachable;
}
const DEBUG_STACK_TRACE = false;

fn state_char(state: SpanState) u8 {
    if (state == .ASSIGNED_FREE) return 'F';
    if (state == .ASSIGNED_USED) return 'U';
    if (state == .UNASSIGNED) return 'X';
    return '_';
}
