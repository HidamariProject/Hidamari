const std = @import("std");
const builtin = @import("builtin");

pub const Error = error{Unknown};

pub const impl = switch (builtin.os.tag) {
    .uefi => @import("platform/uefi.zig"),
    else => @compileError("Unsupported platform"),
};

pub const init = impl.init;
pub const earlyprintk = impl.earlyprintk;
pub const getTimeNano = impl.getTimeNano;
pub const getTime = impl.getTime;
pub const halt = impl.halt;
pub const setTimer = impl.setTimer;
pub const openConsole = impl.openConsole;
const late = impl.late;

pub var internal_malloc = impl.malloc;
pub var internal_realloc = impl.realloc;
pub var internal_free = impl.free;

var earlyInit = true;

// Should probably be in klibc

export fn malloc(size: usize) callconv(.C) ?[*]u8 {
    return internal_malloc(size);
}
export fn realloc(ptr: ?[*]align(8) u8, size: usize) callconv(.C) ?[*]u8 {
    return internal_realloc(ptr, size);
}
export fn free(ptr: ?[*]align(8) u8) callconv(.C) void {
    return internal_free(ptr);
}

// Useful utilities

pub fn earlyprintf(comptime format: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    earlyprintk(std.fmt.bufPrint(buf[0..buf.len], format, args) catch unreachable);
}

pub fn setEarly(val: bool) void {
    if (!earlyInit and val) @panic("Trying to re-enter early initialization.");
    late();
    earlyInit = false;
}

pub fn early() bool {
    return earlyInit;
}

pub fn halt_void() void {
    while (true) {}
}

const PlatformWriter = io.Writer(void, Error, platformWriterWrite);

fn platformWriterWrite(unused: void, bytes: []const u8) Error!usize {
    earlyprintk(bytes);
    return bytes.len;
}

const stderr_writer = PlatformWriter{ .context = {} };
