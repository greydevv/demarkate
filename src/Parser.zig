const std = @import("std");
const ast = @import("ast.zig");
const Tokenizer = @import("Tokenizer.zig");

const Token = Tokenizer.Token;
const Element = ast.Element;
const Span = ast.Span;
const Allocator = std.mem.Allocator;

const Parser = @This();

const ParseError = error{};

pub const Error = struct {
    tag: Tag,
    token: Token,

    pub const Tag = enum {
        unexpected_token,
        invalid_token,
        unterminated_modifier,
        no_line_break_before_block_code,
        unterminated_block_code,
        unterminated_inline_code,
    };

    pub fn allocMsg(self: *const Error, allocator: Allocator) ![]const u8 {
        const tag = self.tag;
        const token = self.token;

        const msg = switch(tag) {
            .unexpected_token =>
                std.fmt.allocPrint(
                    allocator,
                    "Unexpected token ({s}) from {} to {}", .{
                        @tagName(token.tag),
                        token.loc.start_index,
                        token.loc.end_index
                    }
                ),
            .invalid_token =>
                std.fmt.allocPrint(
                    allocator,
                    "Invalid token ({s}) from {} to {}", .{
                        @tagName(token.tag),
                        token.loc.start_index,
                        token.loc.end_index
                    }
                ),
            .unterminated_modifier =>
                std.fmt.allocPrint(
                    allocator,
                    "Unterminated inline modifier ({s})", .{
                        @tagName(token.tag)
                    }
                ),
            .no_line_break_before_block_code =>
                std.fmt.allocPrint(
                    allocator,
                    "No line break before code block", .{}
                ),
            .unterminated_block_code =>
                std.fmt.allocPrint(
                    allocator,
                    "Unterminated code block", .{}
                ),
            .unterminated_inline_code =>
                std.fmt.allocPrint(
                    allocator,
                    "Unterminated inline code", .{}
                ),
        };

        return msg;
    }
};

allocator: Allocator,
source: [:0]const u8,
tokens: []const Token,
tok_i: usize,
elements: std.ArrayList(Element),
errors: std.ArrayList(Error),

pub fn init(allocator: Allocator, source: [:0]const u8, tokens: []const Token) Parser {
    return .{
        .allocator = allocator,
        .source = source,
        .tokens = tokens,
        .tok_i = 0,
        // TODO: use assume capacity strategy that zig uses, ((tokens.len + 2) / 2),
        // but modified for markdown ratio
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
            .pound => blk: {
                if (token.len() > 6) {
                    return self.err(.invalid_token, token);
                }

                break :blk try self.parseHeading();
            },
            .newline => try self.expectLineBreak(),
            .backtick => blk: {
                if (token.len() == 3) {
                    break :blk try self.parseBlockCode();
                } else {
                    break :blk try self.parseInline();
                }
            },
            .ampersat => try self.parseBuiltIn(),
            .eof => return,
            else => try self.parseParagraph(),
        };

        try self.elements.append(el);
    }
}

fn parseBuiltIn(self: *Parser) !Element {
    _ = self.eatToken();

    var span = Span.from(self.tokens[self.tok_i]);
    while (true) {
        const token = self.tokens[self.tok_i];
        switch (token.tag) {
            .colon,
            .open_paren => {
                break;
            },
            // TODO: .colon => parse attributes
            .newline,
            .eof => return self.err(.unexpected_token, token),
            else => {
                span.end = token.loc.end_index;
                _ = self.eatToken();
            }
        }
    }


    if (self.tokens[self.tok_i].tag == .colon) {
        const attrs = try self.parseAttributes();
        defer attrs.deinit();

        std.log.info("Parsed attributes!", .{});
        for (attrs.items) |attr_span| {
            std.log.info("  {s}", .{ attr_span.slice(self.source) });
        }
    }

    _ = self.eatToken();
    // TODO: Throw error for empty modifier

    std.log.info("Parsing {s}", .{ span.slice(self.source) });
    if (std.mem.eql(u8, span.slice(self.source), "code")) {
        return self.parseBlockCode();
    }

    unreachable;
}

