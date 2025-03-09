const Lexer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Token = @import("Token.zig");

pos: u32,
char: u8,
buf: []const u8,

const Error = Allocator.Error || error{EmptySourceBuf};

pub fn init(allocator: Allocator, source_buf: []const u8) Error!*Lexer {
    if (source_buf.len == 0) {
        return Error.EmptySourceBuf;
    }

    const lexer = try allocator.create(Lexer);

    lexer.* = .{
        .pos = 0,
        .char = source_buf[0],
        .buf = source_buf,
    };

    return lexer;
}

pub fn deinit(self: *Lexer, allocator: Allocator) void {
    allocator.destroy(self);
}

pub fn nextToken(self: *Lexer) Token {
    if (self.atEof()) {
        return Token.eof;
    }

    var kind: Token.Kind = undefined;
    var value: []const u8 = undefined;

    kind, value = switch (self.char) {
        '#' => .{ .HEADING, self.lexHeading() },
        '*' => .{ .ASTERISK, self.lexRepeating('*') },
        '`' => .{ .CODE_FENCE, self.lexRepeating('`') },
        '\n' => .{ .NEWLINE, self.lexRepeating('\n') },
        '>' => .{ .GREATER_THAN, self.lexOne() },
        '[', ']' => .{ .BRACKET_SQUARE, self.lexOne() },
        '(', ')' => .{ .BRACKET_PAREN, self.lexOne() },
        170 => return Token.eof,
        else => .{ .INLINE_TEXT, self.lexInlineText() }
    };

    return .{
        .value = value,
        .kind = kind
    };
}

/// Consumes inline text until a tokenizable character appears.
fn lexInlineText(self: *Lexer) []const u8 {
    const start_pos = self.pos;
    while (std.ascii.isAlphanumeric(self.char) and self.char != '\n' and !self.atEof()) {
        self.nextChar();
    }

    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn lexHeading(self: *Lexer) []const u8 {
    const start_pos = self.pos;
    var level: u32 = 0;

    while (self.char == '#' and level < 6) {
        level += 1;
        self.nextChar();
    }

    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn lexOne(self: *Lexer) []const u8 {
    const start_pos = self.pos;
    self.nextChar();
    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

/// Returns a slice of the source buffer containing repeating characters.
fn lexRepeating(self: *Lexer, repeating_char: u8) []const u8 {
    const start_pos = self.pos;

    while (self.char == repeating_char) {
        self.nextChar();
    }

    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn atEof(self: *const Lexer) bool {
    return self.char == 0;
}

/// Returns a slice of the source buffer from `start_pos` to `end_pos` (not inclusive).
fn span(self: *const Lexer, start_pos: u32, end_pos: u32) []const u8 {
    return self.buf[start_pos..end_pos];
}

/// This is the only method that should be used to set `pos` and `char`.
///
/// Using `self.buf[self.pos]` is dangerous.
fn nextChar(self: *Lexer) void {
    if (self.pos == self.buf.len - 1) {
        self.pos += 1;
        self.char = 0;
        return;
    }

    self.pos += 1;
    self.char = self.buf[self.pos];
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;

fn expectTokens(lexer: *Lexer, expected_toks: []const Token) !void {
    for (expected_toks) |tok| {
        const actual_tok = lexer.nextToken();

        expect(std.meta.eql(actual_tok, tok)) catch |e| {
            std.debug.print("Test Failed\n", .{});
            std.debug.print("  {s} == {s}\n", .{ @tagName(actual_tok.kind), @tagName(tok.kind) });
            std.debug.print("  {s} == {s}\n", .{ actual_tok.value, tok.value });
            return e;
        };
    }
}

test "init fails when given empty source" {
    const source = "";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const lexer = Lexer.init(
        allocator,
        source
    );

    try expectError(Error.EmptySourceBuf, lexer);
}

test "returns eof" {
    const source = "hello, world!";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer { _ = gpa.deinit(); }
    const allocator = gpa.allocator();

    const expected_toks = [_]Token{
        Token{
            .kind = .INLINE_TEXT,
            .value = "hello, world!"
        },
        Token.eof
    };

    const lexer = try Lexer.init(
        allocator,
        source
    );
    defer lexer.deinit(allocator);

    try expectTokens(lexer, &expected_toks);
}

test "lexes heading" {
    const source = "### Heading";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const expected_toks = [_]Token{
        Token{
            .kind = .HEADING,
            .value = "###"
        },
        Token{
            .kind = .INLINE_TEXT,
            .value = " Heading"
        },
        Token.eof
    };

    const lexer = try Lexer.init(
        allocator,
        source
    );
    defer lexer.deinit(allocator);

    for (expected_toks) |tok| {
        const actual_tok = lexer.nextToken();

        // std.debug.print("{s} == {s}\n", .{ @tagName(actual_tok.kind), @tagName(tok.kind) });
        // std.debug.print("{s} == {s}\n", .{ actual_tok.value, tok.value });

        try expect(actual_tok.kind == tok.kind);
        try expect(std.mem.eql(u8, actual_tok.value, tok.value));
    }
}
