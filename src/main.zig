const std = @import("std");
const Tokenizer = @import("Tokenizer.zig");
const Parser = @import("Parser.zig");

const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Token = Tokenizer.Token;

const sample_file_path = "/Users/gr.murray/Developer/zig/markdown-parser/samples/test.md";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const buffer = try readFileAlloc(allocator, sample_file_path);
    defer allocator.free(buffer);

    std.log.info("Read {} bytes into buffer", .{ buffer.len });

    var tokenizer = Tokenizer.init(buffer[0..:0]);
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();
    while(true) {
        const token = tokenizer.next();
        try tokens.append(token);
        if (token.tag == .eof) break;
    }

    var parser = Parser.init(allocator, tokens.items);
    defer parser.deinit();
    try parser.parse();

    for (parser.elements.items) |el| {
        try printAst(allocator, &el, 0, &tokenizer);
    }
}

fn readFileAlloc(allocator: Allocator, file_path: []const u8) ![:0]u8 {
    const open_flags = File.OpenFlags { .mode = .read_only };
    const file = try std.fs.openFileAbsolute(file_path, open_flags);
    defer file.close();

    return try file.readToEndAllocOptions(
        allocator,
        8192,
        null,
        @alignOf(u8),
        0
    );
}

const Element = @import("ast.zig").Element;

fn printAst(allocator: Allocator, el: *const Element, depth: u32, tokenizer: *const Tokenizer) !void {
    const indent = try allocator.alloc(u8, depth * 2);
    defer allocator.free(indent);
    @memset(indent, ' ');

    switch(el.*) {
        .node => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(node.tag) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, tokenizer);
            }
        },
        .leaf => |leaf| {
            if (leaf.tag == .text or leaf.tag == .code_literal) {
                const token = &leaf.token;
                std.debug.print("{s}- {s} ({s})\n", .{
                    indent,
                    @tagName(leaf.tag),
                    token.slice(tokenizer.buffer),
                });
            } else {
                std.debug.print("{s}- {s}\n", .{ indent, @tagName(leaf.tag) });
            }
        }
    }
}


















