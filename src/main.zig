const std = @import("std");
const List = std.ArrayListUnmanaged;
const Token = @import("./Token.zig");
const TOK = Token.KIND;
const SourceLexer = @import("./SourceLexer.zig");
const OpenFlags = std.fs.File.OpenFlags;
const CreateFlags = std.fs.File.CreateFlags;
const OpenMode = std.fs.File.OpenMode;
const SourceReader = @import("./SourceReader.zig");
const OpenDirOptions = std.fs.Dir.OpenDirOptions;
const ASC = @import("./Unicode.zig").ASCII;

const Global = @import("./Global.zig");

pub fn panic(msg: []const u8) noreturn {
    @setCold(true);
    Global.g.notice_manager.log_all_notices();
    std.builtin.default_panic(msg, @errorReturnTrace(), @returnAddress());
}

pub fn main() !void {
    Global.g = Global.init(std.haep.page_allocator);
    defer Global.g.cleanup();
    var args = try std.process.argsWithAllocator(Global.g.small_alloc);
    _ = args.next(); // duro_path
    var token_list = List(Token).initCapacity(Global.g.medium_alloc, 100) catch unreachable;
    var source_buffer = List(u8).initCapacity(Global.g.medium_alloc, 1000) catch unreachable;
    while (args.next()) |_| {
        // token_list.clearRetainingCapacity();
        // source_buffer.clearRetainingCapacity();
        // _ = SourceLexer.new(source_buffer.items, source_key);

        // TODO Parse tokens into AST
    }
    // TODO Evaluate AST
    source_buffer.deinit(Global.g.medium_alloc);
    token_list.deinit(Global.g.medium_alloc);
}

test "lexer output" {
    //CHECKPOINT init and implement source manager
    Global.g = Global.init(std.heap.page_allocator);
    defer Global.g.cleanup();
    const large_alloc = Global.g.large_alloc;
    const medium_alloc = Global.g.medium_alloc;
    const small_alloc = Global.g.small_alloc;
    var source_manager = &Global.g.source_manager;
    // var program_rom = &Global.g.program_rom;
    // var ident_manager = &Global.g.ident_manager;
    var notice_manager = &Global.g.notice_manager;
    var token_list = List(Token).initCapacity(medium_alloc, 1024) catch unreachable;
    defer token_list.deinit(medium_alloc);
    var source_buffer = List(u8).initCapacity(large_alloc, 4096) catch unreachable;
    defer source_buffer.deinit(large_alloc);
    var expected_buffer = List(u8).initCapacity(large_alloc, 4096) catch unreachable;
    defer expected_buffer.deinit(large_alloc);
    var mismatch_list = List(u8).initCapacity(small_alloc, 256) catch unreachable;
    defer mismatch_list.deinit(small_alloc);
    var lexing_failed: bool = false;
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
        const input_name = try std.fmt.allocPrint(small_alloc, "{s}/source.duro", .{entry.name});
        defer small_alloc.free(input_name);
        const expected_name = try std.fmt.allocPrint(small_alloc, "{s}/tokens.expected", .{entry.name});
        defer small_alloc.free(expected_name);
        const produced_name = try std.fmt.allocPrint(small_alloc, "{s}/tokens.produced", .{entry.name});
        defer small_alloc.free(produced_name);
        const notices_name = try std.fmt.allocPrint(small_alloc, "{s}/notices.produced", .{entry.name});
        defer small_alloc.free(notices_name);
        token_list.clearRetainingCapacity();
        source_buffer.clearRetainingCapacity();
        expected_buffer.clearRetainingCapacity();
        const input_full_path = try lexer_test_folder.realpathAlloc(small_alloc, input_name);
        defer small_alloc.free(input_full_path);
        const source_key = source_manager.get_source_key(input_full_path);
        const input_file = try lexer_test_folder.openFile(input_name, OpenFlags{ .mode = OpenMode.read_only });
        defer input_file.close();
        const input_file_size: u64 = (try input_file.stat()).size;
        _ = try source_buffer.resize(large_alloc, input_file_size);
        _ = try input_file.readAll(source_buffer.items);
        const expected_file = try lexer_test_folder.openFile(expected_name, OpenFlags{ .mode = OpenMode.read_only });
        defer expected_file.close();
        const expected_file_size: u64 = (try expected_file.stat()).size;
        _ = try expected_buffer.resize(large_alloc, expected_file_size);
        _ = try expected_file.readAll(expected_buffer.items);
        var source_lexer = SourceLexer.new(source_buffer.items, source_key);
        var cont = true;
        while (cont) {
            const token = source_lexer.next_token();
            if (token.kind == TOK.EOF) cont = false;
            try token_list.append(medium_alloc, token);
        }
        source_buffer.clearRetainingCapacity();
        const produced_file = try Token.create_token_output_file(large_alloc, &lexer_test_folder, produced_name, &token_list);
        defer produced_file.close();
        const produced_file_size: u64 = (try produced_file.stat()).size;
        _ = try source_buffer.resize(large_alloc, produced_file_size);
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
                const mismatch_msg = try std.fmt.allocPrint(small_alloc, "TOKEN MISMATCH: ./test_sources/lexing/{s}:{d}:{d}\n\tEXP: {s}\n\tGOT: {s}\n", .{
                    produced_name, p_start_row, p_start_col, expected_reader.data[e_start..e_end], produced_reader.data[p_start..p_end],
                });
                defer small_alloc.free(mismatch_msg);
                try mismatch_list.appendSlice(small_alloc, mismatch_msg);
            }
        }
        const notice_file = try lexer_test_folder.createFile(notices_name, std.fs.File.CreateFlags{
            .read = true,
            .exclusive = false,
            .truncate = true,
        });
        defer notice_file.close();
        const notice_data = try notice_manager.get_notice_list_kinds();
        notice_file.writeAll(notice_data);
        notice_manager.alloc.free(notice_data);
        s_key += 1;
    }
    if (lexing_failed or mismatch_list.items.len > 0) {
        std.log.err("\n{s}", .{mismatch_list.items});
        return error.LexingTestFail;
    }
}
