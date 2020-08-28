// The WebAssembly runtime

const process = @import("../process.zig");
const platform = @import("../platform.zig");
const util = @import("../util.zig");
const w3 = @import("../wasm3.zig");

const Process = process.Process;

inline fn myProc(ctx: *w3.ZigFunctionCtx) *Process {
    return ctx.cookie.as(Process);
}

const WasiPreview1 = struct {
    pub const namespaces = [_][:0]const u8{"wasi_unstable", "wasi_snapshot_preview1"};
    pub const num_exports = w3.ZigFunctionEx.lenInitMany("", WasiPreview1);

    pub fn proc_exit(ctx: *w3.ZigFunctionCtx, args: struct { exit_code: u32 }) !void {
        myProc(ctx).exit_code = args.exit_code;
        return w3.Error.Exit;
    }
};


pub const Runtime = struct {
    pub const Args = struct {
        wasm_image: []u8,
        stack_size: usize = 64 * 1024,
        link_wasi: bool = true,
    };

    proc: *Process,

    wasm3: w3.Runtime,
    module: w3.Module = undefined,

    wasip1_funcs: []w3.ZigFunctionEx,
    entrypoint: w3.Function,

    pub fn init(args: Runtime.Args) !*Runtime {
         var ret = Runtime{ .proc = proc, .wasm3 = try w3.Runtime.init(args.stack_size) };
         ret.wasip1_funcs = try ret.proc.allocator.dupe(w3.ZigFunctionEx.initMany("", WasiPreview1)[0..]);

         ret.module = try ret.wasm3.parseAndLoadModule(args.wasm_image);
         ret.linkWasi(module);

         ret.entry_point = ret.wasm3.findFunction("_start");

         return ret;
    }

    pub fn linkWasi(self: *Runtime, module: w3.Module) void {
         for (WasiPreview1.namespaces) |namespace| {
             for (self.wasip1_funcs) |_, i| {
                 _ = module.linkRawZigFunctionEx(namespace, &self.wasip1_funcs[i]) catch null;
             }
         }
    }

    pub fn start() void {
         self.entry_point.callVoid(void);
         platform.earlyprintk("The program terminated. Awww\r\n");        
    }

    pub fn deinit(self: *Runtime) void {
         self.proc.allocator.free(self.wasip1_proc);
         self.proc.allocator.destroy(self);
    }
};
