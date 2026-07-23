import {
  AppSnapshot,
  AutomaticQueryResultItem,
  INITIAL_SNAPSHOT,
  PeerStatusSnapshot
} from '../model/AppModels';
import { AutomaticQueryProgress } from '../application/AutomaticQueryPolicy';
import { isPeerAvailable } from '../application/PeerStatusProjection';

const BUSY_PROGRESS: AutomaticQueryProgress[] = ['ROUTING', 'SEARCHING', 'ANALYZING'];

export function canSubmitAutomaticQuery(snapshot: AppSnapshot, question: string): boolean {
  return BUSY_PROGRESS.indexOf(snapshot.automaticQueryProgress) < 0 &&
    question.trim().length >= 1 && question.trim().length <= 1000;
}

export function progressLabel(progress: AutomaticQueryProgress): string {
  switch (progress) {
    case 'ROUTING': return '正在路由';
    case 'SEARCHING': return '正在查询';
    case 'ANALYZING': return '正在分析';
    case 'ANSWER_READY': return '结果已就绪';
    case 'INSUFFICIENT': return '证据不足';
    case 'FAILED': return '查询失败';
    default: return '准备查询';
  }
}

export function progressStepIndex(progress: AutomaticQueryProgress): number {
  switch (progress) {
    case 'ROUTING': return 0;
    case 'SEARCHING': return 1;
    case 'ANALYZING': return 2;
    case 'ANSWER_READY': return 4;
    case 'INSUFFICIENT': return 4;
    default: return -1;
  }
}

export function availableDeviceNames(snapshot: AppSnapshot): string[] {
  const names: string[] = ['本机'];
  snapshot.peerStatuses.forEach((peer: PeerStatusSnapshot): void => {
    if (isPeerAvailable(peer)) {
      names.push(peer.deviceName.length > 0 ? peer.deviceName : peer.deviceIdMasked);
    }
  });
  return names;
}

export function queryDeviceStep(snapshot: AppSnapshot): string {
  return '查询' + availableDeviceNames(snapshot).join('、');
}

export function queryDurationLabel(totalTaskMs: number): string {
  if (totalTaskMs <= 0) {
    return '';
  }
  return '总耗时 ' + (totalTaskMs / 1000).toFixed(2) + ' 秒';
}

export function connectionSummary(snapshot: AppSnapshot): string {
  if (snapshot.peerStatuses.length === 0) {
    return '未发现远端设备，当前仅查询本机';
  }
  const failedCount: number = snapshot.peerStatuses.filter((peer: PeerStatusSnapshot): boolean =>
    peer.failureCode.length > 0 || peer.controlState === 'FAILED' || peer.dataState === 'FAILED'
  ).length;
  const connectingCount: number = snapshot.peerStatuses.filter((peer: PeerStatusSnapshot): boolean =>
    peer.controlState === 'CONNECTING' || peer.dataState === 'CONNECTING' || peer.dataState === 'BINDING'
  ).length;
  if (failedCount > 0) {
    return snapshot.activePeerCount.toString() + ' 台远端可用，部分设备连接失败';
  }
  if (connectingCount > 0) {
    return '正在连接远端设备';
  }
  if (snapshot.activePeerCount > 0) {
    return snapshot.activePeerCount.toString() + ' 台远端设备已连接';
  }
  return '远端设备暂不可用';
}

@Component
export struct QueryHome {
  @Prop snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  @Prop question: string = '';
  onQuestionChange: (value: string) => void = () => {};
  onSubmit: () => void = () => {};
  onCancel: () => void = () => {};
  onRetry: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      this.onlineSummary()

