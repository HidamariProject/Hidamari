const std = @import("std");
const fmt = std.fmt;
const platform = @import("platform.zig");

const c = @cImport({
    @cInclude("wasm3/source/m3_env.h");
});

const Error = error{
    Unknown,
    CantCreateEnv,
    CantCreateRuntime,
    NoMoreModules,
    InvalidType,
    InvalidNumArgs,
};

const WasmPtr = struct { offset: u32 };

fn m3ResultToError(m3res: c.M3Result, comptime T: type) !T {
    if (m3res == null) {
        comptime if (T == void) {
            return;
        } else {
            return undefined;
        };
    }
    platform.earlyprintf("M3 Error: {}\r\n", .{std.mem.spanZ(m3res)});
    const err = switch (m3res.?) {
        //    c.m3Err_argumentCountMismatch => Error.InvalidNumArgs,
        else => Error.Unknown,
    };
    return err;
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
            else => @compileError("Invalid type"),
        },
    };
}

pub const ZigFunction = fn (ctx: ZigFunctionCtx) anyerror!void;

pub const ZigFunctionEx = struct {
    name: [*c]const u8,
    sig: [*c]const u8,
    call: ZigFunction,
    _orig: fn () void,

    pub fn init(name: [*c]const u8, f: anytype) ZigFunctionEx {
        comptime var rawftype = @TypeOf(f);
        comptime var ftype = @typeInfo(rawftype);
        comptime var atype = @typeInfo(ftype.Fn.args[1].arg_type.?);
        comptime var sig: [atype.Struct.fields.len + 2 + 1 + 1]u8 = undefined;
        var anonFn = struct {
            pub fn anon(ctx: ZigFunctionCtx) anyerror!void {
                const args = ctx.args(ftype.Fn.args[1].arg_type.?);
                const me = @ptrCast(*ZigFunctionEx, @alignCast(@alignOf(ZigFunctionEx), ctx.cookie));
                var res = @call(.{}, @ptrCast(rawftype, me._orig), .{ ctx, args }) catch |err| return err;
                if (@typeInfo(ftype.Fn.return_type.?).ErrorUnion.payload == void) return else ctx.ret(res);
            }
        }.anon;
        var ret = ZigFunctionEx{ .name = name, .sig = &sig, .call = anonFn, ._orig = @ptrCast(fn () void, f) };
        comptime {
            sig[0] = zigToWasmType(@typeInfo(ftype.Fn.return_type.?).ErrorUnion.payload); // TODO: real thing
            sig[1] = '(';
            var i: usize = 2;
            inline for (atype.Struct.fields) |arg| {
                sig[i] = zigToWasmType(arg.field_type);
                i += 1;
            }
            sig[i] = ')';
            sig[i + 1] = 0;
        }
        return ret;
    }
};

