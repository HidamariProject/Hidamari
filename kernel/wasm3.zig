const std = @import("std");
const builtin = @import("builtin");
const fmt = std.fmt;
const util = @import("util.zig");
const platform = @import("platform.zig");

const Cookie = util.Cookie;

const c = @cImport({
    @cInclude("wasm3/source/m3_env.h");
});

pub const Error = error{
    Unknown,
    CantCreateEnv,
    CantCreateRuntime,
    NoMoreModules,
    InvalidAlignment,
    InvalidType,
    InvalidNumArgs,
    Exit,
    Abort,
    OutOfBounds,
    NoSuchFunction,
};

pub const WasmPtr = extern struct { offset: u32 };

// These types should be used for pointers because WASM memory can be unaligned
pub const u32_ptr = *align(1) u32;
pub const i32_ptr = *align(1) i32;
pub const u64_ptr = *align(1) u64;
pub const i64_ptr = *align(1) i64;

pub const u32_ptr_many = [*]align(1) u32;
pub const i32_ptr_many = [*]align(1) i32;
pub const u64_ptr_many = [*]align(1) u64;
pub const i64_ptr_many = [*]align(1) i64;

const errorConversionPair = struct { a: c.M3Result, b: Error };
var errorConversionTable_back: [256]errorConversionPair = undefined;
var errorConversionTable_len: usize = 0;
var errorConversionTable: ?[]errorConversionPair = null;

inline fn errorConversionTableAddEntry(a: c.M3Result, b: Error) void {
    errorConversionTable_back[errorConversionTable_len] = .{ .a = a, .b = b };
    errorConversionTable_len += 1;
}

fn initErrorConversionTable() void {
    const e = errorConversionTableAddEntry;
    e(c.m3Err_argumentCountMismatch, Error.InvalidNumArgs);
    e(c.m3Err_trapExit, Error.Exit);
    e(c.m3Err_trapAbort, Error.Abort);
    e(c.m3Err_trapOutOfBoundsMemoryAccess, Error.OutOfBounds);
    e(c.m3Err_functionLookupFailed, Error.NoSuchFunction);
    errorConversionTable = errorConversionTable_back[0..errorConversionTable_len];
}

fn m3ResultToError(m3res: c.M3Result, comptime T: type) !T {
    if (m3res == null) {
        comptime if (T == void) {
            return;
        } else {
            return undefined;
        };
    }

    if (errorConversionTable == null) initErrorConversionTable();
    for (errorConversionTable.?) |entry| {
        if (m3res == entry.a) return entry.b;
    }

    if (builtin.mode == .Debug) platform.earlyprintf("Warning: can't convert to Zig error: {}\n", .{std.mem.spanZ(m3res)});
    return Error.Unknown;
}

fn errorToM3Result(err: ?anyerror) c.M3Result {
    if (err == null) return null;

    if (errorConversionTable == null) initErrorConversionTable();
    for (errorConversionTable.?) |entry| {
        if (err.? == entry.b) return entry.a;
    }
    return c.m3Err_trapAbort;
}

inline fn boundsCheck(obj: anytype, off: usize, len: usize) !void {
    if (obj.len <= off or obj.len <= (off + len)) return Error.OutOfBounds;
}

pub const RuntimeStack = struct {
    stack: [*]u64,

    pub inline fn init(ptr: [*]u64) RuntimeStack {
        return RuntimeStack{ .stack = ptr };
    }

    pub inline fn set(self: RuntimeStack, index: usize, val: anytype) void {
        switch (@TypeOf(val)) {
            u64, u32 => self.stack[index] = @intCast(u64, val),
            i64, i32 => self.stack[index] = @intCast(u64, val),
            else => @compileError("Invalid type"),
        }
    }

    pub inline fn get(self: RuntimeStack, comptime T: type, index: usize) T {
        return switch (T) {
            u64 => self.stack[index],
            usize => @truncate(usize, self.stack[index] & 0xFFFFFFFF),
            i64 => @intCast(i64, self.stack[index]),
            u32 => @truncate(u32, self.stack[index] & 0xFFFFFFFF),
            i32 => @truncate(i32, self.stack[index] & 0xFFFFFFFF),
            f64 => (@ptrCast([*]align(1) f64, self.stack))[index],
            else => @compileError("Invalid type"),
        };
    }
};

