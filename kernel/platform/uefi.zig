const std = @import("std");
const builtin = @import("builtin");
const vfs = @import("../vfs.zig");
const uefi = std.os.uefi;
const time = std.time;

const earlyprintf = @import("../platform.zig").earlyprintf;

pub const klibc = @import("../klibc.zig");
pub const debugMalloc = false;

const console = @import("uefi/console.zig");

var exitedBootServices = false;

const Error = error{UefiError};

var timer_event: uefi.Event = undefined;
var timer_call: ?fn () void = null;

pub fn timerCallThunk(event: uefi.Event, context: ?*const c_void) callconv(.C) void {
    console.keyboardHandler();
    if (timer_call) |func| {
        func();
    }
}

pub fn init() void {
    klibc.notifyInitialization();
    const con_out = uefi.system_table.con_out.?;
    const con_in = uefi.system_table.con_in.?;
    _ = uefi.system_table.boot_services.?.setWatchdogTimer(0, 0, 0, null);
    _ = con_out.reset(false);
    _ = con_in._reset(con_in, false);
    _ = uefi.system_table.boot_services.?.createEvent(uefi.tables.BootServices.event_timer | uefi.tables.BootServices.event_notify_signal, uefi.tables.BootServices.tpl_notify, timerCallThunk, null, &timer_event);
    _ = uefi.system_table.boot_services.?.setTimer(timer_event, uefi.tables.TimerDelay.TimerPeriodic, 1000);
}

pub fn malloc(size: usize) ?[*]u8 {
    if (debugMalloc) earlyprintf("Allocating {} bytes\r\n", .{size});
    var buf: [*]align(8) u8 = undefined;
    var status = uefi.system_table.boot_services.?.allocatePool(uefi.tables.MemoryType.BootServicesData, size + 8, &buf);
    if (status != .Success) return null;
    var origSizePtr = @ptrCast([*]align(8) u64, buf);
    origSizePtr[0] = @intCast(u64, size);
    return @intToPtr([*]u8, @ptrToInt(buf) + 8);
}

pub fn realloc(ptr: ?[*]align(8) u8, newsize: usize) ?[*]u8 {
    if (ptr == null) return malloc(newsize);
    if (debugMalloc) earlyprintf("Reallocating {} bytes\r\n", .{newsize});
    var truePtr = @intToPtr([*]align(8) u8, @ptrToInt(ptr.?) - 8);
    var origSizePtr = @ptrCast([*]align(8) u64, truePtr);
    if (origSizePtr[0] == @intCast(u64, newsize + 8)) return ptr;
    defer free(ptr);
    var newPtr = malloc(newsize);
    if (newPtr == null) return null;
    if (debugMalloc) earlyprintf("Original size: {}\r\n", .{origSizePtr[0]});
    @memcpy(newPtr.?, ptr.?, @intCast(usize, origSizePtr[0]));
    return newPtr;
}

pub fn free(ptr: ?[*]align(8) u8) void {
    if (ptr == null) return;
    if (debugMalloc) earlyprintf("Freeing {} ptr\r\n", .{ptr});
    var status = uefi.system_table.boot_services.?.freePool(@intToPtr([*]align(8) u8, @ptrToInt(ptr.?) - 8));
    if (status != .Success) @panic("free() failed (this shouldn't be possible)");
}

pub fn earlyprintk(str: []const u8) void {
    const con_out = uefi.system_table.con_out.?;
    for (str) |c| {
        if (c == '\n') _ = con_out.outputString(&[_:0]u16{ '\r', 0 });
        _ = con_out.outputString(&[_:0]u16{ c, 0 });
    }
}

pub fn openConsole() vfs.Node {
    return console.ConsoleNode.init();
}

pub fn setTimer(cb: @TypeOf(timer_call)) void {
    timer_call = cb;
}

pub fn getTimeNano() i64 {
    var raw = getTimeNative() catch unreachable;
    return uefiToUnixTimeNano(raw);
}

pub fn getTime() i64 {
    return @divFloor(getTimeNano(), time.ns_per_s);
}

pub fn getTimeNative() !uefi.Time {
    var ret: uefi.Time = undefined;
    var status = uefi.system_table.runtime_services.getTime(&ret, null);
    if (status != .Success) return Error.UefiError;
    return ret;
}

pub fn uefiToUnixTimeNano(raw: uefi.Time) i64 {
    const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var tzOffset = if (raw.timezone != uefi.Time.unspecified_timezone) raw.timezone else 0;
    var isLeapYear = false;
    if (raw.year % 4 == 0 and (raw.year % 100 != 0 or raw.year % 400 == 0))
        isLeapYear = true;
    var year = raw.year - 1900;
    var yday = raw.day - 1;
    for (days_in_month[0..(raw.month - 1)]) |v, i| {
        if (i == 1 and isLeapYear) {
            yday += 29;
        } else {
            yday += v;
        }
    }

    var ret: i64 = time.epoch.unix * time.ns_per_s;

    ret += @as(i64, raw.nanosecond);
    ret += @as(i64, raw.second) * time.ns_per_s;
    ret += (@as(i64, raw.minute) - @as(i64, tzOffset)) * time.ns_per_min;
    ret += @as(i64, raw.hour) * time.ns_per_hour;
    ret += @as(i64, yday) * time.ns_per_day;
    ret += @as(i64, year - 70) * 365 * time.ns_per_day;

    // Weird stuff. Leap years were a bad idea.
    ret += @as(i64, @divFloor(year - 69, 4)) * time.ns_per_day;
    ret -= @as(i64, @divFloor(year - 1, 100)) * time.ns_per_day;
    ret += @as(i64, @divFloor(year + 299, 400)) * time.ns_per_day;

    return ret;
}

pub fn late() void {
    // nothing
}

pub fn halt() noreturn {
    if (!exitedBootServices) while (true) {
        _ = uefi.system_table.boot_services.?.stall(0x7FFFFFFF);
    };
    while (true) {}
}
