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

    wasi: w3.NativeModule = undefined,
    entry_point: w3.Function = undefined,

    pub fn init(proc: *Process, args: Runtime.Args) !Runtime {
        var ret = Runtime{ .proc = proc, .wasm3 = try w3.Runtime.init(args.stack_size) };
        ret.wasi = try w3.NativeModule.init(proc.allocator, "", wasi.Preview1, proc);
        errdefer ret.wasi.deinit();

        ret.module = try ret.wasm3.parseAndLoadModule(args.wasm_image);
        try ret.linkWasi(ret.module);

        ret.entry_point = try ret.wasm3.findFunction("_start");

        return ret;
    }

    pub fn linkWasi(self: *Runtime, module: w3.Module) !void {
        for (wasi.Preview1.namespaces) |namespace| {
            self.wasi.link(namespace, module);
        }
    }

    pub fn start(self: *Runtime) void {
        _ = self.entry_point.callVoid(void) catch null;
    }

    pub fn deinit(self: *Runtime) void {
        self.wasi.deinit();
        self.proc.allocator.destroy(self);
    }
};
