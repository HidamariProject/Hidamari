const std = @import("std");
extern "shinkou_debug" fn earlyprintk(str: [*]const u8, str_len: usize) void;

pub fn main() !u8 {
    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();

    var message = "Hello World from userspace!\n\n";
    _ = try std.io.getStdErr().writer().write(message);

    var preopens = std.fs.wasi.PreopenList.init(std.heap.page_allocator);
    try preopens.populate();

    for (preopens.asSlice()) |preopen| {
        _ = try stdout.write(preopen.type.Dir);
        _ = try stdout.write("\n");
    }

    var buf: [100]u8 = undefined;

    while (true) {
        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |line| {
            _ = try stdout.write("you said: ");
            _ = try stdout.write(line);
            _ = try stdout.write("\n");
            if (std.mem.eql(u8, line, "panic")) @panic("panic()'ing now");
        }
    }
    return 42;
}
