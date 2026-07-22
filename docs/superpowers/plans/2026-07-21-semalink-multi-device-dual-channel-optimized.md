# SemaLink 三设备双通道实现计划（鸿蒙原生能力优先优化版）

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐项执行。所有步骤使用复选框跟踪，任何任务未通过测试与构建前不得进入下一任务。

**目标：** 在三台 HarmonyOS NEXT API 24 真机上完成一个可重复演示：发起设备将同一语义查询并行下发给本机和至少两台可信远端设备，DSK 仅承载控制消息，NetworkKit TLS 承载任务与证据数据，发起端合并证据、去重、判断充分性，并输出一个最终结果。

**架构：** 采用“鸿蒙原生能力层—SemaLink 薄封装层—SemaLink 核心业务层”三层结构。设备发现、跨设备协同会话、TLS、SHA-256、安全随机数、网络信息、构建和测试直接调用鸿蒙能力；多设备状态管理、DSK-TLS 绑定、语义路由、并行子任务、证据聚合、充分性判断与早停由 SemaLink 实现。

**技术栈：** HarmonyOS NEXT API 24、ArkTS、`@kit.DistributedServiceKit`、`@kit.NetworkKit`、`@kit.CryptoArchitectureKit`、ArkData、ArkUI、`@ohos/hypium`、Hvigor、PowerShell、HDC、OpenSSL（仅用于生成不提交仓库的演示证书）。

---

## 1. 本次优化结论

原计划的总体方向正确，但同时引入了多设备目录、多会话 DSK、TLS、绑定协议、分页 ACK、窗口重传、聚合、协调器和三真机验收，首轮实现范围过大。

本优化版作出以下调整：

| 原计划内容 | 优化处理 | 原因 |
|---|---|---|
| 自己维护可信设备发现逻辑 | 由鸿蒙设备管理能力提供真实设备列表，SemaLink 只保存业务状态 | 避免重复实现系统能力 |
| 单独拆分 DSK、TLS、绑定为多个大任务 | 合并为“控制通道”和“数据通道与绑定”两个完整可验收任务 | 减少跨任务接口漂移 |
| 自己实现 SHA-256 和随机数算法 | 直接调用 Crypto Architecture Kit | 降低安全风险 |
| MVP 即实现窗口 4、逐页 ACK、三次重试 | 移入增强阶段 | TLS/TCP 已保证有序可靠传输，首版先打通三真机闭环 |
| 每个证据页独立完成复杂状态机 | MVP 每设备、每轮发送一个受预算限制的 `EVIDENCE_BATCH` | 简化通信状态与故障定位 |
| 12 个任务全部作为首轮必做 | 调整为 8 个核心任务 + 1 个增强任务 | 每个核心任务都形成可独立验收的增量 |
| 一开始追求完整容错矩阵 | 先完成双机 TLS 探针，再完成三机业务闭环，最后补故障矩阵 | 降低真机联调风险 |
| ArkData 分布式同步全文或证据 | 不用于实时问答主链路，仅可同步设备知识画像 | 保持“按需查询、不传完整文件”的项目特点 |

### 1.1 MVP 必须完成

- 同时发现并保留两台可信远端设备。
- 为每台远端维护独立 DSK 控制会话。
- 为每台远端建立独立 NetworkKit TLS 数据通道。
- 使用一次性绑定令牌将 DSK 会话与 TLS 连接绑定。
- 一个逻辑任务同时在本机、远端 B、远端 C 执行。
- 每台设备最多返回分配预算内的必要证据，不返回完整文档。
- 发起端进行证据去重、冲突隔离和来源合并。
- L1 证据足够时不进入 L2；不足时只向相关设备请求 L2。
- 单台远端失败不影响其他设备。
- 三真机完成 7 个验收场景并保留日志证据。

### 1.2 首轮明确不做

以下能力不属于 MVP 完成条件：

- 窗口 4 的逐页并发发送。
- 每页 ACK、1.5 秒超时与三次应用层重试。
- 断线后的任务级续传。
- 证书自动轮换和正式 CA 体系。
- 超过两台远端设备的性能优化。
- 跨公网或不同局域网的网络穿透。
- ArkData 全文、Chunk 或向量跨设备同步。
- PDF、OCR、表格等知识解析扩展。

这些内容统一放入 **Task 9：增强型可靠分页传输**，只有 MVP 三真机验收通过后才能开始。

---

## 2. 能力边界

### 2.1 直接调用鸿蒙能力

| 能力 | 鸿蒙组件 | SemaLink 的工作 |
|---|---|---|
| 可信设备获取与状态变化 | Distributed Service Kit 中的设备管理能力 | 包装为可注入 Provider，转换为统一 `PeerDevice` |
| 跨设备协同连接 | `abilityConnectionManager` | 管理多个 session，不重复实现底层会话 |
| 控制消息传输 | DSK 会话消息接口 | 定义小型控制协议、设备映射和去重 |
| TLS 客户端与服务端 | NetworkKit `TLSSocket` / `TLSSocketServer` | 封装连接、证书指纹校验和帧收发 |
| 网络地址获取 | NetworkKit connection 能力 | 选择非回环 IPv4 地址 |
| SHA-256 | Crypto Architecture Kit | 定义规范化证据内容并调用摘要接口 |
| 安全随机数 | Crypto Architecture Kit | 生成一次性绑定令牌 |
| 本地知识数据 | ArkData RDB | 保存文档、Chunk、设备知识画像 |
| UI 与状态展示 | ArkUI | 展示每个远端的控制、数据和任务状态 |
| 测试与构建 | Hypium、Hvigor、HDC | 编写测试和三设备部署脚本 |

### 2.2 必须由 SemaLink 实现

- `DeviceDirectory`：保存设备知识画像和每台设备的业务运行状态。
- `DskControlHub`：管理多个同时存在的 DSK 会话。
- `PeerConnectionPool`：把每个 DSK 控制会话与对应 TLS 数据通道关联。
- `MultiDeviceProtocolCodec`：验证数据面业务消息。
- `DeviceSemanticRouter`：根据查询和设备知识画像选择远端。
- `EvidenceBudgetAllocator`：分配全局字节预算。
- `PeerTaskResponder`：在远端执行 L1/L2 检索。
- `EvidenceAggregator`：去重、冲突隔离、来源合并。
- `MultiDeviceTaskCoordinator`：并行执行、超时、取消、L2 定向和最终结果冻结。
- 三设备故障测试、状态 UI 和验收记录。

---

## 3. 系统架构

```text
┌──────────────────────────────────────────────────────────────┐
│                    SemaLink 核心业务层                        │
│                                                              │
│  DeviceSemanticRouter                                        │
│  EvidenceBudgetAllocator                                     │
│  MultiDeviceTaskCoordinator ─────── PeerTaskResponder         │
│  EvidenceAggregator            SufficiencyEvaluator          │
└─────────────────────────────┬────────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────────┐
│                    SemaLink 薄封装层                          │
│                                                              │
│  HarmonyTrustedDeviceProvider → DeviceDirectory              │
│  DskControlHub                                                │
│  PeerConnectionPool                                           │
│  NetworkTlsChannel + TlsFrameCodec                            │
│  ControlCodec + MultiDeviceProtocolCodec                      │
└─────────────────────────────┬────────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────────┐
│                    HarmonyOS 原生能力层                       │
│                                                              │
│  Distributed Service Kit                                     │
│  abilityConnectionManager                                    │
│  NetworkKit TLS / connection                                 │
│  Crypto Architecture Kit                                     │
│  ArkData / ArkUI / Hypium / Hvigor / HDC                     │
└──────────────────────────────────────────────────────────────┘
```

### 3.1 查询数据流

```text
用户在设备 A 提问
    │
    ▼
DeviceSemanticRouter
    ├── 本机任务 A@local
    ├── 远端任务 A@remote-b
    └── 远端任务 A@remote-c
          │
          ├── DSK：PROFILE / ENDPOINT_OFFER / CANCEL / CLOSE
          └── TLS：TASK / TASK_ACK / EVIDENCE_BATCH / TSF / ERROR
    │
    ▼
EvidenceAggregator
    │
    ▼
SufficiencyEvaluator
    ├── ENOUGH：结束，不进入 L2
    └── NEED_MORE：只向匹配缺失概念的设备发送 L2 请求
    │
    ▼
一个冻结的最终结果
```

