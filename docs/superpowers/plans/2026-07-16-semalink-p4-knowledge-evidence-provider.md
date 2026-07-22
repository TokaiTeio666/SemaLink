# SemaLink P4 Knowledge Evidence Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在现有文档导入、ArkData RDB 和关键词检索基础上，提供稳定的 KnowledgeProfile 与 EvidenceUnit[]，供通信端完成 P4 路由、调度和 TSF。

**Architecture:** 保留 LocalKnowledgeGateway 作为旧 L1/L2 JSON 兼容接口，新增 SemanticKnowledgeProvider 作为通信端唯一的 P4 知识接口。检索端内部通过 RetrievalEngine 抽象接入当前关键词引擎，使用 EvidenceUnitFactory 将候选转换为文档级 L1 和分块级 L2；全局任务预算和发送顺序留给通信端。

**Tech Stack:** HarmonyOS NEXT API 24、ArkTS、@kit.ArkData relationalStore、现有 DocumentChunker/KeywordRetrievalEngine/RDB、@ohos/hypium、Hvigor。

---

## 实施前提

- 当前工作树包含用户未提交的知识修改，执行时只修改本计划列出的文件。
- P4 默认正式检索模式仍是关键词；预计算向量或 Stub 只作为可替换接口和测试实现，不接入真实 MindSpore Lite 或 ArkData 向量数据库。
- 共享 contracts/semantic 契约由项目负责人先冻结；知识计划不复制第二套类型。
- 历史 RDB 版本为 1。新增隐私字段时必须迁移旧表，历史文档默认 PRIVATE_GROUP。

## 验证命令

~~~powershell
$node = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
~~~

预期：退出码 0、无失败用例、构建输出包含 BUILD SUCCESSFUL。真实 RDB 初始化/恢复另运行 entry@ohosTest 并在 API 24 设备验证。

## 文件映射

| 文件 | 职责 |
|---|---|
| entry/src/main/ets/contracts/semantic/SemanticKnowledgeProvider.ets | P4 Provider 接口，来自通信计划的共享契约 |
| entry/src/main/ets/contracts/semantic/SemanticModels.ets | TaskRequest、EvidenceUnit 等共享类型 |
| entry/src/main/ets/knowledge/model/KnowledgeDocument.ets | 文档隐私级别 |
| entry/src/main/ets/knowledge/storage/KnowledgeDatabase.ets | RDB schema 版本和 privacy_level 迁移 |
| entry/src/main/ets/knowledge/storage/DocumentRepository.ets | Repository 文档读写边界 |
| entry/src/main/ets/knowledge/storage/RdbDocumentRepository.ets | privacy_level SQL 读写和默认值 |
| entry/src/main/ets/knowledge/import/RawFileDocumentImporter.ets | 内置文档默认隐私 |
| entry/src/main/ets/knowledge/import/UserDocumentImporter.ets | 用户文档默认隐私 |
| entry/src/main/ets/knowledge/retrieval/RetrievalEngine.ets | P4 检索抽象 |
| entry/src/main/ets/knowledge/retrieval/KeywordRetrievalEngine.ets | 关键词适配和回归 |
| entry/src/main/ets/knowledge/model/RetrievalCandidate.ets | 候选匹配信息 |
| entry/src/main/ets/knowledge/evidence/EvidenceUnitFactory.ets | L1/L2 EvidenceUnit、覆盖增益和成本 |
| entry/src/main/ets/knowledge/service/ArkDataLocalKnowledgeService.ets | searchEvidence 和 Profile |
| entry/src/main/ets/application/KnowledgeApplicationService.ets | 旧 Gateway 与新 Provider |
| entry/src/main/ets/application/KnowledgeCompositionRoot.ets | 组合检索、Factory 和 Provider |
| entry/src/test/KnowledgeDocumentPrivacy.test.ets | 隐私模型 |
| entry/src/test/KnowledgeDatabaseMigration.test.ets | RDB schema 迁移 |
| entry/src/test/EvidenceUnitFactory.test.ets | L1/L2 契约和成本 |
| entry/src/test/SemanticKnowledgeProvider.test.ets | Provider 查询和 Profile |
| entry/src/test/KnowledgeCoreLogic.test.ets | 关键词回归和隐私 fixture |
| entry/src/test/UserDocumentStability.test.ets | 用户文档稳定性 |
| entry/src/test/benchmark/InMemoryBenchmarkRepository.ets | 内存 Repository 字段保存 |
| entry/src/test/benchmark/LocalRetrievalBenchmarkDocuments.ets | 基准 privacy 字段 |
| entry/src/test/benchmark/LocalRetrievalBenchmarkRunner.ets | 基准兼容 |
| entry/src/test/List.test.ets | 注册新增测试 |

