const std = @import("std");
const pos = @import("pos.zig");
const ast = @import("ast.zig");
const Tokenizer = @import("Tokenizer.zig");

pub const ErrorPayload = struct {
    err: Error,
    token: ?Tokenizer.Token,

    pub fn allocMsg(self: *const ErrorPayload, allocator: std.mem.Allocator) ![]const u8 {
        if (self.token) |token| {
            return try std.fmt.allocPrint(
                allocator,
                "{s} ({s}) from {} to {}",
                .{
                    @errorName(self.err),
                    @tagName(token.tag),
                    token.span.start,
                    token.span.end
                }
            );
        } else {
            return try std.fmt.allocPrint(
                allocator,
                "{s}",
                .{
                    @errorName(self.err)
                }
            );
        }
    }
};

const Parser = @This();

allocator: std.mem.Allocator,
tokens: []const Tokenizer.Token,
tok_i: usize,
elements: std.ArrayList(ast.Element),
errors: std.ArrayList(ErrorPayload),

const Error = error{
    UnexpectedEof,
    UnexpectedToken,
    InvalidBlockStart,
    InvalidInlineStart,
    TooManyAttrs,
    EmptyInlineModifier,
    UnterminatedInlineModifier,
    UnindentedCode,
    UnsupportedHeadingSize,
    ParseError
} || std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator, tokens: []const Tokenizer.Token) Parser {
    return .{
        .allocator = allocator,
        .tokens = tokens,
        .tok_i = 0,
        // TODO: use assume capacity strategy that zig uses, ((tokens.len + 2) / 2),
        // but modified for markdown ratio
        .elements = .empty,
        .errors = .empty,
    };
}

pub fn deinit(self: *Parser) void {
    for (self.elements.items) |*el| {
        el.deinit(self.allocator);
    }

    self.elements.deinit(self.allocator);
    self.errors.deinit(self.allocator);
}

pub fn parse(self: *Parser) !void {
    while (self.tokens[self.tok_i].tag != .eof) {
        var el = try self.parseTopLevelElement();
        errdefer el.deinit(self.allocator);
        try self.elements.append(self.allocator, el);
    }
}

/// Parse either a block or inline element.
///
/// Attempts to parse a block element first. If a block element could not be
/// parsed, it will fall back to parsing an inline element.
fn parseTopLevelElement(self: *Parser) !ast.Element {
    if (self.tok_i > 0 and self.tokens[self.tok_i - 1].tag != .newline) {
        // block elements must start on newline
        return self.parseInlineElement();
    }

    const block = self.parseBlockElement() catch |e| {
        if (e == Error.InvalidBlockStart) {
            // fall back to parsing inline element
            _ = self.errors.pop();
            return self.parseInlineElement();
        }

        return e;
    };

    return block;
}

fn parseBlockElement(self: *Parser) !ast.Element {
    const token = self.tokens[self.tok_i];
    return switch (token.tag) {
        .pound => self.parseHeading(),
        .keyword_code => self.parseBlockCode(),
        .keyword_callout => self.parseCallout(),
        else => self.err(Error.InvalidBlockStart, token)
    };
}

fn parseInlineElement(self: *Parser) !ast.Element {
    const token = self.tokens[self.tok_i];
    return switch (token.tag) {
        .inline_code => self.parseInlineCode(),
        .newline => self.parseLineBreak(),
        .escaped_char => self.parseEscapedChar(),
        .literal_text => self.parseLiteralText(),
        .keyword_url => self.parseUrl(),
        .keyword_img => self.parseImg(),
        .empty_inline_code => return self.err(Error.EmptyInlineModifier, token),
        .unterminated_inline_code => return self.err(Error.UnterminatedInlineModifier, token),
        .eof => return self.err(Error.UnexpectedEof, token),
        else => {
            if (modifierTagOrNull(token)) |_| {
                return self.parseInlineModifier();
            } else {
                return self.parseGreedilyAsLiteralText();
                // return self.err(Error.InvalidInlineStart, token);
            }
        }
    };
}

/// Parses a colon-separated list of attributes appearing in instances of
/// directives such as block code.
fn parseOptionalAttributes(self: *Parser, expected_n: u8) Error!std.ArrayList(pos.Span) {
    if (expected_n == 0) {
        unreachable;
    }

    var attrs = std.ArrayList(pos.Span).empty;
    errdefer attrs.deinit(self.allocator);

    while (self.tokens[self.tok_i].tag != .open_paren) {
        var span: ?pos.Span = null;
        attr: while (true) {
            const token = self.tokens[self.tok_i];
            switch (token.tag) {
                .open_paren => {
                    break :attr;
                },
                .colon => {
                    self.skipToken();
                    break :attr;
                },
                .newline,
                .eof => return self.err(Error.UnexpectedToken, token),
                else => {
                    self.skipToken();

                    if (span) |*some_span| {
                        some_span.end = token.span.end;
                    } else {
                        span = token.span;
                    }
                }
            }
        }

        if (span) |some_span| {
            try attrs.append(self.allocator, some_span);
        }
    }

    if (attrs.items.len > expected_n) {
        return self.err(Error.TooManyAttrs, null);
    }

    return attrs;
}

