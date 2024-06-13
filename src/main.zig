const std = @import("std");
const List = std.ArrayListUnmanaged;
const Token = @import("./Token.zig");
const TOK = Token.KIND;
const SourceLexer = @import("./SourceLexer.zig");
const ProgramROM = @import("./ProgramROM.zig");
const NoticeManager = @import("./NoticeManager.zig");
const IdentManager = @import("./IdentManager.zig");
const OpenFlags = std.fs.File.OpenFlags;
const CreateFlags = std.fs.File.CreateFlags;
const OpenMode = std.fs.File.OpenMode;

const ParsingAllocator = @import("./ParsingAllocator.zig");

pub fn main() !void {
    ParsingAllocator.global = ParsingAllocator.new_page();
    ProgramROM.global = ProgramROM.new(1);
    IdentManager.global = IdentManager.new();
    const alloc = ParsingAllocator.global.alloc;
    var args = try std.process.argsWithAllocator(alloc);
    _ = args.next(); // duro_path
    var token_list = List(Token).initCapacity(alloc, 100) catch unreachable;
    var source_buffer = List(u8).initCapacity(alloc, 1000) catch unreachable;
    var s_key: u16 = 1;
    while (args.next()) |arg| {
        token_list.clearRetainingCapacity();
        source_buffer.clearRetainingCapacity();
        const file = try std.fs.cwd().openFile(arg, OpenFlags{ .mode = OpenMode.read_only });
        defer file.close();
        const file_size: u64 = (try file.stat()).size;
        _ = try source_buffer.resize(alloc, file_size);
        _ = try file.readAll(source_buffer.items);

        var source_lexer = SourceLexer.new(source_buffer.items, arg, s_key);
        var cont = true;

        while (cont) {
            const token = source_lexer.next_token();
            if (token.kind == TOK.EOF) cont = false;
            try token_list.append(alloc, token);
        }
        try Token.dump_token_list(alloc, arg, &token_list); //DEBUG
        for (NoticeManager.Notices.error_list.items) |err| {
            std.log.err("\x1b[31m{s}\x1b[0m", .{err.string()});
        }
        for (NoticeManager.Notices.warn_list.items) |warn| {
            std.log.warn("\x1b[33m{s}\x1b[0m", .{warn.string()});
        }
        source_buffer.clearRetainingCapacity();
        token_list.clearRetainingCapacity();
        s_key += 1;
    }
    source_buffer.deinit(alloc);
    token_list.deinit(alloc);
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