### 3.2 MVP 早停定义

首轮采用**轮次级早停**：

1. L1 本机和远端并行开始。
2. 当所有 L1 参与者结束，或 L1 截止时间到达时，统一评估。
3. 若 `ENOUGH`，不发起 L2，并取消仍未结束的远端。
4. 若 `NEED_MORE`，只向与缺失概念匹配且还有预算的设备发起 L2。
5. L2 结束或全局超时后冻结最终结果。

MVP 不采用“每收到一条证据立即结束”，以避免网络到达顺序导致结果集合不稳定。

---

## 4. 全局约束

- 项目目录：`C:\Users\admin\DevEcoStudioProjects\SemaLink`。
- 平台：HarmonyOS NEXT API 24。
- 保留当前分页、取消、超时和已有测试，不允许覆盖用户未提交修改。
- 不使用 `git reset --hard`、`git checkout -- .` 或其他破坏工作区的命令。
- 每个任务先写失败测试，再实现，再运行完整测试和构建。
- 生产代码必须通过依赖注入暴露鸿蒙 API 边界，单元测试不得依赖真机。
- DSK 只允许控制消息，不允许 `TASK`、`EVIDENCE_BATCH` 或证据正文。
- 控制消息编码后不超过 1024 字节。
- TLS 数据帧不超过 64 KiB。
- 日志不得记录完整设备 ID、绑定令牌、私钥、证书全文、查询正文或证据正文。
- 演示证书与私钥不得提交 Git。
- 所有 Map 对外返回排序后的副本，避免测试和结果依赖插入顺序。
- 单台远端的失败、断开、超时和取消不得清除其他远端状态。
- 所有终态必须清理计时器、监听器、缓存任务和未完成 Promise。

---

## 5. 基线验证

开始 Task 1 前运行：

```powershell
Set-Location 'C:\Users\admin\DevEcoStudioProjects\SemaLink'

$devecoNode = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigorScript = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'

& $devecoNode $hvigorScript `
  --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  test

if ($LASTEXITCODE -ne 0) {
  throw 'Baseline tests failed.'
}

& $devecoNode $hvigorScript `
  --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  assembleHap

if ($LASTEXITCODE -ne 0) {
  throw 'Baseline HAP build failed.'
}
```

预期：

- 两条命令退出码均为 0。
- Hypium 没有失败用例。
- 构建输出包含 `BUILD SUCCESSFUL`。
- 当前通信改动已单独提交，或已存在于执行工作树的起始提交中。

### 5.1 API 24 契约确认

曾经出现过 `.d.ts` 声明键名与真机运行时 `wantParam` 键名不同的问题，因此先记录本地 SDK 契约，不允许凭记忆实现。

创建：

```text
docs/testing/api24-native-contract.md
```

记录：

- 可信设备列表和监听接口的实际类型与函数签名。
- `abilityConnectionManager` 的创建、连接、接收、发送、断开接口。
- `TLSSocket`、`TLSSocketServer`、证书读取和本地地址接口。
- Crypto Kit SHA-256 与随机数接口。
- 接收端实际 `wantParam` 外层和内层运行时键名。
- 本地 SDK 路径、API 版本和记录日期。

可使用以下 PowerShell 定位声明：

```powershell
$sdkRoot = 'D:\Program Files\DevEco Studio\sdk'

Get-ChildItem $sdkRoot -Recurse -Filter '*.d.ts' -ErrorAction SilentlyContinue |
  Select-String -Pattern `
    'abilityConnectionManager|createAbilityConnectionSession|acceptConnect|constructTLSSocket|createMd|generateRandom|getAvailableDevice' |
  Select-Object Path, LineNumber, Line
```

---

## 6. 文件结构

| 文件 | 职责 |
|---|---|
| `entry/src/main/ets/communication/device/HarmonyTrustedDeviceProvider.ets` | 调用鸿蒙可信设备能力并转换为 `PeerDevice` |
| `entry/src/main/ets/communication/DeviceDirectory.ets` | 保存多设备知识画像与运行状态 |
| `entry/src/main/ets/communication/TrustedDeviceResolver.ets` | 返回排序后的全部可信设备并保留旧接口 |
| `entry/src/main/ets/communication/DeviceSemanticRouter.ets` | 基于画像和状态选择本机及远端 |
| `entry/src/main/ets/communication/control/ControlModels.ets` | DSK 控制消息 |
| `entry/src/main/ets/communication/control/ControlCodec.ets` | 控制消息严格校验和 1 KiB 限制 |
| `entry/src/main/ets/communication/control/CollaborationApi.ets` | `abilityConnectionManager` 可注入边界 |
| `entry/src/main/ets/communication/control/DskControlHub.ets` | 按设备和 session 管理多个 DSK 会话 |
| `entry/src/main/ets/communication/tls/TlsFrameCodec.ets` | 4 字节大端长度帧 |
| `entry/src/main/ets/communication/tls/ContentDigest.ets` | 调用 Crypto Kit 计算规范化 SHA-256 |
| `entry/src/main/ets/communication/tls/TlsMaterialProvider.ets` | 加载演示证书和私钥 |
| `entry/src/main/ets/communication/tls/NetworkEndpointResolver.ets` | 获取非回环 IPv4 地址 |
| `entry/src/main/ets/communication/tls/NetworkTlsChannel.ets` | NetworkKit TLS 客户端和服务端封装 |
| `entry/src/main/ets/communication/PeerConnectionPool.ets` | 每设备 DSK、TLS 和绑定状态 |
| `entry/src/main/ets/protocol/MultiDeviceProtocolModels.ets` | MVP 数据面消息模型 |
| `entry/src/main/ets/protocol/MultiDeviceProtocolCodec.ets` | 64 KiB 数据面校验 |
| `entry/src/main/ets/communication/EvidenceBudgetAllocator.ets` | 稳定的全局预算分配 |
| `entry/src/main/ets/communication/EvidenceAggregator.ets` | 确定性去重、冲突隔离和来源合并 |
| `entry/src/main/ets/communication/PeerTaskResponder.ets` | 执行远端 L1/L2 子任务 |
| `entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets` | 一个逻辑任务的并行协调 |
| `entry/src/main/ets/runtime/AppRuntime.ets` | 生产依赖装配和销毁 |
| `entry/src/main/ets/model/AppModels.ets` | 设备、通道和任务状态快照 |
| `entry/src/main/ets/state/AppStateStore.ets` | 不可变状态更新 |
| `entry/src/main/ets/pages/Index.ets` | 三设备状态和结果摘要 |
| `entry/src/test/support/FakeDskControlHub.ets` | 可独立故障注入的 DSK 假实现 |
| `entry/src/test/support/FakeTlsNetwork.ets` | 可延迟、断开、重复的 TLS 假网络 |
| `entry/src/test/support/MultiDeviceFixtures.ets` | 三设备测试夹具 |
| `scripts/deploy/New-DemoTlsMaterial.ps1` | 生成未提交的演示证书 |
| `scripts/deploy/Deploy-SemaLink.ps1` | 同一 HAP 部署至三台设备 |
| `docs/testing/multi-device-dual-channel-acceptance.md` | 三真机验收记录 |

---

# Task 1：鸿蒙可信设备接入与多设备目录

**目标：** 不自行实现设备发现，只把鸿蒙提供的可信设备列表转换为 SemaLink 设备对象，并保存每台设备独立的业务状态。

**Files:**

- Create: `entry/src/main/ets/communication/device/HarmonyTrustedDeviceProvider.ets`
- Modify: `entry/src/main/ets/communication/DeviceDirectory.ets`
- Modify: `entry/src/main/ets/communication/TrustedDeviceResolver.ets`
- Modify: `entry/src/main/ets/communication/DeviceSemanticRouter.ets`
- Modify: `entry/src/test/TrustedDeviceResolver.test.ets`
- Modify: `entry/src/test/DeviceSemanticRouter.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**

