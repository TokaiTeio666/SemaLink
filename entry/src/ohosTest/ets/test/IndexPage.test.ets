import { describe, expect, it } from '@ohos/hypium';
import { ConnectionState, DeviceRole, INITIAL_SNAPSHOT, cloneSnapshot, maskDeviceId } from '../../../main/ets/model/AppModels';
import { canSubmit, isBusy, shouldShowConnect } from '../../../main/ets/pages/Index';

export default function indexPageTest(): void {
  describe('IndexPage', () => {
    it('startsWithRoleSelection', 0, () => {
      expect(INITIAL_SNAPSHOT.role).assertEqual(DeviceRole.UNSELECTED);
      expect(shouldShowConnect(INITIAL_SNAPSHOT)).assertFalse();
    });

    it('showsConnectForInitiatorRecoveryStates', 0, () => {
      const snapshot = cloneSnapshot(INITIAL_SNAPSHOT, DeviceRole.INITIATOR);
      expect(shouldShowConnect(snapshot)).assertTrue();
      expect(shouldShowConnect(cloneSnapshot(snapshot, undefined, ConnectionState.ERROR))).assertTrue();
    });

    it('disablesActionsWhileBusy', 0, () => {
      expect(isBusy(ConnectionState.CONNECTING)).assertTrue();
      expect(isBusy(ConnectionState.WAITING_ACK)).assertTrue();
      expect(isBusy(ConnectionState.WAITING_RESULT)).assertTrue();
      expect(isBusy(ConnectionState.CONNECTED)).assertFalse();
    });

    it('enablesOnlyValidConnectedQuestion', 0, () => {
      const connected = cloneSnapshot(INITIAL_SNAPSHOT, DeviceRole.INITIATOR, ConnectionState.CONNECTED);
      expect(canSubmit(connected, '请总结文档')).assertTrue();
      expect(canSubmit(connected, '')).assertFalse();
      expect(canSubmit(cloneSnapshot(connected, undefined, ConnectionState.WAITING_RESULT), '请总结文档'))
        .assertFalse();
    });

    it('responderDoesNotSubmit', 0, () => {
      const responder = cloneSnapshot(INITIAL_SNAPSHOT, DeviceRole.RESPONDER, ConnectionState.CONNECTED);
      expect(canSubmit(responder, 'remote question')).assertFalse();
    });

    it('cloneSnapshotPreservesPeerDeviceFields', 0, () => {
      const base = cloneSnapshot(INITIAL_SNAPSHOT, DeviceRole.INITIATOR);
      // cloneSnapshot should copy peerDeviceName and peerDeviceIdMasked from base
      const cloned = cloneSnapshot(base, undefined, ConnectionState.CONNECTED);
      expect(cloned.peerDeviceName).assertEqual(base.peerDeviceName);
      expect(cloned.peerDeviceIdMasked).assertEqual(base.peerDeviceIdMasked);
    });

    it('maskDeviceIdDoesNotExposeFullId', 0, () => {
      const fullId = '1234567890abcdef';
      const masked = maskDeviceId(fullId);
      expect(masked.includes(fullId)).assertFalse();
      expect(masked.length > 0).assertTrue();
    });
  });
}
