import { AppError, ErrorStage } from '../common/AppError';
import { AppRuntime } from '../runtime/AppRuntime';
import { AppSnapshot, INITIAL_SNAPSHOT, PeerStatusSnapshot } from '../model/AppModels';
import { QueryHome, canSubmitAutomaticQuery } from '../components/QueryHome';
import { DeviceOverview } from '../components/DeviceOverview';
import { QueryHistory } from '../components/QueryHistory';

export function canSubmit(snapshot: AppSnapshot, question: string): boolean {
  return canSubmitAutomaticQuery(snapshot, question);
}

export function shouldShowConnect(_snapshot: AppSnapshot): boolean {
  return false;
}

export function semanticTaskStatus(snapshot: AppSnapshot): string {
  return snapshot.automaticQueryProgress;
}

@Entry
@Component
struct Index {
  @State snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  @State question: string = '';
  @State page: string = 'query';
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    this.unsubscribe = AppRuntime.current().store.subscribe((state: AppSnapshot) => {
      this.snapshot = state;
      this.question = state.question;
    });
    this.refreshDevices();
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  build() {
    Column() {
      if (this.page === 'query') {
        this.header()
      }
      Scroll() {
        Column() {
          if (this.page === 'query') {
            QueryHome({
              snapshot: this.snapshot,
              question: this.question,
              onQuestionChange: (value: string) => this.question = value,
              onSubmit: () => this.submitAutomaticQuery(),
              onCancel: () => this.cancelAutomaticQuery(),
              onRetry: () => this.submitAutomaticQuery()
            })
          } else if (this.page === 'devices') {
            DeviceOverview({ snapshot: this.snapshot, onRefresh: () => this.refreshDevices() })
          } else if (this.page === 'history') {
            QueryHistory({ snapshot: this.snapshot, onSelected: (id: string) => this.selectHistory(id) })
          } else {
            this.diagnostics()
          }
          this.errorSection()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      this.bottomNavigation()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 0 })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  header() {
    Row() {
      Text('☰').fontSize(24).fontColor($r('app.color.text_primary')).width(44)
      Text('SemaLink').fontSize(21).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center).layoutWeight(1)
      Text('♧').fontSize(24).fontColor($r('app.color.text_primary')).width(44).textAlign(TextAlign.End)
    }
    .width('100%').height(48).margin({ bottom: 8 })
  }

  @Builder
  bottomNavigation() {
    Row() {
      this.bottomNavButton('query', '⌕', '查询')
      this.bottomNavButton('devices', '▣', '设备')
      this.bottomNavButton('history', '◷', '历史')
    }
    .width('100%').height(68).backgroundColor($r('app.color.surface'))
    .border({ width: { top: 1 }, color: $r('app.color.border') })
  }

  @Builder
  bottomNavButton(value: string, icon: string, label: string) {
    Column({ space: 3 }) {
      Text(icon).fontSize(22)
        .fontColor(this.page === value ? $r('app.color.accent') : $r('app.color.text_secondary'))
      Text(label).fontSize(11)
        .fontColor(this.page === value ? $r('app.color.accent') : $r('app.color.text_secondary'))
    }
    .layoutWeight(1).height(60).justifyContent(FlexAlign.Center)
    .onClick(() => this.page = value)
  }

  @Builder
  diagnostics() {
    Column({ space: 12 }) {
      Text('Diagnostics').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text('Responder and transport diagnostics are kept outside the default query workflow.')
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      Button('Run TLS probe')
        .width('100%')
        .backgroundColor($r('app.color.surface_muted'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => this.runCommand(() => AppRuntime.current().runTlsProbe()))
      Text('Peer statuses: ' + this.snapshot.peerStatuses.length.toString())
        .fontSize(13).fontColor($r('app.color.text_secondary'))
      ForEach(this.snapshot.peerStatuses, (peer: PeerStatusSnapshot) => {
        Text(peer.deviceName + ' / ' + peer.dataState)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }, (peer: PeerStatusSnapshot) => peer.deviceName + peer.deviceIdMasked)
    }
    .width('100%').padding(16).backgroundColor($r('app.color.surface')).borderRadius(8)
  }

  @Builder
  errorSection() {
    if (this.snapshot.error !== undefined) {
      Text(this.snapshot.error.message)
        .fontSize(13).fontColor($r('app.color.status_error')).width('100%').padding(12)
        .backgroundColor($r('app.color.error_surface')).borderRadius(8)
    }
  }

  private submitAutomaticQuery(): void {
    this.runCommand(() => AppRuntime.current().submitAutomaticQuery(this.question.trim()));
  }

  private cancelAutomaticQuery(): void {
    this.runCommand(() => AppRuntime.current().cancelAutomaticQuery());
  }

  private refreshDevices(): void {
    this.runCommand(() => AppRuntime.current().refreshAvailableDevices(true));
  }

  private selectHistory(id: string): void {
    AppRuntime.current().store.update({ selectedCollaborationRecordId: id });
  }

  private runCommand(command: () => Promise<void>): void {
    command().catch((error: Object) => {
      const appError: AppError = error instanceof AppError ? error :
        new AppError('E_UI_COMMAND_FAILED', 'Command failed', ErrorStage.QUERY, true);
      AppRuntime.current().store.update({ error: appError });
    });
  }
}
