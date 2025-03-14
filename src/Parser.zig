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
        empty_code_block,
        invalid_number_of_backticks,
        unterminated_code_block,
    };
};

allocator: Allocator,
tokens: []const Token,
tok_i: usize,
elements: std.ArrayList(Element),
errors: std.ArrayList(Error),

pub fn init(allocator: Allocator, tokens: []const Token) Parser {
    return .{
        .allocator = allocator,
        .tokens = tokens,
        .tok_i = 0,
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
        const token = self.tokens[self.tok_i];

        const el = switch (token.tag) {
            .heading => blk: {
                if (token.len() > 6) {
                    return self.err(.invalid_heading_size, token);
                }

                _ = self.eatToken();
                const inline_el = try self.eatInline();
                const line_break = try self.eatLineBreak();

                var heading = Element.initNode(self.allocator, .heading);
                errdefer heading.deinit();

                try heading.addChild(inline_el);
                try heading.addChild(line_break);

                break :blk heading;
            },
            .newline => try self.eatLineBreak(),
            .literal_text => try self.eatInline(),
            .backtick => blk: {
                if (token.len() != 1 and token.len() != 3) {
                    return self.err(.invalid_number_of_backticks, token);
                }

                break :blk try self.parseCodeBlock();
            },
            .eof => return,
            else => {
                // skip token (for now)
                std.log.warn("Unhandled token ({s})", .{ @tagName(token.tag) });
                _ = self.eatToken();
                continue;
            },
        };

        try self.elements.append(el);
    }
}

fn parseCodeBlock(self: *Parser) !Element {
    const open_backtick_token = self.eatToken();
    var code_el = Element.initNode(self.allocator, .code);
    errdefer code_el.deinit();

    if (self.tokens[self.tok_i].tag == .backtick and self.tokens[self.tok_i].len() == open_backtick_token.len()) {
        return self.err(.empty_code_block, open_backtick_token);
    }

    loop: while (true) {
        const token = self.tokens[self.tok_i];

        switch (token.tag) {
            .backtick => {
                if (token.len() == open_backtick_token.len()) {
                    _ = self.eatToken();
                    break :loop;
                }
            },
            .eof => {
                return self.err(.unterminated_code_block, open_backtick_token);
            },
            else => {}
        }

        switch (token.tag) {
            .newline => {
                const line_break = try self.eatLineBreak();
                try code_el.addChild(line_break);
            },
            else => {
                const line = self.eatLineOfCode(open_backtick_token);
                try code_el.addChild(line);
            }
        }
    }

    return code_el;
}

fn eatLineOfCode(self: *Parser, open_backtick: Token) Element {
    var result_token = Token{
        .tag = .literal_text,
        .loc = self.tokens[self.tok_i].loc
    };

    while (true) {
        const token = self.tokens[self.tok_i];
        if (token.tag == .newline or token.tag == .eof or (token.tag == .backtick and token.len() == open_backtick.len())) {
            break;
        } else {
            const consumed_token = self.eatToken();
            result_token.loc.end_index = consumed_token.loc.end_index;
        }
    }

    return Element.initLeaf(.text, result_token);
}

fn eatLineBreak(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .newline) {
        return self.err(.unexpected_token, token);
    }

    _ = self.eatToken();
    return Element.initLeaf(.line_break, token);
}

fn eatInline(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .literal_text) {
        // TODO: allow inline content like italics
        return self.err(.unexpected_token, token);
    }

    _ = self.eatToken();
    return Element.initLeaf(.text, token);
}

fn eatToken(self: *Parser) Token {
    if (self.tok_i == self.tokens.len - 1) {
        return self.tokens[self.tok_i];
    }

    self.tok_i += 1;
    return self.tokens[self.tok_i - 1];
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
        .empty_code_block =>
            std.log.err(
                "Empty code block", .{}
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

const SourceBuilder = @import("testing/source_builder.zig").SourceBuilder;

test "fails on invalid code fence" {
    const builder = try SourceBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const source = builder
        .make(.backtick, 2)
        .build();

    var parser = Parser.init(
        std.testing.allocator,
        source,
    );
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.ParseError, result);
}


test "fails on empty code block" {
    const builder = try SourceBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const source = builder
        .make(.backtick, 3)
        .make(.newline, 1)
        .make(.backtick, 3)
        .build();

    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.ParseError, result);
}
