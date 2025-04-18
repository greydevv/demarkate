const std = @import("std");
const ast = @import("../ast.zig");
const Token = @import("../Tokenizer.zig").Token;

const Allocator = std.mem.Allocator;

pub const Error = error{OutOfMemory};

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

    pub fn render(self: *Renderer, elements: []const ast.Element) Error!void {
        try self.openTagWithClass("div", "markdown");

        for (elements) |el| {
            try self.renderElement(el);
        }

        try self.closeTag("div");
    }

    fn renderElement(self: *Renderer, el: ast.Element) Error!void {
        return switch (el) {
            .heading => |h| {
                // TODO: just h1 for now
                try self.openTag("h1");

                for (h.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag("h1");
            },
            .paragraph => |p| {
                try self.openTag("p");

                for (p.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag("p");
            },
            .modifier => |modifier|
                switch (modifier.tag) {
                    .bold => {
                        try self.openTag("strong");

                        for (modifier.children.items) |child| {
                            try self.renderElement(child);
                        }

                        try self.closeTag("strong");
                    },
                    .italic => {
                        try self.openTag("em");

                        for (modifier.children.items) |child| {
                            try self.renderElement(child);
                        }

                        try self.closeTag("em");
                    },
                    .underline => {
                        try self.openTag("s");

                        for (modifier.children.items) |child| {
                            try self.renderElement(child);
                        }

                        try self.closeTag("s");
                    },
                    .strikethrough => {
                        try self.openTag("s");

                        for (modifier.children.items) |child| {
                            try self.renderElement(child);
                        }

                        try self.closeTag("s");
                    },
                },
            .block_code => |block_code| {
                try self.openTag("pre");
                try self.openTag("code");

                for (block_code.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag("code");
                try self.closeTag("pre");
            },
            .inline_code => |span| {
                try self.openTag("code");
                try self.appendSpan(span);
                try self.closeTag("code");
            },
            .code_literal,
            .text => |span| try self.appendSpan(span),
            .line_break => try self.openTag("br"),
            .img => |img| {
                try self.openTag("img");

                // TODO: add src

                for (img.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag("img");
            },
            .url => |url| {
                try self.openTag("a");

                // TODO: add href

                for (url.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag("a");
            },
        };
    }

    fn openTag(self: *Renderer, comptime tag: []const u8) Error!void {
        return self.openTagWithClass(tag, null);
    }

    fn openTagWithClass(self: *Renderer, comptime tag: []const u8, comptime class: ?[]const u8) Error!void {
        const tag_open = comptime blk: {
            if (class) |class_name| {
                break :blk std.fmt.comptimePrint("<{s} class=\"{s}\">", .{ tag, class_name });
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

    fn appendSpan(self: *Renderer, span: ast.Span) !void {
        const source = span.slice(self.source);
        try self.buffer.appendSlice(source);
    }
};
