import { describe, expect, it } from '@ohos/hypium';
import { AppError, ErrorStage } from '../main/ets/common/AppError';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { SystemScheduler } from '../main/ets/common/Scheduler';

export default function commonModelsTest(): void {
  describe('CommonModels', () => {
    it('createsStableErrorMetadata', 0, () => {
      const error = new AppError('E_DEVICE_NOT_FOUND', '未发现设备', ErrorStage.SELECTION, true);
      expect(error.code).assertEqual('E_DEVICE_NOT_FOUND');
      expect(error.recoverable).assertTrue();
    });

    it('createsDistinctIds', 0, () => {
      const ids = new SequenceIdGenerator(() => 1000);
      expect(ids.next('request')).assertEqual('request-1000-1');
      expect(ids.next('request')).assertEqual('request-1000-2');
    });

    it('runsScheduledCallback', 0, async () => {
      let called: boolean = false;
      await new Promise<void>((resolve: () => void) => {
        new SystemScheduler().schedule(0, () => {
          called = true;
          resolve();
        });
      });
      expect(called).assertTrue();
    });

    it('cancelsScheduledCallback', 0, async () => {
      let called: boolean = false;
      const scheduler = new SystemScheduler();
      const timerId = scheduler.schedule(0, () => {
        called = true;
      });
      scheduler.cancel(timerId);
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 10);
      });
      expect(called).assertFalse();
    });
  });
}
