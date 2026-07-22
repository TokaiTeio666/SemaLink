# SemaLink Collaboration History UI Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add an in-memory cross-device collaboration history UI with a responsive list/detail layout and a primary “继续查询” action, without changing the transport protocol or knowledge database.

**Architecture:** Add a focused collaboration-record model and pure state helpers, extend AppSnapshot and AppStateStore, and let QueryCoordinator translate initiator and responder query lifecycles into records. Keep SessionManager unchanged. Compose the existing Index page from focused list/detail components and reuse existing color resources.

**Tech Stack:** HarmonyOS NEXT API 24, ArkTS, ArkUI, AppStateStore, QueryCoordinator, SessionManager, @ohos/hypium, Hvigor.

---

## Existing Worktree

The workspace already has uncommitted changes in:

- entry/src/main/ets/application/QueryCoordinator.ets
- entry/src/main/ets/communication/SessionManager.ets
- entry/src/main/ets/protocol/ProtocolModels.ets
- entry/src/test/QueryCoordinator.test.ets
- entry/src/test/SessionManager.test.ets

Inspect and preserve these changes before implementation. Do not reset, checkout, or broadly reformat them.

## File Map

Create:

- entry/src/main/ets/collaboration/CollaborationModels.ets: record type, status enum, pure record helpers.
- entry/src/main/ets/components/CollaborationRecordList.ets: list, selection, empty state.
- entry/src/main/ets/components/CollaborationRecordDetail.ets: selected record detail and actions.
- entry/src/test/CollaborationRecordState.test.ets: pure record-state tests.

Modify:

- entry/src/main/ets/model/AppModels.ets
- entry/src/main/ets/state/AppStateStore.ets
- entry/src/main/ets/application/QueryCoordinator.ets
- entry/src/main/ets/pages/Index.ets
- entry/src/main/resources/base/element/string.json
- entry/src/test/QueryCoordinator.test.ets
- entry/src/ohosTest/ets/test/IndexPage.test.ets
- entry/src/test/List.test.ets

Do not modify the database schema, protocol model, or SessionManager.ets.

## Task 1: Add the Collaboration Record Model

**Files:**

- Create: entry/src/main/ets/collaboration/CollaborationModels.ets
- Create: entry/src/test/CollaborationRecordState.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: Write failing tests.

Test creation, immutable update, selection, newest-first sorting, and unknown-ID no-op behavior:

    const record = createSendingRecord({
      id: 'request-1',
      question: '项目状态',
      sourceDeviceName: '本机',
      targetDeviceName: 'MatePad',
      createdAt: 1000
    });
    expect(record.status).assertEqual(CollaborationRecordStatus.SENDING);
    expect(record.summary).assertEqual('');
    expect(record.evidenceCount).assertEqual(0);

    const updated = updateCollaborationRecord(record.id, [record], {
      status: CollaborationRecordStatus.SYNCED,
      summary: '摘要',
      evidenceCount: 2
    });
    expect(updated[0].status).assertEqual(CollaborationRecordStatus.SYNCED);
    expect(updated[0].evidenceCount).assertEqual(2);

Register collaborationRecordStateTest in entry/src/test/List.test.ets.

- [ ] Step 2: Run the test and confirm failure.

    $node = 'C:\Program Files\nodejs\node.exe'
    $hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
    & $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test

Expected: failure because the new module and test suite are not implemented.

- [ ] Step 3: Implement the minimal pure model.

Define CollaborationRecordStatus with SENDING, SYNCED, OFFLINE, FAILED, and TIMEOUT. Define CollaborationRecord with id, question, sourceDeviceName, targetDeviceName, createdAt, status, summary, evidenceCount, and errorMessage.

Add createSendingRecord, updateCollaborationRecord, selectCollaborationRecord, and sortCollaborationRecords. Helpers must return new arrays/objects and preserve caller input.

- [ ] Step 4: Run all tests.

Run the Hvigor command from Step 2. Expected: the new record suite and all existing suites pass.

- [ ] Step 5: Commit.

    git add entry/src/main/ets/collaboration/CollaborationModels.ets entry/src/test/CollaborationRecordState.test.ets entry/src/test/List.test.ets
    git commit -m "feat: add collaboration record state model"

## Task 2: Extend App State Without Persistence

**Files:**

- Modify: entry/src/main/ets/model/AppModels.ets
- Modify: entry/src/main/ets/state/AppStateStore.ets
- Modify: entry/src/ohosTest/ets/test/IndexPage.test.ets

- [ ] Step 1: Write failing snapshot tests.

Assert that INITIAL_SNAPSHOT has an empty record array and empty selected ID. Update AppStateStore with selectedCollaborationRecordId = 'request-1', then assert it is published. Assert cloneSnapshot preserves both new fields.

