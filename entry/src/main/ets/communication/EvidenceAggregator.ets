import { EvidenceUnit } from '../contracts/semantic/SemanticModels';

export interface VerifiedEvidence {
  evidence: EvidenceUnit;
  sourceDeviceId: string;
  contentDigest: string;
  round: 1 | 2;
}

export interface AggregatedEvidence {
  evidence: EvidenceUnit;
  contentDigest: string;
  sourceDeviceIds: string[];
  round: 1 | 2;
}

export interface EvidenceConflict {
  evidenceId: string;
  contentDigests: string[];
}

export interface AggregatedEvidenceResult {
  evidence: AggregatedEvidence[];
  conflicts: EvidenceConflict[];
}

export class EvidenceAggregator {
  private readonly digestByEvidenceId = new Map<string, Set<string>>();
  private readonly canonicalByDigest = new Map<string, AggregatedEvidence>();
  private readonly conflictsByEvidenceId = new Map<string, EvidenceConflict>();

  add(value: VerifiedEvidence): void {
    const evidenceId: string = value.evidence.evidenceId;
    const digests: Set<string> = this.digestByEvidenceId.get(evidenceId) ?? new Set<string>();
    digests.add(value.contentDigest);
    this.digestByEvidenceId.set(evidenceId, digests);
    if (digests.size > 1) {
      this.conflictsByEvidenceId.set(evidenceId, {
        evidenceId: evidenceId,
        contentDigests: Array.from(digests).sort()
      });
      return;
    }

    const existing: AggregatedEvidence | undefined = this.canonicalByDigest.get(value.contentDigest);
    if (existing === undefined || evidenceId < existing.evidence.evidenceId) {
      const sourceIds: string[] = existing === undefined ? [value.sourceDeviceId] : existing.sourceDeviceIds.concat([value.sourceDeviceId]);
      this.canonicalByDigest.set(value.contentDigest, {
        evidence: value.evidence,
        contentDigest: value.contentDigest,
        sourceDeviceIds: Array.from(new Set(sourceIds)).sort(),
        round: existing === undefined ? value.round : Math.min(existing.round, value.round) as 1 | 2
      });
    } else if (existing.sourceDeviceIds.indexOf(value.sourceDeviceId) < 0) {
      existing.sourceDeviceIds.push(value.sourceDeviceId);
      existing.sourceDeviceIds.sort();
    }
  }

  result(): AggregatedEvidenceResult {
    const conflicts: EvidenceConflict[] = Array.from(this.conflictsByEvidenceId.values()).sort((left, right) =>
      left.evidenceId.localeCompare(right.evidenceId));
    const conflictIds: Set<string> = new Set(conflicts.map((value: EvidenceConflict): string => value.evidenceId));
    const evidence: AggregatedEvidence[] = Array.from(this.canonicalByDigest.values())
      .filter((value: AggregatedEvidence): boolean => !conflictIds.has(value.evidence.evidenceId))
      .map((value: AggregatedEvidence): AggregatedEvidence => ({
        evidence: value.evidence,
        contentDigest: value.contentDigest,
        sourceDeviceIds: value.sourceDeviceIds.slice().sort(),
        round: value.round
      }))
      .sort((left: AggregatedEvidence, right: AggregatedEvidence): number =>
        left.round - right.round || left.sourceDeviceIds[0].localeCompare(right.sourceDeviceIds[0]) ||
        left.evidence.evidenceId.localeCompare(right.evidence.evidenceId));
    return { evidence: evidence, conflicts: conflicts };
  }

  clear(): void {
    this.digestByEvidenceId.clear();
    this.canonicalByDigest.clear();
    this.conflictsByEvidenceId.clear();
  }
}
