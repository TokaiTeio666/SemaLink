# SemaLink P4 通信端语义闭环需求设计

日期：2026-07-16
负责人：项目负责人
实现归属：通信端
状态：已确认设计，待实施计划

## 1. 目标

通信端在保留现有 Distributed Service Kit（DSK）传输实现的基础上，完成一个可演示、可测量、可独立测试的任务感知语义通信闭环：

```text
TaskRequest
→ 本地/远端设备语义路由
→ EvidenceUnit 边际效用调度
→ 首轮 L1
→ Task Sufficiency Feedback
→ 必要时第二轮 L2
→ ENOUGH / ABORT
```

P4 的核心价值不是替换传输 Kit，而是验证三项项目自研能力：

1. Device Semantic Router：决定任务应由本机还是远端设备处理。
2. Evidence Utility Scheduler：决定哪些证据值得优先发送。
3. Task Sufficiency Feedback：决定证据是否足够，以及是否需要追加。

## 2. 当前基础

项目已经具备：

- `CollaborationTransport` 和 `SessionManager` 的 DSK 通信链路；
- `QUERY / QUERY_ACK / RESULT / ERROR` JSON 协议；
- `QueryCoordinator` 的单轮查询编排；
- 收发字节、往返时延和对端设备信息统计；
- `LocalKnowledgeGateway`、L1/L2 载荷和知识结果校验；
- Fake Transport、Fake Scheduler 和通信单元测试。

P4 必须增量扩展现有实现，不破坏旧通信协议与已有测试。

## 3. 交付边界

### 3.1 通信端负责

- 页面输入到 `TaskRequest` 的映射；
- 本机和一个已连接远端设备的候选目录；
- 设备语义路由与可解释评分；
- Evidence MEU 排序、预算扣减与发送计划；
- 规则型 TSF 计算；
- L1/L2 两轮任务状态机；
- P4 语义协议编解码、幂等和错误处理；
- DSK 传输适配和 Profile 交换；
- 首结果、完成时延、字节、轮次和隐私指标；
- P5 息屏与后台互联扩展。

### 3.2 通信端不负责

- ArkData 表或文档 URI 的读取；
- 文档导入、切片、索引和检索算法；
- `EvidenceUnit` 内容的生成；
- ArkData 向量数据库或 MindSpore Lite 接入；
- 最终自然语言答案生成。

## 4. 共享契约

共享语义契约版本固定为 `1.0`。新语义协议版本固定为 `2.0`。现有协议 `1.0` 和本地知识契约 `1.0` 保持兼容，不与新版本混用。

```ts
export type SemanticContractVersion = '1.0';
export type SemanticProtocolVersion = '2.0';
export type PayloadLevel = 'L1' | 'L2';
export type PrivacyLevel = 'LOCAL_ONLY' | 'PRIVATE_GROUP';

export interface TaskFilters {
  documentIds?: string[];
  tags?: string[];
  modalities?: string[];
  updatedAfter?: number;
}

export interface TaskRequest {
  semanticContractVersion: SemanticContractVersion;
  taskId: string;
  queryText: string;
  requiredConcepts: string[];
  requiredConfidence: number;
  coverageThreshold: number;
  latencyBudgetMs: number;
  byteBudget: number;
  privacyLevel: PrivacyLevel;
  acceptableLevels: PayloadLevel[];
  filters?: TaskFilters;
}

export interface EvidenceUnit {
  semanticContractVersion: SemanticContractVersion;
  evidenceId: string;
  evidenceGroupId: string;
  sourceDeviceId: string;
  sourceDocId: string;
  sourceChunkId?: string;
  parentEvidenceId?: string;
  level: PayloadLevel;
  title: string;
  summary?: string;
  snippet?: string;
  relevance: number;
  coveredConcepts: string[];
  estimatedCoverageGain: number;
  byteCost: number;
  privacyLevel: PrivacyLevel;
  privacyCost: number;
  energyCost: number;
  hash: string;
  canEscalateTo: PayloadLevel[];
}

export interface TaskSufficiencyFeedback {
  semanticContractVersion: SemanticContractVersion;
  taskId: string;
  round: 1 | 2;
  status: 'ENOUGH' | 'NEED_MORE' | 'ABORT';
  answerCoverage: number;
  confidence: number;
  evidenceDiversity: number;
  missingConcepts: string[];
  preferredNextLevels: PayloadLevel[];
  maxAdditionalBytes: number;
  acceptedEvidenceIds: string[];
  rejectedEvidenceIds: string[];
}
```

