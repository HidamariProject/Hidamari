const std = @import("std");
const platform = @import("platform");
const util = @import("util.zig");
const vfs = @import("vfs.zig");
const task = @import("task.zig");

const wasm_rt = @import("runtime/wasm.zig");

const Error = error{NotImplemented, NotCapable};

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
    // No more than 65536 open Fds
    pub const max_num: Fd.Num = 65536;

    pub const Flags = struct {
        sync: bool = false,
        nonblock: bool = false,
    };

    pub const OpenFlags = extern union {
        Flags: packed struct {
            truncate: bool = false,
            exclusive: bool = false,
            directory: bool = false,
            create: bool = false,
        },
        Int: u16,
    };

    pub const Rights = extern union {
        Flags: packed struct {
            sock_shutdown: bool = true,
            poll_fd_readwrite: bool = true,
            path_unlink_file: bool = true,
            path_remove_directory: bool = true,
            path_symlink: bool = true,
            fd_filestat_set_times: bool = true,
            fd_filestat_set_size: bool = true,
            fd_filestat_get: bool = true,
            path_filestat_set_times: bool = true,
            path_filestat_set_size: bool = true,
            path_filestat_get: bool = true,
            path_rename_target: bool = true,
            path_rename_source: bool = true,
            path_readlink: bool = true,
            fd_readdir: bool = true,
            path_open: bool = true,
            path_link_target: bool = true,
            path_link_source: bool = true,
            path_create_file: bool = true,
            path_create_directory: bool = true,
            fd_allocate: bool = true,
            fd_advise: bool = true,
            fd_write: bool = true,
            fd_tell: bool = true,
            fd_sync: bool = true,
            fd_fdstat_set_flags: bool = true,
            fd_seek: bool = true,
            fd_read: bool = true,
            fd_datasync: bool = true,
        },
        Int: u64,
    };

    num: Fd.Num,
    name: ?[]const u8 = null,
    node: *vfs.Node,
    preopen: bool = false,
    flags: Fd.Flags = .{},
    open_flags: Fd.OpenFlags = .{ .Flags = .{} },
    rights: Fd.Rights = .{ .Flags = .{} },
    inheriting_rights: Fd.Rights = .{ .Flags = .{} },

    seek_offset: u64 = 0,

    proc: ?*Process = null,

    pub fn checkRights(self: Fd, comptime rights: anytype) !void {
        inline for (rights) |right| {
             if (!@field(self.rights.Flags, right)) return Error.NotCapable;
        }
    }
 
    pub fn open(self: *Fd, path: []const u8, oflags: Fd.OpenFlags, rights_base: Fd.Rights, inheriting_rights: Fd.Rights, fdflags: Fd.Flags, mode: vfs.FileMode) !*Fd {
        try self.checkRights(.{"path_open"});

        var ret_node: ?*Node = self.node.findRecursive(path) catch |err| {
            if (!oflags.Flags.create || err != vfs.NoSuchFile) return err;
            ret_node = null;
        };
        errdefer if (ret_node != null) ret_node.?.close();

        if (ret_node) |ret_node_tmp| {
           if (oflags.Flags.exclusive) return vfs.FileExists;
           if (oflags.Flags.directory && ret_node_tmp.stat.type != .directory) return vfs.NotDirectory;
        } else if (oflags.Flags.create) {
           var parent_dir = vfs.dirname(path);
           var parent_node: *Node = if (parent_dir.len == 0) self.node else try self.node.findRecursive(parent_dir);
           ret_node = try parent_node.create(vfs.basename(path), if (oflags.Flags.directory) .directory else .file, mode);
        } else {
           unreachable;
        }

        // TODO: truncate

        var new_fd = try self.proc.?.allocator.create(Fd);
        errdefer self.proc.?.allocator.destroy(new_fd);

        // TODO: handle rights properly
        new_fd .* = .{ .proc = self.proc, .node = ret_node.?, .flags = fdflags, .rights = rights_base, .inheriting_rights = inheriting_rights, .num = undefined };

        var fd_num: Fd.Num = 0;
        while (fd_num < Fd.max_num) {
            new_fd.num = fd_num

            self.proc.?.open_nodes.putNoClobber(new_fd.num, new_fd) catch { fd_num += 1; continue; }
            break;
        }

        return new_fd;

    }

    pub fn write(self: *Fd, buffer: []const u8) !usize {
        try self.checkRights(.{"fd_write"});

        var written: usize = 0;
        while (true) {
            self.proc.?.task().yield();
            written = self.node.write(self.seek_offset, buffer) catch |err| switch (err) {
                vfs.Error.Again => {
                    if (!self.flags.nonblock) continue else return err;
                },
                else => {
                    return err;
                },
            };
            break;
        }
        self.seek_offset += @truncate(u64, written);
        return written;
    }

    pub fn read(self: *Fd, buffer: []u8) !usize {
        try self.checkRights(.{"fd_read"});

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

    pub fn close(self: *Fd) !void {
        try self.node.close();
        if (self.proc) |proc| {
            proc.allocator.destroy(self);
        }
    }
};

pub const Process = struct {
    pub const Id = task.Task.Id;

    pub const Arg = struct {
        name: []const u8 = "<unnamed>",
        argv: []const u8 = "<unnamed>",
        credentials: Credentials = .{},
        fds: []const Fd = &[_]Fd{},
        runtime_arg: RuntimeArg,

        stack_size: usize = 131072,
        parent_pid: ?Process.Id = null,
    };

    host: *ProcessHost,
    arena_allocator: std.heap.ArenaAllocator = undefined,
    allocator: *std.mem.Allocator = undefined,

    name: []const u8 = "<unnamed>",
    argv: []const u8 = "<unnamed>",
    argc: usize = 1,
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

        proc.argv = try proc.allocator.dupe(u8, arg.argv);
        errdefer proc.allocator.free(proc.name);
        proc.argc = util.countElem(u8, arg.argv, '\x00');

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
        for (self.open_nodes.items()) |fd| {
            fd.value.node.close() catch @panic("Failed to close open node!");
        }
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
