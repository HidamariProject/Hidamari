const std = @import("std");
const process = @import("process.zig");
const w3 = @import("wasm3.zig");

const Process = process.Process;

pub fn exit(proc: *Process, exit_code: u32) void {
    proc.exit_code = exit_code;
}