fn zigToWasmType(comptime T: type) u8 {
    return switch (T) {
        u64, i64 => 'I',
        u32, i32 => 'i',
        f64 => 'F',
        f32 => 'f',
        void, u0 => 'v',
        WasmPtr => '*',
        else => switch (@typeInfo(T)) {
            .Pointer => '*',
            .Enum => |enm| zigToWasmType(enm.tag_type),
            else => @compileError("Invalid type"),
        },
    };
}

fn zigToWasmTypeMulti(comptime T: type, out: []u8) usize {
    switch (@typeInfo(T)) {
        .Pointer => |ptr| {
            switch (ptr.size) {
                .Slice => {
                    out[0] = '*';
                    out[1] = 'i';
                    return 2;
                },
                else => {
                    out[0] = '*';
                    return 1;
                },
            }
        },
        else => {
            out[0] = zigToWasmType(T);
            return 1;
        },
    }
    unreachable;
}

pub const ZigFunction = fn (ctx: ZigFunctionCtx) anyerror!void;

pub const ZigFunctionEx = struct {
    name: [*c]const u8,
    sig: [*c]const u8,
    call: ZigFunction,
    cookie: Cookie = null,
    _orig: fn () void,

    pub fn init(name: [*c]const u8, f: anytype) ZigFunctionEx {
        comptime var rawftype = @TypeOf(f);
        comptime var ftype = @typeInfo(rawftype);
        comptime var fninfo = ftype.Fn;
        comptime var atype = @typeInfo(fninfo.args[1].arg_type.?);
        comptime var sig: [atype.Struct.fields.len * 2 + 2 + 1 + 1]u8 = undefined;
        var anonFn = struct {
            pub fn anon(ctx: ZigFunctionCtx) anyerror!void {
                const args = try ctx.args(fninfo.args[1].arg_type.?);
                const me = @ptrCast(*ZigFunctionEx, @alignCast(@alignOf(ZigFunctionEx), ctx.trampoline));
                var res = @call(.{}, @ptrCast(rawftype, me._orig), .{ ctx, args }) catch |err| return err;
                if (@typeInfo(fninfo.return_type.?).ErrorUnion.payload == void) return else ctx.ret(res);
            }
        }.anon;
        var ret = ZigFunctionEx{ .name = name, .sig = &sig, .call = anonFn, ._orig = @ptrCast(fn () void, f) };
        comptime {
            sig[0] = zigToWasmType(@typeInfo(fninfo.return_type.?).ErrorUnion.payload); // TODO: real thing
            sig[1] = '(';
            var i: usize = 2;
            inline for (atype.Struct.fields) |arg| {
                i += zigToWasmTypeMulti(arg.field_type, sig[i..sig.len]);
            }
            sig[i] = ')';
            sig[i + 1] = 0;
        }
        return ret;
    }

    pub inline fn lenInitMany(comptime prefix: []const u8, comptime typ: type) comptime usize {
        comptime {
            var t = @typeInfo(typ);
            var i = 0;
            for (t.Struct.decls) |decl| {
                if (std.mem.startsWith(u8, decl.name, prefix))
                    i += switch (decl.data) {
                        .Fn => 1,
                        else => 0,
                    };
            }
            return i;
        }
    }

    pub inline fn initMany(comptime prefix: []const u8, comptime s: type) [lenInitMany(prefix, s)]ZigFunctionEx {
        comptime {
            var ret: [lenInitMany(prefix, s)]ZigFunctionEx = undefined;
            var t = @typeInfo(s);
            var i = 0;
            for (t.Struct.decls) |decl| {
                if (std.mem.startsWith(u8, decl.name, prefix)) {
                    switch (decl.data) {
                        .Fn => {
                            var name: [decl.name.len - prefix.len + 1:0]u8 = undefined;
                            std.mem.copy(u8, name[0..], decl.name[prefix.len..]);
                            name[name.len - 1] = 0;
                            ret[i] = init(name[0..], @field(s, decl.name));
                            i += 1;
                        },
                        else => {},
                    }
                }
            }
            return ret;
        }
    }
};

