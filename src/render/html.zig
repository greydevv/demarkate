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
        class: ?[]u8,
        source: ?[]const u8,

        pub const Tag = enum {
            literal,
            code,
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

    pub fn initLeaf(tag: Leaf.Tag, class: ?[]u8, source: ?[]const u8) Element {
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

pub const RenderError = error{OutOfMemory};

pub const Renderer = struct {
    allocator: Allocator,
    source: [:0]const u8,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator, source: [:0]const u8) Renderer {
        return .{
            .allocator = allocator,
            .source = source,
            .buffer = std.ArrayList(u8).init(allocator)
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.buffer.deinit();
    }

    pub fn render(self: *Renderer, elements: []const ast.Element) !void {
        try self.openTagWithClass("div", "markdown");

        for (elements) |el| {
            try self.renderElement(el);
        }

        try self.closeTag("div");
    }

    fn renderElement(self: *Renderer, el: ast.Element) RenderError!void {
        return switch (el) {
            .node => |node| switch (node.tag) {
                .heading => {
                    const level = node.children.items[0].leaf.token.len();
                    std.log.info("HEADING LEVEL: {}", .{ level });

                    try self.openTag("h1");

                    for (node.children.items[1..]) |child| {
                        try self.renderElement(child);
                    }

                    try self.closeTag("h1");
                },
                .paragraph => {
                    try self.openTag("p");

                    for (node.children.items) |child| {
                        try self.renderElement(child);
                    }

                    try self.closeTag("p");
                },
                .italic => {
                    try self.openTag("em");

                    for (node.children.items) |child| {
                        try self.renderElement(child);
                    }

                    try self.closeTag("em");
                },
                .bold => {
                    try self.openTag("strong");

                    for (node.children.items) |child| {
                        try self.renderElement(child);
                    }

                    try self.closeTag("strong");
                },
                .strikethrough => {
                    try self.openTag("s");

                    for (node.children.items) |child| {
                        try self.renderElement(child);
                    }

                    try self.closeTag("s");
                },
                .block_code => {
                    try self.openTag("pre");
                    try self.openTag("code");

                    for (node.children.items) |child| {
                        try self.renderElement(child);
                    }

                    try self.closeTag("code");
                    try self.closeTag("pre");
                },
                .inline_code => {
                    try self.openTag("code");

                    for (node.children.items) |child| {
                        try self.renderElement(child);
                    }

                    try self.closeTag("code");
                },
            },
            .leaf => |leaf| switch (leaf.tag) {
                .text,
                .code_literal => try self.appendToken(leaf.token),
                .line_break => try self.openTag("br"),
                .metadata => unreachable,
            }
        };
    }

    fn openTag(self: *Renderer, comptime tag: []const u8) !void {
        return self.openTagWithClass(tag, null);
    }

    fn openTagWithClass(self: *Renderer, comptime tag: []const u8, comptime class: ?[]const u8) !void {
        const tag_open = comptime blk: {
            if (class) |class_name| {
                break :blk std.fmt.comptimePrint("<{s} class={s}>", .{ tag, class_name });
            } else {
                break :blk std.fmt.comptimePrint("<{s}>", .{ tag });
            }
        };

        try self.buffer.appendSlice(tag_open);
    }


    fn closeTag(self: *Renderer, comptime tag: []const u8) !void {
        const tag_close = comptime std.fmt.comptimePrint("</{s}>", .{ tag });
        try self.buffer.appendSlice(tag_close);
    }

    fn appendToken(self: *Renderer, token: Token) !void {
        const source = token.slice(self.source);
        try self.buffer.appendSlice(source);
    }
};
