const std = @import("std");
const ast = @import("../ast.zig");
const Token = @import("../Tokenizer.zig").Token;

const Allocator = std.mem.Allocator;

pub const Element = union(Element.Type) {
    node: Node,
    leaf: Leaf,

    pub const Type = enum {
        node,
        leaf
    };

    pub const Node = struct {
        tag: Tag,
        class: []const u8,
        children: std.ArrayList(Element),

        pub const Tag = enum {
            div,
        };
    };

    pub const Leaf = struct {
        tag: Tag,
        class: []u8,
        source: []const u8,

        pub const Tag = enum {
            literal,
            span
        };
    };

    pub fn initNode(allocator: Allocator, tag: Node.Tag, class: []const u8) Element {
        return .{
            .node = .{
                .tag = tag,
                .class = class,
                .children = std.ArrayList(Element).init(allocator)
            }
        };
    }

    pub fn initLeaf(tag: Leaf.Tag, class: []u8, source: []const u8) Element {
        return .{
            .leaf = .{
                .tag = tag,
                .class = class,
                .source = source
            }
        };
    }

    pub fn addChild(self: *Element, el: Element) !void {
        switch (self.*) {
            .node => |*node| try node.children.append(el),
            .leaf => unreachable,
        }
    }
};

pub const Renderer = struct {
    allocator: Allocator,
    source: [:0]const u8,

    pub fn init(allocator: Allocator, source: [:0]const u8) Renderer {
        return .{
            .allocator = allocator,
            .source = source
        };
    }

    pub fn render(self: *const Renderer, elements: []const ast.Element) !Element {
        var top_level_el = Element.initNode(
            self.allocator,
            .div,
            "markdown"
        );

        for (elements) |el| {
            const html_el = switch (el) {
                .node => unreachable,
                .leaf => |leaf| try self.renderLeaf(leaf)
            };

            try top_level_el.addChild(html_el);
        }

        return top_level_el;
    }

    fn renderLeaf(self: *const Renderer, leaf: ast.Element.Leaf) !Element {
        const el = switch (leaf.tag) {
            .text =>
                Element.initLeaf(
                    .literal,
                    "",
                    self.sourceFromToken(leaf.token)
                ),
            else => unreachable,
        };

        return el;
    }

    fn sourceFromToken(self: *const Renderer, token: Token) []const u8 {
        return token.slice(self.source);
    }
};
