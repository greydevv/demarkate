const std = @import("std");
const ast = @import("ast.zig");
const Tokenizer = @import("Tokenizer.zig");

const Token = Tokenizer.Token;
const Element = ast.Element;
const Span = ast.Span;
const Allocator = std.mem.Allocator;

const Parser = @This();

const Error = Allocator.Error || error{ ParseError };

pub const ParseError = struct {
    tag: Tag,
    token: Token,

    pub const Tag = enum {
        unexpected_token,
        unterminated_modifier,
        unterminated_block_code,
        unterminated_inline_code,
    };

    pub fn allocMsg(self: *const ParseError, allocator: Allocator) ![]const u8 {
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

allocator: Allocator,
tokens: []const Token,
tok_i: usize,
elements: std.ArrayList(Element),
errors: std.ArrayList(ParseError),

pub fn init(allocator: Allocator, tokens: []const Token) Parser {
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
            .keyword => try self.parseBuiltIn(),
            .ampersat => try self.parseBuiltIn(),
            else => try self.parseParagraph(),
        };
        errdefer el.deinit();

        try self.elements.append(el);
    }
}

fn parseBuiltIn(self: *Parser) Error!Element {
    const keyword_tag = self.eatToken().tag.keyword;

    const attrs = try self.parseAttributes();
    defer attrs.deinit();

    if (self.tokens[self.tok_i].tag == .open_angle) {
        self.nextToken();
    } else {
        return self.err(.unexpected_token, self.tokens[self.tok_i]);
    }

    // TOOD: may not need union? can just assert here, e.g.
    // switch (token.tag) { .keyword_code, .keyword_etc }.
    // Seemingly no need for indirection.
    return switch (keyword_tag) {
        .code => try self.parseBlockCode(attrs),
        .img => try self.parseImg(attrs),
        .url => try self.parseUrl(attrs),
    };
}

