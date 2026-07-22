# SemaLink 自动路由查询与三页 UI Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 让 SemaLink 在不要求用户选择或连接指定设备的情况下，自动从本机和在线设备中寻找最佳答案，并提供查询、设备、历史三页 UI。

**Architecture:** 新增纯函数式的自动查询任务构造层，复用现有 DeviceDirectory、DeviceSemanticRouter、MultiDeviceTaskCoordinator 和知识库服务。运行时负责发现并按需连接候选设备，协调器负责按路由评分并行检索；ArkTS 页面组件只订阅 AppStateStore，不直接控制连接。旧的单设备 QueryCoordinator 链路保留给兼容调用和远端响应。

**Tech Stack:** HarmonyOS ArkTS, ArkUI, Hypium, SoftBus/DSK, 现有 semantic knowledge contracts.

---

## 文件边界

- Create: entry/src/main/ets/application/AutomaticQueryPolicy.ets - 构造自动查询 TaskRequest、把语义阶段映射为 UI 文案和历史状态。
- Modify: entry/src/main/ets/communication/MultiDeviceTaskCoordinator.ets - 按路由分数选择本机与高匹配远端，保留本机回退。
- Modify: entry/src/main/ets/runtime/AppRuntime.ets - 增加自动查询入口、候选设备发现/按需连接和结果状态同步。
- Modify: entry/src/main/ets/model/AppModels.ets - 补充自动查询所需的只读 UI 快照字段；不删除现有连接字段。
- Modify: entry/src/main/ets/state/AppStateStore.ets - 复制和发布新增快照字段。
- Modify: entry/src/main/ets/collaboration/CollaborationModels.ets - 记录多个自动来源，并保持旧记录构造兼容。
- Create: entry/src/main/ets/components/QueryHome.ets - 查询首屏、自动路由进度和答案摘要。
- Create: entry/src/main/ets/components/DeviceOverview.ets - 在线设备与资料能力列表。
- Create: entry/src/main/ets/components/QueryHistory.ets - 历史筛选、历史条目和记录详情入口。
- Modify: entry/src/main/ets/pages/Index.ets - 只负责导航、订阅快照和调用三个页面组件；移除查询流程中的角色选择/手动连接前置 UI。
- Create: entry/src/test/AutomaticQueryPolicy.test.ets - 任务构造、阶段文案、回退状态测试。
- Modify: entry/src/test/MultiDeviceTaskCoordinator.test.ets - 路由分数排序、远端失败、本机回退测试。
- Modify: entry/src/test/AppRuntime.test.ets - 自动查询入口和无远端设备测试。
- Modify: entry/src/test/CollaborationRecordState.test.ets - 多来源历史记录兼容性测试。

## Task 1: 自动查询策略与快照字段

**Files:** Create AutomaticQueryPolicy.ets; modify AppModels.ets and AppStateStore.ets; create AutomaticQueryPolicy.test.ets.

- [ ] Write failing tests for buildAutomaticTask and queryProgressFor. Verify a trimmed question becomes a PRIVATE_GROUP TaskRequest with semantic contract 1.0, requiredConcepts empty, confidence 0.80, coverage 0.80, latency 10000, byte budget 8192, and levels L1/L2. Verify ROUTING maps to ROUTING, AWAITING_L1 to SEARCHING, EVALUATING_L2 to ANALYZING, SUFFICIENT to ANSWER_READY, ABORTED to INSUFFICIENT, and FAILED to FAILED.
- [ ] Run hvigorw test --tests entry/src/test/AutomaticQueryPolicy.test.ets. Expected: failure because AutomaticQueryPolicy.ets does not exist.
- [ ] Implement exact exports buildAutomaticTask(taskId, question, privacyLevel) and queryProgressFor(phase). Reject an empty trimmed question with E_QUERY_INVALID. Add automaticQueryProgress, automaticSourceNames, and automaticExcludedSourceNames to AppSnapshot, INITIAL_SNAPSHOT, and AppStateStore.update without removing existing fields.
- [ ] Run the focused test again. Expected: PASS.
- [ ] Commit with git add on the four Task 1 files and git commit -m "feat: add automatic query policy state".

## Task 2: 路由并执行可用候选

**Files:** Modify MultiDeviceTaskCoordinator.ets and AppRuntime.ets; modify MultiDeviceTaskCoordinator.test.ets and AppRuntime.test.ets.

