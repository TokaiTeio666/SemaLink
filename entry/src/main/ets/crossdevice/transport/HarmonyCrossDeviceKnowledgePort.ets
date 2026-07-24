import {
  CrossDeviceAvailability,
  CrossDeviceKnowledgePort,
  CrossDeviceQueryResult
} from '../../agent/query/CrossDeviceKnowledgePort';
import {
  DeviceProfileAdvertisement,
  DeviceRuntimeSnapshot,
  TaskRequest
} from '../../contracts/semantic/SemanticModels';
import {
  DeviceRoutingCandidate
} from '../../communication/DeviceDirectory';
import {
  DeviceSemanticRouter,
  RoutedDevice,
  RoutingResult
} from '../../communication/DeviceSemanticRouter';
import {
  CollaborationPeer,
  RemoteKnowledgeProfile
} from '../model/CollaborationModels';
import { RemoteKnowledgeProfileRepository } from '../storage/CollaborationRepositories';
import { TrustedDeviceDirectory } from '../trust/TrustedDeviceDirectory';

export interface HarmonyRemoteQueryClient {
  isPeerConnected(peerKey: string): boolean;
  query(peerKey: string, request: TaskRequest,
    matchedDomain?: string): Promise<CrossDeviceQueryResult>;
  cancel(taskId: string): void;
  destroy(): void;
}

export function isFallbackEligible(result: CrossDeviceQueryResult): boolean {
  return result.reason === 'REMOTE_BUSY' ||
    result.reason === 'REMOTE_NETWORK_ERROR';
}

function candidate(peer: CollaborationPeer,
  profile: RemoteKnowledgeProfile): DeviceRoutingCandidate {
  const snapshot: DeviceRuntimeSnapshot = {
    deviceId: peer.peerKey,
    deviceAlias: peer.deviceAlias,
    isLocal: false,
    state: peer.onlineState === 'ONLINE' && profile.indexState === 'READY' ? 'READY' : 'BUSY',
    profileVersion: profile.profileVersion,
    indexVersion: profile.profileDigest,
    lastSeenAtMs: peer.lastSeenAtMs,
    averageRttMs: 0,
    load: 0,
    advertisedAtMs: profile.receivedAtMs
  };
  const advertisement: DeviceProfileAdvertisement = {
    semanticContractVersion: '1.0',
    deviceId: peer.peerKey,
    deviceAlias: peer.deviceAlias,
    profileVersion: profile.profileVersion,
    indexVersion: profile.profileDigest,
    indexState: profile.indexState,
    knowledgeDomains: profile.knowledgeDomains.slice(),
    modalities: ['text'],
    retrievalModes: profile.retrievalModes.slice(),
    supportedLevels: profile.supportedLevels.slice(),
    advertisedAtMs: profile.receivedAtMs,
    ttlMs: Math.max(1, profile.expiresAtMs - profile.receivedAtMs)
  };
  return { snapshot: snapshot, profile: advertisement };
}

export class HarmonyCrossDeviceKnowledgePort implements CrossDeviceKnowledgePort {
  private readonly directory: TrustedDeviceDirectory;
  private readonly profiles: RemoteKnowledgeProfileRepository;
  private readonly client: HarmonyRemoteQueryClient;
  private readonly clock: () => number;
  private readonly router: DeviceSemanticRouter = new DeviceSemanticRouter();
  private readonly generations: Map<string, number> = new Map<string, number>();
  private destroyed: boolean = false;
  private lastAvailable: boolean = false;

  constructor(directory: TrustedDeviceDirectory, profiles: RemoteKnowledgeProfileRepository,
    client: HarmonyRemoteQueryClient, clock: () => number) {
    this.directory = directory;
    this.profiles = profiles;
    this.client = client;
    this.clock = clock;
  }

  availability(): CrossDeviceAvailability {
    return new CrossDeviceAvailability(
      !this.destroyed && this.lastAvailable,
      this.destroyed ? 'REMOTE_CHANNEL_DESTROYED' :
        this.lastAvailable ? 'AVAILABLE' : 'NO_TRUSTED_ONLINE_PEER'
    );
  }

