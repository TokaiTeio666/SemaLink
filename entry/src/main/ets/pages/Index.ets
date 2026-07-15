import { AppError } from '../common/AppError';
import { AppRuntime } from '../runtime/AppRuntime';
import { AppSnapshot, ConnectionState, DeviceRole, INITIAL_SNAPSHOT } from '../model/AppModels';

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

@Entry
@Component
struct Index {
  @State snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  @State question: string = '';
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
    }
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
  metric(label: Resource, value: string, id: string) {
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
      this.snapshot = { ...this.snapshot, error: appError };
    });
  }
}
