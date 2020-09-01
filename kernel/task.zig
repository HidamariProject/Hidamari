// Generic Scheduler for Shinkou.
// Looking for how we run processes? Check `process.zig`.

const std = @import("std");
const platform = @import("platform.zig");
const util = @import("util.zig");

const c = @cImport({
    @cInclude("ucontext.h");
});

const Cookie = util.Cookie;

pub const Error = error{NoSuchTask};

fn nop(task: *Task) void {}

pub const Task = struct {
    pub const Id = i24;
    pub const EntryPoint = fn (task: *Task) void;
    pub const stack_data_align = @alignOf(usize);

    pub const KernelParentId: Task.Id = -1;

    scheduler: *Scheduler,
    tid: Task.Id,
    parent_tid: ?Task.Id,
    cookie_meta: usize = undefined,
    cookie: Cookie,

    stack_data: []align(Task.stack_data_align) u8,
    context: c.ucontext_t = undefined,

    started: bool = false,
    killed: bool = false,

    entry_point: Task.EntryPoint,
    on_deinit: ?fn (task: *Task) void = null,

    pub fn init(scheduler: *Scheduler, tid: Task.Id, parent_tid: ?Task.Id, entry_point: Task.EntryPoint, stack_size: usize, cookie: Cookie) !*Task {
        var allocator = scheduler.allocator;

        var ret = try allocator.create(Task);
        errdefer allocator.destroy(ret);

        var stack_data = try allocator.allocAdvanced(u8, Task.stack_data_align, stack_size, .at_least);
        errdefer allocator.free(stack_data);

        ret.* = Task{ .scheduler = scheduler, .tid = tid, .parent_tid = parent_tid, .entry_point = entry_point, .stack_data = stack_data, .cookie = cookie };
        ret.context.uc_stack.ss_sp = @ptrCast(*c_void, stack_data);
        ret.context.uc_stack.ss_size = stack_size;
        c.t_makecontext(&ret.context, Task.entryPoint, @ptrToInt(ret));
        return ret;
    }

    fn entryPoint(self_ptr: usize) callconv(.C) void {
        var self = @intToPtr(*Task, self_ptr);
        self.entry_point(self);
        self.yield();
    }

    pub fn yield(self: *Task) void {
        self.started = false;
        _ = c.t_getcontext(&self.context);
        if (!self.started) _ = c.t_setcontext(&self.scheduler.context);
    }

    pub fn kill(self: *Task) void {
        self.killed = true;
    }

    pub fn wait(self: *Task, peek: bool) bool {
        if (!peek and self.killed) self.parent_tid = null;
        return self.killed;
    }

    pub fn deinit(self: *Task) void {
        if (self.on_deinit) |on_deinit| on_deinit(self);
        self.scheduler.allocator.destroy(self);
    }
};

pub const Scheduler = struct {
    const TaskList = std.AutoHashMap(Task.Id, *Task);

    allocator: *std.mem.Allocator,
    tasks: Scheduler.TaskList,
    next_spawn_tid: Task.Id,

    context: c.ucontext_t = undefined,
    current_tid: ?Task.Id = undefined,

    pub fn init(allocator: *std.mem.Allocator) !Scheduler {
        return Scheduler{ .allocator = allocator, .tasks = Scheduler.TaskList.init(allocator), .next_spawn_tid = 0 };
    }

    pub fn yieldCurrent(self: *Scheduler) void {
        if (self.current_tid) |tid| {
            self.tasks.get(tid).?.yield();
        }
    }

    pub fn spawn(self: *Scheduler, parent_tid: ?Task.Id, entry_point: Task.EntryPoint, cookie: Cookie, stack_size: usize) !*Task {
        var new_index: Task.Id = undefined;
        while (true) {
            new_index = @atomicRmw(Task.Id, &self.next_spawn_tid, .Add, 1, .SeqCst);
            if (self.tasks.get(new_index) == null) break;
        }

        var task = try Task.init(self, new_index, parent_tid, entry_point, stack_size, cookie);
        errdefer task.deinit();

        _ = try self.tasks.put(new_index, task);
        return task;
    }

    pub fn loopOnce(self: *Scheduler) void {
        for (self.tasks.items()) |entry| {
            var task = entry.value;
            self.current_tid = entry.key;

            //            platform.earlyprintf("done={}\n",.{task.killed});
            task.started = true;
            _ = c.t_getcontext(&self.context);
            if (!task.killed and task.started)
                _ = c.t_setcontext(&task.context);

            if (task.parent_tid != null and task.parent_tid.? != Task.KernelParentId and self.tasks.get(task.parent_tid.?) == null)
                task.parent_tid = null;

            if (task.killed and task.parent_tid == null) {
                _ = self.tasks.remove(entry.key);

                task.deinit();
            }
        }
        self.current_tid = null;
    }
};