fn parseAttributes(self: *Parser) !std.ArrayList(Span) {
    var attrs = std.ArrayList(Span).init(self.allocator);
    errdefer attrs.deinit();

    while (true) {
        var span: ?Span = null;
        attr: while (true) {
            const token = self.tokens[self.tok_i];
            switch (token.tag) {
                .open_paren => {
                    break :attr;
                },
                .colon => {
                    _ = self.eatToken();
                    break :attr;
                },
                .newline,
                .eof => return self.err(.unterminated_modifier, token),
                else => {
                    _ = self.eatToken();
                    if (span) |*some_span| {
                        some_span.end = token.loc.end_index;
                    } else {
                        span = Span.from(token);
                    }
                }
            }
        }

        if (span) |some_span| {
            try attrs.append(some_span);
        }

        if (self.tokens[self.tok_i].tag == .open_paren) {
            break;
        }
    }

    return attrs;
}

fn eatUntilTokens(self: *Parser, comptime tags: []const Token.Tag) !?Span {
    var span: ?Span = null;
    var token = self.tokens[self.tok_i];
    blk: while (true) {
        inline for (tags) |stop_tag| {
            if (token.tag == stop_tag) {
                break :blk;
            }
        }

        std.debug.print("{s}\n", .{ @tagName(token.tag) });

        if (token.tag == .eof) {
            return self.err(.unexpected_token, token);
        }

        if (span) |*some_span| {
            some_span.end = token.loc.end_index;
        } else {
            span = Span.from(token);
        }

        token = self.nextToken();
    }

    return span;
}

fn parseBlockCode(self: *Parser) !Element {
    var code = Element{
        .block_code = .{
            .children = .init(self.allocator)
        }
    };
    errdefer code.deinit();

    while (true) {
        const span = try self.eatUntilTokens(&.{ .newline, .close_paren });
        if (span) |some_span| {
            _ = try code.addChild(Element{
                .code_literal = some_span
            });
        }

        switch (self.tokens[self.tok_i].tag) {
            .newline => {
                const line_break = try self.expectLineBreak();
                _ = try code.addChild(line_break);
            },
            .close_paren => {
                _ = self.eatToken();
                break;
            },
            else => unreachable,
        }
    }

    return code;
}

fn parseHeading(self: *Parser) !Element {
    const level = self.eatToken().len();
    return Element{
        .heading = .{
            .level = level,
            .children = try self.expectInlineUntilLineBreakOrEof()
        }
    };
}

fn parseParagraph(self: *Parser) !Element {
    return Element{
        .paragraph = .{
            .children = try self.expectInlineUntilLineBreakOrEof()
        }
    };
}

fn expectInlineCode(self: *Parser) !Element {
    const open_backtick_token = self.eatToken();
    var span = Span{
        .start = self.tokens[self.tok_i].loc.start_index,
        .end = self.tokens[self.tok_i].loc.end_index,
    };

    while (true) {
        const token = self.tokens[self.tok_i];
        switch (token.tag) {
            .newline,
            .eof => return self.err(.unterminated_inline_code, open_backtick_token),
            else => {
                if (token.tag == .backtick) {
                    if (token.len() == open_backtick_token.len()) {
                        _ = self.eatToken();
                        break;
                    } else {
                        return self.err(.unexpected_token, token);
                    }
                }

                span.end = token.loc.end_index;
                _ = self.eatToken();
            },
        }
    }

    return Element{
        .inline_code = span
    };
}

fn expectLineBreak(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .newline) {
        return self.err(.unexpected_token, token);
    }

    _ = self.eatToken();
    return Element{
        .line_break = Span.from(token)
    };
}

fn spanUntilLineBreakOrEof(self: *Parser) !Span {
    var token = self.tokens[self.tok_i];
    var span = Span.from(self.tokens[self.tok_i]);
    while (token.tag != .newline and token.tag != .eof) {
        span.end = self.eatToken().loc.start_index;
        token = self.tokens[self.tok_i];
    }

    return span;
}