## Task 1: 文档隐私模型和所有构造点

**Files:**
- Modify: entry/src/main/ets/knowledge/model/KnowledgeDocument.ets
- Modify: entry/src/test/KnowledgeCoreLogic.test.ets
- Modify: entry/src/test/UserDocumentStability.test.ets
- Modify: entry/src/test/benchmark/LocalRetrievalBenchmarkDocuments.ets
- Modify: entry/src/test/benchmark/LocalRetrievalBenchmarkRunner.ets
- Create: entry/src/test/KnowledgeDocumentPrivacy.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。断言 privacyLevel 只接受 LOCAL_ONLY/PRIVATE_GROUP；内置、用户和 benchmark 文档默认 PRIVATE_GROUP；LOCAL_ONLY 在候选中保留。
- [ ] Step 2: 运行 Hvigor test；预期因 privacyLevel 缺失而失败。用 rg -n "KnowledgeDocument =|document: KnowledgeDocument" entry/src/test 定位所有构造点。
- [ ] Step 3: 在 KnowledgeDocument 增加必填 PrivacyLevel 字段，更新所有导入和 benchmark fixture。默认 PRIVATE_GROUP，需要隐私测试的 fixture 显式设置 LOCAL_ONLY。
- [ ] Step 4: 运行 Hvigor test，预期旧知识测试和隐私测试全通过。提交：
~~~powershell
git add entry/src/main/ets/knowledge/model/KnowledgeDocument.ets entry/src/test/KnowledgeDocumentPrivacy.test.ets entry/src/test/KnowledgeCoreLogic.test.ets entry/src/test/UserDocumentStability.test.ets entry/src/test/benchmark/LocalRetrievalBenchmarkDocuments.ets entry/src/test/benchmark/LocalRetrievalBenchmarkRunner.ets entry/src/test/List.test.ets
git commit -m "feat: add document privacy levels"
~~~

## Task 2: RDB schema 迁移和隐私持久化

**Files:**
- Modify: entry/src/main/ets/knowledge/storage/KnowledgeDatabase.ets
- Modify: entry/src/main/ets/knowledge/storage/RdbDocumentRepository.ets
- Create: entry/src/test/KnowledgeDatabaseMigration.test.ets
- Modify: entry/src/ohosTest/ets/test/KnowledgeDatabase.test.ets

- [ ] Step 1: 写失败测试。旧 documents 表没有 privacy_level 时初始化自动增加该列，旧记录读取为 PRIVATE_GROUP，新记录可读写 LOCAL_ONLY，迁移重复执行不报错。
- [ ] Step 2: 运行 Hvigor test；设备可用时运行 entry@ohosTest 数据库测试。预期旧 schema 和 Repository 类型不匹配。
- [ ] Step 3: CREATE_DOCUMENTS 增加 privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP'，数据库版本设为 2。初始化后查询 PRAGMA table_info(documents)，若缺失则执行 ALTER TABLE documents ADD COLUMN privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP'。Repository 保存/读取该字段并拒绝未知值；迁移失败统一返回 E_STORAGE_FAILED。
- [ ] Step 4: 运行本地测试、设备数据库测试和 HAP 构建，预期迁移、恢复和导入测试通过。提交：
~~~powershell
git add entry/src/main/ets/knowledge/storage/KnowledgeDatabase.ets entry/src/main/ets/knowledge/storage/RdbDocumentRepository.ets entry/src/test/KnowledgeDatabaseMigration.test.ets entry/src/ohosTest/ets/test/KnowledgeDatabase.test.ets
git commit -m "feat: migrate knowledge RDB privacy metadata"
~~~