```typescript
export interface TrustedDeviceProvider {
  list(): Promise<PeerDevice[]>;
  release(): void;
}

export interface DirectoryEntry {
  snapshot: DeviceRuntimeSnapshot;
  profile: DeviceProfileAdvertisement;
  controlState: ControlChannelState;
  dataState: DataChannelState;
  endpointVersion: number;
  lastFailureCode: string;
}

export class TrustedDeviceResolver {
  constructor(provider: TrustedDeviceProvider);
  resolveAll(): Promise<PeerDevice[]>;
  resolveUnique(): Promise<PeerDevice>;
}

export class DeviceDirectory {
  upsertRemote(profile: DeviceProfileAdvertisement): void;
  removeRemote(deviceId: string): void;
  updateControlState(deviceId: string, state: ControlChannelState, failureCode?: string): void;
  updateDataState(deviceId: string, state: DataChannelState, failureCode?: string): void;
  candidates(): DirectoryEntry[];
  pruneExpired(): string[];
}
```

- [ ] **Step 1：写失败测试**

覆盖：

- 插入 `remote-b` 和 `remote-c` 后均存在。
- 删除 `remote-b` 不影响 `remote-c`。
- 只让 `remote-b` 过期时，`remote-c` 保留。
- `resolveAll()` 按 `deviceId` 排序。
- `resolveUnique()` 在两个设备时保持旧错误语义。
- Provider 无论成功或失败都只释放一次。
- 路由结果只选择 `READY` 远端。

```typescript
it('keeps remote entries independent', 0, () => {
  const now: number[] = [1000];
  const directory = new DeviceDirectory((): number => now[0]);

  directory.upsertRemote(makeAdvertisement('remote-c', 1000));
  directory.upsertRemote(makeAdvertisement('remote-b', 1000));
  directory.removeRemote('remote-b');

  const entries = directory.candidates();
  expect(entries.length).assertEqual(1);
  expect(entries[0].profile.deviceId).assertEqual('remote-c');
});

it('returns all trusted peers in stable order', 0, async () => {
  const resolver = new TrustedDeviceResolver(new FakeProvider([
    makePeer('remote-c'),
    makePeer('remote-b')
  ]));

  const peers = await resolver.resolveAll();
  expect(peers.length).assertEqual(2);
  expect(peers[0].deviceId).assertEqual('remote-b');
  expect(peers[1].deviceId).assertEqual('remote-c');
});
```

- [ ] **Step 2：运行测试并确认失败**

```powershell
& $devecoNode $hvigorScript --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  test
```

预期：因 `HarmonyTrustedDeviceProvider`、`resolveAll()` 或多设备目录接口不存在而编译失败。

- [ ] **Step 3：实现鸿蒙 Provider**

`HarmonyTrustedDeviceProvider` 只负责：

1. 调用 `api24-native-contract.md` 中已确认的可信设备列表接口。
2. 将系统设备对象转换为项目统一的 `PeerDevice`。
3. 过滤空 `deviceId`。
4. 去重并按 `deviceId` 排序。
5. 释放系统 DeviceManager 或监听资源。

不在 Provider 中保存控制、TLS、任务或知识画像状态。

- [ ] **Step 4：将目录改为多条目 Map**

```typescript
private readonly remotes: Map<string, DirectoryEntry> =
  new Map<string, DirectoryEntry>();

upsertRemote(profile: DeviceProfileAdvertisement): void {
  const previous = this.remotes.get(profile.deviceId);
  this.remotes.set(profile.deviceId, {
    snapshot: this.remoteSnapshot(profile, previous),
    profile: profile,
    controlState: previous?.controlState ?? 'DISCONNECTED',
    dataState: previous?.dataState ?? 'DISCONNECTED',
    endpointVersion: previous?.endpointVersion ?? 0,
    lastFailureCode: previous?.lastFailureCode ?? ''
  });
}

removeRemote(deviceId: string): void {
  this.remotes.delete(deviceId);
}
```

`candidates()` 返回克隆后的数组，并按 `profile.deviceId` 排序。

- [ ] **Step 5：更新语义路由**

增加：

```typescript
selectParallel(result: RoutingResult, maximumRemoteCount: number): RoutedDevice[]
```

规则：

1. 本机始终保留。
2. 远端必须同时满足可信、画像新鲜、控制通道可用、数据通道可用。
3. 按 `routeScore` 降序。
4. 同分时按 `deviceId` 升序。
5. MVP 最多选择两台远端。

- [ ] **Step 6：运行测试和构建**

预期：所有旧单设备测试和新增多设备测试通过。

- [ ] **Step 7：提交**

```powershell
git add `
  entry/src/main/ets/communication/device/HarmonyTrustedDeviceProvider.ets `
  entry/src/main/ets/communication/DeviceDirectory.ets `
  entry/src/main/ets/communication/TrustedDeviceResolver.ets `
  entry/src/main/ets/communication/DeviceSemanticRouter.ets `
  entry/src/test/TrustedDeviceResolver.test.ets `
  entry/src/test/DeviceSemanticRouter.test.ets `
  entry/src/test/List.test.ets

git commit -m "feat: use native trusted devices in multi-device directory"
```

**完成门：** 测试中同时存在两个远端；删除或过期其中一个不会影响另一个。

---

# Task 2：多会话 DSK 控制中心

**目标：** 直接调用鸿蒙跨设备协同能力，同时支持至少两条独立入站或出站 DSK 会话。

**Files:**

- Create: `entry/src/main/ets/communication/control/ControlModels.ets`
- Create: `entry/src/main/ets/communication/control/ControlCodec.ets`
- Create: `entry/src/main/ets/communication/control/CollaborationApi.ets`
- Create: `entry/src/main/ets/communication/control/DskControlHub.ets`
- Modify: `entry/src/main/ets/communication/CollaborationTransport.ets`
- Create: `entry/src/test/ControlCodec.test.ets`
- Create: `entry/src/test/DskControlHub.test.ets`
- Modify: `entry/src/test/List.test.ets`

**控制面只允许：**

```typescript
export type ControlMessageType =
  | 'PROFILE'
  | 'DATA_ENDPOINT_OFFER'
  | 'TASK_CANCEL'
  | 'CONTROL_CLOSE';
```

**禁止经 DSK 发送：**

```text
TASK
TASK_ACK
EVIDENCE_BATCH
EVIDENCE_COMPLETE
TSF
ERROR
文档正文
证据正文
```

**Interfaces:**

```typescript
export interface ControlEnvelope {
  version: '1.0';
  type: ControlMessageType;
  messageId: string;
  deviceId: string;
  sentAtMs: number;
  payload:
    | DeviceProfileAdvertisement
    | DataEndpointOffer
    | TaskCancelControl
    | ControlClose;
}

export interface DskControlHubListener {
  onControlReady(deviceId: string): void;
  onControlMessage(deviceId: string, envelope: ControlEnvelope): void;
  onControlClosed(deviceId: string, error?: AppError): void;
}

