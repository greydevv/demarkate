const std = @import("std");

const Tokenizer = @This();

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Tag = union(enum) {
        pound,
        literal_text,
        newline,
        backtick,
        asterisk,
        forward_slash,
        underscore,
        tilde,
        colon,
        semicolon,
        ampersat,
        open_angle,
        close_angle,
        keyword: enum {
            code,
            url,
            img
        },
        unknown,
        eof,

        pub fn equals(self: *const Tag, other: Tag) bool {
            return std.meta.eql(self.*, other);
        }
    };

    pub const Loc = struct {
        start_index: usize,
        end_index: usize,
    };

    pub fn len(self: *const Token) usize {
        return self.loc.end_index - self.loc.start_index;
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
    if (self.cached_token) |token| {
        self.cached_token = null;
        return token;
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
            self.index += 1;
        },
        ':' => {
            token.tag = .colon;
            self.index += 1;
        },
        ';' => {
            token.tag = .semicolon;
            self.index += 1;
        },
        '@' => {
            self.index += 1;
            while (std.ascii.isAlphabetic(self.buffer[self.index])) {
                self.index += 1;
            }

            const source = self.buffer[(token.loc.start_index + 1)..self.index];

            // TODO: comptime this?
            if (std.mem.eql(u8, "code", source)) {
                token.tag = .{ .keyword =  .code };
            } else if (std.mem.eql(u8, "url", source)) {
                token.tag = .{ .keyword = .url };
            } else if (std.mem.eql(u8, "img", source)) {
                token.tag = .{ .keyword = .img };
            } else {
                token.tag = .literal_text;
            }
        },
        '<' => {
            token.tag = .open_angle;
            self.index += 1;
        },
        '>' => {
            token.tag = .close_angle;
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
            // TODO: should 'escaping' EOF be an error?
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

test "tokenizes empty source" {
    const source = source_builder
        .eof();
    defer source.deinit();

    try expectTokens(source);
}

test "tokenizes text-only source" {
    const source = source_builder
        .tok(.literal_text, "hello, world")
        .eof();
    defer source.deinit();

    try expectTokens(source);
}

test "tokenizes escape character after structural token" {
    const source = source_builder
        .tok(.open_angle, "<")
        .tok(.literal_text, "\\>")
        .tok(.close_angle, ">")
        .eof();
    defer source.deinit();

    try expectTokens(source);
} 

test "tokenizes escape character in literal text" {
    const source = source_builder
        .tok(.literal_text, "hello\\#world")
        .eof();
    defer source.deinit();

    try expectTokens(source);
}

test "tokenizes escape character at eof" {
    const source = source_builder
        .tok(.literal_text, "hello\\")
        .eof();
    defer source.deinit();

    try expectTokens(source);
}

test "tokenizes literal text between structural tokens" {
    const source = source_builder
        .tok(.open_angle, "<")
        .tok(.literal_text, "hello, world")
        .tok(.close_angle, ">")
        .eof();
    defer source.deinit();

    try expectTokens(source);
}

test "tokenizes structural token between literal text" {
    const source = source_builder
        .tok(.literal_text, "hello")
        .tok(.asterisk, "*")
        .tok(.literal_text, "world")
        .eof();
    defer source.deinit();

    try expectTokens(source);
}

test "tokenizes keywords" {
    const source = source_builder
        .tok(.{ .keyword = .code }, "@code")
        .tok(.{ .keyword = .url }, "@url")
        .tok(.{ .keyword = .img }, "@img")
        .eof();
    defer source.deinit();

    try expectTokens(source);
}

const source_builder = @import("testing/source_builder.zig");

fn expectTokens(
    source: source_builder.Source,
) !void {
    const buffer = source.buffer;
    const expected_tokens = source.tokens;

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
