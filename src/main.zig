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
const SourceReader = @import("./SourceReader.zig");
const OpenDirOptions = std.fs.Dir.OpenDirOptions;
const ParsingAllocator = @import("./ParsingAllocator.zig");
const ASC = @import("./Unicode.zig").ASCII;

pub fn main() !void {
    ParsingAllocator.global = ParsingAllocator.new();
    defer ParsingAllocator.global.cleanup();
    ProgramROM.global = ProgramROM.new(1);
    defer ProgramROM.global.cleanup();
    IdentManager.global = IdentManager.new();
    defer IdentManager.global.cleanup();
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
        for (NoticeManager.Notices.error_list.items) |err| {
            std.log.err("\x1b[31m{s}\x1b[0m", .{err.string()});
        }
        for (NoticeManager.Notices.warn_list.items) |warn| {
            std.log.warn("\x1b[33m{s}\x1b[0m", .{warn.string()});
        }
        // TODO Parse tokens into AST
        s_key += 1;
    }
    // TODO Evaluate AST
    source_buffer.deinit(alloc);
    token_list.deinit(alloc);
}

test "lexer output" {
    ParsingAllocator.global = ParsingAllocator.new();
    defer ParsingAllocator.global.cleanup();
    ProgramROM.global = ProgramROM.new(1);
    defer ProgramROM.global.cleanup();
    IdentManager.global = IdentManager.new();
    defer IdentManager.global.cleanup();
    var lexing_failed = false;
    const alloc = ParsingAllocator.global.alloc;
    var token_list = List(Token).initCapacity(alloc, 100) catch unreachable;
    defer token_list.deinit(alloc);
    var source_buffer = List(u8).initCapacity(alloc, 1000) catch unreachable;
    defer source_buffer.deinit(alloc);
    var expected_buffer = List(u8).initCapacity(alloc, 1000) catch unreachable;
    defer expected_buffer.deinit(alloc);
    var mismatch_list = List(u8).initCapacity(alloc, 100) catch unreachable;
    defer mismatch_list.deinit(alloc);
    var s_key: u16 = 1;
    const lexer_test_folder = try std.fs.cwd().openDir("./test_sources/lexing", OpenDirOptions{
        .access_sub_paths = true,
        .iterate = true,
        .no_follow = true,
    });
    var lexer_tests = lexer_test_folder.iterateAssumeFirstIteration();
    while (try lexer_tests.next()) |entry| {
        if (entry.kind != std.fs.File.Kind.directory) {
            continue;
        }
        const input_name = try std.fmt.allocPrint(alloc, "{s}/source.duro", .{entry.name});
        defer alloc.free(input_name);
        const expected_name = try std.fmt.allocPrint(alloc, "{s}/tokens.expected", .{entry.name});
        defer alloc.free(expected_name);
        const produced_name = try std.fmt.allocPrint(alloc, "{s}/tokens.produced", .{entry.name});
        defer alloc.free(produced_name);
        token_list.clearRetainingCapacity();
        source_buffer.clearRetainingCapacity();
        expected_buffer.clearRetainingCapacity();

        const input_file = try lexer_test_folder.openFile(input_name, OpenFlags{ .mode = OpenMode.read_only });
        defer input_file.close();
        const input_file_size: u64 = (try input_file.stat()).size;
        _ = try source_buffer.resize(alloc, input_file_size);
        _ = try input_file.readAll(source_buffer.items);
        const expected_file = try lexer_test_folder.openFile(expected_name, OpenFlags{ .mode = OpenMode.read_only });
        defer expected_file.close();
        const expected_file_size: u64 = (try expected_file.stat()).size;
        _ = try expected_buffer.resize(alloc, expected_file_size);
        _ = try expected_file.readAll(expected_buffer.items);
        var source_lexer = SourceLexer.new(source_buffer.items, input_name, s_key);
        var cont = true;
        while (cont) {
            const token = source_lexer.next_token();
            if (token.kind == TOK.EOF) cont = false;
            try token_list.append(alloc, token);
        }
        source_buffer.clearRetainingCapacity();
        const produced_file = try Token.create_token_output_file(alloc, &lexer_test_folder, produced_name, &token_list);
        defer produced_file.close();
        const produced_file_size: u64 = (try produced_file.stat()).size;
        _ = try source_buffer.resize(alloc, produced_file_size);
        _ = try produced_file.readAll(source_buffer.items);
        var produced_reader = SourceReader.new(produced_name, source_buffer.items);
        var expected_reader = SourceReader.new(expected_name, expected_buffer.items);
        cont = true;
        while (true) {
            produced_reader.skip_whitespace();
            expected_reader.skip_whitespace();
            if (produced_reader.curr.pos >= produced_reader.source.len and expected_reader.curr.pos >= expected_reader.source.len) {
                break;
            }
            // std.debug.print("LOOP\nP: {d} < {d}\nE: {d} < {d}\n", .{ produced_reader.curr.pos, produced_reader.source.len, expected_reader.curr.pos, expected_reader.source.len }); //DEBUG
            const p_start = produced_reader.curr.pos;
            const e_start = expected_reader.curr.pos;
            const p_start_col = produced_reader.curr.col + 1;
            const p_start_row = produced_reader.curr.row + 1;
            produced_reader.skip_alpha_underscore();
            expected_reader.skip_alpha_underscore();
            if (produced_reader.curr.pos < produced_reader.source.len) {
                const p_next_byte = produced_reader.peek_next_byte();
                if (p_next_byte == ASC.L_PAREN) {
                    produced_reader.skip_until_byte_match(ASC.R_PAREN);
                }
            }
            if (expected_reader.curr.pos < expected_reader.source.len) {
                const e_next_byte = expected_reader.peek_next_byte();
                if (e_next_byte == ASC.L_PAREN) {
                    expected_reader.skip_until_byte_match(ASC.R_PAREN);
                }
            }
            const p_end = produced_reader.curr.pos;
            const e_end = expected_reader.curr.pos;
            var case_failed = false;
            if (p_end - p_start != e_end - e_start) case_failed = true;
            if (!case_failed) {
                for (produced_reader.source[p_start..p_end], expected_reader.source[e_start..e_end]) |p, e| {
                    if (p != e) {
                        case_failed = true;
                        break;
                    }
                }
            }
            // std.debug.print("LOOP\nE: {s}\nP: {s}\n", .{ expected_reader.source[e_start..e_end], produced_reader.source[p_start..p_end] }); //DEBUG

            if (case_failed) {
                lexing_failed = true;
                const mismatch_msg = try std.fmt.allocPrint(alloc, "TOKEN MISMATCH: ./test_sources/lexing/{s}:{d}:{d}\n\tEXP: {s}\n\tGOT: {s}\n", .{
                    produced_name, p_start_row, p_start_col, expected_reader.source[e_start..e_end], produced_reader.source[p_start..p_end],
                });
                try mismatch_list.appendSlice(alloc, mismatch_msg);
            }
        }
        // TODO also test output notices
        s_key += 1;
    }
    if (lexing_failed or mismatch_list.items.len > 0) {
        std.log.err("\n{s}", .{mismatch_list.items});
        return error.LexingTestFail;
    }
}