fn parseImg(self: *Parser) Error!ast.Element {
    _ = self.assertToken(.keyword_img);
    self.skipToken();

    _ = try self.expectToken(.open_paren);
    self.skipToken();

    var img = ast.Element{
        .img = .{
            .src = undefined,
            .alt_text = undefined
        }
    };
    errdefer img.deinit(self.allocator);

    img.img.alt_text = try self.spanToNextToken(.semicolon);
    self.skipToken();

    if (try self.spanToNextToken(.close_paren)) |src| {
        img.img.src = src;
    } else {
        return self.err(Error.UnexpectedToken, self.tokens[self.tok_i]);
    }

    _ = self.assertToken(.close_paren);
    self.skipToken();

    return img;
}

fn parseUrl(self: *Parser) Error!ast.Element {
    _ = self.assertToken(.keyword_url);
    self.skipToken();

    _ = try self.expectToken(.open_paren);
    self.skipToken();

    var url = ast.Element{
        .url = .{
            .children = .empty,
            .href = undefined,
        }
    };
    errdefer url.deinit(self.allocator);

    while (self.tokens[self.tok_i].tag != .semicolon) {
        const child = try self.parseInlineElement();
        _ = try url.addChild(self.allocator, child);
    }

    self.skipToken();

    if (try self.spanToNextToken(.close_paren)) |href| {
        url.url.href = href;
    } else {
        return self.err(Error.UnexpectedToken, self.tokens[self.tok_i]);
    }

    _ = self.assertToken(.close_paren);
    self.skipToken();

    return url;
}

fn parseBlockCode(self: *Parser) Error!ast.Element {
    _ = self.assertToken(.keyword_code);
    self.skipToken();

    var attrs = try self.parseOptionalAttributes(1);
    defer attrs.deinit(self.allocator);

    _ = try self.expectToken(.open_paren);
    self.skipToken();

    _ = try self.expectToken(.newline);
    self.skipToken();

    var code = ast.Element{
        .block_code = .{
            .lang = if (attrs.items.len > 0) attrs.items[0] else null,
            .children = .empty
        }
    };
    errdefer code.deinit(self.allocator);

    while (true) {
        switch (self.tokens[self.tok_i].tag) {
            .close_paren => break,
            .newline => {},
            .tab => self.skipToken(),
            else => return self.err(Error.UnindentedCode, self.tokens[self.tok_i])
        }

        if (try self.spanToNextToken(.newline)) |some_span| {
            _ = try code.addChild(self.allocator, ast.Element{
                .code_literal = some_span
            });
        }

        const line_break = try self.parseLineBreak();
        _ = try code.addChild(self.allocator, line_break);
    }

    _ = self.assertToken(.close_paren);
    self.skipToken();

    return code;
}

fn parseCallout(self: *Parser) Error!ast.Element {
    _ = self.assertToken(.keyword_callout);
    self.skipToken();

    var attrs = try self.parseOptionalAttributes(1);
    defer attrs.deinit(self.allocator);

    _ = try self.expectToken(.open_paren);
    self.skipToken();

    var callout = ast.Element{
        .callout = .{
            .style = if (attrs.items.len > 0) attrs.items[0] else null,
            .children = .empty,
        }
    };
    errdefer callout.deinit(self.allocator);

    while (self.tokens[self.tok_i].tag != .close_paren) {
        const child = try self.parseInlineElement();
        _ = try callout.addChild(self.allocator, child);
    }

    _ = self.assertToken(.close_paren);
    self.skipToken();

    return callout;
}

fn parseHeading(self: *Parser) Error!ast.Element {
    const pound_token = self.assertToken(.pound);
    self.skipToken();

    if (pound_token.span.len() > 6) {
        return self.err(Error.UnsupportedHeadingSize, pound_token);
    }

    const children = try self.expectInlineUntilLineBreakOrEof();

    if (self.tokens[self.tok_i].tag == .newline) {
        self.skipToken();
    }

    return ast.Element{
        .heading = .{
            .level = @intCast(pound_token.span.len()),
            .children = children
        }
    };
}