fn parseAttributes(self: *Parser) !std.ArrayList(Span) {
    var attrs = std.ArrayList(Span).init(self.allocator);
    errdefer attrs.deinit();

    while (self.tokens[self.tok_i].tag != .open_angle) {
        var span: ?Span = null;
        attr: while (true) {
            const token = self.tokens[self.tok_i];
            switch (token.tag) {
                .open_angle => {
                    break :attr;
                },
                .colon => {
                    self.nextToken();
                    break :attr;
                },
                .newline,
                .eof => return self.err(.unexpected_token, token),
                else => {
                    self.nextToken();

                    if (span) |*some_span| {
                        some_span.end = token.loc.end_index;
                    } else {
                        span = .from(token);
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

fn parseInlineBuiltIn(self: *Parser) Error!Element {
    const tag = self.eatToken().tag.keyword;

    switch (tag) {
        else => unreachable,
    }
}

fn parseImg(self: *Parser, _: ?std.ArrayList(Span)) Error!Element {
    const url = (try self.parseUrl(null)).url;
    const img = Element{
        .img = .{
            .children = url.children,
            .src = url.href,
        }
    };

    return img;
}

fn parseUrl(self: *Parser, _: ?std.ArrayList(Span)) Error!Element {
    var url = Element{
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

    self.nextToken();



    if (try self.eatUntilTokens(&.{ .close_angle })) |href| {
        // TODO: lol
        url.url.href = href;
    } else {
        return self.err(.unexpected_token, self.tokens[self.tok_i]);
    }


    self.nextToken();

    return url;
}

fn parseBlockCode(self: *Parser, attrs: std.ArrayList(Span)) Error!Element {
    const lang = if (attrs.items.len > 0) attrs.items[0] else null;

    var code = Element{
        .block_code = .{
            .lang = lang,
            .children = .init(self.allocator)
        }
    };
    errdefer code.deinit();

    while (true) {
        const span = try self.eatUntilTokens(&.{ .newline, .close_angle });
        if (span) |some_span| {
            _ = try code.addChild(Element{
                .code_literal = some_span
            });
        }

        switch (self.tokens[self.tok_i].tag) {
            .newline => {
                const line_break = try self.parseLineBreak();
                _ = try code.addChild(line_break);
            },
            .close_angle => {
                self.nextToken();
                break;
            },
            else => unreachable,
        }
    }

    return code;
}

fn eatUntilTokens(self: *Parser, comptime tags: []const Token.Tag) !?Span {
    var span: ?Span = null;
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
            some_span.end = token.loc.end_index;
        } else {
            span = .from(token);
        }

        self.nextToken();
    }

    return span;
}

fn parseHeading(self: *Parser) Error!Element {
    const level = self.eatToken().len();
    const children = try self.expectInlineUntilLineBreakOrEof();
    return Element{
        .heading = .{
            .level = level,
            .children = children
        }
    };
}

fn parseParagraph(self: *Parser) Error!Element {
    const children = try self.expectInlineUntilLineBreakOrEof();
    return Element{
        .paragraph = .{
            .children = children
        }
    };
}

fn parseInlineCode(self: *Parser) Error!Element {
    const open_token = self.eatToken();
    var span = Span.from(self.tokens[self.tok_i]);

    while (true) {
        const token = self.tokens[self.tok_i];
        switch (token.tag) {
            .newline,
            .eof => return self.err(.unterminated_inline_code, open_token),
            else => {
                if (token.tag.equals(open_token.tag) and token.len() == open_token.len()) {
                    self.nextToken();
                    break;
                }

                span.end = token.loc.end_index;
                self.nextToken();
            },
        }
    }

    return Element{
        .inline_code = span
    };
}

fn parseLineBreak(self: *Parser) Error!Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .newline) {
        return self.err(.unexpected_token, token);
    }

    _ = self.nextToken();
    return Element{
        .line_break = Span.from(token)
    };
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

fn parseInline(self: *Parser) Error!Element {
    const token = self.tokens[self.tok_i];
    if (modifierTagOrNull(token)) |_| {
        return self.parseInlineModifier();
    }

    return switch (token.tag) {
        .eof => self.err(.unexpected_token, token),
        .backtick => self.parseInlineCode(),
        .keyword => self.parseBuiltIn(),
        else => Element{
            .text = .from(self.eatToken())
        },
    };
}

fn parseInlineModifier(self: *Parser) Error!Element {
    var outer_most_modifier = Element{
        .modifier = .{
            .children = .init(self.allocator),
            .tag = modifierTag(self.eatToken())
        }
    };
    errdefer outer_most_modifier.deinit();

    var el_stack = std.ArrayList(*Element).init(self.allocator);
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
                const el = Element{
                    .modifier = .{
                        .children = .init(self.allocator),
                        .tag = modifier_tag
                    }
                };

                const old_top = el_stack.getLast();
                _ = try old_top.addChild(el);
                try el_stack.append(old_top.lastChild());
            }

            self.nextToken();
        } else {
            const child_el = try self.parseInline();
            _ = try el_stack.getLast().addChild(child_el);
        }
    }

    return outer_most_modifier;
}

fn modifierTag(token: Token) Element.Modifier.Tag {
    return modifierTagOrNull(token) orelse unreachable;
}

fn modifierTagOrNull(token: Token) ?Element.Modifier.Tag {
    return switch (token.tag) {
        .asterisk => .bold,
        .forward_slash => .italic,
        .underscore => .underline,
        .tilde => .strikethrough,
        else => null,
    };
}

fn nextToken(self: *Parser) void {
    if (self.tok_i == self.tokens.len - 1) {
        return;
    }

    self.tok_i += 1;
}

fn eatToken(self: *Parser) Token {
    if (self.tok_i == self.tokens.len - 1) {
        return self.tokens[self.tok_i];
    }

    self.tok_i += 1;
    return self.tokens[self.tok_i - 1];
}

fn err(self: *Parser, tag: ParseError.Tag, token: Token) error{ ParseError, OutOfMemory } {

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
    defer source_builder.free(source);

    const tokens = source.tokens;

    try expectError(
        source,
        .unterminated_inline_code,
        tokens[0],
    );
}

test "fails on unterminated modifier at eof" {
    const source = source_builder
        .tok(.asterisk, "*")
        .eof();
    defer source_builder.free(source);

    const tokens = source.tokens;

    try expectError(
        source,
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
    defer source_builder.free(source);

    const tokens = source.tokens;
    
    try expectError(
        source,
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
    defer source_builder.free(source);

    const tokens = source.tokens;

    const expected_ast = AstBuilder.init()
        .paragraph(AstBuilder.init()
            .text(tokens[0])
            .modifier(.bold, AstBuilder.init()
                .text(tokens[2])
                .build()
            )
            .text(tokens[4])
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

    const tokens = source.tokens;

    const expected_ast = AstBuilder.init()
        .paragraph(AstBuilder.init()
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

    const tokens = source.tokens;

    const expected_ast = AstBuilder.init()
        .paragraph(AstBuilder.init()
            .text(tokens[0])
            .text(tokens[1])
            .text(tokens[2])
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

test "parses block code" {
    const source = source_builder
        .tok(.{ .keyword = .code }, "@code")
        .eof();
    defer source_builder.free(source);

}

const source_builder = @import("testing/source_builder.zig");
const ast_builder = @import("testing/ast_builder.zig");
const AstBuilder = ast_builder.AstBuilder;

fn expectError(source: []const Token, expected_err: ParseError.Tag, expected_token: Token) !void {
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
