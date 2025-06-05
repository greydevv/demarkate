const std = @import("std");
const pos = @import("pos.zig");
const Tokenizer = @import("Tokenizer.zig");

pub const Element = union(enum) {
    heading: struct {
        level: usize,
        children: std.ArrayList(Element),
    },
    callout: struct {
        type: ?pos.Span,
        children: std.ArrayList(Element),
    },
    url: struct {
        href: pos.Span,
        children: std.ArrayList(Element),
    },
    img: struct {
        src: pos.Span,
        alt_text: ?pos.Span,
    },
    block_code: struct {
        lang: ?pos.Span,
        children: std.ArrayList(Element),
    },
    modifier: Modifier,
    inline_code: pos.Span,
    code_literal: pos.Span,
    text: pos.Span,
    line_break: pos.Span,

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
            .callout => |*el| {
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
                    .callout => |*el| {
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
        return &self.modifier.children.items[self.modifier.children.items.len - 1];
    }
};

fn deinitChildren(of: anytype) void {
    for (of.children.items) |child| child.deinit();
    of.children.deinit();
}
