const std = @import("std");
const debug_assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const AllocError = std.mem.Allocator.Error;
const builtin = @import("builtin");

const NO_IDX: u32 = std.math.maxInt(u32);

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
    /// - block_size >= @max(@alignOf(usize), @alignOf(u32))
    block_size: usize = 1024,
    /// When requesting new memory from the backing allocator, needed bytes will be rounded
    /// up to a multiple of this number.
    ///
    /// DEFAULT = `1024`
    ///
    /// MUST adhere to the following rules:
    /// - is a power of 2
    /// - backing_request_multiple >= block_size
    ///
    /// This can be used to speculatively allocate additional memory for future allocations,
    /// thereby reducing the number of calls to the backing allocator,
    /// and also to prevent the backing allocator from wasting bytes when you ask for a number of
    /// bytes that is smaller than the smallest size of memory region that allocator
    /// can allocate
    ///
    /// For example, when using the `std.mem.page_allocator` as a backing allocator, if
    /// you ask for a 1024 byte block of memory, it returns a slice of 1024 bytes, but in reality
    /// it allocated an entire page of system memory anywhere from 4096 to 64k bytes, and all
    /// the remaining memory is unusable. You could instead set this to std.mem.page_size
    /// to ensure you always get the full page back to use
    ///
    /// (The backing allocator SHOULD know how to resize in place, but this setting allows the
    /// PooledBlockAllocator to be agnostic of that behavior)
    ///
    /// Setting this equal to `block_size` effectively disables any speculative allocation
    /// or potential efficiency gains.
    backing_request_multiple: usize = 1024,
    /// Determines whether or not freed memory is explicitly overwritten with dummy bytes before
    /// being returned to the backing allocator or OS. Takes a bit of additional processing,
    /// but is recomended for sensitive data applications
    ///
    /// DEFAULT = `false`
    ///
    /// The exact byte written to memory is determined by the compiler mode:
    /// - Debug = `0xAA` to adhere to the conventions expected by `Debug` mode
    /// - (Others) `0x00`
    ///
    /// Note that in Debug mode, even if this is set to false the allocator will still
    /// perform `@memset(_, undefined)` on the freed memory (this behavior is optimized away
    /// by the comipler in more optimized modes)
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
};

const BlockState = enum(u2) {
    NEW,
    FREE,
    USED,
    INVALID,
};

const MemBlockExtra = packed struct {
    contiguous_before: u31,
    contiguous_after: u31,
    state: BlockState,
};

const MemBlock = struct {
    ptr: [*]u8,
    next: u32,
    prev: u32,
    extra: MemBlockExtra,

    fn brand_new(ptr: [*]u8, contiguous_before: u31, contiguous_after: u31) MemBlock {
        return MemBlock{
            .ptr = ptr,
            .prev = NO_IDX,
            .next = NO_IDX,
            .extra = MemBlockExtra{
                .state = .NEW,
                .contiguous_after = contiguous_after,
                .contiguous_before = contiguous_before,
            },
        };
    }
};

const MemSpan = struct {
    found: bool,
    block_idx: u32,
    block_len: u32,
    mem_ptr: [*]u8,

    fn not_found() MemSpan {
        return MemSpan{
            .found = false,
            .block_idx = 0,
            .block_len = 0,
            .mem_ptr = @bitCast(std.math.maxInt(usize)),
        };
    }

    fn found(idx: u32, len: u32, ptr: [*]u8) MemSpan {
        return MemSpan{
            .found = true,
            .block_idx = idx,
            .block_len = len,
            .ptr = ptr,
        };
    }
};

const Pool = struct {
    ptr: [*]MemBlock,
    own_idx: u32,
    len: u32,
    cap: u32,

    inline fn has_capacity_for(self: *Pool, additional_blocks: usize) bool {
        return (self.cap - self.len) >= additional_blocks;
    }
};

