const std = @import("std");
const pos = @import("pos.zig");
const ast = @import("ast.zig");

const Formatter = @This();

source: [:0]const u8,

const Error = error{ FormatError };

pub fn init(source: [:0]const u8) Formatter {
    return .{
        .source = source,
    };
}

pub fn format(self: *const Formatter, elements: []ast.Element) Error!void {
    var noop_next_line_break = false;
    for (elements) |*el| {
        if (el.* == ast.Element.line_break) {
            if (noop_next_line_break) {
                el.* = .noop;
            }

            noop_next_line_break = false;
        } else {
            noop_next_line_break = true;
        }

        try self.formatElement(el);
    }
}

fn formatElement(self: *const Formatter, el: *ast.Element) Error!void {
    switch (el.*) {
        .heading => |*heading| {
            if (heading.children.items.len > 0) {
                const child = &heading.children.items[0];
                if (child.* == ast.Element.text) {
                    self.stripLeadingWhitespace(&child.text);
                }
            }
        },
        .url => |*url| {
            self.stripSurroundingWhitespace(&url.href);
        },
        .img => |*img| {
            self.stripSurroundingWhitespace(&img.src);

            if (img.alt_text) |*alt| {
                self.stripSurroundingWhitespace(alt);

                if (alt.len() == 0) {
                    return error.FormatError;
                }
            }
        },
        else => return
    }
}

fn isWhitespace(self: *const Formatter, span: *pos.Span) bool {
    for (span.slice(self.source)) |char| {
        if (!std.ascii.isWhitespace(char)) {
            return false;
        }
    }

    return true;
}

fn stripLeadingWhitespace(self: *const Formatter, span: *pos.Span) void {
    if (span.len() == 0) {
        return;
    }

    const literal = span.slice(self.source);

    var new_start: usize = 0;
    while (new_start < literal.len and literal[new_start] == ' ') {
        new_start += 1;
    }

    span.start += new_start;
}

fn stripTrailingWhitespace(self: *const Formatter, span: *pos.Span) void {
    if (span.len() == 0) {
        return;
    }

    const literal = span.slice(self.source);

    var new_end: usize = 0;
    while (new_end < literal.len and literal[literal.len - 1 - new_end] == ' ') {
        new_end += 1;
    }

    span.end -= new_end;
}

fn stripSurroundingWhitespace(self: *const Formatter, span: *pos.Span) void {
    self.stripLeadingWhitespace(span);
    self.stripTrailingWhitespace(span);
}

test "strips leading whitespace from whitespace string" {
    const source: [:0]const u8 = "     ";
    var span = pos.Span{
        .start = 0,
        .end = 4
    };

    const formatter = Formatter.init(source);
    formatter.stripLeadingWhitespace(&span);

    try std.testing.expect(std.meta.eql(
        span,
        pos.Span{
            .start = 4,
            .end = 4
        }
    ));
}

test "strips trailing whitespace from whitespace string" {
    const source: [:0]const u8 = "     ";
    var span = pos.Span{
        .start = 0,
        .end = 4
    };

    const formatter = Formatter.init(source);
    formatter.stripTrailingWhitespace(&span);

    try std.testing.expect(std.meta.eql(
        span,
        pos.Span{
            .start = 0,
            .end = 0
        }
    ));
}