约束：

- `taskId` 在一次任务的所有轮次中保持不变；
- `messageId` 用于消息幂等，`sessionId` 用于连接会话，两者不能替代 `taskId`；
- `evidenceId` 在同一索引版本内稳定；
- L2 通过 `evidenceGroupId` 或 `parentEvidenceId` 关联到对应 L1；
- `byteCost` 是单条 `EvidenceUnit` JSON 对象序列化后的 UTF-8 字节数，不包含 `EVIDENCE` 外层消息；
- 通信端不得重新解释知识端的数据库对象或文件地址。

## 5. 通信端模块

### 5.1 TaskRequestMapper

输入为页面问题和应用配置，输出合法 `TaskRequest`。

默认值：

- `requiredConfidence = 0.80`；
- `coverageThreshold = 0.80`；
- `latencyBudgetMs = 2000`；
- `byteBudget = 65536`；
- `privacyLevel = PRIVATE_GROUP`；
- `acceptableLevels = [L1, L2]`。

`requiredConcepts` 使用确定性的查询概念提取器产生。测试数据可以显式提供标注概念，以排除分词差异。

### 5.2 DeviceDirectory

设备目录只维护两类候选：本机和一个已连接远端。

```ts
export interface DeviceRuntimeSnapshot {
  rttMs: number;
  load: number;
  batteryLevel: number;
  networkType: string;
  lastSeenAt: number;
}
```

远端设备必须在 DSK 连接后完成 `PROFILE` 交换，才可参加路由。画像缺失、过期、契约不兼容或索引状态非 `READY` 时，远端不可选。

P4 不新增设备发现。远端身份继续由 `TrustedDeviceResolver` 和 DSK 提供。

### 5.3 DeviceSemanticRouter

评分结构：

```text
S(d|q) = 0.45 * semanticMatch
       + 0.20 * filterMatch
       + 0.10 * freshness
       - 0.10 * normalizedRtt
       - 0.05 * load
       - 0.10 * privacyRisk
```

规则：

- 无兼容 embedding 时，`semanticMatch` 使用查询概念与 `knowledgeDomains` 的加权匹配；
- 有兼容 embedding 时，可替换为余弦相似度；
- `LOCAL_ONLY` 任务的远端分数直接为负无穷；
- 硬过滤不满足时，设备不可选；
- 分数相同优先本机，避免无收益通信；
- 输出总分、每个分项和排除原因，供测试与页面展示。

远端 Profile 默认有效期为 5 分钟；连接期间收到新版 Profile 时刷新。过期 Profile 必须重新请求，不能继续沿用旧分数。

### 5.4 EvidenceUtilityScheduler

输入为 `TaskRequest`、候选 `EvidenceUnit[]`、当前任务状态和 TSF，输出本轮发送计划。

`byteBudget` 是任务证据预算：只统计 `EVIDENCE` 消息的完整应用层编码字节，包含消息外层和证据数组开销，不统计 `PROFILE`、`TASK_ACK`、`TSF` 和 `ERROR` 控制消息。总协议字节仍需单独记录，用于性能评测。

默认效用：

```text
utility = 0.30 * relevance
        + 0.25 * coverageGain
        + 0.15 * diversityGain
        - 0.10 * normalizedBytes
        - 0.08 * normalizedLatency
        - 0.08 * privacyCost
        - 0.04 * energyCost

MEU = utility / (byteCost + 128)
```

硬约束优先于评分：

- 首轮只选择 L1；
- 第二轮只选择覆盖 `missingConcepts` 的 L2；
- 累计 `EVIDENCE` 应用层编码字节不得超过 `byteBudget`；
- 不发送不满足任务隐私策略的证据；
- 已接受、已拒绝或已发送证据不得重复发送；
- 排序必须确定，同分按 `evidenceId` 升序；
- 第二轮后不继续追加。

### 5.5 TaskSufficiencyEvaluator

P4 使用规则型评估器，不依赖大模型。

```text
answerCoverage = 已覆盖必需概念权重 / 全部必需概念权重
confidence = 0.60 * 已接受证据平均相关度 + 0.40 * answerCoverage
evidenceDiversity = min(1, 唯一文档数 / max(1, 已接受证据数))
```

