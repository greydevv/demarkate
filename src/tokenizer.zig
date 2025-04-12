const std = @import("std");

const Tokenizer = @This();

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Tag = enum {
        pound,
        literal_text,
        newline,
        backtick,
        asterisk,
        forward_slash,
        underscore,
        tilde,
        bang,
        semicolon,
        ampersat,
        close_angle,
        open_bracket,
        close_bracket,
        open_paren,
        close_paren,
        unknown,
        eof
    };

    pub const Loc = struct {
        start_index: usize,
        end_index: usize,
    };

    pub fn len(self: *const Token) usize {
        return self.loc.end_index - self.loc.start_index;
    }

    pub fn slice(self: *const Token, buffer: [:0]const u8) []const u8 {
        return buffer[self.loc.start_index..self.loc.end_index];
    }
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
    } else if (self.nextStructural()) |next_structural_token| {
        return next_structural_token;
    } else {
        return self.literalText();
    }
}

fn nextStructural(self: *Tokenizer) ?Token {
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
        // TODO: DELETE THIS CASE. THIS IS JUST FOR TESTING (EARLY EXIT TO PARSER).
        '&' => {
            token.tag = .eof;
            std.log.warn("Encountered early EOF character.", .{});
        },
        '#' => {
            token.tag = .pound;
            while (self.buffer[self.index] == '#') {
                self.index += 1;
            }
        },
        '*' => {
            token.tag = .asterisk;
            self.index += 1;
        },
        '/' => {
            token.tag = .forward_slash;
            self.index += 1;
        },
        '_' => {
            token.tag = .underscore;
            self.index += 1;
        },
        '~' => {
            token.tag = .tilde;
            self.index += 1;
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
        ';' => {
            token.tag = .semicolon;
            self.index += 1;
        },
        '@' => {
            token.tag = .ampersat;
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
        else => return null
    }

    token.loc.end_index = self.index;
    return token;
}

fn literalText(self: *Tokenizer) Token {
    var token = Token{
        .tag = .literal_text,
        .loc = .{
            .start_index = self.index,
            .end_index = undefined,
        }
    };

    while (true) {
        // consume until we get some other token, then cache it
        if (self.nextStructural()) |next_token| {
            token.loc.end_index = next_token.loc.start_index;
            self.cached_token = next_token;
            break;
        }

        // if escape, process next or return EOF
        if (self.buffer[self.index] == '\\') {
            if (self.buffer[self.index + 1] == 0) {
                self.index += 1;
                token.loc.end_index = self.index;
                break;
            }

            self.index += 2;
            continue;
        }

        self.index += 1;
    }

    return token;
}

test "empty" {
    const buffer: [:0]const u8 = "";

    const expected_tokens = source_builder
        .eof();
    defer source_builder.free(expected_tokens);

    try expectTokens(buffer, expected_tokens);
}

test "whitespace only" {
    const buffer: [:0]const u8 = " ";

    const expected_tokens = source_builder
        .tok(.literal_text, " ")
        .eof();
    defer source_builder.free(expected_tokens);

    try expectTokens(buffer, expected_tokens);
}


test "inline text only" {
    const buffer: [:0]const u8 = "hello, world";

    const expected_tokens = source_builder
        .tok(.literal_text, "hello, world")
        .eof();
    defer source_builder.free(expected_tokens);

    try expectTokens(buffer, expected_tokens);
}

test "escape character" {
    const buffer: [:0]const u8 = "hello\\#world";

    const expected_tokens = source_builder
        .tok(.literal_text, "hello\\#world")
        .eof();
    defer source_builder.free(expected_tokens);

    try expectTokens(buffer, expected_tokens);
}

test "escape character at eof" {
    const buffer: [:0]const u8 = "hello\\";

    const expected_tokens = source_builder
        .tok(.literal_text, "hello\\")
        .eof();
    defer source_builder.free(expected_tokens);

    try expectTokens(buffer, expected_tokens);
}

test "text between structural tokens" {
    const buffer: [:0]const u8 = "[hello, world]";
    const expected_tokens = source_builder
        .tok(.open_bracket, "[")
        .tok(.literal_text, "hello, world")
        .tok(.close_bracket, "]")
        .eof();
    defer source_builder.free(expected_tokens);

    try expectTokens(buffer, expected_tokens);
}

test "structural token between text" {
    const buffer: [:0]const u8 = "hello*world";

    const expected_tokens = source_builder
        .tok(.literal_text, "hello")
        .tok(.asterisk, "*")
        .tok(.literal_text, "world")
        .eof();
    defer source_builder.free(expected_tokens);

    try expectTokens(buffer, expected_tokens);
}

const source_builder = @import("testing/source_builder.zig");

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
