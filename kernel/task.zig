// Generic Scheduler for Shinkou.
// Looking for how we run processes? Check `process.zig`.

const std = @import("std");
const platform = @import("platform.zig");
const util = @import("util.zig");

const Cookie = util.Cookie;

pub const Error = error{NoSuchTask};

pub const Task = struct {
    pub const Id = i24;
    pub const EntryPoint = fn (task: *Task) callconv(.Async) void;
    pub const frame_data_align = @alignOf(@Frame(sampleTask));

    pub const KernelParentId: Task.Id = -1;

    parent_tid: ?Task.Id,
    tid: Task.Id,
    cookie_meta: usize,
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
        self.frame_ptr = @frame();
        suspend;
    }

    pub fn kill(self: *Task) void {
        self.killed = true;
    }

    pub fn isKilled(self: *Task, peek: bool) bool { 
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

            if (task.killed) continue;

            if (task.started)
                resume task.frame_ptr
            else
                _ = @asyncCall(task.frame_data, {}, task.entry_point, .{task});
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

fn subFn(t: *Task) void {
    platform.earlyprintk("did something\r\n");
    t.yield();
    platform.earlyprintk("and we're back\r\n");
}

pub fn sampleTask(t: *Task) void {
    var n: u64 = 0;
    t.yield();
    while (true) {
        platform.earlyprintf("tid={} n={}\r\n", .{ t.tid, n });
        n += 1;
        //subFn(t);
    }
}

pub fn tryit(allocator: *std.mem.Allocator) !void {
    var sched = try Scheduler.init(allocator);
    _ = try sched.spawn(null, sampleTask, null, 4096);
    _ = try sched.spawn(null, sampleTask, null, 4096);
    while (true) sched.loop_once();
}