判定：

- `answerCoverage >= coverageThreshold` 且 `confidence >= requiredConfidence` 时为 `ENOUGH`；
- 第一轮不足时为 `NEED_MORE`，并返回 `missingConcepts`；
- 第二轮不足、预算耗尽或无可追加证据时为 `ABORT`；
- `ABORT` 的标准错误码为 `INSUFFICIENT_EVIDENCE`。

P4 不接入真实能耗模型。Scheduler 使用知识端提供的确定性代理成本，保证测试可复现；真实电量和 CPU 数据只记录为运行指标，不参与 P4 硬性验收。

### 5.6 ProgressiveQueryCoordinator

连接状态继续由 `SessionManager` 管理。任务状态单独建模：

```text
CREATED
→ ROUTING
→ WAITING_L1
→ EVALUATING_L1
→ WAITING_L2
→ EVALUATING_L2
→ COMPLETED | ABORTED | FAILED
```

任务状态不得复用现有 `ConnectionState`。本机路由胜出时直接调用本地知识 Provider，不发送 `TASK` 或 `EVIDENCE` 网络消息。

## 6. P4 语义协议

协议载荷继续使用结构化 JSON。P4 不要求二进制帧、压缩或任意字节流分片。为满足 DSK
单消息 4 KiB 边界，P4 支持 Evidence 语义分页：发起端通过可选
`TASK.evidencePagingVersion=1` 声明能力，响应端在协商成功后发送带 0-based
`pageIndex/pageCount` 的 `EVIDENCE` 页面。每页至少包含一个完整 `EvidenceUnit`，单个
Evidence 不跨页，完整 envelope 编码后不得超过 4 KiB；单个 Evidence 仍超限时明确失败，
不得静默丢弃。旧 TASK 不声明能力时继续发送单页 Evidence。

接收端按 `taskId + round` 聚合页面，允许乱序和相同页面重试，校验各页 `pageCount`
一致，并在收齐全部页面后按页序合并、跨页去重且只执行一次 TSF。缺页时不得提前评估；
超过任务 `latencyBudgetMs` 仍未收齐时以 `E_EVIDENCE_PAGE_TIMEOUT` 失败并清理聚合状态。

消息类型：

```text
PROFILE
TASK
TASK_ACK
EVIDENCE
TSF
ERROR
CANCEL
```

`EVIDENCE` 必须包含：

- `taskId`；
- `round`；
- `level`；
- `evidence[]`；
- 本消息字节数和累计字节数；
- 是否仍有可升级证据。

旧 `QUERY / QUERY_ACK / RESULT / ERROR` 保持兼容，但不得承载 P4 渐进任务。

幂等和顺序要求：

- 相同 `messageId` 只处理一次；
- 旧轮次和未来轮次消息必须忽略并记录；
- 已完成任务收到重复 `EVIDENCE` 或 `TSF` 不得二次完成；
- 超时、断线和取消必须结束当前等待并释放计时器；
- 错误不得泄漏内部堆栈或知识端异常对象。

## 7. 端到端场景

### 7.1 本机胜出

```text
提交 TaskRequest
→ Router 选择本机
→ 本地 Provider 返回 EvidenceUnit[]
→ 调度 L1
→ TSF 评估
→ 必要时本地追加 L2
→ 完成
```

验收：不发送 `TASK`、`EVIDENCE` 或 `TSF` 网络消息。

### 7.2 远端两轮闭环

```text
PROFILE 已同步
→ Router 选择远端
→ TASK
← TASK_ACK
← EVIDENCE(L1, round=1)
→ TSF(NEED_MORE, missingConcepts)
← EVIDENCE(L2, round=2)
→ TSF(ENOUGH)
→ 完成
```

### 7.3 L1 提前结束

首轮 L1 已达到覆盖率与置信度阈值时，发起端立即发送 `TSF(ENOUGH)`，不得请求或接收第二轮 L2。

### 7.4 证据不足

第二轮后仍不足时发送 `TSF(ABORT)`，任务进入 `ABORTED`，界面展示缺失概念和 `INSUFFICIENT_EVIDENCE`，不得伪造成功结果。

## 8. 指标

每个任务至少记录：

