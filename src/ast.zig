const std = @import("std");
const pos = @import("pos.zig");
const Tokenizer = @import("Tokenizer.zig");

pub const Element = union(enum) {
    heading: struct {
        level: u8,
        children: std.ArrayList(Element),
    },
    callout: struct {
        style: ?pos.Span,
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
    indent: struct {
        span: pos.Span,
        count: usize,
    },
    noop,

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

    pub fn deinit(self: *Element, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .heading => |*el| {
                deinitChildren(allocator, el);
            },
            .callout => |*el| {
                deinitChildren(allocator, el);
            },
            .url => |*el| {
                deinitChildren(allocator, el);
            },
            .modifier => |*el| {
                deinitChildren(allocator, el);
            },
            .block_code => |*el| {
                deinitChildren(allocator, el);
            },
            else => {}
        }
    }

    pub fn addChild(self: *Element, allocator: std.mem.Allocator, child: anytype) !*@TypeOf(child) {
        return switch (@TypeOf(child)) {
            Element =>
                switch (self.*) {
                    .heading => |*el| {
                        try el.children.append(allocator, child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .callout => |*el| {
                        try el.children.append(allocator, child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .url => |*el| {
                        try el.children.append(allocator, child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .modifier => |*el| {
                        try el.children.append(allocator, child);
                        return &el.children.items[el.children.items.len - 1];
                    },
                    .block_code => |*el| {
                        try el.children.append(allocator, child);
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

fn deinitChildren(allocator: std.mem.Allocator, of: anytype) void {
    for (of.children.items) |*child| child.deinit(allocator);
    of.children.deinit(allocator);
}
