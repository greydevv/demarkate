const std = @import("std");
const ast = @import("ast.zig");

const Diagnostic = @This();

spans: std.ArrayList(ast.Span),
line: usize,

pub fn init(msg: []const u8, allocator: std.mem.Allocator) Diagnostic {
    return .{
        .spans = .init(allocator),
        .line = undefined
    };
}
