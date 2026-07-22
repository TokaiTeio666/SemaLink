import { AppSnapshot, INITIAL_SNAPSHOT, PeerStatusSnapshot } from '../model/AppModels';

@Component
export struct DeviceOverview {
  @Prop snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  onRefresh: () => void = () => {};

  build() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text('Devices')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('Available sources and index readiness')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('Refresh')
          .fontSize(12)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.onRefresh())
      }
      .width('100%')

      this.localEntry()
      ForEach(this.snapshot.peerStatuses, (peer: PeerStatusSnapshot) => {
        this.peerEntry(peer)
      }, (peer: PeerStatusSnapshot) => peer.deviceName + peer.deviceIdMasked)
      if (this.snapshot.peerStatuses.length === 0) {
        Text('No remote devices discovered yet.')
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
    Column({ space: 6 }) {
      Row() {
        Text('This device').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text(this.snapshot.knowledgeIndexState).fontSize(12).fontColor($r('app.color.status_success'))
      }
      Text('Local knowledge index').fontSize(13).fontColor($r('app.color.text_secondary'))
      Text(this.snapshot.knowledgeDocumentCount.toString() + ' documents / ' +
        this.snapshot.knowledgeChunkCount.toString() + ' chunks')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(8)
  }

  @Builder
  peerEntry(peer: PeerStatusSnapshot) {
    Column({ space: 6 }) {
      Row() {
        Text(peer.deviceName.length > 0 ? peer.deviceName : peer.deviceIdMasked)
          .fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text(peer.dataState)
          .fontSize(12)
          .fontColor(peer.dataState === 'READY' ? $r('app.color.status_success') : $r('app.color.text_secondary'))
      }
      Text('Control ' + peer.controlState + ' / Data ' + peer.dataState)
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(peer.evidenceCount.toString() + ' evidence items')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(8)
  }
}
