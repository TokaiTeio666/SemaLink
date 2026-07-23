# SemaLink Cross-Device Knowledge Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` for every task and `superpowers:verification-before-completion` before reporting completion. This plan is executed inline in the current task. The repository constraints explicitly prohibit commit, add, push, pull, merge, rebase, reset, stash, branch creation, and branch switching.

**Goal:** Build a permission-controlled, privacy-preserving cross-device knowledge query loop over HarmonyOS API 24 Distributed Service Kit, while preserving local retrieval behavior and keeping the Xiaoyi Agent unchanged except for compile-only compatibility.

**Architecture:** Add an application-level collaboration domain and repositories around the existing knowledge/RDB infrastructure. Reuse `distributedDeviceManager`, `abilityConnectionManager`, `DskDataChannel`, `DeviceSemanticRouter`, `SemanticKnowledgeProvider`, and existing evidence relevance; add a versioned JSON protocol, profile exchange, inbound query server, sanitizer, and a production `CrossDeviceKnowledgePort`. UI surfaces only aliases and application trust state.

**Tech Stack:** ArkTS, HarmonyOS 6.1.1 / API 24, `@kit.DistributedServiceKit`, `@kit.ArkData`, Hypium, existing hvigor build.

## Global Constraints

- Work only on branch `feat/cross-device-knowledge-loop`; never switch or create a branch.
- Never read, print, modify, restore, stage, or stash `build-profile.json5`.
- No commit, add, push, pull, merge, rebase, reset, or stash.
- No third-party dependencies and no HTTP/WebSocket/custom-server fallback.
- Ordinary queries default to `LOCAL_ONLY`; transport starts only after explicit remote scope.
- Official transport is text-only and limited to 1 KB per `sendMessage`; use bounded framing.
- Sharing defaults off; trusted peer is required; default levels `["L1"]`; evidence max 5; snippet max 512.
- Remote profile domains ≤ 20, serialized target ≤ 8 KB, TTL 5 minutes, offline retention ≤ 24 hours.
- Inbound execution ≤ 2, queue ≤ 4, execution deadline 5 seconds, idempotency cache ≤ 128 with 5-minute TTL.
- Logical response ≤ 64 KB; never send document body, path, SQL, database ID, hardware ID, or networkId.
- Remote selection defaults Top 1; try Top 2 only after transport failure or `BUSY`; never broadcast; max remote concurrency 2.
- Preserve existing retrieval/scoring algorithms and Agent behavior.

---

### Task 1: Platform Gate and Versioned PING/PONG Spike

**Files:**
- Create: `docs/research/harmony-api24-cross-device-feasibility.md`
- Create: `entry/src/main/ets/debug/CrossDevicePingPongSpike.ets`
- Create: `entry/src/test/CrossDevicePingPongSpike.test.ets`
- Modify: `entry/src/main/ets/debug/CollaborationProbe.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Produces: `CrossDevicePingPongSpikeCodec.createPing(requestId)`, `createPong(requestId)`, `encode(message)`, `decode(text)`.

- [x] Write failing protocol tests and verify missing implementation fails compilation.
- [x] Add the minimal three-field version 1 codec and use it in the real `abilityConnectionManager` probe.
- [x] Run `entry@default test` and verify `BUILD SUCCESSFUL`.
- [x] Record `AWAITING_DEVICE_SPIKE` and `COMPILED_NOT_EXECUTED`.

### Task 2: Collaboration Domain Models and Safe Defaults

**Files:**
- Create: `entry/src/main/ets/crossdevice/model/CollaborationModels.ets`
- Create: `entry/src/main/ets/crossdevice/model/SharingPolicy.ets`
- Create: `entry/src/test/LocalCollaborationIdentity.test.ets`
- Create: `entry/src/test/CollaborationPeer.test.ets`
- Create: `entry/src/test/PeerTrustState.test.ets`
- Create: `entry/src/test/SharingPolicy.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Produces:
  - `LocalCollaborationIdentity(appInstanceId, deviceAlias, createdAtMs, updatedAtMs, revision)`
  - `CollaborationPeer(peerKey, deviceAlias, trustState, onlineState, lastSeenAtMs, profileVersion, profileDigest, createdAtMs, updatedAtMs)`
  - `RemoteKnowledgeProfile`
  - `SharingPolicy.defaults(nowMs)` and `SharingPolicy.allows(peer, level, domain)`
  - `RemoteAccessRecord`

