const std = @import("std");
const transport_api = @import("transport.zig");
const xrce = @import("xrce.zig");

pub const ClientSession = struct {
    client_key: [4]u8,
    session_id: u8,
    vendor_id: [2]u8 = xrce.vendor_id_zenzen,
    next_sequence_nr: u16 = 0,
    next_request_id: u16 = 1,
    state: State = .disconnected,
    pending_create_sequence_nr: ?u16 = null,
    pending_request: ?xrce.BaseObjectRequest = null,

    pub const Options = struct {
        client_key: [4]u8,
        session_id: u8,
        vendor_id: [2]u8 = xrce.vendor_id_zenzen,
        initial_sequence_nr: u16 = 0,
        initial_request_id: u16 = 1,
    };

    pub const State = enum {
        disconnected,
        create_client_sent,
        connected,
    };

    pub const Event = union(enum) {
        status_agent: xrce.DecodedStatusAgent,
        status: xrce.DecodedStatus,
        ignored,
    };

    pub fn init(options: Options) ClientSession {
        return .{
            .client_key = options.client_key,
            .session_id = options.session_id,
            .vendor_id = options.vendor_id,
            .next_sequence_nr = options.initial_sequence_nr,
            .next_request_id = options.initial_request_id,
        };
    }

    pub fn encodeCreateClient(self: *ClientSession, out: []u8) ![]const u8 {
        const sequence_nr = self.takeSequenceNr();
        const len = try (xrce.CreateClient{
            .client_key = self.client_key,
            .session_id = self.session_id,
            .vendor_id = self.vendor_id,
            .sequence_nr = sequence_nr,
        }).encodeMessage(out);
        self.pending_create_sequence_nr = sequence_nr;
        self.state = .create_client_sent;
        return out[0..len];
    }

    pub fn sendCreateClient(
        self: *ClientSession,
        transport: transport_api.Transport,
        endpoint: transport_api.Endpoint,
        out: []u8,
    ) !void {
        const bytes = try self.encodeCreateClient(out);
        try transport.send(bytes, endpoint);
    }

    pub const CreateByReferenceOptions = struct {
        object_prefix: xrce.ObjectIdPrefix,
        object_kind: xrce.ObjectKind,
        reference: []const u8,
        reuse: bool = true,
        replace: bool = true,
        participant_domain_id: i16 = 0,
        related_object_id: ?xrce.ObjectId = null,
    };

    pub fn encodeCreateByReference(
        self: *ClientSession,
        out: []u8,
        options: CreateByReferenceOptions,
    ) ![]const u8 {
        const request_id = self.takeRequestId();
        const sequence_nr = self.takeSequenceNr();
        const create = xrce.CreateByReference{
            .session_id = self.session_id,
            .sequence_nr = sequence_nr,
            .request_id = request_id,
            .object_prefix = options.object_prefix,
            .object_kind = options.object_kind,
            .reference = options.reference,
            .reuse = options.reuse,
            .replace = options.replace,
            .participant_domain_id = options.participant_domain_id,
            .related_object_id = options.related_object_id,
        };
        const len = try create.encodeMessage(out);
        self.pending_request = .{
            .request_id = request_id,
            .object_id = create.objectId(),
        };
        return out[0..len];
    }

    pub fn sendCreateByReference(
        self: *ClientSession,
        transport: transport_api.Transport,
        endpoint: transport_api.Endpoint,
        out: []u8,
        options: CreateByReferenceOptions,
    ) !void {
        const bytes = try self.encodeCreateByReference(out, options);
        try transport.send(bytes, endpoint);
    }

    pub const WriteDataOptions = struct {
        object_id: xrce.ObjectId,
        serialized_data: []const u8,
    };

    pub fn encodeWriteData(
        self: *ClientSession,
        out: []u8,
        options: WriteDataOptions,
    ) ![]const u8 {
        const request_id = self.takeRequestId();
        const sequence_nr = self.takeSequenceNr();
        const len = try (xrce.WriteData{
            .session_id = self.session_id,
            .sequence_nr = sequence_nr,
            .request_id = request_id,
            .object_id = options.object_id,
            .serialized_data = options.serialized_data,
        }).encodeMessage(out);
        self.pending_request = .{
            .request_id = request_id,
            .object_id = options.object_id,
        };
        return out[0..len];
    }

    pub fn sendWriteData(
        self: *ClientSession,
        transport: transport_api.Transport,
        endpoint: transport_api.Endpoint,
        out: []u8,
        options: WriteDataOptions,
    ) !void {
        const bytes = try self.encodeWriteData(out, options);
        try transport.send(bytes, endpoint);
    }

    pub fn poll(
        self: *ClientSession,
        transport: transport_api.Transport,
        buffer: []u8,
    ) !?Event {
        const message = (try transport.recv(buffer)) orelse return null;
        return try self.handleDatagram(message.bytes);
    }

    pub fn handleDatagram(self: *ClientSession, bytes: []const u8) !Event {
        const message = try xrce.decodeMessage(bytes);
        var iterator = message.submessages();

        while (try iterator.next()) |submessage| {
            switch (submessage.header.id) {
                .status_agent => {
                    const status = try xrce.decodeStatusAgent(message.header, submessage);
                    try self.acceptStatusAgent(status);
                    return .{ .status_agent = status };
                },
                .status => {
                    const status = try xrce.decodeStatus(message.header, submessage);
                    try self.acceptStatus(status);
                    return .{ .status = status };
                },
                else => {},
            }
        }

        return .ignored;
    }

    fn acceptStatusAgent(self: *ClientSession, status: xrce.DecodedStatusAgent) !void {
        if (status.header.session_id != self.session_id) return error.UnexpectedSessionId;
        if (self.pending_create_sequence_nr) |sequence_nr| {
            if (status.header.sequence_nr != sequence_nr) return error.UnexpectedSequenceNr;
        }
        self.pending_create_sequence_nr = null;
        self.state = .connected;
    }

    fn acceptStatus(self: *ClientSession, status: xrce.DecodedStatus) !void {
        const pending = self.pending_request orelse return error.UnexpectedStatus;
        if (!std.mem.eql(u8, &status.related_request.request_id, &pending.request_id)) return error.UnexpectedRequestId;
        if (!std.mem.eql(u8, &status.related_request.object_id, &pending.object_id)) return error.UnexpectedObjectId;
        self.pending_request = null;
    }

    fn takeSequenceNr(self: *ClientSession) u16 {
        const sequence_nr = self.next_sequence_nr;
        self.next_sequence_nr +%= 1;
        return sequence_nr;
    }

    fn takeRequestId(self: *ClientSession) xrce.RequestId {
        const request_id = xrce.requestIdFromInt(self.next_request_id);
        self.next_request_id +%= 1;
        return request_id;
    }
};

