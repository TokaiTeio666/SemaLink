# 小艺端 A2A V0.6 真机测试交接

## 1. 当前实现范围与明确边界

本轮已实现 `SemaLinkAgentExtensionAbility` 的端 A2A V0.6 `message/stream` 解析、Context/Task 生命周期、流式 Artifact/终态响应、完整 Task 响应工厂、取消、进程级 Runtime、真实本机语义知识检索、确定性查询范围解析、`INPUT_REQUIRED` 恢复，以及可替换的 `CrossDeviceKnowledgePort`。生产只处理 `message/stream` 与 `tasks/cancel`；当前华为端文档未列出 `message/send`，因此不要期待或发送该方法。仓库中的完整 Task 响应工厂只是合同核对辅助能力，并未暴露成第三个生产方法。

生产默认使用 `UnavailableCrossDeviceKnowledgePort`。真实 DSK/TLS、设备发现/配对、远端等待、`PeerConnectionPool` 接线均未实现。单元测试中的设备 B 是 Fake，不代表真实跨设备通信成功。本轮也未在真机上执行测试。

后续真实跨设备 Adapter 的唯一推荐接线位置是：

`entry/src/main/ets/agent/query/CrossDeviceKnowledgePort.ets`

将实现注入 `RuntimeAgentKnowledgeQueryPort`，替换 `SemaLinkAgentExtensionAbility` 中的 `UnavailableCrossDeviceKnowledgePort`；不要在 Ability 内直接接触网络或 RDB。

## 2. 真机测试前置条件

- HarmonyOS 6.1.1.125、API 24 兼容设备。
- DevEco Studio 使用项目既有 SDK、bundle、签名和发布配置。
- 小艺测试账号已加入对应测试发布范围，账号、设备区域和应用市场环境一致。
- 安装包中的 `SemaLinkAgentExtensionAbility`、`ohos.extension.agent` metadata 和 `semalink_knowledge_agent` Agent ID 可被平台识别。
- 不要在反馈中提供证书、密码、keystore、签名材料、文档正文、用户问题全文或任何设备标识。

## 3. 构建、安装和发布检查

在仓库根目录运行：

```powershell
& "D:\Huawei\DevEco Studio\tools\node\node.exe" `
  "D:\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" `
  --mode module `
  -p module=entry@default `
  -p product=default `
  -p requiredDeviceType=phone `
  assembleHap `
  --analyze=normal `
  --parallel `
  --incremental `
  --daemon
```

通过 DevEco Studio 将已签名 HAP 安装到测试设备。发布前核对 Agent 测试账号白名单、测试版本状态、AgentCard/应用关联状态、bundleName、Ability 名称和 Agent ID。

本轮已把 AgentCard 的 `capabilities.streaming` 从 `false` 改为 `true`。必须重新导入 AgentCard，并按平台流程重新发布测试版本，否则平台能力声明与安装包行为不一致。

## 4. 本机知识测试数据

1. 首次启动 SemaLink，等待内置知识导入完成；也可通过现有文档导入入口加入一份不敏感的测试文档。
2. 不要在日志或反馈中粘贴文档正文。
3. 推荐提问：“进程和线程有什么区别？”、“事务隔离级别是什么？”、“解释优先级调度”。
4. 关闭 UI 后再次从小艺提问，验证 UI 退出不会销毁 Agent 正在借用的进程级知识 Runtime。
5. 无匹配问题应以 COMPLETED 返回“未找到相关资料”，而不是 FAILED。

## 5. 日志过滤与预期顺序

DevEco Studio Log 过滤关键字：`SemaLinkAgent`。

正常首轮顺序：

1. `lifecycle=onCreate runtime=cold_start_ready`
2. `lifecycle=onConnect`
3. 可能出现 `lifecycle=onAuth` 相关平台调用；授权内容不会记录
4. `event=command kind=message/stream`
5. `event=transition ... TASK_STATE_SUBMITTED`
6. `event=transition ... TASK_STATE_WORKING`
7. `event=runtime outcome=INITIALIZED`（首次冷启动）
8. `event=transition ... TASK_STATE_COMPLETED` 或安全的 FAILED/CANCELLED

日志中的 Context/Task 是统一哈希掩码。请勿要求打印原始 ID、请求 JSON、问题全文、文档正文、deviceId/networkId、路径、SQL 或握手数据。

