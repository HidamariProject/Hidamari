const std = @import("std");
const process = @import("../../process.zig");
const platform = @import("../../platform.zig");
const util = @import("../../util.zig");
const w3 = @import("../../wasm3.zig");
const syscall = @import("../../syscall.zig");

usingnamespace @import("wasi_defs.zig");

const Process = process.Process;

inline fn myProc(ctx: w3.ZigFunctionCtx) *Process {
    return ctx.cookie.?.as(Process);
}

pub const Preview1 = struct {
    pub const namespaces = [_][:0]const u8{"wasi_snapshot_preview1"};

    pub fn proc_exit(ctx: w3.ZigFunctionCtx, args: struct { exit_code: u32 }) !void {
        syscall.exit(myProc(ctx), args.exit_code);
        return w3.Error.Exit;
    }

    //    pub fn args_sizes_get(ctx: w3.ZigFunctionCtx, args: struct {
};