export class DskControlHub {
  connect(peer: PeerDevice): Promise<void>;
  accept(wantParam: Record<string, Object>): boolean;
  send(deviceId: string, envelope: ControlEnvelope): Promise<void>;
  disconnect(deviceId: string): Promise<void>;
  stateOf(deviceId: string): ControlChannelState;
  deviceIds(): string[];
  destroy(): void;
}
```

- [ ] **Step 1：写失败测试**

覆盖：

- 两个出站 session 同时 READY。
- 两个入站 `accept()` 不互相替换。
- `remote-b` 断开后 `remote-c` 仍可发送控制消息。
- 设备级发送只使用对应 session。
- 超过 1024 字节的控制消息被拒绝。
- 未知类型、空 `messageId`、非法端口、已过期 endpoint 被拒绝。
- 重复 `messageId` 只分发一次。
- DSK 中出现 `EVIDENCE_BATCH` 时编码器直接拒绝。

```typescript
it('isolates disconnects by device', 0, async () => {
  const api = new FakeCollaborationApi();
  const hub = makeHub(api);

  await hub.connect(makePeer('remote-b'));
  await hub.connect(makePeer('remote-c'));

  api.emitDisconnect(api.sessionFor('remote-b'), 1001);

  expect(hub.stateOf('remote-b')).assertEqual('FAILED');
  expect(hub.stateOf('remote-c')).assertEqual('READY');

  await hub.send('remote-c', makeClose('close-c', 'remote-c'));
  expect(api.sentFor('remote-c').length).assertEqual(1);
});
```

- [ ] **Step 2：运行测试并确认失败**

预期：控制模型或 `DskControlHub` 不存在导致编译失败。

- [ ] **Step 3：抽取可注入鸿蒙 API 边界**

把当前 `CollaborationTransport.ets` 中直接调用 `abilityConnectionManager` 的代码移动到：

```text
entry/src/main/ets/communication/control/CollaborationApi.ets
```

生产实现负责调用已验证的 API 24 接口；测试实现只记录：

- 创建的 session。
- session 与设备的对应关系。
- 发送消息。
- connect、disconnect、error、receiveMessage 事件。

旧 `CollaborationTransport` 通过相同接口继续工作，避免一次性破坏旧测试。

- [ ] **Step 4：实现严格控制编码器**

`ControlCodec.encode()`：

- 只接受四种控制消息。
- 使用 UTF-8 编码后的真实字节数检查 1024 字节上限。
- 不输出 payload 日志。
- 超限抛出 `E_CONTROL_FRAME_TOO_LARGE`。

`ControlCodec.decode()`：

- 验证 `version === '1.0'`。
- 验证所有字符串非空。
- 验证端口范围为 1～65535。
- 验证 `expiresAtMs > now()`。
- 拒绝原型污染键和未知字段类型。

- [ ] **Step 5：实现多会话 Hub**

内部状态：

```typescript
private readonly sessionsByDevice = new Map<string, DskPeerSession>();
private readonly deviceBySession = new Map<number, string>();
private readonly handledMessageIds = new Map<string, number>();
```

规则：

1. `connect(peer)` 只替换同一 `deviceId` 的旧 session。
2. `accept(wantParam)` 每次创建独立 session。
3. 回调先使用 `sessionId -> deviceId` 查找，再分发。
4. disconnect 只删除对应设备和 session。
5. 旧 session 的迟到事件因映射不存在而被忽略。
6. `destroy()` 才允许关闭全部 session。

- [ ] **Step 6：运行完整测试与构建**

预期：

- 原 `CollaborationTransport.test.ets` 继续通过。
- 新的两设备隔离测试通过。
- `assembleHap` 成功。

- [ ] **Step 7：提交**

```powershell
git add `
  entry/src/main/ets/communication/control `
  entry/src/main/ets/communication/CollaborationTransport.ets `
  entry/src/test/ControlCodec.test.ets `
  entry/src/test/DskControlHub.test.ets `
  entry/src/test/List.test.ets

git commit -m "feat: add multi-session DSK control hub"
```

**完成门：** 假测试中 B 断开后，C 的 session、状态和发送能力均保持不变。

---

# Task 3：NetworkKit TLS 数据通道与 DSK-TLS 绑定

**目标：** 直接使用 NetworkKit TLS 和 Crypto Kit，为每台远端建立独立数据通道，并通过 DSK 下发的一次性令牌完成通道绑定。

**Files:**

- Create: `entry/src/main/ets/communication/tls/TlsFrameCodec.ets`
- Create: `entry/src/main/ets/communication/tls/ContentDigest.ets`
- Create: `entry/src/main/ets/communication/tls/TlsMaterialProvider.ets`
- Create: `entry/src/main/ets/communication/tls/NetworkEndpointResolver.ets`
- Create: `entry/src/main/ets/communication/tls/NetworkTlsChannel.ets`
- Create: `entry/src/main/ets/communication/PeerConnectionPool.ets`
- Modify: `entry/src/main/ets/communication/control/ControlModels.ets`
- Create: `entry/src/test/TlsFrameCodec.test.ets`
- Create: `entry/src/test/ContentDigest.test.ets`
- Create: `entry/src/test/NetworkTlsChannel.test.ets`
- Create: `entry/src/test/PeerConnectionPool.test.ets`
- Create: `scripts/deploy/New-DemoTlsMaterial.ps1`
- Modify: `.gitignore`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**

```typescript
export interface DataEndpointOffer {
  host: string;
  port: number;
  certificateFingerprint: string;
  bindingToken: string;
  endpointVersion: number;
  expiresAtMs: number;
  dataProtocolVersion: '2.0';
}

export interface DataBindPayload {
  deviceId: string;
  controlSessionId: string;
  endpointVersion: number;
  sessionEpoch: string;
  bindingToken: string;
}

export interface DataBindAckPayload {
  deviceId: string;
  endpointVersion: number;
  sessionEpoch: string;
  acceptedAtMs: number;
}

export interface TlsDataChannel {
  connect(deviceId: string, offer: DataEndpointOffer): Promise<void>;
  send(text: string): Promise<void>;
  close(): Promise<void>;
  isReady(): boolean;
}

export class PeerConnectionPool {
  refreshPeers(peers: PeerDevice[]): Promise<void>;
  startResponderEndpoint(deviceId: string): Promise<DataEndpointOffer>;
  acceptBinding(payload: DataBindPayload): Promise<boolean>;
  send(deviceId: string, encodedEnvelope: string): Promise<void>;
  readyDeviceIds(): string[];
  stateOf(deviceId: string): PeerConnectionState;
  close(deviceId: string): Promise<void>;
  destroy(): Promise<void>;
}
```

- [ ] **Step 1：写帧、摘要、TLS 和绑定失败测试**

帧测试：

- 4 字节前缀在每个字节边界拆分。
- 两帧合并到一个 chunk。
- 一帧完整、一帧部分。
- 零长度拒绝。
- 超过 64 KiB 拒绝。
- 关闭时仍有部分帧则报错。

摘要测试：

- SHA-256(`abc`) 等于标准十六进制值。
- 相同证据内容来自不同设备时摘要相同。
- `coveredConcepts` 输入顺序不同，摘要仍相同。
- `evidenceId` 和 `sourceDeviceId` 不参与内容摘要。

TLS 与绑定测试：

- 证书指纹不匹配时发送任何业务帧前关闭。
- endpoint 过期时拒绝。
- endpointVersion 回退时拒绝。
- 一次性 token 重放时拒绝。
- 错误 deviceId 时拒绝。
- B 通道失败不清除 C。
- `destroy()` 幂等。

- [ ] **Step 2：实现长度帧**

```typescript
export const MAX_TLS_FRAME_BYTES: number = 64 * 1024;

export class TlsFrameCodec {
  private pending: Uint8Array = new Uint8Array(0);

  encode(text: string): Uint8Array;
  push(chunk: Uint8Array): string[];
  finish(): void;
}
```

格式：

```text
[4 字节无符号大端长度][UTF-8 JSON]
```

TLS 负责加密和可靠字节传输；`TlsFrameCodec` 只负责业务消息边界。

- [ ] **Step 3：实现规范化 SHA-256**

使用 Crypto Architecture Kit，不自行实现哈希算法。

规范化内容包含：

```text
level
title
summary
snippet
排序后的 coveredConcepts
relevance
estimatedCoverageGain
```

排除：

```text
evidenceId
sourceDeviceId
documentId
旧 hash 字段
```

摘要输出为小写两位十六进制字符串。

- [ ] **Step 4：实现 NetworkKit TLS 封装**

生产实现直接调用本地 API 24 契约文档中的：

- TLS 客户端构造和连接。
- TLS 服务端构造和监听。
- 远端证书读取。
- 本地监听地址读取。
- 网络连接属性查询。

连接顺序：

```text
DSK CONTROL_READY
    ↓
Responder 启动 TLS Server
    ↓
DSK 发送 DATA_ENDPOINT_OFFER
    ↓
Initiator 建立 TLS
    ↓
读取远端证书并计算 SHA-256
    ↓
与 DSK offer 指纹比较
    ↓
匹配后发送 DATA_BIND
    ↓
Responder 校验一次性 token
    ↓
DATA_BIND_ACK
    ↓
状态 READY
```

指纹不匹配时：

- 立即关闭 TLS。
- 不发送 `DATA_BIND`。
- 记录 `E_TLS_FINGERPRINT_MISMATCH`。
- 不打印证书全文。

