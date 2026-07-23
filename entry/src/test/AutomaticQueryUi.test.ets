import { describe, expect, it } from '@ohos/hypium';
import {
  availableDeviceNames,
  canSubmitAutomaticQuery,
  queryDeviceStep,
  queryDurationLabel,
  progressLabel,
  progressStepIndex
} from '../main/ets/components/QueryHome';
import { historyMatchesFilter, historyStatusLabel } from '../main/ets/components/QueryHistory';
import { onlineDeviceSummary, peerConnectionLabel } from '../main/ets/components/DeviceOverview';
import {
  AppSnapshot,
  DeviceRole,
  ConnectionState,
  INITIAL_SNAPSHOT,
  PeerStatusSnapshot,
  cloneSnapshot
} from '../main/ets/model/AppModels';
import { CollaborationRecord, CollaborationRecordStatus } from '../main/ets/collaboration/CollaborationModels';

function record(status: CollaborationRecordStatus, evidenceCount: number): CollaborationRecord {
  return {
    id: 'record-1', question: 'question', sourceDeviceName: 'local', sourceDeviceNames: [],
    targetDeviceName: 'automatic', createdAt: 1, status: status, summary: '',
    evidenceCount: evidenceCount, errorMessage: ''
  };
}

function peer(
  name: string,
  controlState: 'DISCONNECTED' | 'CONNECTING' | 'READY' | 'FAILED',
  dataState: 'DISCONNECTED' | 'CONNECTING' | 'BINDING' | 'READY' | 'FAILED',
  failureCode: string = ''
): PeerStatusSnapshot {
  return {
    deviceIdMasked: '***remote',
    deviceName: name,
    controlState: controlState,
    dataState: dataState,
    taskState: '',
    allocatedBytes: 0,
    evidenceCount: 0,
    failureCode: failureCode
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
      expect(progressLabel('IDLE')).assertEqual('准备查询');
      expect(progressLabel('ROUTING')).assertEqual('正在路由');
      expect(progressLabel('SEARCHING')).assertEqual('正在查询');
      expect(progressLabel('ANALYZING')).assertEqual('正在分析');
      expect(progressLabel('ANSWER_READY')).assertEqual('结果已就绪');
      expect(progressLabel('INSUFFICIENT')).assertEqual('证据不足');
      expect(progressLabel('FAILED')).assertEqual('查询失败');
    });

    it('mapsProgressToReferenceTimelineSteps', 0, () => {
      expect(progressStepIndex('ROUTING')).assertEqual(0);
      expect(progressStepIndex('SEARCHING')).assertEqual(1);
      expect(progressStepIndex('ANALYZING')).assertEqual(2);
      expect(progressStepIndex('ANSWER_READY')).assertEqual(4);
      expect(progressStepIndex('IDLE')).assertEqual(-1);
    });

    it('mapsHistoryStatusesToChineseLabels', 0, () => {
      expect(historyStatusLabel(CollaborationRecordStatus.SYNCED)).assertEqual('查询成功');
      expect(historyStatusLabel(CollaborationRecordStatus.FAILED)).assertEqual('证据不足');
      expect(historyStatusLabel(CollaborationRecordStatus.OFFLINE)).assertEqual('设备离线');
    });

    it('formatsOnlineDeviceSummaryForDevicePage', 0, () => {
      expect(onlineDeviceSummary(2, 3)).assertEqual('2 / 3 台设备可用');
      expect(onlineDeviceSummary(1, 1)).assertEqual('1 / 1 台设备可用');
    });

    it('derivesPeerConnectionLabelsFromBothChannels', 0, () => {
      expect(peerConnectionLabel(peer('Tablet B', 'READY', 'READY'))).assertEqual('已连接');
      expect(peerConnectionLabel(peer('Tablet B', 'READY', 'BINDING'))).assertEqual('正在绑定');
      expect(peerConnectionLabel(peer('Tablet B', 'FAILED', 'DISCONNECTED', 'E_CONNECT_FAILED')))
        .assertEqual('连接失败 · E_CONNECT_FAILED');
    });

    it('includesOnlyAvailablePeersInAutomaticQueryScope', 0, () => {
      const snapshot: AppSnapshot = cloneSnapshot(INITIAL_SNAPSHOT);
      snapshot.peerStatuses = [
        peer('Tablet B', 'READY', 'READY'),
        peer('Tablet C', 'READY', 'DISCONNECTED')
      ];
      const names: string[] = availableDeviceNames(snapshot);
      expect(names.length).assertEqual(2);
      expect(names[0]).assertEqual('本机');
      expect(names[1]).assertEqual('Tablet B');
      expect(queryDeviceStep(snapshot)).assertEqual('查询本机、Tablet B');
    });

    it('formatsOnlyRealTotalQueryDuration', 0, () => {
      expect(queryDurationLabel(1250)).assertEqual('总耗时 1.25 秒');
      expect(queryDurationLabel(0)).assertEqual('');
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
