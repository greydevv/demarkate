pub const Span = struct {
    start: usize,
    end: usize,

    pub fn slice(self: *const Span, buffer: [:0]const u8) []const u8 {
        return buffer[self.start..self.end];
    }

    pub fn len(self: *const Span) usize {
        return self.end - self.start;
    }
};

