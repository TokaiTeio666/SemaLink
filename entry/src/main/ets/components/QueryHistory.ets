import { AppSnapshot, INITIAL_SNAPSHOT } from '../model/AppModels';
import { CollaborationRecord, CollaborationRecordStatus } from '../collaboration/CollaborationModels';

export type HistoryFilter = 'ALL' | 'SUCCESS' | 'INSUFFICIENT' | 'NO_RESULT' | 'OFFLINE';
interface HistoryFilterOption {
  key: string;
  label: string;
}

export function historyStatusLabel(status: CollaborationRecordStatus): string {
  switch (status) {
    case CollaborationRecordStatus.SYNCED: return '查询成功';
    case CollaborationRecordStatus.FAILED:
    case CollaborationRecordStatus.TIMEOUT: return '证据不足';
    case CollaborationRecordStatus.OFFLINE: return '设备离线';
    default: return '查询中';
  }
}

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
    Column({ space: 12 }) {
      Row() {
        Text('查询历史').fontSize(22).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text('⌕').fontSize(28).fontColor($r('app.color.text_primary'))
        Text('▥').fontSize(24).fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      Row({ space: 4 }) {
        ForEach([
          { key: 'ALL', label: '全部' },
          { key: 'SUCCESS', label: '成功' },
          { key: 'INSUFFICIENT', label: '证据不足' },
          { key: 'NO_RESULT', label: '无结果' },
          { key: 'OFFLINE', label: '设备离线' }
        ], (item: HistoryFilterOption) => {
          Button(item.label)
            .fontSize(10)
            .layoutWeight(1)
            .backgroundColor(this.filter === item.key ? $r('app.color.accent') : $r('app.color.surface_muted'))
            .fontColor(this.filter === item.key ? Color.White : $r('app.color.text_primary'))
            .onClick(() => this.filter = item.key as HistoryFilter)
        }, (item: HistoryFilterOption) => item.key)
      }
      .width('100%')
      Text('今天').fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      ForEach(this.filteredRecords(), (record: CollaborationRecord) => {
        this.recordItem(record)
      }, (record: CollaborationRecord) => record.id)
      if (this.filteredRecords().length === 0) {
        Text('当前筛选条件下暂无记录')
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
      Row() {
        Text(this.statusIcon(record)).fontSize(16).fontColor(this.statusColor(record))
        Text(record.question).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(1)
        Text(this.timeLabel(record.createdAt)).fontSize(11).fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(this.detailLabel(record)).fontSize(12).fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row() {
        Text(historyStatusLabel(record.status)).fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Text(this.confidenceLabel(record)).fontSize(12).fontColor(this.statusColor(record))
        Text('›').fontSize(20).fontColor($r('app.color.text_secondary'))
      }.width('100%')
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
      Text('记录详情').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(record.summary.length > 0 ? record.summary : '暂无答案摘要')
        .fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
      Text('状态：' + historyStatusLabel(record.status)).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text('来源：' + this.sourceNames(record)).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text('证据：' + record.evidenceCount.toString() + ' 条').fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .width('100%').padding(14).backgroundColor($r('app.color.surface_muted')).borderRadius(8)
  }

  private statusIcon(record: CollaborationRecord): string {
    return record.status === CollaborationRecordStatus.SYNCED ? '✓' : '○';
  }

  private statusColor(record: CollaborationRecord) {
    if (record.status === CollaborationRecordStatus.SYNCED) {
      return $r('app.color.status_success');
    }
    if (record.status === CollaborationRecordStatus.FAILED || record.status === CollaborationRecordStatus.TIMEOUT) {
      return $r('app.color.status_warning');
    }
    return $r('app.color.text_secondary');
  }

  private detailLabel(record: CollaborationRecord): string {
    const source: string = this.sourceNames(record);
    if (record.status === CollaborationRecordStatus.SYNCED) {
      return '高可信度 · ' + source + ' · 查询成功';
    }
    if (record.status === CollaborationRecordStatus.OFFLINE) {
      return '设备离线 · 查询失败';
    }
    return '证据不足 · ' + source + ' · 部分匹配';
  }

  private confidenceLabel(record: CollaborationRecord): string {
    if (record.evidenceCount <= 0) {
      return '—';
    }
    return Math.min(99, 60 + record.evidenceCount * 7).toString() + '%';
  }

  private timeLabel(timestamp: number): string {
    const date: Date = new Date(timestamp);
    const hours: string = date.getHours().toString().padStart(2, '0');
    const minutes: string = date.getMinutes().toString().padStart(2, '0');
    return hours + ':' + minutes;
  }
}