- [ ] Write model tests for non-empty application identity, trust transitions, immutable aliases, default sharing off, denied-domain precedence, and separate L2 enablement.
- [ ] Run tests and verify missing models fail.
- [ ] Implement only validated data models and policy decisions.
- [ ] Re-run the focused tests and full unit suite.

### Task 3: Repository Contracts, In-Memory Fakes, and RDB Migration

**Files:**
- Create: `entry/src/main/ets/crossdevice/storage/CollaborationRepositories.ets`
- Create: `entry/src/main/ets/crossdevice/storage/InMemoryCollaborationRepositories.ets`
- Create: `entry/src/main/ets/crossdevice/storage/RdbCollaborationRepositories.ets`
- Modify: `entry/src/main/ets/knowledge/storage/KnowledgeDatabaseSchema.ets`
- Modify: `entry/src/main/ets/knowledge/storage/KnowledgeDatabase.ets`
- Create: `entry/src/test/SharingPolicyRepository.test.ets`
- Create: `entry/src/test/CollaborationRepositoryContract.test.ets`
- Create: `entry/src/test/KnowledgeDatabaseCollaborationMigration.test.ets`
- Create: `entry/src/ohosTest/ets/test/CollaborationRepository.test.ets`
- Modify: both `List.test.ets` registries.

**Interfaces:**
- Produces:
  - `LocalCollaborationIdentityRepository.load/save`
  - `CollaborationPeerRepository.list/get/save`
  - `RemoteKnowledgeProfileRepository.listFresh/get/save/deleteExpired`
  - `SharingPolicyRepository.load/save`
  - `RemoteAccessRecordRepository.listRecent/save`

- [ ] Write repository contract tests against in-memory fakes, including copy isolation and transactional failure behavior.
- [ ] Write migration tests proving version 2 data survives version 3 table creation and repeated migration is idempotent.
- [ ] Implement schema version 3 and five collaboration tables without changing existing document tables.
- [ ] Implement RDB repositories with parameterized predicates/values and transaction-owned writes.
- [ ] Run unit migration tests and compile ohosTest repository tests.

### Task 4: Trusted Device Directory and Ephemeral Transport Mapping

**Files:**
- Create: `entry/src/main/ets/crossdevice/trust/SystemTrustedDeviceSource.ets`
- Create: `entry/src/main/ets/crossdevice/trust/TrustedDeviceDirectory.ets`
- Create: `entry/src/main/ets/crossdevice/trust/PeerTransportMapping.ets`
- Create: `entry/src/test/TrustedDeviceDirectory.test.ets`
- Create: `entry/src/test/PeerTransportMapping.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: `distributedDeviceManager.DeviceManager`, `CollaborationPeerRepository`.
- Produces:
  - `SystemTrustedDeviceSource.listVisible()` and online/offline subscription.
  - `TrustedDeviceDirectory.refreshCandidates()`, `trust`, `block`, `revoke`, `rename`, `routablePeers`.
  - `PeerTransportMapping.bind(systemDeviceId, peerKey)`, `peerKeyFor`, `systemIdFor`, `clear`.

- [ ] Write tests proving system visibility creates `PENDING`, never automatic `TRUSTED`; blocked/revoked peers cannot route; reconnect restores by app handshake; mappings are memory-only.
- [ ] Implement the system adapter without exposing system IDs outside the transport package.
- [ ] Run trust tests and existing device-router tests.

### Task 5: Cross-Device Protocol, Limits, and Privacy

**Files:**
- Create: `entry/src/main/ets/crossdevice/protocol/CrossDeviceProtocolModels.ets`
- Create: `entry/src/main/ets/crossdevice/protocol/CrossDeviceProtocolCodec.ets`
- Create: `entry/src/test/CrossDeviceProtocolCodec.test.ets`
- Create: `entry/src/test/CrossDeviceProtocolLimits.test.ets`
- Create: `entry/src/test/CrossDeviceProtocolVersion.test.ets`
- Create: `entry/src/test/CrossDeviceProtocolPrivacy.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Produces `SEMALINK_CROSS_DEVICE_PROTOCOL_VERSION = 1`.
- Produces message types `HELLO`, `PING`, `PONG`, `PROFILE_DIGEST`, `PROFILE_REQUEST`, `PROFILE_RESPONSE`, `QUERY_REQUEST`, `QUERY_RESPONSE`, `QUERY_ERROR`, `QUERY_CANCEL`.
- Produces a strict envelope with protocol/version/type/message/request/task/sender/time/deadline/sequence/payload.

