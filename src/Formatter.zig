const std = @import("std");
const pos = @import("pos.zig");
const ast = @import("ast.zig");

const Formatter = @This();

source: [:0]const u8,

const Error = error{ FormatError };

pub fn init(source: [:0]const u8) Formatter {
    return .{
        .source = source
    };
}

pub fn format(self: *const Formatter, elements: []ast.Element) Error!void {
    for (elements) |*el| {
        try self.formatElement(el);
    }
}

fn formatElement(self: *const Formatter, el: *ast.Element) Error!void {
    switch (el.*) {
        .paragraph => |*paragraph| {
            return self.format(paragraph.children.items);
        },
        .heading => |*heading| {
            if (heading.children.items.len > 0) {
                const child = &heading.children.items[0];
                if (child.* == ast.Element.text) {
                    self.stripLeadingWhitespace(&child.text);
                }
            }
        },
        .block_code => |*block_code| {
            for (block_code.children.items) |*child| {
                switch (child.*) {
                    .code_literal => |*span| {
                        if (std.mem.startsWith(u8, span.slice(self.source), " " ** 4)) {
                            span.start += 4;
                        } else {
                            return error.FormatError;
                        }
                    },
                    .line_break => continue,
                    else => unreachable,
                }
            }
        },
        .url => |*url| {
            self.stripSurroundingWhitespace(&url.href);
        },
        .img => |*img| {
            self.stripSurroundingWhitespace(&img.src);
        },
        else => return
    }
}

fn stripLeadingWhitespace(self: *const Formatter, span: *pos.Span) void {
    const literal = span.slice(self.source);

    var new_start: usize = 0;
    while (literal[new_start] == ' ') {
        new_start += 1;
    }

    span.start += new_start;
}

fn stripTrailingWhitespace(self: *const Formatter, span: *pos.Span) void {
    const literal = span.slice(self.source);

    var new_end: usize = 0;
    while (literal[literal.len - 1 - new_end] == ' ') {
        new_end += 1;
    }

    span.end -= new_end;
}

fn stripSurroundingWhitespace(self: *const Formatter, span: *pos.Span) void {
    self.stripLeadingWhitespace(span);
    self.stripTrailingWhitespace(span);
}
