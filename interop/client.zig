const std = @import("std");
const zz0 = @import("zz0_client");
const xrce = zz0.xrce;

fn exchange(udp: *zz0.host_udp.UdpTransport, session: *zz0.session.ClientSession, bytes: []const u8, expected: xrce.StatusValue) !void {
    try udp.sendBytes(bytes, .none);
    var buf: [512]u8 = undefined;
    const incoming = try udp.recvMessage(&buf, 2000);
    const event = try session.handleDatagram(incoming.bytes);
    switch (event) {
        .status => |status| if (status.result.status != expected) {
            std.debug.print("expected {s}, got {s}\n", .{ @tagName(expected), @tagName(status.result.status) });
            return error.UnexpectedStatus;
        },
        else => return error.ExpectedStatus,
    }
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.iterateAllocator(init.minimal.args, std.heap.page_allocator);
    defer args.deinit();
    _ = args.next();
    const port = try std.fmt.parseInt(u16, args.next() orelse return error.PortRequired, 10);
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    var udp = try zz0.host_udp.UdpTransport.init(threaded.io(), .{ .ip4 = .loopback(port) });
    defer udp.deinit();
    var session = zz0.session.ClientSession.init(.{ .client_key = .{ 0x11, 0x22, 0x33, 0x44 }, .session_id = 0x81, .handshake_encoding = .eprosima_v3, .output_stream_id = xrce.stream_id_builtin_best_effort });
    _ = try udp.openSession(&session, 2000);
    std.debug.print("SESSION OK\n", .{});
    var out: [512]u8 = undefined;
    for (zz0.demo.publish_path_entities) |entity| {
        const bytes = try session.encodeCreateByReference(&out, .{
            .object_prefix = entity.object_prefix,
            .object_kind = entity.object_kind,
            .reference = if (entity.object_kind == .publisher) "" else entity.reference,
            .representation_format = if (entity.object_kind == .publisher) .as_xml_string else .by_reference,
            .participant_domain_id = 0,
            .related_object_id = entity.related_object_id,
        });
        try exchange(&udp, &session, bytes, .ok);
        std.debug.print("CREATE {s} OK\n", .{entity.label});
    }
    const bad = try session.encodeCreateByReference(&out, .{ .object_prefix = .{ 0x20, 0x10 }, .object_kind = .participant, .reference = "MissingParticipant" });
    // This pinned agent maps a missing DDS profile to ERR_DDS_ERROR.
    try exchange(&udp, &session, bad, .err_dds_error);
    // CDR little-endian CounterStatus {42, "zig", [1,2,3]}, no DDS encapsulation.
    const sample = [_]u8{ 42, 0, 0, 0, 4, 0, 0, 0, 'z', 'i', 'g', 0, 3, 0, 0, 0, 1, 2, 3 };
    // Several bounded sends allow the independent DDS observer time to match.
    for (0..20) |_| {
        const bytes = try session.encodeWriteData(&out, .{ .object_id = zz0.demo.datawriter.object_id, .serialized_data = &sample });
        try udp.sendBytes(bytes, .none);
        try std.Io.sleep(threaded.io(), .fromMilliseconds(100), .awake);
    }
    std.debug.print("WRITE SENT; receipt asserted by independent observer\n", .{});
}
