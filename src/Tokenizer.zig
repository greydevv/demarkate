const std = @import("std");
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
        inline_code,
        empty_inline_code,
        unterminated_inline_code,
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

        fn keyword(bytes: []const u8) ?Tag {
            return Token.keywords.get(bytes);
        } 

        pub fn equals(self: *const Tag, other: Tag) bool {
            return std.meta.eql(self.*, other);
        }
    };
};

const State = enum {
    start,
    whitespace,
    keyword,
    open_inline_code,
    inline_code,
    inline_code_backslash,
    heading,
    newline,
    unknown,
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
    }

    return self._next();
}

fn _next(self: *Tokenizer) Token {
    var token = Token{
        .tag = .literal_text,
        .span = .{
            .start = self.index,
            .end = undefined,
        }
    };

    while (true) {
        const next_token = self.nextStructural();

        if (next_token.tag == .literal_text) {
            token.span.end = next_token.span.end;
            continue;
        }

        token.span.end = next_token.span.start;
        if (token.span.len() == 0) {
            return next_token;
        } else {
            std.debug.assert(self.cached_token == null);
            self.cached_token = next_token;
            return token;
        }
    }
}

fn nextStructural(self: *Tokenizer) Token {
    var token = Token{
        .tag = undefined,
        .span = .{
            .start = self.index,
            .end = undefined,
        }
    };

    state: switch (State.start) {
        .start => {
            switch (self.buffer[self.index]) {
                0 => {
                    token.tag = .eof;
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
                ':' => {
                    token.tag = .colon;
                    self.index += 1;
                },
                ';' => {
                    token.tag = .semicolon;
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
                    switch (self.buffer[self.index + 1]) {
                        0, ' ', '\t'...'\r' => {
                            self.index += 1;
                            continue :state .unknown;
                        },
                        else => {
                            token.tag = .escaped_char;
                            self.index += 2;
                        }
                    }
                }, 
                '@' => {
                    self.index += 1;
                    continue :state .keyword;
                },
                ' ' => continue :state .whitespace,
                '`' => {
                    token.tag = .inline_code;
                    self.index += 1;
                    continue :state .open_inline_code;
                },
                '#' => {
                    token.tag = .pound;
                    self.index += 1;
                    continue :state .heading;
                },
                '\n' => {
                    token.tag = .newline;
                    self.index += 1;
                    continue :state .newline;
                },
                else => {
                    self.index += 1;
                    continue :state .unknown;
                }
            }
        },
        .keyword => {
            switch (self.buffer[self.index]) {
                'a'...'z' => {
                    self.index += 1;
                    continue :state .keyword;
                },
                else => {
                    const source = self.buffer[token.span.start + 1..self.index];
                    if (Token.Tag.keyword(source)) |tag| {
                        token.tag = tag;
                    } else {
                        continue :state .unknown;
                    }
                }
            }
        },
        .whitespace => {
            switch (self.buffer[self.index]) {
                ' ' => {
                    self.index += 1;
                    if (self.index - token.span.start == 4) {
                        token.tag = .tab;
                    } else {
                        continue :state .whitespace;
                    }
                },
                else => token.tag = .literal_text,
            }
        },
        .open_inline_code => {
            switch (self.buffer[self.index]) {
                '`' => token.tag = .empty_inline_code,
                else => continue :state .inline_code,
            }
        },
        .inline_code => {
            switch (self.buffer[self.index]) {
                0, '\n' => token.tag = .unterminated_inline_code,
                '\\' => {
                    self.index += 1;
                    continue :state .inline_code_backslash; 
                },
                '`' => self.index += 1,
                else => {
                    self.index += 1;
                    continue :state .inline_code;
                }
            }
        },
        .inline_code_backslash => {
            switch (self.buffer[self.index]) {
                0, '\n' => token.tag = .unterminated_inline_code,
                else => {
                    self.index += 1;
                    continue :state .inline_code;
                }
            }
        },
        .heading => {
            switch (self.buffer[self.index]) {
                '#' => {
                    self.index += 1;
                    continue :state .heading;
                },
                else => {}
            }
        },
        .newline => {
            switch (self.buffer[self.index]) {
                '\n' => {
                    self.index += 1;
                    continue :state .newline;
                },
                else => {}
            }
        },
        .unknown => {
            token.tag = .literal_text;
        }
    }

    token.span.end = self.index;
    return token;
}

test "empty" {
    try testTokenize("", &.{
        .eof
    });
}

test "structural" {
    try testTokenize("*", &.{
        .asterisk,
        .eof
    });
}

test "literal text" {
    try testTokenize("foo", &.{
        .literal_text,
        .eof
    });
}

test "keywords" {
    try testTokenize("@code@url@img@callout", &.{
        .keyword_code,
        .keyword_url,
        .keyword_img,
        .keyword_callout,
        .eof
    });


    // the keywords map was updated and this failure signals to update the test
    // to reflect those changes
    try std.testing.expectEqual(4, Token.keywords.kvs.len);
}

test "no matching keyword" {
    try testTokenize("@unsupported", &.{
        .literal_text,
        .eof
    });
}

test "repeated escape characters" {
    try testTokenize("\\#\\#", &.{
        .escaped_char,
        .escaped_char,
        .eof
    });
}

test "repeated newlines" {
    try testTokenize("\n\n\n", &.{
        .newline,
        .eof
    });
}

test "escape character after structural token" {
    try testTokenize("*\\#", &.{
        .asterisk,
        .escaped_char,
        .eof
    });
} 

test "escape character after non-structural token" {
    try testTokenize("foo\\#", &.{
        .literal_text,
        .escaped_char,
        .eof
    });
}

test "escape character at eof" {
    try testTokenize("\\", &.{
        .literal_text,
        .eof
    });
}

test "literal text between structural tokens" {
    try testTokenize("*foo*", &.{
        .asterisk,
        .literal_text,
        .asterisk,
        .eof
    });
}

test "structural token between literal text" {
    try testTokenize("foo*bar", &.{
        .literal_text,
        .asterisk,
        .literal_text,
        .eof
    });
}

test "inline code escape sequence" {
    try testTokenize("`\\``", &.{
        .inline_code,
        .eof
    });
}

const source_builder = @import("testing/source_builder.zig");

fn testTokenize(source: [:0]const u8, expected_tags: []const Token.Tag) !void {
    const tokens = try tokenize(source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(expected_tags.len, tokens.len);
    for (tokens, 0..) |token, i| {
        try std.testing.expectEqual(expected_tags[i], token.tag);
    }

    const last = tokens[tokens.len - 1];
    try std.testing.expectEqual(source.len, last.span.start);
    try std.testing.expectEqual(source.len, last.span.end);
}

fn tokenize(source: [:0]const u8) ![]const Token {
    var tokens = std.ArrayList(Token).init(std.testing.allocator);
    var tokenizer = Tokenizer.init(source);
    while(true) {
        const token = tokenizer.next();
        try tokens.append(token);
        if (token.tag == .eof) {
            break;
        }
    }

    return tokens.toOwnedSlice();
}
