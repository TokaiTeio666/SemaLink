# SemaLink P4 检索知识端证据提供需求设计

日期：2026-07-16
负责人：项目负责人
实现归属：检索知识端
状态：已确认设计，待实施计划

## 1. 目标

检索知识端负责把本机文档库转换为通信端可消费的知识画像和结构化证据候选：

```text
TaskRequest
→ 本地检索
→ 稳定候选排序
→ EvidenceUnitFactory
→ KnowledgeProfile + EvidenceUnit[]
```

知识端只回答两个问题：

1. 本机拥有哪些知识和检索能力；
2. 当前任务有哪些可用的 L1/L2 证据候选。

知识端不决定选哪台设备、发送顺序、追加轮次或何时停止。

## 2. 当前基础

项目已经具备：

- 文档选择、内置文档导入和用户文本导入；
- 文本归一化、关键词提取和文档切片；
- `KnowledgeDatabase` 与 `RdbDocumentRepository`；
- `KeywordRetrievalEngine` 和稳定相关度排序；
- `L1PayloadBuilder`、`L2PayloadBuilder` 和字节预算控制；
- `KnowledgeProfileBuilder`；
- `LocalKnowledgeGateway`、契约校验和本地检索基准测试。

P4 必须复用这些能力，不重新实现数据库或文档流水线。

## 3. 交付边界

### 3.1 检索知识端负责

- 文档导入、解析、归一化、切片和增量更新；
- ArkData RDB 文档与分块持久化；
- 关键词检索、过滤、候选合并和稳定排序；
- 可替换检索引擎接口；
- 预计算向量或 Stub 检索实现的测试支持；
- `KnowledgeProfile` 的真实统计；
- `EvidenceUnitFactory` 和 L1/L2 候选生成；
- 标准 `KnowledgeError`；
- 重启恢复和索引版本管理。

### 3.2 检索知识端不负责

- DSK、Network Kit 或任何协议发送；
- 设备语义路由；
- MEU 调度和全局字节预算；
- TSF 判定；
- 连接、任务轮次或后台生命周期；
- 最终自然语言答案生成。

## 4. 对外接口

新增通信侧唯一允许调用的窄接口：

```ts
export interface SemanticKnowledgeProvider {
  getProfile(): Promise<KnowledgeProfile>;
  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]>;
}
```

兼容要求：

- 现有 `LocalKnowledgeGateway.query()` 和 `getKnowledgeProfile()` 保留；
- 旧接口继续输出现有 L1/L2 `payloadJson`；
- 新接口直接输出结构化 `EvidenceUnit[]`；
- 通信端不得通过新接口读取 Repository、RDB、文档 URI 或 `RetrievalCandidate`。

## 5. 共享契约

共享语义契约版本固定为 `1.0`。本地知识契约继续使用现有 `1.0`。

知识端消费以下任务字段：

```ts
export interface TaskRequest {
  semanticContractVersion: '1.0';
  taskId: string;
  queryText: string;
  requiredConcepts: string[];
  requiredConfidence: number;
  coverageThreshold: number;
  latencyBudgetMs: number;
  byteBudget: number;
  privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP';
  acceptableLevels: ('L1' | 'L2')[];
  filters?: {
    documentIds?: string[];
    tags?: string[];
    modalities?: string[];
    updatedAfter?: number;
  };
}
```

知识端输出以下证据字段：

```ts
export interface EvidenceUnit {
  semanticContractVersion: '1.0';
  evidenceId: string;
  evidenceGroupId: string;
  sourceDeviceId: string;
  sourceDocId: string;
  sourceChunkId?: string;
  parentEvidenceId?: string;
  level: 'L1' | 'L2';
  title: string;
  summary?: string;
  snippet?: string;
  relevance: number;
  coveredConcepts: string[];
  estimatedCoverageGain: number;
  byteCost: number;
  privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP';
  privacyCost: number;
  energyCost: number;
  hash: string;
  canEscalateTo: ('L1' | 'L2')[];
}
```

`sourceDeviceId` 由应用组合根向 Provider 注入。知识模块不得自行发现设备或依赖 DSK。

## 6. 内部流水线

```text
TaskRequest
→ QueryNormalizer
→ TaskFilterValidator
→ RetrievalEngine.search()
→ CandidateMerger
→ StableReranker
→ EvidenceUnitFactory
→ EvidenceUnit[]
```

### 6.1 QueryNormalizer

- 对 `queryText` 执行与现有关键词检索一致的归一化；
- 去除空白和重复概念；
- 不修改 `taskId`、预算或隐私级别；
- 空查询返回 `E_QUERY_INVALID`。

### 6.2 TaskFilterValidator

