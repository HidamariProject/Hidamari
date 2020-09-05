const std = @import("std");
const platform = @import("platform.zig");

var clock: struct {
    real: i64 = 0,
    monotonic: i64 = 0,
    uptime: i64 = 0,
} = .{};

var timer_interval: i64 = 0;

pub fn init() void {
    timer_interval = platform.getTimerInterval();
    clock.real = platform.getTimeNano();
}

pub fn tick() void {
    // TODO: probably should use atomics for this
    _ = @atomicRmw(i64, &clock.real, .Add, timer_interval, .SeqCst);
    _ = @atomicRmw(i64, &clock.monotonic, .Add, timer_interval, .SeqCst);
    _ = @atomicRmw(i64, &clock.uptime, .Add, timer_interval, .SeqCst);
}

pub fn getClockNano(clock_name: anytype) i64 {
    return @field(clock, @tagName(clock_name));
}

pub fn setClockNano(clock_name: anytype, new_time: i64) void {
    @field(clock, @tagName(clock_name)) = new_time;
}

pub fn getClock(clock_name: anytype) i64 {
    return @divFloor(getClockNano(clock_name), std.time.ns_per_s);
}
