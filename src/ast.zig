const std = @import("std");
const Allocator = std.mem.Allocator;
const Token = @import("Tokenizer.zig").Token;

pub const Element = union(Element.Type) {
    node: Node,
    leaf: Leaf,

    pub const Type = enum {
        node,
        leaf
    };

    pub const Node = struct {
        tag: Tag,
        children: Children,

        pub const Children = std.ArrayList(Element);

        pub const Tag = enum {
            heading,
            code,
            italic,
            bold,
            strikethrough
        };

        pub fn deinit(self: *const Node) void {
            for (self.children.items) |*child| {
                child.deinit();
            }

            self.children.deinit();
        }
    };

    pub const Leaf = struct {
        tag: Tag,
        token: Token,

        pub const Tag = enum {
            text,
            code_literal,
            line_break,
        };
    };

    pub fn initNode(allocator: Allocator, tag: Node.Tag) Element {
        return .{
            .node = Node{
                .tag = tag,
                // TODO: maybe init capacity?
                .children = Node.Children.init(allocator)
            }
        };
    } 

    pub fn initLeaf(tag: Leaf.Tag, token: Token) Element {
        return .{
            .leaf = Leaf{
                .tag = tag,
                .token = token
            }
        };
    }

    pub fn deinit(self: *const Element) void {
        switch (self.*) {
            .node => |*n| n.deinit(),
            .leaf => return,
        }
    }

    /// Add a child element and obtain a pointer to it.
    pub fn addChild(self: *Element, child: Element) !*Element {
        switch (self.*) {
            .node => |*n| {
                try n.children.append(child);
                return &n.children.items[n.children.items.len - 1];
            },
            // TODO: should this be unreachable?
            .leaf => unreachable,
        }
    }

    pub fn lastChild(self: *const Element) *Element {
        switch (self.*) {
            .node => |*n| return &n.children.items[n.children.items.len - 1],
            .leaf => unreachable,
        }
    }

    pub fn children(self: *const Element) []Element {
        switch (self.*) {
            .node => |*n| return n.children.items,
            .leaf => unreachable,
        }
    }
};
