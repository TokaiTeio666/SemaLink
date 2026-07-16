import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit, PrivacyLevel, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { EvidenceUnitFactory } from '../main/ets/knowledge/evidence/EvidenceUnitFactory';
import { DocumentChunk } from '../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../main/ets/knowledge/model/KnowledgeDocument';
import { RetrievalCandidate } from '../main/ets/knowledge/model/RetrievalCandidate';
import { utf8ByteLength } from '../main/ets/knowledge/payload/Utf8Sizer';

function candidate(documentId: string, chunkId: string, chunkIndex: number, privacyLevel: PrivacyLevel,
  relevance: number, text: string = 'Process scheduling uses a priority queue.'): RetrievalCandidate {
  const document: KnowledgeDocument = {
    documentId: documentId, title: 'Process Scheduling', modality: 'text',
    normalizedText: 'full source file:///private/source SQL stack /data/private datashare://source',
    tags: ['Operating System', 'Queue'], checksum: 'sum-' + documentId,
    createdAt: 1, updatedAt: 2, privacyLevel: privacyLevel
  };
  const chunk: DocumentChunk = {
    chunkId: chunkId, documentId: documentId, chunkIndex: chunkIndex, text: text,
    summary: 'Process scheduling summary', keywords: ['process', 'priority queue'],
    startOffset: 0, endOffset: text.length, updatedAt: 2
  };
  return {
    document: document, chunk: chunk, relevance: relevance,
    matchedPrimaryTerms: ['process'], matchedNgrams: ['queue'], exactPhraseMatched: true
  };
}

function task(levels: ('L1' | 'L2')[], privacyLevel: PrivacyLevel,
  requiredConcepts: string[] = ['process', 'priority queue']): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'task-1', queryText: 'process scheduling',
    requiredConcepts: requiredConcepts, requiredConfidence: 0.8, coverageThreshold: 0.6,
    latencyBudgetMs: 1000, byteBudget: 1, privacyLevel: privacyLevel, acceptableLevels: levels
  };
}