fn expectInlineUntilLineBreakOrEof(self: *Parser) !std.ArrayList(Element) {
    var children = std.ArrayList(Element).init(self.allocator);
    errdefer children.deinit();

    var token = self.tokens[self.tok_i];
    while (token.tag != .newline and token.tag != .eof) {
        const child_el = try self.parseInline();
        errdefer child_el.deinit();

        _ = try children.append(child_el);

        token = self.tokens[self.tok_i];
    }

    if (children.items.len == 0) {
        return self.err(.unexpected_token, token);
    }

    return children;
}


/// Parses top-level inline elements.
fn parseInline(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    if (modifierTagOrNull(token.tag)) |_| {
        return self.parseInlineModifier();
    } else {
        return self.parseTerminalInline();
    }
}

/// A variant of parseInline that does not recurse.
fn parseTerminalInline(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    switch (token.tag) {
        .backtick => {
            if (token.len() == 1) {
                return self.expectInlineCode();
            } else {
                return self.err(.unexpected_token, token);
            }
        },
        .colon,
        .pound,
        .literal_text => {
            _ = self.eatToken();
            return Element{
                .text = .{
                    .start = token.loc.start_index,
                    .end = token.loc.end_index,
                }
            };
        },
        else => return self.err(.unexpected_token, token),
    }
}

fn parseInlineModifier(self: *Parser) !Element {
    var outer_most_modifier = Element{
        .modifier = .{
            .children = std.ArrayList(Element).init(self.allocator),
            .tag = modifierTag(self.tokens[self.tok_i].tag)
        }
    };
    errdefer outer_most_modifier.deinit();

    var el_stack = std.ArrayList(*Element).init(self.allocator);
    var tag_stack = std.ArrayList(Element.Modifier.Tag).init(self.allocator);
    var token_stack = std.ArrayList(Token).init(self.allocator);
    defer el_stack.deinit();
    defer tag_stack.deinit();
    defer token_stack.deinit();

    try el_stack.append(&outer_most_modifier);
    try tag_stack.append(outer_most_modifier.modifier.tag);
    try token_stack.append(self.eatToken());

    var open_modifier = &outer_most_modifier;
    while (el_stack.items.len > 0) {
        const token = self.tokens[self.tok_i];

        if (modifierTagOrNull(token.tag)) |modifier_tag| {
            const modifier_token = self.eatToken();
            const tags_equal = tag_stack.getLast() == modifier_tag;
            const len_equal = token_stack.getLast().len() == modifier_token.len();
            if (tags_equal and len_equal) {
                // modifier closed, pop from stack
                _ = el_stack.pop();
                _ = tag_stack.pop();
                _ = token_stack.pop();

                if (el_stack.items.len > 0) {
                    open_modifier = el_stack.getLast();
                }
            } else {
                // new modifier opened, push it to stack
                const el = Element{
                    .modifier = .{
                        .children = std.ArrayList(Element).init(self.allocator),
                        .tag = modifier_tag
                    }
                };

                const child_modifier = try open_modifier.addChild(el);
                open_modifier = child_modifier;

                try el_stack.append(child_modifier);
                try tag_stack.append(modifier_tag);
                try token_stack.append(modifier_token);
            }

            continue;
        }

        switch (token.tag) {
            .newline,
            .eof => return self.err(.unterminated_modifier, token_stack.getLast()),
            else => {
                const child_el = try self.parseTerminalInline();
                _ = try open_modifier.addChild(child_el);
            }
        }
    }

    return outer_most_modifier;
}

fn modifierTag(tag: Token.Tag) Element.Modifier.Tag {
    return modifierTagOrNull(tag) orelse unreachable;
}

fn modifierTagOrNull(tag: Token.Tag) ?Element.Modifier.Tag {
    return switch (tag) {
        .asterisk => .bold,
        .forward_slash => .italic,
        .underscore => .underline,
        .tilde => .strikethrough,
        else => null
    };
}

fn nextToken(self: *Parser) Token {
    if (self.tok_i == self.tokens.len - 1) {
        return self.tokens[self.tok_i];
    }

    self.tok_i += 1;
    return self.tokens[self.tok_i];
}

fn eatToken(self: *Parser) Token {
    if (self.tok_i == self.tokens.len - 1) {
        return self.tokens[self.tok_i];
    }

    self.tok_i += 1;
    return self.tokens[self.tok_i - 1];
}

