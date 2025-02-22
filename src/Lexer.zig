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
        170 => .{ .EOF, "" },
        else => .{ .INLINE_TEXT, self.lexInlineText() }
    };

    const token: Token = .{
        .value = value,
        .kind = kind
    };

    Token.debugPrint(&token);

    return token;
}

fn lexInlineText(self: *Lexer) []const u8 {
    const start_pos = self.pos;
    var char: ?u8 = self.buf[self.pos];

    while (char != '\n') {
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

fn span(self: *Lexer, start_pos: u32, end_pos: u32) []const u8 {
    return self.buf[start_pos..end_pos];
}

fn nextChar(self: *Lexer) ?u8 {
    if (self.pos > self.buf.len - 1) {
        return null;
    }

    self.pos += 1;
    return self.buf[self.pos];
}
