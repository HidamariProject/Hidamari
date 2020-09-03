const std = @import("std");
const platform = @import("platform.zig");

// Pointless crap

pub fn notifyInitialization() void {
    // NOP
}

export fn __chkstk() callconv(.C) void {}

// Actually useful stuff: stdlib

export fn exit(code: c_int) callconv(.C) void {
    platform.earlyprintf("C: exit({})!\n", .{code});
    @panic("exit() function called from C code");
}

export fn abort() callconv(.C) void {
    @panic("abort() function called from C code");
}

export fn strtoul(num: [*c]const u8, ignored: *[*c]u8, base: c_int) callconv(.C) c_ulong {
    return std.fmt.parseInt(c_ulong, std.mem.spanZ(num), @intCast(u8, base)) catch 0;
}

export fn strtoull(num: [*c]const u8, ignored: *[*c]u8, base: c_int) callconv(.C) c_ulonglong {
    return std.fmt.parseInt(c_ulonglong, std.mem.spanZ(num), @intCast(u8, base)) catch 0;
}

// Stdio

export fn __earlyprintk(text: [*c]const u8) callconv(.C) void {
    platform.earlyprintk(std.mem.spanZ(text));
}

export fn __earlyprintk_num(num: i64) callconv(.C) void {
    platform.earlyprintf("(i64)({})", .{num});
}

export fn __earlyprintk_ptr(ptr: [*]u8) callconv(.C) void {
    platform.earlyprintf("(*)({})", .{ptr});
}

// String

export fn _klibc_memset(dest: [*]u8, c: u8, count: usize) [*]u8 {
    @memset(dest, c, count);
    return dest;
}

export fn _klibc_memcpy(dest: [*]u8, source: [*]const u8, amount: usize) callconv(.C) [*]u8 {
    @memcpy(dest, source, amount);
    return dest;
}

export fn strcmp(a: [*c]const u8, b: [*c]const u8) callconv(.C) c_int {
    return std.cstr.cmp(a, b);
}

export fn strlen(str: [*c]const u8) callconv(.C) c_int {
    return @intCast(c_int, std.mem.spanZ(str).len);
}

export fn strcat(dst: [*c]u8, src: [*c]const u8) callconv(.C) c_int {
    return 0;
}

// Math

export fn rint(f: f64) callconv(.C) f64 {
    return @round(f);
}

export fn rintf(f: f32) callconv(.C) f32 {
    return @round(f);
}