## Task 3: 导入器和内存 Repository

**Files:**
- Modify: entry/src/main/ets/knowledge/import/RawFileDocumentImporter.ets
- Modify: entry/src/main/ets/knowledge/import/UserDocumentImporter.ets
- Modify: entry/src/test/benchmark/InMemoryBenchmarkRepository.ets
- Modify: entry/src/test/UserDocumentImportLogic.test.ets
- Modify: entry/src/test/UserDocumentStability.test.ets

- [ ] Step 1: 写失败测试。内置导入、用户导入和内存 Repository 保存后的文档都断言 privacyLevel，错误消息不包含 URI。
- [ ] Step 2: 运行 Hvigor test；预期导入器或内存 Repository 丢失 privacy 字段。
- [ ] Step 3: 两个导入器设置 PRIVATE_GROUP；内存 Repository 保存完整对象；错误路径继续只暴露标准错误。
- [ ] Step 4: 运行 Hvigor test 和本地 retrieval benchmark，预期导入稳定性、checksum 去重和检索无回归。提交：
~~~powershell
git add entry/src/main/ets/knowledge/import/RawFileDocumentImporter.ets entry/src/main/ets/knowledge/import/UserDocumentImporter.ets entry/src/test/benchmark/InMemoryBenchmarkRepository.ets entry/src/test/UserDocumentImportLogic.test.ets entry/src/test/UserDocumentStability.test.ets
git commit -m "test: preserve privacy through document ingestion"
~~~

## Task 4: RetrievalEngine 抽象和关键词回归

**Files:**
- Create: entry/src/main/ets/knowledge/retrieval/RetrievalEngine.ets
- Modify: entry/src/main/ets/knowledge/retrieval/KeywordRetrievalEngine.ets
- Modify: entry/src/main/ets/knowledge/model/RetrievalCandidate.ets
- Create: entry/src/test/RetrievalEngine.test.ets
- Modify: entry/src/test/KnowledgeCoreLogic.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。KeywordRetrievalEngine.mode() 返回 keyword；新 KnowledgeRetrievalRequest 返回稳定候选；旧 LocalKnowledgeQuery 搜索结果不变；隐私过滤有效。
- [ ] Step 2: 运行 Hvigor test；预期 RetrievalEngine 和新 request 类型不存在。
- [ ] Step 3: 新增 KnowledgeRetrievalRequest 和 RetrievalEngine 接口。KeywordRetrievalEngine 实现新接口，旧 search(request: LocalKnowledgeQuery, documents: KnowledgeDocument[], chunks: DocumentChunk[]) 保留为转换入口。候选保留匹配词来源，不复制整篇文本。
- [ ] Step 4: 运行 Hvigor test 和 scripts/run-local-retrieval-benchmark.ps1 -Label latest，预期准确率、无答案拒绝率和稳定排序不回归。提交：
~~~powershell
git add entry/src/main/ets/knowledge/retrieval/RetrievalEngine.ets entry/src/main/ets/knowledge/retrieval/KeywordRetrievalEngine.ets entry/src/main/ets/knowledge/model/RetrievalCandidate.ets entry/src/test/RetrievalEngine.test.ets entry/src/test/KnowledgeCoreLogic.test.ets entry/src/test/List.test.ets
git commit -m "feat: abstract local retrieval engines"
~~~

## Task 5: EvidenceUnitFactory

