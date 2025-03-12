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
    var parser = Parser.init(allocator, &tokenizer);
    defer parser.deinit();
    try parser.parse();

    for (parser.elements.items) |el| {
        try printAst(allocator, &el, 0, &tokenizer);
    }

    // var token: Token = undefined;
    // while (token.tag != .eof) {
    //     token = tokenizer.next();
    //     std.log.info("tokenized {s} ({}, {})", .{
    //         @tagName(token.tag),
    //         token.loc.start_index,
    //         token.loc.end_index
    //     });
    // }
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
            if (leaf.tag == .text) {
                const token = &leaf.token;
                std.debug.print("{s}- {s} ({s})\n", .{
                    indent,
                    @tagName(leaf.tag),
                    tokenizer.buffer[token.loc.start_index..token.loc.end_index]
                });
            } else {
                std.debug.print("{s}- {s}\n", .{ indent, @tagName(leaf.tag) });
            }
        }
    }
}


















