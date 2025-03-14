const std = @import("std");
const Token = @import("../Tokenizer.zig").Token;
const Allocator = std.mem.Allocator;

pub const SourceBuilder = struct {
    allocator: Allocator,
    tokens: std.ArrayList(Token),

    pub fn init(allocator: Allocator) !*SourceBuilder {
        const self = try allocator.create(SourceBuilder);
        self.* = .{
            .allocator = allocator,
            .tokens = std.ArrayList(Token).init(allocator)
        };

        return self;
    }

    pub fn deinit(self: *SourceBuilder) void {
        self.tokens.deinit();
        self.allocator.destroy(self);
    }

    pub fn make(self: *SourceBuilder, tag: Token.Tag, len: usize) *SourceBuilder {
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
        }) catch {
        };

        return self;
    }

    pub fn build(self: *SourceBuilder) []Token {
        return self.tokens.items;
    }
};