- [ ] **Step 5：生成一次性绑定令牌**

使用 Crypto Kit 生成 16 字节安全随机数并编码为小写十六进制。

令牌规则：

- 只保存在内存。
- 与 `deviceId`、`endpointVersion` 和过期时间绑定。
- 第一次校验成功或失败后立即删除。
- 不能通过日志、UI 或状态快照暴露。
- 重放返回 `false` 并记录 `E_BIND_TOKEN_REPLAY`。

- [ ] **Step 6：生成演示证书脚本**

`scripts/deploy/New-DemoTlsMaterial.ps1`：

```powershell
$openssl = Get-Command openssl -ErrorAction Stop
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$materialDirectory = Join-Path $projectRoot `
  'entry\src\main\resources\rawfile\demo_tls'

New-Item -ItemType Directory -Force -Path $materialDirectory | Out-Null

$certificatePath = Join-Path $materialDirectory 'server-cert.pem'
$privateKeyPath = Join-Path $materialDirectory 'server-key.pem'

& $openssl.Source req -x509 -newkey rsa:2048 -sha256 -days 7 -nodes `
  -subj '/CN=SemaLink Demo TLS' `
  -keyout $privateKeyPath `
  -out $certificatePath

if ($LASTEXITCODE -ne 0) {
  throw 'OpenSSL failed to generate demo TLS material.'
}
```

`.gitignore` 增加：

```gitignore
entry/src/main/resources/rawfile/demo_tls/
```

- [ ] **Step 7：运行双真机 TLS 探针**

在 B 启动 TLS Server，通过 DSK 向 A 发送 endpoint offer；A 完成指纹验证和绑定后发送：

```text
TLS_PING
```

B 返回：

```text
TLS_PONG
```

记录：

- 设备 A、B 的脱敏 ID。
- 本地和远端 IP。
- TLS 协议版本。
- 证书指纹前 12 位。
- 连接耗时。
- DATA_BIND 与 ACK 是否成功。

硬门槛：

- 5 秒内建立 TLS。
- 指纹一致。
- `TLS_PING` 和 `TLS_PONG` 均到达。
- 日志没有私钥、令牌或证据正文。

- [ ] **Step 8：运行测试、构建并提交**

```powershell
git add `
  .gitignore `
  entry/src/main/ets/communication/tls `
  entry/src/main/ets/communication/PeerConnectionPool.ets `
  entry/src/main/ets/communication/control/ControlModels.ets `
  entry/src/test/TlsFrameCodec.test.ets `
  entry/src/test/ContentDigest.test.ets `
  entry/src/test/NetworkTlsChannel.test.ets `
  entry/src/test/PeerConnectionPool.test.ets `
  entry/src/test/List.test.ets `
  scripts/deploy/New-DemoTlsMaterial.ps1

git commit -m "feat: add bound NetworkKit TLS peer channels"
```

**完成门：** 双真机 TLS 探针通过后才能进入 Task 4。

---

# Task 4：MVP 数据协议与远端任务响应器

**目标：** 使用一个受预算限制的 `EVIDENCE_BATCH` 完成每台设备每轮的证据交付，不在 MVP 中实现逐页 ACK 和窗口重传。

**Files:**

- Create: `entry/src/main/ets/protocol/MultiDeviceProtocolModels.ets`
- Create: `entry/src/main/ets/protocol/MultiDeviceProtocolCodec.ets`
- Create: `entry/src/main/ets/communication/PeerTaskResponder.ets`
- Create: `entry/src/test/MultiDeviceProtocolCodec.test.ets`
- Create: `entry/src/test/PeerTaskResponder.test.ets`
- Modify: `entry/src/test/List.test.ets`

**MVP 数据消息：**

```typescript
export type DataMessageType =
  | 'DATA_BIND'
  | 'DATA_BIND_ACK'
  | 'TASK'
  | 'TASK_ACK'
  | 'EVIDENCE_BATCH'
  | 'EVIDENCE_COMPLETE'
  | 'TSF'
  | 'ERROR'
  | 'CANCEL';
```

**Interfaces:**

```typescript
export interface PeerContext {
  taskId: string;
  peerTaskId: string;
  sessionEpoch: string;
  sequence: number;
}

export interface EvidenceBatchPayload {
  taskId: string;
  peerTaskId: string;
  round: 1 | 2;
  evidence: EvidenceUnit[];
  batchDigest: string;
  encodedBytes: number;
}

export interface EvidenceCompletePayload {
  taskId: string;
  peerTaskId: string;
  round: 1 | 2;
  evidenceCount: number;
  truncatedByBudget: boolean;
}

export interface DataEnvelope {
  version: '2.0';
  type: DataMessageType;
  messageId: string;
  sentAtMs: number;
  peer: PeerContext;
  payload: ProtocolPayload;
}

export class PeerTaskResponder {
  onEnvelope(deviceId: string, envelope: DataEnvelope): Promise<void>;
  cancel(peerTaskId: string): void;
  destroy(): void;
}
```

- [ ] **Step 1：写协议失败测试**

覆盖：

- 所有消息 round trip。
- 未知版本和类型拒绝。
- `sequence <= 0` 拒绝。
- `peerTaskId` 不属于 `taskId@deviceId` 时拒绝。
- `EVIDENCE_BATCH` 超过 64 KiB 时拒绝。
- `batchDigest` 与规范化证据不一致时拒绝。
- 证据总字节超过分配预算时发送端截断而不是发送超限帧。
- DSK 控制编码器不能编码数据面消息。

- [ ] **Step 2：实现数据编码器**

`MultiDeviceProtocolCodec`：

- 只做结构和字节上限验证。
- 不维护 transport 或任务状态。
- 使用 `ContentDigest` 校验批次摘要。
- 拒绝不属于当前 sessionEpoch 的消息。
- `messageId`、`taskId`、`peerTaskId` 必须非空。

- [ ] **Step 3：写响应器失败测试**

覆盖：

- 第一次 TASK 先发送 `TASK_ACK`，再查询证据。
- 每个 `peerTaskId` 只调用一次本地检索 Provider。
- 重复 TASK 只重放缓存 ACK，不重复查询。
- L1 发送一个批次和一个 COMPLETE。
- 只有收到 `TSF(NEED_MORE)` 才执行 L2。
- `TSF(ENOUGH)`、CANCEL、ERROR 后清理缓存。
- 空结果也发送 `EVIDENCE_COMPLETE`。
- B 的错误不影响 C 的 responder 状态。
- 终态后迟到消息被忽略。

- [ ] **Step 4：实现响应器**

首次 TASK：

1. 验证 `peerTaskId` 归属。
2. 缓存处理过的 `messageId`。
3. 发送 `TASK_ACK`。
4. 调用本地知识检索一次。
5. 缓存候选证据。
6. 按分配预算选择 L1。
7. 编码为单个 `EVIDENCE_BATCH`。
8. 发送 `EVIDENCE_COMPLETE`。

收到 `TSF(NEED_MORE)`：

1. 从已缓存候选中选择 L2，不重新解析文档。
2. 限制在剩余预算内。
3. 发送一个 L2 批次。
4. 发送 COMPLETE。

收到终态消息：

- 删除候选证据。
- 删除任务计时器。
- 删除处理消息缓存。
- 取消未完成检索。
- 后续迟到消息不再改变状态。

- [ ] **Step 5：运行测试、构建并提交**

```powershell
git add `
  entry/src/main/ets/protocol/MultiDeviceProtocolModels.ets `
  entry/src/main/ets/protocol/MultiDeviceProtocolCodec.ets `
  entry/src/main/ets/communication/PeerTaskResponder.ets `
  entry/src/test/MultiDeviceProtocolCodec.test.ets `
  entry/src/test/PeerTaskResponder.test.ets `
  entry/src/test/List.test.ets

git commit -m "feat: add budgeted multi-device evidence batches"
```

**完成门：** Fake TLS 中 TASK、ACK、L1、NEED_MORE、L2 和 CANCEL 全流程通过，且不存在逐页 ACK 依赖。

---

# Task 5：预算分配、证据聚合与多设备协调器

