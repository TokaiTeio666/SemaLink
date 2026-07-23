# SemaLink 无固定中心全互联控制通道实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 让每台可信设备自动形成无固定中心的全互联控制通道，并允许任意设备聚合本机和所有就绪远端设备的查询结果。

**架构：** `DeviceTopologyProvider` 提供本机 `networkId` 与可信设备快照；`PeerMeshPlanner` 用稳定设备 ID 为每个设备对指定主拨号方；`PeerMeshOrchestrator` 串行协调发现、入站宽限、独立重试和清理。`DskControlHub` 选择规范会话并按设备去重，现有 `PeerConnectionPool`、任务协调器和响应器继续使用该有效会话。

**技术栈：** ArkTS、HarmonyOS `distributedDeviceManager`、Distributed Service Kit、Hypium、Hvigor。

---

## 文件结构

| 路径 | 责任 |
| --- | --- |
| `entry/src/main/ets/communication/PeerMeshPlanner.ets` | 纯函数：稳定 ID 比较、拨号角色、首选会话方向和完整网格边规划。 |
| `entry/src/main/ets/communication/DeviceTopologyProvider.ets` | 持有 `DeviceManager`，读取本机 `networkId`、可用可信设备并订阅设备状态事件。 |
| `entry/src/main/ets/communication/PeerMeshOrchestrator.ets` | 串行拓扑协调、入站宽限、逐设备退避、就绪等待与销毁清理。 |
| `entry/src/main/ets/communication/TrustedDeviceResolver.ets` | 复用现有设备映射；为旧调用方保留 `resolveAll()` 兼容性。 |
| `entry/src/main/ets/communication/control/DskControlHub.ets` | 记录会话方向，选出规范会话，按远端设备 ID 有界去重。 |
| `entry/src/main/ets/communication/tls/Task3TlsCoordinator.ets` | 注册发现/入站设备，暴露网格需要的就绪、关闭与连接方法，不再自行决定拨号所有权。 |
| `entry/src/main/ets/runtime/AppRuntime.ets` | 装配网格，刷新时委托协调器，查询前按 3 秒预算等待就绪设备。 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 权限成功后启动网格，前台时触发立即协调。 |
| `entry/src/test/PeerMeshPlanner.test.ets` | 角色、首选方向、三/四设备完整网格边的纯单元测试。 |
| `entry/src/test/DeviceTopologyProvider.test.ets` | 本机网络 ID、设备映射、状态监听和停止释放测试。 |
| `entry/src/test/PeerMeshOrchestrator.test.ets` | 宽限、退避、串行协调、设备移除及销毁测试。 |
| `entry/src/test/DskControlHub.test.ets` | 重复会话规范化与逐设备去重测试。 |
| `entry/src/test/MultiDeviceEndToEnd.test.ets` | 从 A、B、C 任意节点发起的对称查询与故障隔离测试。 |
| `entry/src/test/support/MultiDeviceFixtures.ets` | 让每个模拟节点同时拥有协调器与响应器的全网格夹具。 |
| `entry/src/test/List.test.ets` | 注册新增网格测试套件。 |
| `docs/testing/decentralized-full-mesh-acceptance.md` | 三真机部署、日志和验收记录模板。 |

## 统一验证命令

所有任务的 ArkTS 测试使用以下命令；执行时替换最后的 `test` 参数为项目既有完整测试入口：

```powershell
$devecoNode = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigorScript = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
& $devecoNode $hvigorScript --mode module -p product=default -p module=entry@default -p buildMode=debug test
```

预期：命令退出码为 `0`，且新增 Hypium 用例全部通过。

### Task 1: 建立纯网格规划器

**文件：**
- Create: `entry/src/main/ets/communication/PeerMeshPlanner.ets`
- Create: `entry/src/test/PeerMeshPlanner.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入会失败的规划器测试。**

```ts
import { describe, expect, it } from '@ohos/hypium';
import {
  MeshDialRole,
  preferredSessionDirection,
  planFullMeshEdges,
  planPeerRole
} from '../main/ets/communication/PeerMeshPlanner';

