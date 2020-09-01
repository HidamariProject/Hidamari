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

pub const Fd = struct {
    pub const Num = u32;
    pub const Flags = struct {
        sync: bool = false,
        nonblock: bool = false,
    };

    num: Fd.Num,
    node: *vfs.Node,
    preopen: bool = false,
    flags: Fd.Flags = .{},

    seek_offset: u64 = 0,

    proc: ?*Process = null,

    pub fn write(self: *Fd, buffer: []const u8) !usize {
        var written = try self.node.write(self.seek_offset, buffer);
        self.seek_offset += @truncate(u64, written);
        return written;
    }

    pub fn read(self: *Fd, buffer: []u8) !usize {
        var amount: usize = 0;
        while (true) {
            self.proc.?.task().yield();
            amount = self.node.read(self.seek_offset, buffer) catch |err| switch (err) {
                vfs.Error.Again => {
                    if (!self.flags.nonblock) continue else return err;
                },
                else => {
                    return err;
                },
            };
            break;
        }
        self.seek_offset += @truncate(u64, amount);
        return amount;
    }
};

pub const Process = struct {
    pub const Id = task.Task.Id;

    pub const Arg = struct {
        name: []const u8 = "<unnamed>",
        credentials: Credentials = .{},
        fds: []const Fd = &[_]Fd{},
        runtime_arg: RuntimeArg,

        stack_size: usize = 1262144,
        parent_pid: ?Process.Id = null,
    };

    host: *ProcessHost,
    arena_allocator: std.heap.ArenaAllocator = undefined,
    allocator: *std.mem.Allocator = undefined,

    name: []const u8 = "<unnamed>",
    argc: usize = 1,
    argv: []const u8 = "<unnamed>\x00",
    credentials: Credentials = .{},
    runtime: Runtime = undefined,

    open_nodes: std.AutoHashMap(Fd.Num, *Fd) = undefined,
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
        errdefer proc.allocator.free(proc.name);

        proc.credentials = arg.credentials;

        proc.runtime = switch (arg.runtime_arg) {
            .wasm => .{ .wasm = try wasm_rt.Runtime.init(proc, arg.runtime_arg.wasm) },
            else => {
                return Error.NotImplemented;
            },
        };
        errdefer proc.runtime.deinit();

        proc.open_nodes = @TypeOf(proc.open_nodes).init(proc.allocator);
        for (arg.fds) |fd| {
            var fd_alloced = try proc.allocator.create(Fd);
            fd_alloced.* = fd;
            fd_alloced.proc = proc;
            try proc.open_nodes.putNoClobber(fd.num, fd_alloced);
            errdefer proc.allocator.destroy(fd_alloced);
            try fd_alloced.node.open();
            errdefer fd_alloced.node.close();
        }

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
        self.host.allocator.destroy(self);
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
        ret.on_deinit = Process.deinitTrampoline;

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
