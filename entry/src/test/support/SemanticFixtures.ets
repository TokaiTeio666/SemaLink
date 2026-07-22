import {
  EvidenceLevel,
  TaskRequest,
  TaskRequestFilters
} from '../../main/ets/contracts/semantic/SemanticModels';
import { DocumentChunk } from '../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../main/ets/knowledge/model/KnowledgeDocument';

export type SemanticExpectedDomain = '操作系统' | '数据库' | '网络' | '软件测试' | 'NONE';
export type SemanticExpectedTerminalState =
  'L1_SUFFICIENT' | 'L2_INSUFFICIENT' | 'CANDIDATES_AVAILABLE' | 'NO_MATCH';

export interface SemanticAcceptanceCase {
  name: string;
  queryId: string;
  task: TaskRequest;
  expectedDomain: SemanticExpectedDomain;
  expectedDocumentIds: string[];
  expectedLevels: EvidenceLevel[];
  expectedTerminalState: SemanticExpectedTerminalState;
}

function request(queryId: string, queryText: string, requiredConcepts: string[],
  acceptableLevels: EvidenceLevel[], privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP',
  filters?: TaskRequestFilters): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: queryId, queryText: queryText,
    requiredConcepts: requiredConcepts, requiredConfidence: 0.95, coverageThreshold: 0.9,
    latencyBudgetMs: 1, byteBudget: 1, privacyLevel: privacyLevel,
    acceptableLevels: acceptableLevels, filters: filters
  };
}

function fixture(name: string, queryId: string, queryText: string, requiredConcepts: string[],
  acceptableLevels: EvidenceLevel[], privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP',
  expectedDomain: SemanticExpectedDomain, expectedDocumentIds: string[], expectedLevels: EvidenceLevel[],
  expectedTerminalState: SemanticExpectedTerminalState, filters?: TaskRequestFilters): SemanticAcceptanceCase {
  return {
    name: name,
    queryId: queryId,
    task: request(queryId, queryText, requiredConcepts, acceptableLevels, privacyLevel, filters),
    expectedDomain: expectedDomain,
    expectedDocumentIds: expectedDocumentIds,
    expectedLevels: expectedLevels,
    expectedTerminalState: expectedTerminalState
  };
}

export const SEMANTIC_ACCEPTANCE_DOCUMENTS: KnowledgeDocument[] = [
  {
    documentId: 'doc-os', title: '操作系统进程调度', modality: 'text',
    normalizedText: '进程调度使用优先级队列和老化机制避免饥饿', tags: ['操作系统', '调度'],
    checksum: 'fixture-os', createdAt: 1, updatedAt: 100, privacyLevel: 'PRIVATE_GROUP'
  },
  {
    documentId: 'doc-local-os', title: '本机操作系统进程调度', modality: 'text',
    normalizedText: '进程调度使用优先级队列，本机私有调度笔记', tags: ['操作系统', '调度'],
    checksum: 'fixture-local-os', createdAt: 1, updatedAt: 110, privacyLevel: 'LOCAL_ONLY'
  },
  {
    documentId: 'doc-db', title: '数据库事务 ACID', modality: 'pdf',
    normalizedText: '数据库事务包含原子性一致性隔离性持久性', tags: ['数据库', '事务'],
    checksum: 'fixture-db', createdAt: 1, updatedAt: 200, privacyLevel: 'PRIVATE_GROUP'
  },
  {
    documentId: 'doc-net', title: '网络 TCP 可靠传输', modality: 'image',
    normalizedText: 'TCP 使用序列号确认重传实现可靠传输', tags: ['网络', 'TCP'],
    checksum: 'fixture-net', createdAt: 1, updatedAt: 300, privacyLevel: 'PRIVATE_GROUP'
  },
  {
    documentId: 'doc-test', title: '软件测试阶段', modality: 'ocr_text',
    normalizedText: '软件测试包含单元测试集成测试系统测试和验收测试', tags: ['软件测试', '测试'],
    checksum: 'fixture-test', createdAt: 1, updatedAt: 400, privacyLevel: 'PRIVATE_GROUP'
  }
];

