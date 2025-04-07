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
            span,
        };
    };

    pub const Leaf = struct {
        tag: Tag,
        class: []u8,
        source: []const u8,

        pub const Tag = enum {
            literal,
            br,
        };
    };

    pub fn deinit(self: *const Element) void {
        switch (self.*) {
            .node => |*node| {
                for (node.children.items) |child| {
                    child.deinit();
                }

                node.children.deinit();
            },
            .leaf => return
        }
    }

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

    pub fn render(self: *const Renderer, elements: []const ast.Element) !Element {
        var top_level_el = Element.initNode(
            self.allocator,
            .div,
            "markdown"
        );

        for (elements) |el| {
            const html_el = try self.renderElement(el);
            try top_level_el.addChild(html_el);
        }

        return top_level_el;
    }

    fn renderElement(self: *const Renderer, el: ast.Element) !Element {
        return switch (el) {
            .node => |node| try self.renderNode(node),
            .leaf => |leaf| try self.renderLeaf(leaf)
        };
    }

    fn renderNode(self: *const Renderer, node: ast.Element.Node) !Element {
        const el = switch (node.tag) {
            .italic => blk: {
                const el = Element.initNode(
                    self.allocator,
                    .span,
                    "italic"
                );

                for (node.children.items) |child_node| {
                    const child_el = try self.renderElement(child_node);
                    try el.addChild(child_el);
                }

                break :blk el;
            },
            else => unreachable
        };
        
        return el;
    }

    fn renderLeaf(self: *const Renderer, leaf: ast.Element.Leaf) !Element {
        const el = switch (leaf.tag) {
            .text =>
                Element.initLeaf(
                    .literal,
                    "",
                    self.sourceFromToken(leaf.token)
                ),
            .line_break =>
                Element.initLeaf(
                    .br,
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
