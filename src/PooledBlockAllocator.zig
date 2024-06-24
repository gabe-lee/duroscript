const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocError = std.mem.Allocator.Error;
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;

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
/// - DEBUG
/// - RELEASE_SAFE
/// - RELEASE_SMALL
/// - RELEASE_FAST
/// - ALWAYS
pub const SafetyChecksPanic = enum(u8) {
    /// Never panic with message on failed safety checks
    NEVER = 0,
    /// Only panic with message on failed safety checks in `debug` modes
    DUBUG = 1,
    /// (Default)
    ///
    /// Only panic with message on failed safety checks in `debug` and `release_safe` modes
    RELEASE_SAFE = 2,
    /// Only panic with message on failed safety checks in `debug`, `release_safe`, and `release_small` modes
    RELEASE_SMALL = 3,
    /// Only panic with message on failed safety checks in `debug`, `release_safe`, `release_small`, and `release_fast` mode
    RELEASE_FAST = 4,
    /// Always panic with message on failed safety checks regardless of compile mode
    ALWAYS = 5,
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

/// Configuration options for generating a PooledBlockAllocator
pub const Config = struct {
    /// How large each memory block is in bytes
    ///
    /// DEFAULT = `1024`
    ///
    /// MUST adhere to the following rules:
    /// - is a power of 2
    /// - block_size >= @max(@alignOf(usize), @alignOf(config.index_type))
    block_size: usize = 1024,
    /// When requesting new memory from the backing allocator, needed bytes will be rounded
    /// up to a multiple of this number.
    ///
    /// DEFAULT = `std.mem.page_size`
    ///
    /// MUST adhere to the following rules:
    /// - is a power of 2
    /// - backing_request_size >= block_size
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
    /// the remaining memory is unusable. You could instead set this to std.mem.page_size
    /// to ensure you always get the full page back to use
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
    /// Specifies in what levels of compiler optimization safety checks are inserted as `@panic(msg)` or `unreachable`
    ///
    /// DEFAULT = `.RELEASE_SAFE`
    ///
    /// The compiler cannot optimize out the safety checks in this or any 'less optimized' mode, but give better
    /// feedback on failures in those modes
    safety_checks_panic: SafetyChecksPanic = SafetyChecksPanic.RELEASE_SAFE,
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
};

/// Enum to signal whether a block is free, used, newly-allocated (not in free OR used list), or invalid (released to backing allocator/OS)
const BlockState = enum(u2) {
    /// MemBlock has been newly allocated and has not been added to either `free` or `used` linked list
    NEW,
    /// MemBlock is in the `free` state
    FREE,
    /// MemBlock is in the `used` state
    USED,
    /// MemBlock memory has been released back to the backing allocator or OS. Used to find internal allocator errors
    INVALID,
};

const MAX_ALIGN = std.mem.page_size;
const LOG2_OF_MAX_ALIGN = math.log2_int(comptime_int, MAX_ALIGN);

/// Defines a new PooledBlockAllocator type that uses the provided `Config` struct to build all the necessary constants and safety checks
/// for this allocator.
pub fn PooledBlockAllocator(comptime config: Config) type {
    if (!math.isPowerOfTwo(config.block_size)) @compileError("Config.block_size MUST be a power of 2 (1, 2, 4, 8, 16, ... , 1024, 2048, 4096, ... etc)");
    if (!math.isPowerOfTwo(config.backing_request_size)) @compileError("Config.backing_request_size MUST be a power of 2 (1, 2, 4, 8, 16, ... , 1024, 2048, 4096, ... etc)");
    if (config.block_size < @max(@alignOf(usize), @alignOf(config.index_type))) @compileError("Config.block_size MUST be >= @max(@alignOf(usize), @alignOf(config.index_type))");
    if (config.backing_request_size < config.block_size) @compileError("Config.backing_request_size MUST be >= Config.block_size");
    if (config.index_type != u64 or config.index_type != u32 or config.index_type != u16 or config.index_type != u8 or config.index_type != usize)
        @compileError("Config.index_type MUST be one of the following types: u8, u16, u32, u64, usize");
    return struct {
        const Self = @This();
        const BLOCK_SIZE = config.block_size;
        const LOG2_OF_BLOCK_SIZE = math.log2_int(comptime_int, BLOCK_SIZE);
        const BACKING_SIZE = config.backing_request_size;
        const LOG2_OF_BACKING_SIZE = math.log2_int(comptime_int, BACKING_SIZE);
        const BLOCK_BACKING_RATIO = BACKING_SIZE / BLOCK_SIZE;
        const LOG2_OF_BLOCK_BACKING_RATIO = LOG2_OF_BACKING_SIZE - LOG2_OF_BLOCK_SIZE;
        const WIPE_ON_FREE = config.secure_wipe_freed_memory;
        const SAFETY_PANIC = config.safety_checks_panic;
        const ALLOC_ERROR = config.alloc_error_behavior;
        const WIPE_MEM_BYTE = if (builtin.mode == .Debug) 0xAA else 0x00;
        const T_IDX: type = config.index_type;
        const MAX_TOTAL_ALLOC_BYTES = (1 << @typeInfo(T_IDX).Int.bits) * BLOCK_SIZE;
        const NO_IDX = std.math.maxInt(T_IDX);

        /// Represents a chunk of `Config.block_size` bytes of memory
        const MemBlock = struct {
            /// Pointer to real memory address this MemBlock represents
            ptr: [*]u8,
            /// Index of next MemBlock in the free/used linked list (which list is determined by `state`)
            next: T_IDX,
            /// Index of previous MemBlock in the free/used linked list (which list is determined by `state`)
            prev: T_IDX,
            /// How many MemBlocks in contiguous indexes after this one that also point to contiguous real memory pointers
            contiguous_after: T_IDX,
            /// How many MemBlocks in contiguous indexes before this one that also point to contiguous real memory pointers
            contiguous_before: T_IDX,
            /// How many MemBlocks in contiguous indexes after this one that have the same state as this one and are also
            /// in contiguous real memory
            same_state_after: T_IDX,
            /// Whether the block is free, used, newly-allocated (not in free OR used list), or invalid (released to backing allocator/OS)
            state: BlockState,
            /// The largest log2 value of alignment this chunk can be used to allocate (real align = `1 << largest_align_power`)
            log2_of_largest_align: u8,
        };

        /// A span of contiguous MemBlocks that all point to contiguous real memory
        ///
        /// Includes a bool describing whether the span was actually located by the allocator,
        /// and a convenience pointer that is the same one as stored in the first MemBlock in the span
        const MemSpan = struct {
            found: bool,
            block_idx: T_IDX,
            block_len: T_IDX,
            mem_ptr: [*]u8,

            fn not_found() MemSpan {
                return MemSpan{
                    .found = false,
                    .block_idx = 0,
                    .block_len = 0,
                    .mem_ptr = @bitCast(std.math.maxInt(usize)),
                };
            }

            fn found(idx: T_IDX, len: T_IDX, ptr: [*]u8) MemSpan {
                return MemSpan{
                    .found = true,
                    .block_idx = idx,
                    .block_len = len,
                    .ptr = ptr,
                };
            }
        };

        /// The backing allocator used to request memory from
        backing_alloc: Allocator,
        /// A pointer to the portion of allocated MemBlocks that holds the internal book-keeping portion of the allocator
        pool_ptr: [*]MemBlock,
        /// The index of the MemBlock that holds the internal book-keeping portion of the allocator
        pool_idx: T_IDX,
        /// How many MemBlocks currently exist in total in this allocator
        pool_len: T_IDX,
        /// How many total MemBlocks can be held in the internal book-keeping memory before book-keeping span must be re-allocated
        pool_cap: T_IDX,
        /// Index of the first free MemBlock in a linked-list of all free MemBlocks
        first_free: T_IDX,
        /// Index of the first used MemBlock in a linked-list of all used MemBlocks
        first_used: T_IDX,
        /// Total number of bytes allocated from the backing allocator
        total_mem: usize,
        /// Total number of bytes currently free
        free_mem: usize,

        /// Makes safety-checked assertions based on the `Config.safety_checks_panic` setting
        ///
        /// This function is used to safety check values that can be input by the user of this allocator,
        /// for behavior that should be asserted based on internally expected behavior should use `debug_assert()` instead
        inline fn user_assert(condition: bool, msg: []const u8) void {
            switch (SAFETY_PANIC) {
                .NEVER => if (!condition) unreachable,
                .DUBUG => if (builtin.mode == .Debug) {
                    if (!condition) @panic(msg);
                } else if (!condition) unreachable,
                .RELEASE_SAFE => if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                    if (!condition) @panic(msg);
                } else if (!condition) unreachable,
                .RELEASE_SMALL => if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe or builtin.mode == .ReleaseSmall) {
                    if (!condition) @panic(msg);
                } else if (!condition) unreachable,
                .RELEASE_FAST => if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe or builtin.mode == .ReleaseSmall or builtin.mode == .ReleaseFast) {
                    if (!condition) @panic(msg);
                } else if (!condition) unreachable,
                .ALWAYS => if (!condition) @panic(msg),
            }
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

        inline fn bytes_to_backing_blocks(bytes: usize) T_IDX {
            return @intCast(std.mem.alignForward(usize, bytes, BACKING_SIZE) >> LOG2_OF_BACKING_SIZE);
        }

        inline fn backing_blocks_to_bytes(backing_blocks: T_IDX) usize {
            return @as(usize, @intCast(backing_blocks)) << LOG2_OF_BACKING_SIZE;
        }

        inline fn blocks_to_backing_blocks(blocks: T_IDX) T_IDX {
            if (BACKING_SIZE == BLOCK_SIZE) {
                return blocks;
            } else return std.mem.alignForward(T_IDX, blocks, BLOCK_BACKING_RATIO) >> LOG2_OF_BLOCK_BACKING_RATIO;
        }

        inline fn backing_blocks_to_blocks(backing_blocks: T_IDX) T_IDX {
            if (BACKING_SIZE == BLOCK_SIZE) {
                return backing_blocks;
            } else return backing_blocks << LOG2_OF_BLOCK_BACKING_RATIO;
        }

        inline fn clear_mem_if_needed(mem_slice: []u8) void {
            if (WIPE_ON_FREE) {
                @memset(@as([]volatile u8, mem_slice), WIPE_MEM_BYTE);
            } else @memset(mem, undefined);
        }

        pub fn new() Self {
            var self = Self{
                .pool = undefined,
                .first_free = NO_IDX,
                .first_used = NO_IDX,
            };
            //FIXME fix this
            const list_ptr: [*]u8 = Self.raw_alloc(&self, BLOCK_SIZE, BLOCK_SIZE, 0) orelse unreachable;
            self.pool_capacity = BLOCK_SIZE / @sizeOf(MemBlock);
            self.pool.items.len = 0;
            self.pool.items.ptr = @ptrCast(@alignCast(list_ptr));
        }

        /// Returns an `Allocator` interface struct for this allocator
        pub fn allocator(self: *Self) Allocator {
            return Allocator{
                .ptr = self,
                .vtable = &Allocator.VTable{
                    .alloc = raw_alloc,
                    .resize = raw_resize,
                    .free = raw_free,
                },
            };
        }

        /// Traverses free memory blocks and locates a segment of free contiguous memory that can hold
        /// the needed bytes with the needed alignment
        fn try_find_free_span_with_align(self: *Self, needed_blocks: T_IDX, log2_of_align: u8) MemSpan {
            debug_assert(needed_blocks > 0, DEBUG_FIND_ZERO_BYTES_MSG);
            debug_assert(log2_of_align <= LOG2_OF_MAX_ALIGN, DEBUG_OVER_MAX_ALIGN_MSG);
            debug_assert(self.first_free == NO_IDX or self.first_free < self.pool_len, DEBUG_FOUND_IDX_MORE_THAN_LEN_NOT_NOT_IDX);
            if (self.first_free != NO_IDX) {
                var curr_free_idx = self.first_free;
                var curr_free_mem_block = self.pool_ptr[curr_free_idx];
                debug_assert(curr_free_mem_block.state == .FREE, DEBUG_NON_FREE_IN_FREE_LIST);
                while (true) {
                    const larger_align = @max(log2_of_align, curr_free_mem_block.log2_of_largest_align);
                    const align_offset_shift = (larger_align - curr_free_mem_block.log2_of_largest_align);
                    const align_offset = (1 << align_offset_shift) - 1;
                    if (curr_free_mem_block.same_state_after >= align_offset + needed_blocks - 1) {
                        debug_assert(curr_free_idx + align_offset + needed_blocks <= self.pool_len, DEBUG_FOUND_IDX_MORE_THAN_LEN);
                        debug_assert(mem.isAlignedLog2(@intFromPtr(self.pool_ptr[curr_free_idx + align_offset].ptr), log2_of_align), DEBUG_FAILED_ALIGNMENT_MATH);
                        if (builtin.mode == .Debug) {
                            var expected_ptr = curr_free_mem_block.ptr + (align_offset * BLOCK_SIZE);
                            for (curr_free_idx + align_offset..curr_free_idx + align_offset + needed_blocks) |idx| {
                                const block = self.pool_ptr[idx];
                                debug_assert(block.ptr == expected_ptr, DEBUG_BLOCK_PTR_DOESNT_MATCH_EXPECTED_PTR);
                                debug_assert(block.state != .INVALID, DEBUG_ATTEMPTED_OPERATION_ON_INVALID_BLOCKS);
                                debug_assert(block.state == .FREE, DEBUG_NON_FREE_IN_SAME_STATE_FREE_RANGE);
                                expected_ptr += BLOCK_SIZE;
                            }
                        }
                        const found_idx = curr_free_idx + align_offset;
                        return MemSpan.found(found_idx, needed_blocks, self.pool_ptr[found_idx].ptr);
                    }
                    // TODO try to see if free zone is at end of real allocation and backing allocator can resize in place
                    debug_assert(curr_free_mem_block.next == NO_IDX or curr_free_mem_block.next < self.pool_len, DEBUG_FOUND_IDX_MORE_THAN_LEN_NOT_NOT_IDX);
                    if (curr_free_mem_block.next >= self.pool_len or curr_free_mem_block.next == NO_IDX) break;
                    curr_free_idx = curr_free_mem_block.next;
                    curr_free_mem_block = self.pool_ptr[curr_free_idx];
                }
            }
            return MemSpan.not_found();
        }

        // /// Traverses allocated free memory blocks and locates a segment of free contiguous memory at the end
        // /// of an allocation block that the backing allocator can resize in place to hold the needed bytes.
        // /// Returns a struct with the start index and length of the mem blocks, as well as
        // /// a boolean signaling if the search was sucessful. Does not commit to marking the memory blocks as used.
        // fn try_find_free_span_that_can_resize(self: *Self, needed_bytes: usize) MemSpan {
        //     debug_assert(needed_bytes > 0);
        //     if (self.first_free != NO_IDX) {
        //         const needed_bytes_aligned = std.mem.alignForward(usize, needed_bytes, BLOCK_SIZE);
        //         const contiguous_blocks_required: T_IDX = @intCast(needed_bytes_aligned >> LOG2_OF_BLOCK_SIZE);
        //         var curr_free_idx = self.first_free;
        //         var curr_free_mem_block = self.pool_ptr[curr_free_idx];
        //         while (true) {
        //             const found_mem = self.try_find_contiguous_free_blocks_offset_from_base_idx(curr_free_idx, 0, contiguous_blocks_required);
        //             if (found_mem.found) return found_mem;
        //             if (curr_free_mem_block.next >= self.pool_len or curr_free_mem_block.next == NO_IDX) break;
        //             curr_free_idx = curr_free_mem_block.next;
        //             curr_free_mem_block = self.pool_ptr[curr_free_idx];
        //         }
        //     }
        //     return MemSpan.not_found();
        // }

        // /// Using `base_idx` to find the root ptr, starts at `offset_idx` and tries to find `needed_offset_blocks`
        // /// consecutive free memory blocks with base pointers contiguous with the root ptr. Returns `Memory`
        // /// that represents only the range `offset_idx`=>`offset_idx + needed_offset_blocks`
        // fn try_find_contiguous_free_blocks_offset_from_base_idx(self: *Self, base_idx: T_IDX, offset_count: T_IDX, needed_offset_blocks: T_IDX) MemSpan {
        //     debug_assert(needed_offset_blocks > 0, DEBUG_FIND_ZERO_BYTES_MSG);
        //     debug_assert(base_idx + offset_count + needed_offset_blocks <= self.pool_len, DEBUG_FOUND_IDX_MORE_THAN_LEN);
        //     debug_assert(condition: bool, msg: []const u8)
        //     const first_idx = base_idx + offset_count;
        //     const last_off = offset_count + needed_offset_blocks - 1;
        //     if (self.pool_ptr[base_idx].contiguous_after < last_off) return MemSpan.not_found();
        //     const base_ptr = self.pool_ptr[base_idx].ptr;
        //     var curr_idx = base_idx + last_off;
        //     var curr_ptr = base_ptr + (last_off * BLOCK_SIZE);
        //     while (true) {
        //         const block = self.pool_ptr[curr_idx];
        //         if (block.state != .FREE or (block.ptr != curr_ptr)) return MemSpan.not_found();
        //         if (curr_idx == first_idx) break;
        //         curr_idx -= 1;
        //         curr_ptr -= BLOCK_SIZE;
        //     }
        //     return MemSpan.found(first_idx, needed_offset_blocks, curr_ptr);
        // }

        /// Locates the memory block that contains the base pointer and
        /// collects the memory block count containing at least `slice.len` bytes
        fn find_used_blocks_from_slice(self: *Self, slice: []u8) MemSpan {
            debug_assert(slice.len > 0, DEBUG_FIND_ZERO_BYTES_MSG);
            var next_used_idx = self.first_used;
            while (next_used_idx != NO_IDX) {
                if (self.pool_ptr[next_used_idx].ptr == slice.ptr) return self.find_used_blocks_from_idx(next_used_idx, slice.len);
                next_used_idx = self.pool_ptr[next_used_idx].next;
            }
            // assert ptr was found in used pool
            //TODO make this an optional panic
            unreachable;
        }

        /// Collects memory blocks starting from `idx` and containing at least `byte_len` bytes
        fn find_used_blocks_from_idx(self: *Self, start_idx: T_IDX, byte_len: usize) MemSpan {
            debug_assert(byte_len > 0, DEBUG_FIND_ZERO_BYTES_MSG);
            const block_len: T_IDX = bytes_to_blocks(byte_len);
            debug_assert(start_idx + block_len <= self.pool_len, DEBUG_FOUND_IDX_MORE_THAN_LEN);
            if (builtin.mode == .Debug) {
                var expected_ptr = self.pool_ptr[start_idx].ptr;
                for (start_idx..start_idx + block_len) |idx| {
                    const block = self.pool_ptr[idx];
                    debug_assert(block.ptr == expected_ptr, DEBUG_BLOCK_PTR_DOESNT_MATCH_EXPECTED_PTR);
                    debug_assert(block.state != .INVALID, DEBUG_ATTEMPTED_OPERATION_ON_INVALID_BLOCKS);
                    debug_assert(block.state == .USED, DEBUG_NON_USED_IN_SAME_STATE_USED_RANGE);
                    expected_ptr += BLOCK_SIZE;
                }
            }
            return MemSpan{ .found = true, .block_idx = start_idx, .block_len = block_len, .mem_ptr = self.pool_ptr[start_idx].ptr };
        }

        /// Marks all memory blocks in this range as either free or used, and updates all linked-list indexes
        fn mark_mem_blocks(self: *Self, mem_span: MemSpan, state: BlockState) void {
            debug_assert(mem_span.block_len > 0, DEBUG_FIND_ZERO_BYTES_MSG);
            debug_assert(mem_span.found == true, DEBUG_OPERATE_ON_NOT_FOUND_SPAN);
            debug_assert(mem_span.block_idx + mem_span.block_len <= self.pool_len, DEBUG_FOUND_IDX_MORE_THAN_LEN);
            if (builtin.mode == .Debug) {
                var expected_ptr = mem_span.ptr;
                for (mem_span.block_idx..mem_span.block_idx + mem_span.block_len) |idx| {
                    const block = self.pool_ptr[idx];
                    debug_assert(block.ptr == expected_ptr, DEBUG_BLOCK_PTR_DOESNT_MATCH_EXPECTED_PTR);
                    debug_assert(block.state != .INVALID, DEBUG_ATTEMPTED_OPERATION_ON_INVALID_BLOCKS);
                    debug_assert(block.state != state, DEBUG_MARK_MEM_BLOCKS_WITH_SAME_STATE);
                    expected_ptr += BLOCK_SIZE;
                }
            }
            //CHECKPOINT finish optimizing mark_mem_blocks to only add the first block of a segment of same-state blocks to the
            // relevant linked list and update existing segments with new same_state_after values
            const first_idx = mem_span.block_idx;
            const idx_after_last = mem_span.block_idx + mem_span.block_len;
            const last_idx = idx_after_last - 1;
            var first_block = &self.pool_ptr[first_idx];
            var last_block = &self.pool_ptr[last_idx];
            first_block.prev = NO_IDX;
            for (first_idx..last_idx) |idx| {
                self.pool_ptr[idx].state = state;
                self.pool_ptr[idx].next = idx + 1;
                self.pool_ptr[idx + 1].prev = idx;
            }
            last_block.state = state;
            if (state) {
                last_block.next = self.first_free;
                self.first_free = first_idx;
            } else {
                last_block.next = self.first_used;
                self.first_used = first_idx;
            }
        }

        /// Allocates additional memory using the backing allocator and returns a slice to represent it.
        ///
        /// If memory allocation fails, the Config.alloc_error_behavior determines how to respond
        fn allocate_new_memory(self: *Self, bytes: usize) AllocError![]u8 {
            const aligned_bytes = std.mem.alignForward(usize, bytes, BACKING_SIZE);
            const byte_ptr: [*]u8 = self.backing_alloc.rawAlloc(aligned_bytes, BLOCK_ALIGN, 0) orelse switch (ALLOC_ERROR) {
                .RETURNS => return AllocError.OutOfMemory,
                .PANICS => @panic("PooledBlockAllocator's backing allocator failed to allocate additional memory"),
                .UNREACHABLE => unreachable,
            };
            return byte_ptr[0..aligned_bytes];
        }

        fn resize_pool_for_additional_blocks(self: *Self, additional_pool_len: T_IDX) AllocError!void {
            // Return if pool already has enough capacity
            if (self.pool_cap >= self.pool_len + additional_pool_len) return;
            const new_data_len: usize = @as(usize, @intCast(self.pool_len + additional_pool_len)) * @sizeOf(MemBlock);
            const new_data_blocks: T_IDX = bytes_to_blocks(new_data_len);
            const old_data_cap_len = self.pool_cap * @sizeOf(MemBlock);
            const old_mem: MemSpan = self.find_used_blocks_from_idx(self.pool_idx, old_data_cap_len);
            const old_data_total_len = blocks_to_bytes(old_mem.block_len);
            const delta_blocks = new_data_blocks - old_mem.block_len;
            // Try to just extend the existing MemBlocks if they are followed by enough contiguous free MemBlocks
            var new_mem: MemSpan = self.try_find_contiguous_free_blocks_offset_from_base_idx(old_mem.block_idx, old_mem.block_len, delta_blocks);
            if (new_mem.found) {
                self.mark_mem_blocks(new_mem, .USED);
                const total_new_blocks = old_mem.block_len + new_mem.block_len;
                const total_new_bytes = @as(usize, total_new_blocks) << LOG2_OF_BLOCK_SIZE;
                const new_cap = @as(T_IDX, total_new_bytes / @sizeOf(MemBlock));
                self.pool_cap = new_cap;
                debug_assert(self.pool_cap >= self.pool_len + additional_pool_len);
                return;
            }
            // Try to find another segment of contiguous free MemBlocks that can hold the new needed pool len
            const old_data_len = self.pool_len * @sizeOf(MemBlock);
            new_mem = self.try_find_free_span_with_align(new_data_len);
            if (new_mem.found) {
                @memcpy(new_mem.mem_ptr[0..old_data_len], old_mem.mem_ptr[0..old_data_len]);
                if (WIPE_ON_FREE) @memset(old_mem.mem_ptr[0..old_data_total_len], WIPE_MEM_BYTE);
                self.pool_idx = new_mem.block_idx;
                self.pool_ptr = @ptrCast(@alignCast(new_mem.mem_ptr));
                const new_cap = blocks_to_bytes(new_mem.block_len) / @sizeOf(MemBlock);
                self.pool_cap = new_cap;
                self.mark_mem_blocks(old_mem, .FREE);
                self.mark_mem_blocks(new_mem, .USED);
                debug_assert(self.pool_cap >= self.pool_len + additional_pool_len);
                return;
            }
            // Try to see if the backing allocator can resize in place
            const resize_request = backing_blocks_to_bytes(bytes_to_backing_blocks(new_data_len));
            if (self.backing_alloc.rawResize(old_mem.mem_ptr[0..old_data_total_len], BLOCK_ALIGN, resize_request, 0)) {
                const resize_cap = @as(T_IDX, resize_request / @sizeOf(MemBlock));
                self.pool_cap = resize_cap;
                return;
            }
            // Allocate a brand new memory segment entirely to hold the new pool len
            var predict_alloc_backing_multiple = bytes_to_backing_blocks(new_data_len);
            var predict_alloc_blocks = backing_blocks_to_blocks(predict_alloc_backing_multiple);
            var predict_alloc_bytes: usize = @as(usize, @intCast(self.pool_len + predict_alloc_blocks)) * @sizeOf(MemBlock);
            var real_alloc_backing_multiple = bytes_to_backing_blocks(predict_alloc_bytes);
            // VERIFY There may be a way to compute this without a while loop
            while (real_alloc_backing_multiple != predict_alloc_backing_multiple) {
                predict_alloc_backing_multiple += 1;
                predict_alloc_blocks = backing_blocks_to_blocks(predict_alloc_backing_multiple);
                predict_alloc_bytes = @as(usize, @intCast(self.pool_len + predict_alloc_blocks)) * @sizeOf(MemBlock);
                real_alloc_backing_multiple = bytes_to_backing_blocks(predict_alloc_bytes);
            }
            const real_alloc_bytes = backing_blocks_to_bytes(real_alloc_backing_multiple);
            const real_alloc_blocks = backing_blocks_to_blocks(real_alloc_backing_multiple);
            const real_alloc_pool_blocks = bytes_to_blocks(@as(usize, @intCast(self.pool_len + real_alloc_blocks)) * @sizeOf(MemBlock));
            debug_assert(real_alloc_blocks >= real_alloc_pool_blocks);
            const real_alloc_extra_blocks = real_alloc_blocks - real_alloc_pool_blocks;
            const real_alloc_pool_bytes = blocks_to_bytes(real_alloc_pool_blocks);
            const new_alloc_slice = try self.allocate_new_memory(real_alloc_bytes);
            @memcpy(new_alloc_slice.ptr, old_mem.mem_ptr[0..old_data_len]);
            Self.clear_mem_if_needed(old_mem.mem_ptr[0..old_data_total_len]);
            self.mark_mem_blocks(old_mem, .FREE);
            self.pool_cap = @intCast(real_alloc_pool_bytes / @sizeOf(MemBlock));
            self.pool_ptr = @ptrCast(@alignCast(new_alloc_slice.ptr));
            self.pool_idx = self.pool_len;
            self.pool_len += real_alloc_blocks;
            debug_assert(self.pool_cap >= self.pool_len + additional_pool_len);
            var block_ptr: [*]u8 = new_alloc_slice.ptr;
            for (self.pool_idx..self.pool_idx + real_alloc_blocks) |idx| {
                self.pool_ptr[idx] = MemBlock.brand_new(block_ptr);
                block_ptr += BLOCK_SIZE;
            }
            const uninit_used_blocks = MemSpan.found(self.pool_idx, real_alloc_pool_blocks, new_alloc_slice.ptr);
            const uninit_free_blocks = MemSpan.found(self.pool_idx + real_alloc_pool_blocks, real_alloc_extra_blocks, new_alloc_slice.ptr + (real_alloc_pool_blocks * BLOCK_SIZE));
            self.mark_mem_blocks(uninit_used_blocks, .USED);
            self.mark_mem_blocks(uninit_free_blocks, .FREE);
            return;
        }

        fn raw_alloc(self_opaque: *anyopaque, bytes: usize, log2_of_align: u8, ret_addr: usize) ?[*]u8 {
            _ = ret_addr;
            const real_align = 1 << log2_of_align;
            if (bytes == 0) return @ptrFromInt(std.mem.alignBackward(usize, std.math.maxInt(usize), real_align));
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            // Try to find free memory span
            const free_span = self.try_find_free_span_with_align(bytes);
            if (free_span.found) {
                self.mark_mem_blocks(free_span, .USED);
                return free_span.mem_ptr;
            }
            //CHECKPOINT fix this, maybe also extract functionality from resize_pool()
            //FIXME
            if (self.first_free != NO_IDX) {
                var curr_free_mem_block: *MemBlock = &self.pool.items[self.first_free];
                var prev_next_free_idx_ref: *usize = &self.first_free;
                while (true) {
                    if (curr_free_mem_block.slice.len >= bytes) {
                        prev_next_free_idx_ref.* = curr_free_mem_block.next;
                        curr_free_mem_block.next = NO_IDX;
                        return curr_free_mem_block.slice.ptr;
                    }
                    if (curr_free_mem_block.next == NO_IDX) break;
                    prev_next_free_idx_ref = &curr_free_mem_block.next;
                    curr_free_mem_block = &self.pool.items[curr_free_mem_block.next];
                }
            }
            if (self.pool_capacity - self.pool.items.len < BLOCKS_PER_PAGE) {}
            const paged_bytes = std.mem.alignForward(usize, bytes, PAGE_SIZE);
            const page_ptr = self.ba.rawAlloc(paged_bytes, PAGE_SIZE, 0) orelse return null;
            const new_chunks_array: PAGE_CHUNK_PTR_ARRAY = undefined;
            for (0..BLOCKS_PER_PAGE) |i| {}
            //TODO Optimize for platforms with larger page sizes by chopping the returned page into separate
            // MemBlock chunks and appending them all as new free pointers
            const new_slice = page_ptr[0..paged_bytes];
            self.pool.append(page_allocator, MemBlock{
                .slice = new_slice,
                .is_free = false,
            }) catch return null;
            return page_ptr;
        }

        fn raw_resize(self_opaque: *anyopaque, slice: []u8, log2_of_align: u8, new_size: usize, ret_addr: usize) bool {
            _ = ret_addr;
            user_assert(log2_of_align <= BLOCK_SIZE);
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            for (self.pool.items) |mem_block| {
                if (mem_block.slice.ptr == slice.ptr and mem_block.slice.len >= new_size) return true;
            }
            return false;
        }

        fn raw_free(self_opaque: *anyopaque, slice: []u8, log2_of_align: u8, ret_addr: usize) void {
            _ = ret_addr;
            user_assert(log2_of_align <= BLOCK_SIZE);
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            for (self.pool.items) |*mem_block| {
                if (mem_block.slice.ptr == slice.ptr) {
                    mem_block.is_free = true;
                    return;
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

const DEBUG_FIND_ZERO_BYTES_MSG = "PooledBlockAllocator tried to find a 0-byte memory segment";
const DEBUG_OVER_MAX_ALIGN_MSG = "PooledBlockAllocator tried to find an allocation alignment greater than std.mem.page_size";
const DEBUG_FOUND_IDX_MORE_THAN_LEN_NOT_NOT_IDX = "PooledBlockAllocator found an index in its linked list that is greater than self.len but not the NOT_IDX value";
const DEBUG_NON_FREE_IN_FREE_LIST = "PooledBlockAllocator found an non-free MemBlock in the 'free' linked list";
const DEBUG_FAILED_ALIGNMENT_MATH = "PooledBlockAllocator tried to calculate an alignment but failed";
const DEBUG_FOUND_IDX_MORE_THAN_LEN = "PooledBlockAllocator tried to find a MemBlock at an index greater than or equal to self.pool_len";
const DEBUG_BLOCK_PTR_DOESNT_MATCH_EXPECTED_PTR = "PooledBlockAllocator expected address contiguous with a base pointer offset by some amount, found disjointed address";
const DEBUG_NON_FREE_IN_SAME_STATE_FREE_RANGE = "PooledBlockAllocator expected all blocks in range of block.same_state_after(free) to be free, found non-free block";
const DEBUG_NON_USED_IN_SAME_STATE_USED_RANGE = "PooledBlockAllocator expected all blocks in range of block.same_state_after(used) to be used, found non-used block";
const DEBUG_OPERATE_ON_NOT_FOUND_SPAN = "PooledBlockAllocator tried to perform an operation using a MemSpan that had value `found == false`";
const DEBUG_MARK_MEM_BLOCKS_WITH_SAME_STATE = "PooledBlockAllocator tried to mark memory blocks with the identical free/used state as already present on the block";
const DEBUG_ATTEMPTED_OPERATION_ON_INVALID_BLOCKS = "PooledBlockAllocator tried to preform an operation on memory blocks marked 'invalid'";
