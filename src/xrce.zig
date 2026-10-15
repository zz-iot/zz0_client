const std = @import("std");

pub const xrce_cookie: [4]u8 = .{ 'X', 'R', 'C', 'E' };
pub const xrce_version: [2]u8 = .{ 0x01, 0x00 };
pub const vendor_id_zenzen: [2]u8 = .{ 0x5a, 0x5a };

pub const session_id_none_without_client_key: u8 = 0x80;
pub const stream_id_none: u8 = 0x00;
pub const stream_id_builtin_best_effort: u8 = 0x01;
pub const stream_id_builtin_reliable: u8 = 0x80;

pub const flag_little_endian: u8 = 0x01;
pub const flag_create_reuse: u8 = 0x02;
pub const flag_create_replace: u8 = 0x04;
pub const flag_write_data_format_mask: u8 = 0x0e;

pub const RequestId = [2]u8;
pub const ObjectId = [2]u8;
pub const ObjectIdPrefix = [2]u8;

pub const SubmessageId = enum(u8) {
    create_client = 0,
    create = 1,
    get_info = 2,
    delete = 3,
    status_agent = 4,
    status = 5,
    info = 6,
    write_data = 7,
    read_data = 8,
    data = 9,
    acknack = 10,
    heartbeat = 11,
    reset = 12,
    fragment = 13,
    timestamp = 14,
    timestamp_reply = 15,
};

pub const ObjectKind = enum(u8) {
    invalid = 0x00,
    participant = 0x01,
    topic = 0x02,
    publisher = 0x03,
    subscriber = 0x04,
    datawriter = 0x05,
    datareader = 0x06,
    type = 0x0a,
    qosprofile = 0x0b,
    application = 0x0c,
    agent = 0x0d,
    client = 0x0e,
    other = 0x0f,
};

pub const RepresentationFormat = enum(u8) {
    by_reference = 0x01,
    as_xml_string = 0x02,
    in_binary = 0x03,
};

pub const StatusValue = enum(u8) {
    ok = 0x00,
    ok_matched = 0x01,
    err_dds_error = 0x80,
    err_mismatch = 0x81,
    err_already_exists = 0x82,
    err_denied = 0x83,
    err_unknown_reference = 0x84,
    err_invalid_data = 0x85,
    err_incompatible = 0x86,
    err_resources = 0x87,
};

pub const ResultStatus = struct {
    status: StatusValue = .ok,
    implementation_status: u8 = 0,
};

pub const MessageHeader = struct {
    pub const encoded_len = 4;

    session_id: u8,
    stream_id: u8,
    sequence_nr: u16,

    pub fn encode(self: MessageHeader, out: []u8) !void {
        if (out.len < encoded_len) return error.BufferTooSmall;
        out[0] = self.session_id;
        out[1] = self.stream_id;
        writeU16Le(out[2..4], self.sequence_nr);
    }

    pub fn decode(bytes: []const u8) !MessageHeader {
        if (bytes.len < encoded_len) return error.ShortMessage;
        return .{
            .session_id = bytes[0],
            .stream_id = bytes[1],
            .sequence_nr = readU16Le(bytes[2..4]),
        };
    }
};

pub const Message = struct {
    header: MessageHeader,
    submessage_bytes: []const u8,

    pub fn submessages(self: Message) SubmessageIterator {
        return .{ .remaining = self.submessage_bytes };
    }
};

pub fn decodeMessage(bytes: []const u8) !Message {
    if (bytes.len < MessageHeader.encoded_len) return error.ShortMessage;
    return .{
        .header = try MessageHeader.decode(bytes[0..MessageHeader.encoded_len]),
        .submessage_bytes = bytes[MessageHeader.encoded_len..],
    };
}

pub const SubmessageHeader = struct {
    pub const encoded_len = 4;

    id: SubmessageId,
    flags: u8,
    length: u16,

    pub fn encode(self: SubmessageHeader, out: []u8) !void {
        if (out.len < encoded_len) return error.BufferTooSmall;
        out[0] = @backingInt(self.id);
        out[1] = self.flags;
        writeU16Le(out[2..4], self.length);
    }

    pub fn decode(bytes: []const u8) !SubmessageHeader {
        if (bytes.len < encoded_len) return error.ShortSubmessage;
        return .{
            .id = submessageIdFromByte(bytes[0]) orelse return error.UnknownSubmessageId,
            .flags = bytes[1],
            .length = readU16Le(bytes[2..4]),
        };
    }
};

