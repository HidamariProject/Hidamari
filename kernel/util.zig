pub const RawCookie = struct {
    _dummy: u8,

    pub fn as(self: *RawCookie, comptime T: type) *T {
        return @ptrCast(*T, @alignCast(@alignOf(*T), self));
    }
};

pub const Cookie = ?*RawCookie;

pub fn asCookie(a: anytype) *RawCookie {
    return @ptrCast(*RawCookie, a);
}