- 校验文档 ID、标签、模态和更新时间过滤器；
- 未知模态返回 `E_FILTER_INVALID`；
- `LOCAL_ONLY` 和 `PRIVATE_GROUP` 只用于候选过滤，不决定是否跨设备发送；
- 不允许通过过滤器访问文件 URI 或数据库字段名。

### 6.3 RetrievalEngine

统一抽象：

```ts
export interface RetrievalEngine {
  mode(): 'keyword' | 'vector' | 'hybrid';
  search(task: TaskRequest, candidateLimit: number): Promise<RetrievalCandidate[]>;
}
```

P4 要求：

- `KeywordRetrievalEngine` 是正式默认实现；
- 预计算向量或 Stub 实现只用于测试、消融实验和接口验证；
- 真实 ArkData 向量数据库与 MindSpore Lite 不作为 P4 完成条件；
- 未启用向量时，不得在 Profile 中声明 `vector` 或 `hybrid`；
- 不同 embedding 模型版本的分数不得直接混合。

### 6.4 CandidateMerger 与 StableReranker

- 合并多个检索引擎候选时按 `chunkId` 去重；
- 相关度分数归一化到 `[0, 1]`；
- 默认先按相关度降序，再按 `documentId`、`chunkId` 升序；
- 相同索引、任务和配置必须得到完全相同顺序；
- Candidate 层不得包含跨设备运行时指标。

## 7. EvidenceUnitFactory

`EvidenceUnitFactory` 是知识端 P4 的主要新增模块。

### 7.1 L1 证据

- 每个文档最多生成一个 L1；
- `evidenceId = ev-l1-<documentId>`；
- `evidenceGroupId = doc-<documentId>`；
- `sourceChunkId` 为空；
- `summary` 最长 300 个字符；
- `snippet` 为空；
- `canEscalateTo = [L2]`，仅当该文档存在可用 L2；
- `coveredConcepts` 从标题、标签、关键词和摘要中计算。

### 7.2 L2 证据

- 每个候选分块生成一个 L2；
- `evidenceId = ev-l2-<chunkId>`；
- `evidenceGroupId = doc-<documentId>`；
- `parentEvidenceId = ev-l1-<documentId>`；
- `snippet` 最长 1500 个字符；
- `summary` 为空；
- `canEscalateTo = []`；
- `coveredConcepts` 从标题、标签、关键词和片段中计算。

### 7.3 覆盖增益

```text
estimatedCoverageGain =
  当前证据覆盖的 requiredConcepts 数量 / max(1, requiredConcepts 总数)
```

P4 的覆盖增益是候选自身的静态估计。相对于已接收证据的真正边际覆盖增益由通信端 Scheduler 计算。

### 7.4 字节成本

`byteCost` 必须使用与协议一致的 UTF-8 计数器，对单条 `EvidenceUnit` JSON 对象序列化结果计数，不包含 `EVIDENCE` 外层消息、证据数组和会话字段。通信端根据实际编码后的 `EVIDENCE` 消息计算任务级证据预算。

知识端只提供候选成本，不执行任务级 `byteBudget` 裁剪。通信端负责选择发送集合和累计预算。

### 7.5 隐私与内容边界

P4 的文档隐私级别：

```text
LOCAL_ONLY
PRIVATE_GROUP
```

如果当前文档模型缺少隐私字段，需要新增字段并为历史数据使用 `PRIVATE_GROUP` 迁移默认值。

P4 使用确定性代理成本：

- `LOCAL_ONLY` 的 `privacyCost = 1.0`；
- `PRIVATE_GROUP` 的 `privacyCost = 0.2`；
- L1 的 `energyCost = 0.05`；
- L2 的 `energyCost = 0.10`。

这些值只用于 P4 调度和消融实验，不宣称为真实能耗测量。后续可由运行时估算器替换，但替换时必须提升共享契约小版本并重新固定基准。

禁止输出：

- 文件 URI 和真实文件路径；
- embedding 向量；
- ArkData Row、Predicates 或内部主键对象；
- 内部异常和堆栈；
- L3 完整原文、完整 PDF、原图或二进制文件。

## 8. KnowledgeProfile

Profile 必须从真实 Repository 统计生成，不允许使用手写演示值。

必填字段：

- `profileVersion`；
- `indexState`；
- `knowledgeDomains`；
- `documentCount`；
- `chunkCount`；
- `modalities`；
- `retrievalModes`；
- `supportedLevels`；
- `indexVersion`；
- `embeddingModelVersion`；
- `updatedAt`。

能力声明规则：

- 仅启用关键词检索时，`retrievalModes = ['keyword']`；
- 真实启用向量实现后，才能加入 `vector`；
- 同时启用并实际合并结果后，才能加入 `hybrid`；
- 未启用 embedding 时，`embeddingModelVersion = ''`；
- P4 的 `supportedLevels = ['L1', 'L2']`；
- 索引为空时为 `EMPTY`，构建中为 `BUILDING`，可查询时为 `READY`。

