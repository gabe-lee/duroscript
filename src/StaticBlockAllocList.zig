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

    return struct {
        const Self = @This();
        pub const alloc: *BlockAllocator = allocator_ptr;

        items: Slice,
        capacity: usize,

        pub const Slice = eval: {
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

        pub fn create() Self {
            return Self{
                .items = &[_]T{},
                .capacity = 0,
            };
        }

        pub fn create_with_capacity(num: usize) AllocError!Self {
            var self = Self.create();
            try self.ensure_capacity_exact(num);
            return self;
        }

        pub fn destroy(self: Self) void {
            if (@sizeOf(T) > 0) {
                alloc.free(self.allocated_slice());
            }
        }

        /// List takes ownership of the passed in slice. The slice must have been
        /// allocated with `allocator`
        pub fn take_ownership_of(slice: Slice) Self {
            return Self{
                .items = slice,
                .capacity = slice.len,
            };
        }

        /// List takes ownership of the passed in slice. The slice must have been
        /// allocated with `allocator`.
        pub fn take_ownership_of_sentinel(comptime sentinel: T, slice: SentinelSlice(sentinel)) Self {
            return Self{
                .items = slice,
                .capacity = slice.len + 1,
            };
        }

        /// The caller takes ownership of the slice and is responsible for freeing its memory when done
        ///
        /// This list is empty and re-usable afterwards
        pub fn hand_over_ownership(self: *Self) AllocError!Slice {
            const old_memory = self.allocated_slice();
            if (alloc.resize(old_memory, self.items.len)) |_| {
                const result = self.items;
                self.* = Self.create();
                return result;
            }

            const new_memory = try alloc.alloc_with_align(T, alignment, self.items.len);
            @memcpy(new_memory, self.items);
            self.clear_and_free();
            return new_memory;
        }

        /// The caller takes ownership of the slice and is responsible for freeing its memory when done
        ///
        /// This list is empty and re-usable afterwards
        pub fn hand_over_ownership_sentinel(self: *Self, comptime sentinel: T) AllocError!SentinelSlice(sentinel) {
            try self.ensure_capacity_exact(self.items.len + 1);
            self.append_assume_capacity(sentinel);
            const result = try self.hand_over_ownership();
            return result[0 .. result.len - 1 :sentinel];
        }

        /// Creates a copy of this StaticBlockAllocList, using the same allocator.
        pub fn clone(self: Self) AllocError!Self {
            var cloned = try Self.create_with_capacity(self.capacity);
            cloned.append_slice_assume_capacity(self.items);
            return cloned;
        }

        /// Insert `item` at index `i`. Moves `list[i .. list.len]` to higher indices to make room.
        /// If `i` is equal to the length of the list this operation is equivalent to append.
        /// This operation is O(N).
        /// Invalidates element pointers if additional memory is needed.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn insert(self: *Self, i: usize, item: T) AllocError!void {
            const dst = try self.add_many_slots_at(i, 1);
            dst[0] = item;
        }

        /// Insert `item` at index `i`. Moves `list[i .. list.len]` to higher indices to make room.
        /// If `i` is equal to the length of the list this operation is
        /// equivalent to appendAssumeCapacity.
        /// This operation is O(N).
        /// Asserts that there is enough capacity for the new item.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn insert_assume_capacity(self: *Self, i: usize, item: T) void {
            assert(self.items.len < self.capacity);
            self.items.len += 1;

            mem.copyBackwards(T, self.items[i + 1 .. self.items.len], self.items[i .. self.items.len - 1]);
            self.items[i] = item;
        }

        /// Add `count` new elements at position `index`, which have
        /// `undefined` values. Returns a slice pointing to the newly allocated
        /// elements, which becomes invalid after various `StaticBlockAllocList`
        /// operations.
        /// Invalidates pre-existing pointers to elements at and after `index`.
        /// Invalidates all pre-existing element pointers if capacity must be
        /// increased to accomodate the new elements.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn add_many_slots_at(self: *Self, index: usize, count: usize) AllocError![]T {
            const new_len = try add_or_error(self.items.len, count);

            if (self.capacity >= new_len)
                return add_many_slots_at_assume_capacity(self, index, count);

            // Here we avoid copying allocated but unused bytes by
            // attempting a resize in place, and falling back to allocating
            // a new buffer and doing our own copy. With a realloc() call,
            // the allocator implementation would pointlessly copy our
            // extra capacity.
            const old_memory = self.allocated_slice();
            if (alloc.resize(old_memory, new_len)) |real_new_cap| {
                self.capacity = real_new_cap;
                return add_many_slots_at_assume_capacity(self, index, count);
            }

            // Make a new allocation, avoiding `ensureTotalCapacity` in order
            // to avoid extra memory copies.
            const new_memory = try alloc.alloc_with_align(T, alignment, new_len);
            const to_move = self.items[index..];
            @memcpy(new_memory[0..index], self.items[0..index]);
            @memcpy(new_memory[index + count ..][0..to_move.len], to_move);
            alloc.free(old_memory);
            self.items = new_memory[0..new_len];
            self.capacity = new_memory.len;
            // The inserted elements at `new_memory[index..][0..count]` have
            // already been set to `undefined` by memory allocation.
            return new_memory[index..][0..count];
        }

        /// Add `count` new elements at position `index`, which have
        /// `undefined` values. Returns a slice pointing to the newly allocated
        /// elements, which becomes invalid after various `StaticBlockAllocList`
        /// operations.
        /// Asserts that there is enough capacity for the new elements.
        /// Invalidates pre-existing pointers to elements at and after `index`, but
        /// does not invalidate any before that.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn add_many_slots_at_assume_capacity(self: *Self, index: usize, count: usize) []T {
            const new_len = self.items.len + count;
            assert(self.capacity >= new_len);
            const to_move = self.items[index..];
            self.items.len = new_len;
            mem.copyBackwards(T, self.items[index + count ..], to_move);
            const result = self.items[index..][0..count];
            @memset(result, undefined);
            return result;
        }

        /// Insert slice `items` at index `i` by moving `list[i .. list.len]` to make room.
        /// This operation is O(N).
        /// Invalidates pre-existing pointers to elements at and after `index`.
        /// Invalidates all pre-existing element pointers if capacity must be
        /// increased to accomodate the new elements.
        /// Asserts that the index is in bounds or equal to the length.
        pub fn insert_slice(
            self: *Self,
            index: usize,
            items: []const T,
        ) AllocError!void {
            const dst = try self.add_many_slots_at(index, items.len);
            @memcpy(dst, items);
        }

        //FIXME implement fix
        // /// Grows or shrinks the list as necessary.
        // /// Invalidates element pointers if additional capacity is allocated.
        // /// Asserts that the range is in bounds.
        // pub fn replace_range(self: *Self, start: usize, len: usize, new_items: []const T) AllocError!void {
        //     var unmanaged = self.moveToUnmanaged();
        //     defer self.* = unmanaged.toManaged(self.allocator);
        //     return unmanaged.replaceRange(self.allocator, start, len, new_items);
        // }

        //FIXME implement fix
        // /// Grows or shrinks the list as necessary.
        // /// Never invalidates element pointers.
        // /// Asserts the capacity is enough for additional items.
        // pub fn replace_range_assume_capacity(self: *Self, start: usize, len: usize, new_items: []const T) void {
        //     var unmanaged = self.moveToUnmanaged();
        //     defer self.* = unmanaged.toManaged(self.allocator);
        //     return unmanaged.replaceRangeAssumeCapacity(start, len, new_items);
        // }

        /// Extends the list by 1 element. Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn append(self: *Self, item: T) AllocError!void {
            const new_item_ptr = try self.add_one_slot();
            new_item_ptr.* = item;
        }

        /// Extends the list by 1 element.
        /// Never invalidates element pointers.
        /// Asserts that the list can hold one additional item.
        pub fn append_assume_capacity(self: *Self, item: T) void {
            const new_item_ptr = self.add_one_slot_assume_capacity();
            new_item_ptr.* = item;
        }

        /// Remove the element at index `i`, shift elements after index
        /// `i` forward, and return the removed element.
        /// Invalidates element pointers to end of list.
        /// This operation is O(N).
        /// This preserves item order. Use `swapRemove` if order preservation is not important.
        /// Asserts that the index is in bounds.
        /// Asserts that the list is not empty.
        pub fn remove(self: *Self, i: usize) T {
            const old_item = self.items[i];
            //FIXME
            self.replace_range_assume_capacity(i, 1, &.{});
            return old_item;
        }

        /// Removes the element at the specified index and returns it.
        /// The empty slot is filled from the end of the list.
        /// This operation is O(1).
        /// This may not preserve item order. Use `orderedRemove` if you need to preserve order.
        /// Asserts that the list is not empty.
        /// Asserts that the index is in bounds.
        pub fn swap_remove(self: *Self, i: usize) T {
            if (self.items.len - 1 == i) return self.pop();

            const old_item = self.items[i];
            self.items[i] = self.pop();
            return old_item;
        }

        /// Append the slice of items to the list. Allocates more
        /// memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn append_slice(self: *Self, items: []const T) AllocError!void {
            try self.ensure_unused_capacity(items.len);
            self.append_slice_assume_capacity(items);
        }

        /// Append the slice of items to the list.
        /// Never invalidates element pointers.
        /// Asserts that the list can hold the additional items.
        pub fn append_slice_assume_capacity(self: *Self, items: []const T) void {
            const old_len = self.items.len;
            const new_len = old_len + items.len;
            assert(new_len <= self.capacity);
            self.items.len = new_len;
            @memcpy(self.items[old_len..][0..items.len], items);
        }

        /// Append an unaligned slice of items to the list. Allocates more
        /// memory as necessary. Only call this function if calling
        /// `appendSlice` instead would be a compile error.
        /// Invalidates element pointers if additional memory is needed.
        pub fn append_unaligned_slice(self: *Self, items: []align(1) const T) AllocError!void {
            try self.ensure_unused_capacity(items.len);
            self.append_unaligned_slice_assume_capacity(items);
        }

        /// Append the slice of items to the list.
        /// Never invalidates element pointers.
        /// This function is only needed when calling
        /// `appendSliceAssumeCapacity` instead would be a compile error due to the
        /// alignment of the `items` parameter.
        /// Asserts that the list can hold the additional items.
        pub fn append_unaligned_slice_assume_capacity(self: *Self, items: []align(1) const T) void {
            const old_len = self.items.len;
            const new_len = old_len + items.len;
            assert(new_len <= self.capacity);
            self.items.len = new_len;
            @memcpy(self.items[old_len..][0..items.len], items);
        }

        pub const Writer = if (T != u8)
            @compileError("The Writer interface is only defined for an element type of u8 " ++
                "but the element type of this List is " ++ @typeName(T))
        else
            std.io.Writer(*Self, AllocError, append_write);

        /// Initializes a Writer which will append to the list.
        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        /// Same as `append` except it returns the number of bytes written, which is always the same
        /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
        /// Invalidates element pointers if additional memory is needed.
        fn append_write(self: *Self, m: []const u8) AllocError!usize {
            try self.append_slice(m);
            return m.len;
        }

        /// Append a value to the list `n` times.
        /// Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        /// The function is inline so that a comptime-known `value` parameter will
        /// have a more optimal memset codegen in case it has a repeated byte pattern.
        pub inline fn append_n_times(self: *Self, value: T, n: usize) AllocError!void {
            const old_len = self.items.len;
            try self.resize(try add_or_error(old_len, n));
            @memset(self.items[old_len..self.items.len], value);
        }

        /// Append a value to the list `n` times.
        /// Never invalidates element pointers.
        /// The function is inline so that a comptime-known `value` parameter will
        /// have a more optimal memset codegen in case it has a repeated byte pattern.
        /// Asserts that the list can hold the additional items.
        pub inline fn append_n_times_assume_capacity(self: *Self, value: T, n: usize) void {
            const new_len = self.items.len + n;
            assert(new_len <= self.capacity);
            @memset(self.items.ptr[self.items.len..new_len], value);
            self.items.len = new_len;
        }

        /// Adjust the list length to `new_len`.
        /// Additional elements contain the value `undefined`.
        /// Invalidates element pointers if additional memory is needed.
        pub fn resize(self: *Self, new_len: usize) AllocError!void {
            try self.ensure_capacity(new_len);
            self.items.len = new_len;
        }

        //FIXME implement fix
        // /// Reduce allocated capacity to `new_len`.
        // /// May invalidate element pointers.
        // /// Asserts that the new length is less than or equal to the previous length.
        // pub fn shrink_and_free(self: *Self, new_len: usize) void {
        //     var unmanaged = self.moveToUnmanaged();
        //     unmanaged.shrinkAndFree(self.allocator, new_len);
        //     self.* = unmanaged.toManaged(self.allocator);
        // }

        /// Reduce length to `new_len`.
        /// Invalidates element pointers for the elements `items[new_len..]`.
        /// Asserts that the new length is less than or equal to the previous length.
        pub fn shrink_retaining_capacity(self: *Self, new_len: usize) void {
            assert(new_len <= self.items.len);
            self.items.len = new_len;
        }

        /// Invalidates all element pointers.
        pub fn clear_retaining_capacity(self: *Self) void {
            self.items.len = 0;
        }

        /// Invalidates all element pointers.
        pub fn clear_and_free(self: *Self) void {
            alloc.free(self.allocated_slice());
            self.items.len = 0;
            self.capacity = 0;
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the array so that it can hold at least `new_capacity` items.
        /// Invalidates element pointers if additional memory is needed.
        pub fn ensure_capacity(self: *Self, new_capacity: usize) AllocError!void {
            if (@sizeOf(T) == 0) {
                self.capacity = math.maxInt(usize);
                return;
            }

            if (self.capacity >= new_capacity) return;

            return self.ensure_capacity_exact(new_capacity);
        }

        /// If the current capacity is less than `new_capacity`, this function will
        /// modify the array so that it can hold exactly `new_capacity` items.
        /// Invalidates element pointers if additional memory is needed.
        pub fn ensure_capacity_exact(self: *Self, new_capacity: usize) AllocError!void {
            if (@sizeOf(T) == 0) {
                self.capacity = math.maxInt(usize);
                return;
            }

            if (self.capacity >= new_capacity) return;

            // Here we avoid copying allocated but unused bytes by
            // attempting a resize in place, and falling back to allocating
            // a new buffer and doing our own copy. With a realloc() call,
            // the allocator implementation would pointlessly copy our
            // extra capacity.
            const old_memory = self.allocated_slice();
            if (alloc.resize(old_memory, new_capacity)) |real_cap| {
                self.capacity = real_cap;
            } else {
                const new_memory = try alloc.alloc_with_align(T, alignment, new_capacity);
                @memcpy(new_memory[0..self.items.len], self.items);
                alloc.free(old_memory);
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            }
        }

        /// Modify the array so that it can hold at least `additional_count` **more** items.
        /// Invalidates element pointers if additional memory is needed.
        pub fn ensure_unused_capacity(self: *Self, additional_count: usize) AllocError!void {
            return self.ensure_capacity(try add_or_error(self.items.len, additional_count));
        }

        /// Increases the array's length to match the full capacity that is already allocated.
        /// The new elements have `undefined` values.
        /// Never invalidates element pointers.
        pub fn grow_to_capacity(self: *Self) void {
            self.items.len = self.capacity;
        }

        /// Increase length by 1, returning pointer to the new item.
        /// The returned pointer becomes invalid when the list resized.
        pub fn add_one_slot(self: *Self) AllocError!*T {
            // This can never overflow because `self.items` can never occupy the whole address space
            const newlen = self.items.len + 1;
            try self.ensure_capacity(newlen);
            return self.add_one_slot_assume_capacity();
        }

        /// Increase length by 1, returning pointer to the new item.
        /// The returned pointer becomes invalid when the list is resized.
        /// Never invalidates element pointers.
        /// Asserts that the list can hold one additional item.
        pub fn add_one_slot_assume_capacity(self: *Self) *T {
            assert(self.items.len < self.capacity);
            self.items.len += 1;
            return &self.items[self.items.len - 1];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is an array pointing to the newly allocated elements.
        /// The returned pointer becomes invalid when the list is resized.
        /// Resizes list if `self.capacity` is not large enough.
        pub fn add_many_slots_array_ptr(self: *Self, comptime n: usize) AllocError!*[n]T {
            const prev_len = self.items.len;
            try self.resize(try add_or_error(self.items.len, n));
            return self.items[prev_len..][0..n];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is an array pointing to the newly allocated elements.
        /// Never invalidates element pointers.
        /// The returned pointer becomes invalid when the list is resized.
        /// Asserts that the list can hold the additional items.
        pub fn add_many_slots_array_ptr_assume_capacity(self: *Self, comptime n: usize) *[n]T {
            assert(self.items.len + n <= self.capacity);
            const prev_len = self.items.len;
            self.items.len += n;
            return self.items[prev_len..][0..n];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is a slice pointing to the newly allocated elements.
        /// The returned pointer becomes invalid when the list is resized.
        /// Resizes list if `self.capacity` is not large enough.
        pub fn add_many_slots_slice_ptr(self: *Self, n: usize) AllocError![]T {
            const prev_len = self.items.len;
            try self.resize(try add_or_error(self.items.len, n));
            return self.items[prev_len..][0..n];
        }

        /// Resize the array, adding `n` new elements, which have `undefined` values.
        /// The return value is a slice pointing to the newly allocated elements.
        /// Never invalidates element pointers.
        /// The returned pointer becomes invalid when the list is resized.
        /// Asserts that the list can hold the additional items.
        pub fn add_many_slots_slice_ptr_assume_capacity(self: *Self, n: usize) []T {
            assert(self.items.len + n <= self.capacity);
            const prev_len = self.items.len;
            self.items.len += n;
            return self.items[prev_len..][0..n];
        }

        /// Remove and return the last element from the list.
        /// Invalidates element pointers to the removed element.
        /// Asserts that the list is not empty.
        pub fn pop(self: *Self) T {
            const val = self.items[self.items.len - 1];
            self.items.len -= 1;
            return val;
        }

        /// Remove and return the last element from the list, or
        /// return `null` if list is empty.
        /// Invalidates element pointers to the removed element, if any.
        pub fn pop_or_null(self: *Self) ?T {
            if (self.items.len == 0) return null;
            return self.pop();
        }

        /// Returns a slice of all the items plus the extra capacity, whose memory
        /// contents are `undefined`.
        pub fn allocated_slice(self: Self) Slice {
            // `items.len` is the length, not the capacity.
            return self.items.ptr[0..self.capacity];
        }

        /// Returns a slice of only the extra capacity after items.
        /// This can be useful for writing directly into an StaticBlockAllocList.
        /// Note that such an operation must be followed up with a direct
        /// modification of `self.items.len`.
        pub fn unused_capacity_slice(self: Self) Slice {
            return self.allocated_slice()[self.items.len..];
        }

        /// Returns the last element from the list.
        /// Asserts that the list is not empty.
        pub fn get_last(self: Self) T {
            const val = self.items[self.items.len - 1];
            return val;
        }

        /// Returns the last element from the list, or `null` if list is empty.
        pub fn get_last_or_null(self: Self) ?T {
            if (self.items.len == 0) return null;
            return self.get_last();
        }
    };
}

fn add_or_error(a: usize, b: usize) error{OutOfMemory}!usize {
    const result, const overflow = @addWithOverflow(a, b);
    if (overflow != 0) return error.OutOfMemory;
    return result;
}
