const std = @import("std");
const Token = @import("../Tokenizer.zig").Token;
const Element = @import("../ast.zig").Element;

const allocator = std.testing.allocator;

pub fn tok(tag: Token.Tag, len: usize) *SourceBuilder {
    const builder = allocator.create(SourceBuilder) catch unreachable;
    builder.* = .{
        .tokens = std.ArrayList(Token).init(allocator)
    };

    return builder.tok(tag, len);
}

pub fn free(source: []Token) void {
    allocator.free(source);
}

pub const SourceBuilder = struct {
    tokens: std.ArrayList(Token),

    pub fn deinit(self: *SourceBuilder) void {
        self.tokens.deinit();
        allocator.destroy(self);
    }

    pub fn tok(self: *SourceBuilder, tag: Token.Tag, len: usize) *SourceBuilder {
        var start_index: usize = 0;
        if (self.tokens.items.len > 0) {
            start_index = self.tokens.items[0].loc.start_index;
        }

        self.tokens.append(.{
            .tag = tag,
            .loc = .{
                .start_index = start_index,
                .end_index = start_index + len,
            }
        }) catch unreachable;

        return self;
    }

    pub fn eof(self: *SourceBuilder) []Token {
        _ = self.tok(.eof, 0);
        const source = self.tokens.toOwnedSlice() catch unreachable;
        self.deinit();
        return source;
    }
};
