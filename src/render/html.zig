const std = @import("std");
const pos = @import("../pos.zig");
const ast = @import("../ast.zig");

pub const Error = error{ OutOfMemory, NoSpaceLeft };

const Attr = std.meta.Tuple(&.{ []const u8, []const u8 });

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    source: [:0]const u8,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, source: [:0]const u8) Renderer {
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
        try self.openTagWithAttrs("div", &.{
            .{ "class", "dmk_document" }
        });

        for (elements) |el| {
            try self.renderElement(el);
        }

        try self.closeTag("div");
    }

    fn renderElement(self: *Renderer, el: ast.Element) Error!void {
        return switch (el) {
            .heading => |h| {
                var tag: [2]u8 = undefined;
                _ = std.fmt.bufPrint(&tag, "h{}", .{ h.level }) catch unreachable;

                try self.openTag(&tag);

                for (h.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag(&tag);
            },
            .callout => |callout| {
                var class: []const u8 = undefined;
                if (callout.style) |span| {
                    class = try std.fmt.allocPrint(
                        self.allocator,
                        "dmk_callout_{s}",
                        .{ span.slice(self.source) }
                    );
                } else {
                    class = try std.fmt.allocPrint(
                        self.allocator,
                        "dmk_callout",
                        .{}
                    );
                }
                defer self.allocator.free(class);

                try self.openTagWithAttrs("div", &.{
                    .{ "class", class }
                });

                for (callout.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag("div");
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

                if (block_code.lang) |lang| {
                    try self.openTagWithAttrs("code", &.{
                        .{ "class", lang.slice(self.source) }
                    });
                } else {
                    try self.openTag("code");
                }

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
            .img => |img| {
                var alt: []const u8 = "";
                if (img.alt_text) |span| {
                    alt = span.slice(self.source);
                }

                try self.openTagWithAttrs("img", &.{
                    .{ "src",  img.src.slice(self.source) },
                    .{ "alt",  alt },
                });
            },
            .url => |url| {
                try self.openTagWithAttrs("a", &.{
                    .{ "href",  url.href.slice(self.source) },
                });

                for (url.children.items) |child| {
                    try self.renderElement(child);
                }

                try self.closeTag("a");
            },
            .code_literal,
            .text => |span| try self.appendSpan(span),
            .line_break => {
                try self.openTagWithAttrs("div", &.{
                    .{ "class", "dmk_line_break" }
                });

                try self.closeTag("div");
            },
            .noop => {},
        };
    }

    fn openTag(self: *Renderer, tag: []const u8) Error!void {
        return self.openTagWithAttrs(tag, &.{});
    }

    fn openTagWithAttrs(
        self: *Renderer,
        tag: []const u8,
        attrs: []const Attr
    ) Error!void {
        try self.buffer.append('<');

        try self.buffer.appendSlice(tag);

        for (attrs) |attr| {
            const html_attr = try std.fmt.allocPrint(
                self.allocator,
                " {s}=\"{s}\"",
                .{ attr[0], attr[1] }
            );
            defer self.allocator.free(html_attr);

            try self.buffer.appendSlice(html_attr);
        }

        try self.buffer.append('>');
    }

    fn closeTag(self: *Renderer, tag: []const u8) !void {
        const fmt = "</{s}>";

        var tmp_buf: [16]u8 = undefined;
        const buf = std.fmt.bufPrint(&tmp_buf, fmt, .{ tag }) catch {
            const tag_close = try std.fmt.allocPrint(self.allocator, fmt, .{ tag });
            defer self.allocator.free(tag);
            try self.buffer.appendSlice(tag_close);
            return;
        };

        try self.buffer.appendSlice(buf);
    }

    fn appendSpan(self: *Renderer, span: pos.Span) !void {
        const source = span.slice(self.source);
        try self.buffer.appendSlice(source);
    }
};
