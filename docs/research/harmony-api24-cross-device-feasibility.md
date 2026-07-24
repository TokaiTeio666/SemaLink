# HarmonyOS API 24 跨设备知识查询可行性验证

> 验证日期：2026-07-23  
> 本机 SDK：HarmonyOS 6.1.1 Release，API 24，版本 `6.1.1.125`  
> 结论：`FEASIBLE_FOR_FOREGROUND_TEXT_COLLABORATION`  
> 真机状态：`AWAITING_DEVICE_SPIKE`

## 结论

API 24 提供了满足 SemaLink 前台跨设备知识查询所需的正式公开能力：

- `distributedDeviceManager` 查询已授权、在线且可连接的设备；
- `abilityConnectionManager` 在两台设备上的 UIAbility 之间建立协同会话；
- `sendMessage()` 与 `receiveMessage` 提供双向文本消息；
- 对端 UIAbility 可在 `onCollaborate()` 中接受会话并执行本地逻辑；
- 应用层可以用 `requestId` 实现请求、响应、取消、超时和幂等。

该能力不是后台常驻通道。官方说明：未申请长时任务时，应用锁屏或退至后台约 5 秒后，协同生命周期会结束。因此首版必须按前台协同设计，后台行为需真机验证，不得承诺后台长期接收。

普通三方应用只能使用文本消息。`sendMessage()` 的官方接口说明给出的单条文本上限为 1 KB，所以协议必须把逻辑响应限制在 64 KB 内，并拆分为不超过 1 KB 的帧；不得调用仅系统应用可用的字节流、图片或传输流能力。

## 可行性矩阵

| 项目 | 结果 |
|---|---|
| 候选 Kit/模块 | Distributed Service Kit / `abilityConnectionManager` + `distributedDeviceManager` |
| 精确 import | `import { abilityConnectionManager, distributedDeviceManager } from '@kit.DistributedServiceKit';` |
| 精确 API 名称 | `createDeviceManager`、`getAvailableDeviceList`、`releaseDeviceManager`、`createAbilityConnectionSession`、`on('connect'/'disconnect'/'receiveMessage')`、`connect`、`acceptConnect`、`sendMessage`、`disconnect`、`destroyAbilityConnectionSession` |
| API 起始版本 | 设备管理 API 10；应用协同 API 18 |
| API 24 是否存在 | 是；本机 API 24 声明中真实存在 |
| 支持设备类型 | Phone；本机 `phone.json` 包含 `SystemCapability.DistributedSched.AppCollaboration` |
| 所需权限 | `ohos.permission.INTERNET`、`ohos.permission.GET_NETWORK_INFO`、`ohos.permission.SET_NETWORK_INFO`、`ohos.permission.DISTRIBUTED_DATASYNC` |
| 权限是否 user_grant | 仅 `DISTRIBUTED_DATASYNC` 为 `user_grant`；其余三项为 `system_grant`、`normal` |
| 是否普通三方应用可用 | 是；声明无 `@systemapi`，所需权限级别均为 `normal`；官方指南明确三方应用可传文本 |
| 是否支持设备发现 | 是；支持发现、绑定、查询在线可信设备以及设备上下线监听 |
| 是否支持双向自定义数据 | 是；普通三方应用支持双向文本，可承载严格校验的 JSON |
| 是否支持后台接收 | 有条件；协同期间可接收，但未申请长时任务时后台或锁屏约 5 秒后会结束，不能视为后台常驻 |
| 是否要求特定 Ability | 是；Stage 模型 UIAbility，接收端实现 `onCollaborate()` |
| 是否需要同账号 | 不强制。同账号支持相同或不同 bundleName；非同账号仅支持相同 AppID |
| 是否需要同网络 | 需要先完成分布式组网；官方设备管理指南要求同一局域网或开启蓝牙 |
| 是否需要系统可信组网 | 是；查询到的是已授权、在线且可连接的设备；非可信设备需先发现和绑定 |
| 单次数据大小限制 | `sendMessage()` 单条文本 1 KB；项目逻辑响应上限 64 KB，必须应用层分帧 |
| 关键错误码 | 通用 `201` 权限拒绝、`401` 参数错误、`801` 设备能力不支持；连接结果包括 `CONNECTED_SESSION_EXISTS(0)`、`PEER_APP_REJECTED(1)`、`LOCAL_WIFI_NOT_OPEN(2)`、`PEER_WIFI_NOT_OPEN(3)`、`PEER_ABILITY_NO_ONCOLLABORATE(4)`、`SYSTEM_INTERNAL_ERROR(5)` |
| 本机 SDK 声明路径 | `D:\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.distributedsched.abilityConnectionManager.d.ts`；`D:\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.distributedDeviceManager.d.ts`；`D:\Huawei\DevEco Studio\sdk\default\openharmony\ets\kits\@kit.DistributedServiceKit.d.ts` |
| 官方文档 URL | [跨设备连接 UIAbility 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/abilityconnectmanager-guidelines)；[abilityConnectionManager API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-distributed-abilityconnectionmanager)；[distributedDeviceManager API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-distributeddevicemanager) |

## 证据分级

### 本机 SDK 中真实存在