- [ ] Add a coordinator test with local routeScore 0.30, remote-low 0.20, and remote-high 0.90. Assert remote-high is sent, remote-low is not selected when the remote limit is two, and local evidence still produces ENOUGH when a remote search fails.
- [ ] Run hvigorw test --tests entry/src/test/MultiDeviceTaskCoordinator.test.ets. Expected: failure because the current sort ignores routeScore.
- [ ] Change MultiDeviceTaskCoordinator.submit to filter ready candidates, sort descending by routeScore, use the first local plus at most two highest-scoring remotes, and keep the existing two-round evaluator. Remote send/search failures become empty evidence and do not abort a ready local candidate.
- [ ] Add AppRuntime.submitAutomaticQuery(question) and cancelAutomaticQuery(). Generate a task ID with SequenceIdGenerator, reject empty or over-1000-character input, set automaticQueryProgress to ROUTING, resolve peers with TrustedDeviceResolver.resolveAll(), refresh the DSK pool, and attempt tls.connect for peers concurrently. Record individual connection failures in automaticExcludedSourceNames and continue. Invoke the semantic coordinator without QueryCoordinator.connect(), DeviceRole, or a connected-state prerequisite. Map ENOUGH to ANSWER_READY, ABORT to INSUFFICIENT, and other errors to FAILED; publish summary, confidence, coverage, sufficiency and source aliases.
- [ ] Add a runtime test where a fake semantic provider returns local evidence and no remote exists. Run hvigorw test --tests entry/src/test/MultiDeviceTaskCoordinator.test.ets and hvigorw test --tests entry/src/test/AppRuntime.test.ets. Expected: PASS.
- [ ] Commit the coordinator and runtime files with git commit -m "feat: route automatic queries across available devices".

## Task 3: 自动来源历史记录

**Files:** Modify CollaborationModels.ets and CollaborationRecordState.test.ets; update AppModels.ets/AppStateStore.ets only if the snapshot type requires it.

- [ ] Add a failing test that creates a record with sourceDeviceNames ['工作平板', '生活平板'] and verifies clone, sort, and status update retain both aliases and evidenceCount.
- [ ] Run hvigorw test --tests entry/src/test/CollaborationRecordState.test.ets. Expected: failure because CollaborationRecord has no multi-source field.
- [ ] Add sourceDeviceNames: string[] to CollaborationRecord and CollaborationRecordInput. Update cloneRecord, createSendingRecord, and updateCollaborationRecord to copy the array. Legacy callers that only provide targetDeviceName receive an empty array; automatic records provide actual source aliases.
- [ ] Run hvigorw test --tests entry/src/test/CollaborationRecordState.test.ets and hvigorw test --tests entry/src/test/QueryCoordinator.test.ets. Expected: PASS, including legacy single-device records.
- [ ] Commit with git commit -m "feat: retain automatic query source devices in history".

## Task 4: 三页 ArkUI 页面

**Files:** Create QueryHome.ets, DeviceOverview.ets, QueryHistory.ets; modify Index.ets and required base string/color resources.

- [ ] Add pure helper tests for canSubmitAutomaticQuery(snapshot, question), progressLabel(progress), and historyMatchesFilter(record, filter). The submit helper uses trimmed question length and busy automatic progress only; it must not inspect connectionState or role.
- [ ] Run the focused policy/UI helper test. Expected: failure until the helpers exist.
- [ ] Implement QueryHome with online count, question TextArea, send/cancel actions, expandable progress steps, answer summary, confidence, source aliases, evidence count, and retry. Send calls AppRuntime.current().submitAutomaticQuery(question.trim()).
- [ ] Implement DeviceOverview with local/remote entries, online/index state, knowledge type, last sync and refresh. Refresh is informational and never a prerequisite for submitting.
- [ ] Implement QueryHistory with ALL, SUCCESS, INSUFFICIENT, NO_RESULT and OFFLINE filters. Render sourceDeviceNames and fall back to targetDeviceName for legacy records.
- [ ] Refactor Index.ets to own only subscription, page selection and shared error handling. Default page is query. Remove role selection, normal connect button, and connectionState === CONNECTED query enablement. Preserve responder and TLS diagnostic surfaces behind a non-default diagnostics path. Use existing colors, stable control dimensions, and no unrelated resource changes.
- [ ] Run hvigorw assembleHap and the focused test. Expected: HAP assembly succeeds and helper tests pass. When a device preview is available, verify default query page, no-connection submit, progress expansion, device navigation and history filtering.
- [ ] Commit with git commit -m "feat: add automatic query device and history pages".

## Task 5: 全量回归

**Files:** Inspect all files changed by Tasks 1-4; do not stage pre-existing unrelated worktree changes.

- [ ] Run focused tests for AutomaticQueryPolicy, MultiDeviceTaskCoordinator, AppRuntime, CollaborationRecordState and ProgressiveQueryCoordinator. Expected: PASS.
- [ ] Run hvigorw test and hvigorw assembleHap. Expected: no new test failures and successful HAP assembly.
- [ ] Run git diff --check and git status --short. Confirm only automatic query behavior, history metadata, three-page UI, tests and required resources are included; existing communication-layer changes remain untouched.
- [ ] If a regression is found, add a focused failing test first, fix the behavior, rerun the failing command and commit the fix separately with a behavior-specific message.

## Self-review

- Spec coverage: automatic input-only query, local/remote candidates, route scoring, parallel evidence, local fallback, insufficient/conflict states, three pages, history filters, cancel/retry, and regression verification are covered by Tasks 1-5.
- Placeholder scan: every task names concrete files, commands, expected outcomes, and error behavior.
- Type consistency: Task 1 defines AutomaticQueryProgress and snapshot fields before Tasks 2 and 4 consume them; Task 3 defines sourceDeviceNames before Task 4 renders it.
