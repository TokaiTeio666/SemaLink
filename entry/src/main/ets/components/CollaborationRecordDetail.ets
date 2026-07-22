import { CollaborationRecord, CollaborationRecordStatus } from '../collaboration/CollaborationModels';

/**
 * Sentinel record used when no collaboration record is selected. The detail component
 * checks the hasRecord flag before reading any record field, so this sentinel only
 * satisfies the @Prop requirement that a value is present at construction time.
 */
const EMPTY_COLLABORATION_RECORD: CollaborationRecord = {
  id: '',
  question: '',
  sourceDeviceName: '',
  sourceDeviceNames: [],
  targetDeviceName: '',
  createdAt: 0,
  status: CollaborationRecordStatus.SENDING,
  summary: '',
  evidenceCount: 0,
  errorMessage: ''
};

/**
 * Renders the selected collaboration record detail and its primary actions. The component
 * is a pure UI surface: it receives the record and action callbacks from the parent and
 * never calls AppRuntime or SessionManager directly.
 *
 * Contract:
 * - record: the selected collaboration record (use EMPTY_COLLABORATION_RECORD when none).
 * - hasRecord: true when a real record is selected; false renders the placeholder.
 * - onContinue: invoked with the record id when the user taps 继续查询.
 * - onRetry: invoked with the record id when the user taps 重新发送.
 * - onBack: invoked when the user taps 返回列表 (used for phone-width list/detail transitions).
 *
 * The 重新发送 action is only shown for FAILED, OFFLINE, or TIMEOUT records. The component
 * never auto-submits; it always delegates to the callbacks.
 */
@Component
export struct CollaborationRecordDetail {
  @Prop record: CollaborationRecord = EMPTY_COLLABORATION_RECORD;
  @Prop hasRecord: boolean = false;
  onContinue: (id: string) => void = () => {};
  onRetry: (id: string) => void = () => {};
  onBack: () => void = () => {};

  private canRetry(status: CollaborationRecordStatus): boolean {
    return status === CollaborationRecordStatus.FAILED ||
      status === CollaborationRecordStatus.OFFLINE ||
      status === CollaborationRecordStatus.TIMEOUT;
  }

  private statusLabel(status: CollaborationRecordStatus): Resource {
    switch (status) {
      case CollaborationRecordStatus.SENDING:
        return $r('app.string.collaboration_status_sending');
      case CollaborationRecordStatus.SYNCED:
        return $r('app.string.collaboration_status_synced');
      case CollaborationRecordStatus.OFFLINE:
        return $r('app.string.collaboration_status_offline');
      case CollaborationRecordStatus.FAILED:
        return $r('app.string.collaboration_status_failed');
      case CollaborationRecordStatus.TIMEOUT:
        return $r('app.string.collaboration_status_timeout');
      default:
        return $r('app.string.collaboration_status_sending');
    }
  }

  private statusColor(status: CollaborationRecordStatus): Resource {
    switch (status) {
      case CollaborationRecordStatus.SYNCED:
        return $r('app.color.status_success');
      case CollaborationRecordStatus.FAILED:
      case CollaborationRecordStatus.OFFLINE:
      case CollaborationRecordStatus.TIMEOUT:
        return $r('app.color.status_error');
      default:
        return $r('app.color.text_secondary');
    }
  }

  build() {
    if (!this.hasRecord) {
      Column() {
        Text($r('app.string.collaboration_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .id('collaboration-detail-placeholder')
      .width('100%')
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(8)
    } else {
      Column({ space: 12 }) {
        Text(this.record.question)
          .id('collaboration-detail-question')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Row() {
          Text('来源')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(48)
          Text(this.record.sourceDeviceName)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row() {
          Text('目标')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(48)
          Text(this.record.targetDeviceName)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row() {
          Text('状态')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(48)
          Text(this.statusLabel(this.record.status))
            .fontSize(13)
            .fontColor(this.statusColor(this.record.status))
            .layoutWeight(1)
        }
        .width('100%')

        if (this.record.summary.length > 0) {
          Text('摘要')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text(this.record.summary)
            .id('collaboration-detail-summary')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }

        if (this.record.evidenceCount > 0) {
          Text('证据数量：' + this.record.evidenceCount.toString())
            .id('collaboration-detail-evidence')
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .width('100%')
        }

        if (this.record.errorMessage.length > 0) {
          Column({ space: 4 }) {
            Text('错误')
              .fontSize(12)
              .fontColor($r('app.color.status_error'))
            Text(this.record.errorMessage)
              .id('collaboration-detail-error')
              .fontSize(13)
              .fontColor($r('app.color.status_error'))
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.error_surface'))
          .borderRadius(8)
        }

        Row({ space: 8 }) {
          Button($r('app.string.collaboration_continue_query'))
            .id('collaboration-continue-button')
            .layoutWeight(1)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .onClick(() => this.onContinue(this.record.id))
          if (this.canRetry(this.record.status)) {
            Button($r('app.string.collaboration_retry'))
              .id('collaboration-retry-button')
              .layoutWeight(1)
              .backgroundColor($r('app.color.surface_muted'))
              .fontColor($r('app.color.text_primary'))
              .onClick(() => this.onRetry(this.record.id))
          }
        }
        .width('100%')

        Button($r('app.string.collaboration_back_to_list'))
          .id('collaboration-back-button')
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => this.onBack())
      }
      .id('collaboration-detail')
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(8)
      .alignItems(HorizontalAlign.Start)
    }
  }
}
