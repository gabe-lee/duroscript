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
    Global.notice_manager.log_all_notices();
    std.builtin.default_panic(msg, @errorReturnTrace(), @returnAddress());
}

pub fn main() !void {
    // Global = Global.init(std.haep.page_allocator);
    // defer Global.cleanup();
    // var args = try std.process.argsWithAllocator(Global.small_alloc);
    // _ = args.next(); // duro_path
    // var token_list = List(Token).initCapacity(Global.medium_alloc, 100) catch unreachable;
    // var source_buffer = List(u8).initCapacity(Global.medium_alloc, 1000) catch unreachable;
    // while (args.next()) |_| {
    //     // token_list.clearRetainingCapacity();
    //     // source_buffer.clearRetainingCapacity();
    //     // _ = SourceLexer.new(source_buffer.items, source_key);

    //     // TODO Parse tokens into AST
    // }
    // // TODO Evaluate AST
    // source_buffer.deinit(Global.medium_alloc);
    // token_list.deinit(Global.medium_alloc);
}

test "lexer output" {
    //CHECKPOINT init and implement source manager
    Global.init(std.heap.page_allocator);
    defer Global.cleanup();
    var source_manager = &Global.source_manager;
    // var program_rom = &Global.program_rom;
    // var ident_manager = &Global.ident_manager;
    // var notice_manager = &Global.notice_manager;

    var expected_buffer = Global.U8BufMedium.List.create();
    defer expected_buffer.release();
    var produced_buffer = Global.U8BufMedium.List.create();
    defer produced_buffer.release();
    var mismatch_list = Global.U8BufSmall.List.create();
    defer mismatch_list.release();
    var input_name = Global.U8BufSmall.List.create();
    defer input_name.release();
    var expected_name = Global.U8BufSmall.List.create();
    defer expected_name.release();
    var produced_name = Global.U8BufSmall.List.create();
    defer produced_name.release();
    var notices_name = Global.U8BufSmall.List.create();
    defer notices_name.release();
    // var lexing_failed: bool = false;
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
        expected_buffer.clear();
        produced_buffer.clear();
        input_name.clear();
        expected_name.clear();
        produced_name.clear();
        notices_name.clear();
        input_name.append_fmt_string("{s}/source.duro", .{entry.name});
        expected_name.append_fmt_string("{s}/tokens.expected", .{entry.name});
        produced_name.append_fmt_string("{s}/tokens.produced", .{entry.name});
        notices_name.append_fmt_string("{s}/notices.produced", .{entry.name});
        const complete_path = try lexer_test_folder.realpathAlloc(Global.small_alloc, input_name.slice());
        defer Global.small_alloc.free(complete_path);
        const source_key = source_manager.get_or_create_source_key(complete_path);
        source_manager.advance_source_to_lexed(source_key);
        const expected_file = try lexer_test_folder.openFile(expected_name.slice(), OpenFlags{ .mode = OpenMode.read_only });
        defer expected_file.close();
        const expected_file_size: u64 = (try expected_file.stat()).size;
        _ = expected_buffer.ensure_cap(expected_file_size);
        expected_buffer.grow_len_to_cap();
        _ = try expected_file.readAll(expected_buffer.slice());
        const produced_file = try Token.create_token_output_file(&lexer_test_folder, produced_name.slice(), &source_manager.stage_list.ptr[source_key].LEXED.token_list);
        defer produced_file.close();
        const produced_file_size: u64 = (try produced_file.stat()).size;
        _ = produced_buffer.ensure_cap(produced_file_size);
        produced_buffer.grow_len_to_cap();
        _ = try produced_file.readAll(produced_buffer.slice());
        //FIXME//CHECKPOINT find the infinite loop and fix
        // var produced_reader = SourceReader.new(1, produced_buffer.slice());
        // var expected_reader = SourceReader.new(0, expected_buffer.slice());
        // while (true) {
        //     produced_reader.skip_whitespace();
        //     expected_reader.skip_whitespace();
        //     if (produced_reader.curr.pos >= produced_reader.data.len and expected_reader.curr.pos >= expected_reader.data.len) {
        //         break;
        //     }
        //     const p_start = produced_reader.curr.pos;
        //     const e_start = expected_reader.curr.pos;
        //     const p_start_col = produced_reader.curr.col + 1;
        //     const p_start_row = produced_reader.curr.row + 1;
        //     produced_reader.skip_alpha_underscore();
        //     expected_reader.skip_alpha_underscore();
        //     if (produced_reader.curr.pos < produced_reader.data.len) {
        //         const p_next_byte = produced_reader.peek_next_byte();
        //         if (p_next_byte == ASC.L_PAREN) {
        //             produced_reader.skip_until_byte_match(ASC.R_PAREN);
        //         }
        //     }
        //     if (expected_reader.curr.pos < expected_reader.data.len) {
        //         const e_next_byte = expected_reader.peek_next_byte();
        //         if (e_next_byte == ASC.L_PAREN) {
        //             expected_reader.skip_until_byte_match(ASC.R_PAREN);
        //         }
        //     }
        //     const p_end = produced_reader.curr.pos;
        //     const e_end = expected_reader.curr.pos;
        //     var case_failed = false;
        //     if (p_end - p_start != e_end - e_start) case_failed = true;
        //     if (!case_failed) {
        //         for (produced_reader.data[p_start..p_end], expected_reader.data[e_start..e_end]) |p, e| {
        //             if (p != e) {
        //                 case_failed = true;
        //                 break;
        //             }
        //         }
        //     }
        //     if (case_failed) {
        //         lexing_failed = true;
        //         mismatch_list.append_fmt_string("LEXING TEST FAIL (TOKEN MISMATCH): ./test_sources/lexing/{s}:{d}:{d}\n\tEXP: {s}\n\tGOT: {s}\n", .{
        //             produced_name.slice(), p_start_row, p_start_col, expected_reader.data[e_start..e_end], produced_reader.data[p_start..p_end],
        //         });
        //     }
        // }
        // const notice_file = try lexer_test_folder.createFile(notices_name.slice(), std.fs.File.CreateFlags{
        //     .read = true,
        //     .exclusive = false,
        //     .truncate = true,
        // });
        // defer notice_file.close();
        // var notice_data = try Global.notice_manager.get_notice_list_kinds();
        // defer notice_data.release();
        // try notice_file.writeAll(notice_data.slice());
        // Global.notice_manager.clear();
    }
    // if (lexing_failed or mismatch_list.len > 0) {
    //     std.log.err("\n{s}", .{mismatch_list.slice()});
    //     return error.LexingTestFail;
    // }
}
