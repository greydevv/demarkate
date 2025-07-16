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
                // we skipped the literal '\' when setting the span for
                // escaped_char (one token ahead here), so we need to make sure
                // this token doesn't include the '\' in its span.
                //
                // TODO: we shouldn't have to do this here.
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

test "empty" {
    const tokens = try tokenize("");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(1, tokens.len);

    const actual = tokens[0];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 0 }, actual.span);
}

test "structual" {
    const tokens = try tokenize("*");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(2, tokens.len);

    var actual = tokens[0];
    try std.testing.expectEqual(.asterisk, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 1 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 1, .end = 1 }, actual.span);
}

test "literal text" {
    const tokens = try tokenize("foo");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(2, tokens.len);

    var actual = tokens[0];
    try std.testing.expectEqual(.literal_text, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 3 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 3, .end = 3 }, actual.span);
}

test "keywords" {
    const tokens = try tokenize("@code@url@img@callout");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(5, tokens.len);

    var actual = tokens[0];
    try std.testing.expectEqual(.keyword_code, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 5 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.keyword_url, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 5, .end = 9 }, actual.span);

    actual = tokens[2];
    try std.testing.expectEqual(.keyword_img, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 9, .end = 13 }, actual.span);

    actual = tokens[3];
    try std.testing.expectEqual(.keyword_callout, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 13, .end = 21 }, actual.span);

    actual = tokens[4];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 21, .end = 21 }, actual.span);

    std.testing.expectEqual(4, Token.keywords.kvs.len) catch {
        // test needs to be updated to account for the recent changes to the
        // keywords map
        return error.TestExpectedEqual;
    };
}

test "repeated escape characters" {
    const tokens = try tokenize("\\#\\#");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(3, tokens.len);

    var actual = tokens[0];
    try std.testing.expectEqual(.escaped_char, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 1, .end = 2 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.escaped_char, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 3, .end = 4 }, actual.span);

    actual = tokens[2];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 4, .end = 4 }, actual.span);
}

test "escape character after structural token" {
    const tokens = try tokenize("*\\#");
    defer std.testing.allocator.free(tokens);

    var actual = tokens[0];
    try std.testing.expectEqual(.asterisk, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 1 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.escaped_char, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 2, .end = 3 }, actual.span);

    actual = tokens[2];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 3, .end = 3 }, actual.span);
} 

test "escape character after non-structural token" {
    const tokens = try tokenize("foo\\#");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(3, tokens.len);

    var actual = tokens[0];
    try std.testing.expectEqual(.literal_text, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 3 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.escaped_char, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 4, .end = 5 }, actual.span);

    actual = tokens[2];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 5, .end = 5 }, actual.span);
}

test "ignores escape character at eof" {
    const tokens = try tokenize("\\");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(1, tokens.len);

    const actual = tokens[0];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 0 }, actual.span);
}

test "literal text between structural tokens" {
    const tokens = try tokenize("*foo*");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(4, tokens.len);

    var actual = tokens[0];
    try std.testing.expectEqual(.asterisk, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 1 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.literal_text, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 1, .end = 4 }, actual.span);

    actual = tokens[2];
    try std.testing.expectEqual(.asterisk, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 4, .end = 5 }, actual.span);

    actual = tokens[3];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 5, .end = 5 }, actual.span);
}

test "structural token between literal text" {
    const tokens = try tokenize("foo*bar");
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(4, tokens.len);

    var actual = tokens[0];
    try std.testing.expectEqual(.literal_text, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 0, .end = 3 }, actual.span);

    actual = tokens[1];
    try std.testing.expectEqual(.asterisk, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 3, .end = 4 }, actual.span);

    actual = tokens[2];
    try std.testing.expectEqual(.literal_text, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 4, .end = 7 }, actual.span);

    actual = tokens[3];
    try std.testing.expectEqual(.eof, actual.tag);
    try std.testing.expectEqual(pos.Span{ .start = 7, .end = 7 }, actual.span);
}

const source_builder = @import("testing/source_builder.zig");

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