导入、删除、清空、增量更新和重启恢复后，Profile 必须与 Repository 一致，并更新相应版本和时间。

## 9. 存储与恢复

P4 继续使用 ArkData RDB：

- 文档元数据和分块必须持久化；
- 内容哈希用于跳过未变化文档；
- 删除文档必须同步删除其分块；
- 应用重启后从 RDB 恢复索引状态；
- 不要求重新导入内置测试文档；
- 同一索引版本中证据 ID 必须稳定；
- 索引变化后更新 `indexVersion` 和 `profileVersion`。

P4 不要求 ArkData KV 或向量数据库。

## 10. 错误模型

知识端只返回标准 `KnowledgeError`：

| 错误码 | 条件 | 可重试 |
|---|---|---|
| `E_QUERY_INVALID` | 查询为空或字段非法 | 否 |
| `E_FILTER_INVALID` | 过滤条件非法 | 否 |
| `E_INDEX_NOT_READY` | 索引正在构建 | 是 |
| `E_NO_EVIDENCE` | 没有匹配候选 | 否 |
| `E_RETRIEVAL_FAILED` | 检索执行失败 | 是 |
| `E_STORAGE_FAILED` | RDB 操作失败 | 是 |
| `E_EVIDENCE_INVALID` | 生成证据不符合契约 | 否 |
| `E_PROFILE_INVALID` | Profile 与仓库状态不一致 | 是 |

错误不得包含文件路径、数据库对象或内部堆栈。

## 11. 与通信端的集成规则

- 通信端传入完整 `TaskRequest`；
- 知识端返回候选 `EvidenceUnit[]`，不返回发送计划；
- 通信端不修改证据正文和哈希；
- 通信端可以按 TSF 再次调用 `searchEvidence()`，但同一任务和索引必须返回稳定 ID；
- TSF 由通信端独立计算，不作为 `SemanticKnowledgeProvider` 的输入；
- 重试不得重复导入或重建索引；
- Profile 和 Evidence 使用同一 `indexVersion` 语义；
- 契约版本不匹配时，集成必须在边界失败，不允许静默降级字段。

## 12. 测试与验收

知识端使用与通信端相同的至少 20 条固定查询和必需概念标注。

硬性验收：

- 相同索引、任务和配置产生确定性候选顺序；
- L1 为文档级，L2 为分块级，并正确关联；
- 标签、模态、更新时间、文档 ID 和隐私过滤有效；
- `evidenceId` 唯一且稳定；
- `byteCost` 与实际序列化 UTF-8 字节一致；
- `coveredConcepts` 和 `estimatedCoverageGain` 可由固定数据复现；
- 无匹配、空索引、构建中和数据库异常返回标准错误；
- 应用重启后从 RDB 恢复；
- 旧 `LocalKnowledgeGateway`、Payload Validator 和本地基准测试继续通过；
- 新 Provider 可被 Fake Provider 等价替换。

测试层次：

1. QueryNormalizer、过滤器和 StableReranker 单元测试；
2. EvidenceUnitFactory L1/L2 契约测试；
3. Profile 与 Repository 一致性测试；
4. RDB 导入、删除、清空和重启恢复测试；
5. 固定查询集准确率、顺序稳定性和耗时基准；
6. 与通信端共享契约夹具的集成测试。

## 13. 里程碑

| 阶段 | 知识端交付物 | 依赖 |
|---|---|---|
| P4.0 | 共享契约、隐私字段、固定测试夹具 | 项目负责人确认 |
| P4.1 | `SemanticKnowledgeProvider` 和 RetrievalEngine 抽象 | 现有 Gateway/Engine |
| P4.2 | EvidenceUnitFactory、Profile 规则和单元测试 | 固定查询集 |
| P4.3 | RDB 恢复、稳定 ID、通信端集成 | 通信端契约 1.0 |
| P4.4 | 检索基准、覆盖标注和答辩数据 | 双设备测试语料 |
| 后续 | ArkData 向量数据库和 MindSpore Lite | API 18+ 与模型 |

## 14. P4 明确不做

- DSK、Network Kit 或后台长时任务；
- 设备路由和运行时评分；
- MEU 发送调度；
- TSF 判定；
- ArkData 真实向量数据库；
- MindSpore Lite 推理；
- L3、完整文件和原始二进制输出；
- 新增 OCR 引擎或新增文件格式解析器；
- 大模型答案生成。

息屏场景中，知识端只需保持接口幂等、证据 ID 稳定和 RDB 可恢复；后台生命周期与会话恢复完全由通信端负责。
