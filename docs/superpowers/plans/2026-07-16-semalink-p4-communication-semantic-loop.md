# SemaLink P4 Communication Semantic Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在现有 Distributed Service Kit 链路上实现两设备语义通信闭环：本地/远端路由、EvidenceUnit 边际效用调度、L1→TSF→L2 两轮任务和可测量完成状态。

**Architecture:** 保留现有 SessionManager 的连接生命周期和旧 QUERY/RESULT 兼容路径，在其上增加语义协议派发和独立任务状态。共享语义契约放在 contracts/semantic；通信端只消费 SemanticKnowledgeProvider，响应端缓存候选证据，由通信侧 Scheduler 选择每一轮要发送的证据。

**Tech Stack:** HarmonyOS NEXT API 24、ArkTS、@kit.DistributedServiceKit、@ohos/hypium、Hvigor。

---

## 实施前提

- 当前工作树已有未提交的通信和知识修改，执行时只修改本计划列出的文件，不使用 git reset 或覆盖用户变更。
- P4 只支持本机和一个已连接远端设备；不新增 Network Kit、Socket、真实向量数据库、MindSpore Lite 或后台长时任务。
- P5 息屏互联不在本计划内。P4 只记录后台中断并返回 E_BACKGROUND_INTERRUPTED；P5 需要单独计划。
- 知识端计划必须先完成共享契约和 SemanticKnowledgeProvider 的最小接口，通信端在此之前使用 Fake Provider。

## 验证命令

~~~powershell
$node = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
~~~

预期：退出码为 0，Hypium 无失败用例，构建输出包含 BUILD SUCCESSFUL。真机集成另需两台 API 24 设备。

## 文件映射

| 文件 | 职责 |
|---|---|
| entry/src/main/ets/contracts/semantic/SemanticModels.ets | TaskRequest、EvidenceUnit、TSF、Profile 广播和任务状态 |
| entry/src/main/ets/contracts/semantic/SemanticKnowledgeProvider.ets | 通信端唯一调用的知识 Provider 接口 |
| entry/src/main/ets/communication/DeviceDirectory.ets | 本机/远端 Profile 与运行时指标 |
| entry/src/main/ets/communication/DeviceSemanticRouter.ets | 硬过滤、评分和候选排序 |
| entry/src/main/ets/communication/EvidenceUtilityScheduler.ets | MEU 计算和两轮发送计划 |
| entry/src/main/ets/communication/TaskSufficiencyEvaluator.ets | 覆盖率、置信度和 TSF |
| entry/src/main/ets/communication/ProgressiveQueryCoordinator.ets | P4 任务状态和本地/远端编排 |
| entry/src/main/ets/protocol/ProtocolModels.ets | 旧协议与 P4 消息类型共存 |
| entry/src/main/ets/protocol/ProtocolCodec.ets | JSON 字段、版本、载荷和大小校验 |
| entry/src/main/ets/communication/SessionManager.ets | 连接状态、通用 envelope 发送和语义消息派发 |
| entry/src/main/ets/model/AppModels.ets | UI 任务状态和指标 |
| entry/src/main/ets/state/AppStateStore.ets | 新快照字段的更新与复制 |
| entry/src/main/ets/application/QueryCoordinator.ets | 旧 API 兼容和 P4 委托 |
| entry/src/main/ets/runtime/AppRuntime.ets | 组合 Provider、目录和协调器 |
| entry/src/test/support/FakeSemanticKnowledgeProvider.ets | 通信端独立测试 Provider |
| entry/src/test/support/SemanticFixtures.ets | 20 条查询、Profile、EvidenceUnit 和期望结果 |
| entry/src/test/SemanticModels.test.ets | 共享契约校验 |
| entry/src/test/DeviceSemanticRouter.test.ets | 路由单元测试 |
| entry/src/test/EvidenceUtilityScheduler.test.ets | MEU 和预算测试 |
| entry/src/test/TaskSufficiencyEvaluator.test.ets | TSF 测试 |
| entry/src/test/ProgressiveQueryCoordinator.test.ets | 两轮本地/Fake Provider 闭环 |
| entry/src/test/List.test.ets | 注册新增测试套件 |

