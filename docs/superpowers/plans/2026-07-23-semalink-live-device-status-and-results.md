# SemaLink Live Device Status and Query Results Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the HarmonyOS UI reflect real DSK device state immediately and display the actual evidence accepted by each automatic query.

**Architecture:** Transport layers emit state changes upward; `AppRuntime` projects discovered peers and channel states into `AppStateStore`, which already drives ArkUI redraws. The task coordinator returns accepted evidence as an in-memory local result, and `AppRuntime` maps it to a minimal UI model without changing the cross-device protocol or persisting evidence bodies.

**Tech Stack:** HarmonyOS ArkTS, ArkUI, DSK/SoftBus coordination, Hypium tests, Hvigor build.

**Working-tree constraint:** The target UI, runtime, and communication files already contain user-owned uncommitted changes. Do not stage or commit implementation files during this plan; use focused diffs as checkpoints so those existing changes are not accidentally included in an implementation commit.

---

### Task 1: Define deterministic peer-state projection

**Files:**
- Create: `entry/src/main/ets/application/PeerStatusProjection.ets`
- Modify: `entry/src/main/ets/model/AppModels.ets`
- Modify: `entry/src/main/ets/state/AppStateStore.ets`
- Create: `entry/src/test/PeerStatusProjection.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: Write failing projection tests**

Add tests that construct three `PeerDevice` values and a state source. Assert that only peers with both channels `READY` count as active, failures remain attached to the correct device, and discovery order is stable by device name/device ID.

```ts
const statuses = projectPeerStatuses(peers, {
  controlStateOf: (id: string) => id === 'ready' ? 'READY' : id === 'failed' ? 'FAILED' : 'CONNECTING',
  dataStateOf: (id: string) => id === 'ready' ? 'READY' : 'DISCONNECTED'
}, new Map<string, string>([['failed', 'E_CONNECT_FAILED']]));
expect(activePeerCount(statuses)).assertEqual(1);
expect(statuses.find((item) => item.deviceName === 'Failed')?.failureCode).assertEqual('E_CONNECT_FAILED');
```

- [ ] **Step 2: Run the targeted test and verify RED**

Run: `hvigorw test --no-daemon`

Expected: compilation fails because `PeerStatusProjection` does not exist or the new exports are missing.

- [ ] **Step 3: Add the projection unit and result model**

Create the following focused API:

```ts
export interface PeerChannelStateSource {
  controlStateOf(deviceId: string): ControlChannelState;
  dataStateOf(deviceId: string): DataChannelState;
}

export function isPeerAvailable(status: PeerStatusSnapshot): boolean {
  return status.controlState === 'READY' && status.dataState === 'READY';
}

export function activePeerCount(statuses: PeerStatusSnapshot[]): number {
  return statuses.filter((status: PeerStatusSnapshot): boolean => isPeerAvailable(status)).length;
}
```

`projectPeerStatuses` must use `maskDeviceId`, preserve the system-provided `deviceName`, and never infer knowledge state or device aliases.

Add the UI-only query result type to `AppModels.ets`:

```ts
export interface AutomaticQueryResultItem {
  evidenceId: string;
  title: string;
  content: string;
  sourceName: string;
  sourceDeviceIdMasked: string;
  relevance: number;
  level: 'L1' | 'L2';
}
```

Add `automaticResultItems: AutomaticQueryResultItem[]` to `AppSnapshot`, `INITIAL_SNAPSHOT`, `cloneSnapshot`, and `AppStateStore.update`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `hvigorw test --no-daemon`

Expected: the new projection assertions pass; any unrelated pre-existing repository test compilation failure is recorded separately.

- [ ] **Step 5: Checkpoint the focused diff**

Run: `git diff -- entry/src/main/ets/application/PeerStatusProjection.ets entry/src/main/ets/model/AppModels.ets entry/src/main/ets/state/AppStateStore.ets entry/src/test/PeerStatusProjection.test.ets entry/src/test/List.test.ets`

Expected: only the projection API, result model, state propagation, and test registration are present.

### Task 2: Emit real-time channel state transitions

**Files:**
- Modify: `entry/src/main/ets/communication/PeerConnectionPool.ets`
- Modify: `entry/src/main/ets/communication/tls/Task3TlsCoordinator.ets`
- Modify: `entry/src/test/PeerConnectionPool.test.ets`

- [ ] **Step 1: Write failing data-channel observer tests**

Register an observer before `beginBinding` and assert the observed sequence includes `BINDING`, then `READY` after a valid bind ACK. Add a close assertion for `DISCONNECTED`.

```ts
const states: string[] = [];
pool.onStateChanged((deviceId: string, state: PeerConnectionState): void => {
  states.push(deviceId + ':' + state);
});
await pool.beginBinding('remote-a');
expect(states[0]).assertEqual('remote-a:BINDING');
```

- [ ] **Step 2: Run tests and verify RED**

Run: `hvigorw test --no-daemon`

Expected: compilation fails because `onStateChanged` is missing.

- [ ] **Step 3: Centralize `PeerConnectionPool` state changes**

Add:

```ts
export type PeerConnectionStateListener = (deviceId: string, state: PeerConnectionState) => void;