pub const Submessage = struct {
    header: SubmessageHeader,
    payload: []const u8,
    frame: []const u8,
};

pub const SubmessageIterator = struct {
    remaining: []const u8,

    pub fn next(self: *SubmessageIterator) !?Submessage {
        if (self.remaining.len == 0) return null;
        if (self.remaining.len < SubmessageHeader.encoded_len) return error.ShortSubmessage;

        const header = try SubmessageHeader.decode(self.remaining[0..SubmessageHeader.encoded_len]);
        const frame_len = SubmessageHeader.encoded_len + @as(usize, header.length);
        if (self.remaining.len < frame_len) return error.TruncatedSubmessage;

        const frame = self.remaining[0..frame_len];
        self.remaining = self.remaining[frame_len..];
        return .{
            .header = header,
            .payload = frame[SubmessageHeader.encoded_len..],
            .frame = frame,
        };
    }
};

pub const CreateClient = struct {
    pub const payload_len = 14;
    pub const message_len = MessageHeader.encoded_len + SubmessageHeader.encoded_len + payload_len;

    client_key: [4]u8,
    session_id: u8,
    vendor_id: [2]u8 = vendor_id_zenzen,
    sequence_nr: u16 = 0,

    pub fn encodeMessage(self: CreateClient, out: []u8) !usize {
        if (out.len < message_len) return error.BufferTooSmall;

        try (MessageHeader{
            .session_id = session_id_none_without_client_key,
            .stream_id = stream_id_none,
            .sequence_nr = self.sequence_nr,
        }).encode(out[0..4]);

        try (SubmessageHeader{
            .id = .create_client,
            .flags = flag_little_endian | flag_create_reuse | flag_create_replace,
            .length = payload_len,
        }).encode(out[4..8]);

        @memcpy(out[8..12], &xrce_cookie);
        @memcpy(out[12..14], &xrce_version);
        @memcpy(out[14..16], &self.vendor_id);
        @memcpy(out[16..20], &self.client_key);
        out[20] = self.session_id;
        out[21] = 0; // optional properties absent
        return message_len;
    }
};

pub const BaseObjectRequest = struct {
    request_id: RequestId,
    object_id: ObjectId,
};

pub const CreateByReference = struct {
    session_id: u8,
    stream_id: u8 = stream_id_builtin_reliable,
    sequence_nr: u16,
    request_id: RequestId,
    object_prefix: ObjectIdPrefix,
    object_kind: ObjectKind,
    reference: []const u8,
    reuse: bool = true,
    replace: bool = true,
    participant_domain_id: i16 = 0,
    related_object_id: ?ObjectId = null,

    pub const min_payload_len = 12;

    pub fn encodeMessage(self: CreateByReference, out: []u8) !usize {
        if (out.len < MessageHeader.encoded_len + SubmessageHeader.encoded_len) return error.BufferTooSmall;
        if (self.reference.len > 128) return error.ReferenceTooLong;
        if (!objectKindSupportsReference(self.object_kind)) return error.UnsupportedObjectKind;

        const payload_len = try self.encodePayload(out[MessageHeader.encoded_len + SubmessageHeader.encoded_len ..]);
        const message_len = MessageHeader.encoded_len + SubmessageHeader.encoded_len + payload_len;
        if (out.len < message_len) return error.BufferTooSmall;

        try (MessageHeader{
            .session_id = self.session_id,
            .stream_id = self.stream_id,
            .sequence_nr = self.sequence_nr,
        }).encode(out[0..MessageHeader.encoded_len]);

        try (SubmessageHeader{
            .id = .create,
            .flags = flag_little_endian |
                (if (self.reuse) flag_create_reuse else 0) |
                (if (self.replace) flag_create_replace else 0),
            .length = @intCast(payload_len),
        }).encode(out[MessageHeader.encoded_len..][0..SubmessageHeader.encoded_len]);

        return message_len;
    }

    pub fn objectId(self: CreateByReference) ObjectId {
        return objectIdFromPrefix(self.object_prefix, self.object_kind);
    }

    fn encodePayload(self: CreateByReference, out: []u8) !usize {
        var writer = PayloadWriter.init(out);
        try writer.writeBytes(&self.request_id);
        try writer.writeBytes(&self.object_prefix);
        try writer.writeU8(@backingInt(self.object_kind));
        try writer.writeU8(@backingInt(RepresentationFormat.by_reference));
        try writer.writeString(self.reference);

        switch (self.object_kind) {
            .participant => try writer.writeI16(self.participant_domain_id),
            .topic, .publisher, .subscriber, .datawriter, .datareader => {
                const related_object_id = self.related_object_id orelse return error.MissingRelatedObjectId;
                try writer.writeBytes(&related_object_id);
            },
            .application, .qosprofile, .type => {},
            else => return error.UnsupportedObjectKind,
        }

        return writer.pos;
    }
};