**目标：** 将一个任务稳定地拆分为本机和两台远端子任务，聚合证据，并产生一个不可变的最终结果。

**Files:**

- Create: `entry/src/main/ets/communication/EvidenceBudgetAllocator.ets`
- Create: `entry/src/main/ets/communication/EvidenceAggregator.ets`
- Create: `entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets`
- Modify: `entry/src/main/ets/common/AppError.ets`
- Create: `entry/src/test/EvidenceBudgetAllocator.test.ets`
- Create: `entry/src/test/EvidenceAggregator.test.ets`
- Create: `entry/src/test/MultiDeviceTaskCoordinator.test.ets`
- Modify: `entry/src/test/List.test.ets`

**Interfaces:**

```typescript
export interface PeerTaskState {
  deviceId: string;
  peerTaskId: string;
  status: PeerTaskStatus;
  allocatedBytes: number;
  receivedBytes: number;
  evidenceCount: number;
  failureCode: string;
}

export interface VerifiedEvidence {
  evidence: EvidenceUnit;
  sourceDeviceId: string;
  contentDigest: string;
  round: 1 | 2;
}

export interface AggregatedEvidence {
  evidence: EvidenceUnit;
  contentDigest: string;
  sourceDeviceIds: string[];
  round: 1 | 2;
}

export class MultiDeviceTaskCoordinator {
  submit(task: TaskRequest): Promise<TaskSufficiencyResult>;
  cancel(taskId: string): Promise<void>;
  onEnvelope(deviceId: string, envelope: DataEnvelope): void;
  destroy(): void;
}
```

- [ ] **Step 1：写预算分配测试**

规则：

- 对候选设备按 `deviceId` 排序后再分配余数。
- 权重为 `max(0.01, routeScore)`。
- 单设备最少 512 字节。
- 单设备最多为总预算的 60%。
- 分配总和不超过 `TaskRequest.byteBudget`。
- 相同输入无论候选插入顺序如何，结果 JSON 完全一致。

- [ ] **Step 2：实现预算分配**

建议顺序：

1. 计算本机和远端候选权重。
2. 先分配最小值。
3. 剩余预算按权重分配。
4. 达到上限的设备不再参与下一轮分配。
5. 小数余数按 `deviceId` 升序补齐。
6. 若总预算不足以满足全部最小值，按路由分数降序选择参与者。

- [ ] **Step 3：写证据聚合测试**

覆盖：

- 相同 ID、相同摘要：合并来源。
- 相同 ID、不同摘要：所有版本进入冲突区，不进入有效证据。
- 不同 ID、相同摘要：保留字典序最小 ID，合并来源。
- 不同输入顺序输出完全一致。
- 来源设备 ID 排序。
- L1 结果排在 L2 前。
- 冲突证据不参与充分性计算。

- [ ] **Step 4：实现聚合器**

内部至少维护：

```typescript
private readonly digestByEvidenceId = new Map<string, Set<string>>();
private readonly canonicalByDigest = new Map<string, AggregatedEvidence>();
private readonly conflictsByEvidenceId = new Map<string, EvidenceConflict>();
```

`result()`：

1. 移除所有冲突 ID 的有效版本。
2. 同内容不同 ID 只保留字典序最小 ID。
3. 合并并排序来源设备。
4. 按 `round`、主来源设备、`evidenceId` 排序。
5. 返回克隆后的不可变结果。

- [ ] **Step 5：写协调器失败测试**

覆盖：

- 本机 + B + C 并行执行。
- B/C 返回互补证据后得到 `ENOUGH`。
- C 失败时仍使用本机和 B 完成。
- 两台远端重复证据只计算一次。
- L1 不足时只向匹配缺失概念的设备发起 L2。
- 所有参与者都无有效证据时返回 `E_ALL_PEERS_FAILED`。
- 全局超时时返回已有证据，不让迟到消息修改结果。
- 同时提交第二个任务返回 `E_BUSY`。
- 用户取消后 B/C 均收到取消控制消息。
- 每个终态后 FakeScheduler 没有待处理计时器。

- [ ] **Step 6：实现协调器**

提交任务时：

```text
validate task
    ↓
select local + at most two READY remotes
    ↓
allocate byte budget
    ↓
create peerTaskId = taskId + '@' + deviceId
    ↓
local search and remote TASK run concurrently
    ↓
wait until all L1 participants terminate or L1 deadline
    ↓
aggregate and evaluate
    ├── ENOUGH → terminal cleanup
    └── NEED_MORE → target matching peers for L2
    ↓
L2 complete or global timeout
    ↓
freeze final result
```

时间约束：

- 默认逻辑任务预算 10 秒。
- 硬上限 12 秒。
- L1 截止时间由全局预算的一部分确定，但不得超过 6 秒。
- 终态后所有迟到消息被丢弃。

单设备失败隔离：

- 更新对应 `PeerTaskState`。
- 不关闭其他设备的 DSK 或 TLS。
- 只有本机和全部远端都没有有效证据时才返回 `E_ALL_PEERS_FAILED`。

- [ ] **Step 7：运行测试、构建并提交**

```powershell
git add `
  entry/src/main/ets/communication/EvidenceBudgetAllocator.ets `
  entry/src/main/ets/communication/EvidenceAggregator.ets `
  entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets `
  entry/src/main/ets/common/AppError.ets `
  entry/src/test/EvidenceBudgetAllocator.test.ets `
  entry/src/test/EvidenceAggregator.test.ets `
  entry/src/test/MultiDeviceTaskCoordinator.test.ets `
  entry/src/test/List.test.ets

git commit -m "feat: coordinate and aggregate multi-device evidence"
```

**完成门：** 三设备假环境中，互补证据、单远端失败、去重、L2 定向、取消和超时全部通过。

---

# Task 6：运行时装配、状态模型与 UI

**目标：** 将新组件接入现有应用，保留旧查询入口和已有测试，并在界面上展示两台远端的独立状态。

**Files:**

- Modify: `entry/src/main/ets/runtime/AppRuntime.ets`
- Modify: `entry/src/main/ets/application/QueryCoordinator.ets`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `entry/src/main/ets/model/AppModels.ets`
- Modify: `entry/src/main/ets/state/AppStateStore.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/test/AppRuntime.test.ets`
- Modify: `entry/src/test/QueryCoordinator.test.ets`
- Modify: `entry/src/ohosTest/ets/test/IndexPage.test.ets`

**状态接口：**

```typescript
export interface PeerStatusSnapshot {
  deviceIdMasked: string;
  deviceName: string;
  controlState: ControlChannelState;
  dataState: DataChannelState;
  taskState: PeerTaskStatus | '';
  allocatedBytes: number;
  evidenceCount: number;
  failureCode: string;
}

export interface AppSnapshot {
  peerStatuses: PeerStatusSnapshot[];
  activePeerCount: number;
  evidenceSourceDeviceIds: string[];
  evidenceConflictCount: number;
  // 保留现有字段
}
```

- [ ] **Step 1：写失败测试**

覆盖：

- `AppRuntime` 只创建一个 DSK Hub。
- `AppRuntime` 只创建一个 TLS Server 和一个连接池。
- 连续接受 B、C 的协同请求不会互相替换。
- `destroy()` 按协调器、响应器、连接池、DSK Hub、TLS Server、知识服务顺序执行。
- AppSnapshot 能同时显示 B 和 C。
- 更新 B 状态不会改变 C。
- UI 不显示完整设备 ID、令牌、证书或证据正文。
- 旧 `QueryCoordinator.submit()` 测试继续通过。

- [ ] **Step 2：装配生产组件**

`AppRuntime` 默认创建：

```text
HarmonyTrustedDeviceProvider
TrustedDeviceResolver
DeviceDirectory
DskControlHub
NetworkTlsChannel / TLS Server
PeerConnectionPool
PeerTaskResponder
EvidenceAggregator
MultiDeviceTaskCoordinator
```

测试可注入所有假实现。

`EntryAbility.onCollaborate()`：

```typescript
onCollaborate(wantParam: Record<string, Object>): void {
  this.runtime.acceptCollaboration(wantParam);
}
```

不得在每次 `onCollaborate` 时替换整个 Runtime。

