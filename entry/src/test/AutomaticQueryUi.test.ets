import { describe, expect, it } from '@ohos/hypium';
import { canSubmitAutomaticQuery, progressLabel } from '../main/ets/components/QueryHome';
import { historyMatchesFilter } from '../main/ets/components/QueryHistory';
import { AppSnapshot, DeviceRole, ConnectionState, INITIAL_SNAPSHOT, cloneSnapshot } from '../main/ets/model/AppModels';
import { CollaborationRecord, CollaborationRecordStatus } from '../main/ets/collaboration/CollaborationModels';

function record(status: CollaborationRecordStatus, evidenceCount: number): CollaborationRecord {
  return {
    id: 'record-1', question: 'question', sourceDeviceName: 'local', sourceDeviceNames: [],
    targetDeviceName: 'automatic', createdAt: 1, status: status, summary: '',
    evidenceCount: evidenceCount, errorMessage: ''
  };
}

export default function automaticQueryUiTest(): void {
  describe('AutomaticQueryUi', () => {
    it('submitsOnlyTrimmedQuestionsWhenAutomaticQueryIsIdle', 0, () => {
      const snapshot: AppSnapshot = INITIAL_SNAPSHOT;
      const busySnapshot: AppSnapshot = cloneSnapshot(snapshot);
      busySnapshot.automaticQueryProgress = 'SEARCHING';
      const connectedSnapshot: AppSnapshot = cloneSnapshot(snapshot, DeviceRole.INITIATOR, ConnectionState.CONNECTED);
      expect(canSubmitAutomaticQuery(snapshot, '  question  ')).assertTrue();
      expect(canSubmitAutomaticQuery(snapshot, '   ')).assertFalse();
      expect(canSubmitAutomaticQuery(busySnapshot, 'question')).assertFalse();
      expect(canSubmitAutomaticQuery(connectedSnapshot, 'question')).assertTrue();
    });

    it('mapsAutomaticProgressToStableLabels', 0, () => {
      expect(progressLabel('IDLE')).assertEqual('Ready');
      expect(progressLabel('ROUTING')).assertEqual('Routing');
      expect(progressLabel('SEARCHING')).assertEqual('Searching');
      expect(progressLabel('ANALYZING')).assertEqual('Analyzing');
      expect(progressLabel('ANSWER_READY')).assertEqual('Answer ready');
      expect(progressLabel('INSUFFICIENT')).assertEqual('Insufficient evidence');
      expect(progressLabel('FAILED')).assertEqual('Failed');
    });

    it('filtersHistoryByOutcomeAndOfflineState', 0, () => {
      expect(historyMatchesFilter(record(CollaborationRecordStatus.SYNCED, 2), 'SUCCESS')).assertTrue();
      expect(historyMatchesFilter(record(CollaborationRecordStatus.SYNCED, 0), 'NO_RESULT')).assertTrue();
      expect(historyMatchesFilter(record(CollaborationRecordStatus.FAILED, 0), 'INSUFFICIENT')).assertTrue();
      expect(historyMatchesFilter(record(CollaborationRecordStatus.OFFLINE, 0), 'OFFLINE')).assertTrue();
      expect(historyMatchesFilter(record(CollaborationRecordStatus.SYNCED, 2), 'ALL')).assertTrue();
    });
  });
}