private readonly stateListeners = new Set<PeerConnectionStateListener>();

onStateChanged(listener: PeerConnectionStateListener): void { this.stateListeners.add(listener); }
removeStateChanged(listener: PeerConnectionStateListener): void { this.stateListeners.delete(listener); }

private transition(deviceId: string, connection: PeerConnection, state: PeerConnectionState): void {
  if (connection.state === state) return;
  connection.state = state;
  for (const listener of this.stateListeners) listener(deviceId, state);
}
```

Replace every direct state assignment in binding start, token failure, timeout, send failure, bind rejection, bind acceptance, ACK handling, and close with `transition`. Emit `DISCONNECTED` before deleting a closed connection.

- [ ] **Step 4: Forward combined state changes from `Task3TlsCoordinator`**

Add a coordinator observer API carrying the real peer and optional failure code:

```ts
export type Task3ConnectionStateObserver = (peer: PeerDevice, failureCode: string) => void;
onConnectionStateChanged(observer: Task3ConnectionStateObserver): void;
removeConnectionStateChanged(observer: Task3ConnectionStateObserver): void;
```

Notify observers when a connect attempt starts, `onControlReady` fires, the pool changes state, `onControlClosed` fires, and a connect attempt throws. Do not create timers or poll state.

- [ ] **Step 5: Run tests and inspect state assignment removal**

Run: `hvigorw test --no-daemon`

Run: `rg -n "connection\.state =" entry/src/main/ets/communication/PeerConnectionPool.ets`

Expected: tests pass and the only direct assignment is inside `transition` plus initial object construction.

### Task 3: Publish live device snapshots from AppRuntime

**Files:**
- Modify: `entry/src/main/ets/runtime/AppRuntime.ets`
- Modify: `entry/src/test/AppRuntime.test.ets`

- [ ] **Step 1: Write failing runtime projection tests**

Extend the existing refresh test to assert `activePeerCount === 0` for discovered but disconnected peers. Add a pure runtime projection test using `projectPeerStatuses` to assert a remote becomes active only when both channels are ready and becomes inactive immediately after disconnect.

```ts
expect(runtime.store.snapshot().activePeerCount).assertEqual(0);
expect(runtime.store.snapshot().peerStatuses[0].controlState).assertEqual('DISCONNECTED');
expect(runtime.store.snapshot().peerStatuses[0].dataState).assertEqual('DISCONNECTED');
```

- [ ] **Step 2: Run tests and verify RED**

Run: `hvigorw test --no-daemon`

Expected: active peer count or transition assertions fail because runtime publishes only after refresh completes.

- [ ] **Step 3: Keep discovered peer and failure state in runtime**

Add:

```ts
private readonly discoveredPeers = new Map<string, PeerDevice>();
private readonly peerFailures = new Map<string, string>();
private readonly connectionObserver: Task3ConnectionStateObserver;
```

Register the observer after `controlHub` and `connectionPool` are assigned. The observer updates the real peer entry, sets or clears its failure code, and calls one `publishPeerStatuses()` method.

`publishPeerStatuses()` must use `projectPeerStatuses`, update both `peerStatuses` and `activePeerCount`, and never clear unrelated application errors.

- [ ] **Step 4: Refactor refresh to publish every meaningful phase**

When discovery returns, replace `discoveredPeers` with the current list and publish immediately as disconnected/known. Before each connection attempt clear that device's old failure and publish. Let coordinator state events publish connecting/binding/ready states. In each per-peer catch, store the concrete `AppError.code` or `E_CONNECT_FAILED` and publish again.

- [ ] **Step 5: Run tests and verify GREEN**

Run: `hvigorw test --no-daemon`

Expected: runtime device tests pass and no periodic refresh mechanism is introduced.

### Task 4: Preserve accepted evidence as query results

**Files:**
- Modify: `entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets`
- Modify: `entry/src/main/ets/runtime/AppRuntime.ets`
- Modify: `entry/src/test/MultiDeviceTaskCoordinator.test.ets`
- Modify: `entry/src/test/AppRuntime.test.ets`

- [ ] **Step 1: Write failing coordinator evidence tests**

Extend the sufficient-result test to assert the coordinator returns the accepted evidence objects in stable aggregator order and returns defensive copies.

```ts
const result: CoordinatedTaskResult = await coordinator.submit(task('task-results'));
expect(result.acceptedEvidence.length).assertEqual(2);
expect(result.acceptedEvidence[0].title).assertEqual('a');
expect(result.acceptedEvidence[1].sourceDeviceId).assertEqual('remote-b');
```

- [ ] **Step 2: Run tests and verify RED**

Run: `hvigorw test --no-daemon`

Expected: `CoordinatedTaskResult` or `acceptedEvidence` is missing.

- [ ] **Step 3: Return local accepted evidence without changing protocol types**

Define in `MultiDeviceTaskCoordinator.ets`:

```ts
export interface CoordinatedTaskResult extends TaskSufficiencyResult {
  acceptedEvidence: EvidenceUnit[];
}
```

Change only `MultiDeviceTaskCoordinator.submit` to return `Promise<CoordinatedTaskResult>`. Before returning, intersect `result.acceptedEvidenceIds` with `aggregator.result().evidence`, clone array fields (`coveredConcepts`, `canEscalateTo`), and attach them as `acceptedEvidence`. Keep `TaskSufficiencyResult` and protocol codecs unchanged.

- [ ] **Step 4: Write failing runtime UI projection tests**

Update the automatic query fixture with an L1 summary and assert the snapshot contains its content and `sourceName === '本机'`. Add an L2 fixture with only `snippet` and assert snippet fallback and the correct level.

```ts
expect(runtime.store.snapshot().automaticResultItems[0].title).assertEqual('Local answer');
expect(runtime.store.snapshot().automaticResultItems[0].content).assertEqual('Actual summary');
expect(runtime.store.snapshot().automaticResultItems[0].sourceName).assertEqual('本机');
```

- [ ] **Step 5: Map results and real total duration in AppRuntime**

Capture `startedAtMs = Date.now()` when submission begins. Clear `automaticResultItems` and set `totalTaskMs: 0` in the initial store update. On completion, map `acceptedEvidence` into `AutomaticQueryResultItem[]`, using summary first, snippet second, and an empty string only when neither is present. Resolve remote names through `discoveredPeers`; use masked IDs when names are absent. Set `totalTaskMs` from the measured elapsed time.

On failure and cancellation, clear `automaticResultItems` so stale results cannot survive a new terminal state.

- [ ] **Step 6: Run coordinator and runtime tests**

Run: `hvigorw test --no-daemon`

Expected: accepted evidence, content fallback, source mapping, stale-result clearing, and real duration tests pass.

### Task 5: Replace hardcoded UI with snapshot-driven views

**Files:**
- Modify: `entry/src/main/ets/components/QueryHome.ets`
- Modify: `entry/src/main/ets/components/DeviceOverview.ets`
- Modify: `entry/src/test/AutomaticQueryUi.test.ets`

- [ ] **Step 1: Write failing UI helper tests**

Add exported pure helpers and tests for:

```ts
expect(peerConnectionLabel(readyPeer)).assertEqual('已连接');
expect(peerConnectionLabel(bindingPeer)).assertEqual('正在绑定');
const names: string[] = availableDeviceNames(snapshot);
expect(names.length).assertEqual(2);
expect(names[0]).assertEqual('本机');
expect(names[1]).assertEqual('Tablet B');
expect(queryDeviceStep(snapshot)).assertEqual('查询本机、Tablet B');
expect(queryDurationLabel(1250)).assertEqual('总耗时 1.25 秒');
```

Also assert disconnected peers are absent from query scope and failures produce `连接失败 · E_CONNECT_FAILED`.

- [ ] **Step 2: Run tests and verify RED**

Run: `hvigorw test --no-daemon`

Expected: helper exports are missing or return the current hardcoded labels.

- [ ] **Step 3: Make QueryHome fully snapshot driven**

Replace fixed scope chips with `ForEach(availableDeviceNames(this.snapshot), ...)`. Replace “跨设备服务运行正常” with a computed summary covering no peer, connecting, partial failure, and ready states. Replace “查询工作平板” with `queryDeviceStep(snapshot)`. Remove `stepTime`; show `queryDurationLabel(totalTaskMs)` only for terminal query states and positive duration.

Replace the two callback-free buttons with an inline result list:

```ts
ForEach(this.snapshot.automaticResultItems, (item: AutomaticQueryResultItem) => {
  this.resultEntry(item)
}, (item: AutomaticQueryResultItem) => item.evidenceId)
```

Each result row displays the actual title, content, source name, rounded relevance percentage, and level label. Empty terminal results display “未找到足够的相关内容”.

- [ ] **Step 4: Make DeviceOverview fully snapshot driven**

Remove fixed knowledge types, fixed sync time, fixed “phone” type, fixed healthy-service text, remote index inference, and `deviceLabel`. Show local index label plus actual document/chunk counts. Show remote raw device name or masked ID, combined connection label, separate control/data channel labels, and `failureCode` only when non-empty.

Compute device summary as `(1 + activePeerCount) / (1 + peerStatuses.length) 台设备可用`, with the local device included explicitly.

- [ ] **Step 5: Run UI tests and scan forbidden strings**

Run: `hvigorw test --no-daemon`

Run: `rg -n "工作平板|生活平板|最近同步：刚刚|跨设备服务运行正常|00:0|会议记录、项目文档|deviceLabel" entry/src/main/ets/components`

Expected: UI helper tests pass and the forbidden-string scan returns no matches.

### Task 6: Build and final verification

**Files:**
- Verify all files listed above.

- [ ] **Step 1: Run the full test command**

Run: `hvigorw test --no-daemon`

Expected: PASS. If the known missing test modules/repository interface implementations still block compilation, capture the first concrete errors and confirm none originates from files changed by this plan.

- [ ] **Step 2: Build the HAP**

Run: `hvigorw assembleHap --no-daemon`

Expected: `BUILD SUCCESSFUL` with no new ArkTS errors.

- [ ] **Step 3: Review only scoped diffs**

Run: `git diff -- entry/src/main/ets/application/PeerStatusProjection.ets entry/src/main/ets/model/AppModels.ets entry/src/main/ets/state/AppStateStore.ets entry/src/main/ets/communication/PeerConnectionPool.ets entry/src/main/ets/communication/tls/Task3TlsCoordinator.ets entry/src/main/ets/runtime/AppRuntime.ets entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets entry/src/main/ets/components/QueryHome.ets entry/src/main/ets/components/DeviceOverview.ets entry/src/test/PeerStatusProjection.test.ets entry/src/test/PeerConnectionPool.test.ets entry/src/test/MultiDeviceTaskCoordinator.test.ets entry/src/test/AppRuntime.test.ets entry/src/test/AutomaticQueryUi.test.ets entry/src/test/List.test.ets`

Expected: no remote knowledge metadata is invented, no polling is added, protocol codecs are unchanged, query result bodies are not persisted, and unrelated user changes remain intact.
