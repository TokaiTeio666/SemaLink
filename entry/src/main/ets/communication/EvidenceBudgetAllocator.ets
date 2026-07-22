export interface BudgetCandidate {
  deviceId: string;
  routeScore: number;
}

export interface BudgetAllocation {
  deviceId: string;
  allocatedBytes: number;
}

const MIN_BYTES: number = 512;

export class EvidenceBudgetAllocator {
  allocate(totalBytes: number, candidates: BudgetCandidate[]): BudgetAllocation[] {
    const ordered: BudgetCandidate[] = candidates.slice().sort((left: BudgetCandidate, right: BudgetCandidate): number =>
      left.deviceId.localeCompare(right.deviceId));
    if (ordered.length === 0 || totalBytes <= 0) return [];
    if (totalBytes < ordered.length * MIN_BYTES) {
      const selected: BudgetCandidate = ordered.slice().sort((left: BudgetCandidate, right: BudgetCandidate): number => {
        const score = Math.max(0.01, right.routeScore) - Math.max(0.01, left.routeScore);
        return score === 0 ? left.deviceId.localeCompare(right.deviceId) : score;
      })[0];
      return [{ deviceId: selected.deviceId, allocatedBytes: Math.floor(totalBytes) }];
    }

    const cap: number = Math.max(MIN_BYTES, Math.floor(totalBytes * 0.6));
    const allocations: BudgetAllocation[] = ordered.map((candidate: BudgetCandidate): BudgetAllocation => ({
      deviceId: candidate.deviceId,
      allocatedBytes: MIN_BYTES
    }));
    let remaining: number = Math.floor(totalBytes) - ordered.length * MIN_BYTES;
    const active: boolean[] = ordered.map((): boolean => true);
    while (remaining > 0 && active.some((value: boolean): boolean => value)) {
      let weightTotal: number = 0;
      for (let index = 0; index < ordered.length; index += 1) {
        if (active[index]) weightTotal += Math.max(0.01, ordered[index].routeScore);
      }
      let distributed: number = 0;
      for (let index = 0; index < ordered.length; index += 1) {
        if (!active[index]) continue;
        const weight: number = Math.max(0.01, ordered[index].routeScore);
        const share: number = Math.min(cap - allocations[index].allocatedBytes,
          Math.floor(remaining * weight / weightTotal));
        if (share > 0) {
          allocations[index].allocatedBytes += share;
          remaining -= share;
          distributed += share;
        }
        if (allocations[index].allocatedBytes >= cap) active[index] = false;
      }
      if (distributed === 0) {
        for (let index = 0; index < ordered.length && remaining > 0; index += 1) {
          if (!active[index] || allocations[index].allocatedBytes >= cap) continue;
          allocations[index].allocatedBytes += 1;
          remaining -= 1;
          if (allocations[index].allocatedBytes >= cap) active[index] = false;
        }
      }
    }
    return allocations;
  }
}
