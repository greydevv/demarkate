const std = @import("std");
const Token = @import("../Tokenizer.zig").Token;

const allocator = std.testing.allocator;

pub fn tok(tag: Token.Tag, len: usize) *Builder {
    const builder = allocator.create(Builder) catch unreachable;
    builder.* = .{
        .tokens = std.ArrayList(Token).init(allocator)
    };

    return builder.tok(tag, len);
}

pub fn free(source: []Token) void {
    allocator.free(source);
}

pub const Builder = struct {
    tokens: std.ArrayList(Token),

    pub fn deinit(self: *Builder) void {
        self.tokens.deinit();
        allocator.destroy(self);
    }

    pub fn tok(self: *Builder, tag: Token.Tag, len: usize) *Builder {
        var start_index: usize = 0;
        if (self.tokens.items.len > 0) {
            start_index = self.tokens.items[0].loc.start_index;
        }

        _ = self.tokens.append(.{
            .tag = tag,
            .loc = .{
                .start_index = start_index,
                .end_index = start_index + len,
            }
        }) catch unreachable;

        return self;
    }

    pub fn eof(self: *Builder) []Token {
        _ = self.tok(.eof, 0);
        const source = self.tokens.toOwnedSlice() catch unreachable;
        self.deinit();
        return source;
    }
};