- 本机和远端路由总分与分项；
- 最终选中设备和选择原因；
- 首结果延迟；
- 任务完成延迟；
- 发送与接收字节；
- 任务轮次数；
- 最终 TSF 状态；
- 覆盖率、置信度和多样性；
- 隐私暴露级别；
- 超时、断线和恢复事件。

真机目标：首结果延迟不高于 800 ms，任务完成延迟不高于 2 s。P4 硬门槛是自动输出 P50/P95 和基线对比；单次设备环境波动不直接判定功能失败。

## 9. P5 息屏与后台互联扩展

P4 只记录前后台和息屏行为。发生系统中断时，返回 `E_BACKGROUND_INTERRUPTED`，不得假定 DSK 会话永久存活。

P5 使用单独的实施计划和验收周期，不与 P4 语义闭环放入同一次实现。只有 P4 验收完成后才进入 P5。

P5 目标是在 HarmonyOS 允许的用户可感知长时任务场景中支持息屏互联：

```text
用户主动开启后台互联
→ 启动 Background Tasks Kit 长时任务
→ 显示持续通知
→ 保持或恢复 DSK 会话
→ 息屏期间处理 TASK / EVIDENCE / TSF
→ 任务完成、取消或错误时停止长时任务
```

约束：

- 不实现不可见、无限期后台常驻；
- 必须由用户主动开启；
- 必须有用户可感知的持续通知；
- 只有活动中的多设备互联任务才允许保持；
- P5 具体 API、权限和长时任务类型以目标 API 18+ SDK 为准；
- 当前 DSK 会话能否稳定跨息屏必须通过真机验证，不能只以单测结论代替。
- P5 可以在独立计划中增加低频心跳和重连策略；该能力不属于 P4 协议门槛。

恢复状态至少包含：

- `taskId`；
- 当前轮次；
- 已发送和已接收证据 ID；
- 已接受和已拒绝证据 ID；
- 已使用字节；
- 最近 TSF；
- 当前选中设备和 Profile 版本。

P5 测试矩阵：

- 5、15、30 分钟息屏；
- 发起端息屏、响应端息屏、双端息屏；
- 有长时任务和无长时任务对照；
- 息屏期间发起任务、处理中息屏、完成后息屏；
- 网络切换、断网恢复和用户手动停止。

## 10. 测试与验收

共享固定查询集至少 20 条：

- 8 条应路由本机；
- 8 条应路由远端；
- 2 条 L1 即可满足；
- 2 条 L2 后仍不足。

P4 硬性验收：

- 标注查询集设备 Top-1 路由准确率不低于 90%；
- 相同输入的路由、证据顺序和 TSF 完全确定；
- 远端正常场景完成 `L1 → NEED_MORE → L2 → ENOUGH`；
- L1 足够时不发送 L2；
- 相比“始终发送全部 L2”基线，中位发送字节减少至少 30%；
- 所有任务不超过字节预算；
- P4 不发送 L3、文件 URI、embedding 或完整原文；
- 重复消息、乱序、超时和断线不造成状态卡死或重复完成；
- 现有通信测试继续通过。

通信端必须具备以下测试层次：

1. Router、Scheduler、TSF、状态机和 Codec 单元测试；
2. Fake Transport + Fake Knowledge Provider 单进程闭环测试；
3. DSK 双设备真机集成测试；
4. 基线与 SemaLink 模式对比测试；
5. P5 息屏真机测试。

## 11. 里程碑

| 阶段 | 通信端交付物 | 依赖 |
|---|---|---|
| P4.0 | 共享契约、错误码、固定测试夹具 | 项目负责人确认 |
| P4.1 | Router、Scheduler、TSF、任务状态机 | Fake Knowledge Provider |
| P4.2 | Protocol 2.0、Profile 交换、单端闭环 | Fake Transport |
| P4.3 | DSK 双设备 L1/L2 集成 | 知识端 Provider |
| P4.4 | 指标、基线对比、答辩日志 | 固定查询集 |
| P5 | 长时任务、息屏恢复、真机矩阵 | API 18+ 与系统权限 |

## 12. P4 明确不做

- Network Kit TCP/UDP/Multicast/TLS；
- 多于一个远端候选设备；
- ArkData 真实向量数据库；
- MindSpore Lite 推理；
- L3 原始文件传输；
- 二进制帧、压缩、任意字节流分片、心跳和选择性重传；
- HUKS、Asset Store 和生产级鉴权；
- 大模型答案生成；
- 不可见的后台常驻服务。
