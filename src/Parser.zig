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
            .heading => blk: {
                if (token.len() > 6) {
                    return self.err(.invalid_token, token);
                }

                _ = self.eatToken();
                const inline_el = try self.eatText();
                const line_break = try self.eatLineBreak();

                var heading = Element.initNode(self.allocator, .heading);
                errdefer heading.deinit();

                try heading.addChild(inline_el);
                try heading.addChild(line_break);

                break :blk heading;
            },
            .newline => try self.eatLineBreak(),
            .literal_text => try self.eatText(),
            .underscore => try self.parseInlineModifier(.italic),
            .asterisk => try self.parseInlineModifier(.bold),
            .backtick =>
                switch (token.len()) {
                    1 => try self.parseInlineCode(),
                    2 => return self.err(.empty_inline_code, token),
                    3 => try self.parseBlockCode(),
                    6 => return self.err(.empty_block_code, token),
                    else => return self.err(.invalid_token, token),
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

fn parseInlineCode(self: *Parser) !Element {
    const open_backtick_token = self.eatToken();

    var code_el = Element.initNode(self.allocator, .code);
    errdefer code_el.deinit();

    while (true) {
        const token = self.tokens[self.tok_i];
        switch (token.tag) {
            .eof => return self.err(.unterminated_inline_code, open_backtick_token),
            .newline => return self.err(.unexpected_token, token),
            else => {
                if (token.tag == .backtick and token.len() == open_backtick_token.len()) {
                    _ = self.eatToken();
                    break;
                }

                const child = Element.initLeaf(.code_literal, token);
                try code_el.addChild(child);
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
                try code_el.addChild(child);
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
                try code_el.addChild(child);
                _ = self.eatToken();
            }
        }
    }

    return code_el;
}

fn eatLineBreak(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .newline) {
        return self.err(.unexpected_token, token);
    }

    _ = self.eatToken();
    return Element.initLeaf(.line_break, token);
}

fn eatText(self: *Parser) !Element {
    const token = self.tokens[self.tok_i];
    if (token.tag != .literal_text) {
        return self.err(.unexpected_token, token);
    }

    _ = self.eatToken();
    return Element.initLeaf(.text, token);
}

fn parseInlineModifier(self: *Parser, node_tag: Element.Node.Tag) !Element {
    // TODO: throw error if closing modifier starts on newline, but opening doesn't
    // (and vice-versa)

    var top_node = Element.initNode(self.allocator, node_tag);
    errdefer top_node.deinit();

    var el_stack = std.ArrayList(Element).init(self.allocator);
    var tag_stack = std.ArrayList(Element.Node.Tag).init(self.allocator);
    var token_stack = std.ArrayList(Token).init(self.allocator);
    defer el_stack.deinit();
    defer tag_stack.deinit();
    defer token_stack.deinit();

    try el_stack.append(top_node);
    try tag_stack.append(node_tag);
    try token_stack.append(self.eatToken());

    var top_of_stack = &top_node;
    while (el_stack.items.len > 0) {
        const token = self.tokens[self.tok_i];

        switch (token.tag) {
            .asterisk,
            .underscore => |tag| {
                const modifier_tag = elementTagFromTokenTag(tag);
                const modifier_token = self.eatToken();

                if (tag_stack.getLast() == modifier_tag) {
                    // modifier closed, pop from stack
                    _ = el_stack.pop();
                    _ = tag_stack.pop();
                    _ = token_stack.pop();

                    if (el_stack.items.len > 0) {
                        top_of_stack = &el_stack.items[el_stack.items.len - 1];
                    } else {
                    }
                } else {
                    const modifier_node = Element.initNode(
                        self.allocator,
                        modifier_tag,
                    );

                    // TODO: need errdefer here?

                    // modifier opened, push onto stack
                    try el_stack.append(modifier_node);
                    try tag_stack.append(modifier_tag);
                    try token_stack.append(modifier_token);
                    
                    try top_of_stack.addChild(modifier_node);

                    // set it to the child we just added
                    top_of_stack = top_of_stack.lastChild();
                }
            },
            .literal_text => {
                const text_el = try self.eatText();
                try top_of_stack.addChild(text_el);
            },
            .eof => return self.err(.unterminated_modifier, token_stack.getLast()),
            .newline => return self.err(.unexpected_token, token),
            else => unreachable
        }
    }

    return top_node;
}

fn elementTagFromTokenTag(tag: Token.Tag) Element.Node.Tag {
    switch (tag) {
        .asterisk => return .bold,
        .underscore => return .italic,
        else => unreachable
    }
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
        .unexpected_token =>
            std.log.err(
                "Unexpected token ({s}) from {} to {}", .{
                    @tagName(token.tag),
                    token.loc.start_index,
                    token.loc.end_index 
                }
            ),
        .invalid_token =>
            std.log.err(
                "Invalid token ({s}) from {} to {}", .{
                    @tagName(token.tag),
                    token.loc.start_index,
                    token.loc.end_index 
                }
            ),
        .unterminated_modifier =>
            std.log.err(
                "Unterminated inline modifier ({s})", .{
                    @tagName(token.tag)
                }
            ),
        .no_line_break_before_block_code =>
            std.log.err(
                "No line break before code block", .{}
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

test "fails on unterminated block code" {
    const source = source_builder
        .tok(.backtick, 3)
        .eof();
    defer source_builder.free(source);

    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.ParseError, result);

    const e = parser.errors.items[0];
    try std.testing.expectEqual(e.tag, .unterminated_block_code);
}

test "fails on unterminated inline code" {
    const source = source_builder
        .tok(.backtick, 1)
        .eof();
    defer source_builder.free(source);

    var parser = Parser.init(
        std.testing.allocator,
        source
    );
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.ParseError, result);

    const e = parser.errors.items[0];
    try std.testing.expectEqual(e.tag, .unterminated_inline_code);
}