UI/框架异常日志只输出稳定事件名和脱敏后的有限数值错误码，不再公开序列化任意 Error 或 `BusinessError.message`。

## 6. 协议、范围与多轮预期

- 正常流式成功顺序固定为：完整 Task `SUBMITTED` → `statusUpdate/WORKING` → `artifactUpdate` → `statusUpdate/COMPLETED`。
- `artifactUpdate` 必须包含稳定的 `taskId/contextId`、`artifact.artifactId`、文本 `parts`、`append=false`、`lastChunk=true`。最终 COMPLETED 是独立状态帧。
- 当前可访问的华为端 A2A V0.6 页面和 API 24 声明足以确认 `lastChunk` 与上述帧顺序，但没有提供可核验的 `statusUpdate.final` 端侧样例；当前编码器保守地不发送 `final`。不要借用通用 A2A 实现猜测该字段，真机若观察到平台要求它，只反馈字段名和布尔值，不要反馈原始 JSON。
- 工厂也支持单帧完整 Task：`status=COMPLETED` 且 `artifacts` 位于 Task 内，用于核对华为文档中的完整响应合同；生产当前按 AgentCard 声明发送流式序列。
- 后续携带有效 contextId 的消息应复用 Context。
- 取消标准输出拼写为 `TASK_STATE_CANCELLED`。输入兼容历史 `TASK_STATE_CANCELED`，内部只保留双 L 状态；取消后不得再发送 COMPLETED。
- JSON-RPC `id` 接受非空 string 或有限 number，响应必须保持原类型和值；非法或不可用 ID 的协议错误使用 `id:null`。
- 文本 Part 接受省略 `mediaType` 或 `mediaType:"text/plain"`；二进制、未知字段-only、空文本和内容/类型矛盾均应被拒绝。
- `metadata.traceId` 与 `metadata.agentId` 按华为当前结构均为必填；响应保留请求的 `traceId`，但 `agentId` 始终由服务端固定为 `semalink_knowledge_agent`，绝不回显请求方伪造值。`appVersion` 和未知扩展字段可省略。协议日志不得记录问题正文或 metadata 内容。
- 未明确范围默认 `LOCAL_ONLY`；“本机/本地/当前设备”是 `LOCAL_ONLY`；“其他设备/另一台可信设备/跨设备”是 `REMOTE_ONLY`；同时包含本机、远端和“同时/一起/和/与”时是 `LOCAL_AND_REMOTE`。
- 普通本机查询不得附带“远端不可用”。`LOCAL_AND_REMOTE` 可在本机成功时降级并明确远端未执行。
- `REMOTE_ONLY` 遇到生产不可用端口时，顺序为 SUBMITTED → WORKING → INPUT_REQUIRED，并询问“是否改为本机查询？”。用同一连接、同一 contextId、同一 taskId 发送“改为本机查询”，应继续 WORKING → Artifact(lastChunk) → COMPLETED；实际检索仍使用首轮原问题，只把范围强制改为 `LOCAL_ONLY`，第二轮确认文本不能替代原问题。
- `INPUT_REQUIRED` 期间执行超时暂停，并使用独立的待输入期限；接受后递增执行代次、从第二个请求重新获得完整执行时限，并把后续帧关联到第二个 JSON-RPC `id`。旧代次的超时或迟到结果必须静默丢弃。
- 待输入期限到期时任务在本地原子转为 FAILED 并释放内部执行资源，但不会在已结束的旧请求上异步补发终态；这是为了不让 Timer 长期持有可能已失效的 proxy/sender。到期后的 continuation 会被拒绝。该行为及端侧是否另有待输入超时通知机制需要真机观察，不能凭通用 A2A 约定猜测。
- 本机降级仅接受确定性白名单，例如“改为本机查询/查询本机/可以/好/是/同意”。“不需要/不用了/否/不同意”结束为 CANCELLED；“取消/停止/算了”同样取消；无关文本保持 INPUT_REQUIRED 并再次给出明确提示，不会被当作新查询执行。
- 连接 B 继续或取消连接 A 的 Task 必须得到 Task not found；断开 A 只取消 A 的活动 Task，不影响 B。
- 当前生产版本不会返回真实远端 Evidence。

API 24 的 `authorize(handshakeData)` 是同步 `void`。当前策略仅做非空与 16 KiB UTF-8 字节上限检查，然后把 SDK 提供的不透明协商数据原样交给 `authorize`；公开 SDK/端 A2A 页面没有提供可据以校验版本或调用来源的应用层结构，因此当前不自行解析、不记录 handshakeData，也不声称完成了更强身份校验。

