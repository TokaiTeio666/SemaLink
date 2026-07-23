# SemaLink 中文 UI 重设计实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 HarmonyOS ArkTS 页面调整为设计图中的中文 SemaLink 三页移动端界面，同时保持现有业务状态和查询行为。

**Architecture:** 继续使用 `Index` 作为页面容器和 `AppRuntime` 状态订阅入口，在三个现有组件内完成布局重构。新增少量页面级样式辅助方法，不改变通信、查询路由、持久化和领域模型。

**Tech Stack:** HarmonyOS ArkUI、ArkTS、现有 Hvigor 构建和 Hypium/ArkTS 测试。

---

### Task 1: 重构页面容器与底部导航

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`
- Test: `entry/src/test/AutomaticQueryUi.test.ets`

- [x] **Step 1: 为导航状态补充测试覆盖**

确认现有测试覆盖默认查询页、页面切换和提交回调；如果缺少纯函数断言，补充一个只验证 `query/devices/history` 映射的无副作用测试。

- [x] **Step 2: 保持现有状态订阅，替换顶部导航结构**

保留 `snapshot`、`question`、`page` 和 `AppRuntime` 回调，将顶部胶囊按钮替换为中文标题栏和底部三项导航；诊断页面保留条件分支，但从主导航移除。

- [ ] **Step 3: 运行 UI 单测**

Run: `hvigorw test --no-daemon`

结果：未通过。DevEco Hvigor 可启动，但测试编译被仓库现有问题阻塞：缺少 `RdbSearchBackend.test` 和 `RdbSearchCapabilityProvider.test`，多个测试仓储未实现 `DocumentRepository.listDocuments/listChunks`。本次 UI 文件没有新增 ArkTS 编译错误。

### Task 2: 重构查询页

**Files:**
- Modify: `entry/src/main/ets/components/QueryHome.ets`

- [x] **Step 1: 保留可提交判定和回调契约**

保持 `canSubmitAutomaticQuery`、`onQuestionChange`、`onSubmit`、`onCancel` 和 `onRetry` 的签名不变，确保视图只改变表现层。

- [x] **Step 2: 按设计图实现中文查询布局**

将英文标题替换为中文标题和辅助文案，增加在线设备摘要、查询范围标签、带发送按钮的输入区域、纵向进度节点和答案摘要卡片；进度节点由 `automaticQueryProgress` 映射，结果卡片继续使用现有 `summary`、`taskConfidence`、`taskCoverage` 和来源字段。

- [x] **Step 3: 检查查询状态分支**

验证空输入、查询中、答案就绪、证据不足和失败状态的按钮可见性与可点击性，确保取消、重试仍调用原回调。

### Task 3: 重构设备页

**Files:**
- Modify: `entry/src/main/ets/components/DeviceOverview.ets`

- [x] **Step 1: 使用现有快照字段建立设备摘要**

基于 `activePeerCount`、`peerStatuses`、`knowledgeIndexState` 和文档/分块计数显示在线设备摘要，不增加新的领域字段。

- [x] **Step 2: 实现本机和远程设备卡片**

使用中文设备名称、在线/离线颜色状态、连接状态、知识类型、索引状态和最近同步信息；对于 `PeerStatusSnapshot` 中不存在的设计图字段使用稳定中文兜底文案。

- [x] **Step 3: 保留刷新行为**

保留刷新按钮回调 `onRefresh`，并验证无远程设备时的空状态不会破坏页面滚动布局。

### Task 4: 重构历史页并完成验证

**Files:**
- Modify: `entry/src/main/ets/components/QueryHistory.ets`
- Modify: `entry/src/test/CollaborationRecordState.test.ets` only if a display-state assertion is needed

- [x] **Step 1: 保留筛选和选择逻辑**

继续使用 `HistoryFilter` 和 `historyMatchesFilter`，将筛选按钮改为中文标签；保留记录点击后更新 `selectedId` 和调用 `onSelected`。

- [x] **Step 2: 实现日期分组和结果卡片**

按记录时间可用信息分组；每条记录显示问题、状态、来源、时间和证据/可信度信息。缺失时间或可信度时使用稳定的中文兜底显示，不修改 `CollaborationRecord` 模型。

- [ ] **Step 3: 执行构建与相关测试**

Run: `hvigorw assembleHap --no-daemon`, then run the relevant ArkTS tests for automatic query UI and collaboration history.

结果：`assembleHap --no-daemon` 构建通过；测试仍受上述仓库现有测试编译问题阻塞。构建输出仅保留既有 ArkTS 警告。

- [x] **Step 4: 检查最终差异**

Run: `git diff -- entry/src/main/ets/pages/Index.ets entry/src/main/ets/components/QueryHome.ets entry/src/main/ets/components/DeviceOverview.ets entry/src/main/ets/components/QueryHistory.ets`

Expected: 仅包含界面文案、布局、样式和导航调整，不包含通信、协议、数据库或用户已有未提交改动的回滚。
