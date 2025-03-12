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
        children: std.ArrayList(Element),

        pub const Tag = enum {
            heading,
            code
        };

        pub fn deinit(self: *Node) void {
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
            line_break,
        };
    };

    pub fn initNode(allocator: Allocator, tag: Node.Tag) Element {
        return .{
            .node = Node{
                .tag = tag,
                // TODO: maybe init capacity?
                .children = std.ArrayList(Element).init(allocator)
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

    pub fn deinit(self: *Element) void {
        switch (self.*) {
            .node => |*n| n.deinit(),
            .leaf => return,
        }
    }

    pub fn addChild(self: *Element, child: Element) !void {
        switch (self.*) {
            .node => |*n| try n.children.append(child),
            .leaf => return error.NotANode,
        }
    }
};