pub const DecodedCreate = struct {
    header: MessageHeader,
    submessage: SubmessageHeader,
    request_id: RequestId,
    object_prefix: ObjectIdPrefix,
    object_id: ObjectId,
    object_kind: ObjectKind,
    representation_format: RepresentationFormat,
    reference: []const u8,
    participant_domain_id: ?i16 = null,
    related_object_id: ?ObjectId = null,
};

pub fn decodeCreate(header: MessageHeader, submessage: Submessage) !DecodedCreate {
    const sh = submessage.header;
    if (sh.id != .create) return error.UnexpectedSubmessage;
    if ((sh.flags & flag_little_endian) == 0) return error.UnsupportedEndian;

    var reader = PayloadReader.init(submessage.payload);
    const request_id = try reader.readBytes(2);
    const object_prefix = try reader.readBytes(2);
    const object_kind = objectKindFromByte(try reader.readU8()) orelse return error.UnknownObjectKind;
    const representation_format = representationFormatFromByte(try reader.readU8()) orelse return error.UnknownRepresentationFormat;
    if (representation_format != .by_reference) return error.UnsupportedRepresentationFormat;
    if (!objectKindSupportsReference(object_kind)) return error.UnsupportedObjectKind;

    const reference = try reader.readString();
    var participant_domain_id: ?i16 = null;
    var related_object_id: ?ObjectId = null;

    switch (object_kind) {
        .participant => participant_domain_id = try reader.readI16(),
        .topic, .publisher, .subscriber, .datawriter, .datareader => related_object_id = (try reader.readBytes(2)).*,
        .application, .qosprofile, .type => {},
        else => return error.UnsupportedObjectKind,
    }

    if (reader.remaining() != 0) return error.TrailingCreatePayloadBytes;

    return .{
        .header = header,
        .submessage = sh,
        .request_id = request_id.*,
        .object_prefix = object_prefix.*,
        .object_id = objectIdFromPrefix(object_prefix.*, object_kind),
        .object_kind = object_kind,
        .representation_format = representation_format,
        .reference = reference,
        .participant_domain_id = participant_domain_id,
        .related_object_id = related_object_id,
    };
}

pub fn decodeCreateMessage(bytes: []const u8) !DecodedCreate {
    const message = try decodeMessage(bytes);
    var iterator = message.submessages();
    const submessage = (try iterator.next()) orelse return error.ShortSubmessage;
    return decodeCreate(message.header, submessage);
}

pub const DecodedCreateClient = struct {
    header: MessageHeader,
    submessage: SubmessageHeader,
    client_key: [4]u8,
    session_id: u8,
    vendor_id: [2]u8,
};

pub fn decodeCreateClient(header: MessageHeader, submessage: Submessage) !DecodedCreateClient {
    const sh = submessage.header;
    if (sh.id != .create_client) return error.UnexpectedSubmessage;
    if (sh.length != CreateClient.payload_len) return error.InvalidSubmessageLength;
    if ((sh.flags & flag_little_endian) == 0) return error.UnsupportedEndian;

    const payload = submessage.payload;
    if (payload.len < CreateClient.payload_len) return error.ShortSubmessage;
    if (!std.mem.eql(u8, payload[0..4], &xrce_cookie)) return error.InvalidXrceCookie;
    if (!std.mem.eql(u8, payload[4..6], &xrce_version)) return error.UnsupportedXrceVersion;
    if (payload[13] != 0) return error.PropertiesNotSupported;

    return .{
        .header = header,
        .submessage = sh,
        .client_key = payload[8..12].*,
        .session_id = payload[12],
        .vendor_id = payload[6..8].*,
    };
}

pub fn decodeCreateClientMessage(bytes: []const u8) !DecodedCreateClient {
    const message = try decodeMessage(bytes);
    var iterator = message.submessages();
    const submessage = (try iterator.next()) orelse return error.ShortSubmessage;
    return decodeCreateClient(message.header, submessage);
}

