const std = @import("std");
const platform = @import("../platform.zig");
const vfs = @import("../vfs.zig");
const util = @import("../util.zig");

const TmpFsFile = struct {
    type: vfs.FileType,
    n_links: u64 = 0,
    inode: u64 = 0,

    mode: vfs.FileMode = vfs.FileMode.world_exec_writable,
    uid: u32 = 0,
    gid: u32 = 0,

    access_time: i64 = 0,
    mod_time: i64 = 0,
    creation_time: i64 = 0,

    data: ?[]u8,
    children: ?[]?vfs.Node,

    _in_destruction: bool = false,
    pub fn set_times_to_now(self: *TmpFsFile) void {
        var now = platform.getTimeNano();
        self.access_time = now;
        self.mod_time = now;
        self.creation_time = now;
    }

    pub fn add_child(self: *TmpFsFile, owner: *const vfs.FileSystem, new_child: vfs.Node) anyerror!void {
        var fs_cookie = owner.cookie.?.as(TmpFsCookie);
        for (self.children.?) |child, i| {
            if (child == null) {
                self.children.?[i] = new_child;
                new_child.cookie.?.as(TmpFsNodeCookie).file.ref();
                return;
            }
        }
        self.children = try fs_cookie.file_allocator.realloc(self.children.?, self.children.?.len + 1);
        self.children.?[self.children.?.len - 1] = new_child;
        new_child.cookie.?.as(TmpFsNodeCookie).file.ref();
    }

    pub fn ref(self: *TmpFsFile) void {
        self.n_links += 1;
    }
    pub fn unref(self: *TmpFsFile, owner: *const vfs.FileSystem) void {
        if (self._in_destruction) return; // This function is *NOT* re-entrant

        if (self.n_links != 0) self.n_links -= 1;
        if (self.n_links > 0) return;

        self._in_destruction = true;
        var fs_cookie = owner.cookie.?.as(TmpFsCookie);
        if (self.data != null) fs_cookie.file_allocator.free(self.data.?);
        if (self.children != null) {
            for (self.children.?) |child| {
                if (child != null) child.?.cookie.?.as(TmpFsNodeCookie).file.unref(owner);
            }
            fs_cookie.file_allocator.free(self.children.?);
        }
        fs_cookie.file_allocator.destroy(self);
    }
};

const TmpFsNodeCookie = struct {
    file: *TmpFsFile,
    seek_pos: usize = 0,
    name_buf: [256]u8 = undefined,
};

fn node_init(self: *vfs.Node) anyerror!void {
    // TODO: maybe stuff goes here?
}

fn node_deinit(self: vfs.Node) anyerror!void {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    var fs_cookie = self.file_system.?.cookie.?.as(TmpFsCookie);

    cookie.file.unref(self.file_system.?);
    fs_cookie.file_allocator.destroy(cookie);
}

fn node_open(self: vfs.Node, name: []const u8, flags: vfs.OpenFlags, mode: vfs.FileMode) anyerror!vfs.Node {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    var fs_cookie = self.file_system.?.cookie.?.as(TmpFsCookie);
    if (cookie.file.type != .Directory) return vfs.Error.NotDirectory;

    for (cookie.file.children.?) |child| {
        if (child != null and std.mem.eql(u8, child.?.name, name)) { // TODO: honor flags.directory
            child.?.cookie.?.as(TmpFsNodeCookie).file.ref();
            // TODO: honor open flags
            return child.?; // TODO: use Node.dup()
        }
    }
    if (!flags.create) return vfs.Error.NoNodeFound;

    var new_node = try TmpFsNode.init(self.file_system);
    var new_node_cookie = try fs_cookie.file_allocator.create(TmpFsNodeCookie);
    new_node_cookie.seek_pos = 0;
    std.mem.copy(u8, new_node_cookie.name_buf[0..], name);

    errdefer {
        fs_cookie.file_allocator.destroy(new_node_cookie);
    }
    var new_node_file = try fs_cookie.file_allocator.create(TmpFsFile);
    new_node_file.n_links = 0;

    errdefer {
        new_node_file.unref(self.file_system.?);
    }
    if (flags.directory) {
    new_node_file.children = try fs_cookie.file_allocator.alloc(?vfs.Node, 0);
    new_node_file.type = .Directory;
    } else {
    new_node_file.data = try fs_cookie.file_allocator.alloc(u8, 0);
    new_node_file.type = .File; 
    }
    new_node_file.inode = fs_cookie.ino_counter;
    new_node_file.mode = mode;
    new_node_file.uid = 0; // TODO support other owners
    new_node_file.gid = 0;

    new_node_file.set_times_to_now();

    new_node_cookie.file = new_node_file;
    new_node.cookie = util.asCookie(new_node_cookie);
    new_node.name = new_node_cookie.name_buf[0..name.len];
    try cookie.file.add_child(self.file_system.?, new_node);

    new_node_file.ref(); // open it
    fs_cookie.ino_counter += 1;
    return new_node;
}

