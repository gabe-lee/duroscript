const std = @import("std");
const List = std.ArrayListUnmanaged;
const Token = @import("./Token.zig");
const TOK = Token.KIND;
const SourceLexer = @import("./SourceLexer.zig");
const ProgramROM = @import("./ProgramROM.zig");
const NoticeManager = @import("./NoticeManager.zig");
const IdentManager = @import("./IdentManager.zig");
const SourceManager = @import("./SourceManager.zig");
const OpenFlags = std.fs.File.OpenFlags;
const CreateFlags = std.fs.File.CreateFlags;
const OpenMode = std.fs.File.OpenMode;
const SourceReader = @import("./SourceReader.zig");
const OpenDirOptions = std.fs.Dir.OpenDirOptions;
const ParsingAllocator = @import("./ParsingAllocator.zig");
const ASC = @import("./Unicode.zig").ASCII;

pub fn panic(msg: []const u8) noreturn {
    @setCold(true);
    NoticeManager.global.log_all_notices();
    std.builtin.default_panic(msg, @errorReturnTrace(), @returnAddress());
}

pub fn main() !void {
    ParsingAllocator.global = ParsingAllocator.new();
    defer ParsingAllocator.global.cleanup();
    ProgramROM.global = ProgramROM.new(1);
    defer ProgramROM.global.cleanup();
    IdentManager.global = IdentManager.new();
    defer IdentManager.global.cleanup();
    SourceManager.global = SourceManager.new();
    defer SourceManager.global.cleanup();
    const alloc = ParsingAllocator.global.alloc;
    var args = try std.process.argsWithAllocator(alloc);
    _ = args.next(); // duro_path
    var token_list = List(Token).initCapacity(alloc, 100) catch unreachable;
    var source_buffer = List(u8).initCapacity(alloc, 1000) catch unreachable;
    while (args.next()) |arg| {
        token_list.clearRetainingCapacity();
        source_buffer.clearRetainingCapacity();
        const full_file_path = try std.fs.cwd().realpathAlloc(alloc, arg);
        defer alloc.free(full_file_path);
        const source_key = SourceManager.global.get_source_key(full_file_path);
        const file = try std.fs.openFileAbsolute(full_file_path, OpenFlags{ .mode = OpenMode.read_only });
        defer file.close();
        const file_size: u64 = (try file.stat()).size;
        _ = try source_buffer.resize(alloc, file_size);
        _ = try file.readAll(source_buffer.items);
        var source_lexer = SourceLexer.new(source_buffer.items, source_key);
        
        // TODO Parse tokens into AST
    }
    // TODO Evaluate AST
    source_buffer.deinit(alloc);
    token_list.deinit(alloc);
}

test "lexer output" {
    //CHECKPOINT init and implement source manager
    ParsingAllocator.global = ParsingAllocator.new();
    defer ParsingAllocator.global.cleanup();
    ProgramROM.global = ProgramROM.new(1);
    defer ProgramROM.global.cleanup();
    IdentManager.global = IdentManager.new();
    defer IdentManager.global.cleanup();
    SourceManager.global = SourceManager.new();
    defer SourceManager.global.cleanup();
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
        const notices_name = try std.fmt.allocPrint(alloc, "{s}/notices.produced", .{entry.name});
        defer alloc.free(notices_name);
        token_list.clearRetainingCapacity();
        source_buffer.clearRetainingCapacity();
        expected_buffer.clearRetainingCapacity();
        const input_full_path = try lexer_test_folder.realpathAlloc(alloc, input_name);
        defer alloc.free(input_full_path);
        const source_key = SourceManager.global.get_source_key(input_full_path);
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
        var source_lexer = SourceLexer.new(source_buffer.items, source_key);
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
            if (produced_reader.curr.pos >= produced_reader.data.len and expected_reader.curr.pos >= expected_reader.data.len) {
                break;
            }
            const p_start = produced_reader.curr.pos;
            const e_start = expected_reader.curr.pos;
            const p_start_col = produced_reader.curr.col + 1;
            const p_start_row = produced_reader.curr.row + 1;
            produced_reader.skip_alpha_underscore();
            expected_reader.skip_alpha_underscore();
            if (produced_reader.curr.pos < produced_reader.data.len) {
                const p_next_byte = produced_reader.peek_next_byte();
                if (p_next_byte == ASC.L_PAREN) {
                    produced_reader.skip_until_byte_match(ASC.R_PAREN);
                }
            }
            if (expected_reader.curr.pos < expected_reader.data.len) {
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
                for (produced_reader.data[p_start..p_end], expected_reader.data[e_start..e_end]) |p, e| {
                    if (p != e) {
                        case_failed = true;
                        break;
                    }
                }
            }
            if (case_failed) {
                lexing_failed = true;
                const mismatch_msg = try std.fmt.allocPrint(alloc, "TOKEN MISMATCH: ./test_sources/lexing/{s}:{d}:{d}\n\tEXP: {s}\n\tGOT: {s}\n", .{
                    produced_name, p_start_row, p_start_col, expected_reader.data[e_start..e_end], produced_reader.data[p_start..p_end],
                });
                try mismatch_list.appendSlice(alloc, mismatch_msg);
            }
        }
        const notice_file = try lexer_test_folder.createFile(notices_name, std.fs.File.CreateFlags{
            .read = true,
            .exclusive = false,
            .truncate = true,
        });
        defer notice_file.close();
        const notice_data = try NoticeManager.global.dump_notice_list_kinds();
        notice_file.writeAll(notice_data);
        NoticeManager.global.alloc.free(notice_data);
        s_key += 1;
    }
    if (lexing_failed or mismatch_list.items.len > 0) {
        std.log.err("\n{s}", .{mismatch_list.items});
        return error.LexingTestFail;
    }
}
