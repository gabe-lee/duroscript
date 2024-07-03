const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");
const Global = @import("./Global.zig");

const Self = @This();

data: Global.U8BufLarge.List,
waste: usize,

const MAX_ALIGN = 8;

pub fn new() Self {
    return Self{
        .data = Global.U8BufLarge.List.create(),
        .waste = 0,
    };
}

pub fn cleanup(self: *Self) void {
    self.data.release();
    return;
}

pub fn prepare_space_for_write(self: *Self, add_bytes: usize, comptime need_align: usize) void {
    const aligned_start = mem.alignForward(usize, self.data.len, need_align);
    const waste = aligned_start - self.data.len;
    const new_required = self.data.len + aligned_start + add_bytes;
    _ = self.data.ensure_cap(new_required);
    self.data.set_len_to(aligned_start);
    self.waste += waste;
}

pub fn write_single(self: *Self, comptime T: type, val: T) void {
    assert(mem.isAligned(self.data.len, @alignOf(T)));
    assert((self.data.cap - self.data.len) >= @sizeOf(T));
    const dest_ptr: *T = @ptrCast(@alignCast(self.data.ptr + self.data.len));
    dest_ptr.* = val;
    self.data.len += @sizeOf(T);
}

pub fn write_slice(self: *Self, comptime T: type, vals: []T) void {
    assert(mem.isAligned(self.data.len, @alignOf(T)));
    assert((self.data.cap - self.data.len) >= (@sizeOf(T) * vals.len));
    const dest_ptr: [*]T = @ptrCast(@alignCast(self.data.ptr + self.data.len));
    @memcpy(dest_ptr, vals);
    self.data.len += (@sizeOf(T) * vals.len);
}

pub fn ref_single(self: *Self, comptime T: type, offset: usize) *const T {
    assert(mem.isAligned(self.data.ptr + offset, @alignOf(T)));
    assert(self.data.len >= offset + @sizeOf(T));
    const val_ptr: *const T = @ptrCast(@alignCast(self.data.ptr + offset));
    return val_ptr;
}

pub fn ref_slice(self: *Self, comptime T: type, offset: usize, len: usize) []const T {
    assert(mem.isAligned(self.data.ptr + offset, @alignOf(T)));
    assert(self.data.len >= offset + (@sizeOf(T) * len));
    const slice_ptr: [*]const T = @ptrCast(@alignCast(self.data.ptr + offset));
    return slice_ptr[0..len];
}

pub fn copy_single(self: *Self, comptime T: type, offset: usize) T {
    assert(mem.isAligned(self.data.ptr + offset, @alignOf(T)));
    assert(self.data.len >= offset + @sizeOf(T));
    const val_ptr: *const T = @ptrCast(@alignCast(self.data.ptr + offset));
    return val_ptr.*;
}

pub fn copy_slice(self: *Self, comptime T: type, offset: usize, dest: []T) void {
    assert(mem.isAligned(self.data.ptr + offset, @alignOf(T)));
    assert(self.data.len >= offset + (@sizeOf(T) * dest.len));
    const slice_ptr: [*]const T = @ptrCast(@alignCast(self.data.ptr + offset));
    @memcpy(dest, slice_ptr[0..dest.len]);
    return;
}
