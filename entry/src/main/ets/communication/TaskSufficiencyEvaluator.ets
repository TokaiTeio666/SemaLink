import {
  EvidenceUnit,
  TaskRequest,
  TaskSufficiencyFeedback,
  TaskSufficiencyResult
} from '../contracts/semantic/SemanticModels';

function hasValue(values: string[], value: string): boolean {
  return values.indexOf(value) >= 0;
}

function normalize(value: string): string {
  return value.toLowerCase().replace(/\s+/g, ' ').trim();
}

export class TaskSufficiencyEvaluator {
  evaluate(task: TaskRequest, evidence: EvidenceUnit[], round: number): TaskSufficiencyResult {
    const accepted: EvidenceUnit[] = [];
    const acceptedIds: string[] = [];
    for (const unit of evidence) {
      if (!hasValue(acceptedIds, unit.evidenceId)) {
        accepted.push(unit);
        acceptedIds.push(unit.evidenceId);
      }
    }
    const required: string[] = task.requiredConcepts.map((concept: string): string => normalize(concept));
    const covered: string[] = [];
    for (const unit of accepted) {
      for (const concept of unit.coveredConcepts) {
        const normalized: string = normalize(concept);
        if (hasValue(required, normalized) && !hasValue(covered, normalized)) {
          covered.push(normalized);
        }
      }
    }
    const missing: string[] = required.filter((concept: string): boolean => !hasValue(covered, concept));
    const coverage: number = covered.length / Math.max(1, required.length);
    let relevanceTotal: number = 0;
    const groups: string[] = [];
    for (const unit of accepted) {
      relevanceTotal += Math.max(0, Math.min(1, unit.relevance));
      if (!hasValue(groups, unit.evidenceGroupId)) {
        groups.push(unit.evidenceGroupId);
      }
    }
    const averageRelevance: number = accepted.length === 0 ? 0 : relevanceTotal / accepted.length;
    const confidence: number = 0.60 * averageRelevance + 0.40 * coverage;
    const diversity: number = Math.min(1, groups.length / Math.max(1, accepted.length));
    const enough: boolean = coverage >= task.coverageThreshold && confidence >= task.requiredConfidence;
    const feedback: TaskSufficiencyFeedback = enough ? 'ENOUGH' :
      (round === 1 ? 'NEED_MORE' : 'ABORT');
    return {
      feedback: feedback,
      coverage: coverage,
      confidence: confidence,
      diversity: diversity,
      coveredConcepts: covered,
      missingConcepts: missing,
      acceptedEvidenceIds: acceptedIds
    };
  }
}
