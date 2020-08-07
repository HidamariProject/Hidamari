const std = @import("std");
const platform = @import("platform.zig");
const util = @import("util.zig");

const Cookie = util.Cookie;

pub const Error = error{NoSuchTask};

pub const Task = struct {
    pub const EntryPoint = fn (task: *Task) callconv(.Async) void;
    pub const frame_data_align = @alignOf(@Frame(sampleTask));

    tid: usize,
    cookie: Cookie,

    frameData: []align(Task.frame_data_align) u8,
    framePtr: anyframe = undefined,

    started: bool = false,
    killed: bool = false,

    entryPoint: Task.EntryPoint,
    deinit: ?fn (task: *Task) void = null,

    pub fn init(tid: usize, entryPoint: Task.EntryPoint, frameData: []align(Task.frame_data_align) u8, cookie: Cookie) Task {
        return Task{ .tid = tid, .entryPoint = entryPoint, .frameData = frameData, .cookie = cookie };
    }

    pub fn yield(task: *Task) void {
        task.framePtr = @frame();
        suspend;
    }

    pub fn kill(task: *Task) void {
        task.killed = true;
    }
};

pub const Scheduler = struct {
    allocator: *std.mem.Allocator,
    tasks: []?*Task,

    pub fn init(allocator: *std.mem.Allocator) !Scheduler {
        return Scheduler{ .allocator = allocator, .tasks = try allocator.alloc(?*Task, 0) };
    }

    fn findFreeSlot(self: *Scheduler) !usize {
        for (self.tasks) |task, i| {
            if (task == null) return i;
        }
        self.tasks = try self.allocator.realloc(self.tasks, self.tasks.len + 1);
        return self.tasks.len - 1;
    }

    pub fn getTask(self: Scheduler, tid: usize) !*Task {
        if (tid >= self.tasks.len) return Error.NoSuchTask;
        if (self.tasks[tid] == null) return Error.NoSuchTask;
        return self.tasks[tid];
    }

    pub fn spawn(self: *Scheduler, entryPoint: Task.EntryPoint, cookie: Cookie) !*Task {
        var newIndex = try self.findFreeSlot();

        var frameData = try self.allocator.allocAdvanced(u8, Task.frame_data_align, 4096, .at_least);
        errdefer {
            self.allocator.free(frameData);
        }

        var task = try self.allocator.create(Task);
        errdefer {
            self.allocator.destroy(task);
        }

        task.* = Task.init(newIndex, entryPoint, frameData, cookie);

        self.tasks[newIndex] = task;
        return task;
    }

    pub fn loop(self: *Scheduler) void {
        while (true) {
            for (self.tasks) |maybeTask, i| {
                if (maybeTask) |task| {
                    if (task.started)
                        resume task.framePtr
                    else
                        _ = @asyncCall(task.frameData, {}, task.entryPoint, .{task});
                    task.started = true;
                    if (task.killed) {
                        self.tasks[i] = null;
                        if (task.deinit) |deinit_fn| {
                            deinit_fn(task);
                        }
                        if (i == self.tasks.len - 1) {
                            // TODO realloc
                        }
                        self.allocator.destroy(task);
                    }
                }
            }
        }
    }
};

fn subFn(t: *Task) void {
    platform.earlyprintk("did something\r\n");
    t.yield();
    platform.earlyprintk("and we're back\r\n");
}

fn sampleTask(t: *Task) void {
    var n: u64 = 0;
    while (true) {
        platform.earlyprintf("tid={} n={}\r\n", .{ t.tid, n });
        n += 1;
        subFn(t);
    }
}

pub fn tryit(allocator: *std.mem.Allocator) !void {
    var sched = try Scheduler.init(allocator);
    _ = try sched.spawn(sampleTask, null);
    _ = try sched.spawn(sampleTask, null);
    sched.loop();
}