test "client session encodes CREATE_CLIENT and accepts STATUS_AGENT" {
    var client = ClientSession.init(.{
        .client_key = .{ 0x10, 0x20, 0x30, 0x40 },
        .session_id = 0x81,
        .initial_sequence_nr = 5,
    });

    var request: [xrce.CreateClient.message_len]u8 = undefined;
    const request_bytes = try client.encodeCreateClient(&request);
    try std.testing.expectEqual(ClientSession.State.create_client_sent, client.state);
    try std.testing.expectEqual(@as(u16, 6), client.next_sequence_nr);

    const create = try xrce.decodeCreateClientMessage(request_bytes);
    try std.testing.expectEqual(@as(u16, 5), create.header.sequence_nr);
    try std.testing.expectEqual(@as(u8, 0x81), create.session_id);

    var response: [xrce.StatusAgent.message_len]u8 = undefined;
    _ = try (xrce.StatusAgent{
        .session_id = 0x81,
        .sequence_nr = 5,
    }).encodeMessage(&response);

    const event = try client.handleDatagram(&response);
    switch (event) {
        .status_agent => |status| {
            try std.testing.expectEqual(@as(u16, 5), status.header.sequence_nr);
        },
        else => return error.ExpectedStatusAgent,
    }
    try std.testing.expectEqual(ClientSession.State.connected, client.state);
    try std.testing.expectEqual(@as(?u16, null), client.pending_create_sequence_nr);
}

test "client session rejects STATUS_AGENT for another session" {
    var client = ClientSession.init(.{
        .client_key = .{ 0x10, 0x20, 0x30, 0x40 },
        .session_id = 0x81,
        .initial_sequence_nr = 1,
    });

    var request: [xrce.CreateClient.message_len]u8 = undefined;
    _ = try client.encodeCreateClient(&request);

    var response: [xrce.StatusAgent.message_len]u8 = undefined;
    _ = try (xrce.StatusAgent{
        .session_id = 0x82,
        .sequence_nr = 1,
    }).encodeMessage(&response);

    try std.testing.expectError(error.UnexpectedSessionId, client.handleDatagram(&response));
    try std.testing.expectEqual(ClientSession.State.create_client_sent, client.state);
}

