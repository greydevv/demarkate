const std = @import("std");

const Tokenizer = @This();

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Tag = enum {
        heading,
        inline_text,
        newline,
        backtick,
        asterisk,
        bang,
        close_angle,
        open_bracket,
        close_bracket,
        open_paren,
        close_paren,
        escape,
        unknown,
        eof
    };

    pub const Loc = struct {
        start_index: usize,
        end_index: usize,
    };
};

buffer: [:0]const u8,
index: usize = 0,
cached_token: ?Token = null,

pub fn init(buffer: [:0]const u8) Tokenizer {
    return .{
        .buffer = buffer,
        .index = 0,
        .cached_token = null,
    };
}

pub fn next(self: *Tokenizer) Token {
    if (self.cached_token) |cached_token| {
        self.cached_token = null;
        return cached_token;
    } else if (self.nextLiteral()) |next_literal_token| {
        return next_literal_token;
    } else {
        return self.inlineText();
    }
}

fn nextLiteral(self: *Tokenizer) ?Token {
    var token = Token{
        .tag = undefined,
        .loc = .{
            .start_index = self.index,
            .end_index = undefined,
        }
    };

    switch (self.buffer[self.index]) {
        0 => {
            token.tag = .eof;
        },
        '#' => {
            token.tag = .heading;
            while (self.buffer[self.index] == '#') {
                self.index += 1;
            }
        },
        '*' => {
            token.tag = .asterisk;
            while (self.buffer[self.index] == '*') {
                self.index += 1;
            }
        },
        '`' => {
            token.tag = .backtick;
            while (self.buffer[self.index] == '`') {
                self.index += 1;
            }
        },
        '\n' => {
            token.tag = .newline;
            while (self.buffer[self.index] == '\n') {
                self.index += 1;
            }
        },
        '!' => {
            token.tag = .bang;
            self.index += 1;
        },
        '>' => {
            token.tag = .close_angle;
            self.index += 1;
        },
        '[' => {
            token.tag = .open_bracket;
            self.index += 1;
        },
        ']' => {
            token.tag = .close_bracket;
            self.index += 1;
        },
        '(' => {
            token.tag = .open_paren;
            self.index += 1;
        },
        ')' => {
            token.tag = .close_paren;
            self.index += 1;
        },
        '\\' => {
            token.tag = .escape;
            self.index += 1;
        },
        else => return null
    }

    token.loc.end_index = self.index;
    return token;
}

fn inlineText(self: *Tokenizer) Token {
    var token = Token{
        .tag = .inline_text,
        .loc = .{
            .start_index = self.index,
            .end_index = undefined,
        }
    };

    while (true) {
        // consume until we get some other token, then cache it
        if (self.nextLiteral()) |next_token| {
            token.loc.end_index = next_token.loc.start_index;
            self.cached_token = next_token;
            break;
        } else {
            self.index += 1;
        }
    }

    return token;
}

test "inline text only" {
    const buffer: [:0]const u8 = "hello, world";
    const expected_tokens = [_]Token{
        .{
            .tag = .inline_text,
            .loc = .{ .start_index = 0, .end_index = 12 },
        },
        .{
            .tag = .eof,
            .loc = .{ .start_index = 12, .end_index = 12 }
        }
    };

    try expectTokens(buffer, &expected_tokens);
}

test "inline text between literals" {
    const buffer: [:0]const u8 = "[hello, world]";
    const expected_tokens = [_]Token{
        .{
            .tag = .open_bracket,
            .loc = .{ .start_index = 0, .end_index = 1 },
        },
        .{
            .tag = .inline_text,
            .loc = .{ .start_index = 1, .end_index = 13 }
        },
        .{
            .tag = .close_bracket,
            .loc = .{ .start_index = 13, .end_index = 14 }
        },
        .{
            .tag = .eof,
            .loc = .{ .start_index = 14, .end_index = 14 }
        }
    };

    try expectTokens(buffer, &expected_tokens);
}

test "empty buffer" {
    const buffer: [:0]const u8 = "";
    const expected_tokens = [_]Token{
        .{
            .tag = .eof,
            .loc = .{ .start_index = 0, .end_index = 0 },
        }
    };

    try expectTokens(buffer, &expected_tokens);
}

test "whitespace buffer" {
    const buffer: [:0]const u8 = " ";
    const expected_tokens = [_]Token{
        .{
            .tag = .inline_text,
            .loc = .{ .start_index = 0, .end_index = 1 },
        },
        .{
            .tag = .eof,
            .loc = .{ .start_index = 1, .end_index = 1},
        }
    };

    try expectTokens(buffer, &expected_tokens);
}

fn expectTokens(
    buffer: [:0]const u8,
    expected_tokens: []const Token
) !void {
    var tokenizer = Tokenizer.init(buffer);
    for (expected_tokens) |expected| {
        const received = tokenizer.next();
        try std.testing.expectEqual(expected.tag, received.tag);
        try std.testing.expectEqual(expected.loc.start_index, received.loc.start_index);
        try std.testing.expectEqual(expected.loc.end_index, received.loc.end_index);
    }

    const eof_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, eof_token.tag);
    try std.testing.expectEqual(buffer.len, eof_token.loc.start_index);
    try std.testing.expectEqual(buffer.len, eof_token.loc.end_index);

    // tokenizer should be "drained" at this point (EOF)
    try std.testing.expectEqual(buffer.len, tokenizer.index);
}

// std.testing.expect(std.meta.eql(expected, received)) catch |err| {
//     std.debug.print("Test failed: ", .{});
//     if (expected.tag != received.tag) {
//         std.debug.print(
//             "unequal tags\n\t{s} != {s}\n",
//             .{ @tagName(expected.tag), @tagName(received.tag) }
//         );
//     } else if (expected.loc.start_index != received.loc.start_index) {
//         std.debug.print(
//             "unequal start index\n\t{} != {}\n",
//             .{ expected.loc.start_index, received.loc.start_index }
//         );
//     } else if (expected.loc.end_index != received.loc.end_index) {
//         std.debug.print(
//             "unequal start index\n\t{} != {}\n",
//             .{ expected.loc.end_index, received.loc.end_index })
//         ;
//     } else {
//         std.debug.print("unknown inequality\n", .{});
//     }
//     return err;
// };
