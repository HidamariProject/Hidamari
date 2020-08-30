const std = @import("std");
const process = @import("process.zig");

const Process = process.Process;

const Error = error{NotImplemented};

pub fn exit(proc: *Process, exit_code: u32) void {
    proc.exit_code = exit_code;
}

pub fn write(proc: *Process, fd: process.Fd.Num, buffer: []const u8) !usize {
    // TODO: actually write stuff
    return Error.NotImplemented;
}

