const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const PooledBlockAllocator = @import("./PooledBlockAllocator.zig");
const IdentManager = @import("./IdentManager.zig");
const NoticeManager = @import("./NoticeManager.zig");
const ProgramROM = @import("./ProgramROM.zig");
const SourceManager = @import("./SourceManager.zig");

const Self = @This();

pub var g: Self = undefined;

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

root_alloc: Allocator,
large_alloc: Allocator,
large_alloc_concrete: LargeAlloc,
medium_alloc: Allocator,
medium_alloc_concrete: MediumAlloc,
small_alloc: Allocator,
small_alloc_concrete: SmallAlloc,
ident_manager: IdentManager,
notice_manager: NoticeManager,
program_rom: ProgramROM,
source_manager: SourceManager,

pub fn init(root_alloc: Allocator) Self {
    const large = LargeAlloc.new(root_alloc);
    const large_alloc = large.allocator();
    const medium = MediumAlloc.new(large_alloc);
    const medium_alloc = medium.allocator();
    const small = SmallAlloc.new(medium_alloc);
    const small_alloc = small.allocator();
    return Self{
        .root_alloc = root_alloc,
        .large_alloc = large_alloc,
        .large_alloc_concrete = large,
        .medium_alloc = medium_alloc,
        .medium_alloc_concrete = medium,
        .small_alloc = small_alloc,
        .small_alloc_concrete = small,
        .ident_manager = IdentManager.new(medium_alloc),
        .notice_manager = NoticeManager.new(medium_alloc),
        .program_rom = ProgramROM.new(medium_alloc),
        .source_manager = SourceManager.new(large_alloc),
    };
}

pub fn cleanup(self: *Self) void {
    self.source_manager.cleanup();
    self.program_rom.cleanup();
    self.notice_manager.cleanup();
    self.ident_manager.cleanup();
    self.small_alloc_concrete.release_all_memory();
    self.medium_alloc_concrete.release_all_memory();
    self.large_alloc_concrete.release_all_memory();
}
