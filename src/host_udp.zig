const std = @import("std");
const session = @import("session.zig");
const transport_api = @import("transport.zig");
const xrce = @import("xrce.zig");
const net = std.Io.net;

/// Host UDP adapter. The supplied Io must outlive the transport.
pub const UdpTransport = struct {
    io: std.Io,
    socket: net.Socket,
    agent: net.IpAddress,
    max_payload: usize = 512,

    pub fn init(io: std.Io, agent: net.IpAddress) !UdpTransport {
        const local: net.IpAddress = switch (agent) {
            .ip4 => .{ .ip4 = .unspecified(0) },
            .ip6 => return error.UnsupportedAddressFamily,
        };
        return bind(io, local, agent);
    }

    pub fn bind(io: std.Io, local: net.IpAddress, agent: net.IpAddress) !UdpTransport {
        if (local != .ip4 or agent != .ip4) return error.UnsupportedAddressFamily;
        const socket = try local.bind(io, .{ .mode = .dgram, .protocol = .udp });
        return .{ .io = io, .socket = socket, .agent = agent };
    }

    pub fn deinit(self: *UdpTransport) void {
        self.socket.close(self.io);
        self.* = undefined;
    }

    pub fn transport(self: *UdpTransport) transport_api.Transport {
        return .{
            .ptr = self,
            .vtable = &.{
                .max_payload = maxPayload,
                .send = sendVtable,
                .recv = recvVtable,
            },
        };
    }

    pub fn sendBytes(self: *UdpTransport, bytes: []const u8, endpoint: transport_api.Endpoint) !void {
        const dest = try endpointToAddress(endpoint, self.agent);
        try self.socket.send(self.io, &dest, bytes);
    }

    /// A negative timeout waits indefinitely; zero polls without blocking.
    pub fn recvMessage(self: *UdpTransport, buffer: []u8, timeout_ms: i32) !transport_api.ReceivedMessage {
        const timeout: std.Io.Timeout = if (timeout_ms < 0) .none else .{ .duration = .{
            .clock = .awake,
            .raw = std.Io.Duration.fromMilliseconds(timeout_ms),
        } };
        const incoming = try self.socket.receiveTimeout(self.io, buffer, timeout);
        return .{ .bytes = incoming.data, .source = try addressToEndpoint(incoming.from) };
    }

    pub fn createClientPing(
        self: *UdpTransport,
        request: xrce.CreateClient,
        timeout_ms: i32,
    ) !xrce.DecodedStatusAgent {
        var client_session = session.ClientSession.init(.{
            .client_key = request.client_key,
            .session_id = request.session_id,
            .vendor_id = request.vendor_id,
            .initial_sequence_nr = request.sequence_nr,
        });
        return try self.openSession(&client_session, timeout_ms);
    }

    pub fn openSession(
        self: *UdpTransport,
        client_session: *session.ClientSession,
        timeout_ms: i32,
    ) !xrce.DecodedStatusAgent {
        var outbound: [xrce.CreateClient.message_len]u8 = undefined;
        const outbound_bytes = try client_session.encodeCreateClient(&outbound);
        try self.sendBytes(outbound_bytes, .none);

        var inbound: [xrce.StatusAgent.message_len + 32]u8 = undefined;
        const message = try self.recvMessage(&inbound, timeout_ms);
        const event = try client_session.handleDatagram(message.bytes);
        return switch (event) {
            .status_agent => |status| status,
            else => error.NoStatusAgent,
        };
    }

    fn maxPayload(ctx: *anyopaque) usize {
        const self: *UdpTransport = @ptrCast(@alignCast(ctx));
        return self.max_payload;
    }

    fn sendVtable(ctx: *anyopaque, bytes: []const u8, endpoint: transport_api.Endpoint) !void {
        const self: *UdpTransport = @ptrCast(@alignCast(ctx));
        try self.sendBytes(bytes, endpoint);
    }

    fn recvVtable(ctx: *anyopaque, buffer: []u8) !?transport_api.ReceivedMessage {
        const self: *UdpTransport = @ptrCast(@alignCast(ctx));
        return self.recvMessage(buffer, 0) catch |err| switch (err) {
            error.Timeout => null,
            else => return err,
        };
    }
};

