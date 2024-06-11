const std = @import("std");
const ListUm = std.ArrayListUnmanaged;
const Token = @import("./Token.zig");
const TOK = Token.KIND;
const SourceLexer = @import("./SourceLexer.zig");
const ProgramROM = @import("./ProgramROM.zig");
const OpenFlags = std.fs.File.OpenFlags;
const OpenMode = std.fs.File.OpenMode;

const ParsingAllocator = @import("./ParsingAllocator.zig");

pub fn main() !void {
    ParsingAllocator.global = ParsingAllocator.new();
    ProgramROM.global = ProgramROM.new(1);
    const alloc = ParsingAllocator.global.alloc;
    var args = try std.process.argsWithAllocator(alloc);
    std.debug.print("A", .{});
    var token_list = ListUm(Token).initCapacity(alloc, 100) catch @panic("bad");
    std.debug.print("B", .{});
    var source_buffer = ListUm(u8).initCapacity(alloc, 1000) catch @panic("bad2");
    std.debug.print("C", .{});
    var s_key: u16 = 1;
    while (args.next()) |arg| {
        token_list.clearRetainingCapacity();
        source_buffer.clearRetainingCapacity();
        const file = try std.fs.cwd().openFile(arg, OpenFlags{ .mode = OpenMode.read_only });
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
        // TODO Print out tokens in plain text
        source_buffer.clearRetainingCapacity();
        token_list.clearRetainingCapacity();
        file.close();
        s_key += 1;
    }
    source_buffer.deinit(alloc);
    token_list.deinit(alloc);

    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
