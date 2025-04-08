const std = @import("std");
const ast = @import("ast.zig");
const Tokenizer = @import("Tokenizer.zig");

const Token = Tokenizer.Token;
const Element = ast.Element;
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
            .eof => return,
            else => try self.parseParagraph(),
        };

        try self.elements.append(el);
    }
}

fn parseHeading(self: *Parser) !Element {
    _ = self.eatToken();
    return Element{
        .node = .{
            .tag = .heading,
            .children = try self.expectInlineUntilLineBreakOrEof()
        }
    };
}

fn parseParagraph(self: *Parser) !Element {
    return Element{
        .node = .{
            .tag = .paragraph,
            .children = try self.expectInlineUntilLineBreakOrEof()
        }
    };
}

fn expectInlineCode(self: *Parser) !Element {
    const open_backtick_token = self.eatToken();

    var code_el = Element.initNode(self.allocator, .code);
    errdefer code_el.deinit();

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

                const child = Element.initLeaf(.code_literal, token);
                _ = try code_el.addChild(child);
                _ = self.eatToken();
            },
        }
    }

    return code_el;
}

fn parseBlockCode(self: *Parser) !Element {
    if (self.tok_i > 0 and self.tokens[self.tok_i - 1].tag != .newline) {
        return self.err(.no_line_break_before_block_code, self.tokens[self.tok_i]);
    }

    const open_backtick_token = self.eatToken();
    var code_el = Element.initNode(self.allocator, .code);
    errdefer code_el.deinit();

    while (true) {
        const token = self.tokens[self.tok_i];
        switch (token.tag) {
            .eof => return self.err(.unterminated_block_code, open_backtick_token),
            .newline => {
                const child = Element.initLeaf(.line_break, token);
                _ = try code_el.addChild(child);
                _ = self.eatToken();
            },
            else => {
                if (token.tag == .backtick and token.len() == open_backtick_token.len()) {
                    const previous_token = self.tokens[self.tok_i - 1];
                    if (previous_token.tag == .newline) {
                        _ = self.eatToken();
                        break;
                    } else {
                        return self.err(.no_line_break_before_block_code, token);
                    }
                }

                const child = Element.initLeaf(.code_literal, token);
                _ = try code_el.addChild(child);
                _ = self.eatToken();
            }
        }
    }

    return code_el;
}

fn expectLineBreak(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .newline) {
        return self.err(.unexpected_token, token);
    }

    _ = self.eatToken();
    return Element.initLeaf(.line_break, token);
}

fn expectInlineUntilLineBreakOrEof(self: *Parser) !Element.Node.Children {
    var children = std.ArrayList(Element).init(self.allocator);
    errdefer children.deinit();

    var token = self.tokens[self.tok_i];
    while (token.tag != .newline and token.tag != .eof) {
        const child_el = try self.parseInline();
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
    switch (token.tag) {
        .asterisk,
        .underscore,
        .tilde => return self.parseInlineModifier(),
        else => return self.parseTerminalInline()
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
        .bang,
        .pound,
        .literal_text => {
            _ = self.eatToken();
            return Element.initLeaf(.text, token);
        },
        else => return self.err(.unexpected_token, token),
    }
}

fn parseInlineModifier(self: *Parser) !Element {
    // TODO: throw error if closing modifier starts on newline, but opening doesn't
    // (and vice-versa)

    const initial_modifier_tag = elementTagFromTokenTag(self.tokens[self.tok_i].tag);

    var top_node = Element.initNode(self.allocator, initial_modifier_tag);
    errdefer top_node.deinit();

    var el_stack = std.ArrayList(*Element).init(self.allocator);
    var tag_stack = std.ArrayList(Element.Node.Tag).init(self.allocator);
    var token_stack = std.ArrayList(Token).init(self.allocator);
    defer el_stack.deinit();
    defer tag_stack.deinit();
    defer token_stack.deinit();

    try el_stack.append(&top_node);
    try tag_stack.append(initial_modifier_tag);
    try token_stack.append(self.eatToken());

    var top_of_stack = &top_node;
    while (el_stack.items.len > 0) {
        const token = self.tokens[self.tok_i];

        switch (token.tag) {
            .asterisk,
            .underscore,
            .tilde => |tag| {
                const modifier_tag = elementTagFromTokenTag(tag);
                const modifier_token = self.eatToken();

                const tags_equal = tag_stack.getLast() == modifier_tag;
                const len_equal = token_stack.getLast().len() == modifier_token.len();
                if (tags_equal and len_equal) {
                    // modifier closed, pop from stack
                    _ = el_stack.pop();
                    _ = tag_stack.pop();
                    _ = token_stack.pop();

                    if (el_stack.items.len > 0) {
                        top_of_stack = el_stack.getLast();
                    }
                } else {
                    const new_top = try top_of_stack.addChild(Element.initNode(
                        self.allocator,
                        modifier_tag,
                    ));

                    top_of_stack = new_top;

                    // modifier opened, push onto stack
                    try el_stack.append(new_top);
                    try tag_stack.append(modifier_tag);
                    try token_stack.append(modifier_token);
                }
            },
            .newline,
            .eof => return self.err(.unterminated_modifier, token_stack.getLast()),
            else => {
                const child_el = try self.parseTerminalInline();
                _ = try top_of_stack.addChild(child_el);
            }
        }
    }

    return top_node;
}

fn elementTagFromTokenTag(tag: Token.Tag) Element.Node.Tag {
    return switch (tag) {
        .asterisk => .bold,
        .underscore => .italic,
        .tilde => .strikethrough,
        else => unreachable
    };
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

    const expected_ast = ast_builder
        .node(.paragraph, ast_builder
            .leaf(.text, source[0])
            .node(.bold, ast_builder
                .leaf(.text, source[2])
                .build()
            )
            .leaf(.text, source[4])
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
        .tok(.underscore, "_")
        .tok(.asterisk, "*")
        .tok(.literal_text, "a")
        .tok(.asterisk, "*")
        .tok(.underscore, "_")
        .eof();
    defer source_builder.free(source);

    const expected_ast = ast_builder
        .node(.paragraph, ast_builder
            .node(.italic, ast_builder
                .node(.bold, ast_builder
                    .leaf(.text, source[2])
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

    const expected_ast = ast_builder
        .node(.paragraph, ast_builder
            .leaf(.text, source[0])
            .leaf(.text, source[1])
            .leaf(.text, source[2])
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
