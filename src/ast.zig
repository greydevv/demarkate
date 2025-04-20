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
        href: Span,
    },
    img: struct {
        children: std.ArrayList(Element),
        src: Span,
    },
    block_code: struct {
        lang: ?Span,
        children: std.ArrayList(Element),
    },
    modifier: Modifier,
    inline_code: Span,
    code_literal: Span,
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

    pub fn deinit(self: *const Element) void {
        switch (self.*) {
            .heading => |*el| {
                deinitChildren(el);
            },
            .paragraph => |*el| {
                deinitChildren(el);
            },
            .img => |*el| {
                deinitChildren(el);
            },
            .url => |*el| {
                deinitChildren(el);
            },
            .modifier => |*el| {
                deinitChildren(el);
            },
            .block_code => |*el| {
                deinitChildren(el);
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
            else => @compileError("Unexpected child type '" ++ @typeName(@TypeOf(child)) ++ "'")
        };
    }

    pub fn lastChild(self: *Element) *Element {
        // const active_tag = std.meta.activeTag(self.*);
        // std.debug.print("\n{s}\n\n", .{ @typeName(@TypeOf(active_tag)) });

        return &self.modifier.children.items[self.modifier.children.items.len - 1];
    }
};

fn deinitChildren(of: anytype) void {
    for (of.children.items) |child| child.deinit();
    of.children.deinit();
}
