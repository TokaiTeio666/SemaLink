import { describe, expect, it } from '@ohos/hypium';
import { EvidenceBudgetAllocator, BudgetCandidate } from '../main/ets/communication/EvidenceBudgetAllocator';

function candidate(deviceId: string, routeScore: number): BudgetCandidate {
  return { deviceId: deviceId, routeScore: routeScore };
}

export default function evidenceBudgetAllocatorTest(): void {
  describe('EvidenceBudgetAllocator', () => {
    it('allocates deterministically with minimum and maximum bounds', 0, () => {
      const allocator = new EvidenceBudgetAllocator();
      const left = allocator.allocate(10000, [candidate('remote-c', 0.4), candidate('local', 1), candidate('remote-b', 0.8)]);
      const right = allocator.allocate(10000, [candidate('remote-b', 0.8), candidate('local', 1), candidate('remote-c', 0.4)]);
      expect(JSON.stringify(left)).assertEqual(JSON.stringify(right));
      expect(left.length).assertEqual(3);
      expect(left[0].allocatedBytes <= 6000).assertEqual(true);
      expect(left[0].allocatedBytes >= 512).assertEqual(true);
    });

    it('selects the highest scored participants when minimum budget is impossible', 0, () => {
      const allocator = new EvidenceBudgetAllocator();
      const result = allocator.allocate(1000, [candidate('a', 0.1), candidate('b', 0.9), candidate('c', 0.8)]);
      expect(result.length).assertEqual(1);
      expect(result[0].deviceId).assertEqual('b');
      expect(result[0].allocatedBytes).assertEqual(1000);
    });
  });
}
