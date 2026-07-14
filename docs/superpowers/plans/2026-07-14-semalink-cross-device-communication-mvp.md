# SemaLink 跨设备通信 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在两台同账号可信组网的 HarmonyOS 设备之间建立 `Distributed Service Kit` 协同会话，由手机发送查询并收到对端生成的确定性模拟摘要。

**Architecture:** 单页 UI 只调用 `QueryCoordinator`；`SessionManager` 管理请求状态机、超时和协议派发；`CollaborationTransport` 是唯一接触 `abilityConnectionManager` 的模块。`TrustedDeviceResolver` 使用 `distributedDeviceManager` 查询可用可信设备，只有结果恰好为一台时才自动连接。

**Tech Stack:** HarmonyOS NEXT API 24、ArkTS、ArkUI、`@kit.DistributedServiceKit`、`@kit.AbilityKit`、`@ohos/hypium`、`@ohos/hamock`、Hvigor。

---

## 实施前提与停止条件

- 两台真机使用 API 24、同一华为账号、相同签名和 `bundleName`，并完成可信设备组网。
- `abilityConnectionManager` 需要 `ohos.permission.INTERNET`、`ohos.permission.GET_NETWORK_INFO`、`ohos.permission.SET_NETWORK_INFO`、`ohos.permission.DISTRIBUTED_DATASYNC`。
- 当前 SDK 类型定义确认存在 `UIAbility.onCollaborate()`、`createAbilityConnectionSession()`、`connect()`、`acceptConnect()`、`sendMessage()`、`disconnect()`、`destroyAbilityConnectionSession()` 及 `connect/disconnect/receiveMessage` 事件。
- Task 9 完成后必须先做双真机最小连接探针。如果 `acceptConnect(sessionId, SERVICE_TOKEN)` 在 API 24 真机上被拒绝，停止后续 UI 集成，记录原始错误码，并依据该设备 SDK 对 `token` 的官方说明修正传输适配器。不得绕过协同 API 或切换到 Socket。
- 如果 `distributedDeviceManager.getAvailableDeviceList()` 返回多台设备，MVP 返回 `E_MULTIPLE_DEVICES`，不静默选择第一台。

## 文件结构

| 文件 | 职责 |
|---|---|
| `entry/src/main/ets/common/AppError.ets` | 统一错误码、阶段和可恢复属性 |
| `entry/src/main/ets/common/IdGenerator.ets` | 生成 `messageId`、`requestId`、应用层 `sessionId` |
| `entry/src/main/ets/common/Scheduler.ets` | 封装可注入的计时器 |
| `entry/src/main/ets/common/Logger.ets` | 仅记录隐私安全的消息元数据 |
| `entry/src/main/ets/model/AppModels.ets` | 角色、连接状态、对端设备和 UI 快照 |
| `entry/src/main/ets/protocol/ProtocolModels.ets` | 协议信封、消息类型和 payload |
| `entry/src/main/ets/protocol/ProtocolCodec.ets` | JSON 编解码、字段和大小校验 |
| `entry/src/main/ets/task/MockSummaryService.ets` | 生成确定性模拟摘要 |
| `entry/src/main/ets/communication/Transport.ets` | 传输接口和监听器契约 |
| `entry/src/main/ets/communication/TrustedDeviceResolver.ets` | 将 0/1/多台可信设备解析为错误或唯一对端 |
| `entry/src/main/ets/communication/CollaborationTransport.ets` | 适配 `abilityConnectionManager` 与 `distributedDeviceManager` |
| `entry/src/main/ets/communication/SessionManager.ets` | 会话、请求、ACK/RESULT、超时、幂等和清理 |
| `entry/src/main/ets/state/AppStateStore.ets` | 发布 UI 可观察状态 |
| `entry/src/main/ets/application/QueryCoordinator.ets` | 角色、连接、查询和响应端业务编排 |
| `entry/src/main/ets/runtime/AppRuntime.ets` | 组合根和单例生命周期 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 窗口与 `onCollaborate` 生命周期接入 |
| `entry/src/main/ets/pages/Index.ets` | 单页 MVP UI |

测试文件与源码同名放在 `entry/src/test/`，并由 `entry/src/test/List.test.ets` 显式注册。双真机用例放在 `entry/src/ohosTest/ets/test/CollaborationAbility.test.ets`，人工步骤记录在 `docs/testing/cross-device-mvp-acceptance.md`。

## 验证命令

当前仓库没有项目内 `hvigorw`。使用 DevEco Studio 自带脚本，并显式指定可用的现代 Node runtime：

```powershell
$node = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
```

预期：命令退出码为 0，测试输出无失败用例，构建输出包含 `BUILD SUCCESSFUL`。如果本机 DevEco 安装目录不同，只允许调整 `$node` 与 `$hvigor` 两个路径变量，不修改任务参数。

### Task 1: 配置权限与基础领域类型

**Files:**
- Modify: `entry/src/main/module.json5`
- Create: `entry/src/main/ets/common/AppError.ets`
- Create: `entry/src/main/ets/common/IdGenerator.ets`
- Create: `entry/src/main/ets/common/Scheduler.ets`
- Create: `entry/src/main/ets/model/AppModels.ets`
- Test: `entry/src/test/CommonModels.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入领域类型的失败测试**

```ts
import { describe, expect, it } from '@ohos/hypium';
import { AppError, ErrorStage } from '../main/ets/common/AppError';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';

