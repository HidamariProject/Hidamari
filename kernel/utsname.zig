const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("utsname_extra.h");
});

// Static info that can (and will) be changed

pub const sys_name = "Codename Shinkou";
pub const release = "0.0.1-alpha";

// Actual code

pub const machine = @tagName(builtin.os.tag) ++ "-" ++ @tagName(builtin.cpu.arch);

var version_buf: [64]u8 = undefined;
var version_slice: ?[]u8 = undefined;

pub const UtsName = struct {
    sys_name: []const u8 = sys_name,
    node_name: []const u8 = "unknown",
    release: []const u8 = release,
    version: []const u8 = undefined,
    machine: []const u8 = machine,
};

pub fn uname() UtsName {
    if (version_slice == null)
        version_slice = std.fmt.bufPrint(version_buf[0..], "{} {}", .{ std.mem.spanZ(c.compile_date), std.mem.spanZ(c.compile_time) }) catch unreachable;
    return .{
        .version = version_slice.?,
    };
}
