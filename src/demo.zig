const session = @import("session.zig");
const xrce = @import("xrce.zig");

pub const ReferenceCreate = struct {
    label: []const u8,
    object_prefix: xrce.ObjectIdPrefix,
    object_id: xrce.ObjectId,
    object_kind: xrce.ObjectKind,
    reference: []const u8,
    participant_domain_id: ?i16 = null,
    related_object_id: ?xrce.ObjectId = null,
};

pub const participant = ReferenceCreate{
    .label = "participant",
    .object_prefix = .{ 0x10, 0x10 },
    .object_id = xrce.objectIdFromPrefix(.{ 0x10, 0x10 }, .participant),
    .object_kind = .participant,
    .reference = "MyLibrary::CounterParticipant",
    .participant_domain_id = 0,
};

pub const topic = ReferenceCreate{
    .label = "topic",
    .object_prefix = .{ 0x10, 0x20 },
    .object_id = xrce.objectIdFromPrefix(.{ 0x10, 0x20 }, .topic),
    .object_kind = .topic,
    .reference = "MyLibrary::CounterStatusTopic",
    .related_object_id = participant.object_id,
};

pub const publisher = ReferenceCreate{
    .label = "publisher",
    .object_prefix = .{ 0x10, 0x30 },
    .object_id = xrce.objectIdFromPrefix(.{ 0x10, 0x30 }, .publisher),
    .object_kind = .publisher,
    .reference = "MyLibrary::CounterPublisher",
    .related_object_id = participant.object_id,
};

pub const datawriter = ReferenceCreate{
    .label = "datawriter",
    .object_prefix = .{ 0x10, 0x50 },
    .object_id = xrce.objectIdFromPrefix(.{ 0x10, 0x50 }, .datawriter),
    .object_kind = .datawriter,
    .reference = "MyLibrary::CounterStatusWriter",
    .related_object_id = publisher.object_id,
};

pub const publish_path_entities = [_]ReferenceCreate{
    participant,
    topic,
    publisher,
    datawriter,
};

/// Standard CREATE path: participant/topic references, binary publisher/writer.
/// ReferenceCreate.reference for publisher/writer is retained for explicit peer
/// compatibility fixtures, not used by this firmware path.
pub fn encodeCreate(client: *session.ClientSession, out: []u8, entity: ReferenceCreate) ![]const u8 {
    return switch (entity.object_kind) {
        .publisher, .datawriter => client.encodeCreateBinary(out, .{
            .object_prefix = entity.object_prefix,
            .parent = entity.related_object_id orelse return error.MissingParent,
            .definition = if (entity.object_kind == .publisher)
                .{ .publisher = "pub" }
            else
                .{ .datawriter = "CounterStatusTopic" },
        }),
        else => client.encodeCreateByReference(out, .{
            .object_prefix = entity.object_prefix,
            .object_kind = entity.object_kind,
            .reference = entity.reference,
            .participant_domain_id = entity.participant_domain_id orelse 0,
            .related_object_id = entity.related_object_id,
            .replace = false,
        }),
    };
}

test "firmware CREATE path uses standard representations and tracks requests" {
    const std = @import("std");
    var client = session.ClientSession.init(.{ .client_key = .{ 1, 2, 3, 4 }, .session_id = 0x81 });
    var out: [256]u8 = undefined;
    for (publish_path_entities, 0..) |entity, i| {
        const bytes = try encodeCreate(&client, &out, entity);
        const decoded = try xrce.decodeCreateMessage(bytes);
        try std.testing.expectEqual(if (i < 2) xrce.RepresentationFormat.by_reference else .in_binary, decoded.representation_format);
        try std.testing.expectEqualSlices(u8, &entity.object_id, &client.pending_request.?.object_id);
        try std.testing.expectEqualSlices(u8, &decoded.request_id, &client.pending_request.?.request_id);
        if (i == 2) try std.testing.expectEqualStrings("pub", decoded.representation.in_binary.publisher.?);
        if (i == 3) try std.testing.expectEqualStrings("CounterStatusTopic", decoded.representation.in_binary.datawriter);
    }
}
