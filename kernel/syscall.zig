const std = @import("std");
const process = @import("process.zig");
const w3 = @import("wasm3.zig");

const Process = process.Process;

fn myProc(in: anytype) *Process {
    return in.cookie.as(*Process);
}

const Error = {Exit};

pub const Impl = struct {
    pub fn proc_exit(ctx: anytype, args: struct { exit_code: u32 }) !void {
        myProc(ctx).exit_code = args.exit_code;
        return Error.Exit;
    }
};


