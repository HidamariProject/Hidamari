const std = @import("std");
const time = @import("../time.zig");
const platform = @import("../platform.zig");

const vfs = @import("../vfs.zig");
const util = @import("../util.zig");

const RefCount = util.RefCount;
const Node = vfs.Node;
const File = vfs.File;

const FileList = std.ArrayList(?File);

// These **MUST** be inlined.
inline fn myFsImpl(self: *Node) *FsImpl {
    return self.file_system.?.cookie.?.as(FsImpl);
}
inline fn myImpl(self: *Node) *NodeImpl {
    return self.cookie.?.as(NodeImpl);
}

const NodeImpl = struct {
    const ops: Node.Ops = .{
        .open = NodeImpl.open,
        .close = NodeImpl.close,

        .read = NodeImpl.read,
        .write = NodeImpl.write,

        .find = NodeImpl.find,
        .create = NodeImpl.create,
        .link = NodeImpl.link,
        .unlink = NodeImpl.unlink,
        .readDir = NodeImpl.readDir,

        .unlink_me = NodeImpl.unlink_me,
    };

    children: ?FileList = null,
    data: ?[]u8 = null,
    n_links: RefCount = .{},

    pub fn init(file_system: *vfs.FileSystem, typ: Node.Type, initial_stat: Node.Stat) !*Node {
        var fs_impl = file_system.cookie.?.as(FsImpl);

        var node_impl = try fs_impl.file_allocator.create(NodeImpl);
        errdefer fs_impl.file_allocator.destroy(node_impl);

        if (typ == .directory) {
            node_impl.children = FileList.init(fs_impl.file_allocator);
        } else if (typ == .file) {
            node_impl.data = try fs_impl.file_allocator.alloc(u8, 0);
        } else {
            unreachable;
        }

        var node = try fs_impl.file_allocator.create(Node);
        errdefer fs_impl.file_allocator.destroy(node);

        var true_initial_stat = initial_stat;
        true_initial_stat.inode = fs_impl.inode_count;
        true_initial_stat.type = typ;
        true_initial_stat.size = @sizeOf(NodeImpl) + @sizeOf(Node);

        fs_impl.inode_count += 1;
        node.* = Node.init(NodeImpl.ops, util.asCookie(node_impl), true_initial_stat, file_system);
        return node;
    }

    // This function destroys a properly allocated and initialized Node object. You should almost never need to call this directly.

    pub fn deinit(self: *Node) void {
        var node_impl = myImpl(self);
        var fs_impl = myFsImpl(self);

        if (node_impl.children != null) {
            node_impl.children.?.deinit();
        }
        if (node_impl.data != null) {
            fs_impl.file_allocator.free(node_impl.data.?);
        }

        fs_impl.file_allocator.destroy(node_impl);
        fs_impl.file_allocator.destroy(self);
    }

    // Returns the true reference count (number of opens + number of hard links). We can't deinit until this reaches 0, or bad things will happen.
    fn trueRefCount(self: *Node) usize {
        return self.opens.refs + myImpl(self).n_links.refs;
    }

    pub fn open(self: *Node) !void {
        // I don't think this can fail?
    }

    pub fn close(self: *Node) !void {
        if (NodeImpl.trueRefCount(self) == 0) NodeImpl.deinit(self);
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        var node_impl = myImpl(self);

        if (node_impl.data) |data| {
            var trueEnd = @truncate(usize, if (offset + buffer.len > data.len) data.len else offset + buffer.len);
            var trueOff = @truncate(usize, offset);

            std.mem.copy(u8, buffer, data[trueOff..trueEnd]);

            self.stat.access_time = time.getClockNano(.real);
            return trueEnd - trueOff;
        }
        return vfs.Error.NotFile;
    }

    pub fn write(self: *Node, offset: u64, buffer: []const u8) !usize {
        var node_impl = myImpl(self);
        var fs_impl = myFsImpl(self);

        if (node_impl.data) |data| {
            var trueData = data;
            var trueEnd = @truncate(usize, offset + buffer.len);
            var trueOff = @truncate(usize, offset);

            if (trueEnd > data.len)
                trueData = try fs_impl.file_allocator.realloc(trueData, trueEnd);
            std.mem.copy(u8, trueData[trueOff..trueEnd], buffer);

            var now = time.getClockNano(.real);

            self.stat.access_time = now;
            self.stat.modify_time = now;
            self.stat.size = trueData.len;
            self.stat.blocks = trueData.len + @sizeOf(NodeImpl) + @sizeOf(Node);
            node_impl.data = trueData;
            return buffer.len;
        }
        return vfs.Error.NotFile;
    }

    pub fn find(self: *Node, name: []const u8) !File {
        var node_impl = myImpl(self);
        if (node_impl.children) |children| {
            for (children.items) |child| {
                if (child == null) continue;
                if (std.mem.eql(u8, child.?.name(), name)) {
                    try child.?.open();
                    return child.?;
                }
            }
            return vfs.Error.NoSuchFile;
        }
        return vfs.Error.NotDirectory;
    }

    pub fn create(self: *Node, name: []const u8, typ: Node.Type, mode: Node.Mode) !File {
        var fs_impl = myFsImpl(self);
        var node_impl = myImpl(self);
        if (node_impl.children) |children| {
            for (children.items) |child| {
                if (std.mem.eql(u8, child.?.name(), name)) return vfs.Error.FileExists;
            }

            var now = time.getClockNano(.real);

            var new_node = try NodeImpl.init(self.file_system.?, typ, .{ .mode = mode, .links = 1, .access_time = now, .create_time = now, .modify_time = now });
            errdefer NodeImpl.deinit(new_node);

            var new_file: File = undefined;
            std.mem.copy(u8, new_file.name_buf[0..], name);

            new_file.name_len = name.len;
            new_file.node = new_node;
            try node_impl.children.?.append(new_file);
            myImpl(new_node).n_links.ref();

            try new_node.open();
            return new_file;
        }
        return vfs.Error.NotDirectory;
    }

    pub fn link(self: *Node, name: []const u8, new_node: *Node) !File {
        var node_impl = myImpl(self);
        if (node_impl.children != null) {
            if (NodeImpl.find(self, name) catch null != null) return vfs.Error.FileExists;
            var new_file: File = undefined;
            std.mem.copy(u8, new_file.name_buf[0..], name);

            new_file.name_len = name.len;
            new_file.node = new_node;
            if (new_node.file_system == self.file_system) {
                myImpl(new_node).n_links.ref();
            } else if (new_node.stat.flags.mount_point) {
                try new_node.open();
            }

            try node_impl.children.?.append(new_file);
            return new_file;
        }
        return vfs.Error.NotDirectory;
    }

    pub fn unlink(self: *Node, name: []const u8) !void {
        var node_impl = myImpl(self);
        if (node_impl.children) |children| {
            for (children.items) |child, i| {
                if (std.mem.eql(u8, child.?.name(), name)) {
                    if (child.?.node.ops.unlink_me) |unlink_me_fn| {
                        try unlink_me_fn(child.?.node);
                    }
                    _ = node_impl.children.?.swapRemove(i);
                    return;
                }
            }
            return vfs.Error.NoSuchFile;
        }
        return vfs.Error.NotDirectory;
    }

    pub fn readDir(self: *Node, offset: u64, files: []vfs.File) !usize {
        var node_impl = myImpl(self);
        if (node_impl.children) |children| {
            var total: usize = 0;
            for (children.items) |child, i| {
                if (i < offset) continue;
                if (total == files.len) break;
                files[total] = child.?;
                total += 1;
            }
            return total;
        }
        return vfs.Error.NotDirectory;
    }

    pub fn unlink_me(self: *Node) !void {
        var node_impl = myImpl(self);

        if (node_impl.children) |children| {
            if (children.items.len != 0) return vfs.Error.NotEmpty;
        }

        node_impl.n_links.unref();

        var fs = self.file_system.?;

        if (NodeImpl.trueRefCount(self) == 0) {
            NodeImpl.deinit(self);
        }
    }
};

