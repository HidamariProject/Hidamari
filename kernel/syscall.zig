const std = @import("std");
const process = @import("process.zig");

const Process = process.Process;

const Error = error{NotImplemented, BadFd};

pub fn exit(proc: *Process, exit_code: u32) void {
    proc.exit_code = exit_code;
}

pub fn write(proc: *Process, fd: process.Fd.Num, buffer: []const u8) !usize {
    if(proc.open_nodes.get(fd)) |handle| {
        // TODO: rights checking
        var written = try handle.node.write(handle.seek_offset, buffer);
        handle.seek_offset += written;
        return written; 
    }
    return Error.BadFd;
}

