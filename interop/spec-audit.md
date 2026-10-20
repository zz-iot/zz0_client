# DDS-XRCE 1.0 audit of the interoperability changes

Reviewed 2026-10-20 against [formal/20-02-01](https://www.omg.org/spec/DDS-XRCE/1.0/PDF),
the [normative IDL](https://www.omg.org/spec/DDS-XRCE/20190301/dds_xrce_types.idl),
and the resolved [DDSXRCE-4 reduction](https://issues.omg.org/issues/DDSXRCE-4).
Peer success establishes compatibility with the pinned eProsima implementation;
it does not establish an OMG conformance profile.

## Findings and disposition

| Change | Spec evidence | Disposition |
| --- | --- | --- |
| Remove CREATE_CLIENT reuse/replace flags | §8.3.5.1.1 defines no additional flags | Keep. Appendix B's older flags conflict with the normative clause. |
| Append a client MTU | CLIENT_Representation in Annex A and the normative IDL has no MTU | eProsima compatibility only; explicit `eprosima_v3` selection required. |
| Prepend a STATUS_AGENT result | Annex A/IDL contains agent_info only; §8.3.5.5 retains contradictory reply prose | Explicit eProsima compatibility; default follows the IDL and resolved DDSXRCE-4. |
| Encode complete CREATE object IDs | §7.7.6 defines ObjectId construction; Appendix B.2 uses complete IDs | Keep outgoing complete IDs. §7.7.8 also permits a prefix: accept it, derive the resource ID, retain original request bytes for STATUS correlation. |
| Remove sample encapsulation header | §7.7.2 and Appendix B.3.1 show application XCDR bytes directly after the request fields | Keep. Use XCDR2 as required by §7.7.2; current CounterStatus has only ≤4-byte alignment, so its XCDR1/2 bytes happen to match. |
| Empty publisher XML | §7.7.3.8 permits binary/XML, and §7.7.3.8.1 requires a publisher element | Empty XML is an eProsima compatibility convention, not standard publisher XML. The demo's by-reference publisher is also outside these forms. |
| Ignore login response sequence equality | §8.3.2.3 scopes sequence numbers to streams, not request/reply pairs | Keep; a stream sequence is not a request correlation identifier. |
| Expect ERR_DDS_ERROR for a missing eProsima profile | §7.7.7 distinguishes DDS errors from unknown references | Peer-specific expectation only. Keep our unknown-reference mapping. |

The two login divergences are independently reported upstream:
[MTU placement #138](https://github.com/eProsima/Micro-XRCE-DDS/issues/138) and
[extra STATUS_AGENT member #140](https://github.com/eProsima/Micro-XRCE-DDS/issues/140).
DDSXRCE-4 explicitly resolves the property-free message sizes to 22 and 17 bytes;
the eProsima forms are 24 and 19. No automatic format detection or vendor-ID-based
switching is used. The published layout does not supply a result field; the API
returns an absent result rather than inventing one. Encoding a non-success result
with that layout is rejected because the specification does not provide an
unambiguous field for it.

## Tests and public selection

`HandshakeEncoding.omg_1_0` is the default for the codec and ClientSession.
The independent-agent client opts into `eprosima_v3`; the independent-client
agent runner passes `--handshake=eprosima_v3`. Normal agent operation defaults
to `--handshake=omg_1_0`. Unit fixtures independently assert both layouts and
reject cross-decoding; captured eProsima packets are not normative test vectors.
Default request streams now use best-effort ID 0x01, rather than advertising
reliable ID 0x80 without a reliable-stream implementation. This is a correction
of the advertised stream kind, not evidence that stream behavior is complete.

## Existing gaps affecting conformance claims

The following are still open, and are not established by the live tests:

- §8.3.2.3 requires ordering and duplicate suppression even for best-effort streams.
  Client/agent dispatch currently lacks that state; reliable ACK/repair is also absent.
- §7.8.2.1 requires repeat login with the same key/session to preserve the ProxyClient;
  the demo registry instead resets resources. Login rejection/status, minor-version
  negotiation and keyed headers also need a fuller implementation.
- §8.3.3 requires aligned multi-submessage handling. The iterator/dispatch path is
  not complete, and the live tests deliberately send one operation per datagram.
- §8.3.5.8 requires STATUS after WRITE_DATA and a write into DDS. Our agent only
  validates locally; the pinned eProsima test uses independent receipt because its
  success-status behavior differs. Do not generalize either into a weaker standard.
- General XCDR2 type coverage, valid publisher XML/binary creation, deletion and the
  remaining required behaviors of §2's conformance profiles are incomplete.

These gaps do not invalidate the specific encoding corrections above. They do
prevent calling the current demo or the interop CI an OMG-conformant implementation.

## Validation snapshot

After these corrections: client unit tests 24/24 and agent unit tests 23/23
pass in Debug and ReleaseSafe. Both checked-in live eProsima runners pass with
explicit compatibility selection. Demo host checks pass and both Pico firmware
targets build (66/66 build steps). On 2026-10-20 the operator confirmed both
reflashed boards passed simultaneous publishing, decoded sample checks,
agent-restart recovery and WiFi reconnect recovery with the updated agent.
This is operator-reported hardware evidence. Remote CI has not been run.
No conformance profile is inferred from these results.
