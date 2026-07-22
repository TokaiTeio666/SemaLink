import { AppSnapshot, INITIAL_SNAPSHOT } from '../model/AppModels';
import { CollaborationRecord, CollaborationRecordStatus } from '../collaboration/CollaborationModels';

export type HistoryFilter = 'ALL' | 'SUCCESS' | 'INSUFFICIENT' | 'NO_RESULT' | 'OFFLINE';

export function historyMatchesFilter(record: CollaborationRecord, filter: HistoryFilter): boolean {
  switch (filter) {
    case 'SUCCESS': return record.status === CollaborationRecordStatus.SYNCED && record.evidenceCount > 0;
    case 'INSUFFICIENT': return record.status === CollaborationRecordStatus.FAILED ||
      record.status === CollaborationRecordStatus.TIMEOUT;
    case 'NO_RESULT': return record.status === CollaborationRecordStatus.SYNCED && record.evidenceCount === 0;
    case 'OFFLINE': return record.status === CollaborationRecordStatus.OFFLINE;
    default: return true;
  }
}

@Component
export struct QueryHistory {
  @Prop snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  @State filter: HistoryFilter = 'ALL';
  @State selectedId: string = '';
  onSelected: (id: string) => void = () => {};

  build() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text('History').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('Review automatic query outcomes and sources').fontSize(13).fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(this.snapshot.collaborationRecords.length.toString() + ' records')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Row({ space: 4 }) {
        ForEach(['ALL', 'SUCCESS', 'INSUFFICIENT', 'NO_RESULT', 'OFFLINE'], (value: string) => {
          Button(value)
            .fontSize(10)
            .layoutWeight(1)
            .backgroundColor(this.filter === value ? $r('app.color.accent') : $r('app.color.surface_muted'))
            .fontColor(this.filter === value ? Color.White : $r('app.color.text_primary'))
            .onClick(() => this.filter = value as HistoryFilter)
        }, (value: string) => value)
      }
      .width('100%')
      ForEach(this.filteredRecords(), (record: CollaborationRecord) => {
        this.recordItem(record)
      }, (record: CollaborationRecord) => record.id)
      if (this.filteredRecords().length === 0) {
        Text('No records for this filter.')
          .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding(16)
      }
      if (this.selectedId.length > 0) {
        if (this.selectedRecord() !== undefined) {
          this.detail(this.selectedRecord() as CollaborationRecord);
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private filteredRecords(): CollaborationRecord[] {
    return this.snapshot.collaborationRecords.filter((record: CollaborationRecord): boolean =>
      historyMatchesFilter(record, this.filter));
  }

  @Builder
  recordItem(record: CollaborationRecord) {
    Column({ space: 6 }) {
      Text(record.question).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('Sources: ' + this.sourceNames(record)).fontSize(12).fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row() {
        Text(record.status).fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Text(record.evidenceCount.toString() + ' evidence').fontSize(11).fontColor($r('app.color.accent'))
      }
      .width('100%')
    }
    .width('100%').padding(14).backgroundColor($r('app.color.surface')).borderRadius(8)
    .onClick(() => {
      this.selectedId = record.id;
      this.onSelected(record.id);
    })
  }

  private sourceNames(record: CollaborationRecord): string {
    const names: string[] = record.sourceDeviceNames ?? [];
    return names.length > 0 ? names.join(', ') : record.targetDeviceName;
  }

  private selectedRecord(): CollaborationRecord | undefined {
    return this.snapshot.collaborationRecords.find(
      (record: CollaborationRecord): boolean => record.id === this.selectedId);
  }

  @Builder
  detail(record: CollaborationRecord) {
    Column({ space: 8 }) {
      Text('Record detail').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(record.summary.length > 0 ? record.summary : 'No summary available')
        .fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
      Text('Status: ' + record.status).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text('Sources: ' + this.sourceNames(record)).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text('Evidence: ' + record.evidenceCount.toString()).fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .width('100%').padding(14).backgroundColor($r('app.color.surface_muted')).borderRadius(8)
  }
}
