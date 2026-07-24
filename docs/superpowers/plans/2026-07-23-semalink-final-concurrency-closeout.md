# SemaLink Final Concurrency Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development and execute inline. Do not create worktrees, stage, commit, or push.

**Goal:** Close the authorization-cancellation and premature-success-cache windows in `RemoteKnowledgeQueryServer`.

**Architecture:** Register one request lifecycle by `peerKey|requestId|taskId` before the first await and expose a cancellation signal that authorization reads race against. Keep the existing queue, concurrency limit, `ExecutionLease`, cache bounds, and audit repository, but determine the single final status before calling the cache/audit commit path.

**Tech Stack:** ArkTS, Promise/Map/Set, Hypium, Hvigor.

## Global Constraints

- Modify only the Server and focused RemoteQuery/SharingPolicy tests unless compilation requires a listed adjacent model/repository change.
- Do not read or modify signing configuration or secrets.
- Do not change Router, Normalizer, Transport, Runtime, UI, Agent, RDB schema, dependencies, branch, index, or history.
- Preserve cache capacity 128, TTL five minutes, concurrency two, queue four, and exactly-once `ExecutionLease`.

---

### Task 1: Authorization-stage cancellation

**Files:**
- Modify: `entry/src/test/RemoteQueryAuthorization.test.ets`
- Modify: `entry/src/test/RemoteQueryCancel.test.ets`
- Modify: `entry/src/main/ets/crossdevice/query/RemoteKnowledgeQueryServer.ets`

**Interfaces:**
- Consumes: `cancel(peerKey, requestId, taskId)` and repository `Promise` methods.
- Produces: lifecycle registration keyed by peer/request/task, cancellation-aware authorization awaits, and exactly-once lifecycle cleanup.

- [ ] Add a Deferred peer repository test: start `handle`, cancel while `get()` is pending, resolve it, and assert `CANCELLED` with zero Provider calls.
- [ ] Run the complete unit-test command and verify the new test fails because current `cancel()` cannot observe authorization work.
- [ ] Add a Deferred policy repository test with the same assertions, plus repeated cancel and destroy coverage.
- [ ] Implement a bounded `RequestLifecycle` registered before `peers.get()`, race authorization awaits with its cancellation signal, and clean it only after the request reaches a terminal result.
- [ ] Keep queue/active cancellation and `ExecutionLease` behavior unchanged, then run all RemoteQuery tests.

### Task 2: Final policy result before cache/audit

**Files:**
- Modify: `entry/src/test/RemoteQueryIdempotency.test.ets`
- Modify: `entry/src/test/SharingPolicyEnforcement.test.ets`
- Modify: `entry/src/main/ets/crossdevice/query/RemoteKnowledgeQueryServer.ets`

**Interfaces:**
- Consumes: current policy revision, level/domain authorization, lifecycle cancellation, `finish()`.
- Produces: one final `RemoteQueryResult` committed to cache and audit only after all final checks.

- [ ] Add a controlled policy repository test where Provider completion is followed by sharing disablement before the final policy read resolves; assert original and duplicate both see the same non-OK result and Provider runs once.
- [ ] Add the equivalent L2-denied and user-cancel races, checking final audit status and absence of successful Evidence.
- [ ] Run the complete unit-test command and verify at least the cancellation race observes the prematurely cached `OK`.
- [ ] Remove the `finish(OK)` call before epoch/cancel checks; build the final status first, then invoke `finish()` exactly once.
- [ ] Preserve audit pending/reject behavior, cache isolation, capacity, and TTL; run Idempotency, Policy, Cancel, Concurrency, and Deadline regressions.

### Task 3: Final verification and bounded review

**Files:**
- No production scope expansion.

**Interfaces:**
- Consumes: final working tree.
- Produces: fresh test/build evidence and one bounded independent review.

- [ ] Run the full `List.test.ets` suite and report registered files, total, passed, and failed.
- [ ] Run default and ohosTest CompileArkTS/PackageHap plus assemble/SignHap, recording the existing keystore result without inspecting configuration.
- [ ] Request one read-only review limited to lifecycle cancellation, final-result commit ordering, cache/audit behavior, and scope compliance.
- [ ] Fix only Critical or real-function Important findings, run one final complete regression, then stop modifying code.
