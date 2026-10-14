const std = @import("std");

pub const Endpoint = union(enum) {
    none,
    udp4: Udp4,
    serial: Serial,

    pub const Udp4 = struct {
        address: [4]u8,
        port: u16,
    };

    pub const Serial = struct {
        source: u8,
        remote: u8,
    };
};

pub const ReceivedMessage = struct {
    bytes: []const u8,
    source: Endpoint = .none,
};

pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        max_payload: *const fn (*anyopaque) usize,
        send: *const fn (*anyopaque, []const u8, Endpoint) anyerror!void,
        recv: *const fn (*anyopaque, []u8) anyerror!?ReceivedMessage,
    };

    pub fn maxPayload(self: Transport) usize {
        return self.vtable.max_payload(self.ptr);
    }

    pub fn send(self: Transport, bytes: []const u8, endpoint: Endpoint) !void {
        try self.vtable.send(self.ptr, bytes, endpoint);
    }

    pub fn recv(self: Transport, buffer: []u8) !?ReceivedMessage {
        return self.vtable.recv(self.ptr, buffer);
    }
};

test "mock transport can capture one outgoing message" {
    const Mock = struct {
        sent: [64]u8 = undefined,
        sent_len: usize = 0,
        endpoint: Endpoint = .none,

        fn maxPayload(_: *anyopaque) usize {
            return 64;
        }

        fn send(ctx: *anyopaque, bytes: []const u8, endpoint: Endpoint) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (bytes.len > self.sent.len) return error.MessageTooLarge;
            @memcpy(self.sent[0..bytes.len], bytes);
            self.sent_len = bytes.len;
            self.endpoint = endpoint;
        }

        fn recv(_: *anyopaque, _: []u8) !?ReceivedMessage {
            return null;
        }

        fn transport(self: *@This()) Transport {
            return .{
                .ptr = self,
                .vtable = &.{
                    .max_payload = maxPayload,
                    .send = send,
                    .recv = recv,
                },
            };
        }
    };

    var mock = Mock{};
    const tr = mock.transport();
    try tr.send(&.{ 1, 2, 3 }, .{ .udp4 = .{ .address = .{ 127, 0, 0, 1 }, .port = 8888 } });

    try std.testing.expectEqual(@as(usize, 3), mock.sent_len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, mock.sent[0..mock.sent_len]);
    try std.testing.expectEqual(@as(u16, 8888), mock.endpoint.udp4.port);
}
