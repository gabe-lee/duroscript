const std = @import("std");
const GpaBuilder = std.heap.GeneralPurposeAllocator;
const GpaConfig = std.heap.GeneralPurposeAllocatorConfig;

var Global = GpaBuilder(GpaConfig{}){};
