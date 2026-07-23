import {
  AppSnapshot,
  ControlChannelState,
  DataChannelState,
  INITIAL_SNAPSHOT,
  PeerStatusSnapshot
} from '../model/AppModels';
import { isPeerAvailable } from '../application/PeerStatusProjection';

export function onlineDeviceSummary(available: number, total: number): string {
  return available.toString() + ' / ' + total.toString() + ' 台设备可用';
}

export function channelStateLabel(state: ControlChannelState | DataChannelState): string {
  switch (state) {
    case 'CONNECTING': return '正在连接';
    case 'BINDING': return '正在绑定';
    case 'READY': return '已就绪';
    case 'FAILED': return '失败';
    default: return '未连接';
  }
}

export function peerConnectionLabel(peer: PeerStatusSnapshot): string {
  if (peer.failureCode.length > 0 || peer.controlState === 'FAILED' || peer.dataState === 'FAILED') {
    return peer.failureCode.length > 0 ? '连接失败 · ' + peer.failureCode : '连接失败';
  }
  if (isPeerAvailable(peer)) {
    return '已连接';
  }
  if (peer.dataState === 'BINDING') {
    return '正在绑定';
  }
  if (peer.controlState === 'CONNECTING' || peer.dataState === 'CONNECTING') {
    return '正在连接';
  }
  if (peer.controlState === 'READY') {
    return '数据通道未连接';
  }
  if (peer.dataState === 'READY') {
    return '控制通道未连接';
  }
  return '未连接';
}

export function deviceServiceSummary(snapshot: AppSnapshot): string {
  if (snapshot.peerStatuses.length === 0) {
    return '本机可用，未发现远端设备';
  }
  const failures: number = snapshot.peerStatuses.filter((peer: PeerStatusSnapshot): boolean =>
    peer.failureCode.length > 0 || peer.controlState === 'FAILED' || peer.dataState === 'FAILED'
  ).length;
  if (failures > 0) {
    return '部分远端设备连接失败';
  }
  if (snapshot.activePeerCount === snapshot.peerStatuses.length) {
    return '全部已发现设备可用';
  }
  if (snapshot.activePeerCount > 0) {
    return '部分远端设备可用';
  }
  return '远端设备暂不可用';
}

@Component
export struct DeviceOverview {
  @Prop snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  onRefresh: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('设备协同')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button('↻')
          .fontSize(22)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.onRefresh())
      }
      .width('100%')

      this.summaryCard()
      Text('本机设备')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      this.localEntry()
      Text('远端设备')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      ForEach(this.snapshot.peerStatuses, (peer: PeerStatusSnapshot) => {
        this.peerEntry(peer)
      }, (peer: PeerStatusSnapshot) => peer.deviceName + peer.deviceIdMasked)
      if (this.snapshot.peerStatuses.length === 0) {
        Text('暂未发现远端设备')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding(16)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  localEntry() {
    Row({ space: 12 }) {
      Text('▣').fontSize(32).fontColor($r('app.color.accent')).width(44)
      Column({ space: 5 }) {
        Row() {
          Text('本机')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
          Text('可用')
            .fontSize(11)
            .fontColor(Color.White)
            .padding(4)
            .backgroundColor($r('app.color.status_success'))
            .borderRadius(6)
        }
        Text('索引状态：' + this.indexLabel())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(
          '文档 ' + this.snapshot.knowledgeDocumentCount.toString() +
          ' · 分块 ' + this.snapshot.knowledgeChunkCount.toString()
        )
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        if (this.snapshot.knowledgeError.length > 0) {
          Text(this.snapshot.knowledgeError)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
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
  summaryCard() {
    Row() {
      Column({ space: 4 }) {
        Text(onlineDeviceSummary(
          1 + this.snapshot.activePeerCount,
          1 + this.snapshot.peerStatuses.length
        ))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(deviceServiceSummary(this.snapshot))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('▣').fontSize(36).fontColor($r('app.color.accent'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(8)
  }

  @Builder
  peerEntry(peer: PeerStatusSnapshot) {
    Row({ space: 12 }) {
      Text('▣')
        .fontSize(30)
        .fontColor(isPeerAvailable(peer) ? $r('app.color.accent') : $r('app.color.text_secondary'))
        .width(44)
      Column({ space: 5 }) {
        Row() {
          Text(peer.deviceName.length > 0 ? peer.deviceName : peer.deviceIdMasked)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
          Text(peerConnectionLabel(peer))
            .fontSize(12)
            .fontColor(isPeerAvailable(peer) ?
              $r('app.color.status_success') : $r('app.color.text_secondary'))
        }
        Text('控制通道：' + channelStateLabel(peer.controlState))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text('数据通道：' + channelStateLabel(peer.dataState))
          .fontSize(11)
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

  private indexLabel(): string {
    switch (this.snapshot.knowledgeIndexState) {
      case 'BUILDING': return '正在构建';
      case 'READY': return '已就绪';
      case 'ERROR': return '构建失败';
      default: return '未建立';
    }
  }
}
