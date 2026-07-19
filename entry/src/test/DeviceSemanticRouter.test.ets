import { describe, expect, it } from '@ohos/hypium';
import {
  DEFAULT_COVERAGE_THRESHOLD,
  DEFAULT_REQUIRED_CONFIDENCE,
  DeviceProfileAdvertisement,
  DeviceRuntimeSnapshot,
  SEMANTIC_CONTRACT_VERSION,
  TaskRequest,
  TaskRequestFilters
} from '../main/ets/contracts/semantic/SemanticModels';
import {
  DeviceDirectory,
  DeviceRoutingCandidate,
  REMOTE_PROFILE_TTL_MS
} from '../main/ets/communication/DeviceDirectory';
import {
  DeviceSemanticRouter,
  ExcludedDevice,
  RoutedDevice,
  RoutingResult,
  RoutingSubscores
} from '../main/ets/communication/DeviceSemanticRouter';

const NOW_MS: number = 100000;
const TTL_MS: number = REMOTE_PROFILE_TTL_MS;

function localSnapshot(): DeviceRuntimeSnapshot {
  return {
    deviceId: 'local-device',
    deviceAlias: '本机',
    isLocal: true,
    state: 'READY',
    profileVersion: 'pv-local-1',
    indexVersion: 'iv-local-1',
    lastSeenAtMs: NOW_MS,
    averageRttMs: 0,
    load: 0,
    advertisedAtMs: NOW_MS
  };
}

function remoteSnapshot(deviceId: string, alias: string, advertisedAtMs: number): DeviceRuntimeSnapshot {
  return {
    deviceId: deviceId,
    deviceAlias: alias,
    isLocal: false,
    state: 'READY',
    profileVersion: 'pv-remote-1',
    indexVersion: 'iv-remote-1',
    lastSeenAtMs: advertisedAtMs,
    averageRttMs: 0,
    load: 0,
    advertisedAtMs: advertisedAtMs
  };
}

function localProfile(domains: string[], advertisedAtMs: number): DeviceProfileAdvertisement {
  return {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    deviceId: 'local-device',
    deviceAlias: '本机',
    profileVersion: 'pv-local-1',
    indexVersion: 'iv-local-1',
    indexState: 'READY',
    knowledgeDomains: domains,
    modalities: ['text', 'pdf'],
    retrievalModes: ['keyword'],
    supportedLevels: ['L1', 'L2'],
    advertisedAtMs: advertisedAtMs,
    ttlMs: TTL_MS
  };
}

function remoteProfile(deviceId: string, alias: string, domains: string[],
  advertisedAtMs: number, ttlMs: number = TTL_MS): DeviceProfileAdvertisement {
  return {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    deviceId: deviceId,
    deviceAlias: alias,
    profileVersion: 'pv-remote-1',
    indexVersion: 'iv-remote-1',
    indexState: 'READY',
    knowledgeDomains: domains,
    modalities: ['text', 'pdf'],
    retrievalModes: ['keyword'],
    supportedLevels: ['L1', 'L2'],
    advertisedAtMs: advertisedAtMs,
    ttlMs: ttlMs
  };
}

function taskRequest(requiredConcepts: string[], privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP' = 'PRIVATE_GROUP',
  acceptableLevels: ('L1' | 'L2')[] = ['L1', 'L2'], filters?: TaskRequestFilters): TaskRequest {
  return {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    taskId: 'routing-task',
    queryText: '操作系统进程调度',
    requiredConcepts: requiredConcepts,
    requiredConfidence: DEFAULT_REQUIRED_CONFIDENCE,
    coverageThreshold: DEFAULT_COVERAGE_THRESHOLD,
    latencyBudgetMs: 5000,
    byteBudget: 4096,
    privacyLevel: privacyLevel,
    acceptableLevels: acceptableLevels,
    filters: filters
  };
}

function candidate(snapshot: DeviceRuntimeSnapshot, profile: DeviceProfileAdvertisement): DeviceRoutingCandidate {
  return { snapshot: snapshot, profile: profile };
}

function findRemote(candidates: DeviceRoutingCandidate[]): DeviceRoutingCandidate | null {
  for (const c of candidates) {
    if (!c.snapshot.isLocal) {
      return c;
    }
  }
  return null;
}

