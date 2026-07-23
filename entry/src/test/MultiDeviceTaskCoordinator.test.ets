import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { DataEnvelope } from '../main/ets/protocol/MultiDeviceProtocolModels';
import {
  CoordinatedTaskResult,
  MultiDeviceTaskCoordinator,
  CoordinatorCandidate,
  CoordinatorTransport
} from '../main/ets/communication/MultiDeviceTaskCoordinator';

function task(id: string): TaskRequest {
  return { semanticContractVersion: '1.0', taskId: id, queryText: 'query', requiredConcepts: ['alpha', 'beta'],
    requiredConfidence: 0.8, coverageThreshold: 0.8, latencyBudgetMs: 1000, byteBudget: 4000,
    privacyLevel: 'PRIVATE_GROUP', acceptableLevels: ['L1', 'L2'] };
}
function unit(id: string, concept: string, source: string, level: 'L1' | 'L2' = 'L1'): EvidenceUnit {
  return { semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: id, sourceDeviceId: source,
    sourceDocId: 'doc-' + id, level: level, title: id, summary: id, relevance: 1,
    coveredConcepts: [concept], estimatedCoverageGain: 1, byteCost: 100, privacyLevel: 'PRIVATE_GROUP',
    privacyCost: 0, energyCost: 0, hash: 'hash-' + id, canEscalateTo: ['L2'] };
}
class FakeTransport implements CoordinatorTransport {
  sent: string[] = [];
  envelopes: Array<Record<string, Object>> = [];
  private readonly responses: Map<string, EvidenceUnit[]>;
  private readonly failingSearches: Set<string>;
  constructor(responses: Map<string, EvidenceUnit[]>, failingSearches: Set<string> = new Set<string>()) {
    this.responses = responses;
    this.failingSearches = failingSearches;
  }
  send(deviceId: string, envelope: Object): Promise<void> {
    this.sent.push(deviceId + ':' + (envelope as SentEnvelope).type);
    this.envelopes.push(envelope as Record<string, Object>);
    return Promise.resolve();
  }
  search(deviceId: string, _request: TaskRequest, round: 1 | 2): Promise<EvidenceUnit[]> {
    if (this.failingSearches.has(deviceId + ':' + round)) return Promise.reject(new Error('search failed'));
    return Promise.resolve(this.responses.get(deviceId + ':' + round) ?? []);
  }
}
function candidate(deviceId: string, local: boolean): CoordinatorCandidate {
  return { deviceId: deviceId, isLocal: local, routeScore: local ? 1 : 0.8, ready: true };
}

function scoredCandidate(deviceId: string, local: boolean, routeScore: number): CoordinatorCandidate {
  return { deviceId: deviceId, isLocal: local, routeScore: routeScore, ready: true };
}

interface CaughtError {
  code: string;
}
interface SentEnvelope {
  type: string;
}

export default function multiDeviceTaskCoordinatorTest(): void {
  describe('MultiDeviceTaskCoordinator', () => {
    it('runs local and two remotes and freezes a sufficient result', 0, async () => {
      const transport = new FakeTransport(new Map<string, EvidenceUnit[]>([
        ['local:1', [unit('a', 'alpha', 'local')]], ['remote-b:1', [unit('b', 'beta', 'remote-b')]],
        ['remote-c:1', [unit('b', 'beta', 'remote-c')]]
      ]));
      const coordinator = new MultiDeviceTaskCoordinator(transport, () => [candidate('local', true), candidate('remote-b', false), candidate('remote-c', false)]);
      const result: CoordinatedTaskResult = await coordinator.submit(task('task-1'));
      expect(result.feedback).assertEqual('ENOUGH');
      expect(result.acceptedEvidence.length).assertEqual(2);
      expect(result.acceptedEvidence[0].title).assertEqual('a');
      expect(result.acceptedEvidence[1].sourceDeviceId).assertEqual('remote-b');
      expect(transport.sent.length >= 2).assertEqual(true);
      coordinator.onEnvelope('remote-c', {} as DataEnvelope);
    });

    it('rejects a second active task and can cancel peers', 0, async () => {
      const transport = new FakeTransport(new Map<string, EvidenceUnit[]>());
      const coordinator = new MultiDeviceTaskCoordinator(transport, () => [candidate('local', true), candidate('remote-b', false)]);
      const pending = coordinator.submit(task('task-1'));
      let busy = false;
      try { await coordinator.submit(task('task-2')); } catch (error) { busy = (error as CaughtError).code === 'E_BUSY'; }
      expect(busy).assertEqual(true);
      await coordinator.cancel('task-1');
      await pending;
    });

    it('sends a versioned task envelope to every remote participant', 0, async () => {
      const transport = new FakeTransport(new Map<string, EvidenceUnit[]>([
        ['local:1', [unit('a', 'alpha', 'local')]], ['remote-b:1', [unit('b', 'beta', 'remote-b')]]
      ]));
      const coordinator = new MultiDeviceTaskCoordinator(transport, () => [candidate('local', true), candidate('remote-b', false)]);
      await coordinator.submit(task('task-envelope'));
      expect(transport.envelopes[0]['version']).assertEqual('2.0');
      expect(transport.envelopes[0]['type']).assertEqual('TASK');
    });

    it('selectsHighestScoringReadyRemotesAndKeepsLocalEvidenceWhenRemoteFails', 0, async () => {
      const transport = new FakeTransport(
        new Map<string, EvidenceUnit[]>([['local:1', [unit('local-alpha', 'alpha', 'local'), unit('local-beta', 'beta', 'local')]],
          ['remote-high:1', [unit('remote-beta', 'beta', 'remote-high')]]]),
        new Set<string>(['remote-high:1'])
      );
      const coordinator = new MultiDeviceTaskCoordinator(transport, () => [
        scoredCandidate('local', true, 0.30), scoredCandidate('remote-low', false, 0.20),
        scoredCandidate('remote-high', false, 0.90), scoredCandidate('remote-mid', false, 0.60)
      ]);
      const result = await coordinator.submit(task('task-route-score'));
      expect(result.feedback).assertEqual('ENOUGH');
      expect(transport.sent.indexOf('remote-high:TASK') >= 0).assertTrue();
      expect(transport.sent.indexOf('remote-mid:TASK') >= 0).assertTrue();
      expect(transport.sent.indexOf('remote-low:TASK')).assertEqual(-1);
    });
  });
}
