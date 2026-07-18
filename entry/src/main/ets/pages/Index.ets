import { AppError } from '../common/AppError';
import { AppRuntime } from '../runtime/AppRuntime';
import { AppSnapshot, ConnectionState, DeviceRole, INITIAL_SNAPSHOT, cloneSnapshot } from '../model/AppModels';
import { DisplayKnowledgeItem } from '../application/KnowledgeQueryDisplayState';
import { KnowledgePayloadLevel } from '../contracts/knowledge/KnowledgeModels';
import { CollaborationRecord, CollaborationRecordStatus } from '../collaboration/CollaborationModels';
import { CollaborationRecordList } from '../components/CollaborationRecordList';
import { CollaborationRecordDetail } from '../components/CollaborationRecordDetail';

/**
 * Sentinel record used by the collaboration detail host when no record is currently selected.
 * The detail component only reads record fields when hasRecord is true, so this sentinel merely
 * satisfies the @Prop requirement that a value is present at construction time.
 */
const EMPTY_COLLABORATION_RECORD: CollaborationRecord = {
  id: '',
  question: '',
  sourceDeviceName: '',
  targetDeviceName: '',
  createdAt: 0,
  status: CollaborationRecordStatus.SENDING,
  summary: '',
  evidenceCount: 0,
  errorMessage: ''
};

export function isBusy(state: ConnectionState): boolean {
  return state === ConnectionState.CONNECTING || state === ConnectionState.SELECTING_DEVICE ||
    state === ConnectionState.WAITING_ACK || state === ConnectionState.WAITING_RESULT;
}

export function canSubmit(snapshot: AppSnapshot, question: string): boolean {
  return snapshot.role === DeviceRole.INITIATOR && snapshot.connectionState === ConnectionState.CONNECTED &&
    question.trim().length >= 1 && question.length <= 1000;
}

export function shouldShowConnect(snapshot: AppSnapshot): boolean {
  return snapshot.role === DeviceRole.INITIATOR &&
    (snapshot.connectionState === ConnectionState.IDLE ||
      snapshot.connectionState === ConnectionState.DISCONNECTED ||
      snapshot.connectionState === ConnectionState.ERROR);
}

export function canQueryKnowledge(snapshot: AppSnapshot, question: string): boolean {
  return snapshot.knowledgeInitialized && !snapshot.knowledgeBusy && snapshot.knowledgeIndexState === 'READY' &&
    question.trim().length >= 1 && question.length <= 1000;
}

export function semanticTaskStatus(snapshot: AppSnapshot): string {
  const feedback: string = snapshot.taskFeedback.length > 0 ? snapshot.taskFeedback : '-';
  const round: string = snapshot.taskRound > 0 ? ' · R' + snapshot.taskRound.toString() : '';
  return snapshot.taskPhase + ' · ' + feedback + round;
}

