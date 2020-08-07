const std = @import("std");

const vfs = @import("../vfs.zig");
const util = @import("../util.zig");

const RefCount = util.RefCount;

const c = @cImport({
    @cInclude("miniz/miniz.h");
});

const File = vfs.File;
const Node = vfs.Node;
const FileSystem = vfs.FileSystem;

const NodeImpl = struct {
    const ops: Node.Ops = .{
        // TODO
    };

    pub fn init() *Node {}
};

const FsImpl = struct {
    const ops: FileSystem.Ops = .{
        .mount = FsImpl.mount,
    };

    zip_data: []u8 = undefined,
    archive: c.mz_zip_archive = undefined,

    pub fn mount(self: *FileSystem, allocator: *std.mem.Allocator, zipfile: ?*Node, args: ?[]const u8) anyerror!*Node {
        if (zipfile == null) return vfs.Error.NoSuchFile;

        var fs_impl = try allocator.create(FsImpl);
        errdefer allocator.destroy(fs_impl);

        // TODO: take advantage of read/write/etc callbacks
        fs_impl.* = .{};
        fs_impl.zip_data = try allocator.alloc(u8, zipfile.?.stat.size);
        errdefer allocator.free(fs_impl.zip_data);

        try zipfile.?.read(0, fs_impl.zip_data);
        var mz_ok = c.mz_zip_reader_init_mem(&fs_impl.archive, &fs_impl.zip_data, fs_impl.zip_data.mem, 0);
        if (!mz_ok) return vfs.Error.NoSuchFile;

        return root_node;
    }
};