- [ ] **Step 3：保持旧入口兼容**

- `QueryCoordinator.submit()` 保持签名。
- 新的语义任务内部转发给 `MultiDeviceTaskCoordinator.submit()`。
- 旧单设备模式在无 READY 远端时仍能执行。
- 旧 `SessionManager`、分页和取消测试不得删除。

- [ ] **Step 4：实现最小状态界面**

每个远端一行，显示：

```text
设备名称 / 脱敏 ID
DSK：DISCONNECTED | CONNECTING | READY | FAILED
TLS：DISCONNECTED | CONNECTING | BINDING | READY | FAILED
任务：PENDING | ACKED | RECEIVING | COMPLETE | FAILED | CANCELLED
证据数
失败码
```

结果区显示：

- 最终充分性：`ENOUGH` / `NEED_MORE` / 错误。
- 证据来源设备数。
- 去重后证据数。
- 冲突数。
- 总耗时。
- 是否进入 L2。

- [ ] **Step 5：运行完整测试和构建**

预期：

- 旧测试全部通过。
- 新的两远端 UI 状态测试通过。
- HAP 构建成功。

- [ ] **Step 6：提交**

```powershell
git add `
  entry/src/main/ets/runtime/AppRuntime.ets `
  entry/src/main/ets/application/QueryCoordinator.ets `
  entry/src/main/ets/entryability/EntryAbility.ets `
  entry/src/main/ets/model/AppModels.ets `
  entry/src/main/ets/state/AppStateStore.ets `
  entry/src/main/ets/pages/Index.ets `
  entry/src/test/AppRuntime.test.ets `
  entry/src/test/QueryCoordinator.test.ets `
  entry/src/ohosTest/ets/test/IndexPage.test.ets

git commit -m "feat: wire three-device runtime and status UI"
```

**完成门：** UI 同时展示 B/C 独立状态，旧单设备查询仍可运行。

---

# Task 7：确定性三设备假环境与故障矩阵

**目标：** 在不依赖真机的环境中证明 DSK 只传控制消息、TLS 承载业务消息，并验证单设备故障隔离与状态清理。

**Files:**

- Create: `entry/src/test/support/FakeDskControlHub.ets`
- Create: `entry/src/test/support/FakeTlsNetwork.ets`
- Create: `entry/src/test/support/MultiDeviceFixtures.ets`
- Create: `entry/src/test/MultiDeviceEndToEnd.test.ets`
- Modify: `entry/src/test/List.test.ets`
- Modify: `entry/src/ohosTest/ets/test/CollaborationAbility.test.ets`

**Fake 网络能力：**

对 B、C 分别支持：

- 延迟。
- 重复消息。
- 消息乱序。
- 连接失败。
- 中途断开。
- 指纹错误。
- 迟到消息。
- 空结果。
- 单设备永久失败。

MVP 不模拟 TCP 内部丢包重传；应用层只观察完整 TLS 帧。

- [ ] **Step 1：实现三设备夹具**

夹具必须暴露：

```typescript
connectThreeDevices(): Promise<void>;
runTask(task: TaskRequest): Promise<TaskSufficiencyResult>;
disconnect(deviceId: string): void;
duplicateNextFrame(deviceId: string): void;
delayNextFrame(deviceId: string, delayMs: number): void;
dskPayloadTypes(): string[];
tlsPayloadTypes(): string[];
pendingResourceCount(): number;
```

- [ ] **Step 2：添加完整 MVP 测试矩阵**

至少包括：

1. A 同时连接 B/C。
2. B/C 互补证据合并为 `ENOUGH`。
3. B/C 相同证据只计算一次。
4. 相同 ID、不同内容进入冲突区。
5. C 断开不清除 B。
6. B 返回空结果，C 仍可完成。
7. 用户取消后 B/C 停止，迟到帧被忽略。
8. DSK 中不存在 `TASK` 或 `EVIDENCE_BATCH`。
9. TLS 中存在 `TASK` 和 `EVIDENCE_BATCH`。
10. 连续运行 10 个任务后无残留资源。

关键断言：

```typescript
it('keeps evidence off the DSK control channel', 0, async () => {
  const fixture = new MultiDeviceFixture();
  await fixture.connectThreeDevices();
  await fixture.runComplementaryTask();

  expect(fixture.dskPayloadTypes().indexOf('EVIDENCE_BATCH') < 0).assertTrue();
  expect(fixture.tlsPayloadTypes().indexOf('EVIDENCE_BATCH') >= 0).assertTrue();
});

it('does not leak state after ten tasks', 0, async () => {
  const fixture = new MultiDeviceFixture();
  await fixture.connectThreeDevices();

  for (let index = 0; index < 10; index += 1) {
    await fixture.runTask(makeTask('task-' + index));
  }

  expect(fixture.pendingResourceCount()).assertEqual(0);
});
```

- [ ] **Step 3：运行完整测试与构建**

```powershell
& $devecoNode $hvigorScript --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  test

if ($LASTEXITCODE -ne 0) {
  throw 'Full multi-device tests failed.'
}

& $devecoNode $hvigorScript --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  assembleHap

if ($LASTEXITCODE -ne 0) {
  throw 'HAP build failed.'
}
```

- [ ] **Step 4：提交**

```powershell
git add `
  entry/src/test/support/FakeDskControlHub.ets `
  entry/src/test/support/FakeTlsNetwork.ets `
  entry/src/test/support/MultiDeviceFixtures.ets `
  entry/src/test/MultiDeviceEndToEnd.test.ets `
  entry/src/test/List.test.ets `
  entry/src/ohosTest/ets/test/CollaborationAbility.test.ets

git commit -m "test: cover three-device dual-channel MVP"
```

**完成门：** 10 次连续任务后，计时器、任务缓存、消息缓存和未完成发送数均为 0。

---

# Task 8：三真机部署与验收记录

**目标：** 将同一个已签名 HAP 部署到三台真机，完成可复现的双通道演示与故障验收。

**Files:**

- Modify: `scripts/deploy/Deploy-SemaLink.ps1`
- Modify: `scripts/deploy/README.md`
- Create: `docs/testing/multi-device-dual-channel-acceptance.md`

- [ ] **Step 1：扩展三设备部署脚本**

```powershell
param(
  [string]$DeviceA = '5KLBB25B07200367',
  [string]$DeviceB = '5KLBB25B07200723',
  [Parameter(Mandatory = $true)]
  [string]$DeviceC,
  [switch]$StartApps
)

$deploymentTargets = @(
  @{ Id = $DeviceA; Label = 'Device A' },
  @{ Id = $DeviceB; Label = 'Device B' },
  @{ Id = $DeviceC; Label = 'Device C' }
)
```

脚本必须：

1. 检查三台设备均在 `hdc list targets`。
2. 检查演示证书和私钥存在。
3. 只构建一次 HAP。
4. 计算 HAP SHA-256。
5. 将完全相同的 HAP 安装到三台设备。
6. 安装后验证 `bundleName`、`versionName`、`versionCode` 和 `EntryAbility`。
7. 可选地冷启动三台应用。
8. 任一设备失败时停止并指出设备标签。

- [ ] **Step 2：创建验收文档模板**

文档必须记录：

- 日期和操作者。
- Git commit。
- HarmonyOS/API 版本。
- 三台设备型号和脱敏 ID。
- HAP 路径和 SHA-256。
- 网络名称。
- 证书指纹前 12 位。
- 每个场景的开始和结束时间。
- B/C 的 DSK、TLS、任务状态。
- 证据来源、去重数和冲突数。
- 重试数；MVP 预期为 0。
- 失败码。
- 关联日志文件。
- 最终 PASS/FAIL。

- [ ] **Step 3：执行七个真机场景**

1. **双远端连接**  
   A 同时与 B/C 建立 DSK 和 TLS，二者均达到 READY。

2. **互补语料**  
   B 存工作资料，C 存生活资料；问题需要两类信息，合并后为 `ENOUGH`。

3. **重复语料**  
   B/C 包含相同证据，最终只计一次但来源包含 B/C。

4. **C 网络中断**  
   查询期间断开 C；B 的 DSK、TLS 和任务不被清除。

5. **空结果隔离**  
   B 返回空证据，C 返回有效证据，任务仍能正常结束。

6. **取消和迟到帧**  
   A 取消任务，B/C 停止；随后到达的旧帧不改变 UI 和最终结果。

7. **连续十次任务**  
   每次均正常结束，应用无崩溃、状态串线或残留活跃任务。

- [ ] **Step 4：验收阈值**

- B 和 C 均在 8 秒内达到 READY。
- 第一份有效证据在 3 秒内到达。
- 默认逻辑任务在 12 秒内结束。
- DSK 日志不包含证据正文。
- C 失败不清除 B 的 DSK、TLS 或任务状态。
- 相同内容证据只计一次。
- 取消后最终结果不再变化。
- 十次连续任务后 `activePeerTaskCount === 0`。
- Hvigor `test` 与 `assembleHap` 均退出 0。

- [ ] **Step 5：部署命令**

```powershell
.\scripts\deploy\New-DemoTlsMaterial.ps1

