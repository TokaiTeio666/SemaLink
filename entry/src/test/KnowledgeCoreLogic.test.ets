import { describe, expect, it } from '@ohos/hypium';
import { normalizeText } from '../main/ets/knowledge/import/TextNormalizer';
import { DocumentChunker } from '../main/ets/knowledge/import/DocumentChunker';
import { KnowledgeDocument } from '../main/ets/knowledge/model/KnowledgeDocument';
import { DocumentChunk } from '../main/ets/knowledge/model/DocumentChunk';
import {
  ReferenceKeywordSearch as KeywordRetrievalEngine
} from './support/ReferenceRetrievalEngine';
import { tokenizeQuery } from '../main/ets/knowledge/retrieval/QueryTokenizer';
import { utf8ByteLength } from '../main/ets/knowledge/payload/Utf8Sizer';
import { L2PayloadBuilder } from '../main/ets/knowledge/payload/L2PayloadBuilder';
import { L1PayloadBuilder } from '../main/ets/knowledge/payload/L1PayloadBuilder';
import { KnowledgeProfileBuilder } from '../main/ets/knowledge/profile/KnowledgeProfileBuilder';
import { LocalKnowledgeQuery, LocalKnowledgeResult } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { KnowledgePayloadValidator } from '../main/ets/contracts/knowledge/KnowledgePayloadValidator';
import { RepositoryStatistics, KnowledgeMetadata } from '../main/ets/knowledge/storage/DocumentRepository';
import { L1KnowledgePayload, L2KnowledgePayload } from '../main/ets/contracts/knowledge/KnowledgePayloadSchemas';
import { KnowledgeRetrievalRequest } from '../main/ets/knowledge/retrieval/RetrievalEngine';

function document(id: string, title: string, tags: string[], text: string): KnowledgeDocument {
  return {
    documentId: id,
    title: title,
    modality: 'text',
    normalizedText: text,
    tags: tags,
    checksum: 'sum-' + id,
    createdAt: 1,
    updatedAt: 1,
    privacyLevel: 'PRIVATE_GROUP'
  };
}

function chunk(id: string, docId: string, index: number, text: string): DocumentChunk {
  return {
    chunkId: id,
    documentId: docId,
    chunkIndex: index,
    text: text,
    summary: text,
    keywords: [],
    startOffset: 0,
    endOffset: text.length,
    updatedAt: 1
  };
}

function query(text: string): KnowledgeRetrievalRequest {
  return {
    queryText: text, topK: 5, privacyLevel: 'LOCAL_ONLY'
  };
}

function legacyQuery(text: string, level: 'L1' | 'L2'): LocalKnowledgeQuery {
  return {
    contractVersion: '1.0', requestId: 'q-' + level, queryText: text, topK: 5,
    requestedLevel: level, maxPayloadBytes: 4096
  };
}

function representativeDocuments(): KnowledgeDocument[] {
  return [
    document('doc-os', '进程与线程', ['操作系统', '并发'], '进程线程区别'),
    document('doc-tcp-stream', 'TCP 字节流与粘包', ['网络', 'TCP'], 'TCP 粘包半包'),
    document('doc-tcp-reliable', 'TCP 可靠传输', ['网络', 'TCP'], '可靠传输确认重传'),
    document('doc-db-tx', '数据库事务', ['数据库', '事务'], '数据库事务 ACID'),
    document('doc-db-index', '数据库索引', ['数据库', '索引'], '数据库索引 B 树'),
    document('doc-stage', 'HarmonyOS Stage 模型', ['HarmonyOS', 'Stage'], 'Stage 模型生命周期'),
    document('doc-testing', '软件测试阶段', ['软件工程', '测试'], '软件测试阶段')
  ];
}

function representativeChunks(): DocumentChunk[] {
  return [
    chunk('chunk-os', 'doc-os', 0, '进程是资源分配单位，线程是调度执行单位，两者存在明确区别。'),
    chunk('chunk-tcp-stream', 'doc-tcp-stream', 0, 'TCP 是字节流协议，多个写入可能发生粘包和半包。'),
    chunk('chunk-tcp-reliable', 'doc-tcp-reliable', 0, 'TCP 通过序列号、确认和重传保证可靠传输。'),
    chunk('chunk-db-tx', 'doc-db-tx', 0, '数据库事务具有原子性、一致性、隔离性和持久性。'),
    chunk('chunk-db-index', 'doc-db-index', 0, '数据库索引通过 B 树等数据结构加速查询。'),
    chunk('chunk-stage', 'doc-stage', 0, 'HarmonyOS Stage 模型统一管理应用组件生命周期。'),
    chunk('chunk-testing', 'doc-testing', 0, '软件测试阶段包括单元、集成、系统和验收测试。')
  ];
}