**Files:**
- Create: entry/src/main/ets/knowledge/evidence/EvidenceUnitFactory.ets
- Create: entry/src/test/EvidenceUnitFactory.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。每文档最多一个 L1；每 chunk 一个 L2；ID 稳定；L2 parentEvidenceId 指向 L1；L1 summary ≤300；L2 snippet ≤1500；coveredConcepts、隐私、升级关系、hash 和 byteCost 正确。
- [ ] Step 2: 运行 Hvigor test；预期 Factory 不存在。
- [ ] Step 3: 实现 build(candidates, task, sourceDeviceId)。L1 ID 为 ev-l1-文档 ID，L2 ID 为 ev-l2-chunk ID，group 为 doc-文档 ID。coveredConcepts 是 requiredConcepts 与标题、标签、关键词、摘要/片段的归一化交集；coverageGain 是覆盖概念数除以任务概念数。hash 使用现有稳定哈希规则对 level、sourceDocId、sourceChunkId 和实际摘要/片段内容组合计算，不包含 URI。privacyCost 固定 LOCAL_ONLY 1.0、PRIVATE_GROUP 0.2；energyCost 固定 L1 0.05、L2 0.10；byteCost 使用 Utf8Sizer 对单条 EvidenceUnit JSON 计数。
- [ ] Step 4: 运行 Hvigor test，预期 Factory、旧 Payload Builder 和 UTF-8 测试通过。提交：
~~~powershell
git add entry/src/main/ets/knowledge/evidence/EvidenceUnitFactory.ets entry/src/test/EvidenceUnitFactory.test.ets entry/src/test/List.test.ets
git commit -m "feat: build structured evidence units"
~~~

## Task 6: ArkDataLocalKnowledgeService 实现 Provider

**Files:**
- Modify: entry/src/main/ets/knowledge/service/ArkDataLocalKnowledgeService.ets
- Modify: entry/src/main/ets/application/KnowledgeApplicationService.ets
- Modify: entry/src/main/ets/application/KnowledgeCompositionRoot.ets
- Create: entry/src/test/SemanticKnowledgeProvider.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: 写失败测试。Provider 返回真实 Profile；READY/BUILDING/ERROR/EMPTY 状态有确定结果；相同 task/index 返回稳定 ID；不执行全局 PayloadBudgetController 裁剪。
- [ ] Step 2: 运行 Hvigor test；预期没有 searchEvidence 和 Factory 注入。
- [ ] Step 3: service 注入 RetrievalEngine、EvidenceUnitFactory、sourceDeviceId，实现 validate task、读取 metadata、检查状态、读取 docs/chunks、检索并 build EvidenceUnit。保留旧 query 和 Validator。KnowledgeApplicationService 同时实现旧 Gateway 与新 Provider；CompositionRoot 共享一个 Repository 和 service。
- [ ] Step 4: 运行 Hvigor test、assembleHap 和本地 retrieval benchmark，预期 Provider、旧 Gateway 和基准通过。提交：
~~~powershell
git add entry/src/main/ets/knowledge/service/ArkDataLocalKnowledgeService.ets entry/src/main/ets/application/KnowledgeApplicationService.ets entry/src/main/ets/application/KnowledgeCompositionRoot.ets entry/src/test/SemanticKnowledgeProvider.test.ets entry/src/test/List.test.ets
git commit -m "feat: expose semantic knowledge provider"
~~~

## Task 7: Profile、Runtime 组合和真实 RDB 验证

**Files:**
- Modify: entry/src/main/ets/knowledge/profile/KnowledgeProfileBuilder.ets
- Modify: entry/src/main/ets/runtime/AppRuntime.ets
- Modify: entry/src/ohosTest/ets/test/KnowledgeDatabase.test.ets
- Modify: entry/src/ohosTest/ets/test/DeviceLocalRetrievalBenchmark.test.ets

