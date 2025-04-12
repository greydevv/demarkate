const std = @import("std");
const Allocator = std.mem.Allocator;
const Token = @import("Tokenizer.zig").Token;

pub const Span = struct {
    start: usize,
    end: usize,

    pub fn from(token: Token) Span {
        return .{
            .start = token.loc.start_index,
            .end = token.loc.end_index,
        };
    }

    pub fn slice(self: *const Span, buffer: [:0]const u8) []const u8 {
        return buffer[self.start..self.end];
    }
};

pub const Element = union(enum) {
    heading: struct {
        children: std.ArrayList(Element),
        level: usize,
    },
    paragraph: struct {
        children: std.ArrayList(Element),
    },
    url: struct {
        children: std.ArrayList(Element),
        url: Span,
    },
    img: struct {
        children: std.ArrayList(Element),
        url: Span,
    },
    block_code: struct {
        children: std.ArrayList(Element),
    },
    modifier: Modifier,
    inline_code: Span,
    text: Span,
    line_break: Span,

    pub const Modifier = struct {
        children: std.ArrayList(Element),
        tag: Tag,

        pub const Tag = enum {
            bold,
            italic,
            strikethrough,
            underline
        };
    };

    // pub fn initNode(allocator: Allocator, tag: Node.Tag) Element {
    //     return .{
    //         .node = Node{
    //             .tag = tag,
    //             // TODO: maybe init capacity?
    //             .children = Node.Children.init(allocator)
    //         }
    //     };
    // } 
    //
    // pub fn initLeaf(tag: Leaf.Tag, token: Token) Element {
    //     return .{
    //         .leaf = Leaf{
    //             .tag = tag,
    //             .token = token
    //         }
    //     };
    // }

    pub fn deinit(self: *const Element) void {
        switch (self.*) {
            .heading => |*el| {
                deinitArrayListAndItems(el);
            },
            .paragraph => |*el| {
                deinitArrayListAndItems(el);
            },
            .img => |*el| {
                deinitArrayListAndItems(el);
            },
            .url => |*el| {
                deinitArrayListAndItems(el);
            },
            .modifier => |*el| {
                deinitArrayListAndItems(el);
            },
            .block_code => |*el| {
                el.children.deinit();
            },
            else => {}
        }
    }

    pub fn addChild(self: *Element, child: anytype) !*@TypeOf(child) {
        return switch (@TypeOf(child)) {
            Element =>
                switch (self.*) {
                    .heading => |*el| {
                        try el.children.append(child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .paragraph => |*el| {
                        try el.children.append(child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .img => |*el| {
                        try el.children.append(child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .url => |*el| {
                        try el.children.append(child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .modifier => |*el| {
                        try el.children.append(child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .block_code => |*el| {
                        try el.children.append(child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    else => unreachable,
                },
            else => @compileError("Nothing accepts " ++ @typeName(@TypeOf(child)))
        };
    }

    pub fn lastChild(self: *const Element) *Element {
        switch (self.*) {
            .node => |*n| return &n.children.items[n.children.items.len - 1],
            .leaf => unreachable,
        }
    }
};

fn deinitArrayListAndItems(of: anytype) void {
    for (of.children.items) |child| child.deinit();
    of.children.deinit();
}