pub const ZigFunctionCtx = struct {
    runtime: Runtime,
    sp: RuntimeStack,
    memory: []u8,
    trampoline: ?*c_void,
    cookie: Cookie = null,

    pub inline fn args(self: ZigFunctionCtx, comptime T: type) !T {
        var out: T = undefined;
        comptime var tinfo = @typeInfo(T);
        comptime var i: usize = 0;
        inline for (tinfo.Struct.fields) |field| {
            switch (field.field_type) {
                u64, i64, u32, i32, f64, f32 => {
                    @field(out, field.name) = self.sp.get(field.field_type, i);
                    i += 1;
                },
                else => {
                    switch (@typeInfo(field.field_type)) {
                        .Pointer => |ptr| {
                            switch (ptr.size) {
                                .One, .Many => {
                                    try boundsCheck(self.memory, self.sp.get(usize, i), @sizeOf(ptr.child));
                                    @field(out, field.name) = @ptrCast(field.field_type, @alignCast(ptr.alignment, &self.memory[self.sp.get(usize, i)]));
                                    i += 1;
                                },
                                .Slice => {
                                    try boundsCheck(self.memory, self.sp.get(usize, i), self.sp.get(usize, i + 1));
                                    var rawptr = @ptrCast([*]align(1) ptr.child, @alignCast(1, &self.memory[self.sp.get(usize, i)]));
                                    var len = self.sp.get(usize, i + 1);
                                    @field(out, field.name) = rawptr[0..len];
                                    i += 2;
                                },
                                else => @compileError("Invalid pointer type"),
                            }
                        },
                        .Enum => |enm| {
                            // TODO: check if value is valid
                            @field(out, field.name) = @intToEnum(field.field_type, self.sp.get(enm.tag_type, i));
                            i += 1;
                        },
                        else => @compileError("Invalid type"),
                    }
                },
            }
        }
        return out;
    }

    pub inline fn ret(self: ZigFunctionCtx, val: anytype) void {
        self.sp.set(0, val);
    }
};

pub const NativeModule = struct {
    allocator: *std.mem.Allocator,
    functions: []ZigFunctionEx,

    pub fn init(allocator: *std.mem.Allocator, comptime prefix: []const u8, impl: type, cookie: anytype) !NativeModule {
        var ret = NativeModule{ .allocator = allocator, .functions = try allocator.dupe(ZigFunctionEx, ZigFunctionEx.initMany(prefix, impl)[0..]) };
        for (ret.functions) |_, i| {
            ret.functions[i].cookie = util.asCookie(cookie);
        }
        return ret;
    }

    pub fn link(self: NativeModule, namespace: [:0]const u8, module: Module) void {
        for (self.functions) |_, i| {
            _ = module.linkRawZigFunctionEx(namespace, &self.functions[i]) catch null;
        }
    }

    pub fn deinit(self: NativeModule) void {
        self.allocator.free(self.functions);
    }
};

