const std = @import("std");
const uefi = std.os.uefi;
const uefi_platform = @import("../uefi.zig");
const vfs = @import("../../vfs.zig");

const Node = vfs.Node;

var console_scratch: [8192]u8 = undefined;
var console_fifo = std.fifo.LinearFifo(u8, .Slice).init(console_scratch[0..]);

var keyboard_scratch: [8192]u8 = undefined;
var keyboard_fifo = std.fifo.LinearFifo(u8, .Slice).init(keyboard_scratch[0..]);

pub var text_in_ex: ?*uefi.protocols.SimpleTextInputExProtocol = null;

pub fn init() void {
    if (uefi.system_table.boot_services.?.locateProtocol(&uefi.protocols.SimpleTextInputExProtocol.guid, null, @ptrCast(*?*c_void, &text_in_ex)) == uefi.Status.Success) {
        uefi_platform.earlyprintk("Extended text input supported.\n");
    }
}

pub inline fn keyboardHandler() void {
    if (text_in_ex != null) extendedKeyboardHandler() else basicKeyboardHandler();
}

fn basicKeyboardHandler() void {
    if (uefi.system_table.boot_services.?.checkEvent(uefi.system_table.con_in.?.wait_for_key) != uefi.Status.Success) return;
    var key: uefi.protocols.InputKey = undefined;
    if (uefi.system_table.con_in.?.readKeyStroke(&key) != uefi.Status.Success) return;

    var outbuf: [1]u8 = undefined;
    var inbuf: [1]u16 = undefined;

    inbuf[0] = key.unicode_char;
    _ = std.unicode.utf16leToUtf8(outbuf[0..], inbuf[0..]) catch unreachable;

    _ = console_fifo.write(outbuf[0..]) catch null;
}

fn extendedKeyboardHandler() void {
    if (uefi.system_table.boot_services.?.checkEvent(text_in_ex.?.wait_for_key_ex) != uefi.Status.Success) return;
    var keydata: uefi.protocols.KeyData = undefined;
    if (text_in_ex.?.readKeyStrokeEx(&keydata) != uefi.Status.Success) return;

    var outbuf: [1]u8 = undefined;
    var inbuf: [1]u16 = undefined;

    inbuf[0] = keydata.key.unicode_char;
    _ = std.unicode.utf16leToUtf8(outbuf[0..], inbuf[0..]) catch unreachable;

    _ = console_fifo.write(outbuf[0..]) catch null;

    _ = keyboard_fifo.write(std.mem.asBytes(&keydata)) catch null;
}

pub const ConsoleNode = struct {
    const ops: Node.Ops = .{
        .read = ConsoleNode.read,
        .write = ConsoleNode.write,
    };

    pub fn init() Node {
        return Node.init(ConsoleNode.ops, null, Node.Stat{ .type = .character_device, .device_info = .{ .class = .console, .name = "uefi_console" } }, null);
    }

    pub fn write(self: *Node, offset: u64, buffer: []const u8) !usize {
        uefi_platform.earlyprintk(buffer);
        return buffer.len;
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        var n = console_fifo.read(buffer);
        for (buffer[0..n]) |c, i| {
            if (c == '\r') buffer[i] = '\n';
        }
        uefi_platform.earlyprintk(buffer[0..n]);
        return if (n == 0) vfs.Error.Again else n;
    }
};

pub const KeyboardNode = struct {
    const ops: Node.Ops = .{
        .read = KeyboardNode.read,
    };

    pub fn init() Node {
        return Node.init(KeyboardNode.ops, null, Node.Stat{ .type = character_device, .device_info = .{ .class = .keyboard, .name = "uefi_keyboard" } }, null);
    }

    pub fn read(self: *Node, offset: u64, buffer: []u8) !usize {
        var n = keyboard_fifo.read(buffer);
        return if (n == 0) vfs.Error.Again else n;
    }
};