- [ ] Step 2: Run the focused test and confirm failure.

Run the Hvigor test command from Task 1. Expected: ArkTS compilation failure because the fields do not exist.

- [ ] Step 3: Add snapshot fields.

Import CollaborationRecord and add collaborationRecords: Array<CollaborationRecord> and selectedCollaborationRecordId: string to AppSnapshot. Initialize them as [] and ''. Copy them in cloneSnapshot. Extend StateUpdate and AppStateStore.update to preserve current values when omitted and replace them when supplied.

Do not clear records in selectInitiator. Records are scoped to the current AppRuntime and reset when the runtime is reset.

- [ ] Step 4: Run the regression suite.

Run the Hvigor test command. Expected: all existing tests and the updated IndexPage suite pass.

- [ ] Step 5: Commit.

    git add entry/src/main/ets/model/AppModels.ets entry/src/main/ets/state/AppStateStore.ets entry/src/ohosTest/ets/test/IndexPage.test.ets
    git commit -m "feat: expose collaboration history in app state"

## Task 3: Record Query Lifecycle in QueryCoordinator

**Files:**

- Modify: entry/src/main/ets/application/QueryCoordinator.ets
- Modify: entry/src/test/QueryCoordinator.test.ets

- [ ] Step 1: Write failing initiator and follow-up tests.

Using the existing RecordingTransport, FakeScheduler, and FakeKnowledgeGateway fixtures, test that an initiator query creates SENDING immediately, becomes SYNCED after a result, preserves request ID/question/peer/summary/evidence count, restores the question with prepareFollowUp(recordId), and sends no transport message during follow-up restoration.

Test that prepareFollowUp('missing') returns false and changes no state.

- [ ] Step 2: Write failing error mapping tests.

Cover this exact mapping:

    E_ACK_TIMEOUT     -> TIMEOUT
    E_RESULT_TIMEOUT  -> TIMEOUT
    E_DISCONNECTED    -> OFFLINE
    other AppError    -> FAILED

Use FakeScheduler.advanceBy for timeouts and the existing protocol error fixture for a normal failure. Assert that the original question and actionable error message remain in the record.

- [ ] Step 3: Run the focused tests and confirm failure.

Run the complete Hvigor test command. Expected: the new assertions fail because no record lifecycle code exists.

- [ ] Step 4: Implement initiator lifecycle tracking.

In submit(question), call session.execute and capture requestId. Read the peer name from the store, falling back to 远端设备. Append a SENDING record with ID requestId, source 本机, and createdAt startedAt. Set the selected record ID while preserving current question and metric updates.

On success, update to SYNCED, set summary from result.summary, and set evidence count from result.knowledgeResult?.itemCount ?? 0. On error, map the error code to TIMEOUT, OFFLINE, or FAILED and preserve existing snapshot error behavior.

Use the pure helpers from Task 1. Do not change SessionManager or protocol types.

- [ ] Step 5: Add follow-up methods.

Add selectCollaborationRecord(id: string): boolean and prepareFollowUp(id: string): boolean. Selection only changes the selected ID when the record exists. Follow-up selects the record, restores its question, clears summary/error, and never calls session.execute.

- [ ] Step 6: Track responder-side activity.

In onIncomingQuery, create a record before sending ACK with source equal to the peer name or 远端设备, target 本机, and the envelope request ID. Update to SYNCED after sendResult succeeds, including summary and knowledge item count. Update to FAILED in the catch path before publishing the existing error.

- [ ] Step 7: Run and commit.

Run the full Hvigor test command and expect all new and existing suites to pass.

    git add entry/src/main/ets/application/QueryCoordinator.ets entry/src/test/QueryCoordinator.test.ets
    git commit -m "feat: track cross-device query history"

## Task 4: Build the List and Detail Components

**Files:**

- Create: entry/src/main/ets/components/CollaborationRecordList.ets
- Create: entry/src/main/ets/components/CollaborationRecordDetail.ets

- [ ] Step 1: Define component contracts.

The list accepts records, selectedId, and onSelected(id). The detail accepts record, onContinue(id), onRetry(id), and onBack(). Neither component may call AppRuntime.current() or SessionManager.

- [ ] Step 2: Implement list rendering.

Render newest-first records. Each item must have a stable ID formed by concatenating collaboration-record- and record.id, show question, device direction, time, status, and evidence count, and distinguish the selected item. Render a dedicated empty state when the array is empty. Reuse the existing surface, surface_muted, accent, text_primary, text_secondary, status_success, and error_surface resources.

- [ ] Step 3: Implement detail rendering.

For no selected record, render a placeholder. For a selected record, render question, source/target devices, status, summary, evidence count, and error message when present. Always show the primary 继续查询 action. Show 重新发送 only for FAILED, OFFLINE, or TIMEOUT. Invoke callbacks with the record ID and never auto-submit.