pub const Module = struct {
    module: c.IM3Module,

    pub fn init(modPtr: c.IM3Module) Module {
        return Module{ .module = modPtr };
    }

    pub inline fn name(self: Module) []const u8 {
        return std.mem.spanZ(self.name);
    }

    pub inline fn raw(self: Module) c.IM3Module {
        return self.module;
    }

    pub fn linkRawFunction(self: Module, modName: [*c]const u8, fName: [*c]const u8, sig: [*c]const u8, rawcall: c.M3RawCall) !void {
        return m3ResultToError(c.m3_LinkRawFunction(self.module, modName, fName, sig, rawcall), void);
    }

    pub fn linkRawFunctionEx(self: Module, modName: [*c]const u8, fName: [*c]const u8, sig: [*c]const u8, rawcall: c.M3RawCallEx, cookie: *c_void) !void {
        return m3ResultToError(c.m3_LinkRawFunctionEx(self.module, modName, fName, sig, rawcall, cookie), void);
    }

    fn linkZigFunctionHelper(runtime: c.IM3Runtime, sp: [*c]u64, mem: ?*c_void, cookie: ?*c_void) callconv(.C) ?*c_void {
        var f: ZigFunction = @intToPtr(ZigFunction, @ptrToInt(cookie));
        var bogusRt = Runtime{ .runtime = runtime, .environ = undefined };
        var mem_slice = @ptrCast([*]u8, mem)[0 .. @intCast(usize, runtime.*.memory.numPages) * 65536];
        f(ZigFunctionCtx{ .runtime = bogusRt, .sp = RuntimeStack.init(sp), .memory = mem_slice }) catch |err| return @intToPtr(*c_void, @ptrToInt(errorToM3Result(err)));
        return null;
    }

    pub inline fn linkRawZigFunction(self: Module, modName: [*c]const u8, fName: [*c]const u8, sig: [*c]const u8, f: ZigFunction) !void {
        return self.linkRawFunctionEx(modName, fName, sig, Module.linkZigFunctionHelper, @intToPtr(*c_void, @ptrToInt(f))); // use stupid casting hack
    }

    fn linkZigFunctionHelperEx(runtime: c.IM3Runtime, sp: [*c]u64, mem: ?*c_void, cookie: ?*c_void) callconv(.C) ?*c_void {
        var f: *ZigFunctionEx = @intToPtr(*ZigFunctionEx, @ptrToInt(cookie));
        var bogusRt = Runtime{ .runtime = runtime, .environ = undefined };
        var mem_slice = @ptrCast([*]u8, mem)[0 .. @intCast(usize, runtime.*.memory.numPages) * 65536];
        f.call(ZigFunctionCtx{ .runtime = bogusRt, .sp = RuntimeStack.init(sp), .memory = mem_slice, .cookie = f.cookie, .trampoline = f }) catch |err| return @intToPtr(*c_void, @ptrToInt(errorToM3Result(err)));
        return null;
    }

    pub inline fn linkRawZigFunctionEx(self: Module, modName: [*c]const u8, f: *const ZigFunctionEx) !void {
        return self.linkRawFunctionEx(modName, f.name, f.sig, Module.linkZigFunctionHelperEx, @intToPtr(*c_void, @ptrToInt(f))); // use stupid casting hack
    }

    pub fn destroy(self: Module) void {
        c.m3_FreeModule(self.module);
    }

    pub fn next(self: Module) !Module {
        if (self.module.next == null) return Errors.NoMoreModules;
        return Module.init(self.module.next);
    }
};

