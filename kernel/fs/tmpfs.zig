const std = @import("std");

const vfs = @import("../vfs.zig");
const util = @import("../util.zig");

const Node = vfs.Node;
const File = vfs.File;

const FileList = std.ArrayList(?File);

// These **MUST** be inlined.
inline fn myFsImpl(self: *Node) *FsImpl { return self.file_system.?.cookie.?.as(FsImpl); }
inline fn myImpl(self: *Node) *NodeImpl { return self.cookie.?.as(NodeImpl); }

const NodeImpl = struct {
    const ops: Node.Ops = .{
        .open = NodeImpl.open,
        .close = NodeImpl.close,
    };

    children: ?FileList = null,
    data: ?[]u8 = null,

    pub fn init(file_system: *vfs.FileSystem, typ: Node.Type, initial_stat: vfs.Stat) !*Node {
        var fs_impl = file_system.cookie.?.as(file_system);

        var node_impl = try fs_impl.file_allocator.create(NodeImpl);
        errdefer fs_impl.file_allocator.destroy(node_impl);

        if (typ == .Directory) {
            node_impl.children = FileList.init(fs_impl.file_allocator);
        } else if (typ == .File) {
            node_impl.data = try fs_impl.file_allocator.alloc(u8, 0);
        } else { unreachable; }

        var node = try fs_impl.file_allocator.create(Node);
        errdefer fs_impl.file_allocator.destroy(node);

        var true_initial_stat = initial_stat;
        true_initial_stat.inode = fs_impl.inode_count;

        fs_impl.inode_count += 1;
        node.* = Node.init(NodeImpl.ops, util.asCookie(node_impl), true_initial_stat, file_system);
        return node;
    }

    pub fn open(self: *Node) !void {
        // I don't think this can fail?
    }

    pub fn close(self: *Node) !void {
        // I don't think this can fail?
    }

    pub fn find(self: *Node, name: []const u8) !File {
        var node_impl = myImpl(self);
        if (node_impl.children) |children| {
            for (children) |child| {
                if (child.? == null) continue;
                if (std.mem.eql(u8, child.?.name, name)) return child.?;
            }
            return vfs.Error.NoSuchFile;
        }
        return vfs.Error.NotDirectory;
    }
};

const FsImpl = struct {
    const ops: Node.Ops = .{
        .mount = FsImpl.mount,
    };

    file_allocator: *std.mem.Allocator,
    maybe_fba: std.heap.FixedBufferAllocator,
    maybe_fba_data: []u8,
    inode_count: u64,

    pub fn mount(self: *FileSystem, args: []const u8) !*Node {
        var fs_impl = try self.allocator.create(FsImpl);
        errdefer self.allocator.destroy(fs_impl);

        fs_impl.inode_count = 1;

        fs_impl.maybe_fba_data = try self.allocator.alloc(u8, 4 * 1024 * 1024);
        errdefer self.allocator.free(fs_impl.maybe_fba_data);

        fs_impl.maybe_fba = std.heap.FixedBufferAllocator(fs_impl.maybe_fba_data);
        fs_impl.file_allocator = &fs_impl.maybe_fba.allocator;

        var root_node_cookie = try self.allocator.create(NodeImpl);
        errdefer self.allocator.destroy(root_node_cookie);

        var root_node = try self.allocator.create(Node);
        errdefer self.allocator.destroy(root_node);
        root_node.* = Node.init(self, util.asCookie(root_node_cookie), .{ .type = .Directory, .flags = .{ .mount_point = true }}, self);

        return root_node;
    }
};

pub const Fs = vfs.FileSystem.init("tmpfs", FsImpl.ops);
