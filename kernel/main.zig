const std = @import("std");
const builtin = std.builtin;

const platform = @import("platform.zig");
const w3 = @import("wasm3.zig");
const vfs = @import("vfs.zig");
const task = @import("task.zig");
const process = @import("process.zig");

const utsname = @import("utsname.zig");

const tmpfs = @import("fs/tmpfs.zig");
const zipfs = @import("fs/zipfs.zig");

var systemFlags = .{
    .coop_multitask = true, // Run in cooperative multitasking mode
};

extern fn allSanityChecks() callconv(.C) void;
pub inline fn nop() void {}

pub fn panic(message: []const u8, stack_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    if (platform.early()) {
        platform.earlyprintk("KERNEL PANIC! Early system initialization failure: ");
        platform.earlyprintk(message);
        platform.earlyprintk("\r\n");
        platform.earlyprintf("!!! -> 0x{x}\r\n", .{@returnAddress()});
        if (@errorReturnTrace()) |trace| {
            for (trace.instruction_address[0..trace.index]) |func, i| {
                platform.earlyprintf("{} -> 0x{x}\r\n", .{ i, func });
            }
        } else {
            platform.earlyprintk("Kernel built without stack trace support.\r\n");
        }
        platform.earlyprintk("End stack trace.\r\n");
        platform.earlyprintk("\r\nWell, that didn't go well. Perhaps we should try again? Press the power button to reset.\r\n");
    }
    platform.halt();
}

// Generated at build time
const initrd_zip = @embedFile("../output/temp/initrd.zip");

var prochost: process.ProcessHost = undefined;
var terminated: bool = false;

pub fn timer_tick() void {
    if (!systemFlags.coop_multitask) prochost.scheduler.yieldCurrent();
}

pub fn main() void {
    // Initialize platform
    platform.init();

    // Run sanity tests
    platform.earlyprintk("Running hardware integrity tests. If the system crashes during these, that's your problem, not mine.\r\n");
    allSanityChecks();
    platform.earlyprintk("Tests passed.\r\n");

    // Show kernel information
    var info = utsname.uname();
    platform.earlyprintf("{} {} {} {}\r\n", .{ info.sys_name, info.release, info.version, info.machine });
    platform.earlyprintk("(C) 2020 Ronsor Labs. This software is protected by domestic and international copyright law.\r\n\r\n");

    // Create allocator. TODO: good one
    const static_size = 32 * 1024 * 1024;
    var big_buffer = platform.internal_malloc(static_size).?;
    var allocator = &std.heap.FixedBufferAllocator.init(big_buffer[0..static_size]).allocator;

    var dev_initrd = vfs.ReadOnlyNode.init(initrd_zip);
    platform.earlyprintf("Size of initial ramdisk in bytes: {}.\r\n", .{dev_initrd.stat.size});

    // TODO: support other formats
    var rootfs = zipfs.Fs.mount(allocator, &dev_initrd, null) catch unreachable;
    platform.earlyprintk("Mounted initial ramdisk.\r\n");

    // Setup process host
    prochost = process.ProcessHost.init(allocator) catch unreachable;

    platform.setTimer(timer_tick);

    // TODO: spawn kernel thread
    //_ = sched.spawn(null, task.sampleTask, null, 4096) catch unreachable;

    var bin_file = rootfs.find("bin") catch unreachable;
    var init_file = bin_file.node.find("init") catch unreachable;

    var init_data = allocator.alloc(u8, init_file.node.stat.size) catch unreachable;
    _ = init_file.node.read(0, init_data) catch unreachable;

    platform.earlyprintf("Size of /bin/init in bytes: {}.\r\n", .{init_data.len});

    _ = prochost.createProcess(.{ .parent_pid = task.Task.KernelParentId, .runtime_arg = .{ .wasm = .{ .wasm_image = init_data } } }) catch @panic("can't create init process!");

    while (!terminated) {
        prochost.scheduler.loopOnce();
        var init_proc = prochost.get(0);
        if (init_proc) |proc| {
            if (proc.task().killed) {
                _ = proc.task().wait(false);
                var exit_code = proc.exit_code;
                platform.earlyprintf("init exited with code: {}\r\n", .{exit_code});
                terminated = true;
            }
        }
    }
    // Should be unreachable;
    @panic("init exited!");
}