- [ ] Step 4: Compile the component change.

    $node = 'C:\Program Files\nodejs\node.exe'
    $hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
    & $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap

Expected: BUILD SUCCESSFUL and no ArkTS component/type errors.

- [ ] Step 5: Commit.

    git add entry/src/main/ets/components/CollaborationRecordList.ets entry/src/main/ets/components/CollaborationRecordDetail.ets
    git commit -m "feat: add collaboration history list and detail UI"

## Task 5: Integrate the Responsive Section Into Index

**Files:**

- Modify: entry/src/main/ets/pages/Index.ets
- Modify: entry/src/main/resources/base/element/string.json

- [ ] Step 1: Add resource strings.

Add these resource keys to entry/src/main/resources/base/element/string.json: collaboration_records, collaboration_empty, collaboration_continue_query, collaboration_retry, collaboration_back_to_list, collaboration_status_sending, collaboration_status_synced, collaboration_status_offline, collaboration_status_failed, and collaboration_status_timeout. Use the matching $r('app.string.<key>') resource from the UI components.

- [ ] Step 2: Wire state and callbacks.

Import both components and the record selection helper. Derive the selected record from snapshot.collaborationRecords and snapshot.selectedCollaborationRecordId. Wire selection and continue actions to:

    AppRuntime.current().coordinator.selectCollaborationRecord(id);
    AppRuntime.current().coordinator.prepareFollowUp(id);

The retry action must use the existing initiator/connection validation and submit path; it must not call SessionManager directly.

- [ ] Step 3: Add the collaboration section.

Place collaborationSection immediately after header. Use GridRow/GridCol responsive spans for a wide layout with list on the left and detail on the right. On phone width, render the list until a record is selected, then render detail with a back action. Leave existing knowledge, role, connection, query, result, metrics, error, and disconnect builders intact.

- [ ] Step 4: Manually verify required states.

Verify empty, selected synced, failed, offline, timeout, phone list/detail transition, and tablet side-by-side layout. Check that status changes do not resize buttons or overlap text.

- [ ] Step 5: Compile and commit.

    $node = 'C:\Program Files\nodejs\node.exe'
    $hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
    & $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
    git add entry/src/main/ets/pages/Index.ets entry/src/main/resources/base/element/string.json
    git commit -m "feat: integrate collaboration history into index"

Expected: BUILD SUCCESSFUL.

## Task 6: Final Regression and Acceptance Verification

**Files:**

- Modify: entry/src/test/CollaborationRecordState.test.ets
- Modify: entry/src/test/QueryCoordinator.test.ets
- Modify: entry/src/ohosTest/ets/test/IndexPage.test.ets
- Modify: entry/src/test/List.test.ets

- [ ] Step 1: Complete test coverage.

Ensure coverage includes immutable updates, newest-first ordering, selection, status label mapping, initiator success, responder success, failed send, offline disconnect, ACK timeout, result timeout, follow-up restoration, retry guards, and preservation of existing knowledge/metrics state.

- [ ] Step 2: Run all unit tests.

    $node = 'C:\Program Files\nodejs\node.exe'
    $hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
    & $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test

Expected: exit code 0, all Hypium tests pass, and output contains BUILD SUCCESSFUL.

- [ ] Step 3: Build the HAP.

    & $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap

Expected: exit code 0 and BUILD SUCCESSFUL.

- [ ] Step 4: Run on-device checks when devices are available.

Install the debug HAP using the procedure in docs/SemaLink_编译并安装HAP到设备A和平板B.md on an API 24 phone and tablet. Verify the UI states from Task 5. If devices are unavailable, report that on-device verification was not run; do not claim it passed.

- [ ] Step 5: Review and commit final test changes.

    git diff --check
    git status --short
    git diff --stat
    git add entry/src/test/CollaborationRecordState.test.ets entry/src/test/QueryCoordinator.test.ets entry/src/ohosTest/ets/test/IndexPage.test.ets entry/src/test/List.test.ets
    git commit -m "test: verify collaboration history UI state"

Confirm no database schema, protocol, or unrelated worktree file was staged.

## Acceptance Checklist

- [ ] Collaboration records appear before the existing knowledge section.
- [ ] Records are newest-first and selectable.
- [ ] Wide layouts show list and detail side by side.
- [ ] Phone layouts switch between list and detail without overlap.
- [ ] Synced records show summary, evidence count, and 继续查询.
- [ ] Failed, offline, and timeout records show actionable retry behavior.
- [ ] 继续查询 restores the question without auto-submitting.
- [ ] Existing knowledge and communication flows remain intact.
- [ ] No protocol or database migration is introduced.
- [ ] Hvigor tests and HAP build pass.