export default function commonModelsTest(): void {
  describe('CommonModels', () => {
    it('createsStableErrorMetadata', 0, () => {
      const error = new AppError('E_DEVICE_NOT_FOUND', '未发现设备', ErrorStage.SELECTION, true);
      expect(error.code).assertEqual('E_DEVICE_NOT_FOUND');
      expect(error.recoverable).assertTrue();
    });

    it('createsDistinctIds', 0, () => {
      const ids = new SequenceIdGenerator(() => 1000);
      expect(ids.next('request')).assertEqual('request-1000-1');
      expect(ids.next('request')).assertEqual('request-1000-2');
    });
  });
}
```

在 `List.test.ets` 中注册：

```ts
import commonModelsTest from './CommonModels.test';

export default function testsuite(): void {
  commonModelsTest();
}
```

- [ ] **Step 2: 运行测试并确认因模块不存在而失败**

Run: 上述 Hvigor `test` 命令。  
Expected: FAIL，错误包含 `Cannot find module '../main/ets/common/AppError'`。

- [ ] **Step 3: 实现最小领域类型**

```ts
// common/AppError.ets
export enum ErrorStage {
  SELECTION = 'SELECTION',
  CONNECTION = 'CONNECTION',
  PROTOCOL = 'PROTOCOL',
  QUERY = 'QUERY',
  LIFECYCLE = 'LIFECYCLE'
}

export class AppError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly stage: ErrorStage,
    readonly recoverable: boolean,
    readonly systemCode?: number
  ) {
    super(message);
    this.name = 'AppError';
  }
}
```

```ts
// common/IdGenerator.ets
export class SequenceIdGenerator {
  private sequence: number = 0;

  constructor(private readonly now: () => number = () => Date.now()) {}

  next(prefix: string): string {
    this.sequence += 1;
    return `${prefix}-${this.now()}-${this.sequence}`;
  }
}
```

```ts
// common/Scheduler.ets
export interface Scheduler {
  schedule(delayMs: number, callback: () => void): number;
  cancel(timerId: number): void;
}

export class SystemScheduler implements Scheduler {
  schedule(delayMs: number, callback: () => void): number {
    return setTimeout(callback, delayMs);
  }

  cancel(timerId: number): void {
    clearTimeout(timerId);
  }
}
```

```ts
// model/AppModels.ets
import { AppError } from '../common/AppError';

export enum DeviceRole { UNSELECTED = 'UNSELECTED', INITIATOR = 'INITIATOR', RESPONDER = 'RESPONDER' }
export enum ConnectionState {
  IDLE = 'IDLE', SELECTING_DEVICE = 'SELECTING_DEVICE', CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED', WAITING_ACK = 'WAITING_ACK', WAITING_RESULT = 'WAITING_RESULT',
  DISCONNECTING = 'DISCONNECTING', DISCONNECTED = 'DISCONNECTED', ERROR = 'ERROR'
}
export interface PeerDevice { deviceId: string; deviceName: string; deviceType: string; }
export interface AppSnapshot {
  role: DeviceRole;
  connectionState: ConnectionState;
  question: string;
  summary: string;
  requestId: string;
  roundTripMs: number;
  bytesSent: number;
  bytesReceived: number;
  error?: AppError;
}
export const INITIAL_SNAPSHOT: AppSnapshot = {
  role: DeviceRole.UNSELECTED,
  connectionState: ConnectionState.IDLE,
  question: '', summary: '', requestId: '', roundTripMs: 0,
  bytesSent: 0, bytesReceived: 0
};
```

在 `module.json5` 的 `module` 节点加入：

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.GET_NETWORK_INFO" },
  { "name": "ohos.permission.SET_NETWORK_INFO" },
  { "name": "ohos.permission.DISTRIBUTED_DATASYNC" }
]
```

- [ ] **Step 4: 运行测试和构建**

Run: Hvigor `test`，随后运行 `assembleHap`。  
Expected: `CommonModels` 两个用例 PASS，HAP 构建成功。

- [ ] **Step 5: 提交**

```powershell
git add entry/src/main/module.json5 entry/src/main/ets/common entry/src/main/ets/model entry/src/test
git commit -m "feat: add communication domain foundations"
```

### Task 2: 实现协议模型与严格 JSON Codec

**Files:**
- Create: `entry/src/main/ets/protocol/ProtocolModels.ets`
- Create: `entry/src/main/ets/protocol/ProtocolCodec.ets`
- Create: `entry/src/test/ProtocolCodec.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入合法消息与非法消息测试**

```ts
import { describe, expect, it } from '@ohos/hypium';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import { MessageType, ProtocolEnvelope, QueryPayload } from '../main/ets/protocol/ProtocolModels';
import { AppError } from '../main/ets/common/AppError';

