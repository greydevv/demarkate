const std = @import("std");
const Token = @import("../Tokenizer.zig").Token;
const Element = @import("../ast.zig").Element;

const allocator = std.testing.allocator;

pub fn node(tag: Element.Node.Tag, children: std.ArrayList(Element)) *AstBuilder {
    const builder = allocator.create(AstBuilder) catch unreachable;
    builder.* = .{
        .elements = std.ArrayList(Element).init(allocator)
    };

    builder.elements.append(.{
        .node = .{
            .tag = tag,
            .children = children
        }
    }) catch unreachable;

    return builder;
}

pub fn leaf(tag: Element.Leaf.Tag, token: Token) *AstBuilder {
    const builder = allocator.create(AstBuilder) catch unreachable;
    builder.* = .{
        .elements = std.ArrayList(Element).init(allocator)
    };

    builder.elements.append(.{
        .leaf = .{
            .tag = tag,
            .token = token
        }
    }) catch unreachable;

    return builder;
}

pub fn free(ast: std.ArrayList(Element)) void {
    for (ast.items) |el| {
        switch (el) {
            .node => |n| free(n.children),
            .leaf => continue,
        }
    }

    ast.deinit();
}

pub const AstBuilder = struct {
    elements: std.ArrayList(Element),

    fn deinit(self: *AstBuilder) void {
        allocator.destroy(self);
    }

    pub fn node(self: *AstBuilder, tag: Element.Node.Tag, children: std.ArrayList(Element)) *AstBuilder {
        self.elements.append(.{
            .node = .{
                .tag = tag,
                .children = children
            }
        }) catch unreachable;

        return self;
    }

    pub fn leaf(self: *AstBuilder, tag: Element.Leaf.Tag, token: Token) *AstBuilder {
        self.elements.append(.{
            .leaf = .{
                .tag = tag,
                .token = token
            }
        }) catch unreachable;

        return self;
    }

    pub fn build(self: *AstBuilder) std.ArrayList(Element) {
        defer self.deinit();
        return self.elements;
    }
};

pub fn expectEqual(expected: std.ArrayList(Element), actual: std.ArrayList(Element)) !void {
    if (expected.items.len != actual.items.len) {
        return error.TestExpectedEqual;
    }

    for (expected.items, actual.items) |a, b| {
        switch (a) {
            .node => |expected_node| {
                const actual_node = b.node;
                if (expected_node.tag != actual_node.tag) {
                    return error.TestExpectedEqual;
                }

                return expectEqual(expected_node.children, actual_node.children);
            },
            .leaf => |expected_leaf| {
                const actual_leaf = b.leaf;
                if (!std.meta.eql(expected_leaf, actual_leaf)) {
                    return error.TestExpectedEqual;
                }
            }
        }
    }
}