export const SEMANTIC_ACCEPTANCE_CHUNKS: DocumentChunk[] = [
  {
    chunkId: 'chunk-os', documentId: 'doc-os', chunkIndex: 0,
    text: '操作系统使用优先级队列执行进程调度，老化机制可以避免任务饥饿。',
    summary: '进程调度、优先级队列与老化', keywords: ['操作系统', '进程调度', '优先级队列', '老化'],
    startOffset: 0, endOffset: 31, updatedAt: 100
  },
  {
    chunkId: 'chunk-local-os', documentId: 'doc-local-os', chunkIndex: 0,
    text: '本机私有操作系统笔记：进程调度同样使用优先级队列。',
    summary: '本机私有进程调度', keywords: ['操作系统', '进程调度', '优先级队列'],
    startOffset: 0, endOffset: 25, updatedAt: 110
  },
  {
    chunkId: 'chunk-db', documentId: 'doc-db', chunkIndex: 0,
    text: '数据库事务的 ACID 是原子性、一致性、隔离性和持久性。',
    summary: '数据库事务 ACID', keywords: ['数据库', '事务', 'ACID', '原子性', '隔离性', '持久性'],
    startOffset: 0, endOffset: 28, updatedAt: 200
  },
  {
    chunkId: 'chunk-net', documentId: 'doc-net', chunkIndex: 0,
    text: '网络中的 TCP 使用序列号、确认和重传保证可靠传输。',
    summary: 'TCP 可靠传输、确认与重传', keywords: ['网络', 'TCP', '确认', '重传', '可靠传输'],
    startOffset: 0, endOffset: 27, updatedAt: 300
  },
  {
    chunkId: 'chunk-test', documentId: 'doc-test', chunkIndex: 0,
    text: '软件测试阶段包括单元测试、集成测试、系统测试和验收测试。',
    summary: '软件测试阶段', keywords: ['软件测试', '单元测试', '集成测试', '系统测试', '验收测试'],
    startOffset: 0, endOffset: 29, updatedAt: 400
  }
];

