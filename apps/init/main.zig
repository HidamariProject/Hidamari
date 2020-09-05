const std = @import("std");
extern "shinkou_debug" fn earlyprintk(str: [*]const u8, str_len: usize) void;

pub fn main() !u8 {
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();

    var message = "Hello World from userspace!\n\n";
    _ = try std.io.getStdErr().writer().write(message);

    var preopens = std.fs.wasi.PreopenList.init(std.heap.page_allocator);
    try preopens.populate();

    for (preopens.asSlice()) |preopen| {
        _ = try stdout.write("Found open fd: ");
        _ = try stdout.write(preopen.type.Dir);
        _ = try stdout.write("\n");
    }

    for (args) |arg| {
        _ = try stdout.write("Found arg: ");
        _ = try stdout.write(arg);
        _ = try stdout.write("\n");
    }

    try stdout.print("System time: {}\n", .{std.time.timestamp()});

    var buf: [100]u8 = undefined;

    while (true) {
        _ = try stdout.write("command> ");
        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |line| {
            _ = try stdout.write("you said: ");
            _ = try stdout.write(line);
            _ = try stdout.write("\n");
            if (std.mem.eql(u8, line, "panic")) @panic("panic()'ing now");
            if (std.mem.eql(u8, line, "time")) try stdout.print("System time: {}\n", .{std.time.timestamp()});
        }
    }
    return 42;
}