协议 Fixture 使用 `HuaweiA2AV06Fixtures` 并逐项携带来源 URL、文档标题、版本/更新时间、场景和 fidelity。`EXACT_OFFICIAL` 只允许逐字段复制可核验的华为原样示例；`DERIVED_FROM_OFFICIAL` 是按官方字段整理的最小载荷；`PROJECT_COMPATIBILITY` 是项目边界输入。当前仓库没有可诚实标记为 `EXACT_OFFICIAL` 的 Fixture，现有华为形状样例均明确标为派生，非法请求样例标为项目兼容；这些测试不能证明真机兼容。

自动化范围矩阵已覆盖普通问题默认 `LOCAL_ONLY`、两种本机表达、两种远端表达、两种本机加远端表达；并验证 `LOCAL_ONLY` 不触发远端、`REMOTE_ONLY` 在端口不可用时不偷查本机而进入 INPUT_REQUIRED、`LOCAL_AND_REMOTE` 在本机成功时带降级说明完成。连接隔离测试覆盖跨连接 continuation/cancel、错误 context、重复同意、终态继续和并行 INPUT_REQUIRED 任务不串线。

## 7. 快速故障定位表

| 观察结果 | 优先检查 |
| --- | --- |
| 无 `onCreate` | 测试发布、账号/区域、安装包、Ability 注册、AgentCard/应用关联、平台路由 |
| 有 `onCreate/onConnect`，无 `onData` | 小艺授权/握手、测试账号、平台路由 |
| 有 `onData` 命令错误，无 WORKING | A2A JSON-RPC 方法、必填字段、role、text Part、contextId |
| 有 WORKING，无终态 | Runtime 初始化、本地索引、Executor 阻塞或取消链 |
| `event=runtime outcome=FAILED_RETRY_ALLOWED` | 本地 RDB/资源初始化失败；下一请求会重试 |
| 有 COMPLETED | Agent 本地协议与检索链路成功；不代表真实跨设备成功 |
| Context invalid / 99911222 | contextId 已过期、被重置或不属于当前会话 |
| Task not found / -32001 | taskId 不存在或已清理 |
| INPUT_REQUIRED 后无法继续 | 是否复用原 connection/contextId/taskId，任务是否仍为 INPUT_REQUIRED，确认文本是否属于明确白名单 |
| Artifact 后无 COMPLETED | 是否收到 `lastChunk=true`，平台是否按 `streaming=true` 重新导入 AgentCard |

Runtime 的正常证据是同一进程只出现一次 `event=runtime outcome=INITIALIZED`。并发 UI/Agent 启动应合并初始化；失败时出现 `FAILED_RETRY_ALLOWED`，下一次请求可重试。UI 退出不应出现进程级 `SHUTDOWN`；该事件只属于显式进程/测试关闭。

## 8. 如何区分问题归属

- 平台/账号：完全没有 Ability 生命周期日志，且相同安装包手动启动正常。
- 安装包/注册：平台能看到应用，但找不到 Agent Ability；核对打包后的 module profile。
- 协议：`onData` 已到达且出现 parse/invalid params/unsupported operation。
- Runtime/代码：已有 WORKING，随后 FAILED，或出现 Runtime 失败日志。
- 本地数据：Runtime 成功但总是空结果；核对内置导入状态、索引状态和测试问题是否匹配。
- 真实跨设备：当前尚未接线，看到“跨设备通道当前不可用”是预期，不是网络回归。

## 9. 反馈格式

请只反馈：系统版本、应用测试版本、复现时间、是否出现 onCreate/onConnect/onData、method 名、`id` 的类型（string/number/null，不要值）、掩码后的 context/task/artifact、状态序列、是否看到 `append/lastChunk/final` 字段及其布尔值、公开错误码、Runtime outcome、是否能手动打开应用、是否能完成本机问题。

遇到未知真机协议结构时，最小反馈格式为：`method=<公开方法名>; idType=<类型>; frameKind=<task|statusUpdate|artifactUpdate|error|unknown>; keys=<仅字段名>; publicCode=<公开错误码>; timestamp=<时间>`。不要附带字段值、用户问题全文、文档正文、原始协议 JSON、handshakeData、设备 ID、网络 ID、路径、SQL、证书或签名信息。
