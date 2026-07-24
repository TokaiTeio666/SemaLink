import { common } from '@kit.AbilityKit';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { SemanticKnowledgeProvider } from
  '../../contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUnit, TaskRequest } from
  '../../contracts/semantic/SemanticModels';
import { KnowledgeProfile } from '../../contracts/knowledge/KnowledgeModels';
import {
  CrossDeviceAvailability,
  CrossDeviceKnowledgePort,
  CrossDeviceQueryResult
} from '../../agent/query/CrossDeviceKnowledgePort';
import { KnowledgeDatabase } from '../../knowledge/storage/KnowledgeDatabase';
import {
  CrossDeviceKnowledgeQueryService,
  LocalEvidenceSearch,
  RemoteEvidenceSearch
} from '../application/CrossDeviceKnowledgeQueryService';
import {
  CollaborationPeer,
  LocalCollaborationIdentity,
  RemoteAccessRecord,
  RemoteKnowledgeProfile
} from '../model/CollaborationModels';
import { SharingPolicy } from '../model/SharingPolicy';
import {
  RdbCollaborationPeerRepository,
  RdbLocalCollaborationIdentityRepository,
  RdbRemoteAccessRecordRepository,
  RdbRemoteKnowledgeProfileRepository,
  RdbSharingPolicyRepository
} from '../storage/RdbCollaborationRepositories';
import {
  SystemTrustedDeviceSource,
  SystemVisibleDevice
} from '../trust/SystemTrustedDeviceSource';
import { TrustedDeviceDirectory } from '../trust/TrustedDeviceDirectory';
import { PeerTransportMapping } from '../trust/PeerTransportMapping';
import {
  HarmonyCrossDeviceKnowledgePort
} from '../transport/HarmonyCrossDeviceKnowledgePort';
import { HarmonyCrossDeviceSession } from '../transport/HarmonyCrossDeviceSession';
import { HarmonyProfileMessageHandler } from '../transport/HarmonyCrossDeviceSession';
import { RemoteKnowledgeQueryServer } from '../query/RemoteKnowledgeQueryServer';
import { KnowledgeProfileDigestBuilder } from '../profile/KnowledgeProfileDigestBuilder';
import {
  KnowledgeProfileExchangeService
} from '../profile/KnowledgeProfileExchangeService';
import { RemoteKnowledgeProfileCache } from
  '../profile/RemoteKnowledgeProfileCache';
import { DskControlHub } from '../../communication/control/DskControlHub';

export interface ProfileRefreshSummary {
  succeeded: number;
  skipped: number;
  failed: number;
}

const PROFILE_REFRESH_TIMEOUT_MS: number = 5000;

function announceWithin(announce: () => Promise<void>,
  timeoutMs: number): Promise<boolean> {
  return new Promise<boolean>((resolve: (succeeded: boolean) => void): void => {
    let settled: boolean = false;
    let timer: number = 0;
    const finish = (succeeded: boolean): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve(succeeded);
    };
    timer = setTimeout(
      (): void => finish(false), Math.max(1, timeoutMs));
    try {
      announce().then((): void => finish(true)).catch((): void => finish(false));
    } catch (_) {
      finish(false);
    }
  });
}

export async function refreshRemoteProfiles(peers: CollaborationPeer[],
  isConnected: (peerKey: string) => boolean,
  announce: (peerKey: string) => Promise<void>,
  markOffline: (peer: CollaborationPeer) => Promise<void>,
  timeoutMs: number = PROFILE_REFRESH_TIMEOUT_MS): Promise<ProfileRefreshSummary> {
  const summary: ProfileRefreshSummary = {
    succeeded: 0,
    skipped: 0,
    failed: 0
  };
  await Promise.all(peers.map(async (peer: CollaborationPeer): Promise<void> => {
    if (!isConnected(peer.peerKey)) {
      summary.skipped++;
      await markOffline(peer).catch((): void => {});
      return;
    }
    const succeeded: boolean = await announceWithin(
      (): Promise<void> => announce(peer.peerKey), timeoutMs);
    if (succeeded) {
      summary.succeeded++;
      return;
    }
    summary.failed++;
    await markOffline(peer).catch((): void => {});
  }));
  return summary;
}

function bytesToHex(bytes: Uint8Array): string {
  let result: string = '';
  for (let index: number = 0; index < bytes.length; index++) {
    result += bytes[index].toString(16).padStart(2, '0');
  }
  return result;
}