## Task 1: 共享契约和固定夹具

**Files:**
- Create: entry/src/main/ets/contracts/semantic/SemanticModels.ets
- Create: entry/src/main/ets/contracts/semantic/SemanticKnowledgeProvider.ets
- Create: entry/src/test/support/SemanticFixtures.ets
- Create: entry/src/test/SemanticModels.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。验证 TaskRequest 默认阈值 0.80，EvidenceUnit 的 L1/L2 通过 evidenceGroupId 和 parentEvidenceId 关联，TSF 只接受 ENOUGH/NEED_MORE/ABORT，空 taskId 和负预算被拒绝。
- [ ] Step 2: 注册 semanticModelsTest，运行 Hvigor test；预期因类型和校验函数不存在而失败。
- [ ] Step 3: 实现 SemanticContractVersion 1.0、PayloadLevel、PrivacyLevel、TaskPhase、TaskRequest、EvidenceUnit、TaskSufficiencyFeedback、DeviceRuntimeSnapshot、DeviceProfileAdvertisement 和 validateTaskRequest。Provider 接口只暴露 getProfile 和 searchEvidence。
- [ ] Step 4: 运行 Hvigor test，预期新增和旧测试全通过。提交：
~~~powershell
git add entry/src/main/ets/contracts/semantic entry/src/test/support/SemanticFixtures.ets entry/src/test/SemanticModels.test.ets entry/src/test/List.test.ets
git commit -m "feat: add semantic task contracts"
~~~

## Task 2: P4 协议 Codec，保留旧协议

**Files:**
- Modify: entry/src/main/ets/protocol/ProtocolModels.ets
- Modify: entry/src/main/ets/protocol/ProtocolCodec.ets
- Test: entry/src/test/ProtocolCodec.test.ets

- [ ] Step 1: 写失败测试。覆盖 PROFILE、TASK、TASK_ACK、EVIDENCE、TSF、CANCEL round-trip；错误语义版本、错误轮次、缺 taskId、重复 evidence ID、L3 和超消息上限均拒绝；旧 QUERY 测试保留。
- [ ] Step 2: 运行 Hvigor test；预期新类型和工厂函数不存在。
- [ ] Step 3: 在旧 MessageType 后追加 P4 类型和对应 payload。Codec 同时接受 v1.0 旧 envelope 和 v2.0 语义 envelope；P4 EVIDENCE 做完整 UTF-8 消息大小检查。新增 createProfile、createTask、createTaskAck、createEvidence、createTsf、createCancel，不删除旧工厂。
- [ ] Step 4: 运行 Hvigor test，预期旧协议和 P4 协议全通过。提交：
~~~powershell
git add entry/src/main/ets/protocol/ProtocolModels.ets entry/src/main/ets/protocol/ProtocolCodec.ets entry/src/test/ProtocolCodec.test.ets
git commit -m "feat: add progressive semantic protocol messages"
~~~

## Task 3: 设备目录和语义路由

**Files:**
- Create: entry/src/main/ets/communication/DeviceDirectory.ets
- Create: entry/src/main/ets/communication/DeviceSemanticRouter.ets
- Create: entry/src/test/DeviceSemanticRouter.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。本机/远端域匹配选择正确设备；LOCAL_ONLY 排除远端；画像过期、非 READY、过滤不满足时排除；同分稳定选择本机；结果包含分项和排除原因。
- [ ] Step 2: 运行 Hvigor test；预期目录和 Router 不存在。
- [ ] Step 3: DeviceDirectory 提供 setLocal、setRemote、clearRemote、snapshot，远端 Profile TTL 固定 5 分钟。Router 使用 0.45 semanticMatch + 0.20 filterMatch + 0.10 freshness - 0.10 normalizedRtt - 0.05 load - 0.10 privacyRisk。无 embedding 时 semanticMatch 是 requiredConcepts 与 knowledgeDomains.tag 的加权交集；硬过滤先执行，LOCAL_ONLY 对远端为负无穷，同分按本机再按 deviceId 排序。
- [ ] Step 4: 运行 Hvigor test，预期路由测试全通过。提交：
~~~powershell
git add entry/src/main/ets/communication/DeviceDirectory.ets entry/src/main/ets/communication/DeviceSemanticRouter.ets entry/src/test/DeviceSemanticRouter.test.ets entry/src/test/List.test.ets
git commit -m "feat: add profile-based device semantic routing"
~~~

