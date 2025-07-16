const std = @import("std");
const dmk = @import("demarkate");

const oom_err_msg = @errorName(error.OutOfMemory);

pub const Result = packed struct {
    err_code: u32,
    ptr: [*]const u8,
    len: usize,

    fn ok(html: []const u8) Result {
        return .{
            .err_code = 0,
            .ptr = html.ptr,
            .len = html.len
        };
    }

    fn err(allocator: std.mem.Allocator, e: anyerror) Result {
        const msg = std.fmt.allocPrint(
            allocator,
            "{s}",
            .{ @errorName(e) }
        ) catch oom_err_msg;

        return .{
            .err_code = 1,
            .ptr = msg.ptr,
            .len = msg.len,
        };
    }
};

pub fn renderHtml(allocator: std.mem.Allocator, source_ptr: [*]const u8, source_len: usize) Result {
    const html = _renderHtml(allocator, source_ptr[0..source_len]) catch |e| {
        return .err(allocator, e);
    };

    return .ok(html);
}

fn _renderHtml(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const source_sentinel = try allocator.dupeZ(u8, source);
    defer allocator.free(source_sentinel);

    const document = try dmk.parseBytes(allocator, source_sentinel);
    defer document.deinit();

    var renderer = dmk.HtmlRenderer.init(allocator, source_sentinel);
    defer renderer.deinit();

    try renderer.render(document.elements);
    const html = try renderer.buffer.toOwnedSlice();

    return html;
}

test "success" {
    const allocator = std.testing.allocator;
    const source = try allocator.dupe(u8, "hello, world!");
    defer allocator.free(source);

    const result = renderHtml(allocator, source.ptr, source.len);
    const html = result.ptr[0..result.len];
    defer allocator.free(html);

    try std.testing.expectEqual(0, result.err_code);
    try std.testing.expectEqualDeep(html, "<div class=\"dmk_document\">hello, world!</div>");
}

test "error" {
    const allocator = std.testing.allocator;
    const source = try allocator.dupe(u8, "*");
    defer allocator.free(source);

    const result = renderHtml(allocator, source.ptr, source.len);
    const err_msg = result.ptr[0..result.len];
    defer allocator.free(err_msg);

    try std.testing.expectEqual(1, result.err_code);
    try std.testing.expect(err_msg.len > 0);
}

fn _oom_alloc(
    ctx: *anyopaque,
    len: usize,
    alignment: std.mem.Alignment,
    return_address: usize
) ?[*]u8 {
    _ = ctx;
    _ = len;
    _ = alignment;
    _ = return_address;
    return null;
}

test "oom" {
    var vtable = std.mem.Allocator.VTable{
        .alloc = std.testing.allocator.vtable.alloc,
        .resize = std.testing.allocator.vtable.resize,
        .remap = std.testing.allocator.vtable.remap,
        .free = std.testing.allocator.vtable.free,
    };

    const oom_allocator = std.mem.Allocator{
        .ptr = std.testing.allocator.ptr,
        .vtable = &vtable
    };

    const source = oom_allocator.dupe(u8, "hello, world!") catch |e| {
        std.debug.print("Error: {s}\n", .{ @errorName(e) });
        return;
    };
    defer oom_allocator.free(source);

    vtable.alloc = _oom_alloc;

    // no need to free result.ptr[0..result.len] because result.ptr is a
    // pointer to the stack-allocated oom_err_msg
    const result = renderHtml(oom_allocator, source.ptr, source.len);
    
    try std.testing.expectEqual(1, result.err_code);
    try std.testing.expectEqual(@errorName(error.OutOfMemory), result.ptr[0..result.len]);
}