export const SEMANTIC_ACCEPTANCE_CASES: SemanticAcceptanceCase[] = [
  fixture('操作系统 L1 足够', 'os-l1-sufficient', '操作系统进程调度', ['进程调度'], ['L1'],
    'PRIVATE_GROUP', '操作系统', ['doc-os'], ['L1'], 'L1_SUFFICIENT', { documentIds: ['doc-os'] }),
  fixture('操作系统调度覆盖', 'os-covered-scheduling', '进程调度优先级队列', ['进程调度'], ['L2'],
    'PRIVATE_GROUP', '操作系统', ['doc-os'], ['L2'], 'CANDIDATES_AVAILABLE', { documentIds: ['doc-os'] }),
  fixture('操作系统老化后仍不足', 'os-covered-aging', '进程调度优先级队列老化',
    ['老化', '多级反馈队列'], ['L2'],
    'PRIVATE_GROUP', '操作系统', ['doc-os'], ['L2'], 'L2_INSUFFICIENT', { documentIds: ['doc-os'] }),
  fixture('操作系统 L1 L2', 'os-both-levels', '操作系统进程调度老化', ['进程调度', '老化'], ['L1', 'L2'],
    'PRIVATE_GROUP', '操作系统', ['doc-os'], ['L1', 'L2'], 'CANDIDATES_AVAILABLE',
    { documentIds: ['doc-os'] }),
  fixture('PRIVATE_GROUP 隐私矩阵', 'privacy-private-group', '进程调度优先级队列', ['进程调度'], ['L2'],
    'PRIVATE_GROUP', '操作系统', ['doc-os'], ['L2'], 'CANDIDATES_AVAILABLE'),
  fixture('LOCAL_ONLY 隐私矩阵', 'privacy-local-only', '进程调度优先级队列', ['进程调度'], ['L2'],
    'LOCAL_ONLY', '操作系统', ['doc-local-os', 'doc-os'], ['L2', 'L2'], 'CANDIDATES_AVAILABLE'),

  fixture('数据库 L1 足够', 'db-l1-sufficient', '数据库事务 ACID', ['数据库', '事务'], ['L1'],
    'PRIVATE_GROUP', '数据库', ['doc-db'], ['L1'], 'L1_SUFFICIENT', { documentIds: ['doc-db'] }),
  fixture('数据库隔离后仍不足', 'db-l2-insufficient', '数据库事务隔离性',
    ['隔离性', '两阶段提交'], ['L2'],
    'PRIVATE_GROUP', '数据库', ['doc-db'], ['L2'], 'L2_INSUFFICIENT', { documentIds: ['doc-db'] }),
  fixture('数据库 L1 L2', 'db-both-levels', '数据库事务原子性持久性', ['原子性', '持久性'], ['L1', 'L2'],
    'PRIVATE_GROUP', '数据库', ['doc-db'], ['L1', 'L2'], 'CANDIDATES_AVAILABLE',
    { documentIds: ['doc-db'] }),
  fixture('数据库 documentIds', 'db-document-filter', '数据库事务 ACID', ['ACID'], ['L2'],
    'LOCAL_ONLY', '数据库', ['doc-db'], ['L2'], 'CANDIDATES_AVAILABLE', { documentIds: ['doc-db'] }),
  fixture('数据库 tags', 'db-tags-filter', '数据库事务 ACID', ['事务'], ['L1'],
    'LOCAL_ONLY', '数据库', ['doc-db'], ['L1'], 'CANDIDATES_AVAILABLE', { tags: ['数据库', '事务'] }),
  fixture('数据库 modalities', 'db-modality-filter', '数据库事务 ACID', ['数据库'], ['L2'],
    'LOCAL_ONLY', '数据库', ['doc-db'], ['L2'], 'CANDIDATES_AVAILABLE', { modalities: ['pdf'] }),

  fixture('网络 L1 足够', 'net-l1-sufficient', '网络 TCP 可靠传输', ['TCP', '可靠传输'], ['L1'],
    'PRIVATE_GROUP', '网络', ['doc-net'], ['L1'], 'L1_SUFFICIENT', { documentIds: ['doc-net'] }),
  fixture('网络重传后仍不足', 'net-l2-insufficient', 'TCP 确认重传',
    ['确认', '重传', '拥塞控制'], ['L2'],
    'PRIVATE_GROUP', '网络', ['doc-net'], ['L2'], 'L2_INSUFFICIENT', { documentIds: ['doc-net'] }),
  fixture('网络 L1 L2', 'net-both-levels', 'TCP 可靠传输确认', ['TCP', '确认'], ['L1', 'L2'],
    'PRIVATE_GROUP', '网络', ['doc-net'], ['L1', 'L2'], 'CANDIDATES_AVAILABLE', { documentIds: ['doc-net'] }),
  fixture('网络 modalities', 'net-modality-filter', 'TCP 确认重传', ['重传'], ['L2'],
    'LOCAL_ONLY', '网络', ['doc-net'], ['L2'], 'CANDIDATES_AVAILABLE', { modalities: ['image'] }),
  fixture('网络 updatedAfter', 'net-updated-filter', '网络 TCP 可靠传输', ['TCP'], ['L1'],
    'LOCAL_ONLY', '网络', ['doc-net'], ['L1'], 'CANDIDATES_AVAILABLE', { updatedAfter: 250 }),
  fixture('网络 tags', 'net-tags-filter', '网络 TCP 可靠传输', ['网络'], ['L2'],
    'LOCAL_ONLY', '网络', ['doc-net'], ['L2'], 'CANDIDATES_AVAILABLE', { tags: ['网络', 'TCP'] }),

  fixture('软件测试 L1 足够', 'test-l1-sufficient', '软件测试阶段', ['软件测试'], ['L1'],
    'PRIVATE_GROUP', '软件测试', ['doc-test'], ['L1'], 'L1_SUFFICIENT', { documentIds: ['doc-test'] }),
  fixture('验收测试后仍不足', 'test-l2-insufficient', '软件测试验收测试',
    ['验收测试', '边界值分析'], ['L2'],
    'PRIVATE_GROUP', '软件测试', ['doc-test'], ['L2'], 'L2_INSUFFICIENT', { documentIds: ['doc-test'] }),
  fixture('软件测试 L1 L2', 'test-both-levels', '单元测试集成测试', ['单元测试', '集成测试'], ['L1', 'L2'],
    'PRIVATE_GROUP', '软件测试', ['doc-test'], ['L1', 'L2'], 'CANDIDATES_AVAILABLE',
    { documentIds: ['doc-test'] }),
  fixture('软件测试 modalities', 'test-modality-filter', '软件测试验收测试', ['验收测试'], ['L2'],
    'LOCAL_ONLY', '软件测试', ['doc-test'], ['L2'], 'CANDIDATES_AVAILABLE', { modalities: ['ocr_text'] }),
  fixture('软件测试 updatedAfter', 'test-updated-filter', '软件测试阶段', ['软件测试'], ['L1'],
    'LOCAL_ONLY', '软件测试', ['doc-test'], ['L1'], 'CANDIDATES_AVAILABLE', { updatedAfter: 350 }),
  fixture('软件测试 tags', 'test-tags-filter', '软件测试阶段', ['软件测试'], ['L2'],
    'LOCAL_ONLY', '软件测试', ['doc-test'], ['L2'], 'CANDIDATES_AVAILABLE',
    { tags: ['软件测试', '测试'] }),

  fixture('隐私拒绝', 'privacy-rejected', '本机操作系统进程调度', ['进程调度'], ['L2'],
    'PRIVATE_GROUP', '操作系统', [], [], 'NO_MATCH', { documentIds: ['doc-local-os'] }),
  fixture('标签过滤失败', 'filter-tags-miss', '数据库事务 ACID', ['事务'], ['L1'],
    'LOCAL_ONLY', '数据库', [], [], 'NO_MATCH', { tags: ['网络'] }),
  fixture('模态过滤失败', 'filter-modality-miss', '网络 TCP 可靠传输', ['TCP'], ['L2'],
    'LOCAL_ONLY', '网络', [], [], 'NO_MATCH', { modalities: ['pdf'] }),
  fixture('更新时间过滤失败', 'filter-updated-miss', '软件测试阶段', ['软件测试'], ['L1'],
    'LOCAL_ONLY', '软件测试', [], [], 'NO_MATCH', { updatedAfter: 500 }),
  fixture('无匹配', 'no-match', '量子引力黑洞蒸发', [], ['L1', 'L2'],
    'LOCAL_ONLY', 'NONE', [], [], 'NO_MATCH')
];