async function generateAppInstanceId(): Promise<string> {
  const random = cryptoFramework.createRandom();
  const blob = await random.generateRandom(16);
  return 'sl-' + bytesToHex(new Uint8Array(blob.data as ArrayBuffer));
}

class ProviderEvidenceSearchAdapter implements LocalEvidenceSearch {
  private readonly provider: SemanticKnowledgeProvider;
  constructor(provider: SemanticKnowledgeProvider) {
    this.provider = provider;
  }
  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    return this.provider.searchEvidence(task);
  }
}

class PortEvidenceSearchAdapter implements RemoteEvidenceSearch {
  private readonly port: CrossDeviceKnowledgePort;
  constructor(port: CrossDeviceKnowledgePort) {
    this.port = port;
  }
  search(task: TaskRequest): Promise<CrossDeviceQueryResult> {
    return this.port.search(task);
  }
  cancel(taskId: string): void {
    this.port.cancel(taskId);
  }
}

class RuntimeProfileHandler implements HarmonyProfileMessageHandler {
  private readonly identity: LocalCollaborationIdentity;
  private readonly directory: TrustedDeviceDirectory;
  private readonly provider: SemanticKnowledgeProvider;
  private readonly exchange: KnowledgeProfileExchangeService;
  private readonly session: HarmonyCrossDeviceSession;
  private readonly digestBuilder: KnowledgeProfileDigestBuilder =
    new KnowledgeProfileDigestBuilder();

  constructor(identity: LocalCollaborationIdentity, directory: TrustedDeviceDirectory,
    provider: SemanticKnowledgeProvider, exchange: KnowledgeProfileExchangeService,
    session: HarmonyCrossDeviceSession) {
    this.identity = identity;
    this.directory = directory;
    this.provider = provider;
    this.exchange = exchange;
    this.session = session;
  }

  onHello(peerKey: string, deviceAlias: string): void {
    this.directory.observeCandidate(peerKey, deviceAlias, true)
      .then((peer: CollaborationPeer): Promise<void> => {
        return peer.trustState === 'TRUSTED'
          ? this.announce(peerKey) : Promise.resolve();
      })
      .catch((): void => {});
  }

  onDisconnect(peerKey: string): void {
    this.directory.get(peerKey).then((peer: CollaborationPeer | undefined): Promise<void> => {
      if (peer === undefined) {
        return Promise.resolve();
      }
      return this.directory.observeCandidate(peerKey, peer.deviceAlias, false)
        .then((): void => {});
    }).catch((): void => {});
  }

  onDigest(peerKey: string, profileVersion: string, profileDigest: string): void {
    this.ifTrusted(peerKey, (): Promise<void> =>
      this.exchange.onRemoteDigest(peerKey, profileVersion, profileDigest))
      .catch((): void => {});
  }

  onProfileRequest(peerKey: string): void {
    this.ifTrusted(peerKey, async (): Promise<void> => {
      const profile: RemoteKnowledgeProfile = await this.buildLocalProfile();
      await this.session.sendProfile(peerKey, profile);
    }).catch((): void => {});
  }

  onProfile(peerKey: string, profile: RemoteKnowledgeProfile): void {
    this.ifTrusted(peerKey, (): Promise<void> => {
      const nowMs: number = Date.now();
      const accepted = new RemoteKnowledgeProfile(
        peerKey,
        profile.profileVersion,
        profile.profileDigest,
        profile.indexState,
        profile.knowledgeDomains,
        profile.documentCount,
        profile.chunkCount,
        profile.retrievalModes,
        profile.supportedLevels,
        profile.updatedAtMs,
        nowMs,
        nowMs + 5 * 60 * 1000
      );
      return this.exchange.acceptProfile(accepted);
    }).catch((): void => {});
  }

  async announce(peerKey: string): Promise<void> {
    const profile: KnowledgeProfile = await this.provider.getProfile();
    const digest: string = await this.digestBuilder.digest(profile);
    await this.exchange.announce(peerKey, profile.profileVersion, digest);
  }

  async announceIfTrusted(peerKey: string): Promise<void> {
    await this.ifTrusted(peerKey, (): Promise<void> => this.announce(peerKey));
  }