## Task 4: MEU 调度和规则型 TSF

**Files:**
- Create: entry/src/main/ets/communication/EvidenceUtilityScheduler.ets
- Create: entry/src/main/ets/communication/TaskSufficiencyEvaluator.ets
- Create: entry/src/test/EvidenceUtilityScheduler.test.ets
- Create: entry/src/test/TaskSufficiencyEvaluator.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。首轮只选 L1；第二轮只选覆盖 missingConcepts 的 L2；不重复 evidence；预算不足停止；同分按 evidenceId 排序；TSF 在覆盖率/置信度都 0.80 时 ENOUGH，第一轮不足 NEED_MORE，第二轮不足 ABORT。
- [ ] Step 2: 运行 Hvigor test；预期 Scheduler/Evaluator 不存在。
- [ ] Step 3: 实现 utility = 0.30 relevance + 0.25 coverageGain + 0.15 diversityGain - 0.10 normalizedBytes - 0.08 normalizedLatency - 0.08 privacyCost - 0.04 energyCost，MEU = utility / (byteCost + 128)。代理成本固定为 LOCAL_ONLY 1.0、PRIVATE_GROUP 0.2、L1 energy 0.05、L2 energy 0.10。Evaluator 使用 coverage = coveredConceptWeight / requiredConceptWeight，confidence = 0.60 averageRelevance + 0.40 coverage，diversity = min(1, uniqueDocCount / max(1, acceptedCount))。
- [ ] Step 4: 运行 Hvigor test，预期两个新增套件全通过。提交：
~~~powershell
git add entry/src/main/ets/communication/EvidenceUtilityScheduler.ets entry/src/main/ets/communication/TaskSufficiencyEvaluator.ets entry/src/test/EvidenceUtilityScheduler.test.ets entry/src/test/TaskSufficiencyEvaluator.test.ets entry/src/test/List.test.ets
git commit -m "feat: add evidence scheduling and task sufficiency"
~~~

## Task 5: SessionManager 语义消息派发

**Files:**
- Modify: entry/src/main/ets/communication/SessionManager.ets
- Modify: entry/src/test/SessionManager.test.ets

- [ ] Step 1: 写失败测试。sendEnvelope 计入字节；P4 消息交给独立 ProtocolObserver；重复 messageId 只派发一次；旧 QUERY 状态行为不变；destroy 后不派发。
- [ ] Step 2: 运行 Hvigor test；预期 ProtocolObserver 和 sendEnvelope 不存在。
- [ ] Step 3: 增加 setProtocolObserver 和 sendEnvelope；onMessage 对新类型调用 ProtocolObserver，对旧类型继续现有 switch；增加有界 handledMessageIds，并在任务结束时按 taskId 清理。不要把 ConnectionState 改成 TaskPhase。
- [ ] Step 4: 运行 Hvigor test，预期旧/新增 SessionManager 测试全通过。提交：
~~~powershell
git add entry/src/main/ets/communication/SessionManager.ets entry/src/test/SessionManager.test.ets
git commit -m "feat: dispatch semantic envelopes through sessions"
~~~

## Task 6: ProgressiveQueryCoordinator 本地闭环

