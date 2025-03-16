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
        no_line_break_before_block_code,
        empty_block_code,
        unterminated_block_code,
        empty_inline_code,
        unterminated_inline_code,
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
            .backtick =>
                switch (token.len()) {
                    1 => try self.parseInlineCode(),
                    2 => return self.err(.empty_inline_code, token),
                    3 => try self.parseBlockCode(),
                    6 => return self.err(.empty_block_code, token),
                    else => return self.err(.invalid_number_of_backticks, token),
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

fn parseInlineCode(_: *Parser) !Element {
    unreachable;
    // const open_backtick_token = self.eatToken();
    // const code_token = self.eatLineOfCode(open_backtick_token);
    //
    // const token = self.tokens[self.tok_i];
    // switch (token.tag) {
    //     .eof => return self.err(.unterminated_inline_code, open_backtick_token),
    //     .newline => return self.err(.unexpected_token, token),
    //     .backtick => {
    //         if (self.tokens[self.tok_i].tag == .backtick) {
    //             _ = self.eatToken();
    //         } else {
    //             return self.err(.unexpected_token, self.tokens[self.tok_i]);
    //         }
    //     },
    //     else => unreachable
    // }
    //
    //
    // return Element.initLeaf(.inline_code, code_token);
}

fn parseBlockCode(self: *Parser) !Element {
    const open_backtick_token = self.eatToken();
    var code_el = Element.initNode(self.allocator, .code);
    errdefer code_el.deinit();

    if (self.tok_i > 0 and self.tokens[self.tok_i - 1].tag != .newline) {
        return self.err(.no_line_break_before_block_code, open_backtick_token);
    }

    while (true) {
        const token = self.tokens[self.tok_i];

        switch (token.tag) {
            .backtick => {
                if (token.len() == open_backtick_token.len()) {
                    _ = self.eatToken();
                    break;
                }
            },
            .eof => {
                return self.err(.unterminated_block_code, open_backtick_token);
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
        .empty_block_code =>
            std.log.err(
                "Empty code block", .{}
            ),
        .unterminated_block_code =>
            std.log.err(
                "Unterminated code block", .{}
            ),
        .empty_inline_code =>
            std.log.err(
                "Empty inline code", .{}
            ),
        .unterminated_inline_code =>
            std.log.err(
                "Unterminated inline code", .{}
            ),
    }

    try self.errors.append(.{
        .tag = tag,
        .token = token,
    });

    return error.ParseError;
}

const source_builder = @import("testing/source_builder.zig");

test "fails on invalid code block" {
    // const builder = SourceBuilder.init(std.testing.allocator);
    // defer builder.deinit();
    // const source = builder
    //     .tok(.backtick, 4)
    //     .eof();
    //
    // var parser = Parser.init(
    //     std.testing.allocator,
    //     source,
    // );
    // defer parser.deinit();
    //
    // const result = parser.parse();
    // try std.testing.expectError(error.ParseError, result);
    //
    // const e = parser.errors.items[0];
    // try std.testing.expectEqual(e.tag, .invalid_number_of_backticks);
}

// test "fails on empty inline code" {
//     const builder = SourceBuilder.init(std.testing.allocator);
//     defer builder.deinit();
//     const source = builder
//         .tok(.backtick, 2)
//         .eof();
//
//     var parser = Parser.init(
//         std.testing.allocator,
//         source,
//     );
//     defer parser.deinit();
//
//     const result = parser.parse();
//     try std.testing.expectError(error.ParseError, result);
//
//     const e = parser.errors.items[0];
//     try std.testing.expectEqual(e.tag, .empty_inline_code);
// }

test "fails on empty code block" {
    const source = source_builder
        .tok(.backtick, 3)
        .eof();

    defer source_builder.free(source);

    std.debug.print("{}\n", .{ source.len });

    // const builder = SourceBuilder.init(std.testing.allocator);
    // defer builder.deinit();
    // const source = builder
    //     .tok(.backtick, 3)
    //     .tok(.newline, 1)
    //     .tok(.backtick, 3)
    //     .eof();

    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.ParseError, result);

    const e = parser.errors.items[0];
    try std.testing.expectEqual(e.tag, .empty_block_code);
}

// test "fails on unterminated inline code" {
//     const builder = SourceBuilder.init(std.testing.allocator);
//     defer builder.deinit();
//     const source = builder
//         .tok(.backtick, 1)
//         .tok(.newline, 1)
//         .eof();
//
//     var parser = Parser.init(
//         std.testing.allocator,
//         source
//     );
//     defer parser.deinit();
//
//     const result = parser.parse();
//     try std.testing.expectError(error.ParseError, result);
//
//     const e = parser.errors.items[0];
//     try std.testing.expectEqual(e.tag, .empty_block_code);
// }
