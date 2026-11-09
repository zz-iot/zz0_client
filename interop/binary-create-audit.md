# Binary CREATE encoding checkpoint

2026-10-30. The project explicitly defaults to XTypes 1.3 XCDR2. Publisher/writer
binary CREATE, DELETE and RESET now have bounded little-endian codecs and
independently hand-authored wire fixtures.
They do not establish ordering, reliability or full session lifecycle support.

## Sources and discrepancies

- [DDS-XRCE 1.0](https://www.omg.org/spec/DDS-XRCE/1.0/PDF), normative reference
  section, sections 7.7 and 8.3.5.4/13, and Annex B.2.2/3.
- [DDS-XRCE normative IDL](https://www.omg.org/spec/DDS-XRCE/20190301/dds_xrce_types.idl),
  binary representation unions and publisher/writer binary definitions.
- [XTypes 1.2](https://www.omg.org/spec/DDS-XTypes/1.2/PDF), section 7.4.3.4.1.
- [OMG DDSXTY13-29](https://issues.omg.org/issues/DDSXTY13-29), the resolved change
  removing the delimiter endianness bit in XTypes 1.3.

XRCE references XTypes 1.2. Its delimiter header has an endianness bit, unlike
modern DDS XCDR2. XRCE Annex B.2.2/3 demonstrates that older header and omits the
outer octet-sequence length required by its IDL. These are separate discrepancies.
The writer QoS annotation also contains a spelling error in the published IDL.
A byte dump from one source must not silently override the others.

## Local implementation evidence

The zidl runtime's `packages/zidl-rt/src/cdr.zig` writes a delimiter as a byte
count, without that older endianness bit. The agent/backend uses modern RTPS
encapsulation identifiers when framing application samples. Existing CounterStatus
interop does not exercise appendable/mutable application aggregates, so it cannot
qualify the older delimiter rules or a binary CREATE decoder.

## Encoding decision: XTypes 1.3

Use modern XTypes 1.3 XCDR2 for protocol binary records and application samples,
aligned with zidl/zzdds. `xrce.xcdr_revision` makes the choice explicit. Retain the
IDL's outer octet-sequence length, rather than the inconsistent example layout.
This is a documented project interpretation, not a claim that XRCE 1.0 normatively
references XTypes 1.3 or that an unpublished XRCE revision guarantees it.

Historical 1.2 delimiter headers are rejected explicitly by the binary decoder;
there is no format sniffing or historical serialization mode in zidl's XRCE
profile. Old-peer support can be added under an explicit compatibility mode when
required and tested independently. Future XTypes 1.4 adoption will follow formal
publication and an implementation review, in step with zzdds.

The constrained Pico type profile remains final/bounded. Generated appendable,
nested and mutable fixtures use zidl's full profile and assert modern wire bytes;
they also exercise an appendable sample through the agent packet adapter.
This extends coverage beyond CounterStatus's common encoding subset. Independent
peer and real DDS forwarding acceptance are still required separately.

Publisher/writer decoding must also bound outer sequence lengths, strings, optional
flags, delimiter boundaries and trailing bytes. Reject unsupported QoS explicitly.
The implemented subset covers publisher optional names and writer topic names,
with QoS absent. Tests cover independent byte fixtures, truncation, invalid lengths,
optional flags, unsupported QoS and the rejected historical delimiter bit. Add
independently produced peer packets before claiming native binary interoperability. A local round trip alone is not an oracle. Record deviations in
the test fixture notes and require explicit compatibility selection.

## Completed lifecycle codecs

`DeleteRequest` encodes one BaseObjectRequest and `decodeDelete` preserves its
request/object ID bytes. `Reset` has an empty payload. These codecs require
little-endian submessages, reject unsupported flag bits and enforce exact payload
lengths. Encoders check output capacity before writing. Their fixtures are manually
authored from the field layout, not captured from the local encoder.

The companion agent branch now implements per-client UDP ownership, repeated
and changed-session handling, RESET and ProxyClient deletion. These shared codecs
do not themselves implement that agent lifecycle, reliable streams or general
XRCE conformance; see the agent's backend evidence for its tested subset.
