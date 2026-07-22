import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import {
  EvidenceLevel,
  EvidenceUnit,
  PrivacyLevel,
  SEMANTIC_CONTRACT_VERSION,
  TaskRequest,
  validateTaskRequest
} from '../../contracts/semantic/SemanticModels';
import { checksumUserText } from '../import/UserDocumentPolicy';
import { RetrievalCandidate } from '../model/RetrievalCandidate';
import { utf8ByteLength } from '../payload/Utf8Sizer';

const MAX_BYTE_COST_ITERATIONS: number = 8;

function isVisible(candidate: RetrievalCandidate, privacyLevel: PrivacyLevel): boolean {
  return privacyLevel === 'LOCAL_ONLY' || candidate.document.privacyLevel === 'PRIVATE_GROUP';
}

function bounded(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function safeText(value: string, maximumLength: number): string {
  let safe = value.replace(/\b[a-z][a-z0-9+.-]*:\/\/\S*/gi, '[redacted]');
  safe = safe.replace(/\\\\\S*/g, '[redacted]');
  safe = safe.replace(/[a-z]:\\\S*/gi, '[redacted]');
  safe = safe.replace(/(^|\s)\/\S*/g, '$1[redacted]');
  return safe.length > maximumLength ? safe.substring(0, maximumLength) : safe;
}

function normalizeConcept(value: string): string {
  return value.toLowerCase().replace(/\s+/g, ' ').trim();
}

function safeIdentifier(value: string): string {
  const sanitized: string = safeText(value, 200);
  if (value.length <= 200 && sanitized === value) {
    return value;
  }
  return 'safe-' + checksumUserText(value);
}

function coveredConcepts(task: TaskRequest, candidate: RetrievalCandidate, content: string): string[] {
  const searchable = normalizeConcept(candidate.document.title + ' ' + candidate.document.tags.join(' ') + ' ' +
    candidate.chunk.keywords.join(' ') + ' ' + content);
  const covered: string[] = [];
  for (const required of task.requiredConcepts) {
    const normalized = normalizeConcept(required);
    if (normalized.length > 0 && searchable.includes(normalized) && covered.indexOf(normalized) < 0) {
      covered.push(safeText(normalized, 300));
    }
  }
  return covered;
}

function privacyCost(privacyLevel: PrivacyLevel): number {
  return privacyLevel === 'LOCAL_ONLY' ? 1 : 0.2;
}

function hashInput(unit: EvidenceUnit): string {
  return [
    unit.semanticContractVersion, unit.evidenceId, unit.evidenceGroupId, unit.parentEvidenceId || '',
    unit.sourceDeviceId, unit.sourceDocId, unit.sourceChunkId || '', unit.level, unit.title,
    unit.summary || '', unit.snippet || '', unit.relevance.toString(), unit.coveredConcepts.join(','),
    unit.estimatedCoverageGain.toString(), unit.privacyLevel, unit.privacyCost.toString(),
    unit.energyCost.toString(), unit.canEscalateTo.join(',')
  ].join('\u001f');
}

function finalize(unit: EvidenceUnit): EvidenceUnit {
  unit.hash = checksumUserText(hashInput(unit));
  for (let iteration = 0; iteration < MAX_BYTE_COST_ITERATIONS; iteration++) {
    const measured: number = utf8ByteLength(JSON.stringify(unit));
    if (measured === unit.byteCost) {
      return unit;
    }
    unit.byteCost = measured;
  }
  throw new KnowledgeError('E_EVIDENCE_INVALID', 'Evidence byte cost did not stabilize', false);
}

function coverageGain(covered: string[], required: string[]): number {
  return covered.length / Math.max(1, required.length);
}

function buildL1(candidate: RetrievalCandidate, task: TaskRequest, sourceDeviceId: string): EvidenceUnit {
  const summary: string = safeText(candidate.chunk.summary.length > 0 ?
    candidate.chunk.summary : candidate.chunk.text, 300);
  const concepts: string[] = coveredConcepts(task, candidate, summary);
  const unit: EvidenceUnit = {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    evidenceId: 'ev-l1-' + safeIdentifier(candidate.document.documentId),
    evidenceGroupId: 'doc-' + safeIdentifier(candidate.document.documentId),
    sourceDeviceId: safeIdentifier(sourceDeviceId),
    sourceDocId: safeIdentifier(candidate.document.documentId),
    level: 'L1',
    title: safeText(candidate.document.title, 300),
    summary: summary,
    relevance: bounded(candidate.relevance),
    coveredConcepts: concepts,
    estimatedCoverageGain: coverageGain(concepts, task.requiredConcepts),
    byteCost: 0,
    privacyLevel: candidate.document.privacyLevel,
    privacyCost: privacyCost(candidate.document.privacyLevel),
    energyCost: 0.05,
    hash: '',
    canEscalateTo: ['L2']
  };
  return finalize(unit);
}

function buildL2(candidate: RetrievalCandidate, task: TaskRequest, sourceDeviceId: string): EvidenceUnit {
  const snippet: string = safeText(candidate.chunk.text, 1500);
  const concepts: string[] = coveredConcepts(task, candidate, snippet);
  const unit: EvidenceUnit = {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    evidenceId: 'ev-l2-' + safeIdentifier(candidate.chunk.chunkId),
    evidenceGroupId: 'doc-' + safeIdentifier(candidate.document.documentId),
    sourceDeviceId: safeIdentifier(sourceDeviceId),
    sourceDocId: safeIdentifier(candidate.document.documentId),
    sourceChunkId: safeIdentifier(candidate.chunk.chunkId),
    parentEvidenceId: 'ev-l1-' + safeIdentifier(candidate.document.documentId),
    level: 'L2',
    title: safeText(candidate.document.title, 300),
    snippet: snippet,
    relevance: bounded(candidate.relevance),
    coveredConcepts: concepts,
    estimatedCoverageGain: coverageGain(concepts, task.requiredConcepts),
    byteCost: 0,
    privacyLevel: candidate.document.privacyLevel,
    privacyCost: privacyCost(candidate.document.privacyLevel),
    energyCost: 0.1,
    hash: '',
    canEscalateTo: []
  };
  return finalize(unit);
}

function buildLevel(candidates: RetrievalCandidate[], task: TaskRequest,
  sourceDeviceId: string, level: EvidenceLevel): EvidenceUnit[] {
  const units: EvidenceUnit[] = [];
  const included: Set<string> = new Set<string>();
  for (const candidate of candidates) {
    if (!isVisible(candidate, task.privacyLevel)) {
      continue;
    }
    const identity: string = level === 'L1' ? candidate.document.documentId : candidate.chunk.chunkId;
    if (included.has(identity)) {
      continue;
    }
    included.add(identity);
    units.push(level === 'L1' ? buildL1(candidate, task, sourceDeviceId) :
      buildL2(candidate, task, sourceDeviceId));
  }
  return units;
}

export class EvidenceUnitFactory {
  build(candidates: RetrievalCandidate[], task: TaskRequest, sourceDeviceId: string): EvidenceUnit[] {
    validateTaskRequest(task);
    const units: EvidenceUnit[] = [];
    for (const level of task.acceptableLevels) {
      units.push(...buildLevel(candidates, task, sourceDeviceId, level));
    }
    return units;
  }
}