  async search(request: TaskRequest): Promise<CrossDeviceQueryResult> {
    const overallDeadlineAtMs: number = this.clock() + request.latencyBudgetMs;
    if (this.destroyed) {
      return CrossDeviceQueryResult.failed('REMOTE_CHANNEL_DESTROYED');
    }
    const peers: CollaborationPeer[] = await this.directory.routablePeers();
    const profiles: RemoteKnowledgeProfile[] = await this.profiles.listFresh(this.clock());
    const byPeer: Map<string, RemoteKnowledgeProfile> = new Map<string, RemoteKnowledgeProfile>();
    profiles.forEach((profile: RemoteKnowledgeProfile): void => {
      byPeer.set(profile.peerKey, profile);
    });
    const candidates: DeviceRoutingCandidate[] = [];
    peers.forEach((peer: CollaborationPeer): void => {
      const profile: RemoteKnowledgeProfile | undefined = byPeer.get(peer.peerKey);
      if (profile !== undefined && this.client.isPeerConnected(peer.peerKey)) {
        candidates.push(candidate(peer, profile));
      }
    });
    const routing: RoutingResult = this.router.route(request, candidates, this.clock());
    const remotes: RoutedDevice[] = routing.routed.filter(
      (routed: RoutedDevice): boolean => !routed.candidate.snapshot.isLocal
    );
    this.lastAvailable = remotes.length > 0;
    if (remotes.length === 0) {
      return CrossDeviceQueryResult.failed('REMOTE_UNAVAILABLE');
    }

    const generation: number = this.bumpGeneration(request.taskId);
    const first: CrossDeviceQueryResult = await this.client.query(
      remotes[0].candidate.snapshot.deviceId,
      request,
      remotes[0].matchedDomain
    );
    if (this.generations.get(request.taskId) !== generation) {
      return CrossDeviceQueryResult.cancelledResult();
    }
    if (!isFallbackEligible(first) || remotes.length < 2) {
      return first;
    }
    const remainingMs: number = overallDeadlineAtMs - this.clock();
    if (remainingMs <= 0) {
      return CrossDeviceQueryResult.timeout();
    }
    const fallbackRequest: TaskRequest = {
      semanticContractVersion: request.semanticContractVersion,
      taskId: request.taskId,
      queryText: request.queryText,
      requiredConcepts: request.requiredConcepts.slice(),
      requiredConfidence: request.requiredConfidence,
      coverageThreshold: request.coverageThreshold,
      latencyBudgetMs: remainingMs,
      byteBudget: request.byteBudget,
      privacyLevel: request.privacyLevel,
      acceptableLevels: request.acceptableLevels.slice(),
      filters: request.filters
    };
    const second: CrossDeviceQueryResult = await this.client.query(
      remotes[1].candidate.snapshot.deviceId,
      fallbackRequest,
      remotes[1].matchedDomain
    );
    return this.generations.get(request.taskId) === generation
      ? second : CrossDeviceQueryResult.cancelledResult();
  }

  cancel(internalTaskId: string): void {
    this.bumpGeneration(internalTaskId);
    this.client.cancel(internalTaskId);
  }

  private bumpGeneration(taskId: string): number {
    const generation: number = (this.generations.get(taskId) ?? 0) + 1;
    this.generations.delete(taskId);
    this.generations.set(taskId, generation);
    while (this.generations.size > 128) {
      const oldest: string | undefined = this.generations.keys().next().value;
      if (oldest === undefined) {
        break;
      }
      this.generations.delete(oldest);
    }
    return generation;
  }

  getAvailablePeers(): Promise<CollaborationPeer[]> {
    return this.directory.routablePeers();
  }

  getRemoteProfiles(): Promise<RemoteKnowledgeProfile[]> {
    return this.profiles.listFresh(this.clock());
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.generations.clear();
    this.client.destroy();
  }
}
