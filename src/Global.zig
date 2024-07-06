const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const PooledBlockAllocator = @import("./PooledBlockAllocator.zig");
const BlockAllocator = @import("./BlockAllocator.zig");
const IdentManager = @import("./IdentManager.zig");
const NoticeManager = @import("./NoticeManager.zig");
const ProgramROM = @import("./ProgramROM.zig");
const SourceManager = @import("./SourceManager.zig");
const StaticAllocBuffer = @import("./StaticAllocBuffer.zig");

const Self = @This();

pub var root_alloc: Allocator = undefined;
pub var large_alloc: Allocator = undefined;
pub var large_block_alloc: BlockAllocator = undefined;
pub var large_alloc_concrete: LargeAlloc = undefined;
pub var medium_alloc: Allocator = undefined;
pub var medium_block_alloc: BlockAllocator = undefined;
pub var medium_alloc_concrete: MediumAlloc = undefined;
pub var small_alloc: Allocator = undefined;
pub var small_block_alloc: BlockAllocator = undefined;
pub var small_alloc_concrete: SmallAlloc = undefined;
pub var ident_manager: IdentManager = undefined;
pub var notice_manager: NoticeManager = undefined;
pub var token_rom: ProgramROM = undefined;
pub var source_manager: SourceManager = undefined;

const LargeAlloc = PooledBlockAllocator.define(PooledBlockAllocator.Config{
    .block_size = 4096,
    .backing_request_size = mem.page_size,
    .alloc_error_behavior = .PANICS,
    .safety_checks = .RELEASE_SAFE_AND_BELOW,
    .safety_check_severity = .PANIC,
    .auto_shrink = .SIMPLE,
    .auto_shrink_threshold = .{ .PERCENT_MIN_MAX = .{ .min = 0.25, .max = 0.5 } },
    .index_type = u32,
    .secure_wipe_freed_memory = false,
});

const MediumAlloc = PooledBlockAllocator.define(PooledBlockAllocator.Config{
    .block_size = 1024,
    .backing_request_size = 4096,
    .alloc_error_behavior = .PANICS,
    .safety_checks = .RELEASE_SAFE_AND_BELOW,
    .safety_check_severity = .PANIC,
    .auto_shrink = .SIMPLE,
    .auto_shrink_threshold = .{ .PERCENT_MIN_MAX = .{ .min = 0.25, .max = 0.5 } },
    .index_type = u32,
    .secure_wipe_freed_memory = false,
});

const SmallAlloc = PooledBlockAllocator.define(PooledBlockAllocator.Config{
    .block_size = 256,
    .backing_request_size = 1024,
    .alloc_error_behavior = .PANICS,
    .safety_checks = .RELEASE_SAFE_AND_BELOW,
    .safety_check_severity = .PANIC,
    .auto_shrink = .SIMPLE,
    .auto_shrink_threshold = .{ .PERCENT_MIN_MAX = .{ .min = 0.25, .max = 0.5 } },
    .index_type = u32,
    .secure_wipe_freed_memory = false,
});

pub fn init(use_root_alloc: Allocator) void {
    Self.root_alloc = use_root_alloc;

    Self.large_alloc_concrete = LargeAlloc.new(Self.root_alloc);
    Self.large_alloc = Self.large_alloc_concrete.allocator();
    Self.large_block_alloc = Self.large_alloc_concrete.block_allocator();

    Self.medium_alloc_concrete = MediumAlloc.new(Self.large_alloc);
    Self.medium_alloc = Self.medium_alloc_concrete.allocator();
    Self.medium_block_alloc = Self.medium_alloc_concrete.block_allocator();

    Self.small_alloc_concrete = SmallAlloc.new(Self.medium_alloc);
    Self.small_alloc = Self.small_alloc_concrete.allocator();
    Self.small_block_alloc = Self.small_alloc_concrete.block_allocator();

    Self.ident_manager = IdentManager.new();
    Self.notice_manager = NoticeManager.new();
    Self.token_rom = ProgramROM.new();
    Self.source_manager = SourceManager.new();
}

pub fn cleanup() void {
    Self.source_manager.cleanup();
    Self.token_rom.cleanup();
    Self.notice_manager.cleanup();
    Self.ident_manager.cleanup();
    Self.small_alloc_concrete.release_all_memory(true);
    Self.medium_alloc_concrete.release_all_memory(true);
    Self.large_alloc_concrete.release_all_memory(true);
}

pub const U8BufSmall = StaticAllocBuffer.define(u8, &Self.small_block_alloc);
pub const U8BufMedium = StaticAllocBuffer.define(u8, &Self.medium_block_alloc);
pub const U8BufLarge = StaticAllocBuffer.define(u8, &Self.large_block_alloc);

pub const BufLoc = struct {
    start: u32,
    end: u32,

    pub inline fn new(start: u32, end: u32) BufLoc {
        return BufLoc{
            .start = start,
            .end = end,
        };
    }

    pub inline fn new_usize(start: usize, end: usize) BufLoc {
        return BufLoc{
            .start = @intCast(start),
            .end = @intCast(end),
        };
    }
};

pub const BufLocBufMedium = StaticAllocBuffer.define(BufLoc, &Self.medium_block_alloc);