function findLocal(candidates: DeviceRoutingCandidate[]): DeviceRoutingCandidate | null {
  for (const c of candidates) {
    if (c.snapshot.isLocal) {
      return c;
    }
  }
  return null;
}

export default function deviceSemanticRouterTest(): void {
  describe('DeviceSemanticRouter', () => {
    const router: DeviceSemanticRouter = new DeviceSemanticRouter();

    it('selectsLocalWhenLocalDomainMatchesAndRemoteMisses', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统', '进程调度']);
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], NOW_MS));
      const remote: DeviceRoutingCandidate = candidate(remoteSnapshot('remote-a', '远端A', NOW_MS),
        remoteProfile('remote-a', '远端A', ['网络'], NOW_MS));
      const result: RoutingResult = router.route(task, [local, remote], NOW_MS);

      expect(result.selected !== null).assertTrue();
      expect(result.routed.length).assertEqual(2);
      expect(result.routed[0].candidate.snapshot.isLocal).assertTrue();
      expect(result.routed[0].candidate.snapshot.deviceId).assertEqual('local-device');
      expect(result.routed[0].scores.semanticMatch).assertEqual(0.5);
      expect(result.routed[1].scores.semanticMatch).assertEqual(0);
    });

    it('selectsRemoteWhenRemoteDomainMatchesBetterThanLocal', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统']);
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['数据库'], NOW_MS));
      const remote: DeviceRoutingCandidate = candidate(remoteSnapshot('remote-a', '远端A', NOW_MS),
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [local, remote], NOW_MS);

      expect(result.selected !== null).assertTrue();
      expect(result.routed[0].candidate.snapshot.isLocal).assertFalse();
      expect(result.routed[0].candidate.snapshot.deviceId).assertEqual('remote-a');
      expect(result.routed[0].scores.semanticMatch).assertEqual(1.0);
    });

    it('excludesRemoteWhenTaskIsLocalOnly', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统'], 'LOCAL_ONLY');
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], NOW_MS));
      const remote: DeviceRoutingCandidate = candidate(remoteSnapshot('remote-a', '远端A', NOW_MS),
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [local, remote], NOW_MS);

      expect(result.excluded.length).assertEqual(1);
      expect(result.excluded[0].reason).assertEqual('LOCAL_ONLY_REMOTE');
      expect(result.excluded[0].candidate.snapshot.deviceId).assertEqual('remote-a');
      expect(result.routed.length).assertEqual(1);
      expect(result.routed[0].candidate.snapshot.isLocal).assertTrue();
    });

    it('excludesDeviceWithExpiredProfile', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统']);
      const staleAdvertisedAt: number = NOW_MS - TTL_MS - 1;
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], NOW_MS));
      const remote: DeviceRoutingCandidate = candidate(
        remoteSnapshot('remote-a', '远端A', staleAdvertisedAt),
        remoteProfile('remote-a', '远端A', ['操作系统'], staleAdvertisedAt));
      const result: RoutingResult = router.route(task, [local, remote], NOW_MS);

      expect(result.excluded.length).assertEqual(1);
      expect(result.excluded[0].reason).assertEqual('PROFILE_EXPIRED');
      expect(result.routed.length).assertEqual(1);
      expect(result.routed[0].candidate.snapshot.isLocal).assertTrue();
    });

    it('excludesDeviceNotReady', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统']);
      const busySnapshot: DeviceRuntimeSnapshot = remoteSnapshot('remote-a', '远端A', NOW_MS);
      busySnapshot.state = 'BUSY';
      const remoteProfileNotReady: DeviceProfileAdvertisement =
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS);
      remoteProfileNotReady.indexState = 'INDEXING';
      const remote: DeviceRoutingCandidate = candidate(busySnapshot, remoteProfileNotReady);
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [local, remote], NOW_MS);

      expect(result.excluded.length).assertEqual(1);
      expect(result.excluded[0].reason).assertEqual('NOT_READY');
      expect(result.routed.length).assertEqual(1);
    });

    it('excludesDeviceMissingRequiredLevels', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统'], 'PRIVATE_GROUP', ['L1']);
      const remoteProfileL2Only: DeviceProfileAdvertisement =
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS);
      remoteProfileL2Only.supportedLevels = ['L2'];
      const remote: DeviceRoutingCandidate = candidate(
        remoteSnapshot('remote-a', '远端A', NOW_MS), remoteProfileL2Only);
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [local, remote], NOW_MS);

      expect(result.excluded.length).assertEqual(1);
      expect(result.excluded[0].reason).assertEqual('LEVELS_NOT_SUPPORTED');
      expect(result.routed.length).assertEqual(1);
    });

    it('excludesDeviceMissingRequiredModalities', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统'], 'PRIVATE_GROUP', ['L1', 'L2'],
        { modalities: ['pdf'] });
      const remoteProfileTextOnly: DeviceProfileAdvertisement =
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS);
      remoteProfileTextOnly.modalities = ['text'];
      const remote: DeviceRoutingCandidate = candidate(
        remoteSnapshot('remote-a', '远端A', NOW_MS), remoteProfileTextOnly);
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [local, remote], NOW_MS);

      expect(result.excluded.length).assertEqual(1);
      expect(result.excluded[0].reason).assertEqual('MODALITIES_NOT_SUPPORTED');
      expect(result.routed.length).assertEqual(1);
    });

    it('prefersLocalOverRemoteWhenScoresTie', 0, () => {
      // Local advertised 60s ago -> freshness = 1 - 60000/300000 = 0.8
      // Remote advertised now -> freshness = 1.0
      // Both semanticMatch=1.0, filterMatch=1.0, rtt=0, load=0
      // Local total = 0.45 + 0.20 + 0.10*0.8 = 0.73
      // Remote total = 0.45 + 0.20 + 0.10*1.0 - 0.10*0.2 = 0.73  (tie)
      const staleLocalAdvertisedAt: number = NOW_MS - 60000;
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], staleLocalAdvertisedAt));
      const remote: DeviceRoutingCandidate = candidate(remoteSnapshot('remote-a', '远端A', NOW_MS),
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS));
      const task: TaskRequest = taskRequest(['操作系统']);
      const result: RoutingResult = router.route(task, [remote, local], NOW_MS);

      expect(result.routed.length).assertEqual(2);
      expect(result.routed[0].candidate.snapshot.isLocal).assertTrue();
      expect(result.routed[1].candidate.snapshot.isLocal).assertFalse();
      const diff: number = Math.abs(result.routed[0].scores.total - result.routed[1].scores.total);
      expect(diff < 1e-9).assertTrue();
    });

    it('sortsByDeviceIdWhenTwoRemotesTie', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统']);
      const remoteB: DeviceRoutingCandidate = candidate(
        remoteSnapshot('remote-b', '远端B', NOW_MS),
        remoteProfile('remote-b', '远端B', ['操作系统'], NOW_MS));
      const remoteA: DeviceRoutingCandidate = candidate(
        remoteSnapshot('remote-a', '远端A', NOW_MS),
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [remoteB, remoteA], NOW_MS);

      expect(result.routed.length).assertEqual(2);
      expect(result.routed[0].candidate.snapshot.deviceId).assertEqual('remote-a');
      expect(result.routed[1].candidate.snapshot.deviceId).assertEqual('remote-b');
    });

    it('exposesSubscoresInRoutingResult', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统']);
      const local: DeviceRoutingCandidate = candidate(localSnapshot(),
        localProfile(['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [local], NOW_MS);

      expect(result.routed.length).assertEqual(1);
      const scores: RoutingSubscores = result.routed[0].scores;
      expect(scores.semanticMatch).assertEqual(1.0);
      expect(scores.filterMatch).assertEqual(1.0);
      expect(scores.freshness).assertEqual(1.0);
      expect(scores.normalizedRtt).assertEqual(0);
      expect(scores.load).assertEqual(0);
      expect(scores.privacyRisk).assertEqual(0);
      expect(scores.total).assertEqual(0.75);
    });

    it('exposesExclusionReasonsForFilteredDevices', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统'], 'LOCAL_ONLY', ['L1']);
      const remoteProfileL2Only: DeviceProfileAdvertisement =
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS);
      remoteProfileL2Only.supportedLevels = ['L2'];
      const remote: DeviceRoutingCandidate = candidate(
        remoteSnapshot('remote-a', '远端A', NOW_MS), remoteProfileL2Only);
      const result: RoutingResult = router.route(task, [remote], NOW_MS);

      expect(result.routed.length).assertEqual(0);
      expect(result.selected === null).assertTrue();
      expect(result.excluded.length).assertEqual(1);
      const excluded: ExcludedDevice = result.excluded[0];
      expect(excluded.reason).assertEqual('LOCAL_ONLY_REMOTE');
      expect(excluded.candidate.snapshot.deviceId).assertEqual('remote-a');
    });

    it('returnsEmptyWhenAllCandidatesExcluded', 0, () => {
      const task: TaskRequest = taskRequest(['操作系统'], 'LOCAL_ONLY');
      const remote: DeviceRoutingCandidate = candidate(
        remoteSnapshot('remote-a', '远端A', NOW_MS),
        remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS));
      const result: RoutingResult = router.route(task, [remote], NOW_MS);

      expect(result.routed.length).assertEqual(0);
      expect(result.selected === null).assertTrue();
      expect(result.excluded.length).assertEqual(1);
    });

    it('directorySnapshotExcludesExpiredRemote', 0, () => {
      const clock: number[] = [NOW_MS];
      const directory: DeviceDirectory = new DeviceDirectory((): number => clock[0]);
      directory.setLocal(localSnapshot(), localProfile(['操作系统'], NOW_MS));
      const staleAdvertisedAt: number = NOW_MS - TTL_MS - 1;
      directory.setRemote(remoteProfile('remote-a', '远端A', ['操作系统'], staleAdvertisedAt));

      const snapshots: DeviceRuntimeSnapshot[] = directory.snapshot();
      expect(snapshots.length).assertEqual(1);
      expect(snapshots[0].isLocal).assertTrue();
    });

    it('directoryClearRemoteRemovesEntry', 0, () => {
      const directory: DeviceDirectory = new DeviceDirectory((): number => NOW_MS);
      directory.setLocal(localSnapshot(), localProfile(['操作系统'], NOW_MS));
      directory.setRemote(remoteProfile('remote-a', '远端A', ['操作系统'], NOW_MS));
      expect(directory.snapshot().length).assertEqual(2);

      directory.clearRemote();
      const snapshots: DeviceRuntimeSnapshot[] = directory.snapshot();
      expect(snapshots.length).assertEqual(1);
      expect(snapshots[0].isLocal).assertTrue();
    });

    it('directorySetRemoteOverwritesPreviousEntry', 0, () => {
      const directory: DeviceDirectory = new DeviceDirectory((): number => NOW_MS);
      directory.setLocal(localSnapshot(), localProfile(['操作系统'], NOW_MS));
      directory.setRemote(remoteProfile('remote-a', '远端A', ['数据库'], NOW_MS));
      directory.setRemote(remoteProfile('remote-b', '远端B', ['网络'], NOW_MS));

      const candidates: DeviceRoutingCandidate[] = directory.candidates();
      expect(candidates.length).assertEqual(2);
      const remote: DeviceRoutingCandidate | null = findRemote(candidates);
      expect(remote !== null).assertTrue();
      expect(remote!.snapshot.deviceId).assertEqual('remote-b');
      expect(remote!.profile.knowledgeDomains[0]).assertEqual('网络');
    });

    it('directoryCandidatesBundlesSnapshotsAndProfiles', 0, () => {
      const directory: DeviceDirectory = new DeviceDirectory((): number => NOW_MS);
      directory.setLocal(localSnapshot(), localProfile(['操作系统'], NOW_MS));
      directory.setRemote(remoteProfile('remote-a', '远端A', ['网络'], NOW_MS));

      const candidates: DeviceRoutingCandidate[] = directory.candidates();
      expect(candidates.length).assertEqual(2);
      const local: DeviceRoutingCandidate | null = findLocal(candidates);
      const remote: DeviceRoutingCandidate | null = findRemote(candidates);
      expect(local !== null).assertTrue();
      expect(remote !== null).assertTrue();
      expect(local!.profile.knowledgeDomains[0]).assertEqual('操作系统');
      expect(remote!.profile.knowledgeDomains[0]).assertEqual('网络');
      expect(local!.snapshot.deviceId).assertEqual('local-device');
      expect(remote!.snapshot.deviceId).assertEqual('remote-a');
    });
  });
}