export default function protocolCodecTest(): void {
  describe('ProtocolCodec', () => {
    const codec = new ProtocolCodec();

    it('roundTripsQuery', 0, () => {
      const envelope: ProtocolEnvelope = {
        version: '1.0', type: MessageType.QUERY, messageId: 'm1', sessionId: 's1',
        requestId: 'r1', sentAt: 1000, payload: { question: '测试问题' } as QueryPayload
      };
      const decoded = codec.decode(codec.encode(envelope));
      expect(decoded.requestId).assertEqual('r1');
      expect((decoded.payload as QueryPayload).question).assertEqual('测试问题');
    });

    it('rejectsMalformedJson', 0, () => {
      let code = '';
      try { codec.decode('{bad'); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsOversizedQuestion', 0, () => {
      const payload: QueryPayload = { question: 'x'.repeat(1001) };
      let code = '';
      try { codec.createQuery('m1', 's1', 'r1', 1000, payload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });
  });
}
```

- [ ] **Step 2: 运行测试并确认失败**

Expected: FAIL，缺少 `ProtocolCodec` 和 `ProtocolModels`。

- [ ] **Step 3: 实现协议类型与 Codec**

```ts
// protocol/ProtocolModels.ets
export const PROTOCOL_VERSION: string = '1.0';
export const MAX_MESSAGE_BYTES: number = 16 * 1024;
export const MAX_QUESTION_CHARS: number = 1000;
export const MAX_SUMMARY_CHARS: number = 2000;

export enum MessageType { QUERY = 'QUERY', QUERY_ACK = 'QUERY_ACK', RESULT = 'RESULT', ERROR = 'ERROR' }
export interface QueryPayload { question: string; }
export interface QueryAckPayload { acceptedAt: number; }
export interface ResultPayload { summary: string; sourceDeviceAlias: string; processingMs: number; }
export interface ErrorPayload { code: string; message: string; }
export type ProtocolPayload = QueryPayload | QueryAckPayload | ResultPayload | ErrorPayload;
export interface ProtocolEnvelope {
  version: string; type: MessageType; messageId: string; sessionId: string;
  requestId: string; sentAt: number; payload: ProtocolPayload;
}
```

`ProtocolCodec.ets` 必须实现以下公开方法，内部用 `Record<string, Object>` 做字段检查，禁止直接信任 `JSON.parse()` 的结果：

```ts
export class ProtocolCodec {
  encode(envelope: ProtocolEnvelope): string;
  decode(text: string): ProtocolEnvelope;
  createQuery(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: QueryPayload): ProtocolEnvelope;
  createAck(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: QueryAckPayload): ProtocolEnvelope;
  createResult(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: ResultPayload): ProtocolEnvelope;
  createError(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: ErrorPayload): ProtocolEnvelope;
}
```

校验顺序固定为：UTF-8 字节数不超过 16 KiB、根对象类型、`version === '1.0'`、枚举类型、5 个公共 ID/时间字段、对应 payload。所有协议异常统一抛出 `new AppError('E_PROTOCOL_INVALID', ..., ErrorStage.PROTOCOL, false)`；问题为空或超过 1000 字符抛出 `E_QUERY_INVALID`。

- [ ] **Step 4: 补齐边界测试并运行**

增加未知版本、未知消息类型、字段缺失、空问题、2000 字符摘要成功、2001 字符摘要失败、编码后超过 16 KiB 的测试。  
Expected: 所有 `ProtocolCodec` 用例 PASS。

- [ ] **Step 5: 提交**

```powershell
git add entry/src/main/ets/protocol entry/src/test
git commit -m "feat: add versioned query protocol"
```

### Task 3: 实现确定性 MockSummaryService

**Files:**
- Create: `entry/src/main/ets/task/MockSummaryService.ets`
- Create: `entry/src/test/MockSummaryService.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入确定性与截断测试**

```ts
import { describe, expect, it } from '@ohos/hypium';
import { MockSummaryService } from '../main/ets/task/MockSummaryService';

export default function mockSummaryServiceTest(): void {
  describe('MockSummaryService', () => {
    const service = new MockSummaryService();
    it('returnsDeterministicSummary', 0, () => {
      expect(service.generate('  鸿蒙通信如何工作？  ')).assertEqual(
        service.generate('鸿蒙通信如何工作？'));
    });
    it('includesQuestionAndDisclosure', 0, () => {
      const result = service.generate('项目状态');
      expect(result).assertContain('项目状态');
      expect(result).assertContain('未执行真实文档检索');
      expect(result).assertContain('未传输完整文件');
    });
  });
}
```

- [ ] **Step 2: 运行并确认缺少实现**

Expected: FAIL，缺少 `MockSummaryService`。

- [ ] **Step 3: 实现纯函数服务**

```ts
import { AppError, ErrorStage } from '../common/AppError';
import { MAX_QUESTION_CHARS, MAX_SUMMARY_CHARS } from '../protocol/ProtocolModels';

export class MockSummaryService {
  generate(question: string): string {
    const normalized = question.trim();
    if (normalized.length === 0 || normalized.length > MAX_QUESTION_CHARS) {
      throw new AppError('E_QUERY_INVALID', '问题长度无效', ErrorStage.QUERY, true);
    }
    const excerpt = normalized.substring(0, 120);
    const summary = `设备 B 已收到关于“${excerpt}”的查询。\n` +
      '这是由远端设备生成的模拟摘要，未执行真实文档检索，也未传输完整文件。';
    return summary.substring(0, MAX_SUMMARY_CHARS);
  }
}
```

- [ ] **Step 4: 运行测试**

Expected: 所有 `MockSummaryService` 用例 PASS。

- [ ] **Step 5: 提交**

```powershell
git add entry/src/main/ets/task entry/src/test
git commit -m "feat: add deterministic mock summary service"
```

### Task 4: 实现唯一可信设备解析

**Files:**
- Create: `entry/src/main/ets/communication/TrustedDeviceResolver.ets`
- Create: `entry/src/test/TrustedDeviceResolver.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入 0/1/多设备测试**

```ts
import { describe, expect, it } from '@ohos/hypium';
import { AvailableDeviceProvider, TrustedDeviceResolver } from '../main/ets/communication/TrustedDeviceResolver';
import { AppError } from '../main/ets/common/AppError';
import { PeerDevice } from '../main/ets/model/AppModels';

class FakeProvider implements AvailableDeviceProvider {
  released: boolean = false;
  constructor(private readonly devices: Array<PeerDevice>) {}
  list(): Promise<Array<PeerDevice>> { return Promise.resolve(this.devices); }
  release(): void { this.released = true; }
}

export default function trustedDeviceResolverTest(): void {
  describe('TrustedDeviceResolver', () => {
    it('returnsOnlyDevice', 0, async () => {
      const provider = new FakeProvider([{ deviceId: 'd1', deviceName: 'MatePad', deviceType: 'tablet' }]);
      const peer = await new TrustedDeviceResolver(provider).resolveUnique();
      expect(peer.deviceId).assertEqual('d1');
      expect(provider.released).assertTrue();
    });
    it('rejectsNoDevice', 0, async () => {
      let code = '';
      try { await new TrustedDeviceResolver(new FakeProvider([])).resolveUnique(); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_DEVICE_NOT_FOUND');
    });
    it('rejectsMultipleDevices', 0, async () => {
      const devices: Array<PeerDevice> = [
        { deviceId: 'd1', deviceName: 'A', deviceType: 'phone' },
        { deviceId: 'd2', deviceName: 'B', deviceType: 'tablet' }
      ];
      let code = '';
      try { await new TrustedDeviceResolver(new FakeProvider(devices)).resolveUnique(); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_MULTIPLE_DEVICES');
    });
  });
}
```

- [ ] **Step 2: 运行并确认失败**

Expected: FAIL，缺少 `TrustedDeviceResolver`。

- [ ] **Step 3: 实现 Resolver 与 production provider**

```ts
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { AppError, ErrorStage } from '../common/AppError';
import { PeerDevice } from '../model/AppModels';

export interface AvailableDeviceProvider {
  list(): Promise<Array<PeerDevice>>;
  release(): void;
}

export class DistributedDeviceProvider implements AvailableDeviceProvider {
  private readonly manager: distributedDeviceManager.DeviceManager;
  constructor(bundleName: string) {
    this.manager = distributedDeviceManager.createDeviceManager(bundleName);
  }
  async list(): Promise<Array<PeerDevice>> {
    const devices = await this.manager.getAvailableDeviceList();
    return devices.map((device) => ({
      deviceId: device.deviceId, deviceName: device.deviceName, deviceType: device.deviceType
    }));
  }
  release(): void { distributedDeviceManager.releaseDeviceManager(this.manager); }
}

export class TrustedDeviceResolver {
  constructor(private readonly provider: AvailableDeviceProvider) {}
  async resolveUnique(): Promise<PeerDevice> {
    try {
      const devices = await this.provider.list();
      if (devices.length === 0) {
        throw new AppError('E_DEVICE_NOT_FOUND', '未发现可用可信设备', ErrorStage.SELECTION, true);
      }
      if (devices.length > 1) {
        throw new AppError('E_MULTIPLE_DEVICES', '发现多个可信设备，请仅保留目标设备在线', ErrorStage.SELECTION, true);
      }
      return devices[0];
    } finally {
      this.provider.release();
    }
  }
}
```

- [ ] **Step 4: 运行测试和构建**

Expected: 0/1/多设备用例全部 PASS，`assembleHap` 编译通过。

- [ ] **Step 5: 提交**

```powershell
git add entry/src/main/ets/communication/TrustedDeviceResolver.ets entry/src/test
git commit -m "feat: resolve the only trusted peer"
```

### Task 5: 定义 Transport 契约与 FakeTransport

**Files:**
- Create: `entry/src/main/ets/communication/Transport.ets`
- Create: `entry/src/test/support/FakeTransport.ets`
- Create: `entry/src/test/TransportContract.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入事件与幂等断开契约测试**

```ts
import { describe, expect, it } from '@ohos/hypium';
import { FakeTransport } from './support/FakeTransport';

export default function transportContractTest(): void {
  describe('TransportContract', () => {
    it('deliversMessagesToListener', 0, async () => {
      const transport = new FakeTransport();
      let received = '';
      transport.setListener({
        onConnected: () => {}, onMessage: (text) => received = text,
        onDisconnected: () => {}, onError: () => {}
      });
      transport.emitMessage('hello');
      expect(received).assertEqual('hello');
    });
    it('disconnectIsIdempotent', 0, async () => {
      const transport = new FakeTransport();
      await transport.disconnect();
      await transport.disconnect();
      expect(transport.disconnectCalls).assertEqual(1);
    });
  });
}
```

- [ ] **Step 2: 运行并确认失败**

Expected: FAIL，缺少 `Transport` 和 `FakeTransport`。

- [ ] **Step 3: 定义窄接口**

```ts
import { AppError } from '../common/AppError';
import { PeerDevice } from '../model/AppModels';

export interface TransportListener {
  onConnected(): void;
  onMessage(text: string): void;
  onDisconnected(reason?: number): void;
  onError(error: AppError): void;
}

export interface Transport {
  setListener(listener: TransportListener): void;
  connect(peer: PeerDevice): Promise<void>;
  accept(wantParam: Record<string, Object>): boolean;
  send(text: string): Promise<void>;
  disconnect(): Promise<void>;
  destroy(): void;
  isConnected(): boolean;
}
```

`FakeTransport` 完整实现该接口，保存 `sentMessages`、`connectCalls`、`disconnectCalls`，并提供 `emitConnected()`、`emitMessage()`、`emitDisconnected()` 和 `emitError()`。第二次 `disconnect()` 不增加计数。

- [ ] **Step 4: 运行测试**

Expected: `TransportContract` 全部 PASS。

- [ ] **Step 5: 提交**

```powershell
git add entry/src/main/ets/communication/Transport.ets entry/src/test
git commit -m "feat: define collaboration transport contract"
```

### Task 6: 实现 CollaborationTransport 与真机连接探针

**Files:**
- Create: `entry/src/main/ets/communication/CollaborationTransport.ets`
- Create: `entry/src/main/ets/common/Logger.ets`
- Create: `entry/src/test/CollaborationTransport.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入系统错误映射与 destroy 幂等测试**

将 `abilityConnectionManager` 调用包在内部 `CollaborationApi` 接口后注入 fake。测试以下行为：

```ts
it('mapsRejectedConnection', 0, async () => {
  api.connectResult = { isConnected: false, errorCode: 2, reason: 'wifi off' };
  let code = '';
  try { await transport.connect(PEER); } catch (error) { code = (error as AppError).code; }
  expect(code).assertEqual('E_CONNECT_REJECTED');
});

it('removesListenersBeforeDestroy', 0, () => {
  transport.destroy();
  transport.destroy();
  expect(api.offCalls).assertEqual(3);
  expect(api.destroyCalls).assertEqual(1);
});
```

- [ ] **Step 2: 运行并确认失败**

Expected: FAIL，缺少 `CollaborationTransport`。

- [ ] **Step 3: 实现发起端连接**

常量固定为：

```ts
const SERVICE_NAME: string = 'semalink.communication.v1';
const SERVICE_TOKEN: string = 'semalink-mvp-v1';
const MODULE_NAME: string = 'entry';
const ABILITY_NAME: string = 'EntryAbility';
```

`Logger.ets` 只接受预先筛选后的元数据，不提供记录任意 payload 的入口：

```ts
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x534C;
const TAG: string = 'SemaLink';
export type LogMetadata = Record<string, string | number | boolean>;

export class Logger {
  info(event: string, metadata: LogMetadata = {}): void {
    hilog.info(DOMAIN, TAG, '%{public}s', `${event} ${JSON.stringify(metadata)}`);
  }
  error(event: string, metadata: LogMetadata = {}): void {
    hilog.error(DOMAIN, TAG, '%{public}s', `${event} ${JSON.stringify(metadata)}`);
  }
}
```

`CollaborationTransport` 构造函数接收 `UIAbilityContext`、`bundleName`、`Logger`，测试时还可注入以下内部 adapter；production adapter 逐项委托给 `abilityConnectionManager`：

```ts
interface CollaborationApi {
  create(serviceName: string, context: common.UIAbilityContext, peer: abilityConnectionManager.PeerInfo,
    options: abilityConnectionManager.ConnectOptions): number;
  onConnect(sessionId: number, callback: (info: abilityConnectionManager.EventCallbackInfo) => void): void;
  onDisconnect(sessionId: number, callback: (info: abilityConnectionManager.EventCallbackInfo) => void): void;
  onMessage(sessionId: number, callback: (info: abilityConnectionManager.EventCallbackInfo) => void): void;
  offAll(sessionId: number): void;
  connect(sessionId: number): Promise<abilityConnectionManager.ConnectResult>;
  accept(sessionId: number, token: string): Promise<void>;
  send(sessionId: number, text: string): Promise<void>;
  disconnect(sessionId: number): void;
  destroy(sessionId: number): void;
}
```

`connect(peer)` 必须按顺序执行：创建 `PeerInfo`；调用 `createAbilityConnectionSession()`；注册 `connect/disconnect/receiveMessage` 三个监听；调用 `connect()`；检查 `ConnectResult.isConnected`；失败时注销监听并销毁 session。`ConnectOptions` 使用：

```ts
{
  needSendData: false,
  startOptions: abilityConnectionManager.StartOptionParams.START_IN_FOREGROUND,
  parameters: { 'semalink.role': 'RESPONDER' }
}
```

`send()` 只调用 `sendMessage(sessionId, text)`，不使用 `sendData()`。`disconnect()` 调用 `disconnect()` 后统一进入幂等 `destroy()`。

- [ ] **Step 4: 实现响应端 accept**

`accept(wantParam)` 从以下键读取对象：

```ts
const peerInfo = wantParam[abilityConnectionManager.CollaborationKeys.PEER_INFO]
  as abilityConnectionManager.PeerInfo;
const options = wantParam[abilityConnectionManager.CollaborationKeys.CONNECT_OPTIONS]
  as abilityConnectionManager.ConnectOptions;
```

字段无效时返回 `false`。有效时使用相同 `SERVICE_NAME` 创建 session、注册三个监听，并异步调用：

```ts
abilityConnectionManager.acceptConnect(sessionId, SERVICE_TOKEN)
  .catch((error: BusinessError) => listener.onError(mapBusinessError(error)));
return true;
```

- [ ] **Step 5: 运行单元测试和 HAP 构建**

Expected: fake API 用例 PASS；`@kit.DistributedServiceKit`、`BusinessError`、`onCollaborate` 的类型检查通过；HAP 构建成功。

- [ ] **Step 6: 提交**

```powershell
git add entry/src/main/ets/communication/CollaborationTransport.ets entry/src/main/ets/common/Logger.ets entry/src/test
git commit -m "feat: connect devices through Distributed Service Kit"
```

### Task 7: 用 FakeTransport 驱动 SessionManager 状态机

**Files:**
- Create: `entry/src/main/ets/communication/SessionManager.ets`
- Create: `entry/src/test/support/FakeScheduler.ets`
- Create: `entry/src/test/SessionManager.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入主链路测试**

```ts
it('completesQueryAfterAckAndResult', 0, async () => {
  await manager.connect(PEER);
  transport.emitConnected();
  const pending = manager.execute('项目状态');
  const query = codec.decode(transport.sentMessages[0]);
  transport.emitMessage(codec.encode(codec.createAck('m2', query.sessionId,
    query.requestId, 1010, { acceptedAt: 1010 })));
  transport.emitMessage(codec.encode(codec.createResult('m3', query.sessionId,
    query.requestId, 1020, { summary: '摘要', sourceDeviceAlias: 'B', processingMs: 5 })));
  const result = await pending;
  expect(result.summary).assertEqual('摘要');
  expect(manager.state).assertEqual(ConnectionState.CONNECTED);
});
```

- [ ] **Step 2: 写入异常测试并运行失败**

覆盖：连接期间禁止查询、同一时刻第二个请求返回 `E_BUSY`、3 秒 ACK 超时、10 秒 RESULT 超时、迟到结果忽略、未知 `requestId` 忽略、断线清理 pending、第二次 destroy 不重复释放。  
Expected: FAIL，缺少 `SessionManager`。

- [ ] **Step 3: 实现 SessionManager 公共 API**

```ts
export interface SessionObserver {
  onStateChanged(state: ConnectionState): void;
  onIncomingQuery(envelope: ProtocolEnvelope): void;
  onMetrics(bytesSent: number, bytesReceived: number): void;
  onError(error: AppError): void;
}

export class SessionManager implements TransportListener {
  readonly state: ConnectionState;
  setObserver(observer: SessionObserver): void;
  connect(peer: PeerDevice): Promise<void>;
  accept(wantParam: Record<string, Object>): boolean;
  execute(question: string): Promise<ResultPayload>;
  sendAck(request: ProtocolEnvelope): Promise<void>;
  sendResult(request: ProtocolEnvelope, result: ResultPayload): Promise<void>;
  sendRemoteError(request: ProtocolEnvelope, error: AppError): Promise<void>;
  disconnect(): Promise<void>;
  destroy(): void;
}
```

实现中保存 `pendingRequestId`、`appSessionId`、ACK timer、RESULT timer、已超时 `requestId` 集合、最后一个完成结果缓存和累计字节。状态转换只能经私有 `transition(next)`；`execute()` 在 `CONNECTED` 之外抛 `E_SESSION_NOT_READY`。

- [ ] **Step 4: 实现接收派发**

`onMessage(text)` 固定分派：

- `QUERY`：响应端首个请求绑定 `sessionId`；忙碌时回 `E_BUSY`；已完成 ID 重发缓存；否则通知 `onIncomingQuery`。
- `QUERY_ACK`：必须匹配 pending；取消 ACK timer，进入 `WAITING_RESULT`，启动 10 秒 timer。
- `RESULT`：必须匹配 pending 且未超时；取消 timer，resolve Promise，缓存结果，进入 `CONNECTED`。
- `ERROR`：匹配 pending 时 reject Promise 并进入 `CONNECTED`。

- [ ] **Step 5: 运行 SessionManager 测试**

Expected: 主链路和全部异常用例 PASS，无测试等待真实 3/10 秒；`FakeScheduler.advanceBy()` 触发计时器。

- [ ] **Step 6: 提交**

```powershell
git add entry/src/main/ets/communication/SessionManager.ets entry/src/test
git commit -m "feat: add serial request session state machine"
```

### Task 8: 实现 AppStateStore 与 QueryCoordinator

**Files:**
- Create: `entry/src/main/ets/state/AppStateStore.ets`
- Create: `entry/src/main/ets/application/QueryCoordinator.ets`
- Create: `entry/src/test/QueryCoordinator.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: 写入发起端与响应端编排测试**

```ts
it('connectsOnlyResolvedPeer', 0, async () => {
  await coordinator.selectInitiator();
  await coordinator.connect();
  expect(session.connectedPeerId).assertEqual('d1');
});

it('handlesIncomingQueryOnResponder', 0, async () => {
  coordinator.acceptCollaboration(WANT_PARAM);
  await coordinator.onIncomingQuery(QUERY_ENVELOPE);
  expect(session.sentAckCount).assertEqual(1);
  expect(session.sentResult.summary).assertContain('未执行真实文档检索');
});
```

- [ ] **Step 2: 运行并确认失败**

Expected: FAIL，缺少 store 和 coordinator。

- [ ] **Step 3: 实现可订阅 Store**

```ts
export type StateListener = (snapshot: AppSnapshot) => void;

export class AppStateStore {
  private listeners: Array<StateListener> = [];
  private current: AppSnapshot = INITIAL_SNAPSHOT;
  snapshot(): AppSnapshot { return this.current; }
  subscribe(listener: StateListener): () => void {
    this.listeners.push(listener);
    listener(this.current);
    return () => this.listeners = this.listeners.filter((item) => item !== listener);
  }
  update(next: Partial<AppSnapshot>): void {
    this.current = { ...this.current, ...next };
    this.listeners.forEach((listener) => listener(this.current));
  }
}
```

- [ ] **Step 4: 实现 QueryCoordinator**

公开 API 固定为：

```ts
selectInitiator(): void;
connect(): Promise<void>;
submit(question: string): Promise<void>;
acceptCollaboration(wantParam: Record<string, Object>): boolean;
disconnect(): Promise<void>;
destroy(): void;
```

`connect()` 每次创建新的 `DistributedDeviceProvider`，用 `TrustedDeviceResolver.resolveUnique()` 得到唯一设备，再调用 `SessionManager.connect()`。`submit()` 将结果、`requestId`、端到端耗时和错误写入 store。`acceptCollaboration()` 先设置 `RESPONDER`，再调用 `SessionManager.accept()`。`onIncomingQuery()` 必须先 `sendAck()`，调用 `MockSummaryService.generate()`，再 `sendResult()`；异常则 `sendRemoteError()`。

构造函数接收 `resolverFactory: () => TrustedDeviceResolver`，production factory 每次创建新的 `DistributedDeviceProvider`；测试 factory 返回带 `FakeProvider` 的 resolver。这样 `connect()` 重试不会复用已经 release 的 `DeviceManager`。

- [ ] **Step 5: 运行测试**

Expected: initiator、responder、0/多设备错误、单请求限制和断线状态测试全部 PASS。

- [ ] **Step 6: 提交**

```powershell
git add entry/src/main/ets/state entry/src/main/ets/application entry/src/test
git commit -m "feat: orchestrate cross-device query workflow"
```

### Task 9: 接入 AppRuntime 与 EntryAbility 生命周期

**Files:**
- Create: `entry/src/main/ets/runtime/AppRuntime.ets`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`
- Create: `entry/src/ohosTest/ets/test/CollaborationAbility.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

- [ ] **Step 1: 写入 Runtime 生命周期测试**

使用 fake transport 构造 `AppRuntime`，验证 `initialize()` 只组合一次、`onCollaborate()` 自动设为 `RESPONDER`、`destroy()` 可重复调用且只释放一次。

- [ ] **Step 2: 运行并确认失败**

Expected: FAIL，缺少 `AppRuntime`。

- [ ] **Step 3: 实现组合根**

```ts
export class AppRuntime {
  readonly store: AppStateStore;
  readonly coordinator: QueryCoordinator;

  static initialize(context: common.UIAbilityContext): AppRuntime;
  static current(): AppRuntime;
  static reset(): void;
}
```

`initialize()` 组合 `SystemScheduler`、`ProtocolCodec`、`CollaborationTransport(context, bundleName)`、`SessionManager`、`MockSummaryService`、`AppStateStore`、`QueryCoordinator`。`bundleName` 从 `context.applicationInfo.name` 读取，不在源码重复硬编码。

- [ ] **Step 4: 修改 EntryAbility**

```ts
onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
  AppRuntime.initialize(this.context);
}

onCollaborate(wantParam: Record<string, Object>): AbilityConstant.CollaborateResult {
  return AppRuntime.current().coordinator.acceptCollaboration(wantParam)
    ? AbilityConstant.CollaborateResult.ACCEPT
    : AbilityConstant.CollaborateResult.REJECT;
}

onDestroy(): void {
  AppRuntime.reset();
}
```

保留现有 `onWindowStageCreate()` 的 `pages/Index` 加载逻辑。删除 Task 6 的 probe transport。

- [ ] **Step 5: 运行单元测试、ohosTest 和构建**

Expected: Runtime 测试 PASS；ohosTest 能启动 `EntryAbility`；HAP 构建成功。

- [ ] **Step 6: 执行双真机最小连接门禁**

在设备 A 的 `CollaborationAbility.test.ets` 中调用 `AppRuntime.current().coordinator.selectInitiator()` 和 `connect()`；设备 B 保持应用关闭。测试建立正式 `AppRuntime` 会话后发送一个协议 `QUERY`，由 B 的正式 responder 流程返回 `QUERY_ACK` 和 `RESULT`，随后主动断开。

Expected: B 被拉起；两端收到 `connect`；A 收到 ACK 和模拟摘要；双方完成主动断开；无系统权限错误。若失败，保存 `BusinessError.code/message` 与 `ConnectResult.errorCode/reason`，执行本计划开头的停止条件。

- [ ] **Step 7: 提交**

```powershell
git add entry/src/main/ets/runtime entry/src/main/ets/entryability entry/src/ohosTest
git commit -m "feat: wire collaboration into ability lifecycle"
```

### Task 10: 构建单页 MVP UI

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/resources/base/element/string.json`
- Modify: `entry/src/main/resources/base/element/color.json`
- Create: `entry/src/ohosTest/ets/test/IndexPage.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

- [ ] **Step 1: 写入页面状态测试**

使用 ArkUI component test 验证：初始显示角色选择；选择发起端后显示“自动连接唯一设备”；`CONNECTING` 时禁用按钮；`CONNECTED` 时启用问题输入；`WAITING_ACK/WAITING_RESULT` 时禁用再次提交；`RESPONDER` 显示等待请求；成功后显示摘要、耗时和字节数；错误区域显示可操作信息。

- [ ] **Step 2: 运行并确认现有 Hello World 页面失败**

Expected: FAIL，找不到 `role-selector`、`connect-button`、`question-input`、`submit-button`、`result-summary` 等测试 ID。

- [ ] **Step 3: 实现单页状态订阅**

页面通过 `aboutToAppear()` 订阅 `AppRuntime.current().store`，把快照复制到 `@State snapshot`；`aboutToDisappear()` 调用 unsubscribe，不断开会话。

```ts
@Entry
@Component
struct Index {
  @State snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  @State question: string = '';
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    this.unsubscribe = AppRuntime.current().store.subscribe((state) => this.snapshot = state);
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
  }
}
```

- [ ] **Step 4: 实现完整交互**

页面使用一个可滚动 `Column`，顺序固定为：应用标题与状态；角色 `SegmentButton`；连接区；问题 `TextArea`；提交按钮；摘要区；指标区；错误区；断开按钮。所有控件使用资源字符串，按钮绑定 coordinator 命令并捕获 Promise rejection，禁止直接改 `ConnectionState`。

UI 行为：

- `UNSELECTED`：角色选择可用，其余禁用。
- `INITIATOR + IDLE/DISCONNECTED/ERROR`：显示“自动连接唯一设备”。
- `CONNECTED`：允许输入 1 至 1000 字符并提交。
- `WAITING_ACK/WAITING_RESULT`：显示 `Progress`，禁止第二次提交。
- `RESPONDER`：隐藏输入，显示“等待远端查询”。
- `ERROR`：显示 `AppError.message` 和手动重连操作，不自动调用 connect。

- [ ] **Step 5: 运行页面测试、全部测试和构建**

Expected: 页面测试 PASS；本地单元测试无失败；ohosTest 无失败；HAP 构建成功；320dp 与平板宽度下无文本溢出或控件重叠。

- [ ] **Step 6: 提交**

```powershell
git add entry/src/main/ets/pages entry/src/main/resources entry/src/ohosTest
git commit -m "feat: add cross-device query MVP interface"
```

### Task 11: 完成异常矩阵、指标与双真机验收

**Files:**
- Create: `docs/testing/cross-device-mvp-acceptance.md`
- Modify: `entry/src/test/SessionManager.test.ets`
- Modify: `entry/src/test/QueryCoordinator.test.ets`
- Modify: `entry/src/ohosTest/ets/test/CollaborationAbility.test.ets`

- [ ] **Step 1: 补齐自动化异常矩阵**

逐项添加并运行测试：0 台设备、2 台设备、连接拒绝、Wi-Fi 未开启、发送失败、ACK 超时、RESULT 超时、重复完成请求、迟到结果、未知请求、处理中断线、重复 destroy、第二次协同会话返回 `E_BUSY`。

- [ ] **Step 2: 核对隐私与字节指标**

测试 `Logger` 不输出 `question`、`summary`、完整 `deviceId`；`SessionManager` 的发送/接收字节数使用 UTF-8 编码后长度累加，不使用 JavaScript 字符长度。

- [ ] **Step 3: 编写双真机验收记录模板**

`cross-device-mvp-acceptance.md` 固定包含：设备型号/API/账号与组网前提；HAP commit；10 条查询表格；每条 `requestId`、ACK 时延、总时延、收发字节和结果；断线方式；手动重连结果；已知限制；原始系统错误码。

- [ ] **Step 4: 执行主链路验收**

设备 B 先关闭应用；A 启动并选择发起端；确认 resolver 只发现 B；自动连接并验证 B 被拉起为响应端；同一会话顺序提交 10 个不同问题；每次核对 ACK、匹配的 `requestId`、包含问题片段的模拟摘要和恢复 `CONNECTED`；最后主动断开。

Expected: 10/10 成功，无结果错配、崩溃、重复监听器或残留请求。

- [ ] **Step 5: 执行断线恢复验收**

查询处理中关闭 B 或中断可信连接；确认 A 进入 `DISCONNECTED`、清除 pending 且不自动重试；恢复环境后手动连接；再提交 1 条查询并成功返回。

- [ ] **Step 6: 运行最终验证**

```powershell
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test
& $node $hvigor --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
git diff --check
git status --short
```

Expected: 所有自动化测试通过；两个 HAP 构建成功；`git diff --check` 无输出；工作区只包含验收记录更新。

- [ ] **Step 7: 提交**

```powershell
git add entry/src/test entry/src/ohosTest docs/testing/cross-device-mvp-acceptance.md
git commit -m "test: verify cross-device communication MVP"
```

## 规格覆盖映射

| 规格要求 | 实现任务 |
|---|---|
| 模块边界与窄传输接口 | Task 1、5、8、9 |
| 版本化 JSON、大小和字段校验 | Task 2 |
| 确定性模拟摘要 | Task 3 |
| 自动选择唯一可信设备 | Task 4、8 |
| `Distributed Service Kit` 会话 | Task 6、9 |
| 单连接串行多查询 | Task 7、8 |
| ACK、RESULT、超时和迟到结果 | Task 7 |
| 无自动重连/重发 | Task 7、8、10 |
| 响应端自动拉起与角色识别 | Task 6、9 |
| 单页 UI | Task 10 |
| 异常、清理和隐私日志 | Task 6、7、11 |
| 10 次查询与断线恢复 | Task 11 |

## 完成定义

- 计划中的每个提交均可独立构建，纯逻辑任务遵循 red-green-refactor。
- 本地单元测试、ohosTest 和 debug HAP 构建全部通过。
- 两台真机完成 10 次串行查询和 1 次手动断线恢复。
- 通信内容只有 JSON 文本，不包含文件、URI、完整文档或二进制 payload。
- 未实现小艺、真实检索、Socket、多设备路由、并发、自动重试或后台长时任务。
