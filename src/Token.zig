const std = @import("std");

const Token = @This();

value: []const u8,
kind: Kind,

pub const Kind = enum {
    HEADING,
    INLINE_TEXT,
    NEWLINE,
    CODE_FENCE,
    ASTERISK,
    UNKNOWN,
    EOF,
};

pub fn debugPrint(token: *const Token) void {
    if (token.kind == .NEWLINE or token.kind == .EOF) {
        std.debug.print("{s} ({d})\n", .{ @tagName(token.kind), token.value.len });
        return;
    }

    std.debug.print("{s} {{\n", .{ @tagName(token.kind) });
    std.debug.print("  value: {s} ({})", .{ token.value, token.value.len });
    switch (token.kind) {
        .HEADING => std.debug.print("\n  level: {d}", .{ token.value.len }),
        else => {}
    }

    std.debug.print("\n}}\n", .{ });
}