fn node_readDir(self: vfs.Node, offset: u64, buffer: []vfs.DirEntry) anyerror!usize {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    cookie.file.access_time = platform.getTimeNano();
    if (cookie.file.type != .Directory) return vfs.Error.NotFile;
    var offset_usz = @truncate(usize, offset);
    if (offset_usz >= cookie.file.children.?.len) return 0;
    var i: usize = 0;
    for (cookie.file.children.?[offset_usz..]) |child| {
        if (i == buffer.len) break;
        if (child == null) continue;
        var child_inode = try child.?.get_true_node().get_inode();
        buffer[i] = vfs.DirEntry{ .inode = child_inode, .name = child.?.name };
        i += 1;
    }
    return i;
}

fn node_close(self: vfs.Node) anyerror!void {
    self.cookie.?.as(TmpFsNodeCookie).file.unref(self.file_system.?);
}

fn node_write(self: vfs.Node, buffer: []const u8) anyerror!usize {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    var fs_cookie = self.file_system.?.cookie.?.as(TmpFsCookie);
    cookie.file.access_time = platform.getTimeNano();
    if (cookie.file.type != .File) return vfs.Error.NotFile;

    var newSize = cookie.seek_pos + buffer.len;
    if (newSize > cookie.file.data.?.len) // TODO partial writes on OOM
        cookie.file.data = try fs_cookie.file_allocator.realloc(cookie.file.data.?, newSize);
    std.mem.copy(u8, cookie.file.data.?[cookie.seek_pos..], buffer);
    cookie.seek_pos += buffer.len;
    cookie.file.mod_time = cookie.file.access_time;
    return buffer.len;
}

fn node_read(self: vfs.Node, buffer: []u8) anyerror!usize {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    cookie.file.access_time = platform.getTimeNano();
    if (cookie.file.type != .File) return vfs.Error.NotFile;

    var end = if (buffer.len + cookie.seek_pos > cookie.file.data.?.len) cookie.file.data.?.len else buffer.len + cookie.seek_pos;
    std.mem.copy(u8, buffer, cookie.file.data.?[cookie.seek_pos..end]);

    var n_read = end - cookie.seek_pos;
    cookie.seek_pos = end;
    return n_read;
}

fn node_seek(self: vfs.Node, off: i64, whence: vfs.SeekWhence) anyerror!u64 {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    if (cookie.file.type != .File) return vfs.Error.NotFile;

    var fsize = cookie.file.data.?.len;
    var off_isz = @truncate(isize, off);
    var new_seek_pos: isize = switch (whence) {
        .Absolute => off_isz,
        .Current => @intCast(isize, cookie.seek_pos) + off_isz,
        .End => @intCast(isize, fsize) + off_isz,
    };
    if (new_seek_pos > fsize) {
        cookie.seek_pos = fsize;
    } else if (new_seek_pos < 0) { // !?
        cookie.seek_pos = 0;
    } else {
        cookie.seek_pos = @intCast(usize, new_seek_pos);
    }
    return cookie.seek_pos;
}

