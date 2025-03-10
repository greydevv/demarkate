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
        unknown,
        eof
    };

    pub const Loc = struct {
        start_index: usize,
        end_index: usize,
    };
};

buffer: [:0]const u8,
index: usize,
cached_token: ?Token = null,

pub fn next(self: *Tokenizer) Token {
    if (self.cached_token) |cached_token| {
        self.cached_token = null;
        return cached_token;
    } else if (self.nextStatic()) |next_static_token| {
        return next_static_token;
    } else {
        return self.inlineText();
    }
}

fn nextStatic(self: *Tokenizer) ?Token {
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
        if (self.nextStatic()) |next_token| {
            token.loc.end_index = next_token.loc.start_index;
            self.cached_token = next_token;
            break;
        } else {
            self.index += 1;
        }
    }

    return token;
}
