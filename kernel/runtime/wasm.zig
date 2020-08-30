// The WebAssembly runtime

const std = @import("std");
const process = @import("../process.zig");
const platform = @import("../platform.zig");
const util = @import("../util.zig");
const w3 = @import("../wasm3.zig");

const wasi = @import("wasm/wasi.zig");

const Process = process.Process;

pub const Runtime = struct {
    pub const Args = struct {
        wasm_image: []u8,
        stack_size: usize = 64 * 1024,
        link_wasi: bool = true,
    };

    proc: *Process,

    wasm3: w3.Runtime,
    module: w3.Module = undefined,

    wasi_impl: w3.NativeModule = undefined,
    debug_impl: w3.NativeModule = undefined,
    entry_point: w3.Function = undefined,

    pub fn init(proc: *Process, args: Runtime.Args) !Runtime {
        var ret = Runtime{ .proc = proc, .wasm3 = try w3.Runtime.init(args.stack_size) };

        ret.wasi_impl = try w3.NativeModule.init(proc.allocator, "", wasi.Preview1, proc);
        errdefer ret.wasi_impl.deinit();
        ret.debug_impl = try w3.NativeModule.init(proc.allocator, "", wasi.Debug, proc);
        errdefer ret.debug_impl.deinit();

        ret.module = try ret.wasm3.parseAndLoadModule(args.wasm_image);
        try ret.linkStd(ret.module);

        ret.entry_point = try ret.wasm3.findFunction("_start");

        return ret;
    }

    pub fn linkStd(self: *Runtime, module: w3.Module) !void {
        for (wasi.Preview1.namespaces) |namespace| {
            self.wasi_impl.link(namespace, module);
        }
        self.debug_impl.link("shinkou_debug", module);
    }

    pub fn start(self: *Runtime) void {
        _ = self.entry_point.callVoid(void) catch |err| {
            switch(err) {
                w3.Error.Exit => { return; },
                else => { platform.earlyprintf("ERR: {}\r\n", .{@errorName(err)}); }
            }
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.wasi_impl.deinit();
        self.debug_impl.deinit();
        self.proc.allocator.destroy(self);
    }
};
