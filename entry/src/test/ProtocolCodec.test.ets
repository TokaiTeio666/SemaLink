import { describe, expect, it } from '@ohos/hypium';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import { MessageType, ProtocolEnvelope, QueryPayload, ResultPayload, ErrorPayload, QueryAckPayload, ProfilePayload, TaskPayload, TaskAckPayload, EvidencePayload, TsfPayload, CancelPayload, MAX_QUESTION_CHARS, MAX_SUMMARY_CHARS, MAX_MESSAGE_BYTES } from '../main/ets/protocol/ProtocolModels';
import { AppError } from '../main/ets/common/AppError';
import { L2KnowledgePayload } from '../main/ets/contracts/knowledge/KnowledgePayloadSchemas';
import { LocalKnowledgeResult } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { DeviceProfileAdvertisement, TaskRequest, EvidenceUnit, TaskSufficiencyResult } from '../main/ets/contracts/semantic/SemanticModels';

export default function protocolCodecTest(): void {
  describe('ProtocolCodec', () => {
    const codec: ProtocolCodec = new ProtocolCodec();

    it('roundTripsQuery', 0, () => {
      const qPayload: QueryPayload = { question: '测试问题' };
      const envelope: ProtocolEnvelope = {
        version: '1.0', type: MessageType.QUERY, messageId: 'm1', sessionId: 's1',
        requestId: 'r1', sentAt: 1000, payload: qPayload
      };
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      expect(decoded.requestId).assertEqual('r1');
      expect((decoded.payload as QueryPayload).question).assertEqual('测试问题');
    });

    it('rejectsMalformedJson', 0, () => {
      let code: string = '';
      try { codec.decode('{bad'); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsOversizedQuestion', 0, () => {
      const payload: QueryPayload = { question: 'x'.repeat(MAX_QUESTION_CHARS + 1) };
      let code: string = '';
      try { codec.createQuery('m1', 's1', 'r1', 1000, payload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });

    it('rejectsUnknownVersion', 0, () => {
      const text: string = '{"version":"9.9","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"question":"test"}}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsUnknownMessageType', 0, () => {
      const text: string = '{"version":"1.0","type":"UNKNOWN","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{}}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsMissingField', 0, () => {
      const text: string = '{"version":"1.0","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1"}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsEmptyQuestion', 0, () => {
      let code: string = '';
      const emptyQueryPayload: QueryPayload = { question: '' };
      try { codec.createQuery('m1', 's1', 'r1', 1000, emptyQueryPayload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });

    it('acceptsMaxLengthSummary', 0, () => {
      const summary: string = 'x'.repeat(MAX_SUMMARY_CHARS);
      const resultPayload: ResultPayload = {
        summary: summary, sourceDeviceAlias: '响应端设备', processingMs: 5
      };
      const envelope: ProtocolEnvelope = codec.createResult('m1', 's1', 'r1', 1000, resultPayload);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: ResultPayload = decoded.payload as ResultPayload;
      expect(decodedPayload.summary.length).assertEqual(MAX_SUMMARY_CHARS);
    });

    it('rejectsOversizedSummary', 0, () => {
      const summary: string = 'x'.repeat(MAX_SUMMARY_CHARS + 1);
      let code: string = '';
      const oversizeResultPayload: ResultPayload = {
        summary: summary, sourceDeviceAlias: '响应端设备', processingMs: 5
      };
      try {
        codec.createResult('m1', 's1', 'r1', 1000, oversizeResultPayload);
      } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });

    it('rejectsOversizedEncodedMessage', 0, () => {
      const bigValue: string = 'x'.repeat(MAX_MESSAGE_BYTES + 100);
      const bigText: string = '{"version":"1.0","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"question":"' + bigValue + '"}}';
      let code: string = '';
      try { codec.decode(bigText); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('roundTripsAck', 0, () => {
      const ackPayload: QueryAckPayload = { acceptedAt: 1010 };
      const envelope: ProtocolEnvelope = codec.createAck('m2', 's1', 'r1', 1010, ackPayload);
      expect(envelope.type).assertEqual(MessageType.QUERY_ACK);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      expect((decoded.payload as QueryAckPayload).acceptedAt).assertEqual(1010);
    });

    it('roundTripsResult', 0, () => {
      const resultPayload: ResultPayload = {
        summary: '摘要内容', sourceDeviceAlias: '响应端设备', processingMs: 5
      };
      const envelope: ProtocolEnvelope = codec.createResult('m3', 's1', 'r1', 1020, resultPayload);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const payload: ResultPayload = decoded.payload as ResultPayload;
      expect(payload.summary).assertEqual('摘要内容');
      expect(payload.sourceDeviceAlias).assertEqual('响应端设备');
      expect(payload.processingMs).assertEqual(5);
    });

    it('roundTripsKnowledgeResult', 0, () => {
      const knowledgePayload: L2KnowledgePayload = {
        schemaVersion: '1.0', level: 'L2',
        items: [{
          evidenceId: 'ev-1', documentId: 'doc-1', chunkId: 'chunk-1', title: '测试文档',
          snippet: '知识检索内容', relevance: 0.9, truncated: false
        }]
      };
      const knowledgeResult: LocalKnowledgeResult = {
        contractVersion: '1.0', requestId: 'r1', level: 'L2', itemCount: 1,
        payloadJson: JSON.stringify(knowledgePayload), truncated: false, retrievalMs: 3,
        indexVersion: 'index-1', generatedAt: 1000
      };
      const resultPayload: ResultPayload = {
        summary: '命中 1 条', sourceDeviceAlias: '响应端设备', processingMs: 5,
        resultType: 'KNOWLEDGE', knowledgeResult: knowledgeResult
      };
      const envelope: ProtocolEnvelope = codec.createResult('m3', 's1', 'r1', 1020, resultPayload);
      const decoded: ResultPayload = codec.decode(codec.encode(envelope)).payload as ResultPayload;
      expect(decoded.resultType).assertEqual('KNOWLEDGE');
      expect(decoded.knowledgeResult?.itemCount).assertEqual(1);
      expect(decoded.knowledgeResult?.payloadJson).assertEqual(knowledgeResult.payloadJson);
    });

    it('roundTripsError', 0, () => {
      const errorPayload: ErrorPayload = {
        code: 'E_BUSY', message: '设备忙碌'
      };
      const envelope: ProtocolEnvelope = codec.createError('m4', 's1', 'r1', 1030, errorPayload);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const payload: ErrorPayload = decoded.payload as ErrorPayload;
      expect(payload.code).assertEqual('E_BUSY');
      expect(payload.message).assertEqual('设备忙碌');
    });

    it('rejectsNonObjectPayload', 0, () => {
      const text: string = '{"version":"1.0","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":"not-an-object"}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsTrimsWhitespaceQuestion', 0, () => {
      let code: string = '';
      const wsPayload: QueryPayload = { question: '   ' };
      try { codec.createQuery('m1', 's1', 'r1', 1000, wsPayload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });

    it('roundTripsProfile', 0, () => {
      const profile: DeviceProfileAdvertisement = {
        semanticContractVersion: '1.0',
        deviceId: 'dev-1',
        deviceAlias: '设备A',
        profileVersion: 'pv-1',
        indexVersion: 'iv-1',
        indexState: 'READY',
        knowledgeDomains: ['操作系统', '数据库'],
        modalities: ['text', 'pdf'],
        retrievalModes: ['keyword'],
        supportedLevels: ['L1', 'L2'],
        advertisedAtMs: 1000,
        ttlMs: 300000
      };
      const payload: ProfilePayload = { profile: profile };
      const envelope: ProtocolEnvelope = codec.createProfile('m5', 's1', 'r1', 1000, payload);
      expect(envelope.type).assertEqual(MessageType.PROFILE);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: ProfilePayload = decoded.payload as ProfilePayload;
      expect(decodedPayload.profile.deviceId).assertEqual('dev-1');
      expect(decodedPayload.profile.supportedLevels.length).assertEqual(2);
    });

    it('roundTripsTask', 0, () => {
      const task: TaskRequest = {
        semanticContractVersion: '1.0',
        taskId: 'task-1',
        queryText: '操作系统进程调度',
        requiredConcepts: ['进程调度'],
        requiredConfidence: 0.80,
        coverageThreshold: 0.80,
        latencyBudgetMs: 5000,
        byteBudget: 2048,
        privacyLevel: 'PRIVATE_GROUP',
        acceptableLevels: ['L1', 'L2']
      };
      const payload: TaskPayload = { task: task, round: 1 };
      const envelope: ProtocolEnvelope = codec.createTask('m6', 's1', 'r1', 1000, payload);
      expect(envelope.type).assertEqual(MessageType.TASK);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: TaskPayload = decoded.payload as TaskPayload;
      expect(decodedPayload.task.taskId).assertEqual('task-1');
      expect(decodedPayload.round).assertEqual(1);
    });

    it('roundTripsTaskAck', 0, () => {
      const payload: TaskAckPayload = {
        taskId: 'task-1', round: 1, acceptedAt: 1010, candidateCount: 1
      };
      const envelope: ProtocolEnvelope = codec.createTaskAck('m7', 's1', 'r1', 1010, payload);
      expect(envelope.type).assertEqual(MessageType.TASK_ACK);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: TaskAckPayload = decoded.payload as TaskAckPayload;
      expect(decodedPayload.taskId).assertEqual('task-1');
      expect(decodedPayload.candidateCount).assertEqual(1);
    });

    it('roundTripsEvidence', 0, () => {
      const evidence: EvidenceUnit = {
        semanticContractVersion: '1.0',
        evidenceId: 'ev-1',
        evidenceGroupId: 'grp-1',
        sourceDeviceId: 'dev-1',
        sourceDocId: 'doc-1',
        sourceChunkId: 'chunk-1',
        level: 'L1',
        title: '进程调度',
        summary: '优先级队列',
        snippet: '进程调度使用优先级队列',
        relevance: 0.9,
        coveredConcepts: ['进程调度'],
        estimatedCoverageGain: 0.5,
        byteCost: 256,
        privacyLevel: 'PRIVATE_GROUP',
        privacyCost: 0.2,
        energyCost: 0.05,
        hash: 'hash-1',
        canEscalateTo: ['L2']
      };
      const payload: EvidencePayload = { taskId: 'task-1', round: 1, evidence: [evidence] };
      const envelope: ProtocolEnvelope = codec.createEvidence('m8', 's1', 'r1', 1000, payload);
      expect(envelope.type).assertEqual(MessageType.EVIDENCE);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: EvidencePayload = decoded.payload as EvidencePayload;
      expect(decodedPayload.evidence.length).assertEqual(1);
      expect(decodedPayload.evidence[0].evidenceId).assertEqual('ev-1');
      expect(decodedPayload.evidence[0].level).assertEqual('L1');
    });

    it('roundTripsTsf', 0, () => {
      const result: TaskSufficiencyResult = {
        feedback: 'ENOUGH',
        coverage: 0.9,
        confidence: 0.85,
        diversity: 1.0,
        coveredConcepts: ['进程调度'],
        missingConcepts: [],
        acceptedEvidenceIds: ['ev-1']
      };
      const payload: TsfPayload = { taskId: 'task-1', round: 1, result: result };
      const envelope: ProtocolEnvelope = codec.createTsf('m9', 's1', 'r1', 1000, payload);
      expect(envelope.type).assertEqual(MessageType.TSF);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: TsfPayload = decoded.payload as TsfPayload;
      expect(decodedPayload.result.feedback).assertEqual('ENOUGH');
      expect(decodedPayload.result.coverage).assertEqual(0.9);
    });

    it('roundTripsCancel', 0, () => {
      const payload: CancelPayload = { taskId: 'task-1', code: 'E_CANCELLED', reason: '用户取消' };
      const envelope: ProtocolEnvelope = codec.createCancel('m10', 's1', 'r1', 1000, payload);
      expect(envelope.type).assertEqual(MessageType.CANCEL);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: CancelPayload = decoded.payload as CancelPayload;
      expect(decodedPayload.taskId).assertEqual('task-1');
      expect(decodedPayload.code).assertEqual('E_CANCELLED');
    });

    it('rejectsBadSemanticContractVersionInProfile', 0, () => {
      const rawJson: string = '{"version":"1.0","type":"PROFILE","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"profile":{"semanticContractVersion":"2.0","deviceId":"dev-1","deviceAlias":"A","profileVersion":"pv","indexVersion":"iv","indexState":"READY","knowledgeDomains":["os"],"modalities":["text"],"retrievalModes":["keyword"],"supportedLevels":["L1"],"advertisedAtMs":1000,"ttlMs":300000}}}';
      let code: string = '';
      try { codec.decode(rawJson); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsBadRound', 0, () => {
      const task: TaskRequest = {
        semanticContractVersion: '1.0',
        taskId: 'task-1',
        queryText: '操作系统进程调度',
        requiredConcepts: ['进程调度'],
        requiredConfidence: 0.80,
        coverageThreshold: 0.80,
        latencyBudgetMs: 5000,
        byteBudget: 2048,
        privacyLevel: 'PRIVATE_GROUP',
        acceptableLevels: ['L1', 'L2']
      };
      const payload: TaskPayload = { task: task, round: 3 };
      let code: string = '';
      try { codec.createTask('m1', 's1', 'r1', 1000, payload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsMissingTaskIdInTaskAck', 0, () => {
      const payload: TaskAckPayload = {
        taskId: '', round: 1, acceptedAt: 1010, candidateCount: 1
      };
      let code: string = '';
      try { codec.createTaskAck('m1', 's1', 'r1', 1010, payload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsDuplicateEvidenceId', 0, () => {
      const ev1: EvidenceUnit = {
        semanticContractVersion: '1.0', evidenceId: 'ev-dup', evidenceGroupId: 'grp-1',
        sourceDeviceId: 'dev-1', sourceDocId: 'doc-1', level: 'L1', title: 't1',
        relevance: 0.9, coveredConcepts: ['c'], estimatedCoverageGain: 0.5, byteCost: 256,
        privacyLevel: 'PRIVATE_GROUP', privacyCost: 0.2, energyCost: 0.05, hash: 'h1',
        canEscalateTo: ['L2']
      };
      const ev2: EvidenceUnit = {
        semanticContractVersion: '1.0', evidenceId: 'ev-dup', evidenceGroupId: 'grp-1',
        sourceDeviceId: 'dev-1', sourceDocId: 'doc-2', level: 'L2', title: 't2',
        relevance: 0.8, coveredConcepts: ['c'], estimatedCoverageGain: 0.3, byteCost: 512,
        privacyLevel: 'PRIVATE_GROUP', privacyCost: 0.2, energyCost: 0.10, hash: 'h2',
        canEscalateTo: []
      };
      const payload: EvidencePayload = { taskId: 'task-1', round: 1, evidence: [ev1, ev2] };
      let code: string = '';
      try { codec.createEvidence('m1', 's1', 'r1', 1000, payload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsL3InEvidence', 0, () => {
      const rawJson: string = '{"version":"1.0","type":"EVIDENCE","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"taskId":"task-1","round":1,"evidence":[{"semanticContractVersion":"1.0","evidenceId":"ev-1","evidenceGroupId":"grp-1","sourceDeviceId":"dev-1","sourceDocId":"doc-1","level":"L3","title":"t","relevance":0.9,"coveredConcepts":["c"],"estimatedCoverageGain":0.5,"byteCost":256,"privacyLevel":"PRIVATE_GROUP","privacyCost":0.2,"energyCost":0.05,"hash":"h","canEscalateTo":["L2"]}]}}';
      let code: string = '';
      try { codec.decode(rawJson); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsL3InProfileSupportedLevels', 0, () => {
      const rawJson: string = '{"version":"1.0","type":"PROFILE","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"profile":{"semanticContractVersion":"1.0","deviceId":"dev-1","deviceAlias":"A","profileVersion":"pv","indexVersion":"iv","indexState":"READY","knowledgeDomains":["os"],"modalities":["text"],"retrievalModes":["keyword"],"supportedLevels":["L3"],"advertisedAtMs":1000,"ttlMs":300000}}}';
      let code: string = '';
      try { codec.decode(rawJson); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsOversizedEvidence', 0, () => {
      const bigSnippet: string = 'x'.repeat(MAX_MESSAGE_BYTES + 100);
      const rawJson: string = '{"version":"1.0","type":"EVIDENCE","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"taskId":"task-1","round":1,"evidence":[{"semanticContractVersion":"1.0","evidenceId":"ev-1","evidenceGroupId":"grp-1","sourceDeviceId":"dev-1","sourceDocId":"doc-1","level":"L1","title":"t","snippet":"' + bigSnippet + '","relevance":0.9,"coveredConcepts":["c"],"estimatedCoverageGain":0.5,"byteCost":256,"privacyLevel":"PRIVATE_GROUP","privacyCost":0.2,"energyCost":0.05,"hash":"h","canEscalateTo":["L2"]}]}}';
      let code: string = '';
      try { codec.decode(rawJson); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });
  });
}