$hdc = 'D:\Program Files\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$knownDeviceIds = @(
  '5KLBB25B07200367',
  '5KLBB25B07200723'
)

$deviceC = @(& $hdc list targets) |
  ForEach-Object { ([string]$_).Trim() } |
  Where-Object {
    $_.Length -gt 0 -and $_ -notin $knownDeviceIds
  } |
  Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($deviceC)) {
  throw 'A third HDC target is required.'
}

.\scripts\deploy\Deploy-SemaLink.ps1 `
  -DeviceC $deviceC `
  -StartApps
```

- [ ] **Step 6：提交部署和验收记录**

```powershell
git add `
  scripts/deploy/Deploy-SemaLink.ps1 `
  scripts/deploy/README.md `
  docs/testing/multi-device-dual-channel-acceptance.md

git commit -m "test: record three-device dual-channel acceptance"
```

**完成门：** 七个场景均有真实设备日志和时间记录；没有证据的场景不得标记 PASS。

---

# Task 9：增强型可靠分页传输（MVP 通过后执行）

**目标：** 当单个批次不足以承载证据或需要断线级交付确认时，再引入应用层分页、ACK 和重试，不阻塞首轮三设备演示。

**进入条件：**

- Task 1～8 全部完成。
- 三真机七场景验收通过。
- 已证明真实证据经常超过单帧预算，或确实需要应用层交付确认。

**Files:**

- Modify: `entry/src/main/ets/protocol/MultiDeviceProtocolModels.ets`
- Modify: `entry/src/main/ets/protocol/MultiDeviceProtocolCodec.ets`
- Create: `entry/src/main/ets/communication/ReliablePageSender.ets`
- Create: `entry/src/main/ets/communication/EvidencePageAssembler.ets`
- Create: `entry/src/test/ReliablePageSender.test.ets`
- Create: `entry/src/test/EvidencePageAssembler.test.ets`
- Modify: `entry/src/test/MultiDeviceEndToEnd.test.ets`

**新增消息：**

```typescript
export type ReliableDataMessageType =
  | 'EVIDENCE_PAGE'
  | 'EVIDENCE_ACK'
  | 'EVIDENCE_COMPLETE';
```

**可靠性参数：**

```text
最大在途页：4
ACK 超时：1500 ms
最大尝试：3
最大页数：64
单页最大帧：64 KiB
```

- [ ] **Step 1：先写分页和重试失败测试**
- [ ] **Step 2：实现 pageDigest 与 ACK 校验**
- [ ] **Step 3：实现窗口 4 和 ACK 驱动补充发送**
- [ ] **Step 4：实现 1500 ms 超时和最多三次尝试**
- [ ] **Step 5：实现重复 ACK 幂等和乱序页面组装**
- [ ] **Step 6：实现 `PARTIAL_TIMEOUT`**
- [ ] **Step 7：在假网络中验证丢 ACK、重复页、乱序和迟到页**
- [ ] **Step 8：重新执行三真机七场景并增加丢 ACK 场景**

该任务不得改变 Task 1～8 已稳定的 DSK 会话、TLS 绑定、聚合和协调器边界。

---

## 7. 完成定义

### 7.1 架构完成

- 设备发现和可信列表来自鸿蒙原生能力。
- 每台远端有独立的 DSK 控制会话。
- 每台远端有独立的 TLS 数据通道。
- DSK 与 TLS 使用一次性令牌和设备身份完成绑定。
- DSK 不传业务证据。
- TLS 不承担设备发现和协同拉起职责。

### 7.2 业务完成

- 本机和至少两台远端同时参与一个逻辑任务。
- L1 并行执行。
- L1 足够时不进入 L2。
- L2 只发往匹配缺失概念且有剩余预算的设备。
- 相同内容证据只计算一次。
- 相同 ID 的不同内容被隔离。
- 单台远端失败不清除其他远端。
- 最终结果冻结后迟到消息不能修改状态。

### 7.3 工程完成

- 旧单设备查询和已有分页、取消、超时测试继续通过。
- 新的三设备 Fake 故障矩阵通过。
- 10 次连续任务后无残留任务、计时器或消息缓存。
- Hvigor `test` 和 `assembleHap` 均退出 0。
- 同一个已签名 HAP 成功部署到三台设备。
- 七个真机场景均有日志、时间和状态证据。

---

## 8. 推荐执行顺序

```text
Task 1 设备目录
    ↓
Task 2 DSK 多会话
    ↓
Task 3 TLS + 绑定
    ↓
双真机 TLS 探针
    ↓
Task 4 MVP 数据协议与响应器
    ↓
Task 5 聚合与协调器
    ↓
Task 6 Runtime 与 UI
    ↓
Task 7 三设备 Fake 故障矩阵
    ↓
Task 8 三真机验收
    ↓
Task 9 可选增强可靠传输
```

不得并行实现 Task 2 和 Task 3 的生产连接逻辑；应先稳定 DSK 多会话，再接 TLS。Task 4 和 Task 5 可以在 Task 3 双真机探针通过后由两名开发者并行，但必须共享同一份 `MultiDeviceProtocolModels.ets` 契约。

---

## 9. 两人分工建议

### 甲：跨设备通信与运行时

负责：

- Task 1 中鸿蒙设备 Provider。
- Task 2 DSK 多会话。
- Task 3 TLS、证书指纹和绑定。
- Task 6 Runtime、EntryAbility 和状态 UI。
- Task 8 部署与真机日志。

### 乙：协议、检索与证据协调

负责：

- Task 1 中设备知识画像和语义路由。
- Task 4 数据协议和 PeerTaskResponder。
- Task 5 预算、聚合和 MultiDeviceTaskCoordinator。
- Task 7 三设备 Fake 与故障矩阵。
- Task 8 测试语料和结果核验。

### 共同接口冻结点

在开始并行开发前，共同确认并提交：

```text
ControlModels.ets
MultiDeviceProtocolModels.ets
AppError.ets
DeviceRuntimeSnapshot
TaskRequest
TaskSufficiencyResult
EvidenceUnit
```

任何一方修改共享接口，必须同时更新对方测试，不允许仅让本分支编译通过。

---

## 10. 计划自检结果

- 未将设备发现、TLS、哈希或随机数作为自研算法。
- 未使用 ArkData 同步全文替代按需跨设备查询。
- MVP 不依赖应用层分页 ACK。
- 每个核心任务都有失败测试、实现、完整验证、提交和完成门。
- DSK 控制面与 TLS 数据面边界明确。
- 单设备故障隔离贯穿目录、会话、连接池和协调器。

## 11. 执行状态

Task 1 和 Task 2 已完成并复用现有实现：鸿蒙原生可信设备发现、设备目录、多会话 `abilityConnectionManager` 控制中心均已存在并通过当前代码审计。本轮执行从 Task 3 开始，不重复创建同职责实现。

执行器每轮只执行一个尚未完成的 Task；当所有 Task 均为 `COMPLETED` 或 `FAILED` 时自动暂停循环，不再创建后续运行。Task 9 只有在 Task 1～8 的 MVP 验收完成后才允许执行。
- 真机验收包含真实日志要求，不能仅凭 UI 判断通过。
- 增强可靠传输与 MVP 解耦，不阻塞竞赛演示闭环。
