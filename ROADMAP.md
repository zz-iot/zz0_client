# Roadmap

The client currently implements a transport-neutral DDS-XRCE subset used by the
Pico demo. This roadmap describes intended development order, not release
commitments or an assertion of XRCE conformance.

## Current state

- CREATE_CLIENT / STATUS_AGENT session establishment.
- By-reference CREATE and WRITE_DATA encoding, with request/object matching for
  STATUS replies.
- A transport interface, host UDP implementation and protocol/session tests.
- Integration with MicroZig firmware on Pico WH and Pico 2 WH.

The Pico application supplies timeout, backoff and session/resource recreation
logic. These are application recovery mechanisms, not a complete implementation
of XRCE reliable streams. The current scope is publishing, not subscriptions.

## 1. Establish interoperability and scope

The pinned eProsima agent/observer test and independently captured wire fixtures
now cover the limited publishing subset documented in `interop/README.md`. CI
configuration is included; remote CI execution is not yet evidence. The normative review and remaining compliance
gaps are recorded in `interop/spec-audit.md`; eProsima-specific login encoding
is opt-in. Remaining:

- Maintain a support matrix against the OMG DDS-XRCE specification, documenting
  supported messages, representations, session/stream behavior and limits.
- Exercise this client against an independent agent, starting with session
  establishment, by-reference entity creation and writes.
- Add independent wire fixtures and tests for unsupported or malformed replies,
  stale responses and message/request matching.
- Keep transport-neutral behavior usable on embedded targets without host I/O.

Exit criterion: the documented subset works with an independent agent, with
regressions for discrepancies found. Successful exchanges with zz0_agent alone
are not sufficient evidence of interoperability.

## 2. Demonstrate real DDS publishing

- Coordinate with zz0_agent's known-type zzdds bridge.
- Verify generated samples reach an independent DDS subscriber.
- Document the difference between agent acceptance and DDS delivery.
- Preserve bounded memory use and simultaneous-client operation on both boards.

This milestone can use generated types and configured entity references; it does
not require general XTypes DynamicData support in the client or agent.

## 3. Strengthen sessions, delivery and resource lifecycle

- Define reusable recovery APIs so applications need less custom session logic.
- Test packet loss, duplication, reordering, delayed responses and sequence wrap.
- Implement reliable streams, acknowledgements, retransmission and duplicate
  handling for the supported profile, coordinated with the agent.
- Add entity/session deletion and explicit cleanup behavior.
- Make memory, queue and payload limits configurable and documented.

Exit criterion: deterministic fault-injection tests demonstrate recovery and
bounded resource use; delivery guarantees are stated explicitly.

## 4. Receive DDS data

- Add datareader creation, read requests and DATA delivery handling.
- Provide bounded buffering or callback delivery suitable for microcontrollers.
- Support cancellation, disconnect/reconnect and resource recreation.
- Validate a bidirectional application on both Pico targets.

## Later, driven by applications

Fragmentation, broader entity representations, additional transports and QoS
options should follow actual use cases. Keep protocol/session code independent
of board-specific WiFi, USB logging and application retry policy. Extensive
hardware soak testing is useful confidence work alongside protocol tests.

## References

- [OMG DDS-XRCE 1.0](https://www.omg.org/spec/DDS-XRCE/1.0)
- Companion roadmap: `ROADMAP.md` in the `zz0_agent` repository
- [eProsima Micro XRCE-DDS Agent](https://github.com/eProsima/Micro-XRCE-DDS-Agent)
