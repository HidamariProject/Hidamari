const std = @import("std");
const util = @import("util.zig");

const Cookie = util.Cookie;

const name_max = 256;

pub const Error = error{
    OutOfMemory,
    NotSupported,
    NotDirectory,
    NotFile,
    NodeFound,
    NoNodeFound,
};

pub const OpenFlags = struct {
    read: bool = true,
    write: bool = false,
    create: bool = false,
    truncate: bool = false,
    directory: bool = false,
};

pub const SeekWhence = enum {
    Absolute,
    Current,
    End,
};

pub const FileType = enum {
    File,
    Directory,
    BlockDevice,
    CharacterDevice,
    Fifo,
    Socket,
    Null,
};

pub const FileMode = packed struct {
    const RWX = packed struct {
        execute: bool = false,
        write: bool = false,
        read: bool = false,
    };

    everyone: RWX,
    group: RWX,
    user: RWX,
    _padding: u7 = 0,

    pub fn init(mode: u16) FileMode {
        var ret: FileMode = undefined;
        @ptrCast([*]align(@alignOf(FileMode)) u16, &ret) = mode;
        return ret;
    }

    pub fn toInt(self: FileMode) u16 {
        if (@sizeOf(FileMode) != @sizeOf(u16)) @compileError("Whoops!");
        return @ptrCast([*]align(@alignOf(FileMode)) const u16, &self)[0];
    }

    pub fn toString(self: FileMode, out: []u8) ![]const u8 {
        return try std.fmt.bufPrint(out, "{o}", .{self.toInt()});
    }

    pub const can_r = FileMode.RWX{ .read = true };
    pub const can_rw = FileMode.RWX{ .read = true, .write = true };
    pub const can_rwx = FileMode.RWX{ .read = true, .write = true, .execute = true };

    pub const world_readable = FileMode{ .user = FileMode.can_rw, .group = FileMode.can_r, .everyone = FileMode.can_r };
    pub const world_writable = FileMode{ .user = FileMode.can_rw, .group = FileMode.can_rw, .everyone = FileMode.can_rw };
    pub const world_exec_writable = FileMode{ .user = FileMode.can_rwx, .group = FileMode.can_rwx, .everyone = FileMode.can_rwx };
};

pub const Stat = struct {
    type: FileType,

    mode: FileMode,
    uid: u32,
    gid: u32,

    size: u64,
    size_on_disk: u64,

    access_time: i64,
    mod_time: i64,
    creation_time: i64,

    n_links: u64,
    inode: u64,
};

pub const DirEntry = struct {
    inode: u64,
    name: []const u8,
    name_buf: [name_max]u8 = undefined,
};

pub const NodeOps = struct {
    init: ?fn (self: *Node) anyerror!void = null,
    deinit: ?fn (self: Node) anyerror!void = null,

    open: ?fn (self: Node, name: []const u8, flags: OpenFlags, mode: FileMode) anyerror!Node = null,
    readDir: ?fn (self: Node, offset: u64, buffer: []DirEntry) anyerror!usize = null,
    close: ?fn (self: Node) anyerror!void = null,

    read: ?fn (self: Node, buffer: []u8) anyerror!usize = null,
    write: ?fn (self: Node, buffer: []const u8) anyerror!usize = null,
    seek: ?fn (self: Node, offset: i64, whence: SeekWhence) anyerror!u64 = null,

    stat: ?fn (self: Node) anyerror!Stat = null,
    chmod: ?fn (self: Node, mode: FileMode) anyerror!void = null,
    chown: ?fn (self: Node, uid: u32, gid: u32) anyerror!void = null,
    unlink: ?fn (self: Node, name: []const u8) anyerror!void = null,
};