export default function peerMeshPlannerTest(): void {
  describe('PeerMeshPlanner', () => {
    it('plansExactlyOnePrimaryDialerForEachPair', 0, () => {
      expect(planPeerRole('device-a', 'device-b')).assertEqual(MeshDialRole.PRIMARY_DIALER);
      expect(planPeerRole('device-b', 'device-a')).assertEqual(MeshDialRole.INBOUND_WAITER);
      expect(planPeerRole('device-a', 'device-a')).assertEqual(MeshDialRole.INVALID_SELF);
    });

    it('producesTheThreeEdgesOfAThreeDeviceMesh', 0, () => {
      expect(planFullMeshEdges(['device-c', 'device-a', 'device-b']))
        .assertDeepEquals(['device-a->device-b', 'device-a->device-c', 'device-b->device-c']);
    });

    it('selectsTheSameCanonicalDirectionAtBothEnds', 0, () => {
      expect(preferredSessionDirection('device-a', 'device-b')).assertEqual('OUTBOUND');
      expect(preferredSessionDirection('device-b', 'device-a')).assertEqual('INBOUND');
    });
  });
}
```

- [ ] **Step 2: 在 `entry/src/test/List.test.ets` 导入并调用新套件。**

```ts
import peerMeshPlannerTest from './PeerMeshPlanner.test';

// 在 testsuite() 的其他测试调用旁加入：
peerMeshPlannerTest();
```

- [ ] **Step 3: 运行测试确认失败。**

运行：统一验证命令。

预期：编译失败，指出模块 `../main/ets/communication/PeerMeshPlanner` 不存在。

- [ ] **Step 4: 实现最小纯规划器。**

```ts
export enum MeshDialRole {
  PRIMARY_DIALER = 'PRIMARY_DIALER',
  INBOUND_WAITER = 'INBOUND_WAITER',
  INVALID_SELF = 'INVALID_SELF'
}

export type MeshSessionDirection = 'INBOUND' | 'OUTBOUND';

export function planPeerRole(localDeviceId: string, remoteDeviceId: string): MeshDialRole {
  if (localDeviceId === remoteDeviceId) return MeshDialRole.INVALID_SELF;
  return localDeviceId < remoteDeviceId ? MeshDialRole.PRIMARY_DIALER : MeshDialRole.INBOUND_WAITER;
}

export function preferredSessionDirection(localDeviceId: string, remoteDeviceId: string): MeshSessionDirection {
  return planPeerRole(localDeviceId, remoteDeviceId) === MeshDialRole.PRIMARY_DIALER ? 'OUTBOUND' : 'INBOUND';
}

export function planFullMeshEdges(deviceIds: string[]): string[] {
  const ids: string[] = Array.from(new Set(deviceIds.filter((id: string): boolean => id.length > 0))).sort();
  const edges: string[] = [];
  for (let left = 0; left < ids.length; left += 1) {
    for (let right = left + 1; right < ids.length; right += 1) edges.push(ids[left] + '->' + ids[right]);
  }
  return edges;
}
```

- [ ] **Step 5: 补充四设备六边断言并运行测试。**

```ts
expect(planFullMeshEdges(['d', 'c', 'b', 'a'])).assertDeepEquals([
  'a->b', 'a->c', 'a->d', 'b->c', 'b->d', 'c->d'
]);
```

运行：统一验证命令。

预期：规划器的三设备、四设备、方向与自连接用例全部通过。

- [ ] **Step 6: 提交规划器。**

```bash
git add entry/src/main/ets/communication/PeerMeshPlanner.ets entry/src/test/PeerMeshPlanner.test.ets entry/src/test/List.test.ets
git commit -m "feat: add deterministic peer mesh planner"
```

### Task 2: 提供稳定本机身份和设备状态监听

**文件：**
- Create: `entry/src/main/ets/communication/DeviceTopologyProvider.ets`
- Create: `entry/src/test/DeviceTopologyProvider.test.ets`
- Modify: `entry/src/main/ets/communication/TrustedDeviceResolver.ets`
- Modify: `entry/src/test/TrustedDeviceResolver.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入拓扑提供器的失败测试及可替换平台接口。**

```ts
export interface DeviceTopologySnapshot { localDeviceId: string; peers: PeerDevice[]; }
export interface DeviceTopologyProvider {
  start(onChanged: () => void): void;
  snapshot(): Promise<DeviceTopologySnapshot>;
  stop(): void;
}

export interface DeviceTopologyPlatform {
  localNetworkId(): string;
  availableDevices(): Promise<AvailableDeviceInfo[]>;
  onDeviceStateChanged(listener: () => void): void;
  offDeviceStateChanged(listener: () => void): void;
  release(): void;
}

export class HarmonyDeviceTopologyProvider implements DeviceTopologyProvider {
  constructor(bundleName: string, platform?: DeviceTopologyPlatform);
  start(onChanged: () => void): void;
  snapshot(): Promise<DeviceTopologySnapshot>;
  stop(): void;
}
```