pub const Function = struct {
    func: ?*c.M3Function,
    runtime: Runtime,

    pub fn init(func: c.IM3Function, runtime: Runtime) Function {
        return Function{ .func = func, .runtime = runtime };
    }

    pub fn name(self: Function) []const u8 {
        return std.mem.spanZ(self.func.?.name);
    }

    pub fn numArgs(self: Function) u8 {
        return @truncate(u8, self.func.?.funcType.*.numArgs);
    }

    pub fn callVoid(self: Function, comptime T: type) !T {
        var res = c.m3_Call(self.func);
        if (res != null) return m3ResultToError(res, T);
        comptime if (T == void) return;
        return self.runtime.stack().get(T, 0);
    }

    pub fn callWithArgs(self: Function, comptime T: type, args: [*c]const [*c]const u8, argc: usize) !T {
        var res = c.m3_CallWithArgs(self.func, @intCast(u32, argc), args);
        if (res != null) return m3ResultToError(res, T);
        comptime if (T == void) return;
        return self.runtime.stack().get(T, 0);
    }

    pub fn call(self: Function, comptime T: type, args: anytype) !T {
        comptime var tInfo = @typeInfo(@TypeOf(args));
        var trueArgs: [tInfo.Struct.fields.len][32]u8 = undefined;
        var cArgs: [tInfo.Struct.fields.len + 1][*c]u8 = undefined;
        inline for (tInfo.Struct.fields) |field, i| {
            switch (@typeInfo(field.field_type)) {
                .ComptimeInt, .Int => try fmt.bufPrint(trueArgs[i][0..], "{d}\x00", .{@field(args, field.name)}),
                .ComptimeFloat => {
                    {
                        var rtFloat: f64 = @field(args, field.name);
                        _ = try fmt.bufPrint(trueArgs[i][0..], "{d}\x00", .{@ptrCast([*]u64, &rtFloat)[0]});
                    }
                },
                .Float => switch (@typeInfo(field.field_type).Float.bits) {
                    64 => _ = try fmt.bufPrint(trueArgs[i][0..], "{d}\x00", .{@ptrCast([*]u64, &@field(args, field.name))[0]}),
                    32 => _ = try fmt.bufPrint(trueArgs[i][0..], "{d}\x00", .{@ptrCast([*]u32, &@field(args, field.name))[0]}),
                    else => @compileError("Invalid float type"),
                },
                else => @compileError("Invalid argument type"),
            }
            cArgs[i] = &trueArgs[i];
        }
        cArgs[tInfo.Struct.fields.len] = @intToPtr([*c]u8, 0);
        return self.callWithArgs(T, &cArgs, tInfo.Struct.fields.len);
    }
};

pub const Runtime = struct {
    environ: c.IM3Environment,
    runtime: ?*c.M3Runtime,

    pub fn init(stackBytes: usize) !Runtime {
        var ret: Runtime = undefined;
        ret.environ = c.m3_NewEnvironment();
        if (ret.environ == null) return Error.CantCreateEnv;
        errdefer c.m3_FreeEnvironment(ret.environ);
        ret.runtime = c.m3_NewRuntime(ret.environ, @intCast(u32, stackBytes), null);
        if (ret.runtime == null) return Error.CantCreateRuntime;
        errdefer c.m3_FreeRuntime(ret.environ);

        return ret;
    }

    pub fn parseAndLoadModule(self: Runtime, data: []const u8) !Module {
        var modPtr: c.IM3Module = undefined;
        var res = c.m3_ParseModule(self.environ, &modPtr, data.ptr, @intCast(u32, data.len));
        if (res != null) return m3ResultToError(res, Module);
        errdefer {
            c.m3_FreeModule(modPtr);
        }
        res = c.m3_LoadModule(self.runtime, modPtr);
        if (res != null) return m3ResultToError(res, Module);
        return Module.init(modPtr);
    }

    pub fn findFunction(self: Runtime, name: [*c]const u8) !Function {
        var rawf: c.IM3Function = undefined;
        var res = c.m3_FindFunction(&rawf, self.runtime, name);
        if (res != null) return m3ResultToError(res, Function);
        return Function.init(rawf, self);
    }

    pub inline fn stack(self: Runtime) RuntimeStack {
        var rawstack = @ptrCast([*]u64, @alignCast(@alignOf([*]u64), self.runtime.?.stack));
        return RuntimeStack.init(rawstack);
    }

    pub fn deinit(self: Runtime) void {
        c.m3_FreeRuntime(self.runtime);
        c.m3_FreeEnvironment(self.environ);
    }
};