pub const ZigFunctionCtx = struct {
    runtime: Runtime,
    sp: RuntimeStack,
    memory: [*]u8,
    cookie: ?*c_void,

    pub inline fn args(self: ZigFunctionCtx, comptime T: type) T {
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
                        .Pointer => {
                            @field(out, field.name) = @ptrCast(field.field_type, &self.memory[self.sp.get(u64, i)]);
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

pub const Module = struct {
    _mod: c.IM3Module,

    pub fn init(modPtr: c.IM3Module) Module {
        return Module{ ._mod = modPtr };
    }

    pub inline fn name(self: Module) []const u8 {
        return std.mem.spanZ(self.name);
    }

    pub inline fn raw(self: Module) c.IM3Module {
        return self._mod;
    }

    pub fn linkRawFunction(self: Module, modName: [*c]const u8, fName: [*c]const u8, sig: [*c]const u8, rawcall: c.M3RawCall) !void {
        return m3ResultToError(c.m3_LinkRawFunction(self._mod, modName, fName, sig, rawcall), void);
    }

    pub fn linkRawFunctionEx(self: Module, modName: [*c]const u8, fName: [*c]const u8, sig: [*c]const u8, rawcall: c.M3RawCallEx, cookie: *c_void) !void {
        return m3ResultToError(c.m3_LinkRawFunctionEx(self._mod, modName, fName, sig, rawcall, cookie), void);
    }

    fn linkZigFunctionHelper(runtime: c.IM3Runtime, sp: [*c]u64, mem: ?*c_void, cookie: ?*c_void) callconv(.C) ?*c_void {
        var f: ZigFunction = @intToPtr(ZigFunction, @ptrToInt(cookie));
        var bogusRt = Runtime{ ._rt = runtime, ._env = undefined };
        f(ZigFunctionCtx{ .runtime = bogusRt, .sp = RuntimeStack.init(sp), .memory = @ptrCast([*]u8, mem), .cookie = cookie }) catch |err| return @intToPtr(*c_void, @ptrToInt(c.m3Err_trapAbort)); // TODO: memory safety
        return null;
    }

    pub inline fn linkRawZigFunction(self: Module, modName: [*c]const u8, fName: [*c]const u8, sig: [*c]const u8, f: ZigFunction) !void {
        return self.linkRawFunctionEx(modName, fName, sig, Module.linkZigFunctionHelper, @intToPtr(*c_void, @ptrToInt(f))); // use stupid casting hack
    }

    fn linkZigFunctionHelperEx(runtime: c.IM3Runtime, sp: [*c]u64, mem: ?*c_void, cookie: ?*c_void) callconv(.C) ?*c_void {
        var f: *ZigFunctionEx = @intToPtr(*ZigFunctionEx, @ptrToInt(cookie));
        var bogusRt = Runtime{ ._rt = runtime, ._env = undefined };
        f.call(ZigFunctionCtx{ .runtime = bogusRt, .sp = RuntimeStack.init(sp), .memory = @ptrCast([*]u8, mem), .cookie = cookie }) catch |err| return @intToPtr(*c_void, @ptrToInt(c.m3Err_trapAbort)); // TODO: memory safety
        return null;
    }

    pub inline fn linkRawZigFunctionEx(self: Module, modName: [*c]const u8, f: *const ZigFunctionEx) !void {
        return self.linkRawFunctionEx(modName, f.name, f.sig, Module.linkZigFunctionHelperEx, @intToPtr(*c_void, @ptrToInt(f))); // use stupid casting hack
    }

    pub fn destroy(self: Module) void {
        c.m3_FreeModule(self._mod);
    }

    pub fn next(self: Module) !Module {
        if (self._mod.next == null) return Errors.NoMoreModules;
        return Module.init(self._mod.next);
    }
};

pub const Function = struct {
    _func: ?*c.M3Function,
    _runtime: Runtime,

    pub fn init(func: c.IM3Function, runtime: Runtime) Function {
        return Function{ ._func = func, ._runtime = runtime };
    }

    pub fn name(self: Function) []const u8 {
        return std.mem.spanZ(self._func.?.name);
    }

    pub fn numArgs(self: Function) u8 {
        return @truncate(u8, self._func.?.funcType.*.numArgs);
    }

    pub fn callVoid(self: Function, comptime T: type) !T {
        var res = c.m3_Call(self._func);
        if (res != null) return m3ResultToError(res, T);
        comptime if (T == void) return;
        return self._runtime.stack().get(T, 0);
    }

    pub fn callWithArgs(self: Function, comptime T: type, args: [*c]const [*c]const u8, argc: usize) !T {
        var res = c.m3_CallWithArgs(self._func, @intCast(u32, argc), args);
        if (res != null) return m3ResultToError(res, T);
        comptime if (T == void) return;
        return self._runtime.stack().get(T, 0);
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
    _env: c.IM3Environment,
    _rt: ?*c.M3Runtime,

    pub fn init(stackBytes: usize) !Runtime {
        var ret: Runtime = undefined;
        ret._env = c.m3_NewEnvironment();
        if (ret._env == null) return Error.CantCreateEnv;
        errdefer {
            c.m3_FreeEnvironment(ret._env);
        }
        ret._rt = c.m3_NewRuntime(ret._env, @intCast(u32, stackBytes), null);
        if (ret._rt == null) return Error.CantCreateRuntime;
        errdefer {
            c.m3_FreeRuntime(ret._env);
        }
        return ret;
    }

    pub fn parseAndLoadModule(self: Runtime, data: []const u8) !Module {
        var modPtr: c.IM3Module = undefined;
        var res = c.m3_ParseModule(self._env, &modPtr, data.ptr, @intCast(u32, data.len));
        if (res != null) return m3ResultToError(res, Module);
        errdefer {
            c.m3_FreeModule(modPtr);
        }
        res = c.m3_LoadModule(self._rt, modPtr);
        if (res != null) return m3ResultToError(res, Module);
        return Module.init(modPtr);
    }

    pub fn findFunction(self: Runtime, name: [*c]const u8) !Function {
        var rawf: c.IM3Function = undefined;
        var res = c.m3_FindFunction(&rawf, self._rt, name);
        if (res != null) return m3ResultToError(res, Function);
        return Function.init(rawf, self);
    }

    pub inline fn stack(self: Runtime) RuntimeStack {
        var rawstack = @ptrCast([*]u64, @alignCast(@alignOf([*]u64), self._rt.?.stack));
        return RuntimeStack.init(rawstack);
    }

    pub fn deinit(self: Runtime) void {
        c.m3_FreeRuntime(self._rt);
        c.m3_FreeEnvironment(self._env);
    }
};