pub const WriteData = struct {
    session_id: u8,
    stream_id: u8 = stream_id_builtin_reliable,
    sequence_nr: u16,
    request_id: RequestId,
    object_id: ObjectId,
    serialized_data: []const u8,

    pub fn encodeMessage(self: WriteData, out: []u8) !usize {
        const payload_len = 4 + self.serialized_data.len;
        const message_len = MessageHeader.encoded_len + SubmessageHeader.encoded_len + payload_len;
        if (out.len < message_len) return error.BufferTooSmall;

        try (MessageHeader{
            .session_id = self.session_id,
            .stream_id = self.stream_id,
            .sequence_nr = self.sequence_nr,
        }).encode(out[0..MessageHeader.encoded_len]);

        try (SubmessageHeader{
            .id = .write_data,
            .flags = flag_little_endian,
            .length = @intCast(payload_len),
        }).encode(out[MessageHeader.encoded_len..][0..SubmessageHeader.encoded_len]);

        @memcpy(out[8..10], &self.request_id);
        @memcpy(out[10..12], &self.object_id);
        @memcpy(out[12..][0..self.serialized_data.len], self.serialized_data);
        return message_len;
    }
};

pub const DecodedWriteData = struct {
    header: MessageHeader,
    submessage: SubmessageHeader,
    request_id: RequestId,
    object_id: ObjectId,
    serialized_data: []const u8,
};

pub fn decodeWriteData(header: MessageHeader, submessage: Submessage) !DecodedWriteData {
    const sh = submessage.header;
    if (sh.id != .write_data) return error.UnexpectedSubmessage;
    if ((sh.flags & flag_little_endian) == 0) return error.UnsupportedEndian;
    if ((sh.flags & flag_write_data_format_mask) != 0) return error.UnsupportedWriteDataFormat;
    if (submessage.payload.len < 4) return error.ShortSubmessage;

    return .{
        .header = header,
        .submessage = sh,
        .request_id = submessage.payload[0..2].*,
        .object_id = submessage.payload[2..4].*,
        .serialized_data = submessage.payload[4..],
    };
}

pub fn decodeWriteDataMessage(bytes: []const u8) !DecodedWriteData {
    const message = try decodeMessage(bytes);
    var iterator = message.submessages();
    const submessage = (try iterator.next()) orelse return error.ShortSubmessage;
    return decodeWriteData(message.header, submessage);
}

pub const Status = struct {
    pub const payload_len = 6;
    pub const message_len = MessageHeader.encoded_len + SubmessageHeader.encoded_len + payload_len;

    session_id: u8,
    stream_id: u8 = stream_id_builtin_reliable,
    sequence_nr: u16,
    request: BaseObjectRequest,
    result: ResultStatus = .{},

    pub fn encodeMessage(self: Status, out: []u8) !usize {
        if (out.len < message_len) return error.BufferTooSmall;

        try (MessageHeader{
            .session_id = self.session_id,
            .stream_id = self.stream_id,
            .sequence_nr = self.sequence_nr,
        }).encode(out[0..MessageHeader.encoded_len]);

        try (SubmessageHeader{
            .id = .status,
            .flags = flag_little_endian,
            .length = payload_len,
        }).encode(out[MessageHeader.encoded_len..][0..SubmessageHeader.encoded_len]);

        @memcpy(out[8..10], &self.request.request_id);
        @memcpy(out[10..12], &self.request.object_id);
        out[12] = @backingInt(self.result.status);
        out[13] = self.result.implementation_status;
        return message_len;
    }
};

pub const DecodedStatus = struct {
    header: MessageHeader,
    submessage: SubmessageHeader,
    related_request: BaseObjectRequest,
    result: ResultStatus,
};

pub fn decodeStatus(header: MessageHeader, submessage: Submessage) !DecodedStatus {
    const sh = submessage.header;
    if (sh.id != .status) return error.UnexpectedSubmessage;
    if (sh.length != Status.payload_len) return error.InvalidSubmessageLength;
    if ((sh.flags & flag_little_endian) == 0) return error.UnsupportedEndian;

    const payload = submessage.payload;
    if (payload.len < Status.payload_len) return error.ShortSubmessage;
    return .{
        .header = header,
        .submessage = sh,
        .related_request = .{
            .request_id = payload[0..2].*,
            .object_id = payload[2..4].*,
        },
        .result = .{
            .status = statusValueFromByte(payload[4]) orelse return error.UnknownStatusValue,
            .implementation_status = payload[5],
        },
    };
}

pub fn decodeStatusMessage(bytes: []const u8) !DecodedStatus {
    const message = try decodeMessage(bytes);
    var iterator = message.submessages();
    const submessage = (try iterator.next()) orelse return error.ShortSubmessage;
    return decodeStatus(message.header, submessage);
}

