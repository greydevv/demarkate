const std = @import("std");

pub const ast = @import("ast.zig");
pub const HtmlRenderer = @import("render/html.zig").Renderer;

const Tokenizer = @import("Tokenizer.zig");
const Parser = @import("Parser.zig");
const Formatter = @import("Formatter.zig");
const pos = @import("pos.zig");

pub const Document = struct {
    allocator: std.mem.Allocator,
    elements: []ast.Element,

    pub fn deinit(self: *const Document) void {
        for (self.elements) |*el| {
            el.deinit(self.allocator);
        }

        self.allocator.free(self.elements);
    }
};

pub fn parseBytes(allocator: std.mem.Allocator, source: [:0]const u8) !Document {
    std.log.info("Parsing {} bytes", .{ source.len });

    // tokenize
    var tokenizer = Tokenizer.init(source);
    var tokens = std.ArrayList(Tokenizer.Token).empty;
    defer tokens.deinit(allocator);

    while (true) {
        const token = tokenizer.next();
        try tokens.append(allocator, token);
        if (token.tag == .eof) break;
    }

    // parse
    var parser = Parser.init(allocator, tokens.items);
    defer parser.deinit();

    parser.parse() catch |parse_err| {
        for (parser.errors.items) |e| {
            const msg = try e.allocMsg(allocator);
            std.log.debug("Error: {s}", .{ msg });
            allocator.free(msg);
        }

        return parse_err;
    };

    // format
    const formatter = Formatter.init(tokenizer.buffer);
    try formatter.format(parser.elements.items);

    // return elements;
    return Document{
        .allocator = allocator,
        .elements = try parser.elements.toOwnedSlice(allocator)
    };
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "renders" {
    const source = "hello, world!";
    const allocator = std.testing.allocator;
    const document = try parseBytes(allocator, source);
    defer document.deinit();

    var renderer = HtmlRenderer.init(allocator, source);
    defer renderer.deinit();
    try renderer.render(document.elements);
}