export type SemanticExpectedDevice = 'LOCAL' | 'REMOTE' | 'EITHER';
export type SemanticCommunicationTerminalState =
  'L1_SUFFICIENT' | 'L2_SUFFICIENT' | 'L2_INSUFFICIENT';

export interface SemanticCommunicationCase {
  name: string;
  task: TaskRequest;
  expectedDevice: SemanticExpectedDevice;
  expectedDomain: SemanticExpectedDomain;
  expectedTerminalState: SemanticCommunicationTerminalState;
  expectedEvidenceBytes: number;
}

function communicationTask(taskId: string, queryText: string, requiredConcepts: string[],
  acceptableLevels: EvidenceLevel[] = ['L1', 'L2']): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: taskId, queryText: queryText,
    requiredConcepts: requiredConcepts, requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: acceptableLevels
  };
}

function communicationFixture(name: string, taskId: string, queryText: string, requiredConcepts: string[],
  expectedDevice: SemanticExpectedDevice, expectedDomain: SemanticExpectedDomain,
  expectedTerminalState: SemanticCommunicationTerminalState, expectedEvidenceBytes: number): SemanticCommunicationCase {
  return {
    name: name, task: communicationTask(taskId, queryText, requiredConcepts), expectedDevice: expectedDevice,
    expectedDomain: expectedDomain, expectedTerminalState: expectedTerminalState,
    expectedEvidenceBytes: expectedEvidenceBytes
  };
}