  private async ifTrusted(peerKey: string,
    action: () => Promise<void>): Promise<void> {
    const peer: CollaborationPeer | undefined = await this.directory.get(peerKey);
    if (peer !== undefined && peer.trustState === 'TRUSTED') {
      await action();
    }
  }

  private async buildLocalProfile(): Promise<RemoteKnowledgeProfile> {
    const profile: KnowledgeProfile = await this.provider.getProfile();
    const digest: string = await this.digestBuilder.digest(profile);
    const indexState: 'NOT_READY' | 'INDEXING' | 'READY' =
      profile.indexState === 'READY' ? 'READY' :
        profile.indexState === 'BUILDING' ? 'INDEXING' : 'NOT_READY';
    const domains: string[] = profile.knowledgeDomains.map(
      (domain): string => domain.tag
    ).slice(0, 20);
    const nowMs: number = Date.now();
    return new RemoteKnowledgeProfile(
      this.identity.appInstanceId,
      profile.profileVersion,
      digest,
      indexState,
      domains,
      profile.documentCount,
      profile.chunkCount,
      profile.retrievalModes,
      profile.supportedLevels,
      profile.updatedAt,
      nowMs,
      nowMs + 5 * 60 * 1000
    );
  }
}

export class CrossDeviceRuntime {
  identity: LocalCollaborationIdentity;
  readonly directory: TrustedDeviceDirectory;
  readonly port: HarmonyCrossDeviceKnowledgePort;
  readonly queries: CrossDeviceKnowledgeQueryService;
  private readonly identityRepository: RdbLocalCollaborationIdentityRepository;
  private readonly profileRepository: RdbRemoteKnowledgeProfileRepository;
  private readonly profileCache: RemoteKnowledgeProfileCache;
  private readonly policyRepository: RdbSharingPolicyRepository;
  private readonly accessRepository: RdbRemoteAccessRecordRepository;
  private readonly source: SystemTrustedDeviceSource;
  private readonly session: HarmonyCrossDeviceSession;
  private readonly server: RemoteKnowledgeQueryServer;
  private readonly profileHandler: RuntimeProfileHandler;
  private destroyed: boolean = false;

  private constructor(identity: LocalCollaborationIdentity,
    identityRepository: RdbLocalCollaborationIdentityRepository,
    directory: TrustedDeviceDirectory,
    profileRepository: RdbRemoteKnowledgeProfileRepository,
    profileCache: RemoteKnowledgeProfileCache,
    policyRepository: RdbSharingPolicyRepository,
    accessRepository: RdbRemoteAccessRecordRepository,
    source: SystemTrustedDeviceSource,
    server: RemoteKnowledgeQueryServer,
    profileHandler: RuntimeProfileHandler,
    session: HarmonyCrossDeviceSession,
    port: HarmonyCrossDeviceKnowledgePort,
    queries: CrossDeviceKnowledgeQueryService) {
    this.identity = identity;
    this.identityRepository = identityRepository;
    this.directory = directory;
    this.profileRepository = profileRepository;
    this.profileCache = profileCache;
    this.policyRepository = policyRepository;
    this.accessRepository = accessRepository;
    this.source = source;
    this.server = server;
    this.profileHandler = profileHandler;
    this.session = session;
    this.port = port;
    this.queries = queries;
  }

  static async create(context: common.UIAbilityContext, database: KnowledgeDatabase,
    provider: SemanticKnowledgeProvider, sharedHub?: DskControlHub): Promise<CrossDeviceRuntime> {
    const clock = (): number => Date.now();
    const identityRepository = new RdbLocalCollaborationIdentityRepository(database);
    let identity: LocalCollaborationIdentity | undefined = await identityRepository.load();
    if (identity === undefined) {
      const nowMs: number = clock();
      identity = new LocalCollaborationIdentity(
        await generateAppInstanceId(),
        'SemaLink Device',
        nowMs,
        nowMs,
        1
      );
      await identityRepository.save(identity);
    }
    const peers = new RdbCollaborationPeerRepository(database);
    const profiles = new RdbRemoteKnowledgeProfileRepository(database);
    const policies = new RdbSharingPolicyRepository(database, clock);
    const accessRecords = new RdbRemoteAccessRecordRepository(database);
    const directory = new TrustedDeviceDirectory(peers, clock);
    await directory.resetOnlineStates();
    const server = new RemoteKnowledgeQueryServer(
      provider, peers, policies, accessRecords, clock
    );
    const mapping = new PeerTransportMapping();
    const session = new HarmonyCrossDeviceSession(
      context,
      context.applicationInfo.name,
      identity.appInstanceId,
      identity.deviceAlias,
      mapping,
      server,
      accessRecords,
      undefined,
      sharedHub
    );
    const exchange = new KnowledgeProfileExchangeService(profiles, session);
    const profileCache = new RemoteKnowledgeProfileCache(profiles);
    const profileHandler = new RuntimeProfileHandler(
      identity, directory, provider, exchange, session
    );
    session.setProfileHandler(profileHandler);
    const port = new HarmonyCrossDeviceKnowledgePort(
      directory, profiles, session, clock
    );
    const queries = new CrossDeviceKnowledgeQueryService(
      new ProviderEvidenceSearchAdapter(provider),
      new PortEvidenceSearchAdapter(port)
    );
    const source = new SystemTrustedDeviceSource(context.applicationInfo.name);
    return new CrossDeviceRuntime(
      identity, identityRepository, directory, profiles, profileCache, policies,
      accessRecords, source, server, profileHandler, session, port, queries
    );
  }

