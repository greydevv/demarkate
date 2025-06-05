const std = @import("std");
const pos = @import("pos.zig");
const ast = @import("ast.zig");
const Tokenizer = @import("Tokenizer.zig");

pub const ParseError = struct {
    tag: Tag,
    token: Tokenizer.Token,

    pub const Tag = enum {
        unexpected_token,
        unterminated_modifier,
        unterminated_block_code,
        unterminated_inline_code,
    };

    pub fn allocMsg(self: *const ParseError, allocator: std.mem.Allocator) ![]const u8 {
        const tag = self.tag;
        const token = self.token;

        const msg = switch(tag) {
            .unexpected_token =>
                std.fmt.allocPrint(
                    allocator,
                    "Unexpected token ({s}) from {} to {}", .{
                        @tagName(token.tag),
                        token.span.start,
                        token.span.end
                    }
                ),
            .unterminated_modifier =>
                std.fmt.allocPrint(
                    allocator,
                    "Unterminated inline modifier ({s})", .{
                        @tagName(token.tag)
                    }
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

const Context = enum {
    @"inline",
    block
};

const Parser = @This();

allocator: std.mem.Allocator,
tokens: []const Tokenizer.Token,
tok_i: usize,
elements: std.ArrayList(ast.Element),
errors: std.ArrayList(ParseError),

const Error = std.mem.Allocator.Error || error{ ParseError };

pub fn init(allocator: std.mem.Allocator, tokens: []const Tokenizer.Token) Parser {
    return .{
        .allocator = allocator,
        .tokens = tokens,
        .tok_i = 0,
        // TODO: use assume capacity strategy that zig uses, ((tokens.len + 2) / 2),
        // but modified for markdown ratio
        .elements = .init(allocator),
        .errors = .init(allocator),
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
    while (self.tokens[self.tok_i].tag != .eof) {
        const el = switch (self.tokens[self.tok_i].tag) {
            .pound => try self.parseHeading(),
            .newline => try self.parseLineBreak(),
            .keyword_code,
            .keyword_img,
            .keyword_url,
            .keyword_callout => try self.parseDirective(),
            else => try self.parseInline(),
        };
        errdefer el.deinit();

        try self.elements.append(el);
    }
}

fn parseDirective(self: *Parser) Error!ast.Element {
    const keyword_tag = self.eatToken().tag;

    const attrs = try self.parseAttributes();
    defer attrs.deinit();

    if (self.tokens[self.tok_i].tag == .open_angle) {
        self.skipToken();
    } else {
        return self.err(.unexpected_token, self.tokens[self.tok_i]);
    }

    // TOOD: may not need union? can just assert here, e.g.
    // switch (token.tag) { .keyword_code, .keyword_etc }.
    // Seemingly no need for indirection.
    return switch (keyword_tag) {
        .keyword_code => try self.parseBlockCode(attrs),
        .keyword_img => try self.parseImg(attrs),
        .keyword_url => try self.parseUrl(attrs),
        .keyword_callout => try self.parseCallout(attrs),
        else => unreachable,
    };
}

fn parseAttributes(self: *Parser) !std.ArrayList(pos.Span) {
    var attrs = std.ArrayList(pos.Span).init(self.allocator);
    errdefer attrs.deinit();

    while (self.tokens[self.tok_i].tag != .open_angle) {
        var span: ?pos.Span = null;
        attr: while (true) {
            const token = self.tokens[self.tok_i];
            switch (token.tag) {
                .open_angle => {
                    break :attr;
                },
                .colon => {
                    self.skipToken();
                    break :attr;
                },
                .newline,
                .eof => return self.err(.unexpected_token, token),
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
            try attrs.append(some_span);
        }
    }

    return attrs;
}

fn parseCallout(self: *Parser, _: ?std.ArrayList(pos.Span)) Error!ast.Element {
    var callout = ast.Element{
        .callout = .{
            .type = undefined,
            .children = .init(self.allocator),
        }
    };
    errdefer callout.deinit();

    callout.callout.type = try self.eatUntilTokens(&.{ .semicolon });
    self.skipToken();

    while (self.tokens[self.tok_i].tag != .close_angle) {
        const child = try self.parseInline();
        _ = try callout.addChild(child);
    }

    self.skipToken();

    return callout;
}

fn parseImg(self: *Parser, _: ?std.ArrayList(pos.Span)) Error!ast.Element {
    var img = ast.Element{
        .img = .{
            .src = undefined,
            .alt_text = undefined
        }
    };
    errdefer img.deinit();

    img.img.alt_text = try self.eatUntilTokens(&.{ .semicolon });
    self.skipToken();

    if (try self.eatUntilTokens(&.{ .close_angle })) |src| {
        img.img.src = src;
        self.skipToken();
    } else {
        return self.err(.unexpected_token, self.tokens[self.tok_i]);
    }

    return img;
}

fn parseUrl(self: *Parser, _: ?std.ArrayList(pos.Span)) Error!ast.Element {
    var url = ast.Element{
        .url = .{
            .children = .init(self.allocator),
            .href = undefined,
        }
    };
    errdefer url.deinit();

    while (self.tokens[self.tok_i].tag != .semicolon) {
        const child = try self.parseInline();
        _ = try url.addChild(child);
    }

    self.skipToken();

    if (try self.eatUntilTokens(&.{ .close_angle })) |href| {
        url.url.href = href;
        self.skipToken();
    } else {
        return self.err(.unexpected_token, self.tokens[self.tok_i]);
    }

    return url;
}

fn parseBlockCode(self: *Parser, attrs: std.ArrayList(pos.Span)) Error!ast.Element {
    const lang = if (attrs.items.len > 0) attrs.items[0] else null;

    var code = ast.Element{
        .block_code = .{
            .lang = lang,
            .children = .init(self.allocator)
        }
    };
    errdefer code.deinit();

    while (true) {
        const span = try self.eatUntilTokens(&.{ .newline, .close_angle });
        if (span) |some_span| {
            _ = try code.addChild(ast.Element{
                .code_literal = some_span
            });
        }

        switch (self.tokens[self.tok_i].tag) {
            .newline => {
                const line_break = try self.parseLineBreak();
                _ = try code.addChild(line_break);
            },
            .close_angle => {
                self.skipToken();
                break;
            },
            else => unreachable,
        }
    }

    return code;
}

fn eatUntilTokens(self: *Parser, comptime tags: []const Tokenizer.Token.Tag) !?pos.Span {
    var span: ?pos.Span = null;
    blk: while (true) {
        const token = self.tokens[self.tok_i];
        inline for (tags) |stop_tag| {
            if (token.tag.equals(stop_tag)) {
                break :blk;
            }
        }

        if (token.tag == .eof) {
            return self.err(.unexpected_token, token);
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

fn parseHeading(self: *Parser) Error!ast.Element {
    const level = self.eatToken().span.len();
    const children = try self.expectInlineUntilLineBreakOrEof();
    return ast.Element{
        .heading = .{
            .level = level,
            .children = children
        }
    };
}

fn parseInlineCode(self: *Parser) Error!ast.Element {
    const open_token = self.eatToken();
    var span = self.tokens[self.tok_i].span;

    while (true) {
        const token = self.tokens[self.tok_i];
        switch (token.tag) {
            .newline,
            .eof => return self.err(.unterminated_inline_code, open_token),
            else => {
                if (token.tag.equals(open_token.tag) and token.span.len() == open_token.span.len()) {
                    self.skipToken();
                    break;
                }

                span.end = token.span.end;
                self.skipToken();
            },
        }
    }

    return ast.Element{
        .inline_code = span
    };
}

fn parseLineBreak(self: *Parser) Error!ast.Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .newline) {
        return self.err(.unexpected_token, token);
    }

    _ = self.skipToken();
    return ast.Element{
        .line_break = token.span
    };
}

fn expectInlineUntilLineBreakOrEof(self: *Parser) !std.ArrayList(ast.Element) {
    var children = std.ArrayList(ast.Element).init(self.allocator);
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

fn parseInline(self: *Parser) Error!ast.Element {
    const token = self.tokens[self.tok_i];
    if (modifierTagOrNull(token)) |_| {
        return self.parseInlineModifier();
    }

    return switch (token.tag) {
        .eof => self.err(.unexpected_token, token),
        .backtick => self.parseInlineCode(),
        .keyword_code,
        .keyword_img,
        .keyword_url,
        .keyword_callout => self.parseDirective(),
        else => ast.Element{
            .text = self.eatToken().span
        },
    };
}

fn parseInlineModifier(self: *Parser) Error!ast.Element {
    var outer_most_modifier = ast.Element{
        .modifier = .{
            .children = .init(self.allocator),
            .tag = modifierTag(self.eatToken())
        }
    };
    errdefer outer_most_modifier.deinit();

    var el_stack = std.ArrayList(*ast.Element).init(self.allocator);
    defer el_stack.deinit();

    try el_stack.append(&outer_most_modifier);

    while (el_stack.items.len > 0) {
        const token = self.tokens[self.tok_i];

        if (modifierTagOrNull(token)) |modifier_tag| {
            if (el_stack.getLast().modifier.tag == modifier_tag) {
                // modifier CLOSED, pop from stack
                _ = el_stack.pop();
            } else {
                // modifier OPENED, push it to stack
                const el = ast.Element{
                    .modifier = .{
                        .children = .init(self.allocator),
                        .tag = modifier_tag
                    }
                };

                const old_top = el_stack.getLast();
                _ = try old_top.addChild(el);
                try el_stack.append(old_top.lastChild());
            }

            self.skipToken();
        } else {
            const child_el = try self.parseInline();
            _ = try el_stack.getLast().addChild(child_el);
        }
    }

    return outer_most_modifier;
}

fn modifierTag(token: Tokenizer.Token) ast.Element.Modifier.Tag {
    return modifierTagOrNull(token) orelse unreachable;
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
    tag: ParseError.Tag,
    token: Tokenizer.Token
) Error {
    try self.errors.append(.{
        .tag = tag,
        .token = token,
    });

    return error.ParseError;
}

test "fails on unterminated inline code" {
    const source = source_builder
        .tok(.backtick, "`")
        .eof();
    defer source.deinit();

    const tokens = source.tokens;

    try expectError(
        tokens,
        .unterminated_inline_code,
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
        .unexpected_token,
        tokens[1]
    );
}

test "fails on unterminated nested modifier" {
    const source = source_builder
        .tok(.asterisk, "*")
        .tok(.underscore, "_")
        .tok(.asterisk, "*")
        .eof();
    defer source.deinit();

    const tokens = source.tokens;
    
    try expectError(
        tokens,
        .unexpected_token,
        tokens[3],
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

    const expected_ast = AstBuilder.init()
        .text(tokens[0])
        .modifier(.bold, AstBuilder.init()
            .text(tokens[2])
            .build()
        )
        .text(tokens[4])
        .build();
    defer ast_builder.free(expected_ast);

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

    const expected_ast = AstBuilder.init()
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
    defer ast_builder.free(expected_ast);

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

    const expected_ast = AstBuilder.init()
        .text(tokens[0])
        .text(tokens[1])
        .text(tokens[2])
        .build();
    defer ast_builder.free(expected_ast);

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
    expected_err: ParseError.Tag,
    expected_token: Tokenizer.Token
) !void {
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