- [ ] Write failing golden, invalid JSON, unknown version/type, missing field, deadline, max logical payload, and forbidden-field tests.
- [ ] Implement deterministic JSON encoding and strict decoding; cap logical payload at 64 KB and frame payload below the DSK text limit.
- [ ] Prove query text and forbidden identifiers are not passed to logger metadata.
- [ ] Run protocol and existing protocol suites.

### Task 6: Profile Digest, Exchange, and Cache

**Files:**
- Create: `entry/src/main/ets/crossdevice/profile/KnowledgeProfileDigestBuilder.ets`
- Create: `entry/src/main/ets/crossdevice/profile/RemoteKnowledgeProfileCache.ets`
- Create: `entry/src/main/ets/crossdevice/profile/KnowledgeProfileExchangeService.ets`
- Create: `entry/src/test/KnowledgeProfileDigest.test.ets`
- Create: `entry/src/test/KnowledgeProfileExchange.test.ets`
- Create: `entry/src/test/RemoteKnowledgeProfileCache.test.ets`
- Create: `entry/src/test/RemoteKnowledgeProfileExpiry.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: existing `KnowledgeProfile`, protocol sender, profile repository.
- Produces deterministic digest over allowed summary fields only.
- Produces digest-first exchange and cache read rules: fresh ≤ 5 minutes; offline fallback ≤ 24 hours.

- [ ] Write failing digest stability/privacy/20-domain/8-KB tests.
- [ ] Write exchange tests for equal digest, changed digest, expiry, first trust, reconnect, local version change, and manual refresh.
- [ ] Implement canonical allowed-field projection and bounded cache.
- [ ] Run profile tests and existing `KnowledgeProfileBuilder` tests.

### Task 7: Evidence Sanitizer and Inbound Query Server

**Files:**
- Create: `entry/src/main/ets/crossdevice/query/RemoteEvidenceSanitizer.ets`
- Create: `entry/src/main/ets/crossdevice/query/RemoteKnowledgeQueryServer.ets`
- Create: `entry/src/test/RemoteEvidenceSanitizer.test.ets`
- Create: `entry/src/test/RemoteEvidenceSizeLimit.test.ets`
- Create: `entry/src/test/RemoteEvidencePrivacy.test.ets`
- Create: `entry/src/test/RemoteKnowledgeQueryServer.test.ets`
- Create: `entry/src/test/RemoteQueryAuthorization.test.ets`
- Create: `entry/src/test/RemoteQueryDeadline.test.ets`
- Create: `entry/src/test/RemoteQueryIdempotency.test.ets`
- Create: `entry/src/test/RemoteQueryConcurrencyLimit.test.ets`
- Create: `entry/src/test/RemoteQueryCancel.test.ets`
- Create: `entry/src/test/SharingPolicyEnforcement.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: `SemanticKnowledgeProvider.searchEvidence`, trusted directory, sharing policy repository, access record repository.
- Produces stable errors `UNAUTHORIZED`, `SHARING_DISABLED`, `LEVEL_DENIED`, `DEADLINE_EXCEEDED`, `BUSY`, `CANCELLED`, `INVALID_REQUEST`, `INTERNAL_ERROR`.

