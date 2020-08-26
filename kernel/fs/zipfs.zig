const std = @import("std");
const platform = @import("../platform.zig");
const time = std.time;

const vfs = @import("../vfs.zig");
const util = @import("../util.zig");

const RefCount = util.RefCount;

const File = vfs.File;
const Node = vfs.Node;

const c = @cImport({
    @cInclude("miniz/miniz.h");
});
/// Support for mounting .zip files as a filesystem. DIRECTORY ENTRIES ARE REQUIRED in the .zip file.

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
        .find = NodeImpl.find,
        .readDir = NodeImpl.readDir,
        .unlink_me = NodeImpl.unlink_me,
    };

    miniz_stat: c.mz_zip_archive_file_stat = undefined,
    data: ?[]u8 = null,

    fn minizToVfsStat(in: c.mz_zip_archive_file_stat) Node.Stat {
        return .{
            .inode = in.m_file_index + 2,
            .blocks = in.m_comp_size,
            .size = in.m_uncomp_size,
            .type = if (in.m_is_directory != 0) .Directory else .File,
            .modify_time = @truncate(i64, in.m_time) * time.ns_per_s,
            .access_time = @truncate(i64, in.m_time) * time.ns_per_s,
            .create_time = @truncate(i64, in.m_time) * time.ns_per_s,
            .mode = Node.Mode.all,
        };
    }

    fn lazyExtract(self: *Node) !void {
        var node_impl = myImpl(self);
        var fs_impl = myFsImpl(self);

        if (node_impl.miniz_stat.m_is_directory != 0) return vfs.Error.NotFile;
        if (node_impl.data != null) return;

        node_impl.data = try self.file_system.?.allocator.alloc(u8, node_impl.miniz_stat.m_uncomp_size);
        var mz_ok = c.mz_zip_reader_extract_to_mem(&fs_impl.archive, node_impl.miniz_stat.m_file_index, node_impl.data.?.ptr, node_impl.data.?.len, 0);
        if (mz_ok == 0) return vfs.Error.ReadFailed;
    }

    pub fn init(file_system: *vfs.FileSystem, index: u32, preinit_stat: ?c.mz_zip_archive_file_stat) !*Node {
        var fs_impl = file_system.cookie.?.as(FsImpl);
        if (fs_impl.opened.get(index)) |existing_node| {
            return existing_node;
        }
        var node_impl = try file_system.allocator.create(NodeImpl);
        errdefer file_system.allocator.destroy(node_impl);
        node_impl.* = .{};

        if (preinit_stat) |preinit_stat_inner| {
            node_impl.miniz_stat = preinit_stat_inner;
        } else {
            var mz_ok = c.mz_zip_reader_file_stat(&fs_impl.archive, @truncate(c.mz_uint, index), &node_impl.miniz_stat);
            if (mz_ok == 0) return vfs.Error.ReadFailed;
        }
        var initial_stat = NodeImpl.minizToVfsStat(node_impl.miniz_stat);

        var node = try file_system.allocator.create(Node);
        errdefer file_system.allocator.destroy(node);
        node.* = Node.init(NodeImpl.ops, util.asCookie(node_impl), initial_stat, file_system);

        try fs_impl.opened.putNoClobber(node_impl.miniz_stat.m_file_index, node);
        return node;
    }

    pub fn open(self: *Node) !void {
        // Do nothing, as there is nothing to do.
    }

    pub fn close(self: *Node) !void {
        var node_impl = myImpl(self);

        if (self.opens.refs == 0) {
            if (node_impl.data != null) self.file_system.?.allocator.free(node_impl.data.?);
            if (!self.stat.flags.mount_point) _ = myFsImpl(self).opened.remove(node_impl.miniz_stat.m_file_index);
            self.file_system.?.allocator.destroy(node_impl);
            self.file_system.?.allocator.destroy(self);
        }
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        if (self.stat.type == .Directory) return vfs.Error.NotFile;

        try lazyExtract(self);

        var my_data = myImpl(self).data.?;
        var trueOff = @truncate(usize, offset);
        var trueEnd = if (trueOff + buffer.len > self.stat.size) self.stat.size else trueOff + buffer.len;
        std.mem.copy(u8, buffer, my_data[trueOff..trueEnd]);
        return trueEnd - trueOff;
    }

    pub fn find(self: *Node, path: []const u8) !File {
        var node_impl = myImpl(self);
        var fs_impl = myFsImpl(self);

        if (self.stat.type != .Directory) return vfs.Error.NotDirectory;

        var index: u32 = undefined;

        if (!self.stat.flags.mount_point) {
            var my_path_raw: [1024]u8 = undefined;
            var my_path_len = c.mz_zip_reader_get_filename(&fs_impl.archive, node_impl.miniz_stat.m_file_index, &my_path_raw, 1024);
            if (my_path_len == 0) return vfs.Error.ReadFailed;
            var my_path = my_path_raw[0..my_path_len];

            var full_path_raw: [1024]u8 = undefined;
            var full_path = try std.fmt.bufPrint(full_path_raw[0..], "{}/{}", .{ my_path, path });
            full_path_raw[full_path.len] = 0;

            var mz_ok = c.mz_zip_reader_locate_file_v2(&fs_impl.archive, full_path.ptr, null, 0, &index);
            if (mz_ok == 0) return vfs.Error.NoSuchFile;
        } else {
            var full_path_raw: [1024]u8 = undefined;
            var full_path: []u8 = full_path_raw[0..path.len];
            std.mem.copy(u8, full_path, path);
            full_path_raw[full_path.len] = 0;

            var mz_ok = c.mz_zip_reader_locate_file_v2(&fs_impl.archive, full_path.ptr, null, 0, &index);
            if (mz_ok == 0) return vfs.Error.NoSuchFile;
        }

        var node = try NodeImpl.init(self.file_system.?, index, null);

        try node.open();

        var file: File = undefined;
        std.mem.copy(u8, file.name_buf[0..], path);
        file.name_len = path.len;
        file.node = node;

        return file;
    }

    pub fn readDir(self: *Node, offset: u64, files: []File) !usize {
        if (self.stat.type != .Directory) return vfs.Error.NotDirectory;
        var node_impl = myImpl(self);
        var fs_impl = myFsImpl(self);

        var my_path_raw: [1024]u8 = undefined;
        var my_path: []const u8 = "";

        if (!self.stat.flags.mount_point) {
            var my_path_len = c.mz_zip_reader_get_filename(&fs_impl.archive, node_impl.miniz_stat.m_file_index, &my_path_raw, 1024);
            if (my_path_len == 0) return vfs.Error.ReadFailed;
            my_path_raw[my_path_len] = '/';
            my_path = my_path_raw[0 .. my_path_len + 1];
        }

        var true_index: usize = 0;
        var total_index = @truncate(usize, offset);
        while (total_index < fs_impl.archive.m_total_files and true_index < files.len) {
            var file_info: c.mz_zip_archive_file_stat = undefined;
            var mz_ok = c.mz_zip_reader_file_stat(&fs_impl.archive, @truncate(c.mz_uint, total_index), &file_info);
            if (mz_ok == 0) return vfs.Error.ReadFailed;

            var path_slice: []u8 = std.mem.spanZ(@ptrCast([*c]u8, &file_info.m_filename));
            if (my_path.len > 0 and !std.mem.startsWith(u8, path_slice, my_path)) {
                total_index += 1;
                continue;
            }
            if (std.mem.endsWith(u8, path_slice, "/")) {
                path_slice = path_slice[0 .. path_slice.len - 1];
            }
            if (std.mem.indexOf(u8, path_slice, "/") != null) {
                total_index += 1;
                continue;
            }

            var file: File = undefined;
            std.mem.copy(u8, file.name_buf[0..], path_slice[my_path.len..]);
            file.name_len = path_slice.len - my_path.len;

            files[true_index] = file;

            true_index += 1;
            total_index += 1;
        }
        return true_index;
    }

    pub fn unlink_me(self: *Node) !void {
        // There's nothing worth doing here.
    }
};