test "client session transport helpers use the transport interface" {
    const Mock = struct {
        sent: [xrce.CreateClient.message_len]u8 = undefined,
        sent_len: usize = 0,
        response: [xrce.StatusAgent.message_len]u8 = undefined,
        has_response: bool = false,

        fn maxPayload(_: *anyopaque) usize {
            return 512;
        }

        fn send(ctx: *anyopaque, bytes: []const u8, _: transport_api.Endpoint) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (bytes.len > self.sent.len) return error.MessageTooLarge;
            @memcpy(self.sent[0..bytes.len], bytes);
            self.sent_len = bytes.len;
        }

        fn recv(ctx: *anyopaque, buffer: []u8) !?transport_api.ReceivedMessage {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (!self.has_response) return null;
            if (buffer.len < xrce.StatusAgent.message_len) return error.BufferTooSmall;
            @memcpy(buffer[0..xrce.StatusAgent.message_len], &self.response);
            self.has_response = false;
            return .{ .bytes = buffer[0..xrce.StatusAgent.message_len] };
        }

        fn transport(self: *@This()) transport_api.Transport {
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
    _ = try (xrce.StatusAgent{
        .session_id = 0x81,
        .sequence_nr = 2,
    }).encodeMessage(&mock.response);
    mock.has_response = true;

    var client = ClientSession.init(.{
        .client_key = .{ 1, 2, 3, 4 },
        .session_id = 0x81,
        .initial_sequence_nr = 2,
    });

    var request: [xrce.CreateClient.message_len]u8 = undefined;
    try client.sendCreateClient(mock.transport(), .none, &request);
    try std.testing.expectEqual(@as(usize, xrce.CreateClient.message_len), mock.sent_len);

    var response: [xrce.StatusAgent.message_len]u8 = undefined;
    const event = (try client.poll(mock.transport(), &response)).?;
    switch (event) {
        .status_agent => |status| try std.testing.expectEqual(@as(u16, 2), status.header.sequence_nr),
        else => return error.ExpectedStatusAgent,
    }
    try std.testing.expectEqual(ClientSession.State.connected, client.state);
}

test "client session creates by reference and accepts STATUS" {
    var client = ClientSession.init(.{
        .client_key = .{ 1, 2, 3, 4 },
        .session_id = 0x81,
        .initial_sequence_nr = 8,
        .initial_request_id = 0x01aa,
    });

    var request: [128]u8 = undefined;
    const bytes = try client.encodeCreateByReference(&request, .{
        .object_prefix = .{ 0xdd, 0xd0 },
        .object_kind = .application,
        .reference = "DemoApp",
    });

    const create = try xrce.decodeCreateMessage(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0x01 }, &create.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 0xdd, 0xdc }, &create.object_id);
    try std.testing.expectEqual(xrce.ObjectKind.application, create.object_kind);
    try std.testing.expectEqualSlices(u8, "DemoApp", create.reference);

    var response: [xrce.Status.message_len]u8 = undefined;
    _ = try (xrce.Status{
        .session_id = 0x81,
        .sequence_nr = 8,
        .request = .{
            .request_id = create.request_id,
            .object_id = create.object_id,
        },
        .result = .{ .status = .ok },
    }).encodeMessage(&response);

    const event = try client.handleDatagram(&response);
    switch (event) {
        .status => |status| try std.testing.expectEqual(xrce.StatusValue.ok, status.result.status),
        else => return error.ExpectedStatus,
    }
    try std.testing.expectEqual(@as(?xrce.BaseObjectRequest, null), client.pending_request);
}

test "client session writes data and accepts STATUS" {
    var client = ClientSession.init(.{
        .client_key = .{ 1, 2, 3, 4 },
        .session_id = 0x81,
        .initial_sequence_nr = 20,
        .initial_request_id = 0x0200,
    });

    var request: [128]u8 = undefined;
    const bytes = try client.encodeWriteData(&request, .{
        .object_id = .{ 0x10, 0x55 },
        .serialized_data = &.{ 0x00, 0x07, 0x00, 0x00 },
    });

    const write = try xrce.decodeWriteDataMessage(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x02 }, &write.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x55 }, &write.object_id);

    var response: [xrce.Status.message_len]u8 = undefined;
    _ = try (xrce.Status{
        .session_id = 0x81,
        .sequence_nr = 20,
        .request = .{
            .request_id = write.request_id,
            .object_id = write.object_id,
        },
        .result = .{ .status = .ok },
    }).encodeMessage(&response);

    const event = try client.handleDatagram(&response);
    switch (event) {
        .status => |status| try std.testing.expectEqual(xrce.StatusValue.ok, status.result.status),
        else => return error.ExpectedStatus,
    }
    try std.testing.expectEqual(@as(?xrce.BaseObjectRequest, null), client.pending_request);
}
