import { describe, expect, it } from '@ohos/hypium';
import { AppSnapshot, ConnectionState, DeviceRole, INITIAL_SNAPSHOT } from '../../../main/ets/model/AppModels';
import { canSubmit, isBusy, shouldShowConnect } from '../../../main/ets/pages/Index';

export default function indexPageTest(): void {
  describe('IndexPage', () => {
    it('startsWithRoleSelection', 0, () => {
      expect(INITIAL_SNAPSHOT.role).assertEqual(DeviceRole.UNSELECTED);
      expect(shouldShowConnect(INITIAL_SNAPSHOT)).assertFalse();
    });

    it('showsConnectForInitiatorRecoveryStates', 0, () => {
      const snapshot: AppSnapshot = { ...INITIAL_SNAPSHOT, role: DeviceRole.INITIATOR };
      expect(shouldShowConnect(snapshot)).assertTrue();
      expect(shouldShowConnect({ ...snapshot, connectionState: ConnectionState.ERROR })).assertTrue();
    });

    it('disablesActionsWhileBusy', 0, () => {
      expect(isBusy(ConnectionState.CONNECTING)).assertTrue();
      expect(isBusy(ConnectionState.WAITING_ACK)).assertTrue();
      expect(isBusy(ConnectionState.WAITING_RESULT)).assertTrue();
      expect(isBusy(ConnectionState.CONNECTED)).assertFalse();
    });

    it('enablesOnlyValidConnectedQuestion', 0, () => {
      const connected: AppSnapshot = {
        ...INITIAL_SNAPSHOT,
        role: DeviceRole.INITIATOR,
        connectionState: ConnectionState.CONNECTED
      };
      expect(canSubmit(connected, '请总结文档')).assertTrue();
      expect(canSubmit(connected, '')).assertFalse();
      expect(canSubmit({ ...connected, connectionState: ConnectionState.WAITING_RESULT }, '请总结文档'))
        .assertFalse();
    });

    it('responderDoesNotSubmit', 0, () => {
      const responder: AppSnapshot = {
        ...INITIAL_SNAPSHOT,
        role: DeviceRole.RESPONDER,
        connectionState: ConnectionState.CONNECTED
      };
      expect(canSubmit(responder, 'remote question')).assertFalse();
    });
  });
}
