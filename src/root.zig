const builtin = @import("builtin");

pub const xrce = @import("xrce.zig");
pub const demo = @import("demo.zig");
pub const session = @import("session.zig");
pub const transport = @import("transport.zig");
pub const host_udp = if (builtin.os.tag == .freestanding)
    struct {}
else
    @import("host_udp.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
