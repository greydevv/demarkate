const std = @import("std");
const builtin = @import("builtin");
const dmk = @import("demarkate");

extern fn printBytes([*]const u8, usize) void;
extern fn print(usize) void;

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = log,
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;

    if (builtin.mode == .Debug) {
        const allocator = std.heap.wasm_allocator;
        const bytes = std.fmt.allocPrint(
            allocator,
            "[WASM:" ++ level.asText() ++ "] " ++ format,
            args
        ) catch return;
        defer allocator.free(bytes);

        printBytes(bytes.ptr, bytes.len);
    }
}

const OutputSlice = packed struct(u96) {
    err_code: u32,
    ptr: u32,
    len: u32,

    fn ok(html: []const u8) OutputSlice {
        return .{
            .err_code = 0,
            .ptr = @intFromPtr(html.ptr),
            .len = html.len
        };
    }

    fn err(allocator: std.mem.Allocator, e: anyerror) OutputSlice {
        const msg = std.fmt.allocPrint(
            allocator,
            "{s}",
            .{ @errorName(e) }
        ) catch oom_err_msg;

        return .{
            .err_code = 1,
            .ptr = @intFromPtr(msg.ptr),
            .len = msg.len,
        };
    }
};

export fn alloc(num_bytes: u32) u32 {
    const allocator = std.heap.wasm_allocator;
    const slice = allocator.alloc(u8, num_bytes) catch return 0;
    return @intFromPtr(slice.ptr);
}

export fn free(ptr: [*]const u8, len: usize) void {
    const allocator = std.heap.wasm_allocator;
    allocator.free(ptr[0..len]);
}

var output: OutputSlice = undefined;
const oom_err_msg: []const u8 = @errorName(error.OutOfMemory);

export fn renderHtml(source_ptr: [*]const u8, source_len: usize) *OutputSlice {
    const allocator = std.heap.wasm_allocator;
    output = _renderHtml(allocator, source_ptr, source_len) catch |err| .err(allocator, err);

    return &output;
}

fn _renderHtml(allocator: std.mem.Allocator, source_ptr: [*]const u8, source_len: usize) !OutputSlice {
    const source_sentinel = try allocator.allocSentinel(u8, source_len, 0);
    @memcpy(source_sentinel, source_ptr);
    
    const document = try dmk.parseBytes(allocator, source_sentinel);
    defer document.deinit();

    var renderer = dmk.HtmlRenderer.init(allocator, source_sentinel);
    defer renderer.deinit();
    try renderer.render(document.elements);
    const html = try renderer.buffer.toOwnedSlice();

    return .ok(html);
}
