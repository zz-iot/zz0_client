const std = @import("std");
const session = @import("session.zig");
const transport_api = @import("transport.zig");
const xrce = @import("xrce.zig");

const posix = std.posix;

pub const UdpTransport = struct {
    fd: posix.socket_t,
    agent: std.net.Address,
    max_payload: usize = 512,

    pub fn init(agent: std.net.Address) !UdpTransport {
        const fd = try posix.socket(agent.any.family, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, posix.IPPROTO.UDP);
        return .{ .fd = fd, .agent = agent };
    }

    pub fn bind(local: std.net.Address, agent: std.net.Address) !UdpTransport {
        const fd = try posix.socket(local.any.family, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, posix.IPPROTO.UDP);
        errdefer posix.close(fd);
        try posix.bind(fd, &local.any, local.getOsSockLen());
        return .{ .fd = fd, .agent = agent };
    }

    pub fn deinit(self: *UdpTransport) void {
        posix.close(self.fd);
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
        const sent = try posix.sendto(self.fd, bytes, 0, &dest.any, dest.getOsSockLen());
        if (sent != bytes.len) return error.ShortDatagramSend;
    }

    pub fn recvMessage(self: *UdpTransport, buffer: []u8, timeout_ms: i32) !transport_api.ReceivedMessage {
        try waitReadable(self.fd, timeout_ms);
        return try self.recvBlocking(buffer);
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

    fn recvBlocking(self: *UdpTransport, buffer: []u8) !transport_api.ReceivedMessage {
        var storage: posix.sockaddr.storage = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
        const addr: *posix.sockaddr = @ptrCast(&storage);
        const n = try posix.recvfrom(self.fd, buffer, 0, addr, &addr_len);

        const source_addr: *align(4) const posix.sockaddr = @ptrCast(&storage);
        const source = try addressToEndpoint(std.net.Address.initPosix(source_addr));
        return .{ .bytes = buffer[0..n], .source = source };
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
        if (!try isReadable(self.fd, 0)) return null;
        return try self.recvBlocking(buffer);
    }
};

fn endpointToAddress(endpoint: transport_api.Endpoint, default: std.net.Address) !std.net.Address {
    return switch (endpoint) {
        .none => default,
        .udp4 => |udp4| std.net.Address.initIp4(udp4.address, udp4.port),
        .serial => error.UnsupportedEndpoint,
    };
}

fn addressToEndpoint(address: std.net.Address) !transport_api.Endpoint {
    if (address.any.family != posix.AF.INET) return error.UnsupportedAddressFamily;
    const bytes: *const [4]u8 = @ptrCast(&address.in.sa.addr);
    return .{ .udp4 = .{ .address = bytes.*, .port = address.getPort() } };
}

fn waitReadable(fd: posix.socket_t, timeout_ms: i32) !void {
    if (!try isReadable(fd, timeout_ms)) return error.Timeout;
}

fn isReadable(fd: posix.socket_t, timeout_ms: i32) !bool {
    var fds = [_]posix.pollfd{.{
        .fd = fd,
        .events = posix.POLL.IN,
        .revents = 0,
    }};
    const ready = try posix.poll(&fds, timeout_ms);
    return ready != 0 and (fds[0].revents & posix.POLL.IN) != 0;
}

test "host UDP transport exchanges CREATE_CLIENT and STATUS_AGENT" {
    const TestAgent = struct {
        fd: posix.socket_t,
        address: std.net.Address,
        result: anyerror!void = {},

        fn init() !@This() {
            const bind_addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 0);
            const fd = try posix.socket(bind_addr.any.family, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, posix.IPPROTO.UDP);
            errdefer posix.close(fd);
            try posix.bind(fd, &bind_addr.any, bind_addr.getOsSockLen());

            var storage: posix.sockaddr.storage = undefined;
            var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
            const addr: *posix.sockaddr = @ptrCast(&storage);
            try posix.getsockname(fd, addr, &addr_len);

            const local_addr: *align(4) const posix.sockaddr = @ptrCast(&storage);
            return .{
                .fd = fd,
                .address = std.net.Address.initPosix(local_addr),
            };
        }

        fn deinit(self: *@This()) void {
            posix.close(self.fd);
            self.* = undefined;
        }

        fn run(self: *@This()) void {
            self.result = self.runFallible();
        }

        fn runFallible(self: *@This()) !void {
            try waitReadable(self.fd, 1000);

            var request: [xrce.CreateClient.message_len + 32]u8 = undefined;
            var source: posix.sockaddr.storage = undefined;
            var source_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
            const source_addr: *posix.sockaddr = @ptrCast(&source);
            const request_len = try posix.recvfrom(self.fd, &request, 0, source_addr, &source_len);
            const create = try xrce.decodeCreateClientMessage(request[0..request_len]);

            var response: [xrce.StatusAgent.message_len]u8 = undefined;
            const response_len = try (xrce.StatusAgent{
                .session_id = create.session_id,
                .sequence_nr = create.header.sequence_nr,
            }).encodeMessage(&response);

            const sent = try posix.sendto(self.fd, response[0..response_len], 0, source_addr, source_len);
            if (sent != response_len) return error.ShortDatagramSend;
        }
    };

    var agent = try TestAgent.init();
    defer agent.deinit();

    var agent_thread = try std.Thread.spawn(.{}, TestAgent.run, .{&agent});

    var client = try UdpTransport.init(agent.address);
    defer client.deinit();

    const status = try client.createClientPing(.{
        .client_key = .{ 0x11, 0x22, 0x33, 0x44 },
        .session_id = 0x81,
        .sequence_nr = 9,
    }, 1000);

    agent_thread.join();
    try agent.result;

    try std.testing.expectEqual(@as(u8, 0x81), status.header.session_id);
    try std.testing.expectEqual(@as(u16, 9), status.header.sequence_nr);
    try std.testing.expectEqualSlices(u8, &xrce.vendor_id_zenzen, &status.vendor_id);
}