fn parseInlineCode(self: *Parser) Error!ast.Element {
    const token = self.assertToken(.inline_code);
    self.skipToken();
    return ast.Element{
        .inline_code = .{
            // remove the leading backtick
            .start = token.span.start + 1,
            // remove the trailing backtick
            .end = token.span.end - 1
        }
    };
}

fn parseLineBreak(self: *Parser) Error!ast.Element {
    const token = self.assertToken(.newline);
    self.skipToken();
    return ast.Element{
        .line_break = token.span
    };
}

fn parseEscapedChar(self: *Parser) ast.Element {
    const token = self.assertToken(.escaped_char);
    self.skipToken();
    return ast.Element {
        .text = .{
            // remove the backslash from the output
            .start = token.span.start + 1,
            .end = token.span.end
        }
    };
}

fn parseLiteralText(self: *Parser) ast.Element {
    const token = self.assertToken(.literal_text);
    self.skipToken();
    return ast.Element{
        .text = token.span
    };
}

/// Parse anything other than EOF as literal text.
fn parseGreedilyAsLiteralText(self: *Parser) ast.Element {
    if (self.tokens[self.tok_i].tag == .eof) {
        unreachable;
    }

    const token = self.eatToken();
    return ast.Element {
        .text = token.span
    };
}

fn spanToNextToken(self: *Parser, comptime tag: Tokenizer.Token.Tag) !?pos.Span {
    return self.spanToNextTokens(&.{ tag });
}

fn spanToNextTokens(self: *Parser, comptime tags: []const Tokenizer.Token.Tag) !?pos.Span {
    var span: ?pos.Span = null;
    blk: while (true) {
        const token = self.tokens[self.tok_i];
        inline for (tags) |stop_tag| {
            if (token.tag.equals(stop_tag)) {
                break :blk;
            }
        }

        if (token.tag == .eof) {
            return self.err(Error.UnexpectedToken, token);
        }

        if (span) |*some_span| {
            some_span.end = token.span.end;
        } else {
            span = token.span;
        }

        self.skipToken();
    }

    return span;
}

/// Assert the tag of the current token matches `expected_tag`.
///
/// If it does not match, the program panics.
fn assertToken(self: *Parser, expected_tag: Tokenizer.Token.Tag) Tokenizer.Token {
    return self.expectToken(expected_tag) catch unreachable;
}

/// Expects the tag of the current token to match `expected_tag`.
///
/// If it does not match, `Error.UnexpectedToken` is returned.
fn expectToken(self: *Parser, expected_tag: Tokenizer.Token.Tag) Error!Tokenizer.Token {
    const token = self.tokens[self.tok_i];
    if (token.tag != expected_tag) {
        std.log.err("Expected {s} but got {s}", .{ @tagName(expected_tag), @tagName(token.tag) });
        return self.err(Error.UnexpectedToken, token);
    }

    return token;
}

fn expectInlineUntilLineBreakOrEof(self: *Parser) !std.ArrayList(ast.Element) {
    var children = std.ArrayList(ast.Element).empty;
    errdefer children.deinit(self.allocator);

    var token = self.tokens[self.tok_i];
    while (token.tag != .newline and token.tag != .eof) {
        var child_el = try self.parseInlineElement();
        errdefer child_el.deinit(self.allocator);

        _ = try children.append(self.allocator, child_el);
        token = self.tokens[self.tok_i];
    }

    if (children.items.len == 0) {
        return self.err(Error.UnexpectedToken, token);
    }

    return children;
}

fn parseInlineModifier(self: *Parser) Error!ast.Element {
    var open_modifier_token = self.eatToken();

    var outer_most_modifier = ast.Element{
        .modifier = .{
            .children = .empty,
            .tag = modifierTagOrNull(open_modifier_token) orelse unreachable
        }
    };
    errdefer outer_most_modifier.deinit(self.allocator);

    var modifier_el_stack = std.ArrayList(*ast.Element).empty;
    defer modifier_el_stack.deinit(self.allocator);

    try modifier_el_stack.append(self.allocator, &outer_most_modifier);

    while (modifier_el_stack.items.len > 0) {
        const token = self.tokens[self.tok_i];

        if (token.tag == .eof) {
            // TODO: get open token here
            return self.err(Error.UnterminatedInlineModifier, open_modifier_token);
        }

        if (modifierTagOrNull(token)) |modifier_tag| {
            if (modifier_el_stack.getLast().modifier.tag == modifier_tag) {
                // modifier CLOSED, pop from stack
                _ = modifier_el_stack.pop();
            } else {
                // modifier OPENED, push it to stack
                const el = ast.Element{
                    .modifier = .{
                        .children = .empty,
                        .tag = modifier_tag
                    }
                };

                const old_top = modifier_el_stack.getLast();
                _ = try old_top.addChild(self.allocator, el);
                try modifier_el_stack.append(self.allocator, old_top.lastChild());
                open_modifier_token = token;
            }

            self.skipToken();
        } else {
            const child_el = try self.parseInlineElement();
            _ = try modifier_el_stack.getLast().addChild(self.allocator, child_el);
        }
    }

    return outer_most_modifier;
}