pub fn PooledChunkAllocator(comptime config: Config) type {
    const shift = @ctz(config.block_size);
    if (config.block_size == 0 or config.block_size >> shift != 1) @compileError("Config.block_size MUST be a power of 2 (4, 8, 16, ... , 1024, 2048, 4096, ... etc)");
    if (config.block_size < @alignOf(MemBlock)) @compileError("Config.block_size MUST be >= @max(@alignOf(usize), @alignOf(u32))");
    if (config.backing_request_multiple < config.block_size) @compileError("Config.backing_request_multiple MUST be >= Config.block_size");
    return struct {
        const Self = @This();
        const BLOCK_SIZE = config.block_size;
        const BLOCK_SIZE_SHIFT = shift;
        const BLOCK_ALIGN = @min(BACKING_SIZE, BLOCK_SIZE);
        const BACKING_SIZE = config.backing_request_multiple;
        const BACKING_SIZE_SHIFT = @ctz(BACKING_SIZE);
        const BLOCK_BACKING_RATIO = if (BACKING_SIZE > BLOCK_SIZE) BACKING_SIZE / BLOCK_SIZE else 1;
        const BLOCK_BACKING_SHIFT = if (BACKING_SIZE > BLOCK_SIZE) BACKING_SIZE_SHIFT - BLOCK_SIZE_SHIFT else 0;
        const WIPE_ON_FREE = config.secure_wipe_freed_memory;
        const SAFETY_PANIC = config.safety_checks_panic;
        const ALLOC_ERROR = config.alloc_error_behavior;
        const WIPE_MEM_BYTE = if (builtin.mode == .Debug) 0xAA else 0x00;
        const LARGEST_ALLOC_REQUEST = std.mem.alignBackward(usize, std.math.maxInt(u31) * BLOCK_SIZE, BACKING_SIZE);
        const MAX_TOTAL_ALLOC = (1 << 32) * BLOCK_SIZE;

        backing_alloc: Allocator,
        pool: Pool,
        first_free: u32,
        first_used: u32,
        total_mem: usize,
        free_mem: usize,

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

        inline fn bytes_to_blocks(bytes: usize) u32 {
            return @intCast(std.mem.alignForward(usize, bytes, BLOCK_SIZE) >> BLOCK_SIZE_SHIFT);
        }

        inline fn blocks_to_bytes(blocks: u32) usize {
            return @as(usize, @intCast(blocks)) << BLOCK_SIZE_SHIFT;
        }

        inline fn bytes_to_backing_blocks(bytes: usize) u32 {
            return @intCast(std.mem.alignForward(usize, bytes, BACKING_SIZE) >> BACKING_SIZE_SHIFT);
        }

        inline fn backing_blocks_to_bytes(backing_blocks: u32) usize {
            return @as(usize, @intCast(backing_blocks)) << BACKING_SIZE_SHIFT;
        }

        inline fn blocks_to_backing_blocks(blocks: u32) u32 {
            if (BACKING_SIZE == BLOCK_SIZE) {
                return blocks;
            } else return std.mem.alignForward(u32, blocks, BLOCK_BACKING_RATIO) >> BLOCK_BACKING_SHIFT;
        }

        inline fn backing_blocks_to_blocks(backing_blocks: u32) u32 {
            if (BACKING_SIZE == BLOCK_SIZE) {
                return backing_blocks;
            } else return backing_blocks << BLOCK_BACKING_SHIFT;
        }

        inline fn clear_mem_if_needed(mem: []u8) void {
            if (WIPE_ON_FREE) {
                @memset(@as([]volatile u8, mem), WIPE_MEM_BYTE);
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
            self.pool.capacity = BLOCK_SIZE / @sizeOf(MemBlock);
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

        /// Traverses allocated free memory blocks and locates a segment of free contiguous memory that can hold
        /// the needed bytes. Returns a struct with the start index and length of the mem blocks, as well as
        /// a boolean signaling if the search was sucessful. Does not commit to marking the memory blocks as used.
        fn try_find_free_span(self: *Self, needed_bytes: usize) MemSpan {
            debug_assert(needed_bytes > 0);
            if (self.first_free != NO_IDX) {
                const needed_bytes_aligned = std.mem.alignForward(usize, needed_bytes, BLOCK_SIZE);
                const contiguous_blocks_required: u32 = @intCast(needed_bytes_aligned >> BLOCK_SIZE_SHIFT);
                var curr_free_idx = self.first_free;
                var curr_free_mem_block = self.pool.ptr[curr_free_idx];
                while (true) {
                    const found_mem = self.try_find_contiguous_free_blocks_offset_from_base_idx(curr_free_idx, 0, contiguous_blocks_required);
                    if (found_mem.found) return found_mem;
                    if (curr_free_mem_block.next >= self.pool.len or curr_free_mem_block.next == NO_IDX) break;
                    curr_free_idx = curr_free_mem_block.next;
                    curr_free_mem_block = self.pool.ptr[curr_free_idx];
                }
            }
            return MemSpan.not_found();
        }

        /// Traverses allocated free memory blocks and locates a segment of free contiguous memory at the end
        /// of an allocation block that the backing allocator can resize in place to hold the needed bytes.
        /// Returns a struct with the start index and length of the mem blocks, as well as
        /// a boolean signaling if the search was sucessful. Does not commit to marking the memory blocks as used.
        fn try_find_free_span_that_can_resize(self: *Self, needed_bytes: usize) MemSpan {
            debug_assert(needed_bytes > 0);
            if (self.first_free != NO_IDX) {
                const needed_bytes_aligned = std.mem.alignForward(usize, needed_bytes, BLOCK_SIZE);
                const contiguous_blocks_required: u32 = @intCast(needed_bytes_aligned >> BLOCK_SIZE_SHIFT);
                var curr_free_idx = self.first_free;
                var curr_free_mem_block = self.pool.ptr[curr_free_idx];
                while (true) {
                    const found_mem = self.try_find_contiguous_free_blocks_offset_from_base_idx(curr_free_idx, 0, contiguous_blocks_required);
                    if (found_mem.found) return found_mem;
                    if (curr_free_mem_block.next >= self.pool.len or curr_free_mem_block.next == NO_IDX) break;
                    curr_free_idx = curr_free_mem_block.next;
                    curr_free_mem_block = self.pool.ptr[curr_free_idx];
                }
            }
            return MemSpan.not_found();
        }

        /// Using `base_idx` to find the root ptr, starts at `offset_idx` and tries to find `needed_offset_blocks`
        /// consecutive free memory blocks with base pointers contiguous with the root ptr. Returns `Memory`
        /// that represents only the range `offset_idx`=>`offset_idx + needed_offset_blocks`
        fn try_find_contiguous_free_blocks_offset_from_base_idx(self: *Self, base_idx: u32, offset_count: u32, needed_offset_blocks: u32) MemSpan {
            debug_assert(needed_offset_blocks > 0);
            const first_idx = base_idx + offset_count;
            if (first_idx + needed_offset_blocks > self.pool.len) return MemSpan.not_found();
            const last_off = offset_count + needed_offset_blocks - 1;
            if (self.pool.ptr[base_idx].contiguous_after < last_off) return MemSpan.not_found();
            const base_ptr = self.pool.ptr[base_idx].ptr;
            var curr_idx = base_idx + last_off;
            var curr_ptr = base_ptr + (last_off * BLOCK_SIZE);
            while (true) {
                const block = self.pool.ptr[curr_idx];
                if (block.state != .FREE or (block.ptr != curr_ptr)) return MemSpan.not_found();
                if (curr_idx == first_idx) break;
                curr_idx -= 1;
                curr_ptr -= BLOCK_SIZE;
            }
            return MemSpan.found(first_idx, needed_offset_blocks, curr_ptr);
        }

        /// Locates the memory block that contains the base pointer and
        /// collects the memory block count containing at least `slice.len` bytes
        fn find_used_blocks_from_slice(self: *Self, slice: []u8) MemSpan {
            var next_used_idx = self.first_used;
            while (next_used_idx != NO_IDX) {
                if (self.pool.ptr[next_used_idx].ptr == slice.ptr) return self.find_used_blocks_from_idx(next_used_idx, slice.len);
                next_used_idx = self.pool.ptr[next_used_idx].next;
            }
            // assert ptr was found in used pool
            //TODO make this an optional panic
            unreachable;
        }

        /// Collects memory blocks starting from `idx` and containing at least `byte_len` bytes
        ///
        /// opt_asserts (Debug/Release Safe):
        /// - `byte_len` > 0
        /// - All contiguous memory block indexes starting from `idx` required for `byte_len` are within pool range
        /// - All contiguous memory blocks are currently in the `used` state
        /// - All contiguous memory blocks have contiguous base memory pointers
        fn find_used_blocks_from_idx(self: *Self, idx: u32, byte_len: usize) MemSpan {
            debug_assert(byte_len > 0);
            const block_len: u32 = @intCast(std.mem.alignForward(usize, byte_len, BLOCK_SIZE) >> BLOCK_SIZE_SHIFT);
            debug_assert(idx + block_len <= self.pool.len);
            const base_ptr = self.pool.ptr[idx].ptr;
            debug_assert(compute: {
                for (0..block_len) |i| {
                    const n_idx = idx + i;
                    if (self.pool.ptr[n_idx].state == .FREE) break :compute false;
                    if (self.pool.ptr[n_idx].ptr != base_ptr + (i * BLOCK_SIZE)) break :compute false;
                }
                break :compute true;
            });
            return MemSpan{ .found = true, .block_idx = idx, .block_len = block_len, .mem_ptr = base_ptr };
        }

        /// Marks all memory blocks in this range as either free or used, and updates all linked-list indexes
        fn mark_mem_blocks(self: *Self, mem: MemSpan, state: BlockState) void {
            debug_assert((mem.found == true) and (mem.block_idx + mem.block_len <= self.pool.len) and (mem.block_len > 0));
            debug_assert(compute: {
                const base_ptr = mem.mem_ptr;
                for (0..mem.block_len) |i| {
                    const idx = mem.block_idx + i;
                    if (self.pool.ptr[idx].state == state or self.pool.ptr[idx].state == .INVALID) break :compute false;
                    if (self.pool.ptr[idx].ptr != base_ptr + (i * BLOCK_SIZE)) break :compute false;
                }
                break :compute true;
            });
            const first_idx = mem.block_idx;
            const last_idx = mem.block_idx + mem.block_len - 1;
            var first_block = &self.pool.ptr[first_idx];
            var last_block = &self.pool.ptr[last_idx];
            first_block.prev = NO_IDX;
            for (first_idx..last_idx) |idx| {
                self.pool.ptr[idx].state = state;
                self.pool.ptr[idx].next = idx + 1;
                self.pool.ptr[idx + 1].prev = idx;
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

        fn resize_pool_for_additional_blocks(self: *Self, additional_pool_len: u32) AllocError!void {
            // Return if pool already has enough capacity
            if (self.pool.cap >= self.pool.len + additional_pool_len) return;
            const new_data_len: usize = @as(usize, @intCast(self.pool.len + additional_pool_len)) * @sizeOf(MemBlock);
            const new_data_blocks: u32 = bytes_to_blocks(new_data_len);
            const old_data_cap_len = self.pool.cap * @sizeOf(MemBlock);
            const old_mem: MemSpan = self.find_used_blocks_from_idx(self.pool.own_idx, old_data_cap_len);
            const old_data_total_len = blocks_to_bytes(old_mem.block_len);
            const delta_blocks = new_data_blocks - old_mem.block_len;
            // Try to just extend the existing MemBlocks if they are followed by enough contiguous free MemBlocks
            var new_mem: MemSpan = self.try_find_contiguous_free_blocks_offset_from_base_idx(old_mem.block_idx, old_mem.block_len, delta_blocks);
            if (new_mem.found) {
                self.mark_mem_blocks(new_mem, .USED);
                const total_new_blocks = old_mem.block_len + new_mem.block_len;
                const total_new_bytes = @as(usize, total_new_blocks) << BLOCK_SIZE_SHIFT;
                const new_cap = @as(u32, total_new_bytes / @sizeOf(MemBlock));
                self.pool.cap = new_cap;
                debug_assert(self.pool.cap >= self.pool.len + additional_pool_len);
                return;
            }
            // Try to find another segment of contiguous free MemBlocks that can hold the new needed pool len
            const old_data_len = self.pool.len * @sizeOf(MemBlock);
            new_mem = self.try_find_free_span(new_data_len);
            if (new_mem.found) {
                @memcpy(new_mem.mem_ptr[0..old_data_len], old_mem.mem_ptr[0..old_data_len]);
                if (WIPE_ON_FREE) @memset(old_mem.mem_ptr[0..old_data_total_len], WIPE_MEM_BYTE);
                self.pool.own_idx = new_mem.block_idx;
                self.pool.ptr = @ptrCast(@alignCast(new_mem.mem_ptr));
                const new_cap = blocks_to_bytes(new_mem.block_len) / @sizeOf(MemBlock);
                self.pool.cap = new_cap;
                self.mark_mem_blocks(old_mem, .FREE);
                self.mark_mem_blocks(new_mem, .USED);
                debug_assert(self.pool.cap >= self.pool.len + additional_pool_len);
                return;
            }
            // Try to see if the backing allocator can resize in place
            const resize_request = backing_blocks_to_bytes(bytes_to_backing_blocks(new_data_len));
            if (self.backing_alloc.rawResize(old_mem.mem_ptr[0..old_data_total_len], BLOCK_ALIGN, resize_request, 0)) {
                const resize_cap = @as(u32, resize_request / @sizeOf(MemBlock));
                self.pool.cap = resize_cap;
                return;
            }
            // Allocate a brand new memory segment entirely to hold the new pool len
            var predict_alloc_backing_multiple = bytes_to_backing_blocks(new_data_len);
            var predict_alloc_blocks = backing_blocks_to_blocks(predict_alloc_backing_multiple);
            var predict_alloc_bytes: usize = @as(usize, @intCast(self.pool.len + predict_alloc_blocks)) * @sizeOf(MemBlock);
            var real_alloc_backing_multiple = bytes_to_backing_blocks(predict_alloc_bytes);
            // VERIFY There may be a way to compute this without a while loop
            while (real_alloc_backing_multiple != predict_alloc_backing_multiple) {
                predict_alloc_backing_multiple += 1;
                predict_alloc_blocks = backing_blocks_to_blocks(predict_alloc_backing_multiple);
                predict_alloc_bytes = @as(usize, @intCast(self.pool.len + predict_alloc_blocks)) * @sizeOf(MemBlock);
                real_alloc_backing_multiple = bytes_to_backing_blocks(predict_alloc_bytes);
            }
            const real_alloc_bytes = backing_blocks_to_bytes(real_alloc_backing_multiple);
            const real_alloc_blocks = backing_blocks_to_blocks(real_alloc_backing_multiple);
            const real_alloc_pool_blocks = bytes_to_blocks(@as(usize, @intCast(self.pool.len + real_alloc_blocks)) * @sizeOf(MemBlock));
            debug_assert(real_alloc_blocks >= real_alloc_pool_blocks);
            const real_alloc_extra_blocks = real_alloc_blocks - real_alloc_pool_blocks;
            const real_alloc_pool_bytes = blocks_to_bytes(real_alloc_pool_blocks);
            const new_alloc_slice = try self.allocate_new_memory(real_alloc_bytes);
            @memcpy(new_alloc_slice.ptr, old_mem.mem_ptr[0..old_data_len]);
            Self.clear_mem_if_needed(old_mem.mem_ptr[0..old_data_total_len]);
            self.mark_mem_blocks(old_mem, .FREE);
            self.pool.cap = @intCast(real_alloc_pool_bytes / @sizeOf(MemBlock));
            self.pool.ptr = @ptrCast(@alignCast(new_alloc_slice.ptr));
            self.pool.own_idx = self.pool.len;
            self.pool.len += real_alloc_blocks;
            debug_assert(self.pool.cap >= self.pool.len + additional_pool_len);
            var block_ptr: [*]u8 = new_alloc_slice.ptr;
            for (self.pool.own_idx..self.pool.own_idx + real_alloc_blocks) |idx| {
                self.pool.ptr[idx] = MemBlock.brand_new(block_ptr);
                block_ptr += BLOCK_SIZE;
            }
            const uninit_used_blocks = MemSpan.found(self.pool.own_idx, real_alloc_pool_blocks, new_alloc_slice.ptr);
            const uninit_free_blocks = MemSpan.found(self.pool.own_idx + real_alloc_pool_blocks, real_alloc_extra_blocks, new_alloc_slice.ptr + (real_alloc_pool_blocks * BLOCK_SIZE));
            self.mark_mem_blocks(uninit_used_blocks, .USED);
            self.mark_mem_blocks(uninit_free_blocks, .FREE);
            return;
        }

        fn raw_alloc(self_opaque: *anyopaque, bytes: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            _ = ret_addr;
            if (bytes == 0) return @ptrFromInt(std.mem.alignBackward(usize, std.math.maxInt(usize), ptr_align));
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            // Try to find free memory span
            const free_span = self.try_find_free_span(bytes);
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
            if (self.pool.capacity - self.pool.items.len < BLOCKS_PER_PAGE) {}
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

        fn raw_resize(self_opaque: *anyopaque, slice: []u8, ptr_align: u8, new_size: usize, ret_addr: usize) bool {
            _ = ret_addr;
            user_assert(ptr_align <= BLOCK_SIZE);
            const self: *Self = @ptrCast(@alignCast(self_opaque));
            for (self.pool.items) |mem_block| {
                if (mem_block.slice.ptr == slice.ptr and mem_block.slice.len >= new_size) return true;
            }
            return false;
        }

        fn raw_free(self_opaque: *anyopaque, slice: []u8, ptr_align: u8, ret_addr: usize) void {
            _ = ret_addr;
            user_assert(ptr_align <= BLOCK_SIZE);
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
