import { describe, expect, it } from '@ohos/hypium';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';
import { InMemorySharingPolicyRepository } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';

export default function sharingPolicyRepositoryTest(): void {
  describe('SharingPolicyRepository', () => {
    it('returns the safe default until an explicit policy is saved', 0, async () => {
      const repository = new InMemorySharingPolicyRepository((): number => 100);
      const initial: SharingPolicy = await repository.load();
      expect(initial.enabled).assertFalse();
      expect(initial.allowedLevels.join(',')).assertEqual('L1');

      await repository.save(new SharingPolicy(true, true, ['L1', 'L2'], 4, 300, [], [], 200, 2));
      const saved: SharingPolicy = await repository.load();
      expect(saved.enabled).assertTrue();
      expect(saved.allowedLevels.join(',')).assertEqual('L1,L2');
    });
  });
}
