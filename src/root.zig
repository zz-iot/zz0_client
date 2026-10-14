const builtin = @import("builtin");

pub const xrce = @import("xrce.zig");
pub const demo = @import("demo.zig");
pub const session = @import("session.zig");
pub const transport = @import("transport.zig");
pub const host_udp = if (builtin.zig_version.major == 0 and builtin.zig_version.minor == 15)
    @import("host_udp.zig")
else
    struct {};

test {
    @import("std").testing.refAllDecls(@This());
}
