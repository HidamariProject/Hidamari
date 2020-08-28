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

pub fn timer_tick() void {
//    if (!systemFlags.coop_multitask) sched.yieldCurrent();
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

    _ = prochost.createProcess(.{ .runtime_type = .wasm, .runtime_arg = .{ .wasm_bytes = init_data } });

    while (true) prochost.scheduler.loopOnce();
    // Should be unreachable;
    @panic("kernel attempted to exit!");
}

fn nopehaha() void {
    var fs = tmpfs.Fs.mount(allocator, null, null) catch unreachable;
    var file = fs.create("file.txt", .File, vfs.Node.Mode.all) catch unreachable;
    platform.earlyprintf("another ret: {}\r\n", .{file.node.write(0, "Hello World\r\n")});
    platform.earlyprintf("stats: {}\r\n", .{file.node.stat});
    var buf: [64]u8 = undefined;
    platform.earlyprintf("readback: {}\r\n", .{file.node.read(0, buf[0..])});
    //task.tryit(allocator) catch unreachable;
    // We shouldn't reach this
    @panic("kernel attempted to exit!");
}

fn neveragain() void {
    var str: [8]u8 = undefined;
    var newStr = vfs.null_node.mode.toString(str[0..]) catch unreachable;
    platform.earlyprintf("MODE={}\r\n", .{newStr});
    _ = vfs.null_node.write(0, "This has gone to null") catch unreachable;
    platform.halt();
    //wasmtest() catch |err| @panic(@errorName(err));
}

fn add(ctx: w3.ZigFunctionCtx) anyerror!void {
    var args = ctx.args(struct { a: i64, b: i64 });
    platform.earlyprintf("{} {}\r\n", .{ args.a, args.b });
    ctx.ret(args.a + args.b);
    //    platform.earlyprintf("{} {} {}\r\n", .{sp.stack[0], sp.stack[1], sp.stack[2]});
    //    sp.stack[0] = sp.stack[0] + sp.stack[1];
}

fn nuadd(ctx: w3.ZigFunctionCtx, args: struct { a: i64, b: i64 }) !i64 {
    platform.earlyprintf("{} {}\r\n", .{ args.a, args.b });
    return args.a + args.b;
}

fn wasmprint(ctx: w3.ZigFunctionCtx, args: struct { a: [*c]const u8 }) !void {
    platform.earlyprintk("wasm is sayin' something\r\n");
    platform.earlyprintf("message from wasm world: {}\r\n", .{std.mem.spanZ(args.a)});
}

fn wasmtest() !void {
    var rt = try w3.Runtime.init(65536);
    platform.earlyprintk("create runtime\r\n");
    var mod = try rt.parseAndLoadModule(binInit[0..]);
    platform.earlyprintk("parse and load\r\n");
    //try mod.linkRawZigFunction("test", "add", "I(II)", add);
    const nufn = w3.ZigFunctionEx.init("add", nuadd);
    mod.linkRawZigFunctionEx("test", &nufn) catch nop();
    const prfn = w3.ZigFunctionEx.init("wasmprint", wasmprint);
    platform.earlyprintf("sig: {}\r\n", .{std.mem.spanZ(prfn.sig)});
    mod.linkRawZigFunctionEx("test", &prfn) catch nop();
    platform.earlyprintk("link func\r\n");
    var func = try rt.findFunction("meaningOfLife");
    platform.earlyprintk("find function\r\n");
    var res = try func.callVoid(i64);
    platform.earlyprintk("call void\r\n");
    platform.earlyprintf("Got val: {}\r\n", .{res});
    var func2 = try rt.findFunction("gimmeFloat");
    platform.earlyprintk("find func2\r\n");
    platform.earlyprintf("numargs: {}\r\n", .{func2.numArgs()});
    var res2 = try func2.call(f64, .{ 5.5, 2.5 });
    platform.earlyprintk("call with 2 arg\r\n");
    platform.earlyprintf("Got val: {}\r\n", .{res2});
    platform.halt();
}
