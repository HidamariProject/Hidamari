//! The WebAssembly runtime

const process = @import("../process.zig");
const w3 = @import("../wasm3.zig");
const wasi = @import("wasm/wasi.zig");

const Process = process.Process;

pub const Runtime = struct {
    pub const Args = struct {
        wasm_image: []u8,
        stack_size: usize = 64 * 1024,
    };

    proc: *Process,

    wasm3: w3.Runtime,
    module: w3.Module = undefined,
    wasi: wasi.Wasi = .{},

    pub fn init(proc: *Process, args: Runtime.Args) !Runtime {
         var ret = Runtime{ .proc = proc, .wasm3 = try w3.Runtime.init(args.stack_size); };
         ret.module = try ret.wasm3.parseAndLoadModule(args.wasm_image);
         try wasi.link(ret, ret.module);
         return ret;
    }
};
