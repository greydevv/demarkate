const std = @import("std");
const ast = @import("ast.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;
const Element = ast.Element;
const Allocator = std.mem.Allocator;

const Parser = @This();

allocator: Allocator,
tokenizer: *Tokenizer,
elements: std.ArrayList(Element),
errors: std.ArrayList(Error),

pub fn init(allocator: Allocator, tokenizer: *Tokenizer) Parser {
    return .{
        .allocator = allocator,
        .tokenizer = tokenizer,
        // TODO: use assume capacity strategy that zig uses, ((tokens.len + 2) / 2)
        .elements = std.ArrayList(Element).init(allocator),
        .errors = std.ArrayList(Error).init(allocator),
    };
}

pub fn deinit(self: *Parser) void {
    for (self.elements.items) |*el| {
        el.deinit();
    }

    self.elements.deinit();
    self.errors.deinit();
}

pub fn parse(self: *Parser) !void {
    loop: while (true) {
        const token = self.tokenizer.next();
        if (token.tag == .eof) {
            break;
        }

        const el = switch (token.tag) {
            .heading => blk: {
                if (token.len() > 6) {
                    return self.err(.heading_too_small, token);
                }

                const inline_el = try self.parseInline();
                var node = Element.initNode(self.allocator, .heading);
                try node.addChild(inline_el);
                break :blk node;
            },
            .newline => Element.initLeaf(.line_break, token),
            .literal_text => Element.initLeaf(.text, token),
            .eof => break :loop,
            else => return self.err(.unexpected_token, token),
        };

        try self.elements.append(el);
    }
}

fn parseInline(self: *Parser) !Element {
    const token = self.tokenizer.next();
    if (token.tag != .literal_text) {
        return self.err(.unexpected_token, token);
    }

    return Element.initLeaf(.text, token);
}


fn err(self: *Parser, tag: Error.Tag, token: Token) error{ ParseError, OutOfMemory } {
    switch(tag) {
        .heading_too_small =>
            std.log.err(
                "Heading too small ({})", .{
                    token.len()
                }
            ),
        // this is a catch-all for now
        .unexpected_token =>
            std.log.err(
                "Unexpected token ({s}) from {} to {}", .{
                    @tagName(token.tag),
                    token.loc.start_index,
                    token.loc.end_index 
                }
            ),
    }

    try self.errors.append(.{
        .tag = tag,
        .token = token,
    });

    return error.ParseError;
}

pub const Error = struct {
    tag: Tag,
    token: Token,

    pub const Tag = enum {
        heading_too_small,
        unexpected_token,
    };
};
