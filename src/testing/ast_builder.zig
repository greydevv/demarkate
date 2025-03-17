const std = @import("std");
const Element = @import("../ast.zig").Element;

const allocator = std.testing.allocator;

pub fn node(tag: Element.Node.Tag) *AstBuilder {
    const builder = allocator.create(AstBuilder) catch unreachable;
    builder.* = .{
        .elements = std.ArrayList(Element).init(allocator),
        .last_el = undefined,
    };

    builder.elements.append(
        Element.initNode(allocator, tag)
    ) catch unreachable;

    builder.last_el = &builder.elements.items[0];

    return builder.node(tag);
}

pub fn free(elements: []Element) void {
    allocator.free(elements);
}

pub const AstBuilder = struct {
    elements: std.ArrayList(Element),
    last_el: *Element,

    pub fn deinit(self: *AstBuilder) void {
        self.elements.deinit();
        allocator.destroy(self);
    }

    pub fn node(self: *AstBuilder, e: Element) *AstBuilder {
        self.element(e);

        return self;
    }

    pub fn leaf(self: *AstBuilder, tag: Element.Leaf.Tag) *AstBuilder {
        const child = Element.initLeaf(tag);
        self.element(child);

        return self;
    }

    pub fn childNode(self: *AstBuilder, tag: Element.Node.Tag) *AstBuilder {
        const child = Element.initNode(tag);
        _ = self.last_el.addChild(child) catch unreachable;

        return self;
    }
    
    pub fn childLeaf(self: *AstBuilder, tag: Element.Leaf.Tag) *AstBuilder {
        const child = Element.initLeaf(tag);
        _ = self.last_el.addChild(child) catch unreachable;

        return self;
    }

    pub fn build(self: *AstBuilder) []Element {
        const elements = self.elements.toOwnedSlice() catch unreachable;
        self.deinit();
        return elements;
    }

    fn element(self: *AstBuilder, e: Element) void {
        self.elements.append(e) catch unreachable;
        self.last_el = &self.elements.items[self.elements.items.len - 1];
    }
};