- [ ] Write sanitizer tests for count 5, snippet 512, relevance trimming, truncation flag, forbidden paths/SQL/internal IDs/hardware IDs/networkId, and 64-KB response.
- [ ] Write server tests for validation order, trusted peer, live policy lookup, deadline, concurrency 2, queue 4, 5-second cap, idempotency 128/5 minutes, cancel, and safe access records.
- [ ] Implement sanitizer, bounded scheduler, idempotency cache, cancellation tokens, and safe error mapping.
- [ ] Run query-server, sanitizer, semantic-provider, and privacy tests.

### Task 8: Production Harmony Transport and CrossDeviceKnowledgePort

**Files:**
- Create: `entry/src/main/ets/crossdevice/transport/HarmonyCrossDeviceSession.ets`
- Create: `entry/src/main/ets/crossdevice/transport/HarmonyCrossDeviceKnowledgePort.ets`
- Modify: `entry/src/main/ets/agent/query/CrossDeviceKnowledgePort.ets` only if required for compile-compatible `getAvailablePeers/getRemoteProfiles`.
- Create: `entry/src/test/CrossDeviceTopOneRouting.test.ets`
- Create: `entry/src/test/CrossDeviceFallbackRouting.test.ets`
- Create: `entry/src/test/CrossDeviceLateResult.test.ets`
- Create: `entry/src/test/RemoteQueryCancel.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: `DskControlHub`, `DskDataChannel`, `DeviceSemanticRouter`, trusted directory, remote profile cache.
- Produces `query/search`, `cancel`, `getAvailablePeers`, `getRemoteProfiles`.

- [ ] Write tests proving Top 1 only, Top 2 only after network/BUSY failure, max remote concurrency 2, no broadcast, deadline, propagated cancel, late-result drop, disconnect cleanup, bounded exponential reconnect, and idempotent destroy.
- [ ] Implement the adapter using only `abilityConnectionManager` text transport and bounded DSK framing.
- [ ] Keep system IDs inside transport mapping and aliases in returned evidence.
- [ ] Run transport, routing, and existing Agent tests.

### Task 9: Local/Remote Coordination and Evidence Merge

**Files:**
- Create: `entry/src/main/ets/crossdevice/application/CrossDeviceKnowledgeQueryService.ets`
- Create: `entry/src/test/LocalAndRemoteQuery.test.ets`
- Create: `entry/src/test/RemoteOnlyQuery.test.ets`
- Create: `entry/src/test/CrossDeviceEvidenceMerge.test.ets`
- Create: `entry/src/test/CrossDevicePartialFailure.test.ets`
- Create: `entry/src/test/CrossDeviceKnowledgeBusinessLoopEndToEnd.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**
- Consumes: existing local `SemanticKnowledgeProvider`, production cross-device port, existing relevance values.
- Produces scopes `LOCAL_ONLY`, `REMOTE_ONLY`, `LOCAL_AND_REMOTE` with generation-based stale-result protection.

- [ ] Write tests for no remote initialization in default local query, parallel local/one-remote execution, explicit remote unavailable result, hash dedupe retaining higher relevance, max 8 total/max 5 per device, source alias, partial failure, cancel, and late-result drop.
- [ ] Implement merge only; do not create a new scorer or alter local retrieval.
- [ ] Add the complete fake three-device business test while labeling it business-logic-only.
- [ ] Run all query and existing knowledge tests.

### Task 10: Runtime Composition and Minimal UI Surfaces

**Files:**
- Modify: `entry/src/main/ets/runtime/AppRuntime.ets`
- Modify: `entry/src/main/ets/application/KnowledgeCompositionRoot.ets`
- Modify: `entry/src/main/ets/state/AppStateStore.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/resources/base/element/string.json`
- Create: `entry/src/test/CrossDeviceRuntimeComposition.test.ets`
- Create: `entry/src/ohosTest/ets/test/CrossDeviceKnowledgeUi.test.ets`
- Modify: both test registries.