测试应验证：`networkId` 优先于 `deviceId`、快照按 `deviceId` 排序去重、`start()` 只订阅一次、状态变化仅调用一次回调、`stop()` 取消订阅并释放平台。

- [ ] **Step 2: 运行测试确认失败。**

运行：统一验证命令。

预期：编译失败，指出 `DeviceTopologyProvider` 模块不存在。

- [ ] **Step 3: 实现生产平台和快照提供器。**

```ts
class HarmonyDeviceTopologyPlatform implements DeviceTopologyPlatform {
  private readonly manager: distributedDeviceManager.DeviceManager;
  private callback: (() => void) | undefined;

  constructor(bundleName: string) { this.manager = distributedDeviceManager.createDeviceManager(bundleName); }
  localNetworkId(): string { return this.manager.getLocalDeviceNetworkId(); }
  async availableDevices(): Promise<AvailableDeviceInfo[]> { return await this.manager.getAvailableDeviceList(); }
  onDeviceStateChanged(listener: () => void): void {
    this.callback = listener;
    this.manager.on('deviceStateChange', (): void => listener());
  }
  offDeviceStateChanged(_listener: () => void): void {
    if (this.callback !== undefined) this.manager.off('deviceStateChange');
    this.callback = undefined;
  }
  release(): void { distributedDeviceManager.releaseDeviceManager(this.manager); }
}
```

`DeviceTopologyProvider.snapshot()` 必须在本机 ID 为空时抛出
`new AppError('E_LOCAL_DEVICE_ID_UNAVAILABLE', 'local network id unavailable', ErrorStage.SELECTION, true)`；远端设备使用现有 `mapAvailableDevice()` 转换、去重并排序。

- [ ] **Step 4: 使 `TrustedDeviceResolver` 复用同一映射语义。**

保留 `AvailableDeviceProvider`、`resolveAll()` 和 `resolveUnique()` 的公共签名。将现有去重排序抽取为导出的纯函数：

```ts
export function uniqueSortedPeers(devices: PeerDevice[]): PeerDevice[] {
  const unique = new Map<string, PeerDevice>();
  for (const device of devices) if (device.deviceId.length > 0 && !unique.has(device.deviceId)) unique.set(device.deviceId, device);
  return Array.from(unique.values()).sort((left: PeerDevice, right: PeerDevice): number =>
    left.deviceId < right.deviceId ? -1 : (left.deviceId > right.deviceId ? 1 : 0));
}
```

- [ ] **Step 5: 运行新增和既有解析器测试。**

运行：统一验证命令。

预期：新提供器测试与现有 `TrustedDeviceResolver` 测试均通过，且 `release()` 只发生一次。

- [ ] **Step 6: 提交拓扑提供器。**

```bash
git add entry/src/main/ets/communication/DeviceTopologyProvider.ets entry/src/main/ets/communication/TrustedDeviceResolver.ets entry/src/test/DeviceTopologyProvider.test.ets entry/src/test/TrustedDeviceResolver.test.ets entry/src/test/List.test.ets
git commit -m "feat: expose local device topology"
```

### Task 3: 在控制 Hub 中收敛重复会话

**文件：**
- Modify: `entry/src/main/ets/communication/control/DskControlHub.ets`
- Modify: `entry/src/test/DskControlHub.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 扩展 `FakeApi` 并写入失败测试。**

在 `DskControlHub.test.ets` 中新增能同时建立入站和出站会话的测试，覆盖以下断言：

```ts
it('prefersOutboundForTheLexicallySmallerDevice', 0, async () => {
  const api = new FakeApi();
  const hub = new DskControlHub(context, 'b', new Logger(), api, listener, 'device-a');
  await hub.connect(peer('device-b'));
  hub.accept(acceptWant('device-b'));
  api.emitConnect(2);
  expect(hub.canonicalSessionDirection('device-b')).assertEqual('OUTBOUND');
  expect(api.disconnects.length).assertEqual(1);
});

