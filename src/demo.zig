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