const FsImpl = struct {
    const OpenedCache = std.AutoHashMap(u32, *Node);

    const ops: vfs.FileSystem.Ops = .{
        .mount = FsImpl.mount,
        .unmount = FsImpl.unmount,
    };

    zip_data: []u8 = undefined,
    archive: c.mz_zip_archive = undefined,
    opened: FsImpl.OpenedCache = undefined,

    pub fn mount(self: *vfs.FileSystem, zipfile: ?*Node, args: ?[]const u8) anyerror!*Node {
        if (zipfile == null) return vfs.Error.NoSuchFile;

        var fs_impl = try self.allocator.create(FsImpl);
        errdefer self.allocator.destroy(fs_impl);

        // TODO: take advantage of read/write/etc callbacks
        // TODO: take advantage of memory allocation callbacks
        fs_impl.* = .{};
        fs_impl.zip_data = try self.allocator.alloc(u8, zipfile.?.stat.size);
        errdefer self.allocator.free(fs_impl.zip_data);

        var amount = try zipfile.?.read(0, fs_impl.zip_data);
        if (amount != zipfile.?.stat.size) return vfs.Error.ReadFailed;

        c.mz_zip_zero_struct(&fs_impl.archive);
        var mz_ok = c.mz_zip_reader_init_mem(&fs_impl.archive, fs_impl.zip_data.ptr, fs_impl.zip_data.len, 0);
        if (mz_ok == 0) return vfs.Error.NoSuchFile;

        fs_impl.opened = FsImpl.OpenedCache.init(self.allocator);
        errdefer fs_impl.opened.deinit();

        self.cookie = util.asCookie(fs_impl);

        var root_node_impl = try self.allocator.create(NodeImpl);
        errdefer self.allocator.destroy(root_node_impl);

        var now = platform.getTimeNano();

        var root_node_stat = Node.Stat{
            .flags = .{ .mount_point = true },
            .inode = 1,
            .type = .Directory,
            .mode = Node.Mode.all,
            .modify_time = now,
            .create_time = now,
            .access_time = now,
        };

        var root_node = try self.allocator.create(Node);
        errdefer self.allocator.destroy(root_node);

        root_node.* = Node.init(NodeImpl.ops, util.asCookie(root_node_impl), root_node_stat, self);

        return root_node;
    }

    pub fn unmount(self: *vfs.FileSystem) void {
        var fs_impl = self.cookie.?.as(FsImpl);
        _ = c.mz_zip_reader_end(&fs_impl.archive);
    }
};

pub const Fs = vfs.FileSystem.init("zipfs", FsImpl.ops);
