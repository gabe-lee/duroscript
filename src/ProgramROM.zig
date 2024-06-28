const std = @import("std");
const mem = std.mem;
const PageAllocator = std.heap.PageAllocator;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const DEBUG = std.debug.print;

const Self = @This();

alloc: Allocator,
ptr: [*]u8,
len: usize,
cap: usize,
waste: usize,

const PAGE_SIZE = std.mem.page_size;
const PAGE_SIZE_SHIFT = @ctz(@as(u64, PAGE_SIZE));
const ALLOC = std.heap.page_allocator;
const MAX_ALIGN = 8;

pub fn new(alloc: Allocator) Self {
    return Self{
        .alloc = alloc,
        .ptr = std.math.maxInt(usize),
        .len = 0,
        .cap = 0,
        .waste = 0,
    };
}

pub fn cleanup(self: *Self) void {
    self.alloc.free(self.ptr[0..self.cap]);
    return;
}

pub fn prepare_space_for_write(self: *Self, add_bytes: usize, comptime need_align: usize) void {
    const advance_count = (need_align - (self.len & ALIGN_MASK[need_align])) & ALIGN_MASK[need_align];
    assert(mem.alignForward(usize, self.len + advance_count, need_align));
    const new_required = self.len + advance_count + add_bytes;
    if (new_required > self.cap) {
        const resized_in_place = self.alloc.resize(self.ptr[0..self.len], new_required);
        if (!resized_in_place) {
            const new_mem_slice = self.alloc.alloc(u8, new_required) catch unreachable;
            self.alloc.free(self.ptr[0..self.len]);
            self.ptr = new_mem_slice.ptr;
            self.cap = new_mem_slice.len;
        } else {
            self.cap = new_required;
        }
    }
    self.len += advance_count;
    self.waste += advance_count;
    assert(mem.isAligned(self.len, need_align));
}

pub fn write_single(self: *Self, comptime T: type, val: T) void {
    assert(mem.isAligned(self.len, @alignOf(T)));
    assert((self.cap - self.len) >= @sizeOf(T));
    const dest_ptr: *T = @ptrCast(@alignCast(self.ptr + self.len));
    dest_ptr.* = val;
    self.len += @sizeOf(T);
}

pub fn write_slice(self: *Self, comptime T: type, vals: []T) void {
    assert(mem.isAligned(self.len, @alignOf(T)));
    assert((self.cap - self.len) >= (@sizeOf(T) * vals.len));
    const dest_ptr: [*]T = @ptrCast(@alignCast(self.ptr + self.len));
    @memcpy(dest_ptr, vals);
    self.len += (@sizeOf(T) * vals.len);
}

pub fn ref_single(self: *Self, comptime T: type, offset: usize) *const T {
    assert(offset & (@alignOf(T) - 1) == 0);
    assert(self.len >= offset + @sizeOf(T));
    const val_ptr: *const T = @ptrCast(@alignCast(self.ptr + offset));
    return val_ptr;
}

pub fn ref_slice(self: *Self, comptime T: type, offset: usize, len: usize) []const T {
    assert(offset & (@alignOf(T) - 1) == 0);
    assert(self.len >= offset + (@sizeOf(T) * len));
    const slice_ptr: [*]const T = @ptrCast(@alignCast(self.ptr + offset));
    return slice_ptr[0..len];
}

pub fn copy_single(self: *Self, comptime T: type, offset: usize) T {
    assert(offset & (@alignOf(T) - 1) == 0);
    assert(self.len >= offset + @sizeOf(T));
    const val_ptr: *const T = @ptrCast(@alignCast(self.ptr + offset));
    return val_ptr.*;
}

pub fn copy_slice(self: *Self, comptime T: type, offset: usize, dest: []T) void {
    assert(offset & (@alignOf(T) - 1) == 0);
    assert(self.len >= offset + (@sizeOf(T) * dest.len));
    const slice_ptr: [*]const T = @ptrCast(@alignCast(self.ptr + offset));
    @memcpy(dest, slice_ptr[0..dest.len]);
    return;
}

const ALIGN_MASK = [9]usize{
    0, // 0
    0b0, // 1
    0b1, // 2
    0, // 3
    0b11, // 4
    0, // 5
    0, // 6
    0, // 7
    0b111, // 8
};
