# Zenzen Zero Client

Reusable Zig DDS-XRCE client core for host tests and MicroZig firmware.

The package is intentionally kept compatible with Zig 0.15.1 so the same core
can be imported by MicroZig applications.

Current host-side smoke coverage includes a UDP `CREATE_CLIENT` ping helper
that expects a `STATUS_AGENT` reply. Embedded transports should use the same
transport interface rather than depending on the host UDP module directly.

The client session layer now also encodes by-reference `CREATE` requests and
tracks their `STATUS` replies through transport-agnostic request ids. It also
encodes XRCE `WRITE_DATA` requests and matches the resulting `STATUS` replies
against the pending request/object pair.

## Build and use

Run `zig build test` with Zig 0.15.1 for the protocol, session, transport, and
host UDP tests. The transport-neutral core is also consumed by the Zig 0.16.0
agent; `host_udp` is only exposed when compiling with Zig 0.15.x.

The package exports the `zz0_client` module. With a dependency named
`zz0_client`, add it to an application module in `build.zig`:

```zig
const client = b.dependency("zz0_client", .{ .target = target, .optimize = optimize });
app.addImport("zz0_client", client.module("zz0_client"));
```

Application code can then use `@import("zz0_client")`.
