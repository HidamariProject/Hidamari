const std = @import("std");
const platform = @import("platform.zig");
const util = @import("util.zig");

const Cookie = util.Cookie;
const RefCount = util.RefCount;

pub const max_name_len = 256;

pub const Error = error{ NotImplemented, NotDirectory, NotFile, NoSuchFile, FileExists, NotEmpty, ReadFailed, WriteFailed };

/// Node represents a FileSystem VNode
/// There should only be ONE VNode in memory per file at a time!
/// Any other situation may cause unexpected results!
pub const Node = struct {
    pub const Mode = packed struct {
        // Remember, LSB first! exec, write, read (xwr) & everyone, group, user (egu) order!
        // TODO: care about big-endian systems
        const RWX = packed struct { x: bool = false, w: bool = false, r: bool = false };

        all: Node.Mode.RWX = .{},
        grp: Node.Mode.RWX = .{},
        usr: Node.Mode.RWX = .{},
        _padding: u7 = 0,

        pub fn init(val: u16) Mode {
            var m: Mode = .{};
            m.set(val);
            return m;
        }

        pub fn get(self: *const Mode) u16 {
            return @ptrCast(*u16, self).*;
        }
        pub fn set(self: *Mode, val: u16) void {
            @ptrCast(*u16, self).* = val;
        }

        pub const all = Mode{
            .all = .{ .x = true, .w = true, .r = true },
            .grp = .{ .x = true, .w = true, .r = true },
            .usr = .{ .x = true, .w = true, .r = true },
        };
    };

    pub const Flags = struct {
        mount_point: bool = false,
        read_only: bool = false,
    };

    pub const Type = enum {
        None,
        File,
        Directory,
        BlockDevice,
        CharacterDevice,
        SymLink,
        Socket,
        Fifo,
    };

    pub const Stat = struct {
        type: Node.Type = .None,

        mode: Mode = .{},
        uid: u32 = 0,
        gid: u32 = 0,

        size: u64 = 0,

        access_time: i64 = 0,
        create_time: i64 = 0,
        modify_time: i64 = 0,

        links: i64 = 0,
        blocks: u64 = 0,
        block_size: u64 = 1,
        flags: Node.Flags = .{},

        inode: u64 = 0,
    };

    pub const Ops = struct {
        open: ?fn (self: *Node) anyerror!void = null,
        close: ?fn (self: *Node) anyerror!void = null,

        read: ?fn (self: *Node, offset: u64, buffer: []u8) anyerror!usize = null,
        write: ?fn (self: *Node, offset: u64, buffer: []const u8) anyerror!usize = null,

        find: ?fn (self: *Node, name: []const u8) anyerror!File = null,
        create: ?fn (self: *Node, name: []const u8, typ: Node.Type, mode: Node.Mode) anyerror!File = null,
        link: ?fn (self: *Node, name: []const u8, other_node: *Node) anyerror!File = null,
        unlink: ?fn (self: *Node, name: []const u8) anyerror!void = null,
        readDir: ?fn (self: *Node, offset: u64, files: []File) anyerror!usize = null,

        unlink_me: ?fn (self: *Node) anyerror!void = null,
        free_me: ?fn (self: *Node) void = null,
    };

    stat: Stat = .{},
    opens: RefCount = .{},
    file_system: ?*FileSystem,

    ops: Node.Ops,
    cookie: Cookie = null,
    alt_cookie: ?[]const u8 = null,

    pub fn init(ops: Node.Ops, cookie: Cookie, stat: ?Stat, file_system: ?*FileSystem) Node {
        return .{ .ops = ops, .cookie = cookie, .stat = if (stat != null) stat.? else .{}, .file_system = file_system };
    }

    pub fn open(self: *Node) !void {
        if (self.ops.open) |open_fn| {
            try open_fn(self);
        }
        self.opens.ref();
    }

    pub fn close(self: *Node) !void {
        self.opens.unref();
        if (self.ops.close) |close_fn| {
            close_fn(self) catch |err| {
                self.opens.ref();
                return err;
            };
        }
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        if (self.ops.read) |read_fn| {
            return try read_fn(self, offset, buffer);
        }
        return Error.NotImplemented;
    }

    pub fn write(self: *Node, offset: u64, buffer: []const u8) !usize {
        if (self.ops.write) |write_fn| {
            return try write_fn(self, offset, buffer);
        }
        return Error.NotImplemented;
    }

    pub fn find(self: *Node, name: []const u8) !File {
        if (self.ops.find) |find_fn| {
            return try find_fn(self, name);
        }
        return Error.NotImplemented;
    }

    pub fn create(self: *Node, name: []const u8, typ: Node.Type, mode: Node.Mode) !File {
        if (self.ops.create) |create_fn| {
            return try create_fn(self, name, typ, mode);
        }
        return Error.NotImplemented;
    }

    pub fn link(self: *Node, name: []const u8, new_node: *Node) !File {
        if (self.ops.link) |link_fn| {
            return try link_fn(self, name, new_node);
        }
        return Error.NotImplemented;
    }

    pub fn unlink(self: *Node, name: []const u8) !void {
        if (self.ops.unlink) |unlink_fn| {
            return try unlink_fn(self, name);
        }
        return Error.NotImplemented;
    }

    pub fn readDir(self: *Node, offset: u64, files: []File) !usize {
        if (self.ops.readDir) |readDir_fn| {
            return try readDir_fn(self, offset, files);
        }
        return Error.NotImplemented;
    }
};