fn node_stat(self: vfs.Node) anyerror!vfs.Stat {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    cookie.file.access_time = platform.getTimeNano();
    var size = if (cookie.file.data != null) cookie.file.data.?.len else cookie.file.children.?.len;
    return vfs.Stat{
        .size = size,
        .size_on_disk = @sizeOf(TmpFsFile) + size,
        .inode = cookie.file.inode,
        .n_links = cookie.file.n_links,
        .type = cookie.file.type,
        .mode = cookie.file.mode,
        .uid = cookie.file.uid,
        .gid = cookie.file.gid,
        .mod_time = cookie.file.mod_time,
        .access_time = cookie.file.access_time,
        .creation_time = cookie.file.creation_time,
    };
}

fn node_chmod(self: vfs.Node, mode: vfs.FileMode) anyerror!void {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    cookie.file.mode = mode;
}

fn node_chown(self: vfs.Node, uid: u32, gid: u32) anyerror!void {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    cookie.file.uid = uid;
    cookie.file.gid = gid;
}

fn node_unlink(self: vfs.Node, name: []const u8) anyerror!void {
    var cookie = self.cookie.?.as(TmpFsNodeCookie);
    var fs_cookie = self.file_system.?.cookie.?.as(TmpFsCookie);
    if (cookie.file.type != .Directory) return vfs.Error.NotDirectory;

    for (cookie.file.children.?) |child, i| {
        if (child != null and std.mem.eql(u8, child.?.name, name)) { // TODO: honor flags.directory
            try child.?.deinit();
            // TODO: care if it's a file or not
            cookie.file.children.?[i] = null;
            return;
        }
    }    
    return vfs.Error.NoNodeFound;
}

const TmpFsNodeOps = vfs.NodeOps{
    .init = node_init,
    .deinit = node_deinit,

    .open = node_open,
    .close = node_close,
    .readDir = node_readDir,

    .read = node_read,
    .write = node_write,
    .seek = node_seek,

    .stat = node_stat,
    .chmod = node_chmod,
    .chown = node_chown,
    .unlink = node_unlink,
};

const TmpFsNode = vfs.Node{ .ops = &TmpFsNodeOps };

const TmpFsCookie = struct {
    file_buffer: ?[]u8 = null,
    file_allocator: *std.mem.Allocator = undefined,
    file_fixed_buffer_allocator: std.heap.FixedBufferAllocator = undefined,
    file_arena_allocator: std.heap.ArenaAllocator = undefined,
    ino_counter: u64 = 1,
};

fn fs_init(self: *vfs.FileSystem, allocator: *std.mem.Allocator, args: ?[]const u8) anyerror!vfs.Node {
    var fs_cookie = try allocator.create(TmpFsCookie);
    errdefer {
        allocator.destroy(fs_cookie);
    }

    fs_cookie.ino_counter = 2; // 1 is taken by root_node
    fs_cookie.file_buffer = try allocator.alloc(u8, 4 * 1024 * 1024); // TODO: allow custom amount
    errdefer {
        allocator.free(fs_cookie.file_buffer.?);
    }
    fs_cookie.file_fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(fs_cookie.file_buffer.?);
    fs_cookie.file_allocator = &fs_cookie.file_fixed_buffer_allocator.allocator;

    self.cookie = util.asCookie(fs_cookie);

    var root_node = try TmpFsNode.init(self);

    var root_node_cookie = try fs_cookie.file_allocator.create(TmpFsNodeCookie);
    errdefer {
        fs_cookie.file_allocator.destroy(root_node_cookie);
    }
    var root_node_file = try fs_cookie.file_allocator.create(TmpFsFile);
    root_node_file.n_links = 0;

    errdefer {
        root_node_file.unref(self);
    }
    root_node_file.ref();

    root_node_file.type = .Directory;
    root_node_file.children = try fs_cookie.file_allocator.alloc(?vfs.Node, 0);
    root_node_file.inode = 1;

    root_node_file.mode = vfs.FileMode.world_exec_writable;
    root_node_file.uid = 0;
    root_node_file.gid = 0;

    root_node_file.set_times_to_now();

    root_node_cookie.file = root_node_file;
    root_node.cookie = util.asCookie(root_node_cookie);
    return root_node;
}

const TmpFsOps = vfs.FileSystemOps{
    .init = fs_init,
};

pub const TmpFs = vfs.FileSystem{
    .name = "tmpfs",
    .ops = &TmpFsOps,
};
