const std = @import("std");
const dmk = @import("demarkate");

extern fn printBytes([*]const u8, usize) void;
extern fn print(usize) void;

pub const std_options = std.Options{
    // Set the log level to info
    .log_level = .info,

    // Define logFn to override the std implementation
    .logFn = log,
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;

    const allocator = std.heap.wasm_allocator;
    const bytes = std.fmt.allocPrint(allocator, level.asText() ++ ": " ++ format, args) catch return;
    printBytes(bytes.ptr, bytes.len);
}

const OutputSlice = packed struct (u64) {
    ptr: u32,
    len: u32,

    fn empty() OutputSlice {
        return .{ .ptr = 0, .len = 0 };
    }
};

var output: OutputSlice = undefined;

export fn renderHtml(source_ptr: [*]const u8, source_len: usize) OutputSlice {
    const allocator = std.heap.wasm_allocator;
    const source_sentinel = allocator.allocSentinel(u8, source_len, 0) catch return .empty();
    @memcpy(source_sentinel, source_ptr);
    
    const document = dmk.parseBytes(allocator, source_sentinel) catch return .empty();
    defer document.deinit();

    var renderer = dmk.HtmlRenderer.init(allocator, source_sentinel);
    defer renderer.deinit();
    renderer.render(document.elements) catch return .empty();

    const out = renderer.buffer.toOwnedSlice() catch return .empty();

    return .{
        .ptr = @intFromPtr(out.ptr),
        .len = out.len
    };
}
