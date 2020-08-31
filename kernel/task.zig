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
    pub const EntryPoint = fn (task: *Task) callconv(.Async) void;
    pub const frame_data_align = @alignOf(@Frame(nop));

    pub const KernelParentId: Task.Id = -1;

    parent_tid: ?Task.Id,
    tid: Task.Id,
    cookie_meta: usize = undefined,
    cookie: Cookie,

    frame_data: []align(Task.frame_data_align) u8,
    frame_ptr: anyframe = undefined,

    started: bool = false,
    killed: bool = false,

    entry_point: Task.EntryPoint,
    deinit: ?fn (task: *Task) void = null,

    pub fn init(tid: Task.Id, parent_tid: ?Task.Id, entry_point: Task.EntryPoint, frame_data: []align(Task.frame_data_align) u8, cookie: Cookie) Task {
        return Task{ .tid = tid, .parent_tid = parent_tid, .entry_point = entry_point, .frame_data = frame_data, .cookie = cookie };
    }

    pub fn yield(self: *Task) void {
        platform.earlyprintk("gonna yield\n");
        platform.earlyprintk("actually gonna yield\n");
        self.frame_ptr = @frame();
        suspend;
while (true) {}
        platform.earlyprintk("back\r\n");
    }

    pub fn kill(self: *Task) void {
        self.killed = true;
    }

    pub fn wait(self: *Task, peek: bool) bool {
        if (!peek and self.killed) self.parent_tid = null;
        return self.killed;
    }
};

pub const Scheduler = struct {
    const TaskList = std.AutoHashMap(Task.Id, *Task);

    allocator: *std.mem.Allocator,
    tasks: Scheduler.TaskList,
    next_spawn_tid: Task.Id,

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

        var frame_data = try self.allocator.allocAdvanced(u8, Task.frame_data_align, stack_size, .at_least);
        errdefer self.allocator.free(frame_data);

        var task = try self.allocator.create(Task);
        errdefer self.allocator.destroy(task);

        task.* = Task.init(new_index, parent_tid, entry_point, frame_data, cookie);

        _ = try self.tasks.put(new_index, task);
        return task;
    }

    pub fn loopOnce(self: *Scheduler) void {
        for (self.tasks.items()) |entry| {
            var task = entry.value;
            self.current_tid = entry.key;
platform.earlyprintf("{x} DO\n", .{@ptrCast(*c_void, task)});
platform.earlyprintk("lap\n");
platform.earlyprintf("{} DO\n", .{.{ .started = task.started, .killed = task.killed}});
            if (!task.killed and task.started) {
//                resume task.frame_ptr;
            } else if (!task.killed) {
                _ = @asyncCall(task.frame_data, {}, task.entry_point, .{task});
            }
platform.earlyprintk("lap(B)\n");
            task.started = true;

            if (task.parent_tid != null and task.parent_tid.? != Task.KernelParentId and self.tasks.get(task.parent_tid.?) == null)
                task.parent_tid = null;

            if (task.killed and task.parent_tid == null) {
                _ = self.tasks.remove(entry.key);

                if (task.deinit) |deinit_fn| {
                    deinit_fn(task);
                }

                self.allocator.free(task.frame_data);
                self.allocator.destroy(task);
            }
        }
        self.current_tid = null;
    }
};

var ctx: c.ucontext_t = undefined;
var orig: c.ucontext_t = undefined;
var stk: [4096]u8 = undefined;

pub fn tryme() callconv(.C) void {
    _ = c.t_getcontext(&ctx);
_ = c.t_swapcontext(&orig, &ctx);
    // haha undefined behavior
    ctx.uc_stack.ss_sp = &stk;
    ctx.uc_stack.ss_size = @sizeOf(@TypeOf(stk));
    ctx.uc_link = &orig;
    _ = c.__makecontext(&ctx, @ptrCast(fn () callconv(.C) void, tryentry), 0, @intCast(u32, 65535));
    platform.earlyprintf("{}\n", .{ctx.uc_mcontext.gregs[0..16]});
    _ = c.t_swapcontext(&orig, &ctx);
}

fn tryentry() callconv(.C) void {
    platform.earlyprintf("I got: {x}\n", .{83});
    @panic("that's all folks!");
//    _ = c.swapcontext(&ctx, &orig);
}
