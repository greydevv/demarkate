const std = @import("std");

const Token = @This();

value: []const u8,
kind: Kind,

pub const Kind = enum {
    HEADING,
    INLINE_TEXT,
    NEWLINE,
    CODE_FENCE,
    UNKNOWN,
    EOF,
};

pub fn debugPrint(token: *const Token) void {
    std.debug.print("{s} {{\n", .{ @tagName(token.kind) });
    std.debug.print("  value: {s} ({})", .{ token.value, token.value.len });
    switch (token.kind) {
        .HEADING => std.debug.print("\n  level: {d}", .{ token.value.len }),
        else => {}
    }

    std.debug.print("\n}}\n", .{ });
}
