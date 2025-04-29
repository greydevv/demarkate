const std = @import("std");
const Tokenizer = @import("../Tokenizer.zig");
const ast = @import("../ast.zig");

const allocator = std.testing.allocator;

pub fn tok(tag: Tokenizer.Token.Tag, source: []const u8) *SourceBuilder {
    const builder = allocator.create(SourceBuilder) catch unreachable;
    builder.* = .{
        .source = .init(allocator),
        .tokens = .init(allocator)
    };

    return builder.tok(tag, source);
}

pub fn eof() Source {
    const builder = allocator.create(SourceBuilder) catch unreachable;
    builder.* = .{
        .source = .init(allocator),
        .tokens = .init(allocator)
    };

    return builder.eof();
}

pub const Source = struct {
    buffer: [:0]const u8,
    tokens: []const Tokenizer.Token,

    pub fn deinit(self: *const Source) void {
        allocator.free(self.buffer);
        allocator.free(self.tokens);
    }
};

pub const SourceBuilder = struct {
    source: std.ArrayList(u8),
    tokens: std.ArrayList(Tokenizer.Token),

    pub fn deinit(self: *SourceBuilder) void {
        self.tokens.deinit();
        allocator.destroy(self);
    }

    pub fn tok(self: *SourceBuilder, tag: Tokenizer.Token.Tag, source: []const u8) *SourceBuilder {
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

        self.source.appendSlice(source) catch unreachable;

        return self;
    }

    pub fn eof(self: *SourceBuilder) Source {
        _ = self.tok(.eof, "");
        const tokens = self.tokens.toOwnedSlice() catch unreachable;
        const source = self.source.toOwnedSliceSentinel(0) catch unreachable;
        self.deinit();

        return .{
            .buffer = source,
            .tokens = tokens,
        };
    }
};
