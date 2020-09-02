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
    pub const namespaces = [_][:0]const u8{ "wasi_snapshot_preview1", "wasi_unstable" };

    const IoVec = packed struct {
        bufptr: u32,
        buflen: u32,
    }; // These structs will always be manually padded if needed

    const PrestatDir = packed struct {
        fd_type: u32 = 0,
        name_len: u32 = 0,
    };

    const Self = @This();

    pub fn proc_exit(ctx: w3.ZigFunctionCtx, args: struct { exit_code: u32 }) !void {
        syscall.exit(myProc(ctx), args.exit_code);
        return w3.Error.Exit;
    }

    pub fn sched_yield(ctx: w3.ZigFunctionCtx, args: struct {}) !u32 {
        myProc(ctx).task().yield();
        return errnoInt(.ESUCCESS);
    }

    pub fn fd_prestat_get(ctx: w3.ZigFunctionCtx, args: struct { fd: u32, prestat: *align(1) Self.PrestatDir }) !u32 {
        if (myProc(ctx).open_nodes.get(@truncate(process.Fd.Num, args.fd))) |fd| {
            if (!fd.preopen) return errnoInt(.ENOTSUP);
            args.prestat.* = .{ .name_len = if (fd.name != null) @truncate(u32, fd.name.?.len) else 0 };
            return errnoInt(.ESUCCESS);
        }
        return errnoInt(.EBADF);
    }

    pub fn fd_prestat_dir_name(ctx: w3.ZigFunctionCtx, args: struct { fd: u32, name: []u8 }) !u32 {
        if (myProc(ctx).open_nodes.get(@truncate(process.Fd.Num, args.fd))) |fd| {
            std.mem.copy(u8, args.name, if (fd.name != null) fd.name.? else "");
            return errnoInt(.ESUCCESS);
        }
        return errnoInt(.EBADF);
    }

    pub fn fd_write(ctx: w3.ZigFunctionCtx, args: struct { fd: u32, iovecs: []align(1) Self.IoVec, written: w3.u32_ptr }) !u32 {
        myProc(ctx).task().yield();
        args.written.* = 0;
        if (myProc(ctx).open_nodes.get(@truncate(process.Fd.Num, args.fd))) |fd| {
            for (args.iovecs) |iovec| {
                args.written.* += @truncate(u32, fd.write(ctx.memory[iovec.bufptr .. iovec.bufptr + iovec.buflen]) catch |err| return errnoInt(errorToNo(err)));
            }
            return errnoInt(.ESUCCESS);
        }
        return errnoInt(.EBADF);
    }

    pub fn fd_read(ctx: w3.ZigFunctionCtx, args: struct { fd: u32, iovecs: []align(1) Self.IoVec, amount: w3.u32_ptr }) !u32 {
        myProc(ctx).task().yield();
        args.amount.* = 0;
        if (myProc(ctx).open_nodes.get(@truncate(process.Fd.Num, args.fd))) |fd| {
            for (args.iovecs) |iovec| {
                args.amount.* += @truncate(u32, fd.read(ctx.memory[iovec.bufptr .. iovec.bufptr + iovec.buflen]) catch |err| return errnoInt(errorToNo(err)));
            }
            return errnoInt(.ESUCCESS);
        }
        return errnoInt(.EBADF);
    }

    // WASI only functions

    pub fn args_sizes_get(ctx: w3.ZigFunctionCtx, args: struct { argc: w3.u32_ptr, argv_buf_size: w3.u32_ptr }) !u32 {
        args.argc.* = @truncate(u32, myProc(ctx).argc);
        args.argv_buf_size.* = @truncate(u32, myProc(ctx).argv.len);

        return errnoInt(.ESUCCESS);
    }
};
