const std = @import("std");
const Tokenizer = @import("../Tokenizer.zig");
const pos = @import("../pos.zig");
const ast = @import("../ast.zig");

const allocator = std.testing.allocator;

pub fn free(elements: *std.ArrayList(ast.Element)) void {
    for (elements.items) |*el| {
        el.deinit(allocator);
    }

    elements.deinit(allocator);
}

pub const AstBuilder = struct {
    elements: std.ArrayList(ast.Element),

    pub fn init() *AstBuilder {
        const builder = allocator.create(AstBuilder) catch unreachable;
        builder.* = .{
            .elements = std.ArrayList(ast.Element).empty
        };

        return builder;
    }

    pub fn block_code(self: *AstBuilder, children: std.ArrayList(ast.Element)) *AstBuilder {
        const el = ast.Element{
            .block_code = .{
                .children = children
            }
        };

        self.elements.append(allocator, el) catch unreachable;
        return self;
    }

    pub fn modifier(self: *AstBuilder, tag: ast.Element.Modifier.Tag, children: std.ArrayList(ast.Element)) *AstBuilder {
        const el = ast.Element{
            .modifier = .{
                .children = children,
                .tag = tag,
            }
        };

        return self.node(el);
    }

    pub fn text(self: *AstBuilder, token: Tokenizer.Token) *AstBuilder {
        return self.leaf(@tagName(ast.Element.text), token);
    }

    fn node(self: *AstBuilder, el: ast.Element) *AstBuilder {
        self.elements.append(allocator, el) catch unreachable;
        return self;
    }

    fn leaf(self: *AstBuilder, comptime tag_name: []const u8, token: Tokenizer.Token) *AstBuilder {
        self.elements.append(
            allocator,
            @unionInit(
                ast.Element,
                tag_name,
                token.span,
            )
        ) catch unreachable;

        return self;
    }

    pub fn build(self: *AstBuilder) std.ArrayList(ast.Element) {
        defer allocator.destroy(self);
        return self.elements;
    }
};

pub fn expectEqual(expected_ast: std.ArrayList(ast.Element), actual_ast: std.ArrayList(ast.Element)) !void {
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
                if (!std.meta.eql(img.src, actual.img.src)) {
                    return error.TestExpectedEqual;
                }

                if (!std.meta.eql(img.alt_text, actual.img.alt_text)) {
                    return error.TestExpectedEqual;
                }
            },
            .url => |url| {
                if (!std.meta.eql(url.href, actual.url.href)) {
                    return error.TestExpectedEqual;
                }

                try expectEqual(url.children, actual.url.children);
            },
            .callout => unreachable,
            .inline_code => |inline_code| {
                try std.testing.expectEqual(inline_code, actual.inline_code);
            },
            .code_literal => |code_literal| {
                try std.testing.expectEqual(code_literal, actual.code_literal);
            },
            .text => |text| {
                try std.testing.expectEqual(text, actual.text);
            },
            .line_break => |line_break| {
                try std.testing.expectEqual(line_break, actual.line_break);
            },
            .noop => |el| {
                try std.testing.expectEqual(el, actual.noop);
            }
        }
    }
}
