const std = @import("std");
const builtin = @import("builtin");
const pos = @import("pos.zig");

pub const Token = struct {
    tag: Tag,
    span: pos.Span,

    const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "code", .keyword_code },
        .{ "url", .keyword_url },
        .{ "img", .keyword_img },
        .{ "callout", .keyword_callout },
    });

    pub const Tag = enum {
        pound,
        escaped_char,
        literal_text,
        newline,
        backtick,
        asterisk,
        forward_slash,
        underscore,
        tilde,
        colon,
        semicolon,
        open_paren,
        close_paren,
        keyword_code,
        keyword_url,
        keyword_img,
        keyword_callout,
        tab,
        unknown,
        eof,

        fn fromBytes(bytes: []const u8) ?Tag {
            return Token.keywords.get(bytes);
        } 

        pub fn equals(self: *const Tag, other: Tag) bool {
            return std.meta.eql(self.*, other);
        }
    };
};

const Tokenizer = @This();

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
        .span = .{
            .start = self.index,
            .end = undefined,
        }
    };

    switch (self.buffer[self.index]) {
        0 => {
            token.tag = .eof;
        },
        '&' => {
            if (builtin.mode != .Debug) {
                // parse as literal text in Release* modes
                return null;
            }

            token.tag = .eof;
            std.log.warn("Encountered early EOF character (debug only).", .{});
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
            self.index += 1;
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

            const source = self.buffer[(token.span.start + 1)..self.index];

            if (Token.Tag.fromBytes(source)) |keyword_tag| {
                token.tag = keyword_tag;
            } else {
                token.tag = .literal_text;
            }
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
            token.tag = .escaped_char;
            
            if (self.buffer[self.index + 1] == 0) {
                token.tag = .eof;
            } else {
                // skip escape character
                token.span.start += 1;
                self.index += 2;
            }
        },
        ' ' => {
            if (self.buffer.len - self.index > 4) {
                if (std.mem.eql(u8, self.buffer[self.index..self.index + 4], " " ** 4)) {
                    token.tag = .tab;
                    self.index += 4;
                } else {
                    return null;
                }
            } else {
                return null;
            }
        },
        else => return null
    }

    token.span.end = self.index;
    return token;
}

fn literalText(self: *Tokenizer) Token {
    var token = Token{
        .tag = .literal_text,
        .span = .{
            .start = self.index,
            .end = undefined,
        }
    };

    while (true) {
        // consume until we get some other token, then cache it
        if (self.nextStructural()) |next_token| {
            if (next_token.tag == .escaped_char) {
                // don't capture escape character
                token.span.end = next_token.span.start - 1;
            } else {
                token.span.end = next_token.span.start;
            }

            self.cached_token = next_token;
            break;
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
        .tok(.open_paren, "(")
        .tok(.literal_text, "\\>")
        .tok(.close_paren, ")")
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
        .tok(.open_paren, "(")
        .tok(.literal_text, "hello, world")
        .tok(.close_paren, ")")
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
        .tok(.keyword_code, "@code")
        .tok(.keyword_img, "@img")
        .tok(.keyword_url, "@url")
        .tok(.keyword_callout, "@callout")
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
        try std.testing.expectEqual(expected.span.start, received.span.start);
        try std.testing.expectEqual(expected.span.end, received.span.end);
    }

    const eof_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, eof_token.tag);
    try std.testing.expectEqual(buffer.len, eof_token.span.start);
    try std.testing.expectEqual(buffer.len, eof_token.span.end);

    // tokenizer should be "drained" at this point (EOF)
    try std.testing.expectEqual(buffer.len, tokenizer.index);
}
