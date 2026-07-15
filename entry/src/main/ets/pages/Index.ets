import { common } from '@kit.AbilityKit';
import { KnowledgeApplicationService } from '../application/KnowledgeApplicationService';
import {
  beginQueryState,
  DisplayKnowledgeItem,
  failQueryState,
  initialQueryState,
  KnowledgeQueryDisplayState,
  succeedQueryState
} from '../application/KnowledgeQueryDisplayState';
import { KnowledgeError } from '../contracts/knowledge/KnowledgeError';
import {
  KnowledgePayloadLevel,
  KnowledgeProfile,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from '../contracts/knowledge/KnowledgeModels';
import { L1KnowledgePayload, L2KnowledgePayload } from '../contracts/knowledge/KnowledgePayloadSchemas';

@Entry
@Component
struct Index {
  private readonly service: KnowledgeApplicationService = new KnowledgeApplicationService();
  @State private loading: boolean = true;
  @State private operationText: string = '正在初始化';
  @State private queryText: string = '进程和线程有什么区别';
  @State private topKText: string = '5';
  @State private budgetText: string = '4096';
  @State private level: KnowledgePayloadLevel = 'L1';
  @State private indexState: string = 'EMPTY';
  @State private documentCount: number = 0;
  @State private chunkCount: number = 0;
  @State private domains: string = '-';
  @State private indexVersion: string = 'index-empty';
  @State private profileVersion: string = 'profile-empty';
  @State private retrievalSummary: string = '尚未查询';
  @State private results: DisplayKnowledgeItem[] = [];
  @State private errorText: string = '';

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    this.loading = true;
    this.operationText = '正在初始化';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await this.service.initialize(context);
      await this.refreshProfile();
    } catch (error) {
      this.results = [];
      this.retrievalSummary = '初始化失败';
      this.showError(error);
    } finally {
      this.loading = false;
      this.operationText = '';
    }
  }

  private async importDocuments(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.operationText = '正在导入';
    this.errorText = '';
    try {
      const report = await this.service.importBuiltInDocuments();
      this.retrievalSummary = '导入 ' + report.importedDocuments.toString() + '，跳过 ' +
        report.skippedDocuments.toString() + '，新增分块 ' + report.createdChunks.toString();
      await this.refreshProfile();
    } catch (error) {
      this.results = [];
      this.retrievalSummary = '导入失败';
      this.showError(error);
    } finally {
      this.loading = false;
      this.operationText = '';
    }
  }

  private async selectAndImportDocuments(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.operationText = '正在导入';
    this.errorText = '';
    try {
      const report = await this.service.selectAndImportTextDocuments();
      this.retrievalSummary = '导入 ' + report.importedDocuments.toString() + '，跳过 ' +
        report.skippedDocuments.toString() + '，失败 ' + report.failedDocuments.toString() +
        '，新增分块 ' + report.createdChunks.toString();
      await this.refreshProfile();
    } catch (error) {
      this.results = [];
      this.retrievalSummary = '导入失败';
      this.showError(error);
    } finally {
      this.loading = false;
      this.operationText = '';
    }
  }

  private async clearKnowledge(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.operationText = '正在清空';
    try {
      await this.service.clearKnowledgeBase();
      this.results = [];
      this.retrievalSummary = '知识库已清空';
      await this.refreshProfile();
    } catch (error) {
      this.results = [];
      this.retrievalSummary = '清空失败';
      this.showError(error);
    } finally {
      this.loading = false;
      this.operationText = '';
    }
  }

  private async runQuery(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.operationText = '正在查询';
    this.applyQueryState(beginQueryState(this.currentQueryState()));
    try {
      const request: LocalKnowledgeQuery = {
        contractVersion: '1.0',
        requestId: 'local-' + Date.now().toString(),
        queryText: this.queryText,
        topK: Number.parseInt(this.topKText),
        requestedLevel: this.level,
        maxPayloadBytes: Number.parseInt(this.budgetText)
      };
      const result = await this.service.query(request);
      this.applyQueryState(succeedQueryState(this.toDisplayItems(result), result.retrievalMs, result.truncated));
    } catch (error) {
      if (error instanceof KnowledgeError) {
        this.applyQueryState(failQueryState(this.currentQueryState(), error.code, error.message));
      } else {
        this.applyQueryState(failQueryState(this.currentQueryState(), 'E_RETRIEVAL_FAILED', '操作失败'));
      }
    } finally {
      this.loading = false;
      this.operationText = '';
    }
  }

  private async refreshProfile(): Promise<void> {
    const profile: KnowledgeProfile = await this.service.getKnowledgeProfile();
    this.indexState = profile.indexState;
    this.documentCount = profile.documentCount;
    this.chunkCount = profile.chunkCount;
    const labels: string[] = [];
    for (const domain of profile.knowledgeDomains) {
      labels.push(domain.tag + ' ' + domain.weight.toFixed(2));
    }
    this.domains = labels.length === 0 ? '-' : labels.join(' · ');
    this.indexVersion = profile.indexVersion;
    this.profileVersion = profile.profileVersion;
  }

  private async refreshProfileAction(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.operationText = '正在刷新画像';
    this.errorText = '';
    try {
      await this.refreshProfile();
      this.retrievalSummary = '知识画像已刷新';
    } catch (error) {
      this.results = [];
      this.retrievalSummary = '刷新画像失败';
      this.showError(error);
    } finally {
      this.loading = false;
      this.operationText = '';
    }
  }

  private toDisplayItems(result: LocalKnowledgeResult): DisplayKnowledgeItem[] {
    const display: DisplayKnowledgeItem[] = [];
    if (result.level === 'L1') {
      const payload = JSON.parse(result.payloadJson) as L1KnowledgePayload;
      for (const item of payload.items) {
        display.push({
          title: item.title,
          relevance: item.relevance,
          content: item.summary,
          kind: '摘要',
          chunkLabel: ''
        });
      }
    } else {
      const payload = JSON.parse(result.payloadJson) as L2KnowledgePayload;
      for (const item of payload.items) {
        display.push({
          title: item.title,
          relevance: item.relevance,
          content: item.snippet,
          kind: '命中段落',
          chunkLabel: this.safeChunkLabel(item.chunkId)
        });
      }
    }
    return display;
  }

  private currentQueryState(): KnowledgeQueryDisplayState {
    const base = initialQueryState();
    return {
      status: base.status,
      summary: this.retrievalSummary,
      errorText: this.errorText,
      items: this.results
    };
  }

  private applyQueryState(state: KnowledgeQueryDisplayState): void {
    this.retrievalSummary = state.summary;
    this.errorText = state.errorText;
    this.results = state.items;
  }

  private safeChunkLabel(chunkId: string): string {
    const suffixLength: number = Math.min(8, chunkId.length);
    return '分块 …' + chunkId.substring(chunkId.length - suffixLength);
  }

  private showError(error: Error): void {
    if (error instanceof KnowledgeError) {
      this.errorText = error.code + ': ' + error.message;
    } else {
      this.errorText = 'E_RETRIEVAL_FAILED: 操作失败';
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('SemaLink Local Knowledge').fontSize(24).fontWeight(FontWeight.Bold)
        Text('状态 ' + this.indexState + ' · 文档 ' + this.documentCount.toString() +
          ' · 分块 ' + this.chunkCount.toString()).fontSize(16)
        Text('领域：' + this.domains).fontSize(13).fontColor('#555555')
        Text('索引：' + this.indexVersion + '\n画像：' + this.profileVersion).fontSize(12).fontColor('#777777')
        Row({ space: 8 }) {
          Button('导入内置文档').onClick((): void => { this.importDocuments(); }).enabled(!this.loading)
          Button('选择 TXT/MD').onClick((): void => { this.selectAndImportDocuments(); }).enabled(!this.loading)
          Button('清空').onClick((): void => { this.clearKnowledge(); }).enabled(!this.loading)
        }
        TextInput({ text: this.queryText, placeholder: '输入本地知识问题' })
          .onChange((value: string): void => { this.queryText = value; })
        Row({ space: 8 }) {
          TextInput({ text: this.topKText, placeholder: 'Top-K' }).width('30%')
            .type(InputType.Number).onChange((value: string): void => { this.topKText = value; })
          TextInput({ text: this.budgetText, placeholder: '字节预算' }).width('40%')
            .type(InputType.Number).onChange((value: string): void => { this.budgetText = value; })
          Button(this.level).onClick((): void => { this.level = this.level === 'L1' ? 'L2' : 'L1'; })
        }
        Button(this.loading ? this.operationText : '执行查询').width('100%')
          .onClick((): void => { this.runQuery(); }).enabled(!this.loading)
        Button('刷新知识画像').width('100%').onClick((): void => {
          this.refreshProfileAction();
        }).enabled(!this.loading)
        Text(this.retrievalSummary).fontSize(14).fontColor('#336699')
        if (this.errorText.length > 0) {
          Text(this.errorText).fontSize(14).fontColor(Color.Red)
        }
        ForEach(this.results, (item: DisplayKnowledgeItem) => {
          Column({ space: 6 }) {
            Text(item.title + ' · ' + item.relevance.toFixed(3)).fontWeight(FontWeight.Bold)
            Text(item.kind + (item.chunkLabel.length > 0 ? ' · ' + item.chunkLabel : ''))
              .fontSize(12).fontColor('#667788')
            Text(item.content).fontSize(14)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .width('100%')
          .backgroundColor('#F4F6F8')
          .borderRadius(8)
        }, (item: DisplayKnowledgeItem): string => item.title + item.content)
      }
      .padding(16)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
