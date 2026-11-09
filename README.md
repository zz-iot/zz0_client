# Zenzen Zero Client

Reusable Zig DDS-XRCE client core for host tests and MicroZig firmware.

The package requires Zig 0.17.0 for both host applications and MicroZig firmware.

Current host-side smoke coverage includes a UDP `CREATE_CLIENT` ping helper
that expects a `STATUS_AGENT` reply. Embedded transports should use the same
transport interface rather than depending on the host UDP module directly.

The client session layer encodes by-reference and binary `CREATE` requests and
tracks their `STATUS` replies through transport-agnostic request ids. It also
encodes XRCE `WRITE_DATA` requests and matches the resulting `STATUS` replies
against the pending request/object pair.

## Build and use

Run `zig build test` with Zig 0.17.0 for the protocol, session, transport, and
host UDP tests. The transport-neutral core is also consumed by the agent and firmware.
`host_udp` is available on hosted targets; initialize it with a `std.Io` and
`std.Io.net.IpAddress`. The I/O context must outlive the transport.

The package exports the `zz0_client` module. With a dependency named
`zz0_client`, add it to an application module in `build.zig`:

```zig
const client = b.dependency("zz0_client", .{ .target = target, .optimize = optimize });
app.addImport("zz0_client", client.module("zz0_client"));
```

Application code can then use `@import("zz0_client")`.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for current scope, interoperability goals and the
planned path toward DDS bridging, reliable sessions and subscriptions.

## Independent interoperability

See [interop/README.md](interop/README.md) for the pinned eProsima peer test,
local commands, CI workflow and exact scope of the verified subset.

Login encoding defaults to the published OMG 1.0 IDL. An explicit
`HandshakeEncoding.eprosima_v3` option enables the pinned peer's extra login
fields. See [the spec audit](interop/spec-audit.md) for the distinction between
encoding fixes and compatibility conventions. Default request streams are
best-effort (0x01); reliable streams remain unimplemented.

## XCDR2 encoding revision

This project explicitly uses modern **XTypes 1.3 XCDR2**. This agrees with zidl
and zzdds; it does not select the older XTypes 1.2 delimiter format referenced
by XRCE 1.0. The constrained `zidl --profile xrce` limits type features and does
not force XCDR1 or select historical XCDR2. Future historical-peer compatibility
must be explicit; future XTypes 1.4 support will follow formal publication/review.

The Pico demo uses `demo.encodeCreate`: participant/topic references and modern
binary publisher/writer definitions, with REUSE enabled and REPLACE disabled.
Publisher/writer reference names remain only for explicit compatibility fixtures.