pub const StatusAgent = struct {
    pub const payload_len = 9;
    pub const message_len = MessageHeader.encoded_len + SubmessageHeader.encoded_len + payload_len;

    session_id: u8,
    sequence_nr: u16 = 0,
    vendor_id: [2]u8 = vendor_id_zenzen,

    pub fn encodeMessage(self: StatusAgent, out: []u8) !usize {
        if (out.len < message_len) return error.BufferTooSmall;

        try (MessageHeader{
            .session_id = self.session_id,
            .stream_id = stream_id_none,
            .sequence_nr = self.sequence_nr,
        }).encode(out[0..4]);

        try (SubmessageHeader{
            .id = .status_agent,
            .flags = flag_little_endian,
            .length = payload_len,
        }).encode(out[4..8]);

        @memcpy(out[8..12], &xrce_cookie);
        @memcpy(out[12..14], &xrce_version);
        @memcpy(out[14..16], &self.vendor_id);
        out[16] = 0; // optional properties absent
        return message_len;
    }
};

pub const DecodedStatusAgent = struct {
    header: MessageHeader,
    submessage: SubmessageHeader,
    vendor_id: [2]u8,
};

pub fn decodeStatusAgent(header: MessageHeader, submessage: Submessage) !DecodedStatusAgent {
    const sh = submessage.header;
    if (sh.id != .status_agent) return error.UnexpectedSubmessage;
    if (sh.length != StatusAgent.payload_len) return error.InvalidSubmessageLength;
    if ((sh.flags & flag_little_endian) == 0) return error.UnsupportedEndian;

    const payload = submessage.payload;
    if (payload.len < StatusAgent.payload_len) return error.ShortSubmessage;
    if (!std.mem.eql(u8, payload[0..4], &xrce_cookie)) return error.InvalidXrceCookie;
    if (!std.mem.eql(u8, payload[4..6], &xrce_version)) return error.UnsupportedXrceVersion;
    if (payload[8] != 0) return error.PropertiesNotSupported;

    return .{
        .header = header,
        .submessage = sh,
        .vendor_id = payload[6..8].*,
    };
}

pub fn decodeStatusAgentMessage(bytes: []const u8) !DecodedStatusAgent {
    const message = try decodeMessage(bytes);
    var iterator = message.submessages();
    const submessage = (try iterator.next()) orelse return error.ShortSubmessage;
    return decodeStatusAgent(message.header, submessage);
}

fn submessageIdFromByte(value: u8) ?SubmessageId {
    return switch (value) {
        0 => .create_client,
        1 => .create,
        2 => .get_info,
        3 => .delete,
        4 => .status_agent,
        5 => .status,
        6 => .info,
        7 => .write_data,
        8 => .read_data,
        9 => .data,
        10 => .acknack,
        11 => .heartbeat,
        12 => .reset,
        13 => .fragment,
        14 => .timestamp,
        15 => .timestamp_reply,
        else => null,
    };
}

pub fn requestIdFromInt(value: u16) RequestId {
    return .{ @truncate(value & 0x00ff), @truncate(value >> 8) };
}

pub fn objectIdFromPrefix(prefix: ObjectIdPrefix, kind: ObjectKind) ObjectId {
    return .{ prefix[0], (prefix[1] & 0xf0) | (@backingInt(kind) & 0x0f) };
}

fn objectKindFromByte(value: u8) ?ObjectKind {
    return switch (value) {
        0x00 => .invalid,
        0x01 => .participant,
        0x02 => .topic,
        0x03 => .publisher,
        0x04 => .subscriber,
        0x05 => .datawriter,
        0x06 => .datareader,
        0x0a => .type,
        0x0b => .qosprofile,
        0x0c => .application,
        0x0d => .agent,
        0x0e => .client,
        0x0f => .other,
        else => null,
    };
}

fn representationFormatFromByte(value: u8) ?RepresentationFormat {
    return switch (value) {
        0x01 => .by_reference,
        0x02 => .as_xml_string,
        0x03 => .in_binary,
        else => null,
    };
}

fn statusValueFromByte(value: u8) ?StatusValue {
    return switch (value) {
        0x00 => .ok,
        0x01 => .ok_matched,
        0x80 => .err_dds_error,
        0x81 => .err_mismatch,
        0x82 => .err_already_exists,
        0x83 => .err_denied,
        0x84 => .err_unknown_reference,
        0x85 => .err_invalid_data,
        0x86 => .err_incompatible,
        0x87 => .err_resources,
        else => null,
    };
}

