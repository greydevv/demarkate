const std = @import("std");
const ast = @import("ast.zig");

const Element = ast.Element;
const Span = ast.Span;

pub const Formatter = struct {
    source: [:0]const u8,

    pub fn init(source: [:0]const u8) Formatter {
        return .{
            .source = source
        };
    }

    pub fn format(self: *const Formatter, elements: []Element) !void {
        for (elements) |*el| {
            try self.formatElement(el);
        }
    }

    fn formatElement(self: *const Formatter, el: *Element) !void {
        switch (el.*) {
            .block_code => |*block_code| {

                for (block_code.children.items) |*child| {
                    switch (child.*) {
                        .code_literal => |*span| {
                            std.log.info("Formatting line of code: {s}", .{ span.slice(self.source) });
                            if (std.mem.startsWith(u8, " " ** 4, span.slice(self.source) )) {
                                return error.UnindentedCode;
                            } else {
                                span.start += 4;
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
            else => return
        }
    }

    fn stripSurroundingWhitespace(self: *const Formatter, span: *Span) void {
        const literal = span.slice(self.source);

        std.log.info("Starting char: {}\n", .{ literal[span.start] });

        while (literal[span.start] == ' ') {
            span.start += 1;
        }
    }
};

