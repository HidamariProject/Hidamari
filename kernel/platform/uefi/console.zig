const std = @import("std");
const uefi = std.os.uefi;
const uefi_platform = @import("../uefi.zig");
const vfs = @import("../../vfs.zig");

const Node = vfs.Node;

var console_scratch: [8192]u8 = undefined;
var console_fifo = std.fifo.LinearFifo(u8, .Slice).init(console_scratch[0..]);

// TODO: pass scancodes

pub fn keyboardHandler() void {
    const input_events = [_]uefi.Event{
        uefi.system_table.con_in.?.wait_for_key,
    };
    var index: usize = 0;
    if (uefi.system_table.boot_services.?.waitForEvent(input_events.len, &input_events, &index) != uefi.Status.Success) return;
    if (index != 0) return;

    var key: uefi.protocols.InputKey = undefined;
    if (uefi.system_table.con_in.?.readKeyStroke(&key) != uefi.Status.Success) return;

    var outbuf: [1]u8 = undefined;
    var inbuf: [1]u16 = undefined;

    inbuf[0] = key.unicode_char;
    _ = std.unicode.utf16leToUtf8(outbuf[0..], inbuf[0..]) catch unreachable;

    _ = console_fifo.write(outbuf[0..]) catch null;
}

pub const ConsoleNode = struct {
    const ops: Node.Ops = .{ 
        .read = ConsoleNode.read,
        .write = ConsoleNode.write,
    };

    pub fn init() Node {
        return Node.init(ConsoleNode.ops, null, null, null);
    }

    pub fn write(self: *Node, offset: u64, buffer: []const u8) !usize {
        uefi_platform.earlyprintk(buffer);
        return buffer.len;
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        return console_fifo.read(buffer);
    }
};