- `sdk-pkg.json` 声明 `apiVersion: 24`、`displayName: HarmonyOS 6.1.1`、`version: 6.1.1.125`。
- `@kit.DistributedServiceKit.d.ts` 公开导出 `distributedDeviceManager` 与 `abilityConnectionManager`。
- `abilityConnectionManager` 的命名空间、类型和核心函数从 API 18 起存在，使用 `SystemCapability.DistributedSched.AppCollaboration`。
- `distributedDeviceManager` 的设备列表和生命周期 API 从 API 10 起存在。
- Phone 的设备能力清单包含 `SystemCapability.DistributedSched.AppCollaboration`。
- 权限定义表中四项权限均为 `normal`；`DISTRIBUTED_DATASYNC` 为 `user_grant`。

### 华为官方文档明确支持

- API 18 起支持跨设备 UIAbility 连接与通信。
- 普通三方应用可发送文本消息；更高带宽的数据类型只对系统应用开放。
- `connect()` 可拉起对端应用，对端通过 `onCollaborate()` 和 `acceptConnect()` 接受连接。
- 双端可监听消息并调用 `sendMessage()`，因此可实现请求与响应。
- 设备管理提供发现、绑定、可信设备查询和上下线监听。
- 同账号可跨相同或不同 bundleName；非同账号必须是相同 AppID。
- 未申请长时任务时，锁屏或退到后台约 5 秒后会结束协同生命周期。

### 项目推断

- JSON 文本可承载版本化 PING/PONG、画像摘要、查询、响应、错误和取消消息。
- `requestId`、`deadlineAtMs` 和幂等缓存属于应用层，不依赖系统提供 RPC 语义。
- 64 KB 逻辑响应可用 1 KB 以下的有界分帧实现，但必须限制总帧数、总大小、重组 TTL 和并发，不能把单条系统消息当成 64 KB。
- 系统可信设备只代表系统层已组网，不等于 SemaLink 应用层 `TRUSTED`；仍需用户在 SemaLink 中确认。

### 尚未确认

- 三台具体 API 24 真机上的发现范围、系统组网状态和 `onCollaborate()` 拉起行为；
- 真机前台 PING/PONG、画像交换、QUERY/RESPONSE 和 CANCEL；
- 不同账号但相同 AppID 的真机行为；
- 长时任务申请后的后台持续时间；
- 1 KB 边界按 UTF-8 字节还是平台内部字符串长度执行的具体错误表现。

## 被排除的候选能力

| 候选 | 结论 |
|---|---|
| Service Collaboration Kit | 面向特定协同服务，不是本任务所需的通用同应用请求/响应通道 |
| Share Kit、系统分享 | 面向内容分享和目标应用选择，不提供持续双向请求/响应会话 |
| 相机互通、图库互通、游戏资源传输 | 专用业务能力，不能当成通用消息通道 |
| 跨端迁移/接续 | 迁移 UI 或任务状态，不等于双向远端查询 RPC |
| Distributed Data Object/关系型数据跨设备同步 | 面向状态或数据同步，不适合作为有截止时间、取消和逐请求授权的 RPC |
| Network Kit TCP/TLS/HTTP/WebSocket | 技术上可通信，但本任务明确禁止用自建网络通道绕过官方跨设备能力 |
| 旧 Feature Ability / API 7 示例 | 已不符合 Stage 模型和 API 24 约束 |

## 最小 PING/PONG Spike

代码：

- `entry/src/main/ets/debug/CrossDevicePingPongSpike.ets`
- `entry/src/main/ets/debug/CollaborationProbe.ets`
- `entry/src/test/CrossDevicePingPongSpike.test.ets`

负载严格只有：

```json
{
  "protocolVersion": 1,
  "requestId": "opaque-request-id",
  "messageType": "PING"
}
```

响应只把 `messageType` 改为 `PONG` 并保留同一 `requestId`。日志只记录事件类型，不记录完整设备 ID、networkId 或 requestId。

编译验证：

```text
hvigor ... entry@default ... test
BUILD SUCCESSFUL
```

该结果只证明 API 24 SDK 声明、真实 `abilityConnectionManager` 适配代码和 Spike 协议可以编译。尚未在三台真机上执行，因此状态为：

```text
AWAITING_DEVICE_SPIKE
COMPILED_NOT_EXECUTED
```

## 三台真机执行步骤

1. A/B/C 安装同一签名、同一 AppID 的 SemaLink HAP，确认系统均为 API 24。
2. 打开 Wi-Fi 和蓝牙；同账号时确认系统已自组网，非同账号时先完成设备发现与绑定。
3. 三台设备授予 `ohos.permission.DISTRIBUTED_DATASYNC`。
4. 在 B/C 上保持 SemaLink 可被前台拉起。
5. A 列出在线可信设备，但日志和 UI 不显示完整 networkId。
6. A 选择 B，调用真实 `createAbilityConnectionSession()` 和 `connect()`。
7. B 的 `onCollaborate()` 调用真实 `acceptConnect()`。
8. A 发送版本 1 的 PING；B 校验后返回相同 `requestId` 的 PONG。
9. A 收到 PONG 后主动 `disconnect()` 并 `destroyAbilityConnectionSession()`。
10. 对 C 重复步骤 6 至 9。
11. 记录错误码、连接耗时和 PING/PONG 往返耗时，不记录完整设备 ID 或消息负载。

通过标准：A→B 和 A→C 均在真机收到匹配 PONG，资源正常释放，无权限、能力或签名错误。执行前不得把本次编译结果写成真机通过。
