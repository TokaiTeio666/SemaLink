# SemaLink DSK Remote Reliability Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with TDD and verification checkpoints.

**Goal:** Connect the real DSK/SoftBus remote semantic path, add reliable evidence paging, and close connection lifecycle leaks without adding NetworkKit TLS.

**Architecture:** Keep DSK/SoftBus as the only transport. Add one runtime ingress dispatcher, use keyed promises for remote task rounds, and isolate page sending/assembly in a small reliability component. Connection classes own their timers, listeners, and pending state.

**Tech Stack:** HarmonyOS NEXT API 24, ArkTS, Hypium, Hvigor.

---

### Task 1: Real remote semantic ingress and round completion

**Files:**
- Modify: `entry/src/main/ets/runtime/AppRuntime.ets`
- Modify: `entry/src/main/ets/communication/tls/Task3TlsCoordinator.ets`
- Modify: `entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets`
- Modify: `entry/src/test/MultiDeviceEndToEnd.test.ets`
- Modify: `entry/src/test/MultiDeviceTaskCoordinator.test.ets`

- [ ] Add a failing test proving an inbound remote `EVIDENCE_BATCH` reaches the active coordinator through the runtime transport.
- [ ] Run the focused tests and observe failure because remote search currently returns an empty array.
- [ ] Add a coordinator ingress callback and keyed round waiters; send complete v2 envelopes for TASK, TSF, and CANCEL.
- [ ] Register the responder/coordinator dispatcher through `Task3TlsCoordinator` and resolve remote rounds on `EVIDENCE_COMPLETE`.
- [ ] Run focused tests, then the full unit test command.

### Task 2: Reliable evidence paging

**Files:**
- Modify: `entry/src/main/ets/protocol/MultiDeviceProtocolModels.ets`
- Modify: `entry/src/main/ets/protocol/MultiDeviceProtocolCodec.ets`
- Modify: `entry/src/main/ets/communication/PeerTaskResponder.ets`
- Modify: `entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets`
- Modify: `entry/src/test/MultiDeviceProtocolCodec.test.ets`
- Modify: `entry/src/test/PeerTaskResponder.test.ets`
- Modify: `entry/src/test/MultiDeviceEndToEnd.test.ets`

- [ ] Add failing tests for page digest validation, duplicate/乱序 page assembly, ACK timeout retry, and retry exhaustion.
- [ ] Run focused tests and confirm the missing reliability behavior.
- [ ] Implement bounded page windows, 1500ms ACK timeout, three attempts, idempotent receive, and terminal cleanup.
- [ ] Use `EVIDENCE_COMPLETE` only after all pages are acknowledged/assembled; report explicit transfer errors.
- [ ] Run focused tests and the full unit test command.

### Task 3: Connection lifecycle and resource cleanup

**Files:**
- Modify: `entry/src/main/ets/communication/PeerConnectionPool.ets`
- Modify: `entry/src/main/ets/communication/control/DskDataChannel.ets`
- Modify: `entry/src/main/ets/communication/tls/Task3TlsCoordinator.ets`
- Modify: `entry/src/test/PeerConnectionPool.test.ets`
- Modify: `entry/src/test/DskDataChannel.test.ets`

- [ ] Add failing tests for callback coexistence, binding timer cleanup, incomplete-frame expiry, frame-cache bounds, and idempotent destroy.
- [ ] Run focused tests and observe the current overwrite/leak behavior.
- [ ] Replace single handlers with removable handler registrations, store timer handles, and bound/expire frame assembly state.
- [ ] Ensure close/destroy removes listeners, resolves pending binders, and clears all caches.
- [ ] Run communication tests, HAP build, and `git diff --check`.

