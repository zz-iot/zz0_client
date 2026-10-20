# Independent XRCE wire fixtures

Captured from the live eProsima v3.0.1 client/agent exchange on 2026-10-20,
using `interop/observer.c` and `interop/agent.refs`. The source was the agent's
verbosity-6 UDP hex log; these packets were not emitted by zz0's codec.

- `eprosima-create-client.bin`: client key 55667788, session 81, MTU 508.
- `eprosima-status-agent.bin`: successful result, vendor 010f, no properties.
- `eprosima-participant.bin`: request 000a, object 0011, domain 0, by reference.
- `eprosima-topic.bin`: request 000b, object 0012, parent 0011, by reference.

Exact peer/dependency revisions are in `../../interop/build_peers.py`.
The live CI tests complement these deterministic regression fixtures.

`omg-create-client.bin` and `omg-status-agent.bin` are independently authored
known-answer packets derived from the published OMG IDL and the resolved
[DDSXRCE-4](https://issues.omg.org/issues/DDSXRCE-4) layouts (22/17 total bytes
with no properties or header client key). They were not captured from eProsima.
The eProsima packets require explicit `eprosima_v3` handshake selection;
regressions ensure neither encoding is silently accepted as the other.
