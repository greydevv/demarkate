const std = @import("std");
const builtin = @import("builtin");
const impl = @import("impl.zig");

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

export fn alloc(num_bytes: u32) ?[*]const u8 {
    const allocator = std.heap.wasm_allocator;
    const slice = allocator.alloc(u8, num_bytes) catch return null;
    return slice.ptr;
}

export fn free(ptr: [*]const u8, len: usize) void {
    const allocator = std.heap.wasm_allocator;
    allocator.free(ptr[0..len]);
}

var result: impl.Result = undefined;

export fn renderHtml(source_ptr: [*]const u8, source_len: usize) *impl.Result {
    const allocator = std.heap.wasm_allocator;
    result = impl.renderHtml(allocator, source_ptr, source_len);
    return &result;
}
