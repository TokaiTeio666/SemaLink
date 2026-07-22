import { AppSnapshot, INITIAL_SNAPSHOT } from '../model/AppModels';
import { AutomaticQueryProgress } from '../application/AutomaticQueryPolicy';

const BUSY_PROGRESS: AutomaticQueryProgress[] = ['ROUTING', 'SEARCHING', 'ANALYZING'];

export function canSubmitAutomaticQuery(snapshot: AppSnapshot, question: string): boolean {
  return BUSY_PROGRESS.indexOf(snapshot.automaticQueryProgress) < 0 &&
    question.trim().length >= 1 && question.trim().length <= 1000;
}

export function progressLabel(progress: AutomaticQueryProgress): string {
  switch (progress) {
    case 'ROUTING': return 'Routing';
    case 'SEARCHING': return 'Searching';
    case 'ANALYZING': return 'Analyzing';
    case 'ANSWER_READY': return 'Answer ready';
    case 'INSUFFICIENT': return 'Insufficient evidence';
    case 'FAILED': return 'Failed';
    default: return 'Ready';
  }
}

@Component
export struct QueryHome {
  @Prop snapshot: AppSnapshot = INITIAL_SNAPSHOT;
  @Prop question: string = '';
  @State expanded: boolean = false;
  onQuestionChange: (value: string) => void = () => {};
  onSubmit: () => void = () => {};
  onCancel: () => void = () => {};
  onRetry: () => void = () => {};

  build() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text('Ask SemaLink')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('Find the best answer across available knowledge sources.')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(this.snapshot.activePeerCount.toString() + ' online')
          .fontSize(12)
          .fontColor($r('app.color.status_success'))
      }
      .width('100%')

      TextArea({ placeholder: 'Ask a question', text: this.question })
        .id('automatic-query-input')
        .height(112)
        .maxLength(1000)
        .onChange((value: string) => this.onQuestionChange(value))

      Row({ space: 8 }) {
        Button('Send')
          .id('automatic-query-send')
          .layoutWeight(1)
          .enabled(canSubmitAutomaticQuery(this.snapshot, this.question))
          .backgroundColor($r('app.color.accent'))
          .fontColor(Color.White)
          .onClick(() => this.onSubmit())
        if (BUSY_PROGRESS.indexOf(this.snapshot.automaticQueryProgress) >= 0) {
          Button('Cancel')
            .id('automatic-query-cancel')
            .layoutWeight(1)
            .backgroundColor($r('app.color.surface_muted'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.onCancel())
        }
      }
      .width('100%')

      Column({ space: 8 }) {
        Row() {
          Text(progressLabel(this.snapshot.automaticQueryProgress))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Button(this.expanded ? 'Hide steps' : 'Show steps')
            .fontSize(12)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.expanded = !this.expanded)
        }
        if (this.expanded) {
          ForEach(['Routing', 'Searching', 'Analyzing', 'Answer ready'], (step: string) => {
            Row({ space: 8 }) {
              Text(step)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Text(this.stepMarker(step))
                .fontSize(13)
                .fontColor($r('app.color.accent'))
            }
          }, (step: string) => step)
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(8)

      if (this.snapshot.automaticQueryProgress === 'ANSWER_READY' ||
        this.snapshot.automaticQueryProgress === 'INSUFFICIENT') {
        Column({ space: 8 }) {
          Text('Answer summary')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.snapshot.summary.length > 0 ? this.snapshot.summary : 'No summary available')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Row({ space: 16 }) {
            Text('Confidence ' + this.snapshot.taskConfidence.toFixed(2))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text('Coverage ' + this.snapshot.taskCoverage.toFixed(2))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text('Evidence ' + this.snapshot.evidenceSourceDeviceIds.length.toString())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          Text('Sources: ' + this.sourceNames())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          if (this.snapshot.automaticQueryProgress === 'INSUFFICIENT') {
            Button('Retry')
              .width('100%')
              .backgroundColor($r('app.color.surface_muted'))
              .fontColor($r('app.color.text_primary'))
              .onClick(() => this.onRetry())
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(8)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private sourceNames(): string {
    return this.snapshot.automaticSourceNames.length > 0 ?
      this.snapshot.automaticSourceNames.join(', ') : 'Local';
  }

  private stepMarker(step: string): string {
    const active: string = progressLabel(this.snapshot.automaticQueryProgress);
    return step === active ? 'current' : (this.snapshot.automaticQueryProgress === 'ANSWER_READY' ? 'done' : '');
  }
}