**Files:**
- Create: entry/src/main/ets/communication/ProgressiveQueryCoordinator.ets
- Modify: entry/src/main/ets/model/AppModels.ets
- Modify: entry/src/main/ets/state/AppStateStore.ets
- Create: entry/src/test/ProgressiveQueryCoordinator.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。Fake Provider 覆盖本机路由、L1→NEED_MORE→L2→ENOUGH、L1 直接 ENOUGH、第二轮 ABORT、预算不足和重复提交 E_BUSY。
- [ ] Step 2: 运行 Hvigor test；预期协调器和任务字段不存在。
- [ ] Step 3: 构造函数注入 SessionManager、AppStateStore、SemanticKnowledgeProvider、DeviceDirectory、Router、Scheduler、Evaluator 和 Clock。公开 submit(task)、cancel(taskId)、onProtocolEnvelope(envelope)。本机胜出时 Provider→Scheduler→Evaluator；任务完成/ABORT 清理候选和计时器。
- [ ] Step 4: 运行 Hvigor test，预期本地闭环全通过。提交：
~~~powershell
git add entry/src/main/ets/communication/ProgressiveQueryCoordinator.ets entry/src/main/ets/model/AppModels.ets entry/src/main/ets/state/AppStateStore.ets entry/src/test/ProgressiveQueryCoordinator.test.ets entry/src/test/List.test.ets
git commit -m "feat: orchestrate local progressive semantic tasks"
~~~

## Task 7: 远端 PROFILE、TASK、EVIDENCE、TSF

**Files:**
- Modify: entry/src/main/ets/communication/ProgressiveQueryCoordinator.ets
- Modify: entry/src/main/ets/application/QueryCoordinator.ets
- Modify: entry/src/main/ets/runtime/AppRuntime.ets
- Modify: entry/src/test/ProgressiveQueryCoordinator.test.ets
- Modify: entry/src/test/QueryCoordinator.test.ets

- [ ] Step 1: 写失败测试。Fake Transport 模拟 Profile 交换、远端 TASK、TASK_ACK、L1、NEED_MORE、L2、ENOUGH，并覆盖乱序 round、旧 taskId、重复 evidence、远端错误和超时。
- [ ] Step 2: 运行 Hvigor test；预期 P4 envelope 尚未被协调器派发。
- [ ] Step 3: 响应端收到 TASK 后调用 Provider 一次并按 taskId 缓存候选，发送 TASK_ACK 和 L1；发起端对 EVIDENCE 执行 Evaluator，NEED_MORE 转发给响应端，响应端从缓存选择 L2。QueryCoordinator.submit(question) 保留；新增 submitSemanticTask(task) 委托 P4。连接后用 PROFILE 交换画像，TTL 过期重新交换。P4 本机 source ID 使用稳定别名 local-device，远端使用可信设备 network ID。
- [ ] Step 4: 运行 Hvigor test，预期旧 QueryCoordinator 和新远端闭环全通过。提交：
~~~powershell
git add entry/src/main/ets/communication/ProgressiveQueryCoordinator.ets entry/src/main/ets/application/QueryCoordinator.ets entry/src/main/ets/runtime/AppRuntime.ets entry/src/test/ProgressiveQueryCoordinator.test.ets entry/src/test/QueryCoordinator.test.ets
git commit -m "feat: integrate remote progressive evidence flow"
~~~

## Task 8: Fake Provider 和 20 条固定查询

**Files:**
- Create: entry/src/test/support/FakeSemanticKnowledgeProvider.ets
- Modify: entry/src/test/support/SemanticFixtures.ets
- Modify: entry/src/test/ProgressiveQueryCoordinator.test.ets

- [ ] Step 1: 写 fixture 测试。固定 20 条任务：8 条本机、8 条远端、2 条 L1 足够、2 条 L2 后不足；每条包含 requiredConcepts、期望设备、终态和 evidence 成本。
- [ ] Step 2: 运行 Hvigor test；预期 fixture 或 Fake Provider 不完整。
- [ ] Step 3: Fake Provider 按 taskId 返回固定 Profile 和 EvidenceUnit[]，记录调用次数和 indexVersion，不使用随机数。本机 Profile 使用操作系统/数据库，远端使用网络/软件测试。
- [ ] Step 4: 运行 Hvigor test，预期 20 条任务结果稳定。提交：
~~~powershell
git add entry/src/test/support/FakeSemanticKnowledgeProvider.ets entry/src/test/support/SemanticFixtures.ets entry/src/test/ProgressiveQueryCoordinator.test.ets
git commit -m "test: add deterministic semantic task fixtures"
~~~

