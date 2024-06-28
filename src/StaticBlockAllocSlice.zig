const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const BlockAllocator = @import("./BlockAllocator.zig");
const AllocError = BlockAllocator.AllocError;

pub inline fn define(comptime T: type, comptime allocator_ptr: *BlockAllocator) type {
    return define_with_sentinel_and_align(T, null, null, allocator_ptr);
}

pub inline fn define_with_sentinel(comptime T: type, comptime sentinel: T, comptime allocator_ptr: *BlockAllocator) type {
    return define_with_sentinel_and_align(T, sentinel, null, allocator_ptr);
}

pub inline fn define_with_align(comptime T: type, comptime alignment: ?u29, comptime allocator_ptr: *BlockAllocator) type {
    return define_with_sentinel_and_align(T, null, alignment, allocator_ptr);
}

pub fn define_with_sentinel_and_align(comptime T: type, comptime sentinel: ?T, comptime alignment: ?u29, comptime allocator_ptr: *BlockAllocator) type {
    if (alignment) |a| {
        if (a == @alignOf(T)) {
            return define_with_sentinel_and_align(T, sentinel, null, allocator_ptr);
        }
    }

    const aa = if (alignment) |a| a else @alignOf(T);
    if (aa < @alignOf(T)) @compileError("specified alignment is smaller than @alignOf(T)");

    return struct {
        const Self = @This();
        pub const alloc: *BlockAllocator = allocator_ptr;
        const ALIGN: u29 = aa;
        const LOG2_OF_ALIGN: u8 = @as(u8, math.log2_int(u29, ALIGN));
        const BLANK_ARRAY align(ALIGN) = if (sentinel) [0:sentinel]T{} else [0]T{};
        const BLANK_PTR: Ptr = @alignCast(&BLANK_ARRAY);

        ptr: Ptr,
        len: usize,

        pub const SliceType = eval: {
            if (alignment) |a| {
                if (sentinel) |s| {
                    break :eval [:s]align(a) T;
                } else {
                    break :eval []align(a) T;
                }
            } else {
                if (sentinel) |s| {
                    break :eval [:s]T;
                } else {
                    break :eval []T;
                }
            }
        };
        const Ptr = eval: {
            if (alignment) |a| {
                break :eval [*]align(a) T;
            } else {
                break :eval [*]T;
            }
        };
        const AllocPtr = eval: {
            if (alignment) |a| {
                break :eval [*]align(a) u8;
            } else {
                break :eval [*]u8;
            }
        };
        const AllocSlice = eval: {
            if (alignment) |a| {
                break :eval []align(a) u8;
            } else {
                break :eval []u8;
            }
        };

        /// Creates a new slice using the type-defined allocator with a length equal-to
        /// or greater-than the minimum requested
        ///
        /// If `len == 0` the pointer references a type-defined const zero-length (with optional sentinel) array
        ///
        /// For a slice with an exact length, use `.create_exact(exact_len)`
        pub fn create_minimum(min_len: usize) AllocError!Self {
            if (min_len == 0) {
                return Self{
                    .ptr = BLANK_PTR,
                    .len = 0,
                };
            }
            const alloc_len = len_to_alloc_len(min_len);
            const alloc_slice: AllocSlice = @alignCast(alloc.raw_alloc(alloc_len, LOG2_OF_ALIGN, @returnAddress()) orelse return AllocError.OutOfMemory);
            var new = from_alloc_mem(alloc_slice);
            if (sentinel) |s| {
                new.ptr[new.len] = s;
            }
            return new;
        }

        /// Creates a new slice using the type-defined allocator with an exact length
        ///
        /// If `len == 0` the pointer references a type-defined const zero-length (with optional sentinel) array
        pub fn create_exact(exact_len: usize) AllocError!Self {
            var new = try Self.create_minimum(exact_len);
            new.len = exact_len;
            if (sentinel) |s| {
                new.ptr[new.len] = s;
            }
            return new;
        }

        /// Resizes slice using type-defined allocator to a new length greater-than
        /// or equal-to the requested length
        ///
        /// Returns `false` if existing memory pointers were invalidated (underlying memory reallocated),
        /// else `true` if existing memory pointers are still valid (no memory move)
        ///
        /// For a slice with an exact length, you can re-slice the result, or use
        /// `.resize_exact(exact_len)`
        pub fn resize_minimum(self: *Self, new_min_len: usize) AllocError!bool {
            if (self.len == 0 or self.ptr == BLANK_PTR) {
                if (new_min_len == 0) {
                    return true;
                }
                self.* = try Self.create_minimum(new_min_len);
                return false;
            }
            if (new_min_len == 0) {
                self.release();
                return false;
            }
            const alloc_mem = self.to_alloc_mem();
            const new_alloc_len = len_to_alloc_len(new_min_len);
            if (alloc.raw_resize(alloc_mem, LOG2_OF_ALIGN, new_alloc_len, @returnAddress())) |new_real_len| {
                self.len = new_real_len;
                if (sentinel) |s| {
                    self.ptr[self.len] = s;
                }
                return true;
            }
            const new = try Self.create_minimum(new_min_len);
            const least_len = @min(self.len, new.len);
            @memcpy(new.ptr[0..least_len], self.ptr[0..least_len]);
            self.release();
            self.* = new;
            return false;
        }

        /// Resizes slice using type-defined allocator to a new exact length
        ///
        /// Returns `false` if existing memory pointers were invalidated (underlying memory reallocated),
        /// else `true` if existing memory pointers are still valid (no memory move)
        pub fn resize_exact(self: *Self, exact_len: usize) AllocError!bool {
            const resize_result = try self.resize_at_least(exact_len);
            self.len = exact_len;
            if (sentinel) |s| {
                self.ptr[self.len] = s;
            }
            return resize_result;
        }

        /// Attempts to resize slice using type-defined allocator to a new length greater-than
        /// or equal-to the requested length, WITHOUT moving the memory address
        ///
        /// Returns `false` if resize could not be completed without moving the memory address,
        /// else `true` if resize without move was successful
        ///
        /// For a slice with an exact length, you can re-slice the result, or use
        /// `.resize_exact_no_move(exact_len)`
        pub fn resize_minimum_no_move(self: *Self, new_min_len: usize) AllocError!bool {
            if ((self.len == 0 or self.ptr == BLANK_PTR) and new_min_len == 0) {
                return true;
            }
            if (new_min_len == 0) {
                return false;
            }
            const alloc_mem = self.to_alloc_mem();
            const new_alloc_len = len_to_alloc_len(new_min_len);
            if (alloc.raw_resize(alloc_mem, LOG2_OF_ALIGN, new_alloc_len, @returnAddress())) |new_real_len| {
                self.len = new_real_len;
                if (sentinel) |s| {
                    self.ptr[self.len] = s;
                }
                return true;
            }
            return false;
        }

        /// Resizes slice using type-defined allocator to a new exact length,
        /// WITHOUT moving the underlying memory address
        ///
        /// Returns `false` if resize could not be completed without moving the memory address,
        /// else `true` if resize without move was successful
        pub fn resize_exact_no_move(self: *Self, exact_len: usize) AllocError!bool {
            const resize_success = try self.resize_minimum_no_move(exact_len);
            if (resize_success) {
                self.len = exact_len;
                if (sentinel) |s| {
                    self.ptr[self.len] = s;
                }
            }
            return resize_success;
        }

        /// Releases the memory using the type-defined allocator, invalidating any element pointers
        ///
        /// Does nothing if `len == 0` or the pointer references the type-defined const zero-length array
        ///
        /// The slice struct can still be re-used by calling `slice.resize(new_len)` to allocate a new piece of memory for it
        pub fn release(self: *Self) void {
            if (self.len == 0 or self.ptr == BLANK_PTR) return;
            const alloc_slice = self.to_alloc_mem();
            alloc.raw_free(alloc_slice, LOG2_OF_ALIGN, @returnAddress());
            self.len = 0;
            self.ptr = BLANK_PTR;
        }

        /// Creates a new slice referencing new memory that holds all the same values as the this one
        pub fn clone(self: *Self) Self {
            const new = try Self.create_exact(self.len);
            @memcpy(new.ptr[0..self.len], self.ptr[0..self.len]);
            return new;
        }

        /// Returns the normal Zig slice using the pointer and length
        pub inline fn slice(self: *Self) SliceType {
            return self.ptr[0..self.len];
        }

        inline fn to_alloc_mem(self: *Self) AllocSlice {
            const byte_ptr: AllocPtr = @ptrCast(self.ptr);
            return byte_ptr[0..len_to_alloc_len(self.len)];
        }

        inline fn from_alloc_mem(alloc_slice: AllocSlice) Self {
            const type_ptr: Ptr = @ptrCast(@alignCast(alloc_slice.ptr));
            return Self{
                .items = type_ptr[0..len_from_alloc_len(alloc_slice.len)],
            };
        }

        inline fn len_to_alloc_len(len: usize) usize {
            const type_len = if (sentinel != null) len + 1 else len;
            return (type_len * @sizeOf(T));
        }

        inline fn len_from_alloc_len(alloc_len: usize) usize {
            const non_sentinel_len = if (sentinel != null) alloc_len - @sizeOf(T) else alloc_len;
            return (non_sentinel_len / @sizeOf(T));
        }
    };
}
