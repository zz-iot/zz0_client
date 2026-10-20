# Independent XRCE interoperability

This host-only test runs `zz0_client` against eProsima Micro XRCE-DDS Agent
v3.0.1 backed by Fast DDS. A separate session using eProsima's C client library
and Micro-CDR receives and validates `{counter=42, board="zig", payload=[1,2,3]}`.
No zz0 codec is used by the independent agent or observer.

The test covers no-properties/keyless-session login, little-endian by-reference
participant/topic/writer creation, empty-XML publisher creation, missing-reference
error reporting, and bounded unfragmented best-effort writes. Missing profiles
produce ERR_DDS_ERROR in this pinned agent. Receipt is checked by the observer;
this peer test does not assert WRITE_DATA success statuses. The standard requires
a STATUS response (§8.3.5.8); the pinned peer's behavior does not weaken that rule. The topic is
NO_KEY: this test does not validate DDS keyed-instance semantics.

On Linux, install CMake, a C/C++ compiler, OpenSSL development headers and
`libfoonathan-memory-dev`, then run from this repository with Zig 0.17.0:

```sh
python3 interop/build_peers.py --work /tmp/zz0-peers --agent
zig build interop-client -Doptimize=ReleaseSafe
python3 interop/run.py --client zig-out/bin/zz0_interop_client \
  --prefix /tmp/zz0-peers/install --logs /tmp/zz0-client-interop
```

All upstream sources and non-system dependency revisions are pinned in
`build_peers.py`; Fast DDS submodules follow its pinned gitlinks. There are no
upstream protocol patches. Peer source/build/install trees stay outside the
repo. The first build is substantial; CI caches it by build-script hash.
CMake still checks the cached build on subsequent runs. CI runs this test on
pushes to main, pull requests, manual dispatch and weekly, and uploads process
logs even on failure. Localhost UDP and DDS sockets are required; inability to
open sockets is a test failure, not a skip. All peer processes have deadlines
and are stopped on success or failure.

`src/fixtures/` retains independent wire packets for fast unit regressions.
Unit tests and live peers serve different purposes; both remain enabled.

This is a deliberately limited profile, not general XRCE conformance. Reliable
streams/ACKs, loss recovery, fragmentation, keyed message headers, optional login
properties, big-endian payloads, deletion and subscriptions in zz0_client are
outside this test. Requests are sent individually, one per datagram. The SDK
observer's read support does not imply subscription support in zz0_client.

The existing demo still uses a legacy by-reference publisher representation;
this test selects eProsima's empty-XML publisher convention, which does not satisfy
the standard's publisher-element XML requirement. Session `output_stream_id`
defaults to best-effort 0x01; reliable streams remain unimplemented.

## Normative audit

See [spec-audit.md](spec-audit.md) for the clause-by-clause review and remaining
gaps. The codec defaults to the published OMG login layout. This test explicitly
selects `HandshakeEncoding.eprosima_v3` for the extra MTU/result fields.