pub const File = struct {
    node: *Node,
    name_ptr: ?[]const u8,
    name_buf: [max_name_len]u8,
    name_len: usize,

    pub fn name(self: File) []const u8 {
        if (self.name_ptr) |name_str| {
            return name_str;
        }
        return self.name_buf[0..self.name_len];
    }
};

/// FileSystem defines a FileSystem
pub const FileSystem = struct {
    pub const Ops = struct {
        mount: fn (self: *FileSystem, device: ?*Node, args: ?[]const u8) anyerror!*Node,
        unmount: ?fn (self: *FileSystem) void = null,
    };

    name: []const u8,
    ops: FileSystem.Ops,
    cookie: Cookie = null,
    raw_allocator: *std.mem.Allocator = undefined,
    arena_allocator: std.heap.ArenaAllocator = undefined,
    allocator: *std.mem.Allocator = undefined,

    pub fn init(name: []const u8, ops: FileSystem.Ops) FileSystem {
        return .{ .name = name, .ops = ops };
    }

    /// Mount a disk (or nothing) using a FileSystem.
    /// `device` should already be opened before calling mount().
    pub fn mount(self: FileSystem, allocator: *std.mem.Allocator, device: ?*Node, args: ?[]const u8) anyerror!*Node {
        var fs = try allocator.create(FileSystem);
        errdefer allocator.destroy(fs);

        fs.* = .{ .name = self.name, .ops = self.ops, .raw_allocator = allocator, .arena_allocator = std.heap.ArenaAllocator.init(allocator), .allocator = undefined };
        fs.allocator = &fs.arena_allocator.allocator;
        errdefer fs.arena_allocator.deinit();

        return try fs.ops.mount(fs, device, args);
    }

    /// You should never call this yourself. unlink() the root node instead.
    pub fn deinit(self: *FileSystem) void {
        if (self.ops.unmount) |unmount_fn| {
            unmount_fn(self);
        }
        self.arena_allocator.deinit();
        self.raw_allocator.destroy(self);
    }
};

/// "/dev/null" type node
pub const NullNode = struct {
    const ops: Node.Ops = .{
        .read = NullNode.read,
        .write = NullNode.write,
    };

    pub fn init() Node {
        return Node.init(NullNode.ops, null, null, null);
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        return 0;
    }
    pub fn write(self: *Node, offset: u64, buffer: []const u8) !usize {
        return buffer.len;
    }
};

/// "/dev/zero" type node
pub const ZeroNode = struct {
    const ops: Node.Ops = .{
        .read = ZeroNode.read,
    };

    pub fn init() Node {
        return Node.init(ZeroNode.ops, null, null, null);
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        std.mem.set(u8, buffer, 0);
        return buffer.len;
    }
};
/// Read-only node that serves a fixed number of bytes
// TODO: better name?
pub const ReadOnlyNode = struct {
    const ops: Node.Ops = .{
        .read = ReadOnlyNode.read,
    };

    pub fn init(buffer: []const u8) Node {
        var new_node = Node.init(ReadOnlyNode.ops, null, Node.Stat{ .size = buffer.len, .blocks = buffer.len + @sizeOf(Node) }, null);
        new_node.alt_cookie = buffer;
        return new_node;
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        var my_data = self.alt_cookie.?;
        var trueOff = @truncate(usize, offset);
        var trueEnd = if (trueOff + buffer.len > self.stat.size) self.stat.size else trueOff + buffer.len;
        std.mem.copy(u8, buffer, my_data[trueOff..trueEnd]);
        return trueEnd - trueOff;
    }
};