fn objectKindSupportsReference(kind: ObjectKind) bool {
    return switch (kind) {
        .application, .participant, .publisher, .subscriber, .datawriter, .datareader, .qosprofile, .topic, .type => true,
        else => false,
    };
}

fn writeU16Le(out: []u8, value: u16) void {
    out[0] = @truncate(value & 0x00ff);
    out[1] = @truncate(value >> 8);
}

fn readU16Le(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

fn writeI16Le(out: []u8, value: i16) void {
    writeU16Le(out, @bitCast(value));
}

fn readI16Le(bytes: []const u8) i16 {
    return @bitCast(readU16Le(bytes));
}

fn writeU32Le(out: []u8, value: u32) void {
    out[0] = @truncate(value & 0x000000ff);
    out[1] = @truncate((value >> 8) & 0x000000ff);
    out[2] = @truncate((value >> 16) & 0x000000ff);
    out[3] = @truncate(value >> 24);
}

fn readU32Le(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

const PayloadWriter = struct {
    out: []u8,
    pos: usize = 0,

    fn init(out: []u8) PayloadWriter {
        return .{ .out = out };
    }

    fn ensure(self: PayloadWriter, len: usize) !void {
        if (self.pos + len > self.out.len) return error.BufferTooSmall;
    }

    fn alignTo(self: *PayloadWriter, boundary: usize) !void {
        const rem = self.pos % boundary;
        if (rem == 0) return;
        const pad = boundary - rem;
        try self.ensure(pad);
        @memset(self.out[self.pos..][0..pad], 0);
        self.pos += pad;
    }

    fn writeBytes(self: *PayloadWriter, bytes: []const u8) !void {
        try self.ensure(bytes.len);
        @memcpy(self.out[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    fn writeU8(self: *PayloadWriter, value: u8) !void {
        try self.ensure(1);
        self.out[self.pos] = value;
        self.pos += 1;
    }

    fn writeI16(self: *PayloadWriter, value: i16) !void {
        try self.alignTo(2);
        try self.ensure(2);
        writeI16Le(self.out[self.pos..][0..2], value);
        self.pos += 2;
    }

    fn writeU32(self: *PayloadWriter, value: u32) !void {
        try self.alignTo(4);
        try self.ensure(4);
        writeU32Le(self.out[self.pos..][0..4], value);
        self.pos += 4;
    }

    fn writeString(self: *PayloadWriter, value: []const u8) !void {
        if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidString;
        try self.writeU32(@intCast(value.len + 1));
        try self.writeBytes(value);
        try self.writeU8(0);
    }
};

const PayloadReader = struct {
    data: []const u8,
    pos: usize = 0,

    fn init(data: []const u8) PayloadReader {
        return .{ .data = data };
    }

    fn remaining(self: PayloadReader) usize {
        return if (self.pos < self.data.len) self.data.len - self.pos else 0;
    }

    fn alignTo(self: *PayloadReader, boundary: usize) !void {
        const rem = self.pos % boundary;
        if (rem != 0) self.pos += boundary - rem;
        if (self.pos > self.data.len) return error.EndOfStream;
    }

    fn readBytes(self: *PayloadReader, comptime len: usize) !*const [len]u8 {
        if (self.pos + len > self.data.len) return error.EndOfStream;
        const bytes = self.data[self.pos..][0..len];
        self.pos += len;
        return bytes;
    }

    fn readU8(self: *PayloadReader) !u8 {
        return (try self.readBytes(1))[0];
    }

    fn readI16(self: *PayloadReader) !i16 {
        try self.alignTo(2);
        return readI16Le(try self.readBytes(2));
    }

    fn readU32(self: *PayloadReader) !u32 {
        try self.alignTo(4);
        return readU32Le(try self.readBytes(4));
    }

    fn readString(self: *PayloadReader) ![]const u8 {
        const wire_len = try self.readU32();
        if (wire_len == 0) return error.InvalidString;
        if (wire_len > self.remaining()) return error.EndOfStream;
        const len: usize = @intCast(wire_len);
        const bytes = self.data[self.pos..][0..len];
        self.pos += len;
        if (bytes[bytes.len - 1] != 0) return error.InvalidString;
        return bytes[0 .. bytes.len - 1];
    }
};

test "message header round trip" {
    var buf: [4]u8 = undefined;
    try (MessageHeader{ .session_id = 0x80, .stream_id = 0x00, .sequence_nr = 0x1234 }).encode(&buf);
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x00, 0x34, 0x12 }, &buf);

    const got = try MessageHeader.decode(&buf);
    try std.testing.expectEqual(@as(u8, 0x80), got.session_id);
    try std.testing.expectEqual(@as(u16, 0x1234), got.sequence_nr);
}

test "message iterator parses multiple submessages" {
    var create: [CreateClient.message_len]u8 = undefined;
    _ = try (CreateClient{
        .client_key = .{ 0xaa, 0xbb, 0xcc, 0xdd },
        .session_id = 0x81,
        .sequence_nr = 3,
    }).encodeMessage(&create);

    var message: [MessageHeader.encoded_len + SubmessageHeader.encoded_len + (SubmessageHeader.encoded_len + CreateClient.payload_len)]u8 = undefined;
    @memcpy(message[0..MessageHeader.encoded_len], create[0..MessageHeader.encoded_len]);
    try (SubmessageHeader{
        .id = .timestamp,
        .flags = flag_little_endian,
        .length = 0,
    }).encode(message[4..8]);
    @memcpy(message[8..], create[4..]);

    const decoded = try decodeMessage(&message);
    var iterator = decoded.submessages();

    const timestamp = (try iterator.next()).?;
    try std.testing.expectEqual(SubmessageId.timestamp, timestamp.header.id);
    try std.testing.expectEqual(@as(usize, 0), timestamp.payload.len);

    const create_submessage = (try iterator.next()).?;
    try std.testing.expectEqual(SubmessageId.create_client, create_submessage.header.id);
    try std.testing.expectEqual(@as(usize, CreateClient.payload_len), create_submessage.payload.len);
    try std.testing.expect((try iterator.next()) == null);
}

test "message iterator rejects truncated submessage payload" {
    var message: [MessageHeader.encoded_len + SubmessageHeader.encoded_len + 1]u8 = undefined;
    try (MessageHeader{
        .session_id = session_id_none_without_client_key,
        .stream_id = stream_id_none,
        .sequence_nr = 1,
    }).encode(message[0..4]);
    try (SubmessageHeader{
        .id = .create_client,
        .flags = flag_little_endian,
        .length = CreateClient.payload_len,
    }).encode(message[4..8]);
    message[8] = 0;

    const decoded = try decodeMessage(&message);
    var iterator = decoded.submessages();
    try std.testing.expectError(error.TruncatedSubmessage, iterator.next());
}

test "create client encode/decode" {
    var buf: [CreateClient.message_len]u8 = undefined;
    const n = try (CreateClient{
        .client_key = .{ 0x22, 0x33, 0x44, 0x55 },
        .session_id = 0xdd,
        .vendor_id = .{ 0x0f, 0x0f },
    }).encodeMessage(&buf);

    try std.testing.expectEqual(@as(usize, CreateClient.message_len), n);
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x00, 0x00, 0x00 }, buf[0..4]);
    try std.testing.expectEqual(@backingInt(SubmessageId.create_client), buf[4]);
    try std.testing.expectEqual(flag_little_endian | flag_create_reuse | flag_create_replace, buf[5]);
    try std.testing.expectEqual(@as(u16, CreateClient.payload_len), readU16Le(buf[6..8]));

    const got = try decodeCreateClientMessage(&buf);
    try std.testing.expectEqualSlices(u8, &.{ 0x22, 0x33, 0x44, 0x55 }, &got.client_key);
    try std.testing.expectEqual(@as(u8, 0xdd), got.session_id);
    try std.testing.expectEqualSlices(u8, &.{ 0x0f, 0x0f }, &got.vendor_id);
}

test "create by reference encodes and decodes application" {
    var buf: [128]u8 = undefined;
    const n = try (CreateByReference{
        .session_id = 0x81,
        .sequence_nr = 7,
        .request_id = .{ 0xaa, 0x01 },
        .object_prefix = .{ 0xdd, 0xd0 },
        .object_kind = .application,
        .reference = "DemoApp",
    }).encodeMessage(&buf);

    try std.testing.expectEqual(@as(u8, 0x81), buf[0]);
    try std.testing.expectEqual(@backingInt(SubmessageId.create), buf[4]);
    try std.testing.expectEqual(flag_little_endian | flag_create_reuse | flag_create_replace, buf[5]);

    const got = try decodeCreateMessage(buf[0..n]);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0x01 }, &got.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 0xdd, 0xd0 }, &got.object_prefix);
    try std.testing.expectEqualSlices(u8, &.{ 0xdd, 0xdc }, &got.object_id);
    try std.testing.expectEqual(ObjectKind.application, got.object_kind);
    try std.testing.expectEqual(RepresentationFormat.by_reference, got.representation_format);
    try std.testing.expectEqualSlices(u8, "DemoApp", got.reference);
}

