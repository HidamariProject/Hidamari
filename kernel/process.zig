const std = @import("std");
const platform = @import("platform");
const util = @import("util.zig");
const vfs = @import("vfs.zig");
const task = @import("task.zig");

const wasm_rt = @import("runtime/wasm.zig");

const Error = error{NotImplemented};

pub const RuntimeType = enum {
    wasm,
    native, // TODO
    zpu, // TODO
};

pub const Runtime = union(RuntimeType) {
    wasm: wasm_rt.Runtime, native: void, zpu: void
};

pub const Credentials = struct {
    uid: u32 = 0,
    gid: u32 = 0,
    extra_groups: ?[]u32 = null,
    key: u128 = 0xFFFF_EEEE_DDDD_BEEF_CCCC_AAAA_FFEE_DEAD, // Internal process key. Not yet used.
};

pub const Process = struct {
    pub const Id = task.Task.Id;

    pub const Arg = struct {
        name: []const u8 = "<unnamed>",
        creds: Credentials = .{},
        runtime_type: RuntimeType,
        runtime_arg: anytype,

        stack_size: usize = 32768,
        parent_pid: ?Process.Id,
    };

    host: *ProcessHost,
    arena_allocator: std.heap.ArenaAllocator,
    allocator: *std.mem.Allocator,

    name: []const u8 = "<unnamed>",
    credentials: Credentials = {},
    runtime: Runtime = undefined,

    openedNodes: std.AutoHashMap(u32, *vfs.Node),

    bogus_task: ?*task.Task,

    inline fn task(self: *Process) *task.Task {
        if (self.bogus_task) |task| { return task; }
        return @fieldParentPtr(task.Task, "cookie", self);
    }

    pub fn init(host: *ProcessHost, arg: Process.Arg) !*Process {
        var proc = try host.allocator.create(Process);

        proc.* = .{ .host = host, .name = try host.allocator.dupe(u8, arg.name), .credentials = arg.creds };
        errdefer host.allocator.free(proc.name);

        proc.arena_allocator = std.heap.ArenaAllocator.init(&host.allocator);
        errdefer proc.arena_allocator.deinit();

        proc.allocator = &proc.arena_allocator.allocator;

        proc.runtime = switch(arg.runtime_type) {
            .wasm => wasm_rt.Runtime.init(proc, arg.runtime_arg),
            else => { return Error.NotImplemented; }
        };
        errdefer proc.runtime.deinit();

        return proc;
    }

    pub fn entryPoint(self_task: *task.Task) void {
        var process = self_task.cookie.as(Process);
        process.runtime.start();
    }

    pub fn deinit(self: *Process) void {
        self.runtime.deinit();
        self.arena_allocator.deinit();
    }

    pub fn deinitTrampoline(self_task: *task.Task) void {
        self_task.cookie.as(Process).deinit();
    }
};

fn nop() void {

}

pub const ProcessHost = struct {
    scheduler: task.Scheduler,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator) !ProcessHost {
        return ProcessHost{ .scheduler = try task.Scheduler.init(allocator), .allocator = allocator };
    }

    pub inline fn createProcess(self: *ProcessHost, options: Process.Arg) !*Task {
        var proc = Process.init(self.allocator, options);
        var task = try self.scheduler.spawn(options.parent_pid, proc.entryPoint, util.asCookie(proc), options.stack_size);
        task.deinit = proc.deinitTrampoline;

        return task;
    }

    pub fn loopOnce(self: *ProcessHost) void {
        var sched = &self.scheduler;
        sched.loopOnce();
    }
};