## Task 9: 真实 Provider 和页面状态

**Files:**
- Modify: entry/src/main/ets/application/KnowledgeApplicationService.ets
- Modify: entry/src/main/ets/application/KnowledgeCompositionRoot.ets
- Modify: entry/src/main/ets/runtime/AppRuntime.ets
- Modify: entry/src/main/ets/pages/Index.ets
- Modify: entry/src/ohosTest/ets/test/IndexPage.test.ets

- [ ] Step 1: 写失败测试。Runtime 同时暴露旧 queryLocalKnowledge 和 semanticProvider；页面显示 task phase、TSF、选中设备和 evidence bytes；旧查询显示保持不变。
- [ ] Step 2: 运行 Hvigor test 和 assembleHap；预期 P4 状态字段不存在。
- [ ] Step 3: KnowledgeApplicationService 实现 SemanticKnowledgeProvider；AppRuntime 将本地 Profile 写入 DeviceDirectory 并注入 P4 coordinator；Index 只显示状态和指标，不读取 Repository 或证据算法。
- [ ] Step 4: 运行 Hvigor test 和 assembleHap，预期旧页面和 P4 状态测试通过。提交：
~~~powershell
git add entry/src/main/ets/application/KnowledgeApplicationService.ets entry/src/main/ets/application/KnowledgeCompositionRoot.ets entry/src/main/ets/runtime/AppRuntime.ets entry/src/main/ets/pages/Index.ets entry/src/ohosTest/ets/test/IndexPage.test.ets
git commit -m "feat: expose progressive semantic task state"
~~~

## Task 10: 指标、错误矩阵和双设备验收

**Files:**
- Modify: entry/src/main/ets/model/AppModels.ets
- Modify: entry/src/main/ets/state/AppStateStore.ets
- Modify: entry/src/main/ets/common/AppError.ets
- Modify: entry/src/test/ProgressiveQueryCoordinator.test.ets
- Modify: entry/src/ohosTest/ets/test/CollaborationAbility.test.ets
- Create: docs/testing/p4-semantic-loop-acceptance.md

- [ ] Step 1: 写指标/错误失败测试。覆盖路由分项、首结果延迟、完成延迟、总协议字节、EVIDENCE 预算字节、轮次、TSF、隐私级别和 INSUFFICIENT_EVIDENCE、E_BACKGROUND_INTERRUPTED、E_PROFILE_STALE、E_SEMANTIC_PROTOCOL_INVALID。
- [ ] Step 2: 运行 Hvigor test 和 assembleHap；预期新字段/错误码断言失败。
- [ ] Step 3: 记录 P50/P95 原始样本；证据预算只计算 EVIDENCE 编码字节，总协议字节单独累计。验收文档固定两设备、20 条查询、L1 足够、L2 足够和证据不足场景。
- [ ] Step 4: 运行 Hvigor test 和 assembleHap，预期退出码 0、无失败用例、BUILD SUCCESSFUL。提交：
~~~powershell
git add entry/src/main/ets/model/AppModels.ets entry/src/main/ets/state/AppStateStore.ets entry/src/main/ets/common/AppError.ets entry/src/test/ProgressiveQueryCoordinator.test.ets entry/src/ohosTest/ets/test/CollaborationAbility.test.ets docs/testing/p4-semantic-loop-acceptance.md
git commit -m "test: define P4 semantic loop acceptance"
~~~
- [ ] Step 5: 双真机执行本机胜出、远端两轮、L1 提前结束、预算不足、断线和重复消息，并记录真实 P50/P95。

## 完成定义

- 20 条固定查询的设备 Top-1 路由准确率不低于 90%；
- 远端正常场景完成 L1 → NEED_MORE → L2 → ENOUGH；
- L1 足够时不发送 L2；
- 第二轮仍不足时稳定返回 ABORT/INSUFFICIENT_EVIDENCE；
- EVIDENCE 字节不超过任务证据预算；
- P4 不发送 L3、文件 URI、embedding 或完整原文；
- 旧 QUERY/RESULT 测试和页面行为保持通过；
- P5 息屏后台能力不在本计划完成定义内。