it('deduplicatesAcrossTemporarySessions', 0, () => {
  // 将同一个 messageId 分别送入设备 b 的两个会话。
  expect(messages.length).assertEqual(1);
});
```

- [ ] **Step 2: 运行测试确认失败。**

运行：统一验证命令。

预期：编译失败，指出构造函数尚不接收本机 ID，且不存在 `canonicalSessionDirection()`。

- [ ] **Step 3: 给会话记录方向和规范会话选择。**

将 `Session` 改为如下结构，并在出站 `connect()` 中使用 `OUTBOUND`，入站 `accept()` 中使用 `INBOUND`：

```ts
type SessionDirection = 'INBOUND' | 'OUTBOUND';
interface Session {
  device: PeerDevice;
  id: number;
  state: ControlChannelState;
  direction: SessionDirection;
  createdOrder: number;
}
```

在构造函数追加可选 `localDeviceId: string = ''`，并将字段设为可变，以保持旧测试和生产调用兼容。新增：

```ts
private preferredDirection(deviceId: string): SessionDirection | undefined {
  if (this.localDeviceId.length === 0 || this.localDeviceId === deviceId) return undefined;
  return this.localDeviceId < deviceId ? 'OUTBOUND' : 'INBOUND';
}

setLocalDeviceId(deviceId: string): void {
  this.localDeviceId = deviceId;
}

private canonical(deviceId: string): Session | undefined {
  const ready = (this.sessionsByDevice.get(deviceId) ?? []).filter((item: Session): boolean => item.state === 'READY');
  const preferred = this.preferredDirection(deviceId);
  return ready.find((item: Session): boolean => item.direction === preferred) ?? ready.sort((a, b) => a.createdOrder - b.createdOrder)[0];
}
```

`waitForReady()` 和 `send()` 必须使用 `canonical(deviceId)`。在 `ready()` 内，当首选会话已准备好时，调用 `remove()` 关闭同设备的其他就绪或连接中会话；不得关闭刚刚被选中的会话。

- [ ] **Step 4: 将去重缓存改为逐设备有界缓存。**

替换会话内 `seen` 集合：

```ts
private readonly seenByDevice = new Map<string, string[]>();
private isDuplicate(deviceId: string, messageId: string): boolean {
  const ids = this.seenByDevice.get(deviceId) ?? [];
  if (ids.indexOf(messageId) >= 0) return true;
  ids.push(messageId);
  if (ids.length > 256) ids.shift();
  this.seenByDevice.set(deviceId, ids);
  return false;
}
```

在 `message()` 解码控制信封后调用 `isDuplicate(d, e.messageId)`。`disconnect()`、设备彻底移除和 `destroy()` 时清除该设备缓存。

- [ ] **Step 5: 运行控制 Hub 测试。**

运行：统一验证命令。

预期：既有入站、出站、发送等待和断线隔离测试继续通过；新增首选方向、临时重复会话和跨会话去重测试通过。

- [ ] **Step 6: 提交会话收敛实现。**

```bash
git add entry/src/main/ets/communication/control/DskControlHub.ets entry/src/test/DskControlHub.test.ets entry/src/test/List.test.ets
git commit -m "feat: converge duplicate peer control sessions"
```

### Task 4: 让 TLS 协调器只负责单对设备连接

**文件：**
- Modify: `entry/src/main/ets/communication/tls/Task3TlsCoordinator.ets`
- Modify: `entry/src/test/PeerConnectionPool.test.ets`
- Create: `entry/src/test/Task3TlsCoordinator.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入网格所需的失败测试。**

测试新增 `setLocalDeviceId(deviceId)`、`registerPeers(peers)`、`isReady(deviceId)` 和 `disconnectPeer(deviceId)` 行为：注册不会拨号；入站设备会成为可绑定节点；关闭一个设备不会关闭另一个设备。

```ts
await coordinator.registerPeers([PEER_B, PEER_C]);
expect(coordinator.isReady('remote-b')).assertFalse();
await coordinator.connect(PEER_B);
await coordinator.connect(PEER_C);
expect(coordinator.isReady('remote-b')).assertTrue();
expect(coordinator.isReady('remote-c')).assertTrue();
await coordinator.disconnectPeer('remote-b');
expect(coordinator.pool.stateOf('remote-c')).assertEqual('READY');
```

- [ ] **Step 2: 运行测试确认失败。**

运行：统一验证命令。

预期：编译失败，指出上述网格边界方法不存在。

