const std = @import("std");
const dmk = @import("demarkate");

const sample_file_path = "/Users/gr.murray/Developer/zig/demarkate/samples/test.md";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const source = try readFileAlloc(allocator, sample_file_path);
    defer allocator.free(source);

    const document = try dmk.parseBytes(allocator, source);
    defer document.deinit();

    for (document.elements) |el| {
        try printAst(allocator, &el, 0, source);
    }

    var renderer = dmk.HtmlRenderer.init(allocator, source);
    defer renderer.deinit();
    try renderer.render(document.elements);

    std.debug.print("{s}\n", .{ renderer.buffer.items });
}

fn readFileAlloc(allocator: std.mem.Allocator, file_path: []const u8) ![:0]u8 {
    const open_flags = std.fs.File.OpenFlags { .mode = .read_only };
    const file = try std.fs.openFileAbsolute(file_path, open_flags);
    defer file.close();

    return try file.readToEndAllocOptions(
        allocator,
        8192,
        null,
        std.mem.Alignment.@"1",
        0
    );
}

fn printAst(allocator: std.mem.Allocator, el: *const dmk.ast.Element, depth: u32, source: [:0]const u8) !void {
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
                span.slice(source)
            });
        },
        .line_break => {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
        },
        .heading => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, source);
            }
        },
        .callout => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, source);
            }
        },
        .url => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });
            std.debug.print("  - {s}'{s}'\n", .{ indent, node.href.slice(source) });

            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, source);
            }
        },
        .img => |node| {
            std.debug.print("{s}- {s}\n", .{ indent, @tagName(el.*) });

            if (node.alt_text) |alt_text| {
                std.debug.print("  - {s}'{s}'\n", .{ indent, alt_text.slice(source) });
            }

            std.debug.print("  - {s}'{s}'\n", .{ indent, node.src.slice(source) });
        },
        .block_code => |node| {
            std.debug.print("{s}- {s}", .{ indent, @tagName(el.*) });
            if (node.lang) |lang| {
                std.debug.print("({s})", .{ lang.slice(source) });
            }

            std.debug.print("\n", .{});

            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, source);
            }
        },
        .modifier => |node| {
            std.debug.print("{s}- {s}({s})\n", .{ indent, @tagName(el.*), @tagName(node.tag) });
            for (node.children.items) |child| {
                try printAst(allocator, &child, depth + 1, source);
            }
        },
        .noop => {},
    }
}
