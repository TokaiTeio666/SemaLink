import { describe, expect, it } from '@ohos/hypium';
import { AppRuntime } from '../../../main/ets/runtime/AppRuntime';

export default function collaborationAbilityTest(): void {
  describe('CollaborationAbility', () => {
    it('connectsAndCompletesMinimalQuery', 0, async () => {
      const runtime: AppRuntime = AppRuntime.current();
      runtime.coordinator.selectInitiator();
      await runtime.coordinator.connect();
      await runtime.coordinator.submit('Task 9 lifecycle probe');
      expect(runtime.store.snapshot().summary).assertContain('未执行真实文档检索');
      await runtime.coordinator.disconnect();
    });
  });
}