- [ ] **Step 3: 实现注册、状态和逐设备关闭 API。**

```ts
async registerPeers(peers: PeerDevice[]): Promise<void> {
  this.peers.clear();
  for (const peer of peers) this.peers.set(peer.deviceId, peer);
  await this.pool.refreshPeers(Array.from(this.peers.values()));
  for (const peer of peers) this.installDataHandler(peer.deviceId);
}

setLocalDeviceId(deviceId: string): void {
  this.dsk.setLocalDeviceId(deviceId);
}

isReady(deviceId: string): boolean {
  return this.dsk.stateOf(deviceId) === 'READY' && this.pool.stateOf(deviceId) === 'READY';
}

async disconnectPeer(deviceId: string): Promise<void> {
  this.connecting.delete(deviceId);
  this.installedDataHandlers.delete(deviceId);
  this.peers.delete(deviceId);
  this.failures.delete(deviceId);
  await this.dsk.disconnect(deviceId);
  await this.pool.refreshPeers(Array.from(this.peers.values()));
}
```

`Task3TlsCoordinator` 构造 `DskControlHub` 的调用保持兼容；网格首次取得拓扑快照后调用 `setLocalDeviceId(deviceId)`，只有非空值才影响规范方向。

- [ ] **Step 4: 保持入站绑定兼容。**

`accept()` 必须继续将入站 `PeerInfo.deviceId` 加入 `peers` 并刷新连接池。`onControlReady()` 仍只发布状态；只有 `PeerMeshOrchestrator` 调用 `connect(peer)` 来决定主动连接。

- [ ] **Step 5: 运行协调器、连接池和控制 Hub 回归测试。**

运行：统一验证命令。

预期：单对连接、入站绑定、逐设备关闭与状态观察全部通过。

- [ ] **Step 6: 提交单对设备 API。**

```bash
git add entry/src/main/ets/communication/tls/Task3TlsCoordinator.ets entry/src/test/Task3TlsCoordinator.test.ets entry/src/test/PeerConnectionPool.test.ets entry/src/test/List.test.ets
git commit -m "feat: expose peer lifecycle for mesh coordination"
```

### Task 5: 实现全网格生命周期协调器

**文件：**
- Create: `entry/src/main/ets/communication/PeerMeshOrchestrator.ets`
- Create: `entry/src/test/PeerMeshOrchestrator.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 创建带可控时钟和计时器的失败测试。**

定义测试依赖，避免依赖真实 `setTimeout`：

```ts
export interface MeshTimer {
  after(delayMs: number, callback: () => void): number;
  cancel(id: number): void;
  now(): number;
  sleep(delayMs: number): Promise<void>;
}
export interface MeshPeerTransport {
  setLocalDeviceId(deviceId: string): void;
  registerPeers(peers: PeerDevice[]): Promise<void>;
  connect(peer: PeerDevice): Promise<void>;
  disconnectPeer(deviceId: string): Promise<void>;
  isReady(deviceId: string): boolean;
}

export interface PeerMeshController {
  start(): Promise<void>;
  reconcile(): Promise<void>;
  ensureReady(waitBudgetMs: number): Promise<string[]>;
  knownPeers(): PeerDevice[];
  destroy(): void;
}
```

测试必须覆盖：主拨号方立即连接；入站等待方在 3000 毫秒前不拨号、到期后兜底拨号；失败后依次安排 1000、2000、4000、8000、30000 毫秒；设备移除只取消自身计时器；并发 `reconcile()` 不重叠；`destroy()` 后不再执行回调。

- [ ] **Step 2: 运行测试确认失败。**

运行：统一验证命令。

预期：编译失败，指出 `PeerMeshOrchestrator` 模块不存在。

- [ ] **Step 3: 实现协调器的状态和常量。**

```ts
const INBOUND_GRACE_MS = 3000;
const RETRY_DELAYS_MS: number[] = [1000, 2000, 4000, 8000, 30000];