pub const Node = struct {
    name: []const u8 = "<null>",
    cookie: Cookie = null,
    ops: *const NodeOps,
    file_system: ?*FileSystem = null,

    pub fn init(self: Node, file_system: ?*FileSystem) anyerror!Node {
        var newNode = Node{ .ops = self.ops, .file_system = file_system };
        if (self.ops.init != null) {
            try self.ops.init.?(&newNode);
        }
        return newNode;
    }

    pub fn deinit(self: Node) anyerror!void {
        // TODO destroy any mounts
        if (self.ops.deinit) |deinit_fn| { try deinit_fn(self); }
    }

    pub fn get_inode(self: Node) anyerror!u64 {
        if (self.ops.stat != null) return (try self.ops.stat.?(self)).inode;
        return Error.NotSupported;
    }

    pub fn open(self: Node, name: []const u8, flags: OpenFlags, mode: FileMode) anyerror!Node {
        if (self.get_true_node().ops.open == null) return Error.NotSupported;
        return self.get_true_node().ops.open.?(self, name, flags, mode);
    }

    pub fn readDir(self: Node, offset: u64, buffer: []DirEntry) anyerror!usize {
        if (self.get_true_node().ops.readDir == null) return Error.NotSupported;
        return self.get_true_node().ops.readDir.?(self, offset, buffer);
    }

    pub fn close(self: Node) anyerror!void {
        if (self.get_true_node().ops.close != null) try self.get_true_node().ops.close.?(self);
        try self.deinit();
    }

    pub fn read(self: Node, buffer: []u8) anyerror!usize {
        if (self.get_true_node().ops.read == null) return Error.NotSupported;
        return self.get_true_node().ops.read.?(self, buffer);
    }

    pub fn write(self: Node, buffer: []const u8) anyerror!usize {
        if (self.get_true_node().ops.write == null) return Error.NotSupported;
        return self.get_true_node().ops.write.?(self, buffer);
    }

    pub fn seek(self: Node, offset: i64, whence: SeekWhence) anyerror!u64 {
        if (self.get_true_node().ops.seek == null) return Error.NotSupported;
        return self.get_true_node().ops.seek.?(self, offset, whence);
    }

    pub fn stat(self: Node) anyerror!Stat {
        if (self.get_true_node().ops.stat == null) return Error.NotSupported;
        return self.get_true_node().ops.stat.?(self.get_true_node());
    }

    pub fn unlink(self: Node, name: []const u8) anyerror!void {
        if (self.get_true_node().ops.unlink) |unlink_fn| { return unlink_fn(self.get_true_node(), name); }
        return Error.NotSupported;
    }

    // Mounting

    pub fn mount(self: Node, newNode: Node) anyerror!void {
        var stats = try self.stat();
        var ptr = try self.file_system.?.allocator.create(Node);
        ptr.* = newNode;
        try self.file_system.?.mounts.putNoClobber(stats.inode, util.asCookie(ptr));
    }

    pub fn get_true_node(self: Node) *const Node {
        if (self.file_system == null) return &self;
        var inode = self.get_inode() catch return &self;
        if (self.file_system.?.mounts.get(inode)) |true_node| { return true_node.as(Node); }
        return &self;
    }
};

pub const FileSystemOps = struct {
    init: fn (self: *FileSystem, allocator: *std.mem.Allocator, arg: ?[]const u8) anyerror!Node,
};

// Work around "Node depends on itself"
const InodeMap = std.AutoHashMap(u64, *util.RawCookie);

pub const FileSystem = struct {
    name: []const u8,
    cookie: Cookie = null,
    allocator: *std.mem.Allocator = undefined,
    ops: *const FileSystemOps,

    mounts: InodeMap = undefined, // inode -> Node

    pub fn init(self: *const FileSystem, allocator: *std.mem.Allocator, arg: ?[]const u8) anyerror!Node {
        var newSelf = try allocator.create(FileSystem);
        errdefer {
            allocator.destroy(newSelf);
        }
        newSelf.ops = self.ops;
        newSelf.name = self.name;
        newSelf.allocator = allocator;
        newSelf.mounts = InodeMap.init(allocator);
        errdefer { newSelf.mounts.deinit(); }

        return try newSelf.ops.init(newSelf, allocator, arg);
    }
};

const NullOps = NodeOps{
    .read = null_read,
    .write = null_write,
    .close = null_close,
};

fn null_read(self: Node, buffer: []u8) anyerror!usize {
    return 0;
}

fn null_write(self: Node, buffer: []const u8) anyerror!usize {
    return buffer.len;
}

fn null_close(self: Node) anyerror!void {
    return;
}

pub var null_node = Node{ .ops = &NullOps };