@Entry
@Component
struct Index {
  @State snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  @State question: string = '';
  @State localQuestion: string = '';
  @State knowledgeLevel: KnowledgePayloadLevel = 'L2';
  @State collaborationBreakpoint: string = 'sm';
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    this.unsubscribe = AppRuntime.current().store.subscribe((state: AppSnapshot) => {
      this.snapshot = state;
      this.question = state.question;
    });
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        this.header()
        this.collaborationSection()
        this.knowledgeSection()
        this.semanticTaskSection()
        this.roleSelector()
        this.connectionSection()
        if (this.snapshot.role === DeviceRole.RESPONDER) {
          this.responderSection()
        } else {
          this.querySection()
        }
        this.resultSection()
        this.metricsSection()
        this.errorSection()
        this.disconnectButton()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .scrollBar(BarState.Off)
  }

  @Builder
  knowledgeSection() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text('本机知识库')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.snapshot.knowledgeMessage)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(this.snapshot.knowledgeIndexState)
          .fontSize(12)
          .fontColor(this.snapshot.knowledgeIndexState === 'READY' ?
            $r('app.color.status_success') : $r('app.color.text_secondary'))
      }
      .width('100%')

      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text('文档').fontSize(12).fontColor($r('app.color.text_secondary'))
          Text(this.snapshot.knowledgeDocumentCount.toString())
            .id('knowledge-document-count')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding(12)
        .backgroundColor($r('app.color.surface'))
        Column({ space: 4 }) {
          Text('分块').fontSize(12).fontColor($r('app.color.text_secondary'))
          Text(this.snapshot.knowledgeChunkCount.toString())
            .id('knowledge-chunk-count')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding(12)
        .backgroundColor($r('app.color.surface'))
      }
      .width('100%')

      if (this.snapshot.knowledgeBusy) {
        Row({ space: 10 }) {
          Progress({ value: 0 }).width(22).height(22)
          Text('正在处理...').fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
      }

      Row({ space: 8 }) {
        Button('L1 摘要')
          .layoutWeight(1)
          .backgroundColor(this.knowledgeLevel === 'L1' ? $r('app.color.accent') : $r('app.color.surface_muted'))
          .fontColor(this.knowledgeLevel === 'L1' ? Color.White : $r('app.color.text_primary'))
          .onClick(() => this.knowledgeLevel = 'L1')
        Button('L2 段落')
          .layoutWeight(1)
          .backgroundColor(this.knowledgeLevel === 'L2' ? $r('app.color.accent') : $r('app.color.surface_muted'))
          .fontColor(this.knowledgeLevel === 'L2' ? Color.White : $r('app.color.text_primary'))
          .onClick(() => this.knowledgeLevel = 'L2')
      }
      .width('100%')

      TextArea({ placeholder: '输入要在本机知识库检索的问题', text: this.localQuestion })
        .id('local-knowledge-input')
        .height(96)
        .enabled(this.snapshot.knowledgeInitialized && !this.snapshot.knowledgeBusy)
        .maxLength(1000)
        .onChange((value: string) => this.localQuestion = value)
      Button('查询本机知识库')
        .id('local-knowledge-query')
        .width('100%')
        .enabled(canQueryKnowledge(this.snapshot, this.localQuestion))
        .onClick(() => this.runKnowledgeCommand(() =>
          AppRuntime.current().queryLocalKnowledge(this.localQuestion.trim(), this.knowledgeLevel)))

      Row({ space: 8 }) {
        Button('导入内置文档')
          .layoutWeight(1)
          .fontSize(13)
          .enabled(this.snapshot.knowledgeInitialized && !this.snapshot.knowledgeBusy)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.runKnowledgeCommand(() => AppRuntime.current().importBuiltInKnowledge()))
        Button('选择文本文件')
          .layoutWeight(1)
          .fontSize(13)
          .enabled(this.snapshot.knowledgeInitialized && !this.snapshot.knowledgeBusy)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.runKnowledgeCommand(() => AppRuntime.current().importUserKnowledge()))
      }
      .width('100%')

      if (this.snapshot.knowledgeDocumentCount > 0) {
        Button('清空知识库')
          .width('100%')
          .enabled(!this.snapshot.knowledgeBusy)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.status_error'))
          .onClick(() => this.confirmClearKnowledge())
      }

      if (this.snapshot.knowledgeError.length > 0) {
        Text(this.snapshot.knowledgeError)
          .fontSize(13)
          .fontColor($r('app.color.status_error'))
          .width('100%')
      }

      if (this.snapshot.knowledgeQueryStatus === 'EMPTY') {
        Text('没有找到相关内容')
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      ForEach(this.snapshot.knowledgeItems, (item: DisplayKnowledgeItem, index: number) => {
        this.knowledgeResultItem(item, index)
      }, (item: DisplayKnowledgeItem, index: number) => item.title + index.toString())
    }
    .id('knowledge-section')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  knowledgeResultItem(item: DisplayKnowledgeItem, index: number) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text((item.relevance * 100).toFixed(0) + '%')
          .fontSize(12)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')
      Text(item.kind + (item.chunkLabel.length > 0 ? ' · ' + item.chunkLabel : ''))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text(item.content)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
    .id('knowledge-result-' + index.toString())
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_muted'))
  }

  @Builder
  semanticTaskSection() {
    Column({ space: 10 }) {
      Text('语义任务状态')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(semanticTaskStatus(this.snapshot))
        .id('semantic-task-status')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        this.metric('TSF 覆盖率', `${(this.snapshot.taskCoverage * 100).toFixed(0)}%`, 'semantic-task-coverage')
        this.metric('TSF 置信度', `${(this.snapshot.taskConfidence * 100).toFixed(0)}%`, 'semantic-task-confidence')
      }
      .width('100%')
      Row({ space: 8 }) {
        this.metric('选中设备', this.snapshot.selectedDeviceId.length > 0 ?
          this.snapshot.selectedDeviceId : '-', 'semantic-task-device')
        this.metric('证据字节', `${this.snapshot.evidenceBytes} B`, 'semantic-task-evidence-bytes')
      }
      .width('100%')
    }
    .id('semantic-task-section')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  header() {
    Column({ space: 6 }) {
      Text($r('app.string.app_title'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(this.connectionLabel())
        .id('connection-status')
        .fontSize(14)
        .fontColor(this.snapshot.connectionState === ConnectionState.ERROR ?
          $r('app.color.status_error') : $r('app.color.text_secondary'))
        .width('100%')
      if (this.snapshot.peerDeviceName.length > 0) {
        Text(this.snapshot.peerDeviceName + ' · ' + this.snapshot.peerDeviceIdMasked)
          .id('peer-device-info')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  collaborationSection() {
    Column({ space: 12 }) {
      Text($r('app.string.collaboration_records'))
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      GridRow({ breakpoints: { value: ['600vp', '840vp'] } }) {
        GridCol({ span: { sm: 12, md: 6, lg: 6 } }) {
          if (this.showCollaborationList()) {
            CollaborationRecordList({
              records: this.snapshot.collaborationRecords,
              selectedId: this.snapshot.selectedCollaborationRecordId,
              onSelected: (id: string) => {
                AppRuntime.current().coordinator.selectCollaborationRecord(id);
              }
            })
          }
        }

        GridCol({ span: { sm: 12, md: 6, lg: 6 } }) {
          if (this.showCollaborationDetail()) {
            CollaborationRecordDetail({
              record: this.findSelectedRecord(),
              hasRecord: this.hasSelectedRecord(),
              onContinue: (id: string) => {
                AppRuntime.current().coordinator.prepareFollowUp(id);
              },
              onRetry: (id: string) => {
                this.retryCollaborationQuery(id);
              },
              onBack: () => {
                this.backToCollaborationList();
              }
            })
          }
        }
      }
      .onBreakpointChange((bp: string) => {
        this.collaborationBreakpoint = bp;
      })
      .width('100%')
    }
    .id('collaboration-section')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  roleSelector() {
    Column({ space: 8 }) {
      Text($r('app.string.role_label')).fontSize(14).fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        Button($r('app.string.initiator_role'))
          .id('role-selector')
          .layoutWeight(1)
          .enabled(this.snapshot.role === DeviceRole.UNSELECTED)
          .backgroundColor(this.snapshot.role === DeviceRole.INITIATOR ?
            $r('app.color.accent') : $r('app.color.surface'))
          .fontColor(this.snapshot.role === DeviceRole.INITIATOR ? Color.White :
            $r('app.color.text_primary'))
          .onClick(() => AppRuntime.current().coordinator.selectInitiator())
        Button($r('app.string.responder_role'))
          .id('responder-selector')
          .layoutWeight(1)
          .enabled(false)
          .backgroundColor(this.snapshot.role === DeviceRole.RESPONDER ?
            $r('app.color.accent') : $r('app.color.surface'))
          .fontColor(this.snapshot.role === DeviceRole.RESPONDER ? Color.White :
            $r('app.color.text_primary'))
      }
      .width('100%')
    }
    .id('role-selector-section')
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  connectionSection() {
    Column({ space: 10 }) {
      if (shouldShowConnect(this.snapshot)) {
        Button(this.snapshot.connectionState === ConnectionState.ERROR ?
          $r('app.string.retry_connection') : $r('app.string.connect_device'))
          .id('connect-button')
          .width('100%')
          .onClick(() => this.runCommand(() => AppRuntime.current().coordinator.connect()))
      } else if (isBusy(this.snapshot.connectionState)) {
        Row({ space: 10 }) {
          Progress({ value: 0 })
          Text($r('app.string.connecting')).fontColor($r('app.color.text_secondary'))
        }
        .id('connecting-indicator')
      }
    }
    .width('100%')
  }

  @Builder
  responderSection() {
    Text($r('app.string.waiting_remote_query'))
      .id('responder-waiting')
      .fontSize(16)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding(20)
      .backgroundColor($r('app.color.surface'))
  }

  @Builder
  querySection() {
    Column({ space: 10 }) {
      TextArea({ placeholder: $r('app.string.question_placeholder'), text: this.question })
        .id('question-input')
        .height(112)
        .enabled(this.snapshot.connectionState === ConnectionState.CONNECTED)
        .maxLength(1000)
        .onChange((value: string) => this.question = value)
      Button($r('app.string.submit_query'))
        .id('submit-button')
        .width('100%')
        .enabled(canSubmit(this.snapshot, this.question))
        .onClick(() => this.runCommand(() => AppRuntime.current().coordinator.submit(this.question.trim())))
    }
    .width('100%')
  }

  @Builder
  resultSection() {
    if (this.snapshot.summary.length > 0) {
      Column({ space: 8 }) {
        Text($r('app.string.result_label')).fontSize(14).fontColor($r('app.color.text_secondary'))
        Text(this.snapshot.summary)
          .id('result-summary')
          .fontSize(17)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface'))
    }
  }

  @Builder
  metricsSection() {
    Row({ space: 8 }) {
      this.metric($r('app.string.time_metric'), `${this.snapshot.roundTripMs} ms`, 'round-trip-ms')
      this.metric($r('app.string.bytes_metric'), `${this.snapshot.bytesSent + this.snapshot.bytesReceived} B`, 'bytes-total')
    }
    .width('100%')
  }

  @Builder
  metric(label: Resource | string, value: string, id: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(value).id(id).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  errorSection() {
    if (this.snapshot.error !== undefined) {
      Column({ space: 8 }) {
        Text(this.snapshot.error.message)
          .id('error-message')
          .fontColor($r('app.color.status_error'))
          .width('100%')
        Text(`${this.snapshot.error.code} · ${this.snapshot.error.stage}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .id('error-section')
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.error_surface'))
    }
  }

  @Builder
  disconnectButton() {
    if (this.snapshot.connectionState !== ConnectionState.IDLE &&
      this.snapshot.connectionState !== ConnectionState.DISCONNECTED &&
      this.snapshot.role !== DeviceRole.UNSELECTED) {
      Button($r('app.string.disconnect'))
        .id('disconnect-button')
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => this.runCommand(() => AppRuntime.current().coordinator.disconnect()))
    }
  }

  private findSelectedRecord(): CollaborationRecord {
    const records: Array<CollaborationRecord> = this.snapshot.collaborationRecords;
    const selectedId: string = this.snapshot.selectedCollaborationRecordId;
    for (let i = 0; i < records.length; i++) {
      if (records[i].id === selectedId) {
        return records[i];
      }
    }
    return EMPTY_COLLABORATION_RECORD;
  }

  private hasSelectedRecord(): boolean {
    return this.snapshot.selectedCollaborationRecordId.length > 0;
  }

  private isWideLayout(): boolean {
    return this.collaborationBreakpoint === 'md' ||
      this.collaborationBreakpoint === 'lg' ||
      this.collaborationBreakpoint === 'xl' ||
      this.collaborationBreakpoint === 'xxl';
  }

  private showCollaborationList(): boolean {
    // On wide layouts the list is always rendered alongside the detail.
    // On phone widths the list renders only until a record is selected.
    return this.isWideLayout() || !this.hasSelectedRecord();
  }

  private showCollaborationDetail(): boolean {
    // On wide layouts the detail (or placeholder) is always rendered next to the list.
    // On phone widths the detail renders only when a record is selected.
    return this.isWideLayout() || this.hasSelectedRecord();
  }

  private retryCollaborationQuery(id: string): void {
    // Locate the record's question without relying on the currently edited question input.
    const records: Array<CollaborationRecord> = this.snapshot.collaborationRecords;
    let question: string = '';
    for (let i = 0; i < records.length; i++) {
      if (records[i].id === id) {
        question = records[i].question;
        break;
      }
    }
    if (question.length === 0) {
      return;
    }
    // Restore the question and clear summary/error before submitting through the existing path.
    if (!AppRuntime.current().coordinator.prepareFollowUp(id)) {
      return;
    }
    // Submit through the existing initiator/connection validation and submit path.
    this.runCommand(() => AppRuntime.current().coordinator.submit(question.trim()));
  }

  private backToCollaborationList(): void {
    // Clear the selection so phone-width layouts return to the list view.
    AppRuntime.current().store.update({ selectedCollaborationRecordId: '' });
  }

  private connectionLabel(): Resource {
    switch (this.snapshot.connectionState) {
      case ConnectionState.CONNECTED: return $r('app.string.status_connected');
      case ConnectionState.ERROR: return $r('app.string.status_error');
      case ConnectionState.WAITING_ACK:
      case ConnectionState.WAITING_RESULT: return $r('app.string.status_processing');
      default: return $r('app.string.status_ready');
    }
  }

  private runCommand(command: () => Promise<void>): void {
    command().catch((error: Object) => {
      const appError: AppError = error as AppError;
      this.snapshot = cloneSnapshot(this.snapshot, undefined, undefined, appError);
    });
  }

  private runKnowledgeCommand(command: () => Promise<void>): void {
    command().catch((_error: Object) => {
      // AppRuntime publishes knowledge errors through AppStateStore.
    });
  }

  private confirmClearKnowledge(): void {
    AlertDialog.show({
      title: '清空知识库',
      message: '已导入的内置文档和用户文档都会被删除。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.status_error'),
        action: () => this.runKnowledgeCommand(() => AppRuntime.current().clearKnowledge())
      }
    });
  }
}