export default function evidenceUnitFactoryTest() {
  describe('EvidenceUnitFactory', () => {
    it('builds at most one L1 unit per document with stable parent-ready identifiers', 0, () => {
      const candidates = [
        candidate('doc-a', 'chunk-a-1', 0, 'PRIVATE_GROUP', 0.9),
        candidate('doc-a', 'chunk-a-2', 1, 'PRIVATE_GROUP', 0.8),
        candidate('doc-b', 'chunk-b-1', 0, 'PRIVATE_GROUP', 0.7)
      ];
      const units = new EvidenceUnitFactory().build(candidates, task(['L1'], 'PRIVATE_GROUP'), 'local-device');

      expect(units.length).assertEqual(2);
      expect(units[0].evidenceId).assertEqual('ev-l1-doc-a');
      expect(units[0].evidenceGroupId).assertEqual('doc-doc-a');
      expect(units[0].sourceChunkId === undefined).assertTrue();
      expect(units[0].snippet === undefined).assertTrue();
      expect((units[0].summary?.length || 0) <= 300).assertTrue();
      expect(JSON.stringify(units[0].canEscalateTo)).assertEqual(JSON.stringify(['L2']));
    });

    it('builds one L2 unit per candidate chunk with the L1 parent relationship', 0, () => {
      const units = new EvidenceUnitFactory().build([
        candidate('doc-a', 'chunk-a-1', 0, 'PRIVATE_GROUP', 0.9),
        candidate('doc-a', 'chunk-a-2', 1, 'PRIVATE_GROUP', 0.8)
      ], task(['L2'], 'PRIVATE_GROUP'), 'local-device');

      expect(units.length).assertEqual(2);
      expect(units[0].evidenceId).assertEqual('ev-l2-chunk-a-1');
      expect(units[0].evidenceGroupId).assertEqual('doc-doc-a');
      expect(units[0].parentEvidenceId).assertEqual('ev-l1-doc-a');
      expect(units[0].sourceChunkId).assertEqual('chunk-a-1');
      expect(units[0].summary === undefined).assertTrue();
      expect((units[0].snippet?.length || 0) <= 1500).assertTrue();
      expect(units[0].canEscalateTo.length).assertEqual(0);
    });

    it('keeps input order stable and leaves candidate limiting to retrieval', 0, () => {
      const candidates: RetrievalCandidate[] = [];
      for (let index = 0; index < 25; index++) {
        candidates.push(candidate('doc-' + index.toString(), 'chunk-' + index.toString(), 0,
          'PRIVATE_GROUP', 1 - index / 100));
      }
      const factory = new EvidenceUnitFactory();
      const first = factory.build(candidates, task(['L2'], 'PRIVATE_GROUP'), 'local-device');
      const second = factory.build(candidates, task(['L2'], 'PRIVATE_GROUP'), 'local-device');

      expect(first.length).assertEqual(25);
      expect(first[0].evidenceId).assertEqual('ev-l2-chunk-0');
      expect(first[24].evidenceId).assertEqual('ev-l2-chunk-24');
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
    });

    it('emits both levels in acceptableLevels order with stable order inside each level', 0, () => {
      const candidates = [
        candidate('doc-a', 'chunk-a-1', 0, 'PRIVATE_GROUP', 0.9),
        candidate('doc-a', 'chunk-a-2', 1, 'PRIVATE_GROUP', 0.8),
        candidate('doc-b', 'chunk-b-1', 0, 'PRIVATE_GROUP', 0.7)
      ];
      const l1ThenL2 = new EvidenceUnitFactory().build(candidates,
        task(['L1', 'L2'], 'PRIVATE_GROUP'), 'local-device');
      const l2ThenL1 = new EvidenceUnitFactory().build(candidates,
        task(['L2', 'L1'], 'PRIVATE_GROUP'), 'local-device');

      expect(JSON.stringify(l1ThenL2.map((unit): string => unit.evidenceId))).assertEqual(
        JSON.stringify(['ev-l1-doc-a', 'ev-l1-doc-b', 'ev-l2-chunk-a-1', 'ev-l2-chunk-a-2', 'ev-l2-chunk-b-1']));
      expect(JSON.stringify(l2ThenL1.map((unit): string => unit.evidenceId))).assertEqual(
        JSON.stringify(['ev-l2-chunk-a-1', 'ev-l2-chunk-a-2', 'ev-l2-chunk-b-1', 'ev-l1-doc-a', 'ev-l1-doc-b']));
      expect(l2ThenL1[0].parentEvidenceId).assertEqual('ev-l1-doc-a');
    });

    it('normalizes covered concepts and computes estimated coverage gain', 0, () => {
      const units = new EvidenceUnitFactory().build([
        candidate('doc-a', 'chunk-a', 0, 'PRIVATE_GROUP', 1)
      ], task(['L2'], 'PRIVATE_GROUP', [' PROCESS ', 'Priority Queue', 'missing']), 'local-device');

      expect(JSON.stringify(units[0].coveredConcepts)).assertEqual(JSON.stringify(['process', 'priority queue']));
      expect(units[0].estimatedCoverageGain).assertEqual(2 / 3);
    });

    it('applies the privacy matrix and fixed privacy and energy costs', 0, () => {
      const candidates = [
        candidate('group', 'chunk-group', 0, 'PRIVATE_GROUP', 1.2),
        candidate('local', 'chunk-local', 0, 'LOCAL_ONLY', -0.2)
      ];
      const factory = new EvidenceUnitFactory();
      const localL1 = factory.build(candidates, task(['L1'], 'LOCAL_ONLY'), 'local-device');
      const localL2 = factory.build(candidates, task(['L2'], 'LOCAL_ONLY'), 'local-device');
      const groupL2 = factory.build(candidates, task(['L2'], 'PRIVATE_GROUP'), 'local-device');

      expect(localL1.length).assertEqual(2);
      expect(localL1[0].privacyCost).assertEqual(0.2);
      expect(localL1[1].privacyCost).assertEqual(1);
      expect(localL1[0].energyCost).assertEqual(0.05);
      expect(localL2[0].energyCost).assertEqual(0.1);
      expect(localL2[0].relevance).assertEqual(1);
      expect(localL2[1].relevance).assertEqual(0);
      expect(groupL2.length).assertEqual(1);
      expect(groupL2[0].sourceDocId).assertEqual('group');
      expect(groupL2[0].semanticContractVersion).assertEqual('1.0');
    });

    it('keeps hashes stable and byteCost equal to final UTF-8 JSON including itself', 0, () => {
      const chinese = '中文证据用于验证 UTF-8 字节计数。';
      const factory = new EvidenceUnitFactory();
      const first = factory.build([candidate('zh', 'chunk-zh', 0, 'PRIVATE_GROUP', 0.8, chinese)],
        task(['L2'], 'PRIVATE_GROUP', ['中文证据']), 'local-device')[0];
      const second = factory.build([candidate('zh', 'chunk-zh', 0, 'PRIVATE_GROUP', 0.8, chinese)],
        task(['L2'], 'PRIVATE_GROUP', ['中文证据']), 'local-device')[0];

      expect(first.hash).assertEqual(second.hash);
      expect(first.byteCost).assertEqual(utf8ByteLength(JSON.stringify(first)));
      expect(first.byteCost > JSON.stringify(first).length).assertTrue();
    });

    it('does not apply task byteBudget pruning and returns empty for no candidates', 0, () => {
      const factory = new EvidenceUnitFactory();
      const nonEmpty = factory.build([candidate('doc-a', 'chunk-a', 0, 'PRIVATE_GROUP', 0.8)],
        task(['L2'], 'PRIVATE_GROUP'), 'local-device');
      const empty = factory.build([], task(['L2'], 'PRIVATE_GROUP'), 'local-device');

      expect(nonEmpty.length).assertEqual(1);
      expect(empty.length).assertEqual(0);
    });

    it('preserves legitimate SQL and stack knowledge while removing real paths and URIs', 0, () => {
      const unsafe = 'SQL 查询优化使用执行计划。线程调用栈和技术栈。file:///private/a datashare://b ' +
        '/data/private /home/user/secret /tmp C:\\Users\\owner\\secret.txt \\\\server\\share\\secret.txt';
      const unit: EvidenceUnit = new EvidenceUnitFactory().build([
        candidate('safe', 'chunk-safe', 0, 'PRIVATE_GROUP', 0.8, unsafe)
      ], task(['L2'], 'PRIVATE_GROUP'), 'local-device')[0];
      const json = JSON.stringify(unit).toLowerCase();

      expect(json.includes('file://')).assertFalse();
      expect(json.includes('datashare://')).assertFalse();
      expect(json.includes('/data/')).assertFalse();
      expect(json.includes('/home/')).assertFalse();
      expect(json.includes('/tmp')).assertFalse();
      expect(json.includes('c:\\users\\')).assertFalse();
      expect(json.includes('\\\\server\\')).assertFalse();
      expect(unit.snippet?.includes('SQL 查询优化使用执行计划')).assertTrue();
      expect(unit.snippet?.includes('线程调用栈和技术栈')).assertTrue();
      expect(json.includes('full source')).assertFalse();
    });

    it('never uses internal error messages or stack traces as evidence content', 0, () => {
      const clean = candidate('safe', 'chunk-safe', 0, 'PRIVATE_GROUP', 0.8,
        'SQL 查询优化使用执行计划');
      clean.document.normalizedText = 'Error: query failed at file:///data/private\nstack trace internal';
      const unit = new EvidenceUnitFactory().build([clean],
        task(['L2'], 'PRIVATE_GROUP'), 'local-device')[0];
      const json = JSON.stringify(unit).toLowerCase();

      expect(json.includes('query failed')).assertFalse();
      expect(json.includes('stack trace internal')).assertFalse();
      expect(unit.snippet).assertEqual('SQL 查询优化使用执行计划');
    });

    it('sanitizes identifiers device ids and covered concepts before emitting JSON', 0, () => {
      const unsafeCandidate = candidate('file://SQL-doc', 'datashare://stack-chunk', 0,
        'PRIVATE_GROUP', 0.8);
      unsafeCandidate.document.tags = ['SQL stack'];
      unsafeCandidate.chunk.keywords = ['/data/private'];
      const unit = new EvidenceUnitFactory().build([unsafeCandidate],
        task(['L2'], 'PRIVATE_GROUP', ['SQL stack', '/data/private']), 'file://device-stack')[0];
      const json = JSON.stringify(unit).toLowerCase();

      expect(json.includes('file://')).assertFalse();
      expect(json.includes('datashare://')).assertFalse();
      expect(json.includes('/data/')).assertFalse();
      expect(json.includes('sql stack')).assertTrue();
    });

    it('keeps sanitized identifiers unique for distinct unsafe source ids', 0, () => {
      const units = new EvidenceUnitFactory().build([
        candidate('file://document-a', 'datashare://chunk-a', 0, 'PRIVATE_GROUP', 0.9),
        candidate('file://document-b', 'datashare://chunk-b', 0, 'PRIVATE_GROUP', 0.8)
      ], task(['L2'], 'PRIVATE_GROUP'), 'local-device');

      expect(units.length).assertEqual(2);
      expect(units[0].evidenceId === units[1].evidenceId).assertFalse();
      expect(units[0].sourceDocId === units[1].sourceDocId).assertFalse();
      expect(units[0].sourceChunkId === units[1].sourceChunkId).assertFalse();
    });
  });
}
