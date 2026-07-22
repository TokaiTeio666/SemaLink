import { CollaborationRecord, CollaborationRecordStatus } from '../collaboration/CollaborationModels';

/**
 * Renders the cross-device collaboration history list. The component is a pure UI surface:
 * it receives records and the current selection id from the parent and reports selection
 * changes through the onSelected callback. It never calls AppRuntime or SessionManager.
 *
 * Contract:
 * - records: newest-first collaboration records to render.
 * - selectedId: the currently selected record id (may be empty).
 * - onSelected: invoked with the record id when the user taps an item.
 */
@Component
export struct CollaborationRecordList {
  @Prop records: Array<CollaborationRecord> = [];
  @Prop selectedId: string = '';
  onSelected: (id: string) => void = () => {};

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

  private formatTime(timestamp: number): string {
    if (timestamp === 0) {
      return '';
    }
    const date: Date = new Date(timestamp);
    const hours: number = date.getHours();
    const minutes: number = date.getMinutes();
    const hourStr: string = hours < 10 ? '0' + hours.toString() : hours.toString();
    const minuteStr: string = minutes < 10 ? '0' + minutes.toString() : minutes.toString();
    return (date.getMonth() + 1).toString() + '/' + date.getDate().toString() + ' ' + hourStr + ':' + minuteStr;
  }

  build() {
    if (this.records.length === 0) {
      Column() {
        Text($r('app.string.collaboration_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .id('collaboration-list-empty')
      .width('100%')
      .padding(20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(8)
    } else {
      Column({ space: 8 }) {
        ForEach(this.records, (record: CollaborationRecord) => {
          this.recordItem(record)
        }, (record: CollaborationRecord) => record.id)
      }
      .id('collaboration-list')
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  recordItem(record: CollaborationRecord) {
    Column({ space: 4 }) {
      Text(record.question)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        Text(record.sourceDeviceName + ' → ' + record.targetDeviceName)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.statusLabel(record.status))
          .fontSize(11)
          .fontColor(this.statusColor(record.status))
      }
      .width('100%')

      Row() {
        Text(this.formatTime(record.createdAt))
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (record.evidenceCount > 0) {
          Text('证据 ' + record.evidenceCount.toString())
            .fontSize(10)
            .fontColor($r('app.color.accent'))
        }
      }
      .width('100%')
    }
    .id('collaboration-record-' + record.id)
    .width('100%')
    .padding(12)
    .backgroundColor(record.id === this.selectedId ?
      $r('app.color.surface_muted') : $r('app.color.surface'))
    .border({
      width: record.id === this.selectedId ? 1 : 0,
      color: $r('app.color.accent')
    })
    .borderRadius(8)
    .onClick(() => this.onSelected(record.id))
  }
}
