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

pub const Debug = struct {
    pub const namespaces = [_][:0]const u8{"shinkou_debug"};

    pub fn earlyprintk(ctx: w3.ZigFunctionCtx, args: struct { string: []u8 }) !void {
        platform.earlyprintk(args.string);
    }

    pub fn read_kmem(ctx: w3.ZigFunctionCtx, args: struct {}) !void {
        @panic("Unimplemented!");
    }
};

pub const Preview1 = struct {
    pub const namespaces = [_][:0]const u8{"wasi_snapshot_preview1", "wasi_unstable"};

    const IoVec = packed struct {
        bufptr: u32,
        buflen: u32,
    }; // These structs will always be manually padded if needed

    const Self = @This();

    pub fn proc_exit(ctx: w3.ZigFunctionCtx, args: struct { exit_code: u32 }) !void {
        syscall.exit(myProc(ctx), args.exit_code);
        return w3.Error.Exit;
    }

    pub fn fd_write(ctx: w3.ZigFunctionCtx, args: struct { fd: u32, iovecs: []align(1) Self.IoVec, written: w3.u32_ptr }) !u32 {
        args.written.* = 0;
        for (args.iovecs) |iovec| {
            args.written.* += @truncate(u32, syscall.write(myProc(ctx), args.fd, ctx.memory[iovec.bufptr..iovec.bufptr + iovec.buflen]) catch return errnoInt(.ESUCCESS));
        }
        return errnoInt(.ESUCCESS);
    }

    // WASI only functions

    pub fn args_sizes_get(ctx: w3.ZigFunctionCtx, args: struct { argc: w3.u32_ptr, argv_buf_size: w3.u32_ptr }) !u32 {
        args.argc.* = @truncate(u32, myProc(ctx).argc);
        args.argv_buf_size.* = @truncate(u32, myProc(ctx).argv.len);

        return errnoInt(.ESUCCESS);
    }
};