fn endpointToAddress(endpoint: transport_api.Endpoint, default: net.IpAddress) !net.IpAddress {
    return switch (endpoint) {
        .none => default,
        .udp4 => |udp4| .{ .ip4 = .{ .bytes = udp4.address, .port = udp4.port } },
        .serial => error.UnsupportedEndpoint,
    };
}

fn addressToEndpoint(address: net.IpAddress) !transport_api.Endpoint {
    return switch (address) {
        .ip4 => |ip4| .{ .udp4 = .{ .address = ip4.bytes, .port = ip4.port } },
        .ip6 => error.UnsupportedAddressFamily,
    };
}

test "host UDP transport exchanges CREATE_CLIENT and STATUS_AGENT" {
    const io = std.testing.io;
    const local: net.IpAddress = .{ .ip4 = .loopback(0) };
    const socket = try local.bind(io, .{ .mode = .dgram, .protocol = .udp });
    defer socket.close(io);

    const TestAgent = struct {
        socket: net.Socket,
        result: anyerror!void = {},

        fn run(self: *@This()) void {
            self.result = self.runFallible();
        }

        fn runFallible(self: *@This()) !void {
            var request: [xrce.CreateClient.message_len + 32]u8 = undefined;
            const incoming = try self.socket.receiveTimeout(std.testing.io, &request, .{ .duration = .{
                .clock = .awake,
                .raw = std.Io.Duration.fromMilliseconds(1000),
            } });
            const create = try xrce.decodeCreateClientMessage(incoming.data);
            var response: [xrce.StatusAgent.message_len]u8 = undefined;
            const response_len = try (xrce.StatusAgent{
                .session_id = create.session_id,
                .sequence_nr = create.header.sequence_nr,
            }).encodeMessage(&response);
            try self.socket.send(std.testing.io, &incoming.from, response[0..response_len]);
        }
    };
    var agent = TestAgent{ .socket = socket };
    const agent_thread = try std.Thread.spawn(.{}, TestAgent.run, .{&agent});
    defer agent_thread.join();

    var client = try UdpTransport.init(io, socket.address);
    defer client.deinit();
    const status = try client.createClientPing(.{
        .client_key = .{ 0x11, 0x22, 0x33, 0x44 },
        .session_id = 0x81,
        .sequence_nr = 9,
    }, 1000);

    try std.testing.expectEqual(@as(u8, 0x81), status.header.session_id);
    try std.testing.expectEqual(@as(u16, 9), status.header.sequence_nr);
    try std.testing.expectEqualSlices(u8, &xrce.vendor_id_zenzen, &status.vendor_id);
}

test "host UDP transport polls and receives from an explicit endpoint" {
    const io = std.testing.io;
    const local: net.IpAddress = .{ .ip4 = .loopback(0) };
    var sender = try UdpTransport.bind(io, local, local);
    defer sender.deinit();
    var receiver = try UdpTransport.bind(io, local, sender.socket.address);
    defer receiver.deinit();
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqual(null, try receiver.transport().recv(&buffer));
    try std.testing.expectError(error.Timeout, receiver.recvMessage(&buffer, 1));

    const destination = try addressToEndpoint(receiver.socket.address);
    try sender.transport().send("hello", destination);
    const message = try receiver.transport().recv(&buffer) orelse return error.ExpectedDatagram;
    try std.testing.expectEqualStrings("hello", message.bytes);
    try std.testing.expectEqualDeep(try addressToEndpoint(sender.socket.address), message.source);
    try std.testing.expectError(error.UnsupportedEndpoint, sender.sendBytes("x", .{ .serial = .{ .source = 1, .remote = 2 } }));
}
