const std = @import("std");
const builtin = std.builtin;

const platform = @import("platform.zig");
const w3 = @import("wasm3.zig");
const vfs = @import("vfs.zig");
const task = @import("task.zig");
const process = @import("process.zig");
const time = @import("time.zig");

const utsname = @import("utsname.zig");

const tmpfs = @import("fs/tmpfs.zig");
const zipfs = @import("fs/zipfs.zig");

var kernel_flags = .{
    .coop_multitask = true, // Run in cooperative multitasking mode
    .save_cpu = true, // Use `hlt` so we don't spike CPU usage
    .init_args = "init\x00default\x00",
};

extern fn allSanityChecks() callconv(.C) void;
pub inline fn nop() void {}

pub fn panic(message: []const u8, stack_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    if (platform.early()) {
        platform.earlyprintk("\nKERNEL PANIC! Early system initialization failure: ");
        platform.earlyprintk(message);
        platform.earlyprintk("\r\n");
        platform.earlyprintf("(!) -> 0x{x}\r\n", .{@returnAddress()});
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

pub fn timerTick() void {
    time.tick();

    if (!kernel_flags.coop_multitask) {
        platform.beforeYield();
        prochost.scheduler.yieldCurrent();
    }
}

pub fn main() void {
    // Initialize platform
    platform.init();

    // Run sanity tests
    platform.earlyprintk("Running hardware integrity tests. If the system crashes during these, that's your problem, not mine.\r\n");
    allSanityChecks();
    platform.earlyprintk("Tests passed.\r\n");

    // Show kernel information
    time.init();

    var info = utsname.uname();
    platform.earlyprintf("{} {} {} {}\r\n", .{ info.sys_name, info.release, info.version, info.machine });
    platform.earlyprintk("(C) 2020 Ronsor Labs. This software is protected by domestic and international copyright law.\r\n\r\n");
    platform.earlyprintf("Boot timestamp: {}.\r\n", .{ time.getClock(.real) });


    // Create allocator. TODO: good one
    const static_size = 32 * 1024 * 1024;
    var big_buffer = platform.internal_malloc(static_size).?;
    var allocator = &std.heap.FixedBufferAllocator.init(big_buffer[0..static_size]).allocator;

    var dev_initrd = vfs.ReadOnlyNode.init(initrd_zip);
    platform.earlyprintf("Size of initial ramdisk in bytes: {}.\r\n", .{dev_initrd.stat.size});

    // TODO: support other formats
    var rootfs = zipfs.Fs.mount(allocator, &dev_initrd, null) catch @panic("Can't mount initrd!");
    platform.earlyprintk("Mounted initial ramdisk.\r\n");

    // Setup process host
    prochost = process.ProcessHost.init(allocator) catch @panic("Can't initialize process host!");

    platform.setTimer(timerTick);

    var init_file = rootfs.findRecursive("/bin/init") catch @panic("Can't find init binary!");

    var init_data = allocator.alloc(u8, init_file.node.stat.size) catch @panic("Can't read init binary!");
    _ = init_file.node.read(0, init_data) catch unreachable;

    platform.earlyprintf("Size of /bin/init in bytes: {}.\r\n", .{init_data.len});

    var console_node = platform.openConsole();
    _ = console_node.write(0, "Initialized /dev/console.\r\n") catch @panic("Can't initialize early console!");

    var init_proc_options = process.Process.Arg{
        .name = "/bin/init",
        .argv = kernel_flags.init_args,
        .parent_pid = task.Task.KernelParentId,
        .fds = &[_]process.Fd{
            .{ .num = 0, .node = &console_node },
            .{ .num = 1, .node = &console_node },
            .{ .num = 2, .node = &console_node },
            .{ .num = 3, .node = rootfs, .preopen = true, .name = "/" },
        },
        .runtime_arg = .{
            .wasm = .{
                .wasm_image = init_data,
            },
        },
    };

    _ = prochost.createProcess(init_proc_options) catch @panic("Can't create init process!");

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
        if (kernel_flags.save_cpu) platform.waitTimer(1);
    }
    // Should be unreachable;
    @panic("init exited!");
}