test "create by reference encodes participant domain id" {
    var buf: [160]u8 = undefined;
    const n = try (CreateByReference{
        .session_id = 0x81,
        .sequence_nr = 7,
        .request_id = .{ 0xaa, 0x01 },
        .object_prefix = .{ 0xdd, 0xd0 },
        .object_kind = .participant,
        .reference = "MyLibrary::MyParticipant",
        .participant_domain_id = 3,
    }).encodeMessage(&buf);

    const got = try decodeCreateMessage(buf[0..n]);
    try std.testing.expectEqual(ObjectKind.participant, got.object_kind);
    try std.testing.expectEqual(@as(?i16, 3), got.participant_domain_id);
    try std.testing.expectEqualSlices(u8, &.{ 0xdd, 0xd1 }, &got.object_id);
    try std.testing.expectEqualSlices(u8, "MyLibrary::MyParticipant", got.reference);
}

test "create by reference encodes related object id for datawriter" {
    var buf: [160]u8 = undefined;
    const n = try (CreateByReference{
        .session_id = 0x81,
        .sequence_nr = 7,
        .request_id = .{ 0xaa, 0x01 },
        .object_prefix = .{ 0x10, 0x50 },
        .object_kind = .datawriter,
        .reference = "MyLibrary::CounterStatusWriter",
        .related_object_id = .{ 0x10, 0x33 },
    }).encodeMessage(&buf);

    const got = try decodeCreateMessage(buf[0..n]);
    try std.testing.expectEqual(ObjectKind.datawriter, got.object_kind);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x33 }, &got.related_object_id.?);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x55 }, &got.object_id);
}

