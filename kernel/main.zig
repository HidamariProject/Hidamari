const std = @import("std");
const builtin = std.builtin;
const platform = @import("platform.zig");

const w3 = @import("wasm3.zig");

const vfs = @import("vfs.zig");
const tmpfs = @import("fs/tmpfs.zig");

const utsname = @import("utsname.zig");

extern fn allSanityChecks() callconv(.C) void;
pub inline fn nop() void {}

pub fn panic(message: []const u8, stack_trace: ?*builtin.StackTrace) noreturn {
    if (platform.early()) {
        platform.earlyprintk("Early system initialization failure: ");
        platform.earlyprintk(message);
        platform.earlyprintk("\r\n");
        platform.earlyprintf("-> {x}\r\n", .{@returnAddress()});
    }
    platform.halt();
}

fn log(a: anytype) void {
    platform.earlyprintf("LOG: {}\r\n", .{a});
}

const binInit = @embedFile("init.wasm");

var bigBuffer: [32 * 1024 * 1024]u8 = undefined;

pub fn main() void {
    platform.init();
    platform.earlyprintk("Running hardware integrity tests. If the system crashes during these, that's your problem, not mine.\r\n");
    allSanityChecks();
    platform.earlyprintk("Tests passed.\r\n");
    var info = utsname.uname();
    platform.earlyprintf("{} {} {} {}\r\n", .{ info.sys_name, info.release, info.version, info.machine });

    var allocator = &std.heap.FixedBufferAllocator.init(bigBuffer[0..]).allocator;
    log(vfs.null_node.write("hello world\r\n"));
    var fs = tmpfs.TmpFs.init(allocator, null) catch unreachable;
    var dir = fs.open("testdir", .{ .create = true, .directory = true }, vfs.FileMode.world_exec_writable) catch unreachable;
    var dir2 = fs.open("mounted", .{ .create = true, .directory = true }, vfs.FileMode.world_exec_writable) catch unreachable;
    var fs2 = tmpfs.TmpFs.init(allocator, null) catch unreachable;
    dir2.mount(fs2) catch unreachable;
    var nod = dir.open("test.txt", .{ .write = true, .create = true }, vfs.FileMode.world_writable) catch unreachable;
    log(nod);
    log(nod.write("this is text"));
    //nod.close() catch unreachable;
    dir.unlink("test.txt") catch unreachable;
    var dirents: [16]vfs.DirEntry = undefined;
    var n = fs.readDir(0, dirents[0..]) catch unreachable;
    log(n);
    for (dirents[0..n]) |entry| {
        platform.earlyprintf("File: {} - ino={}\r\n", .{ entry.name, entry.inode });
    }
    platform.earlyprintf("Stat: {}\r\n", .{dir2.stat()});
    platform.halt();
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
