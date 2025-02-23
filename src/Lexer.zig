const std = @import("std");
const Token = @import("Token.zig");

const Allocator = std.mem.Allocator;
const Lexer = @This();

pos: u32,
buf: []const u8,

pub fn init(allocator: Allocator, source_buf: []const u8) Allocator.Error!*Lexer {
    const lexer = try allocator.create(Lexer);

    lexer.* = .{
        .pos = 0,
        .buf = source_buf,
    };

    return lexer;
}

pub fn deinit(self: *Lexer, allocator: Allocator) void {
    allocator.destroy(self);
}

pub fn nextToken(self: *Lexer) Token {
    if (self.atEof()) {
        std.debug.print("returning eof\n", .{});
        return Token.eof;
    }

    const char = self.buf[self.pos];

    var kind: Token.Kind = undefined;
    var value: []const u8 = undefined;
    kind, value = switch (char) {
        '#' => .{ .HEADING, self.lexHeading() },
        '*' => .{ .ASTERISK, self.lexRepeating('*') },
        '\n' => .{ .NEWLINE, self.lexRepeating('\n') },
        '`' => .{ .CODE_FENCE, self.lexRepeating('`') },
        '[', ']' => .{ .BRACKET_SQUARE, self.lexOne() },
        '(', ')' => .{ .BRACKET_PAREN, self.lexOne() },
        170 => return Token.eof,
        else => .{ .INLINE_TEXT, self.lexInlineText() }
    };

    const token: Token = .{
        .value = value,
        .kind = kind
    };

    return token;
}

fn lexInlineText(self: *Lexer) []const u8 {
    const start_pos = self.pos;
    var char: ?u8 = self.buf[self.pos];

    while (char != '\n' and !self.atEof()) {
        if (char) |cur_char| {
            if (isTokenizableChar(cur_char)) {
                break;
            }
        }

        char = self.nextChar();
    }

    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn lexHeading(self: *Lexer) []const u8 {
    const start_pos = self.pos;
    var char: ?u8 = self.buf[self.pos];
    var level: u32 = 0;

    while (char == '#' and level < 6) {
        level += 1;
        char = self.nextChar();
    }

    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn lexOne(self: *Lexer) []const u8 {
    const start_pos = self.pos;
    _ = self.nextChar();
    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn lexRepeating(self: *Lexer, repeating_char: u8) []const u8 {
    var char: ?u8 = self.buf[self.pos];
    const start_pos = self.pos;

    while (char == repeating_char) {
        char = self.nextChar();
    }

    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn isTokenizableChar(char: u8) bool {
    return switch (char) {
        '*', '[', ']', '(', ')' => true,
        else => false
    };
}

fn atEof(self: *Lexer) bool {
    return self.pos == self.buf.len - 1;
}

fn span(self: *Lexer, start_pos: u32, end_pos: u32) []const u8 {
    if (self.atEof()) {
        return self.buf[start_pos..end_pos + 1];
    }
    return self.buf[start_pos..end_pos];
}

fn nextChar(self: *Lexer) ?u8 {
    if (self.pos == self.buf.len - 1) {
        return null;
    }

    self.pos += 1;
    return self.buf[self.pos];
}

const expect = std.testing.expect;

test "lexes heading" {
    const source = "### Heading";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const expected_toks: [3]Token = .{
        Token{
            .kind = .HEADING,
            .value = "###"
        },
        Token{
            .kind = .INLINE_TEXT,
            .value = " Heading"
        },
        Token{
            .kind = .EOF,
            .value = ""
        }
    };

    const lexer = try Lexer.init(
        allocator,
        source
    );

    for (expected_toks) |tok| {
        const actual_tok = lexer.nextToken();

        std.debug.print("{s} == {s}\n", .{ @tagName(actual_tok.kind), @tagName(tok.kind) });
        std.debug.print("{s} == {s}\n", .{ actual_tok.value, tok.value });

        try expect(actual_tok.kind == tok.kind);
        try expect(std.mem.eql(u8, actual_tok.value, tok.value));
    }
}