interface PeerMeshState {
  peer: PeerDevice;
  graceTimer: number | undefined;
  retryTimer: number | undefined;
  retryAttempt: number;
}
```

`PeerMeshOrchestrator` 构造函数为 `constructor(provider: DeviceTopologyProvider, transport: MeshPeerTransport, timer?: MeshTimer)`，并实现 `PeerMeshController`。`reconcile()` 读取 `DeviceTopologyProvider.snapshot()`，先调用 `transport.setLocalDeviceId(snapshot.localDeviceId)`，再调用 `transport.registerPeers(snapshot.peers)`，删除已不存在的状态，且对每个保留节点根据 `planPeerRole(snapshot.localDeviceId, peer.deviceId)` 调用 `ensurePeer()`。

- [ ] **Step 4: 实现串行协调和逐设备重试。**

```ts
async reconcile(): Promise<void> {
  if (this.destroyed) return;
  if (this.reconciling !== undefined) { this.reconcileAgain = true; await this.reconciling; return; }
  this.reconciling = this.reconcileOnce();
  try { await this.reconciling; }
  finally {
    this.reconciling = undefined;
    if (this.reconcileAgain) { this.reconcileAgain = false; await this.reconcile(); }
  }
}
```

`ensurePeer()` 在主拨号方调用 `attemptConnect()`；入站等待方启动一次宽限计时器。`attemptConnect()` 失败时仅为该设备调用 `scheduleRetry()`。`scheduleRetry()` 用 `Math.min(retryAttempt, RETRY_DELAYS_MS.length - 1)` 选择延迟，并且不得替换其他设备的计时器。

- [ ] **Step 5: 实现查询准备和销毁。**

```ts
async ensureReady(waitBudgetMs: number): Promise<string[]> {
  await this.reconcile();
  const deadline = this.timer.now() + waitBudgetMs;
  while (this.timer.now() < deadline && this.hasPendingConnections()) await this.timer.sleep(25);
  return this.readyDeviceIds();
}
```

`start()` 调用 `provider.start()` 注册一个 300 毫秒合并回调，然后执行首次 `reconcile()`。同时公开 `knownPeers(): PeerDevice[]`，返回最后一次快照的排序副本。`destroy()` 必须停止拓扑提供器、取消所有宽限和重试计时器、清空状态，之后调用 `disconnectPeer()` 逐个关闭已知节点。

- [ ] **Step 6: 运行协调器测试。**

运行：统一验证命令。

预期：所有计时器由假计时器可观测地创建和取消；没有真实等待；主拨号、兜底、退避、移除和销毁用例通过。

- [ ] **Step 7: 提交网格协调器。**

```bash
git add entry/src/main/ets/communication/PeerMeshOrchestrator.ets entry/src/test/PeerMeshOrchestrator.test.ets entry/src/test/List.test.ets
git commit -m "feat: coordinate decentralized peer mesh"
```

### Task 6: 将网格接入运行时、权限和查询路径

**文件：**
- Modify: `entry/src/main/ets/runtime/AppRuntime.ets`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `entry/src/test/AppRuntime.test.ets`
- Modify: `entry/src/test/AutomaticQueryUi.test.ets`

- [ ] **Step 1: 写入运行时依赖和查询预算的失败测试。**

在 `RuntimeDependencies` 增加可注入网格工厂：

```ts
meshFactory?: (tls: Task3TlsCoordinator | undefined, bundleName: string) => PeerMeshController | undefined;
```

测试使用假的网格断言：

```ts
await runtime.refreshAvailableDevices(true);
expect(mesh.reconcileCalls).assertEqual(1);
await runtime.submitAutomaticQuery('mesh query');
expect(mesh.ensureReadyBudgets).assertDeepEquals([3000]);
expect(mesh.readyIdsAtSubmit).assertDeepEquals(['remote-a', 'remote-b']);
```

另加测试：网格只返回 `remote-a` 时，自动查询来源列表为 `['local', 'remote-a']`，而不是连接尝试成功列表。

- [ ] **Step 2: 运行测试确认失败。**

运行：统一验证命令。

预期：编译失败，指出 `meshFactory`、`PeerMeshOrchestrator` 或新的调用点不存在。

- [ ] **Step 3: 在 `AppRuntime` 装配网格。**

在 `AppRuntime` 字段中增加 `private readonly mesh: PeerMeshController | undefined;`。构造函数中，创建 `Task3TlsCoordinator` 后构造网格：

```ts
this.mesh = dependencies.meshFactory?.(this.tls, bundleName) ?? this.createPeerMesh(context, bundleName);
```

`createPeerMesh()` 返回 `PeerMeshController | undefined`，使用 `new HarmonyDeviceTopologyProvider(bundleName)` 和 `Task3TlsCoordinator`；若 DSK 初始化失败，返回 `undefined`，保留单设备查询能力。

将 `refreshAvailableDevices(true)` 中的并行 `tls.connect(peer)` 循环替换为网格协调；`connectDiscovered` 为 `false` 时继续使用旧解析器只刷新列表：

```ts
if (connectDiscovered && this.mesh !== undefined) await this.mesh.reconcile();
const peers = connectDiscovered && this.mesh !== undefined ?
  this.mesh.knownPeers() : await this.resolverFactory().resolveAll();
