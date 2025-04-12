const std = @import("std");
const Token = @import("../Tokenizer.zig").Token;

const Element = @import("../ast.zig").Element;
const Span = @import("../ast.zig").Span;

const allocator = std.testing.allocator;

pub fn free(ast: std.ArrayList(Element)) void {
    for (ast.items) |el| {
        el.deinit();
    }

    ast.deinit();
}

pub const AstBuilder = struct {
    elements: std.ArrayList(Element),

    pub fn init() *AstBuilder {
        const builder = allocator.create(AstBuilder) catch unreachable;
        builder.* = .{
            .elements = std.ArrayList(Element).init(allocator)
        };

        return builder;
    }

    pub fn block_code(self: *AstBuilder, children: std.ArrayList(Element)) *AstBuilder {
        const el = Element{
            .block_code = .{
                .children = children
            }
        };

        self.elements.append(el) catch unreachable;
        return self;
    }

    pub fn paragraph(self: *AstBuilder, children: std.ArrayList(Element)) *AstBuilder {
        const el = Element{
            .paragraph = .{
                .children = children
            }
        };

        return self.node(el);
    }

    pub fn modifier(self: *AstBuilder, tag: Element.Modifier.Tag, children: std.ArrayList(Element)) *AstBuilder {
        const el = Element{
            .modifier = .{
                .children = children,
                .tag = tag,
            }
        };

        return self.node(el);
    }

    pub fn text(self: *AstBuilder, token: Token) *AstBuilder {
        return self.leaf(@tagName(Element.text), token);
    }

    fn node(self: *AstBuilder, el: Element) *AstBuilder {
        self.elements.append(el) catch unreachable;
        return self;
    }

    fn leaf(self: *AstBuilder, comptime tag_name: []const u8, token: Token) *AstBuilder {
        self.elements.append(
            @unionInit(
                Element,
                tag_name,
                Span.from(token)
            )
        ) catch unreachable;

        return self;
    }

    pub fn build(self: *AstBuilder) std.ArrayList(Element) {
        defer allocator.destroy(self);
        return self.elements;
    }
};

pub fn expectEqual(expected_ast: std.ArrayList(Element), actual_ast: std.ArrayList(Element)) !void {
    if (expected_ast.items.len != actual_ast.items.len) {
        return error.TestExpectedEqual;
    }

    for (expected_ast.items, actual_ast.items) |expected, actual| {
        if (std.meta.activeTag(expected) != std.meta.activeTag(actual)) {
            return error.TestExpectedEqual;
        }

        switch (expected) {
            .heading => |heading| {
                try expectEqual(heading.children, actual.heading.children);
            },
            .paragraph => |paragraph| {
                try expectEqual(paragraph.children, actual.paragraph.children);
            },
            .block_code => |block_code| {
                try expectEqual(block_code.children, actual.block_code.children);
            },
            .modifier => |modifier| {
                if (!std.meta.eql(modifier.tag, actual.modifier.tag)) {
                    return error.TestExpectedEqual;
                }

                try expectEqual(modifier.children, actual.modifier.children);
            },
            .img => |img| {
                if (!std.meta.eql(img.url, actual.img.url)) {
                    return error.TestExpectedEqual;
                }

                try expectEqual(img.children, actual.img.children);
            },
            .url => |url| {
                if (!std.meta.eql(url.url, actual.url.url)) {
                    return error.TestExpectedEqual;
                }

                try expectEqual(url.children, actual.url.children);
            },
            .inline_code => |inline_code| {
                try std.testing.expectEqual(inline_code, actual.inline_code);
            },
            .text => |text| {
                try std.testing.expectEqual(text, actual.text);
            },
            .line_break => |line_break| {
                try std.testing.expectEqual(line_break, actual.line_break);
            }
        }
    }
}
