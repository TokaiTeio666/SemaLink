import { EvidenceUnit, EvidenceLevel, TaskRequest } from '../contracts/semantic/SemanticModels';

export interface EvidenceSelection {
  evidence: EvidenceUnit;
  utility: number;
  meu: number;
}

export interface EvidenceSchedule {
  round: number;
  selected: EvidenceUnit[];
  selections: EvidenceSelection[];
  totalByteCost: number;
}

const SCORE_EPSILON: number = 1e-9;

function bounded(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function hasValue(values: string[], value: string): boolean {
  return values.indexOf(value) >= 0;
}

function privacyCompatible(task: TaskRequest, evidence: EvidenceUnit): boolean {
  return task.privacyLevel !== 'PRIVATE_GROUP' || evidence.privacyLevel === 'PRIVATE_GROUP';
}

function levelForRound(round: number): EvidenceLevel | null {
  if (round === 1) {
    return 'L1';
  }
  if (round === 2) {
    return 'L2';
  }
  return null;
}

function coveredBy(evidence: EvidenceUnit[]): string[] {
  const concepts: string[] = [];
  for (const unit of evidence) {
    for (const concept of unit.coveredConcepts) {
      if (!hasValue(concepts, concept)) {
        concepts.push(concept);
      }
    }
  }
  return concepts;
}

function selectionFor(task: TaskRequest, evidence: EvidenceUnit, existingGroups: string[]): EvidenceSelection {
  const normalizedBytes: number = bounded(evidence.byteCost / Math.max(1, task.byteBudget));
  const diversityGain: number = hasValue(existingGroups, evidence.evidenceGroupId) ? 0 : 1;
  const utility: number = 0.30 * bounded(evidence.relevance) +
    0.25 * bounded(evidence.estimatedCoverageGain) + 0.15 * diversityGain -
    0.10 * normalizedBytes - 0.10 * 0 - 0.08 * bounded(evidence.privacyCost) -
    0.04 * bounded(evidence.energyCost);
  return { evidence: evidence, utility: utility, meu: utility / (evidence.byteCost + 128) };
}

export class EvidenceUtilityScheduler {
  schedule(task: TaskRequest, candidates: EvidenceUnit[], round: number,
    alreadySent: EvidenceUnit[] = []): EvidenceSchedule {
    const level: EvidenceLevel | null = levelForRound(round);
    if (level === null) {
      return { round: round, selected: [], selections: [], totalByteCost: 0 };
    }
    const sentIds: Set<string> = new Set<string>();
    for (const unit of alreadySent) {
      sentIds.add(unit.evidenceId);
    }
    const missingConcepts: string[] = [];
    for (const concept of task.requiredConcepts) {
      if (!hasValue(coveredBy(alreadySent), concept)) {
        missingConcepts.push(concept);
      }
    }
    const seenIds: Set<string> = new Set<string>();
    const pool: EvidenceSelection[] = [];
    for (const candidate of candidates) {
      if (candidate.level !== level || !hasValue(task.acceptableLevels, candidate.level) ||
        !privacyCompatible(task, candidate) || sentIds.has(candidate.evidenceId) ||
        seenIds.has(candidate.evidenceId)) {
        continue;
      }
      if (round === 2 && missingConcepts.length > 0 &&
        !candidate.coveredConcepts.some((concept: string): boolean => hasValue(missingConcepts, concept))) {
        continue;
      }
      seenIds.add(candidate.evidenceId);
      pool.push(selectionFor(task, candidate, alreadySent.map((unit: EvidenceUnit): string => unit.evidenceGroupId)));
    }
    pool.sort((left: EvidenceSelection, right: EvidenceSelection): number => {
      const difference: number = right.meu - left.meu;
      if (Math.abs(difference) > SCORE_EPSILON) {
        return difference;
      }
      return left.evidence.evidenceId < right.evidence.evidenceId ? -1 :
        (left.evidence.evidenceId > right.evidence.evidenceId ? 1 : 0);
    });
    const selected: EvidenceUnit[] = [];
    const selections: EvidenceSelection[] = [];
    let totalByteCost: number = 0;
    for (const unit of alreadySent) {
      totalByteCost += unit.byteCost;
    }
    const selectedGroups: string[] = alreadySent.map((unit: EvidenceUnit): string => unit.evidenceGroupId);
    for (const selection of pool) {
      if (totalByteCost + selection.evidence.byteCost > task.byteBudget) {
        continue;
      }
      selected.push(selection.evidence);
      selections.push(selection);
      totalByteCost += selection.evidence.byteCost;
      if (!hasValue(selectedGroups, selection.evidence.evidenceGroupId)) {
        selectedGroups.push(selection.evidence.evidenceGroupId);
      }
    }
    return { round: round, selected: selected, selections: selections, totalByteCost: totalByteCost };
  }
}