this.replaceDiscoveredPeers(peers);
this.publishPeerStatuses();
```

新增私有 `replaceDiscoveredPeers(peers)`，先清空 `discoveredPeers` 再插入当前快照，复用现有状态投影代码。

- [ ] **Step 4: 将自动查询改为使用就绪快照。**

在 `submitAutomaticQuery()` 的 `try` 块开头替换当前“解析全部设备并等待所有连接”的逻辑：

```ts
const readyIds = await (this.mesh?.ensureReady(3000) ?? Promise.resolve<string[]>([]));
const readyPeers = readyIds.map((id: string): PeerDevice | undefined => this.discoveredPeers.get(id))
  .filter((peer: PeerDevice | undefined): peer is PeerDevice => peer !== undefined);
```

`automaticSourceNames` 使用 `['local'].concat(readyPeers...)`；`automaticExcludedSourceNames` 使用当前已发现但不在 `readyIds` 的设备。不要在查询路径再调用 `tls.connect()`，后台网格负责重连。

- [ ] **Step 5: 在生命周期中启动、刷新和销毁网格。**

新增运行时公开方法；启动和刷新后都要用 `mesh.knownPeers()` 更新 `discoveredPeers` 并发布状态：

```ts
async startPeerMesh(): Promise<void> { await this.mesh?.start(); }
async refreshPeerMesh(): Promise<void> { await this.mesh?.reconcile(); }
```

`EntryAbility` 权限成功时改为 `startPeerMesh()`；`onForeground()` 改为 `refreshPeerMesh()`。`AppRuntime.destroy()` 在销毁 TLS 前调用 `this.mesh?.destroy()`。

- [ ] **Step 6: 运行运行时和自动查询回归测试。**

运行：统一验证命令。

预期：无设备时本机查询继续通过；已有设备状态投影继续正确；查询只等待 3000 毫秒网格预算；权限和前台路径均触发网格协调。

- [ ] **Step 7: 提交运行时接入。**

```bash
git add entry/src/main/ets/runtime/AppRuntime.ets entry/src/main/ets/entryability/EntryAbility.ets entry/src/test/AppRuntime.test.ets entry/src/test/AutomaticQueryUi.test.ets
git commit -m "feat: run queries over decentralized peer mesh"
```

### Task 7: 扩展全网格测试夹具并验证任意节点查询

**文件：**
- Modify: `entry/src/test/support/MultiDeviceFixtures.ets`
- Modify: `entry/src/test/MultiDeviceEndToEnd.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入对称三设备查询的失败用例。**

```ts
it('allowsEveryDeviceToQueryTheOtherTwo', 0, async () => {
  const fixture = new MultiDeviceFixture();
  await fixture.connectFullMesh();
  fixture.setEvidence('device-a', [evidence('a-alpha', 'alpha')]);
  fixture.setEvidence('device-b', [evidence('b-beta', 'beta')]);
  fixture.setEvidence('device-c', [evidence('c-gamma', 'gamma')]);

  expect((await fixture.runTaskFrom('device-a', makeTask('from-a'))).feedback).assertEqual('ENOUGH');
  expect((await fixture.runTaskFrom('device-b', makeTask('from-b'))).feedback).assertEqual('ENOUGH');
  expect((await fixture.runTaskFrom('device-c', makeTask('from-c'))).feedback).assertEqual('ENOUGH');
});

it('keepsTheRemainingPairQueryableWhenOneDeviceLeaves', 0, async () => {
  const fixture = new MultiDeviceFixture();
  await fixture.connectFullMesh();
  fixture.disconnect('device-c');
  expect(fixture.readyPeersOf('device-a')).assertDeepEquals(['device-b']);
  expect(fixture.readyPeersOf('device-b')).assertDeepEquals(['device-a']);
});
```

- [ ] **Step 2: 运行测试确认失败。**

运行：统一验证命令。

