const std = @import("std");
const ast = @import("ast.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;
const Element = ast.Element;
const Allocator = std.mem.Allocator;

const Parser = @This();

pub const Error = struct {
    tag: Tag,
    token: Token,

    pub const Tag = enum {
        invalid_heading_size,
        unexpected_token,
        invalid_number_of_backticks,
        unterminated_code_block,
    };
};

allocator: Allocator,
tokens: []const Token,
elements: std.ArrayList(Element),
errors: std.ArrayList(Error),

pub fn init(allocator: Allocator, tokens: []const Token) Parser {
    return .{
        .allocator = allocator,
        .tokens = tokens,
        // TODO: use assume capacity strategy that zig uses, ((tokens.len + 2) / 2),
        // but tailor it to markdown.
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
    while (true) {
        const token = self.tokenizer.next();
        if (token.tag == .eof) {
            break;
        }

        const el = switch (token.tag) {
            .heading => blk: {
                if (token.len() > 6) {
                    return self.err(.invalid_heading_size, token);
                }

                const inline_el = try self.parseInline();
                var node = Element.initNode(self.allocator, .heading);
                try node.addChild(inline_el);
                break :blk node;
            },
            .newline => Element.initLeaf(.line_break, token),
            .literal_text => Element.initLeaf(.text, token),
            .backtick => blk: {
                if (token.len() != 1 and token.len() != 3) {
                    return self.err(.invalid_number_of_backticks, token);
                }

                const node = try self.parseCodeBlock(token.len());
                break :blk node;
            },
            .eof => return,
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

fn parseCodeBlock(self: *Parser, n_open_backticks: usize) !Element {
    var lines = std.ArrayList(Element).init(self.allocator);

    while(true) {
        var line = self.consumeUntilLineBreakOrEof();
        var token = self.tokenizer.next();
        if (token.tag == .backtick and token.len() == n_open_backticks) {
            break;
        }

        // if (token.tag == .newline) {
        //     const line_break = Element.initLeaf(.line_break, token);
        //     try lines.append(line_break);
        //     continue;
        // }

        const line_start_index = token.loc.start_index;
        var line_end_index: ?usize = null;

        while(true) {
            if (token.tag == .newline) {
                const line_break = Element.initLeaf(.line_break, token);
                try lines.append(line_break);
                break;
            }

            line_end_index = token.loc.end_index;
            token = self.tokenizer.next();
        }

        if (line_end_index) |end_index| {
            const el = Element.initLeaf(
                .text,
                Token{
                    .tag = .literal_text,
                    .loc = .{
                        .start_index = line_start_index,
                        .end_index = end_index
                    }
                }
            );

            try lines.append(el);
        }
    }

    return Element{
        .node = .{
            .tag = .code,
            .children = lines
        }
    };
}

fn consumeUntilLineBreakOrEof(self: *Parser) ?Token {
    var token = self.tokenizer.next();

    var result_token = Token{
        .tag = .literal_text,
        .loc = token.loc,
    };

    while(true) {
        if (token.tag == .newline or token.tag == .eof) {
            break;
        } else {
            result_token.loc.end_index = token.loc.end_index;
        }

        token = self.tokenizer.next();
    }

    return result_token;
}

fn err(self: *Parser, tag: Error.Tag, token: Token) error{ ParseError, OutOfMemory } {
    switch(tag) {
        .invalid_heading_size =>
            std.log.err(
                "Invalid heading size: {}", .{
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
        .invalid_number_of_backticks =>
            std.log.err(
                "Invalid number of backticks: {}", .{
                    token.len()
                }
            ),
        .unterminated_code_block =>
            std.log.err(
                "Unterminated code block", .{}
            ),
    }

    try self.errors.append(.{
        .tag = tag,
        .token = token,
    });

    return error.ParseError;
}