fn err(self: *Parser, tag: Error.Tag, token: Token) error{ ParseError, OutOfMemory } {

    try self.errors.append(.{
        .tag = tag,
        .token = token,
    });

    return error.ParseError;
}

test "fails on unterminated block code" {
    const source = source_builder
        .tok(.backtick, "```")
        .eof();
    defer source_builder.free(source);

    try expectError(
        source,
        .unterminated_block_code,
        source[0],
    );
}

test "fails on unterminated inline code" {
    const source = source_builder
        .tok(.backtick, "`")
        .eof();
    defer source_builder.free(source);

    try expectError(
        source,
        .unterminated_inline_code,
        source[0],
    );
}

test "fails on unterminated modifier at eof" {
    const source = source_builder
        .tok(.asterisk, "*")
        .eof();
    defer source_builder.free(source);

    try expectError(
        source,
        .unterminated_modifier,
        source[0]
    );
}

test "fails on unterminated nested modifier" {
    const source = source_builder
        .tok(.asterisk, "*")
        .tok(.underscore, "_")
        .tok(.asterisk, "*")
        .eof();
    defer source_builder.free(source);

    try expectError(
        source,
        .unterminated_modifier,
        source[2],
    );
}

test "parses modifier" {
    const source = source_builder
        .tok(.literal_text, "a")
        .tok(.asterisk, "*")
        .tok(.literal_text, "a")
        .tok(.asterisk, "*")
        .tok(.literal_text, "a")
        .eof();
    defer source_builder.free(source);

    const expected_ast = AstBuilder.init()
        .paragraph(AstBuilder.init()
            .text(source[0])
            .modifier(.bold, AstBuilder.init()
                .text(source[2])
                .build()
            )
            .text(source[4])
            .build()
        )
        .build();
    defer ast_builder.free(expected_ast);

    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    _ = try parser.parse();

    try std.testing.expectEqual(0, parser.errors.items.len);
    try ast_builder.expectEqual(expected_ast, parser.elements);
}

test "parses nested modifiers" {
    const source = source_builder
        .tok(.asterisk, "*")
        .tok(.forward_slash, "/")
        .tok(.underscore, "_")
        .tok(.tilde, "~")
        .tok(.literal_text, "a")
        .tok(.tilde, "~")
        .tok(.underscore, "_")
        .tok(.forward_slash, "/")
        .tok(.asterisk, "*")
        .eof();
    defer source_builder.free(source);

    const expected_ast = AstBuilder.init()
        .paragraph(AstBuilder.init()
            .modifier(.bold, AstBuilder.init()
                .modifier(.italic, AstBuilder.init()
                    .modifier(.underline, AstBuilder.init()
                        .modifier(.strikethrough, AstBuilder.init()
                            .text(source[4])
                            .build()
                        )
                        .build()
                    )
                    .build()
                )
                .build()
            )
            .build()
        )
        .build();
    defer ast_builder.free(expected_ast);

    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    _ = try parser.parse();

    try std.testing.expectEqual(0, parser.errors.items.len);
    try ast_builder.expectEqual(expected_ast, parser.elements);
}

test "parses pound as literal text" {
    const source = source_builder
        .tok(.literal_text, "a")
        .tok(.pound, "###")
        .tok(.literal_text, "a")
        .eof();
    defer source_builder.free(source);

    const expected_ast = AstBuilder.init()
        .paragraph(AstBuilder.init()
            .text(source[0])
            .text(source[1])
            .text(source[2])
            .build()
        )
        .build();
    defer ast_builder.free(expected_ast);

    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    _ = try parser.parse();

    try std.testing.expectEqual(0, parser.errors.items.len);
    try ast_builder.expectEqual(expected_ast, parser.elements);
}

const source_builder = @import("testing/source_builder.zig");
const ast_builder = @import("testing/ast_builder.zig");
const AstBuilder = ast_builder.AstBuilder;

fn expectError(source: []const Token, expected_err: Error.Tag, expected_token: Token) !void {
    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.ParseError, result);

    const e = parser.errors.items[0];
    try std.testing.expectEqual(e.tag, expected_err);
    try std.testing.expectEqual(e.token, expected_token);
}