**Interfaces:**
- Produces UI actions for list/trust/block/revoke/rename/refresh, sharing controls, access records, query scope, cancel, and source-state display.

- [ ] Write runtime tests proving local knowledge initializes independently and remote services are lazy.
- [ ] Write UI tests for three bounded sections: trusted devices, sharing settings, result sources.
- [ ] Compose repositories/transport/services after local runtime is ready; release all listeners/sessions on destroy.
- [ ] Add only the three required UI regions without rebuilding the page.
- [ ] Run runtime, page, Agent, and local query tests.

### Task 11: Device Tests, Performance Benchmarks, and Handoff

**Files:**
- Create: `entry/src/ohosTest/ets/test/CrossDeviceKnowledgeTransport.test.ets`
- Create: `entry/src/ohosTest/ets/test/CollaborationMigration.test.ets`
- Create: `entry/src/test/CrossDeviceKnowledgePerformance.test.ets`
- Create: `docs/testing/cross-device-knowledge-three-device-test.md`
- Modify: both test registries.

- [ ] Add compilable real-API device cases for PING/PONG, profile exchange, query/response, and cancel; mark hardware-required cases `COMPILED_NOT_EXECUTED`.
- [ ] Add real RDB create/migrate/restart/rollback device tests.
- [ ] Benchmark local-query added overhead ≤ 10 ms, cached profile route ≤ 20 ms, 10/100 cached peer routing, 20 domains per peer, 5 evidence, 64-KB boundary, and repeated-query memory stability.
- [ ] Write the exact A/B/C manual procedure, privacy checks, restart persistence, and P50/P95 recording table.

### Task 12: Independent Review and Final Verification

**Files:** all changed files.

- [ ] Invoke `superpowers:requesting-code-review`; fix all Critical and Important findings or document test-backed reasons.
- [ ] Invoke `superpowers:verification-before-completion`.
- [ ] Run full unit suite, existing knowledge/router/fake/Agent suites, full `List.test.ets`, `default@CompileArkTS`, `ohosTest@OhosTestCompileArkTS`, both PackageHap targets, `assembleHap`, and `SignHap`.
- [ ] Distinguish unit, ArkTS, ohosTest, package, signing/keystore, and device-test outcomes.
- [ ] Re-run branch/HEAD/status/diff stat/diff check without reading `build-profile.json5`.
- [ ] Report only `AWAITING_DEVICE_SPIKE` until three-device hardware execution actually passes.

## 2026-07-23 四项缺陷根因记录

1. **执行槽泄漏**：`RemoteKnowledgeQueryServer` 只在底层
   `searchEvidence()` 最终 resolve/reject 时释放 `activeCount`。外层 deadline
   或 cancel 已经返回终态时没有同步释放容量，因此永不 settle 或晚到的 Provider
   会长期占用执行槽；Server 也缺少统一的 destroy 清理边界。
2. **领域链路不一致**：查询概念、设备画像、路由命中、协议字段与远端标签过滤
   分别执行大小写敏感比较或局部 `trim/toLowerCase`，路由结果又不携带实际命中的
   画像领域，导致 `QUERY_REQUEST` 可能用查询首词伪装为权威领域，并在远端形成错误
   或大小写敏感的标签过滤。
3. **冷启动假在线**：持久化的 `onlineState` 被当作当前进程实时事实恢复，而
   `PeerTransportMapping` 与 HELLO 会话只存在于内存。Runtime 初始化没有先把历史
   ONLINE 重置为 OFFLINE，路由和批量 Profile 刷新也没有同时校验当前 mapping/session，
   且 `Promise.all` 会让单 Peer 失败拒绝整个刷新。
4. **响应关联与幂等竞态**：Session 在删除 Pending 前只校验 peer/request，
   未校验 task；Server 的幂等键也缺少 task。终态结果又在异步访问审计保存完成后才
   写入缓存，而 `inFlight` 会更早清除，形成重复请求重新执行 Provider 的时间窗口，
   审计失败还会阻止缓存落地。