test "write data encode/decode" {
    var buf: [128]u8 = undefined;
    const n = try (WriteData{
        .session_id = 0x81,
        .sequence_nr = 12,
        .request_id = .{ 0xba, 0x01 },
        .object_id = .{ 0x10, 0x55 },
        .serialized_data = &.{ 0x00, 0x01, 0x02, 0x03 },
    }).encodeMessage(&buf);

    try std.testing.expectEqual(@backingInt(SubmessageId.write_data), buf[4]);
    try std.testing.expectEqual(flag_little_endian, buf[5]);

    const got = try decodeWriteDataMessage(buf[0..n]);
    try std.testing.expectEqual(@as(u8, 0x81), got.header.session_id);
    try std.testing.expectEqualSlices(u8, &.{ 0xba, 0x01 }, &got.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x55 }, &got.object_id);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x01, 0x02, 0x03 }, got.serialized_data);
}

test "status encode/decode" {
    var buf: [Status.message_len]u8 = undefined;
    const n = try (Status{
        .session_id = 0x81,
        .sequence_nr = 9,
        .request = .{
            .request_id = .{ 0xaa, 0x01 },
            .object_id = .{ 0xdd, 0xdc },
        },
        .result = .{ .status = .ok_matched, .implementation_status = 2 },
    }).encodeMessage(&buf);

    try std.testing.expectEqual(@as(usize, Status.message_len), n);
    try std.testing.expectEqual(@backingInt(SubmessageId.status), buf[4]);

    const got = try decodeStatusMessage(&buf);
    try std.testing.expectEqual(@as(u8, 0x81), got.header.session_id);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0x01 }, &got.related_request.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 0xdd, 0xdc }, &got.related_request.object_id);
    try std.testing.expectEqual(StatusValue.ok_matched, got.result.status);
    try std.testing.expectEqual(@as(u8, 2), got.result.implementation_status);
}

test "status agent encode/decode" {
    var buf: [StatusAgent.message_len]u8 = undefined;
    const n = try (StatusAgent{ .session_id = 0xdd, .sequence_nr = 1 }).encodeMessage(&buf);

    try std.testing.expectEqual(@as(usize, StatusAgent.message_len), n);
    try std.testing.expectEqual(@backingInt(SubmessageId.status_agent), buf[4]);

    const got = try decodeStatusAgentMessage(&buf);
    try std.testing.expectEqual(@as(u8, 0xdd), got.header.session_id);
    try std.testing.expectEqual(@as(u16, 1), got.header.sequence_nr);
    try std.testing.expectEqualSlices(u8, &vendor_id_zenzen, &got.vendor_id);
}