预期：编译失败，指出 `connectFullMesh()`、`runTaskFrom()` 和 `readyPeersOf()` 不存在。

- [ ] **Step 3: 将夹具改为按节点保存状态。**

新增节点模型并使每个节点同时拥有任务协调器与可被其他节点调用的响应路径：

```ts
interface FixtureNode {
  deviceId: string;
  connected: Set<string>;
  coordinator: MultiDeviceTaskCoordinator;
}
```

`connectFullMesh()` 必须通过 `planFullMeshEdges(['device-a', 'device-b', 'device-c'])` 建立三条边，并在两端分别标记对方就绪。`runTaskFrom(deviceId, task)` 只使用发起节点的就绪邻居；`disconnect(deviceId)` 必须从全部剩余节点移除该设备，而不是清空整张网。

- [ ] **Step 4: 增加临时重复会话和重连验收。**

在夹具中注入一次备用边，再调用规范会话选择逻辑，断言每个无序设备对只有一个有效连接。随后断开 `device-c` 并重新加入，断言 A-B 边的连接计数不变，A-C 和 B-C 两条边恢复。

- [ ] **Step 5: 运行全部多设备端到端测试。**

运行：统一验证命令。

预期：既有 A 发起查询用例继续通过；A、B、C 三个发起端均可聚合本机和远端证据；单节点离线时其余设备继续可查询；重连不重建无关边。

- [ ] **Step 6: 提交对称端到端覆盖。**

```bash
git add entry/src/test/support/MultiDeviceFixtures.ets entry/src/test/MultiDeviceEndToEnd.test.ets entry/src/test/List.test.ets
git commit -m "test: cover decentralized full-mesh queries"
```

### Task 8: 构建、真机验收和回归收尾

**文件：**
- Create: `docs/testing/decentralized-full-mesh-acceptance.md`
- Create: `docs/superpowers/2026-07-24-semalink-decentralized-full-mesh-control-progress.md`

- [ ] **Step 1: 创建三真机验收记录模板。**

文档必须包含固定记录项：设备 A/B/C 的 `networkId` 后四位、权限状态、每台显示的活动节点数、每对设备的规范会话方向、从 A/B/C 分别发起的查询 ID、实际证据来源、离线设备、恢复时间、日志中的重复会话数和重试次数。

- [ ] **Step 2: 执行完整 ArkTS 测试。**

运行：统一验证命令。

预期：退出码 `0`；记录总测试数、失败数 `0` 和编译警告数量。

- [ ] **Step 3: 构建可安装 HAP。**

```powershell
$devecoNode = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigorScript = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
& $devecoNode $hvigorScript --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
```

预期：退出码 `0`，生成 `entry\build\default\outputs\default\entry-default-signed.hap`。

- [ ] **Step 4: 在三台互信设备上验收。**

1. 为三台设备安装同一 HAP 并启动应用。
2. 在三台设备均在前台时，确认每台都显示另外两台，活动节点数为 2。
3. 分别在 A、B、C 发起同一类查询，记录本机和另外两台的来源证据。
4. 让 C 离线，确认 A-B 仍互相 `READY` 且可查询。
5. 让 C 回到前台，确认 A-C、B-C 自动恢复且 A-B 未重连。
6. 将结果、设备标识后四位和日志证据填入验收记录。

- [ ] **Step 5: 写入进度文档并提交收尾。**

```bash
git add docs/testing/decentralized-full-mesh-acceptance.md docs/superpowers/2026-07-24-semalink-decentralized-full-mesh-control-progress.md
git commit -m "docs: record full mesh verification"
```

## 计划自审

- 规格覆盖：Task 1 覆盖确定性所有权；Task 2 覆盖本机身份与设备监听；Task 3 覆盖规范会话和有界去重；Task 4-6 覆盖连接、生命周期、查询预算与权限前台入口；Task 7 覆盖任意节点查询、离线隔离和重连；Task 8 覆盖全量测试、构建与三真机验收。
- 占位文本检查：未发现未完成标记；每个任务均包含测试、失败确认、最小实现、通过确认和提交命令。
- 类型一致性：`MeshDialRole`、`MeshSessionDirection`、`DeviceTopologyProvider`、`MeshPeerTransport`、`PeerMeshOrchestrator`、`registerPeers()`、`disconnectPeer()`、`ensureReady()` 的定义和后续使用保持一致。