export default function knowledgeCoreLogicTest() {
  describe('KnowledgeCoreLogic', () => {
    it('normalizes BOM newlines and whitespace while preserving paragraphs', 0, () => {
      expect(normalizeText('\uFEFF  第一段\r\n  内容   A \r\n\r\n 第二段  '))
        .assertEqual('第一段\n内容 A\n\n第二段');
    });

    it('creates deterministic non-empty chunks with valid offsets', 0, () => {
      const text = normalizeText(('进程用于隔离资源，线程负责执行调度。').repeat(80));
      const chunker = new DocumentChunker();
      const first = chunker.chunkDocument('doc-os', text, 1);
      const second = chunker.chunkDocument('doc-os', text, 1);
      expect(first.length > 1).assertTrue();
      expect(first[0].chunkId).assertEqual(second[0].chunkId);
      expect(first[0].text.length <= 700).assertTrue();
      expect(first[0].endOffset > first[0].startOffset).assertTrue();
    });

    it('splits a long document into at least three ordered overlapping chunks', 0, () => {
      const text = normalizeText(('并发程序需要协调进程、线程、锁、条件变量与消息队列，并明确共享状态的所有权。' +
        '网络协议实现还要处理字节流边界、确认、重传、拥塞控制和超时恢复。').repeat(45));
      const chunks = new DocumentChunker().chunkDocument('doc-long', text, 1);
      expect(text.length > 1800).assertTrue();
      expect(chunks.length >= 3).assertTrue();
      for (let index = 0; index < chunks.length; index++) {
        expect(chunks[index].text.length > 0).assertTrue();
        expect(chunks[index].text.length <= 700).assertTrue();
        expect(chunks[index].chunkIndex).assertEqual(index);
        expect(chunks[index].endOffset > chunks[index].startOffset).assertTrue();
        if (index > 0) {
          expect(chunks[index].startOffset < chunks[index - 1].endOffset).assertTrue();
        }
      }
    });

    it('tokenizes Chinese ngrams and English deterministically', 0, () => {
      const tokens = tokenizeQuery('TCP 为什么发生粘包 TCP 123');
      expect(tokens.indexOf('tcp') >= 0).assertTrue();
      expect(tokens.indexOf('粘包') >= 0).assertTrue();
      expect(tokens.indexOf('123') >= 0).assertTrue();
      expect(tokens.indexOf('tcp')).assertEqual(tokens.lastIndexOf('tcp'));
    });

    it('retrieves process and TCP documents with stable score order', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-os', '进程与线程', ['操作系统'], '进程和线程的区别'),
        document('doc-net', 'TCP 字节流', ['网络', 'TCP'], 'TCP 粘包与拆包')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-os', 'doc-os', 0, '进程是资源分配单位，线程是调度执行单位。'),
        chunk('chunk-net', 'doc-net', 0, 'TCP 是字节流协议，多个写入可能出现粘包。')
      ];
      const engine = new KeywordRetrievalEngine();
      const os = engine.search(query('进程和线程有什么区别'), documents, chunks);
      const network = engine.search(query('TCP 为什么发生粘包'), documents, chunks);
      expect(os[0].document.documentId).assertEqual('doc-os');
      expect(network[0].document.documentId).assertEqual('doc-net');
    });

    it('returns no candidates for an unrelated multi-term query', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-db-index', '数据库索引', ['数据库', '索引'], '数据库索引用于加速查询'),
        document('doc-db-tx', '数据库事务', ['数据库', '事务'], '数据库事务具有原子性')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-db-index', 'doc-db-index', 0, '数据库索引通过额外的数据结构加速查询。'),
        chunk('chunk-db-tx', 'doc-db-tx', 0, '数据库事务保证数据一致性。')
      ];

      const results = new KeywordRetrievalEngine().search(
        query('量子引力黑洞蒸发实验数据'), documents, chunks);

      expect(results.length).assertEqual(0);
    });

    it('ranks process and thread document first', 0, () => {
      const results = new KeywordRetrievalEngine().search(query('进程和线程有什么区别'),
        representativeDocuments(), representativeChunks());
      expect(results[0].document.documentId).assertEqual('doc-os');
    });

    it('ranks TCP stream document first for sticky packet query', 0, () => {
      const results = new KeywordRetrievalEngine().search(query('TCP 为什么会发生粘包'),
        representativeDocuments(), representativeChunks());
      expect(results[0].document.documentId).assertEqual('doc-tcp-stream');
    });

    it('ranks transaction document first for database transaction query', 0, () => {
      const results = new KeywordRetrievalEngine().search(query('数据库事务有哪些特性'),
        representativeDocuments(), representativeChunks());
      expect(results[0].document.documentId).assertEqual('doc-db-tx');
    });

    it('keeps single keyword transaction and index searches useful', 0, () => {
      const engine = new KeywordRetrievalEngine();
      const transaction = engine.search(query('事务'), representativeDocuments(), representativeChunks());
      const index = engine.search(query('索引'), representativeDocuments(), representativeChunks());
      expect(transaction[0].document.documentId).assertEqual('doc-db-tx');
      expect(index[0].document.documentId).assertEqual('doc-db-index');
    });

    it('ranks representative domain queries correctly', 0, () => {
      const engine = new KeywordRetrievalEngine();
      expect(engine.search(query('可靠传输'), representativeDocuments(), representativeChunks())[0]
        .document.documentId).assertEqual('doc-tcp-reliable');
      expect(engine.search(query('Stage 模型'), representativeDocuments(), representativeChunks())[0]
        .document.documentId).assertEqual('doc-stage');
      expect(engine.search(query('软件测试阶段'), representativeDocuments(), representativeChunks())[0]
        .document.documentId).assertEqual('doc-testing');
    });

    it('does not retrieve candidates for generic-only terms', 0, () => {
      const results = new KeywordRetrievalEngine().search(query('有哪些数据内容'),
        representativeDocuments(), representativeChunks());
      expect(results.length).assertEqual(0);
    });

    it('retrieves a scheduling paraphrase from discriminating Chinese ngrams', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-scheduling', '进程调度算法', ['操作系统', '调度'], '优先级调度与老化'),
        document('doc-arkts', 'ArkTS 与 ArkUI', ['HarmonyOS', '系统'], '强类型系统')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-scheduling', 'doc-scheduling', 0,
          '优先级调度先运行优先级高的任务，可用老化机制避免低优先级任务长期得不到执行。'),
        chunk('chunk-arkts', 'doc-arkts', 0, 'ArkTS 是 HarmonyOS 应用开发使用的强类型编程语言。')
      ];
      const results = new KeywordRetrievalEngine().search(query('怎样避免低优先级任务一直没有机会运行'),
        documents, chunks);
      expect(results.length > 0).assertTrue();
      expect(results[0].document.documentId).assertEqual('doc-scheduling');
    });

    it('prefers specific time-slice evidence over generic system words', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-scheduling', '进程调度算法', ['操作系统', '调度'], '时间片轮转'),
        document('doc-arkts', 'ArkTS 与 ArkUI', ['HarmonyOS', '系统'], '强类型系统')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-scheduling', 'doc-scheduling', 0, '时间片轮转为每个就绪任务分配固定时间片，适合交互系统。'),
        chunk('chunk-arkts', 'doc-arkts', 0, '严格类型有助于在编译阶段发现不安全的数据流。')
      ];
      const results = new KeywordRetrievalEngine().search(query('时间片轮转适合什么类型的系统'), documents, chunks);
      expect(results.length > 0).assertTrue();
      expect(results[0].document.documentId).assertEqual('doc-scheduling');
    });

    it('retrieves a noisy transaction query without weakening unrelated rejection', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-tx', '数据库事务', ['数据库', '事务'], '隔离级别'),
        document('doc-index', '数据库索引', ['数据库', '索引'], '查询优化')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-tx', 'doc-tx', 0, '隔离级别应根据脏读、不可重复读和幻读风险选择。'),
        chunk('chunk-index', 'doc-index', 0, '查询优化器根据统计信息选择全表扫描或索引访问。')
      ];
      const engine = new KeywordRetrievalEngine();
      const results = engine.search(query('暂不讨论索引，如何按脏读、不可重复读和幻读风险选择隔离强度？'),
        documents, chunks);
      expect(results.length > 0).assertTrue();
      expect(results[0].document.documentId).assertEqual('doc-tx');
      expect(engine.search(query('量子引力黑洞蒸发实验数据'), documents, chunks).length).assertEqual(0);
    });

    it('uses separated process and thread concepts in a long paraphrase', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-process', '进程与线程', ['操作系统', '并发'], '进程线程'),
        document('doc-other', '并发工程', ['工程'], '并发')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-process', 'doc-process', 0,
          '进程强调资源隔离，线程是处理器调度和执行的基本单位。'),
        chunk('chunk-other', 'doc-other', 0, '任务执行需要工程边界和恢复策略。')
      ];
      const results = new KeywordRetrievalEngine().search(
        query('为什么说任务隔离通常由进程承担，而执行调度落在线程上？'), documents, chunks);
      expect(results.length > 0).assertTrue();
      expect(results[0].document.documentId).assertEqual('doc-process');
    });

    it('uses heap coverage to distinguish a process document from a broad concurrency document', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-process', '进程与线程', ['操作系统'], '线程共享堆和文件'),
        document('doc-concurrency', '操作系统并发工程', ['操作系统', '并发'], '共享文件')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-process', 'doc-process', 0, '同一进程内的线程共享代码、堆和打开的文件。'),
        chunk('chunk-concurrency', 'doc-concurrency', 0, '并发执行单元共享文件描述符并需要明确资源所有权。')
      ];
      const results = new KeywordRetrievalEngine().search(
        query('部署开销先不谈，同一个程序里的执行单元怎样共享堆和文件？'), documents, chunks);
      expect(results.length > 0).assertTrue();
      expect(results[0].document.documentId).assertEqual('doc-process');
    });

    it('combines static typing and page boundary concepts across document paragraphs', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-arkts', 'ArkTS 与 ArkUI', ['HarmonyOS', 'ArkTS'], '强类型页面边界'),
        document('doc-stage', 'HarmonyOS Stage 模型', ['HarmonyOS', 'Stage'], '页面生命周期')
      ];
      const chunks: DocumentChunk[] = [
        chunk('chunk-arkts', 'doc-arkts', 0,
          'ArkTS 是强类型编程语言，严格类型有助于编译阶段检查。业务服务与持久化逻辑应和页面保持清晰边界。'),
        chunk('chunk-stage', 'doc-stage', 0, '页面加载在 UIAbility 生命周期中完成。')
      ];
      const results = new KeywordRetrievalEngine().search(
        query('静态类型检查与页面业务边界为什么都重要？'), documents, chunks);
      expect(results.length > 0).assertTrue();
      expect(results[0].document.documentId).assertEqual('doc-arkts');
    });

    it('records internal match evidence without changing deterministic order', 0, () => {
      const engine = new KeywordRetrievalEngine();
      const first = engine.search(query('TCP 为什么会发生粘包'), representativeDocuments(), representativeChunks());
      const second = engine.search(query('TCP 为什么会发生粘包'), representativeDocuments(), representativeChunks());
      expect(first[0].matchedPrimaryTerms.length >= 2).assertTrue();
      expect(first[0].matchedNgrams.length > 0).assertTrue();
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
    });

    it('measures ASCII Chinese and emoji UTF-8 bytes', 0, () => {
      expect(utf8ByteLength('abc')).assertEqual(3);
      expect(utf8ByteLength('中文')).assertEqual(6);
      expect(utf8ByteLength('😀')).assertEqual(4);
    });

    it('builds legal budgeted L2 JSON', 0, () => {
      const doc = document('doc-net', 'TCP 字节流', ['网络'], 'TCP 粘包');
      const candidates = new KeywordRetrievalEngine().search(query('TCP 粘包'), [doc], [
        chunk('chunk-net', 'doc-net', 0, ('TCP 粘包需要应用层进行消息定界。').repeat(80))
      ]);
      const result = new L2PayloadBuilder().build(candidates, 1024);
      expect(utf8ByteLength(result.payloadJson) <= 1024).assertTrue();
      expect(result.truncated).assertTrue();
    });

    it('aggregates L1 candidates by document', 0, () => {
      const doc = document('doc-os', '进程与线程', ['操作系统'], '进程线程');
      const candidates = new KeywordRetrievalEngine().search(query('进程和线程'), [doc], [
        chunk('chunk-1', 'doc-os', 0, '进程负责资源隔离，线程负责执行。'),
        chunk('chunk-2', 'doc-os', 1, '线程共享进程资源。')
      ]);
      const result = new L1PayloadBuilder().build(candidates, 4096);
      expect(result.itemCount).assertEqual(1);
    });

    it('keeps L1 document-level while L2 exposes multiple matching chunks', 0, () => {
      const doc = document('doc-os-long', '进程与线程并发协作', ['操作系统', '并发'], '进程线程并发');
      const candidates = new KeywordRetrievalEngine().search(query('进程和线程并发'), [doc], [
        chunk('chunk-resource', 'doc-os-long', 0, '进程提供资源隔离和独立地址空间。进程切换需要保存更多上下文。'),
        chunk('chunk-execution', 'doc-os-long', 1, '线程共享所属进程的资源。线程是并发执行和调度的基本单位。')
      ]);
      const l1 = new L1PayloadBuilder().build(candidates, 4096);
      const l2 = new L2PayloadBuilder().build(candidates, 4096);
      const l1Payload = JSON.parse(l1.payloadJson) as L1KnowledgePayload;
      const l2Payload = JSON.parse(l2.payloadJson) as L2KnowledgePayload;

      expect(l1.itemCount).assertEqual(1);
      expect(l2.itemCount).assertEqual(2);
      expect(l1.payloadJson === l2.payloadJson).assertFalse();
      expect(l1Payload.items[0].summary.indexOf('资源隔离') >= 0).assertTrue();
      expect(l1Payload.items[0].summary.indexOf('共享') >= 0).assertTrue();
      expect(l1Payload.items[0].summary.length <
        l2Payload.items[0].snippet.length + l2Payload.items[1].snippet.length).assertTrue();
      expect(l1Payload.items[0].summary.length <= 300).assertTrue();
      expect(l2Payload.items[0].snippet.length <= 1500).assertTrue();

      const l1Request = legacyQuery('进程和线程并发', 'L1');
      const l2Request = legacyQuery('进程和线程并发', 'L2');
      const l1Result: LocalKnowledgeResult = {
        contractVersion: '1.0', requestId: l1Request.requestId, level: 'L1', itemCount: l1.itemCount,
        payloadJson: l1.payloadJson, truncated: l1.truncated, retrievalMs: 0,
        indexVersion: 'index-test', generatedAt: 1
      };
      const l2Result: LocalKnowledgeResult = {
        contractVersion: '1.0', requestId: l2Request.requestId, level: 'L2', itemCount: l2.itemCount,
        payloadJson: l2.payloadJson, truncated: l2.truncated, retrievalMs: 0,
        indexVersion: 'index-test', generatedAt: 1
      };
      const validator = new KnowledgePayloadValidator();
      validator.validateResult(l1Request, l1Result);
      validator.validateResult(l2Request, l2Result);
    });

    it('applies document filters before Top-K', 0, () => {
      const documents: KnowledgeDocument[] = [
        document('doc-os', '进程线程', ['操作系统'], '进程线程'),
        document('doc-net', '进程通信网络', ['网络'], '进程通信')
      ];
      const request = query('进程通信');
      request.filters = { documentIds: ['doc-net'] };
      const candidates = new KeywordRetrievalEngine().search(request, documents, [
        chunk('chunk-os', 'doc-os', 0, '进程通信'), chunk('chunk-net', 'doc-net', 0, '进程通信网络')
      ]);
      expect(candidates[0].document.documentId).assertEqual('doc-net');
    });

    it('builds keyword-only READY profile with weighted domains', 0, () => {
      const statistics: RepositoryStatistics = {
        documentCount: 2,
        chunkCount: 3,
        modalities: ['text'],
        domainCounts: [{ tag: '操作系统', documentCount: 2 }, { tag: '网络', documentCount: 1 }]
      };
      const metadata: KnowledgeMetadata = {
        indexState: 'READY', indexVersion: 'index-1', profileVersion: 'profile-1', updatedAt: 1
      };
      const profile = new KnowledgeProfileBuilder().buildProfile(statistics, metadata);
      expect(profile.retrievalModes[0]).assertEqual('keyword');
      expect(profile.embeddingModelVersion).assertEqual('');
      expect(profile.knowledgeDomains[0].weight).assertEqual(1);
    });
  });
}
