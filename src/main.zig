const std = @import("std");
const dmk = @import("demarkate");
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const sample_file_path = "/Users/gr.murray/Developer/zig/markdown-parser/samples/test.md";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const buffer = try readFileAlloc(allocator, sample_file_path);
    defer allocator.free(buffer);

    std.log.info("Read {} bytes into buffer", .{ buffer.len });

    var tokenizer = dmk.Tokenizer.init(buffer[0..:0]);
    var tokens = std.ArrayList(dmk.Tokenizer.Token).init(allocator);
    defer tokens.deinit();

    while(true) {
        const token = tokenizer.next();
        try tokens.append(token);
        if (token.tag == .eof) break;
    }

    var parser = dmk.Parser.init(allocator, tokens.items);
    defer parser.deinit();
    parser.parse() catch {
        for (parser.errors.items) |e| {
            const msg = try e.allocMsg(allocator);
            std.log.err("{s}", .{ msg });
            allocator.free(msg);
        }

        return;
    };

    const formatter = dmk.Formatter.init(tokenizer.buffer);
    try formatter.format(parser.elements.items);

    for (parser.elements.items) |el| {
        try printAst(allocator, &el, 0, &tokenizer);
    }

    var renderer = dmk.HtmlRenderer.init(allocator, buffer[0..:0]);
    defer renderer.deinit();
    try renderer.render(parser.elements.items);

    std.debug.print("{s}\n", .{ renderer.buffer.items });
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

fn printAst(allocator: Allocator, el: *const dmk.ast.Element, depth: u32, tokenizer: *const dmk.Tokenizer) !void {
    const indent = try allocator.alloc(u8, depth * 2);
    defer allocator.free(indent);
    @memset(indent, ' ');

    switch(el.*) {
        .inline_code,
        .code_literal,
        .text => |span| {
            std.debug.print("{s}- {s}\n", .{
                indent,
                @tagName(el.*)
            });
            std.debug.print("  {s}  '{s}'\n", .{
                indent,
                span.slice(tokenizer.buffer)
            });
        },
        .line_break => {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
        },
        .heading => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, tokenizer);
            }
        },
        .paragraph => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, tokenizer);
            }
        },
        .url => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, tokenizer);
            }
        },
        .img => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, tokenizer);
            }
        },
        .block_code => |node| {
            std.debug.print("{s}- {s}", .{ indent, @tagName(el.*) });
            
            if (node.lang) |lang| {
                std.debug.print("({s})", .{ lang.slice(tokenizer.buffer) });
            }

            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, tokenizer);
            }
        },
        .modifier => |node| {
            std.debug.print("{s}- {s}({s})\n", .{ indent, @tagName(el.*), @tagName(node.tag) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, tokenizer);
            }
        }
    }
}
