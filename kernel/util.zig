pub const RawCookie = struct {
    _dummy: u8,

    pub fn as(self: *RawCookie, comptime T: type) *T {
        return @ptrCast(*T, @alignCast(@alignOf(T), self));
    }
};

pub const Cookie = ?*RawCookie;

pub fn asCookie(a: anytype) *RawCookie {
    return @ptrCast(*RawCookie, a);
}

/// Reference counting helper
pub const RefCount = struct {
    refs: usize = 0,

    pub fn ref(self: *RefCount) void {
        self.refs += 1;
    }

    pub fn unref(self: *RefCount) void {
        if (self.refs == 0) return;
        self.refs -= 1;
    }
};

pub inline fn compAssert(comptime v: bool) void {
    comptime if (!v) @compileError("Assertion failed.");
}