  listVisibleDevices(): Promise<SystemVisibleDevice[]> {
    return this.source.listVisible();
  }

  listPeers(): Promise<CollaborationPeer[]> {
    return this.directory.list();
  }

  async listProfiles(): Promise<RemoteKnowledgeProfile[]> {
    const nowMs: number = Date.now();
    const peers: CollaborationPeer[] = await this.directory.list();
    const retained: RemoteKnowledgeProfile[] = [];
    for (const peer of peers) {
      const profile: RemoteKnowledgeProfile | undefined = await this.profileCache.get(
        peer.peerKey, nowMs, peer.onlineState === 'ONLINE'
      );
      if (profile !== undefined) {
        retained.push(profile);
      }
    }
    return retained;
  }

  async refreshProfiles(): Promise<ProfileRefreshSummary> {
    const peers: CollaborationPeer[] = await this.directory.routablePeers();
    return refreshRemoteProfiles(
      peers,
      (peerKey: string): boolean => this.session.isPeerConnected(peerKey),
      (peerKey: string): Promise<void> => this.profileHandler.announce(peerKey),
      (peer: CollaborationPeer): Promise<void> =>
        this.directory.observeCandidate(peer.peerKey, peer.deviceAlias, false)
          .then((): void => {})
    );
  }

  listAccessRecords(): Promise<RemoteAccessRecord[]> {
    return this.accessRepository.listRecent(128);
  }

  sharingPolicy(): Promise<SharingPolicy> {
    return this.policyRepository.load();
  }

  async saveSharingPolicy(policy: SharingPolicy): Promise<void> {
    await this.policyRepository.save(policy);
    this.server.policyChanged();
  }

  async trust(peerKey: string): Promise<void> {
    await this.directory.trust(peerKey);
    await this.profileHandler.announceIfTrusted(peerKey);
  }

  async block(peerKey: string): Promise<void> {
    await this.directory.block(peerKey);
    await this.session.disconnectPeer(peerKey);
  }

  async revoke(peerKey: string): Promise<void> {
    await this.directory.revoke(peerKey);
    await this.session.disconnectPeer(peerKey);
  }

  renamePeer(peerKey: string, alias: string): Promise<void> {
    return this.directory.rename(peerKey, alias);
  }

  async renameLocal(alias: string): Promise<void> {
    const renamed: LocalCollaborationIdentity =
      this.identity.rename(alias, Date.now());
    await this.identityRepository.save(renamed);
    this.identity = renamed;
    this.session.updateLocalAlias(renamed.deviceAlias);
  }

  connect(peerKey: string, device: SystemVisibleDevice): Promise<void> {
    return this.session.connect(
      peerKey, device.transportReference, device.alias, device.deviceType
    ).then((): Promise<void> => this.profileHandler.announceIfTrusted(peerKey));
  }

  connectCandidate(device: SystemVisibleDevice): Promise<void> {
    const temporaryPeerKey: string = 'pending-' + Date.now() + '-' +
      Math.floor(Math.random() * 100000);
    return this.session.connect(
      temporaryPeerKey,
      device.transportReference,
      device.alias,
      device.deviceType
    );
  }

  accept(want: Record<string, Object>): boolean {
    return this.session.accept(want);
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.source.destroy();
    this.server.destroy();
    this.port.destroy();
  }
}
