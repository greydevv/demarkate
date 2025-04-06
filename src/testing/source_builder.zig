const std = @import("std");
const Token = @import("../Tokenizer.zig").Token;
const Element = @import("../ast.zig").Element;

const allocator = std.testing.allocator;

pub fn tok(tag: Token.Tag, source: []const u8) *SourceBuilder {
    const builder = allocator.create(SourceBuilder) catch unreachable;
    builder.* = .{
        .tokens = std.ArrayList(Token).init(allocator)
    };

    return builder.tok(tag, source);
}

pub fn eof() []Token {
    const source = allocator.alloc(Token, 1) catch unreachable;

    source[0] = .{
        .tag = .eof,
        .loc = .{
            .start_index = 0,
            .end_index = 0,
        },
    };

    return source;
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

    pub fn tok(self: *SourceBuilder, tag: Token.Tag, source: []const u8) *SourceBuilder {
        var start_index: usize = 0;
        if (self.tokens.items.len > 0) {
            start_index = self.tokens.getLast().loc.end_index;
        }

        self.tokens.append(.{
            .tag = tag,
            .loc = .{
                .start_index = start_index,
                .end_index = start_index + source.len,
            }
        }) catch unreachable;

        return self;
    }

    pub fn eof(self: *SourceBuilder) []Token {
        _ = self.tok(.eof, "");
        const source = self.tokens.toOwnedSlice() catch unreachable;
        self.deinit();
        return source;
    }
};
