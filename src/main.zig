const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;

const sample_file_path = "/Users/gr.murray/Developer/zig/markdown-parser/samples/test.md";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const buffer = try readFileAlloc(allocator, sample_file_path);
    defer allocator.free(buffer);

    std.log.info("Read {} bytes into buffer\n", .{ buffer.len });

    var tokenizer = Tokenizer{
        .buffer = buffer[0..:0],
        .index = 0,
    };

    var token: Token = undefined;
    while (token.tag != .eof) {
        token = tokenizer.next();
        std.log.info("tokenized {s} ({}, {})", .{
            @tagName(token.tag),
            token.loc.start_index,
            token.loc.end_index
        });
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
