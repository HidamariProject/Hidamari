extern "shinkou_debug" fn earlyprintk(str: [*]const u8, str_len: usize) void;

pub fn main() u8 {
    var message = "Hello World from userspace!";
    earlyprintk(message[0..], message[0..].len);
    return 42;
}