- [ ] Step 1: 写失败测试。Profile 与 RDB 统计一致，只声明 keyword，embeddingModelVersion 为空，导入/清空更新 indexVersion/profileVersion；Runtime 可返回旧 Gateway 和新 Provider。
- [ ] Step 2: 运行 HAP test 和设备 ohosTest；预期组合根或 Profile 断言失败。
- [ ] Step 3: CompositionRoot.create(context, sourceDeviceId) 注入 Factory、KeywordRetrievalEngine 和 service，返回 gateway/provider；AppRuntime 使用稳定 P4 别名 local-device，不引入未确认的本机 network ID API。Profile 不包含 RTT、电量或 CPU。
- [ ] Step 4: 运行本地 test、assembleHap 和 API 24 RDB/检索 ohosTest，预期恢复和 smoke test 通过。提交：
~~~powershell
git add entry/src/main/ets/knowledge/profile/KnowledgeProfileBuilder.ets entry/src/main/ets/runtime/AppRuntime.ets entry/src/ohosTest/ets/test/KnowledgeDatabase.test.ets entry/src/ohosTest/ets/test/DeviceLocalRetrievalBenchmark.test.ets
git commit -m "test: verify semantic provider on RDB runtime"
~~~

## Task 8: 固定验收数据和知识端契约测试

**Files:**
- Modify: entry/src/test/support/SemanticFixtures.ets
- Modify: entry/src/test/EvidenceUnitFactory.test.ets
- Modify: entry/src/test/SemanticKnowledgeProvider.test.ets
- Modify: entry/src/test/KnowledgeCoreLogic.test.ets

- [ ] Step 1: 写验收测试。至少 20 条任务可产生候选：8 条本机域、8 条远端域、2 条 L1 足够、2 条 L2 后不足；不同 requiredConcepts 产生不同 covered concepts；隐私过滤有效。
- [ ] Step 2: 运行 Hvigor test 和本地 benchmark；预期数据缺项或覆盖不稳定时失败。
- [ ] Step 3: 固定 queryId、queryText、requiredConcepts、expectedDomain、expectedLevel 和 expectedTerminalState。本机文档域使用操作系统/数据库，远端使用网络/软件测试，不使用随机抽样。
- [ ] Step 4: 运行 Hvigor test、benchmark script 和 assembleHap，预期 Provider、Factory、旧查询和基准全通过。提交：
~~~powershell
git add entry/src/test/support/SemanticFixtures.ets entry/src/test/EvidenceUnitFactory.test.ets entry/src/test/SemanticKnowledgeProvider.test.ets entry/src/test/KnowledgeCoreLogic.test.ets
git commit -m "test: add knowledge evidence acceptance fixtures"
~~~

## Task 9: 知识端 handoff 验收说明

**Files:**
- Create: docs/testing/p4-knowledge-provider-acceptance.md

- [ ] Step 1: 写 handoff 检查。记录 indexVersion、Profile retrievalModes、evidence ID、parent ID、coveredConcepts、byteCost、privacyLevel，并确认输出不含 URI、embedding、RDB 对象和完整原文。
- [ ] Step 2: 运行 Hvigor test、assembleHap、scripts/run-local-retrieval-benchmark.ps1 -Label latest 和真实 RDB ohosTest；预期退出码 0、无失败用例、benchmark 报告生成。
- [ ] Step 3: 文档固定数据集版本、Provider 接口版本、Profile 能力、L1/L2 样例、错误码、RDB 恢复结果、耗时 P50/P95 和限制。提交：
~~~powershell
git add docs/testing/p4-knowledge-provider-acceptance.md
git commit -m "docs: record P4 knowledge provider acceptance"
~~~

## 完成定义

- Provider Profile 与 RDB 统计一致；
- searchEvidence 返回稳定、唯一、可升级的 L1/L2 EvidenceUnit；
- byteCost 与单条 EvidenceUnit JSON 的 UTF-8 字节一致；
- 隐私等级从导入、RDB、内存夹具到 Provider 全链路保留；
- retrievalModes 只有 keyword，embeddingModelVersion 为空；
- 空索引、构建中、错误索引和无匹配都有确定性结果或标准 KnowledgeError；
- 旧 LocalKnowledgeGateway 和本地 retrieval benchmark 通过；
- 新 Provider 可被通信端 Fake Provider 替换；
- P4 不实现真实向量数据库、MindSpore Lite、L3 和后台生命周期。
