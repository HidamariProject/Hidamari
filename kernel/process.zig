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
    wasm: wasm_rt.Runtime,
    native: void,
    zpu: void,

    fn start(self: *Runtime) void {
        switch (self.*) {
            .wasm => self.wasm.start(),
            .native => unreachable,
            else => unreachable,
        }
    }

    fn deinit(self: *Runtime) void {
        switch (self.*) {
            .wasm => self.wasm.deinit(),
            .native => unreachable,
            else => unreachable,
        }
    }
};

pub const RuntimeArg = union(RuntimeType) {
    wasm: wasm_rt.Runtime.Args, native: void, zpu: void
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
        credentials: Credentials = .{},
        runtime_arg: RuntimeArg,

        stack_size: usize = 32768,
        parent_pid: ?Process.Id = null,
    };

    host: *ProcessHost,
    arena_allocator: std.heap.ArenaAllocator = undefined,
    allocator: *std.mem.Allocator = undefined,

    name: []const u8 = "<unnamed>",
    credentials: Credentials = .{},
    runtime: Runtime = undefined,

    openedNodes: std.AutoHashMap(u32, *vfs.Node) = undefined,
    exit_code: ?u32 = undefined,

    internal_task: ?*task.Task = null,

    pub inline fn task(self: *Process) *task.Task {
        return self.internal_task.?;
    }

    pub fn init(host: *ProcessHost, arg: Process.Arg) !*Process {
        var proc = try host.allocator.create(Process);

        proc.* = .{ .host = host };

        proc.arena_allocator = std.heap.ArenaAllocator.init(host.allocator);
        errdefer proc.arena_allocator.deinit();

        proc.allocator = &proc.arena_allocator.allocator;

        proc.name = try proc.allocator.dupe(u8, arg.name);
        proc.credentials = arg.credentials;

        proc.runtime = switch (arg.runtime_arg) {
            .wasm => .{ .wasm = try wasm_rt.Runtime.init(proc, arg.runtime_arg.wasm) },
            else => {
                return Error.NotImplemented;
            },
        };
        errdefer proc.runtime.deinit();

        return proc;
    }

    pub fn entryPoint(self_task: *task.Task) void {
        var process = self_task.cookie.?.as(Process);
        process.runtime.start();
        self_task.killed = true;
    }

    pub fn deinit(self: *Process) void {
        self.runtime.deinit();
        self.arena_allocator.deinit();
    }

    pub fn deinitTrampoline(self_task: *task.Task) void {
        self_task.cookie.?.as(Process).deinit();
    }
};

pub const ProcessHost = struct {
    scheduler: task.Scheduler,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator) !ProcessHost {
        return ProcessHost{ .scheduler = try task.Scheduler.init(allocator), .allocator = allocator };
    }

    pub inline fn createProcess(self: *ProcessHost, options: Process.Arg) !*Process {
        var proc = try Process.init(self, options);
        var ret = try self.scheduler.spawn(options.parent_pid, Process.entryPoint, util.asCookie(proc), options.stack_size);
        proc.internal_task = ret;
        ret.deinit = Process.deinitTrampoline;

        return proc;
    }

    pub inline fn get(self: *ProcessHost, id: Process.Id) ?*Process {
        var my_task = self.scheduler.tasks.get(id);
        if (my_task == null) return null;
        return my_task.?.cookie.?.as(Process);
    }

    pub fn loopOnce(self: *ProcessHost) void {
        var sched = &self.scheduler;
        sched.loopOnce();
    }
};