export const SEMANTIC_COMMUNICATION_CASES: SemanticCommunicationCase[] = [
  communicationFixture('本机操作系统 L1 足够', 'comm-local-os-01', '操作系统进程调度', ['进程调度'],
    'LOCAL', '操作系统', 'L1_SUFFICIENT', 180),
  communicationFixture('本机操作系统 L2 不足', 'comm-local-os-02', '操作系统老化', ['老化', '多级反馈队列'],
    'LOCAL', '操作系统', 'L2_INSUFFICIENT', 360),
  communicationFixture('本机操作系统 L2 足够', 'comm-local-os-03', '操作系统优先级队列', ['进程调度', '优先级队列'],
    'LOCAL', '操作系统', 'L2_SUFFICIENT', 360),
  communicationFixture('本机操作系统升级', 'comm-local-os-04', '操作系统调度策略', ['进程调度'],
    'LOCAL', '操作系统', 'L2_SUFFICIENT', 360),
  communicationFixture('本机数据库 L1 足够', 'comm-local-db-01', '数据库事务 ACID', ['数据库', '事务'],
    'LOCAL', '数据库', 'L1_SUFFICIENT', 180),
  communicationFixture('本机数据库 L2 不足', 'comm-local-db-02', '数据库两阶段提交', ['隔离性', '两阶段提交'],
    'LOCAL', '数据库', 'L2_INSUFFICIENT', 360),
  communicationFixture('本机数据库 L2 足够', 'comm-local-db-03', '数据库持久性', ['原子性', '持久性'],
    'LOCAL', '数据库', 'L2_SUFFICIENT', 360),
  communicationFixture('本机数据库隔离', 'comm-local-db-04', '数据库隔离性', ['事务', '隔离性'],
    'LOCAL', '数据库', 'L2_SUFFICIENT', 360),
  communicationFixture('远端网络 TCP', 'comm-remote-net-01', '网络 TCP 可靠传输', ['TCP', '可靠传输'],
    'REMOTE', '网络', 'L2_SUFFICIENT', 360),
  communicationFixture('远端网络确认', 'comm-remote-net-02', '网络确认重传', ['确认', '重传'],
    'REMOTE', '网络', 'L2_SUFFICIENT', 360),
  communicationFixture('远端网络拥塞', 'comm-remote-net-03', '网络拥塞控制', ['拥塞控制'],
    'REMOTE', '网络', 'L2_SUFFICIENT', 360),
  communicationFixture('远端网络链路', 'comm-remote-net-04', '网络链路可靠性', ['可靠传输'],
    'REMOTE', '网络', 'L2_SUFFICIENT', 360),
  communicationFixture('远端软件测试 L1', 'comm-remote-test-01', '软件测试阶段', ['软件测试'],
    'REMOTE', '软件测试', 'L2_SUFFICIENT', 360),
  communicationFixture('远端软件测试单元', 'comm-remote-test-02', '软件测试单元测试', ['单元测试'],
    'REMOTE', '软件测试', 'L2_SUFFICIENT', 360),
  communicationFixture('远端软件测试集成', 'comm-remote-test-03', '软件测试集成测试', ['集成测试'],
    'REMOTE', '软件测试', 'L2_SUFFICIENT', 360),
  communicationFixture('远端软件测试验收', 'comm-remote-test-04', '软件测试验收测试', ['验收测试'],
    'REMOTE', '软件测试', 'L2_SUFFICIENT', 360),
  communicationFixture('跨设备操作系统', 'comm-either-os-01', '操作系统进程', ['进程调度'],
    'EITHER', '操作系统', 'L2_SUFFICIENT', 360),
  communicationFixture('跨设备数据库', 'comm-either-db-01', '数据库事务', ['事务'],
    'EITHER', '数据库', 'L2_SUFFICIENT', 360),
  communicationFixture('跨设备网络', 'comm-either-net-01', '网络重传', ['重传'],
    'EITHER', '网络', 'L2_SUFFICIENT', 360),
  communicationFixture('跨设备测试', 'comm-either-test-01', '软件测试验收', ['验收测试'],
    'EITHER', '软件测试', 'L2_SUFFICIENT', 360)
];
