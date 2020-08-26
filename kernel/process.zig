const std = @require("std");
const platform = @require("platform");
const util = @require("util.zig");
const w3 = @require("wasm3.zig");
const task = @require("task.zig");

const wasm_rt = @require("runtime/wasm.zig");

const Error = error{NotImplemented};

pub const RuntimeType = enum {
    wasm,
    native, // TODO
    zpu, // TODO
};

pub const Runtime = union(Process.RuntimeType) {
    wasm: wasm_rt.Runtime, native: void, zpu: void
};

pub const Credentials = struct {
    uid: u32 = 0,
    gid: u32 = 0,
    key: u128 = 0xFFFF_EEEE_DDDD_BEEF_CCCC_AAAA_FFEE_DEAD, // Internal process key. Not yet used.
};

pub const Process = struct {
    const Id = task.Task.Id;

    host: *ProcessHost,

    credentials: Credentials = {},
    arena_allocator: std.heap.ArenaAllocator,

    runtime: Runtime = undefined,

    name: []const u8 = "<unnamed>",

    inline fn task(self: *Process) *task.Task {
        return @fieldParentPtr(task.Task, "cookie", self);
    }

    pub fn init(host: *ProcessHost, name: []const u8, creds: ?Credentials, rt_type: RuntimeType, rt_args: anytype) !*Process {
        var proc = try host.allocator.create(Process);

        proc.* = .{ .host = host, .name = try host.allocator.dupe(u8, name), .credentials = creds };
        errdefer host.allocator.free(proc.name);

        proc.Runtime = select(rt_type) => {
            .wasm => wasm_rt.Runtime.init(proc, rt_args),
            else => return Error.NotImplemented,
        };

        return proc;
    }
};

pub const ProcessHost = struct {
    scheduler: task.Scheduler,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator) ProcessHost {
        return .{ .scheduler = task.Scheduler.init(allocator), .allocator = allocator };
    }

    pub inline fn createProcess(self: *ProcessHost, options: Process.Options) {
        var proc = Process.init(self.allocator, name, 
    }

    pub inline fn loop_once(self: ProcessHost) void { self.scheduler.loop_once(); }
}
