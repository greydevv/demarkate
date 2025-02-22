const std = @import("std");
const Lexer = @import("lexer.zig");
const File = std.fs.File;
const Token = @import("Token.zig");

const sample_file_path = "/Users/gr.murray/Developer/zig/markdown-parser/samples/test.md";
const FileIoError = File.OpenError || File.ReadError;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const source_buf = try allocator.alloc(u8, 400);
    defer allocator.free(source_buf);
    try readFile(sample_file_path, source_buf);

    const lexer = try Lexer.init(allocator, source_buf);
    defer lexer.deinit(allocator);

    var token: Token = lexer.nextToken();
    while (token.kind != .EOF) {
        token = lexer.nextToken();
    }
}

fn readFile(file_path: []const u8, buffer: []u8) FileIoError!void {
    const open_flags = File.OpenFlags { .mode = .read_only };

    const file = try std.fs.openFileAbsolute(file_path, open_flags);
    defer file.close();

    _ = try file.readAll(buffer);
}