fn modifierTagOrNull(token: Tokenizer.Token) ?ast.Element.Modifier.Tag {
    return switch (token.tag) {
        .asterisk => .bold,
        .forward_slash => .italic,
        .underscore => .underline,
        .tilde => .strikethrough,
        else => null,
    };
}

fn skipToken(self: *Parser) void {
    if (self.tok_i == self.tokens.len - 1) {
        return;
    }

    self.tok_i += 1;
}

fn eatToken(self: *Parser) Tokenizer.Token {
    if (self.tok_i == self.tokens.len - 1) {
        return self.tokens[self.tok_i];
    }

    self.tok_i += 1;
    return self.tokens[self.tok_i - 1];
}

fn err(
    self: *Parser,
    e: Error,
    token: ?Tokenizer.Token
) Error {
    try self.errors.append(self.allocator, .{
        .err = e,
        .token = token,
    });

    return e;
}

test "fails on empty inline code" {
    const source = source_builder
        .tok(.empty_inline_code, "``")
        .eof();
    defer source.deinit();

    const tokens = source.tokens;

    try expectError(
        tokens,
        Error.EmptyInlineModifier,
        tokens[0],
    );
}

test "fails on unterminated inline code" {
    const source = source_builder
        .tok(.unterminated_inline_code, "`")
        .eof();
    defer source.deinit();

    const tokens = source.tokens;

    try expectError(
        tokens,
        Error.UnterminatedInlineModifier,
        tokens[0],
    );
}

test "fails on unterminated modifier at eof" {
    const source = source_builder
        .tok(.asterisk, "*")
        .eof();
    defer source.deinit();

    const tokens = source.tokens;

    try expectError(
        tokens,
        Error.UnterminatedInlineModifier,
        tokens[0]
    );
}

test "fails on unterminated nested modifier" {
    const source = source_builder
        .tok(.asterisk, "*")
        .tok(.underscore, "_")
        .eof();
    defer source.deinit();

    const tokens = source.tokens;
    
    try expectError(
        tokens,
        Error.UnterminatedInlineModifier,
        tokens[1],
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
    defer source.deinit();

    const tokens = source.tokens;

    var expected_ast = AstBuilder.init()
        .text(tokens[0])
        .modifier(.bold, AstBuilder.init()
            .text(tokens[2])
            .build()
        )
        .text(tokens[4])
        .build();
    defer ast_builder.free(&expected_ast);

    var parser = Parser.init(
        std.testing.allocator,
        tokens
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
    defer source.deinit();

    const tokens = source.tokens;

    var expected_ast = AstBuilder.init()
        .modifier(.bold, AstBuilder.init()
            .modifier(.italic, AstBuilder.init()
                .modifier(.underline, AstBuilder.init()
                    .modifier(.strikethrough, AstBuilder.init()
                        .text(tokens[4])
                        .build()
                    )
                    .build()
                )
                .build()
            )
            .build()
        )
    .build();
    defer ast_builder.free(&expected_ast);

    var parser = Parser.init(
        std.testing.allocator,
        tokens
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
    defer source.deinit();

    const tokens = source.tokens;

    var expected_ast = AstBuilder.init()
        .text(tokens[0])
        .text(tokens[1])
        .text(tokens[2])
        .build();
    defer ast_builder.free(&expected_ast);

    var parser = Parser.init(
        std.testing.allocator,
        tokens
    );
    defer parser.deinit();

    _ = try parser.parse();

    try std.testing.expectEqual(0, parser.errors.items.len);
    try ast_builder.expectEqual(expected_ast, parser.elements);
}

test "parses block code" {
    const source = source_builder
        .tok(.keyword_code, "@code")
        .eof();
    defer source.deinit();

}

const source_builder = @import("testing/source_builder.zig");
const ast_builder = @import("testing/ast_builder.zig");
const AstBuilder = ast_builder.AstBuilder;

fn expectError(
    source: []const Tokenizer.Token,
    expected_err: Error,
    expected_token: Tokenizer.Token
) !void {
    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(expected_err, result);

    const e = parser.errors.items[0];
    try std.testing.expectEqual(expected_err, e.err);
    try std.testing.expectEqual(expected_token, e.token);
}
