const std = @import("std");
const fs = @import("std").fs;

pub fn main() !void {
    const file = fs.openFileAbsolute(
        "/Users/gr.murray/Developer/zig/markdown-parser/samples/test.md",
        .{ .mode = .read_only }
    ) catch |e| {
        std.debug.print("Failed to open file: {},", .{ e });
        return;
    };

    defer file.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }

    const allocator = gpa.allocator();
    const buffer: []u8 = try allocator.alloc(u8, 400);
    defer allocator.free(buffer);

    const n_bytes_read = try file.read(buffer);

    std.debug.print("Read {d} bytes from the file.\n", .{ n_bytes_read });
    std.debug.print("{s}", .{ buffer });
}

