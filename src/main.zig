const std = @import("std");
const Lexer = @import("lexer.zig");
const Token = @import("Token.zig");

const file_path = "/Users/gr.murray/Developer/zig/markdown-parser/samples/test.md";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const lexer = try Lexer.init(allocator, file_path);
    defer lexer.deinit(allocator);

    for (lexer.file_contents) |char| {
        std.debug.print("{d}\n", .{ char });
    }

    var token: Token = lexer.nextToken();
    while (token.kind != .EOF) {
        token = lexer.nextToken();
    }
}
