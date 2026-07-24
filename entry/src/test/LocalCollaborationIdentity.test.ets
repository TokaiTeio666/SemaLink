import { describe, expect, it } from '@ohos/hypium';
import { LocalCollaborationIdentity } from '../main/ets/crossdevice/model/CollaborationModels';

export default function localCollaborationIdentityTest(): void {
  describe('LocalCollaborationIdentity', () => {
    it('requires an application-scoped random identifier', 0, () => {
      let rejected: boolean = false;
      try {
        new LocalCollaborationIdentity('', '本机', 100, 100, 1);
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('renames without changing the application instance identifier', 0, () => {
      const identity = new LocalCollaborationIdentity('app-random-1', '设备 A', 100, 100, 1);
      const renamed: LocalCollaborationIdentity = identity.rename('书房手机', 200);
      expect(renamed.appInstanceId).assertEqual('app-random-1');
      expect(renamed.deviceAlias).assertEqual('书房手机');
      expect(renamed.createdAtMs).assertEqual(100);
      expect(renamed.updatedAtMs).assertEqual(200);
      expect(renamed.revision).assertEqual(2);
    });
  });
}
