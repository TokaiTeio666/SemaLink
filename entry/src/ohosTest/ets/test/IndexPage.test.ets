import { describe, expect, it } from '@ohos/hypium';
import {
  AppSnapshot,
  ConnectionState,
  DeviceRole,
  INITIAL_SNAPSHOT,
  cloneSnapshot,
  maskDeviceId
} from '../../../main/ets/model/AppModels';
import {
  CollaborationRecord,
  createSendingRecord,
  sortCollaborationRecords
} from '../../../main/ets/collaboration/CollaborationModels';
import { AppStateStore } from '../../../main/ets/state/AppStateStore';
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

  describe('AppStateStoreCollaboration', () => {
    it('initialSnapshotHasEmptyCollaborationFields', 0, () => {
      expect(INITIAL_SNAPSHOT.collaborationRecords.length).assertEqual(0);
      expect(INITIAL_SNAPSHOT.selectedCollaborationRecordId).assertEqual('');
    });

    it('updatePublishesSelectedCollaborationRecordId', 0, () => {
      const store = new AppStateStore();
      let observedId = '';
      store.subscribe((snapshot: AppSnapshot) => {
        observedId = snapshot.selectedCollaborationRecordId;
      });
      store.update({ selectedCollaborationRecordId: 'request-1' });
      expect(observedId).assertEqual('request-1');
    });

    it('updatePreservesCollaborationRecordsWhenOmitted', 0, () => {
      const record: CollaborationRecord = createSendingRecord({
        id: 'request-1',
        question: '项目状态',
        sourceDeviceName: '本机',
        targetDeviceName: 'MatePad',
        createdAt: 1000
      });
      const store = new AppStateStore();
      store.update({ collaborationRecords: [record] });
      expect(store.snapshot().collaborationRecords.length).assertEqual(1);
      // An unrelated update must preserve the existing records array
      store.update({ question: 'another question' });
      const after = store.snapshot();
      expect(after.collaborationRecords.length).assertEqual(1);
      expect(after.collaborationRecords[0].id).assertEqual('request-1');
    });

    it('cloneSnapshotPreservesCollaborationFields', 0, () => {
      const record: CollaborationRecord = createSendingRecord({
        id: 'request-2',
        question: '继续查询',
        sourceDeviceName: '本机',
        targetDeviceName: 'MatePad',
        createdAt: 2000
      });
      // Populate a snapshot with collaboration fields via the store
      const store = new AppStateStore();
      store.update({
        collaborationRecords: sortCollaborationRecords([record]),
        selectedCollaborationRecordId: 'request-2'
      });
      const populated = store.snapshot();
      const cloned = cloneSnapshot(populated, undefined, ConnectionState.CONNECTED);
      expect(cloned.collaborationRecords.length).assertEqual(1);
      expect(cloned.collaborationRecords[0].id).assertEqual('request-2');
      expect(cloned.selectedCollaborationRecordId).assertEqual('request-2');
    });

    it('cloneSnapshotPreservesKnowledgeWhenCollaborationChanges', 0, () => {
      const record: CollaborationRecord = createSendingRecord({
        id: 'request-3',
        question: '协作问题',
        sourceDeviceName: '本机',
        targetDeviceName: 'MatePad',
        createdAt: 3000
      });
      const store = new AppStateStore();
      // Populate both knowledge AND collaboration state.
      store.update({
        knowledgeDocumentCount: 5,
        knowledgeChunkCount: 30,
        knowledgeQueryStatus: 'SUCCESS',
        collaborationRecords: sortCollaborationRecords([record]),
        selectedCollaborationRecordId: 'request-3'
      });
      const populated = store.snapshot();
      // Clone with a connection state change (simulating collaboration activity).
      const cloned = cloneSnapshot(populated, undefined, ConnectionState.CONNECTED);
      // Knowledge fields must be preserved across the clone.
      expect(cloned.knowledgeDocumentCount).assertEqual(5);
      expect(cloned.knowledgeChunkCount).assertEqual(30);
      expect(cloned.knowledgeQueryStatus).assertEqual('SUCCESS');
      // Collaboration fields must also be preserved.
      expect(cloned.collaborationRecords.length).assertEqual(1);
      expect(cloned.collaborationRecords[0].id).assertEqual('request-3');
      expect(cloned.selectedCollaborationRecordId).assertEqual('request-3');
    });

    it('updatePreservesKnowledgeFieldsDuringCollaborationUpdate', 0, () => {
      const store = new AppStateStore();
      // Populate knowledge state first.
      store.update({
        knowledgeDocumentCount: 3,
        knowledgeChunkCount: 15,
        knowledgeQueryStatus: 'SUCCESS'
      });
      // A collaboration-only update must preserve the knowledge fields.
      store.update({
        selectedCollaborationRecordId: 'request-1'
      });
      const after = store.snapshot();
      expect(after.knowledgeDocumentCount).assertEqual(3);
      expect(after.knowledgeChunkCount).assertEqual(15);
      expect(after.knowledgeQueryStatus).assertEqual('SUCCESS');
      expect(after.selectedCollaborationRecordId).assertEqual('request-1');
    });
  });
}