      Text('询问所有可用设备中的资料')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        TextArea({ placeholder: '输入要查询的问题', text: this.question })
          .id('automatic-query-input')
          .height(56)
          .maxLength(1000)
          .layoutWeight(1)
          .backgroundColor($r('app.color.surface'))
          .border({ width: 1, color: $r('app.color.border') })
          .borderRadius(8)
          .onChange((value: string) => this.onQuestionChange(value))
        Button('发送')
          .id('automatic-query-send')
          .width(64)
          .height(44)
          .enabled(canSubmitAutomaticQuery(this.snapshot, this.question))
          .backgroundColor($r('app.color.accent'))
          .fontColor(Color.White)
          .onClick(() => this.onSubmit())
      }
      .width('100%')

      this.scopeChips()
      this.progressCard()

      if (this.isTerminal()) {
        this.resultList()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  onlineSummary() {
    Row() {
      Column({ space: 4 }) {
        Text(availableDeviceNames(this.snapshot).length.toString() + ' 台设备可用')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(connectionSummary(this.snapshot))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(8)
  }

  @Builder
  scopeChips() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text('查询范围：')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 8, bottom: 6 })
      ForEach(availableDeviceNames(this.snapshot), (name: string) => {
        Text(name)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .margin({ right: 8, bottom: 6 })
          .backgroundColor($r('app.color.chip_background'))
          .borderRadius(14)
      }, (name: string) => name)
    }
    .width('100%')
  }

  @Builder
  progressCard() {
    Column({ space: 8 }) {
      Row() {
        Text('查询进度')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (BUSY_PROGRESS.indexOf(this.snapshot.automaticQueryProgress) >= 0) {
          Button('取消')
            .fontSize(12)
            .height(28)
            .backgroundColor($r('app.color.surface_muted'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.onCancel())
        }
      }
      ForEach(this.progressSteps(), (step: string, index: number) => {
        Row({ space: 8 }) {
          Text(this.stepIcon(index)).fontSize(14).fontColor(this.stepColor(index))
          Column({ space: 2 }) {
            Text(step).fontSize(13).fontColor($r('app.color.text_primary'))
            Text(this.stepDescription(index)).fontSize(11).fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .height(38)
      }, (step: string) => step)
      if (this.shouldShowDuration() && this.snapshot.totalTaskMs > 0) {
        Text(queryDurationLabel(this.snapshot.totalTaskMs))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(8)
  }

  @Builder
  resultList() {
    Column({ space: 10 }) {
      Text('查询结果')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.snapshot.automaticResultItems.length === 0) {
        Text('未找到足够的相关内容')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      } else {
        ForEach(this.snapshot.automaticResultItems, (item: AutomaticQueryResultItem) => {
          this.resultEntry(item)
        }, (item: AutomaticQueryResultItem) => item.evidenceId)
      }
      if (this.snapshot.automaticQueryProgress === 'INSUFFICIENT') {
        Button('重试查询')
          .width('100%')
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.onRetry())
      }
    }
    .width('100%')
  }

  @Builder
  resultEntry(item: AutomaticQueryResultItem) {
    Column({ space: 8 }) {
      Text(item.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (item.content.length > 0) {
        Text(item.content)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      Row({ space: 8 }) {
        Text(item.sourceName)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text(Math.round(item.relevance * 100).toString() + '% 相关')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text(item.level)
          .fontSize(11)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(8)
  }

  private isTerminal(): boolean {
    return this.snapshot.automaticQueryProgress === 'ANSWER_READY' ||
      this.snapshot.automaticQueryProgress === 'INSUFFICIENT';
  }

  private shouldShowDuration(): boolean {
    return this.isTerminal() || this.snapshot.automaticQueryProgress === 'FAILED';
  }

  private progressSteps(): string[] {
    return ['理解问题', '选择设备', queryDeviceStep(this.snapshot), '分析证据', '整理结果'];
  }

  private stepIcon(index: number): string {
    const current: number = progressStepIndex(this.snapshot.automaticQueryProgress);
    return current >= 0 && index <= current ? '●' : '○';
  }

  private stepColor(index: number) {
    const current: number = progressStepIndex(this.snapshot.automaticQueryProgress);
    if (index === current) {
      return $r('app.color.accent');
    }
    if (current > index) {
      return $r('app.color.status_success');
    }
    return $r('app.color.text_secondary');
  }

  private stepDescription(index: number): string {
    const current: number = progressStepIndex(this.snapshot.automaticQueryProgress);
    if (index < current) {
      return '已完成';
    }
    if (index === current) {
      return '正在处理相关资料...';
    }
    return '等待开始';
  }
}
