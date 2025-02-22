const std = @import("std");
const Token = @import("Token.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;

const FileIoError = File.OpenError || File.ReadError;
const Error = Allocator.Error || FileIoError;

const Lexer = @This();

pos: u32,
file_contents: []u8,

pub fn init(allocator: Allocator, file_path: []const u8) Error!*Lexer {
    const lexer = try allocator.create(Lexer);

    lexer.* = .{
        .pos = 0,
        .file_contents = try allocator.alloc(u8, 400),
    };

    try readFile(file_path, lexer.file_contents);

    return lexer;
}

pub fn deinit(self: *Lexer, allocator: Allocator) void {
    allocator.free(self.file_contents);
    allocator.destroy(self);
}

pub fn nextToken(self: *Lexer) Token {
    const char = self.file_contents[self.pos];

    var kind: Token.Kind = undefined;
    var value: []u8 = undefined;
    kind, value = switch (char) {
        '#' =>  .{ .HEADING, self.lexHeading() },
        '*' =>  .{ .ASTERISK, self.lexRepeating('*') },
        '\n' => .{ .NEWLINE, self.lexRepeating('\n') },
        '`' =>  .{ .CODE_FENCE, self.lexRepeating('`') },
        '[', ']' =>  .{ .BRACKET_SQUARE, self.lexOne() },
        '(', ')' =>  .{ .BRACKET_PAREN, self.lexOne() },
        170 =>  .{ .EOF, "" },
        else => .{ .INLINE_TEXT, self.lexInlineText() }
    };

    const token: Token = .{
        .value = value,
        .kind = kind
    };

    Token.debugPrint(&token);

    return token;
}

fn lexInlineText(self: *Lexer) []u8 {
    const start_pos = self.pos;
    var char: ?u8 = self.file_contents[self.pos];

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

fn lexHeading(self: *Lexer) []u8 {
    const start_pos = self.pos;
    var char: ?u8 = self.file_contents[self.pos];
    var level: u32 = 0;

    while (char == '#' and level < 6) {
        level += 1;
        char = self.nextChar();
    }

    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn lexOne(self: *Lexer) []u8 {
    const start_pos = self.pos;
    _ = self.nextChar();
    const end_pos = self.pos;
    return self.span(start_pos, end_pos);
}

fn lexRepeating(self: *Lexer, repeating_char: u8) []u8 {
    var char: ?u8 = self.file_contents[self.pos];
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

fn span(self: *Lexer, start_pos: u32, end_pos: u32) []u8 {
    return self.file_contents[start_pos..end_pos];
}

fn nextChar(self: *Lexer) ?u8 {
    if (self.pos > self.file_contents.len - 1) {
        return null;
    }

    self.pos += 1;
    return self.file_contents[self.pos];
}

fn readFile(file_path: []const u8, buffer: []u8) FileIoError!void {
    const open_flags = File.OpenFlags { .mode = .read_only };

    const file = try std.fs.openFileAbsolute(file_path, open_flags);
    defer file.close();

    _ = try file.readAll(buffer);
}