const FsImpl = struct {
    const ops: vfs.FileSystem.Ops = .{
        .mount = FsImpl.mount,
    };

    file_allocator: *std.mem.Allocator,
    maybe_fba: std.heap.FixedBufferAllocator,
    maybe_fba_data: []u8,
    inode_count: u64,

    pub fn mount(self: *vfs.FileSystem, unused: ?*Node, args: ?[]const u8) !*Node {
        var fs_impl = try self.allocator.create(FsImpl);
        errdefer self.allocator.destroy(fs_impl);

        fs_impl.inode_count = 1;

        fs_impl.maybe_fba_data = try self.allocator.alloc(u8, 4 * 1024 * 1024);
        errdefer self.allocator.free(fs_impl.maybe_fba_data);

        fs_impl.maybe_fba = std.heap.FixedBufferAllocator.init(fs_impl.maybe_fba_data);
        fs_impl.file_allocator = &fs_impl.maybe_fba.allocator;

        self.cookie = util.asCookie(fs_impl);

        var now = time.getClockNano(.real);

        var root_node = try NodeImpl.init(self, .directory, .{ .flags = .{ .mount_point = true }, .create_time = now, .access_time = now, .modify_time = now });
        return root_node;
    }
};

pub const Fs = vfs.FileSystem.init("tmpfs", FsImpl.ops);
