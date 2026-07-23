import { common } from '@kit.AbilityKit';
import {
  CrossDeviceQueryResult
} from '../../agent/query/CrossDeviceKnowledgePort';
import { Logger } from '../../common/Logger';
import {
  EvidenceUnit,
  TaskRequest
} from '../../contracts/semantic/SemanticModels';
import { PeerDevice } from '../../model/AppModels';
import {
  DskControlHub,
  DskControlHubListener
} from '../../communication/control/DskControlHub';
import { DskDataChannel } from '../../communication/control/DskDataChannel';
import { ControlEnvelope } from '../../communication/control/ControlModels';
import { AppError } from '../../common/AppError';
import {
  CrossDeviceEnvelope
} from '../protocol/CrossDeviceProtocolModels';
import {
  CrossDeviceProtocolCodec
} from '../protocol/CrossDeviceProtocolCodec';
import {
  InboundRemoteQuery,
  RemoteKnowledgeQueryServer,
  RemoteQueryResult
} from '../query/RemoteKnowledgeQueryServer';
import { RemoteEvidence } from '../query/RemoteEvidenceSanitizer';
import {
  RemoteAccessRecord,
  RemoteKnowledgeProfile
} from '../model/CollaborationModels';
import { RemoteAccessRecordRepository } from
  '../storage/CollaborationRepositories';
import { ProfileExchangeSender } from '../profile/KnowledgeProfileExchangeService';
import { PeerTransportMapping } from '../trust/PeerTransportMapping';
import { HarmonyRemoteQueryClient } from './HarmonyCrossDeviceKnowledgePort';

const SESSION_TIMEOUT_MS: number = 5000;

export class BoundedReconnectPolicy {
  readonly maximumAttempts: number;
  private readonly baseDelayMs: number;
  private readonly maximumDelayMs: number;

  constructor(maximumAttempts: number = 3, baseDelayMs: number = 100,
    maximumDelayMs: number = 2000) {
    this.maximumAttempts = Math.max(1, Math.min(5, maximumAttempts));
    this.baseDelayMs = Math.max(1, baseDelayMs);
    this.maximumDelayMs = Math.max(this.baseDelayMs, maximumDelayMs);
  }

  delayAfterFailure(attempt: number): number {
    return Math.min(
      this.maximumDelayMs,
      this.baseDelayMs * Math.pow(2, Math.max(0, attempt))
    );
  }
}

class HelloPayload {
  readonly peerKey: string;
  readonly deviceAlias: string;
  constructor(peerKey: string, deviceAlias: string) {
    this.peerKey = peerKey;
    this.deviceAlias = deviceAlias;
  }
}

class QueryRequestPayload {
  readonly query: TaskRequest;
  readonly knowledgeDomain: string;
  constructor(query: TaskRequest, knowledgeDomain: string) {
    this.query = query;
    this.knowledgeDomain = knowledgeDomain;
  }
}

class QueryResponsePayload {
  readonly status: string;
  readonly evidence: RemoteEvidence[];
  readonly truncated: boolean;
  constructor(result: RemoteQueryResult) {
    this.status = result.status;
    this.evidence = result.evidence;
    this.truncated = result.truncated;
  }
}

class CancelPayload {
  readonly taskId: string;
  constructor(taskId: string) {
    this.taskId = taskId;
  }
}

class EmptyProfilePayload {
  readonly requested: boolean = true;
}

class ProfileDigestPayload {
  readonly profileVersion: string;
  readonly profileDigest: string;
  constructor(profileVersion: string, profileDigest: string) {
    this.profileVersion = profileVersion;
    this.profileDigest = profileDigest;
  }
}

class ProfileResponsePayload {
  readonly profile: RemoteKnowledgeProfile;
  constructor(profile: RemoteKnowledgeProfile) {
    this.profile = profile;
  }
}

interface DecodedQueryRequestPayload {
  query: TaskRequest;
  knowledgeDomain: string;
}

interface DecodedQueryResponsePayload {
  status: string;
  evidence: RemoteEvidence[];
  truncated: boolean;
}

interface PendingRemoteQuery {
  taskId: string;
  peerKey: string;
  resolve: (result: CrossDeviceQueryResult) => void;
  timer: number;
}

export function matchesPendingResponse(peerKey: string, requestId: string,
  taskId: string, envelope: CrossDeviceEnvelope): boolean {
  return envelope.senderAppInstanceId === peerKey &&
    envelope.requestId === requestId &&
    envelope.taskId === taskId;
}

interface IncomingPeerInfo {
  deviceId?: string;
}

interface DecodedHelloPayload {
  peerKey: string;
  deviceAlias: string;
}

interface DecodedProfileDigestPayload {
  profileVersion: string;
  profileDigest: string;
}

interface DecodedProfileResponsePayload {
  profile: RemoteKnowledgeProfile;
}

export interface HarmonyProfileMessageHandler {
  onHello(peerKey: string, deviceAlias: string): void;
  onDisconnect(peerKey: string): void;
  onDigest(peerKey: string, profileVersion: string, profileDigest: string): void;
  onProfileRequest(peerKey: string): void;
  onProfile(peerKey: string, profile: RemoteKnowledgeProfile): void;
}

export class HarmonyCrossDeviceSession
implements HarmonyRemoteQueryClient, ProfileExchangeSender, DskControlHubListener {
  private readonly localAppInstanceId: string;
  private localDeviceAlias: string;
  private readonly mapping: PeerTransportMapping;
  private readonly server: RemoteKnowledgeQueryServer | undefined;
  private readonly hub: DskControlHub;
  private readonly ownsHub: boolean;
  private readonly data: DskDataChannel;
  private readonly codec: CrossDeviceProtocolCodec = new CrossDeviceProtocolCodec();
  private readonly pending: Map<string, PendingRemoteQuery> =
    new Map<string, PendingRemoteQuery>();
  private readonly installedTransportReferences: Set<string> = new Set<string>();
  private readonly helloReceived: Set<string> = new Set<string>();
  private destroyed: boolean = false;
  private profileHandler: HarmonyProfileMessageHandler | undefined = undefined;
  private readonly reconnectPolicy: BoundedReconnectPolicy =
    new BoundedReconnectPolicy();
  private readonly accessRecords: RemoteAccessRecordRepository | undefined;

  constructor(context: common.UIAbilityContext, bundleName: string,
    localAppInstanceId: string, localDeviceAlias: string, mapping: PeerTransportMapping,
    server?: RemoteKnowledgeQueryServer,
    accessRecords?: RemoteAccessRecordRepository, logger: Logger = new Logger(),
    sharedHub?: DskControlHub) {
    this.localAppInstanceId = localAppInstanceId;
    this.localDeviceAlias = localDeviceAlias;
    this.mapping = mapping;
    this.server = server;
    this.accessRecords = accessRecords;
    this.ownsHub = sharedHub === undefined;
    this.hub = sharedHub ?? new DskControlHub(context, bundleName, logger, undefined, this);
    if (sharedHub !== undefined) {
      this.hub.setListener(this);
    }
    this.data = new DskDataChannel(this.hub);
  }

  async connect(peerKey: string, transportReference: string, alias: string,
    deviceType: string): Promise<void> {
    this.mapping.bind(transportReference, peerKey);
    this.installHandler(transportReference);
    const peer: PeerDevice = {
      deviceId: transportReference,
      deviceName: alias,
      deviceType: deviceType
    };
    await this.connectWithRetry(peer);
    await this.sendEnvelope(transportReference, new CrossDeviceEnvelope(
      'HELLO',
      this.messageId('hello'),
      this.messageId('hello-request'),
      'hello',
      this.localAppInstanceId,
      Date.now(),
      Date.now() + SESSION_TIMEOUT_MS,
      0,
      new HelloPayload(this.localAppInstanceId, this.localDeviceAlias)
    ));
  }

  private async connectWithRetry(peer: PeerDevice): Promise<void> {
    let lastError: Error = new Error('REMOTE_NETWORK_ERROR');
    for (let attempt: number = 0;
      attempt < this.reconnectPolicy.maximumAttempts; attempt++) {
      try {
        await this.hub.connect(peer);
        return;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error('REMOTE_NETWORK_ERROR');
        if (attempt + 1 >= this.reconnectPolicy.maximumAttempts) {
          break;
        }
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, this.reconnectPolicy.delayAfterFailure(attempt));
        });
      }
    }
    throw lastError;
  }

  setProfileHandler(handler: HarmonyProfileMessageHandler): void {
    this.profileHandler = handler;
    this.hub.deviceIds().forEach((deviceId: string): void =>
      this.installHandler(deviceId));
  }

  updateLocalAlias(alias: string): void {
    this.localDeviceAlias = alias;
  }

  async disconnectPeer(peerKey: string): Promise<void> {
    const transportReference: string | undefined = this.mapping.systemIdFor(peerKey);
    if (transportReference === undefined) {
      return;
    }
    await this.hub.disconnect(transportReference);
    this.helloReceived.delete(transportReference);
    this.mapping.unbindSystemId(transportReference);
    this.failPendingForPeer(peerKey);
    this.profileHandler?.onDisconnect(peerKey);
  }

  sendDigest(peerKey: string, version: string, digest: string): Promise<void> {
    return this.sendProfileEnvelope(
      peerKey, 'PROFILE_DIGEST', new ProfileDigestPayload(version, digest)
    );
  }

  requestProfile(peerKey: string): Promise<void> {
    return this.sendProfileEnvelope(
      peerKey, 'PROFILE_REQUEST', new EmptyProfilePayload()
    );
  }

  sendProfile(peerKey: string, profile: RemoteKnowledgeProfile): Promise<void> {
    return this.sendProfileEnvelope(
      peerKey, 'PROFILE_RESPONSE', new ProfileResponsePayload(profile)
    );
  }

  accept(want: Record<string, Object>): boolean {
    const raw: Object | undefined =
      want['ohos.extra.param.key.supportCollaborateIndex'];
    if (typeof raw !== 'object' || raw === null) {
      return false;
    }
    const values: Record<string, Object> = raw as Record<string, Object>;
    const peer: IncomingPeerInfo = values['PeerInfo'] as IncomingPeerInfo;
    if (peer === undefined || typeof peer.deviceId !== 'string') {
      return false;
    }
    this.installHandler(peer.deviceId);
    return this.hub.accept(want);
  }

  isPeerConnected(peerKey: string): boolean {
    const transportReference: string | undefined =
      this.mapping.systemIdFor(peerKey);
    return transportReference !== undefined &&
      this.hub.stateOf(transportReference) === 'READY' &&
      this.helloReceived.has(transportReference);
  }

  async query(peerKey: string, request: TaskRequest,
    matchedDomain: string = ''): Promise<CrossDeviceQueryResult> {
    if (this.destroyed) {
      return CrossDeviceQueryResult.failed('REMOTE_NETWORK_ERROR');
    }
    const transportReference: string | undefined = this.mapping.systemIdFor(peerKey);
    if (transportReference === undefined || !this.isPeerConnected(peerKey)) {
      return CrossDeviceQueryResult.failed('REMOTE_NETWORK_ERROR');
    }
    const requestId: string = this.messageId('query');
    const sentAtMs: number = Date.now();
    const deadlineAtMs: number = sentAtMs + Math.min(SESSION_TIMEOUT_MS, request.latencyBudgetMs);
    const result = new Promise<CrossDeviceQueryResult>(
      (resolve: (value: CrossDeviceQueryResult) => void): void => {
        const timer: number = setTimeout((): void => {
          this.pending.delete(requestId);
          resolve(CrossDeviceQueryResult.timeout());
        }, Math.max(1, deadlineAtMs - Date.now()));
        this.pending.set(requestId, {
          taskId: request.taskId,
          peerKey: peerKey,
          resolve: resolve,
          timer: timer
        });
      }
    );
    try {
      await this.sendEnvelope(transportReference, new CrossDeviceEnvelope(
        'QUERY_REQUEST',
        this.messageId('message'),
        requestId,
        request.taskId,
        this.localAppInstanceId,
        sentAtMs,
        deadlineAtMs,
        0,
        new QueryRequestPayload(request, matchedDomain)
      ));
    } catch (_) {
      const pending: PendingRemoteQuery | undefined = this.pending.get(requestId);
      if (pending !== undefined) {
        clearTimeout(pending.timer);
        this.pending.delete(requestId);
        pending.resolve(CrossDeviceQueryResult.failed('REMOTE_NETWORK_ERROR'));
      }
    }
    const completed: CrossDeviceQueryResult = await result;
    this.recordOutbound(
      requestId, peerKey, request, matchedDomain, sentAtMs, completed
    );
    return completed;
  }

  cancel(taskId: string): void {
    const entries: Array<[string, PendingRemoteQuery]> =
      Array.from(this.pending.entries());
    entries.forEach((entry: [string, PendingRemoteQuery]): void => {
      const requestId: string = entry[0];
      const pending: PendingRemoteQuery = entry[1];
      if (pending.taskId !== taskId) {
        return;
      }
      clearTimeout(pending.timer);
      this.pending.delete(requestId);
      pending.resolve(CrossDeviceQueryResult.cancelledResult());
      const transportReference: string | undefined =
        this.mapping.systemIdFor(pending.peerKey);
      if (transportReference !== undefined) {
        const nowMs: number = Date.now();
        this.sendEnvelope(transportReference, new CrossDeviceEnvelope(
          'QUERY_CANCEL', this.messageId('cancel'), requestId,
          taskId, this.localAppInstanceId, nowMs, nowMs + SESSION_TIMEOUT_MS, 0,
          new CancelPayload(taskId)
        )).catch((): void => {});
      }
    });
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.pending.forEach((pending: PendingRemoteQuery): void => {
      clearTimeout(pending.timer);
      pending.resolve(CrossDeviceQueryResult.cancelledResult());
    });
    this.pending.clear();
    this.helloReceived.clear();
    this.mapping.clear();
    if (this.ownsHub) {
      this.hub.destroy();
    } else {
      this.hub.setListener(null);
    }
  }

  onControlReady(_deviceId: string): void {}
  onControlMessage(_deviceId: string, _envelope: ControlEnvelope): void {}

  onControlClosed(deviceId: string, _error?: AppError): void {
    const peerKey: string | undefined = this.mapping.peerKeyFor(deviceId);
    this.helloReceived.delete(deviceId);
    this.mapping.unbindSystemId(deviceId);
    if (peerKey === undefined) {
      return;
    }
    this.failPendingForPeer(peerKey);
    this.profileHandler?.onDisconnect(peerKey);
  }

  private failPendingForPeer(peerKey: string): void {
    this.pending.forEach((pending: PendingRemoteQuery, requestId: string): void => {
      if (pending.peerKey === peerKey) {
        clearTimeout(pending.timer);
        this.pending.delete(requestId);
        pending.resolve(CrossDeviceQueryResult.failed('REMOTE_NETWORK_ERROR'));
      }
    });
  }

  private installHandler(transportReference: string): void {
    if (this.installedTransportReferences.has(transportReference)) {
      return;
    }
    this.installedTransportReferences.add(transportReference);
    this.data.onMessage(transportReference, (text: string): void => {
      this.receive(transportReference, text);
    });
  }

  private receive(transportReference: string, text: string): void {
    let envelope: CrossDeviceEnvelope;
    try {
      envelope = this.codec.decode(text, Date.now());
    } catch (_) {
      return;
    }
    if (envelope.messageType === 'HELLO') {
      const hello: DecodedHelloPayload = envelope.payload as DecodedHelloPayload;
      const firstHello: boolean = !this.helloReceived.has(transportReference);
      this.helloReceived.add(transportReference);
      this.mapping.bind(transportReference, envelope.senderAppInstanceId);
      this.profileHandler?.onHello(
        envelope.senderAppInstanceId,
        typeof hello.deviceAlias === 'string' ? hello.deviceAlias : 'SemaLink Device'
      );
      if (firstHello) {
        this.sendHello(transportReference).catch((): void => {});
      }
      return;
    }
    const mappedPeerKey: string | undefined =
      this.mapping.peerKeyFor(transportReference);
    if (mappedPeerKey === undefined ||
      mappedPeerKey !== envelope.senderAppInstanceId) {
      return;
    }
    if (envelope.messageType === 'PROFILE_DIGEST') {
      const digest: DecodedProfileDigestPayload =
        envelope.payload as DecodedProfileDigestPayload;
      this.profileHandler?.onDigest(
        envelope.senderAppInstanceId,
        digest.profileVersion,
        digest.profileDigest
      );
      return;
    }
    if (envelope.messageType === 'PROFILE_REQUEST') {
      this.profileHandler?.onProfileRequest(envelope.senderAppInstanceId);
      return;
    }
    if (envelope.messageType === 'PROFILE_RESPONSE') {
      const response: DecodedProfileResponsePayload =
        envelope.payload as DecodedProfileResponsePayload;
      this.profileHandler?.onProfile(
        envelope.senderAppInstanceId,
        response.profile
      );
      return;
    }
    if (envelope.messageType === 'QUERY_RESPONSE' ||
      envelope.messageType === 'QUERY_ERROR') {
      this.completeResponse(envelope);
      return;
    }
    if (envelope.messageType === 'QUERY_CANCEL') {
      this.server?.cancel(mappedPeerKey, envelope.requestId, envelope.taskId);
      return;
    }
    if (envelope.messageType === 'QUERY_REQUEST' && this.server !== undefined) {
      this.handleInbound(transportReference, envelope).catch((): void => {});
    }
  }

  private completeResponse(envelope: CrossDeviceEnvelope): void {
    const pending: PendingRemoteQuery | undefined = this.pending.get(envelope.requestId);
    if (pending === undefined || !matchesPendingResponse(
      pending.peerKey, envelope.requestId, pending.taskId, envelope
    )) {
      return;
    }
    clearTimeout(pending.timer);
    this.pending.delete(envelope.requestId);
    const payload: DecodedQueryResponsePayload =
      envelope.payload as DecodedQueryResponsePayload;
    if (payload.status !== 'OK') {
      pending.resolve(CrossDeviceQueryResult.failed(
        payload.status === 'BUSY' ? 'REMOTE_BUSY' : 'REMOTE_' + payload.status
      ));
      return;
    }
    pending.resolve(CrossDeviceQueryResult.success(
      this.toEvidence(payload.evidence, pending.peerKey, envelope.requestId)
    ));
  }

  private async handleInbound(transportReference: string,
    envelope: CrossDeviceEnvelope): Promise<void> {
    const payload: DecodedQueryRequestPayload =
      envelope.payload as DecodedQueryRequestPayload;
    const peerKey: string = envelope.senderAppInstanceId;
    const result: RemoteQueryResult = await this.server!.handle(new InboundRemoteQuery(
      envelope.requestId,
      peerKey,
      peerKey,
      payload.knowledgeDomain,
      payload.query.acceptableLevels[0],
      payload.query,
      envelope.deadlineAtMs
    ));
    const nowMs: number = Date.now();
    await this.sendEnvelope(transportReference, new CrossDeviceEnvelope(
      result.status === 'OK' ? 'QUERY_RESPONSE' : 'QUERY_ERROR',
      this.messageId('response'),
      envelope.requestId,
      envelope.taskId,
      this.localAppInstanceId,
      nowMs,
      envelope.deadlineAtMs,
      envelope.sequence,
      new QueryResponsePayload(result)
    ));
  }

  private toEvidence(remote: RemoteEvidence[], peerKey: string,
    requestId: string): EvidenceUnit[] {
    return remote.map((item: RemoteEvidence, index: number): EvidenceUnit => {
      const summary: string = item.summary.length > 0 ? item.summary : item.snippet;
      return {
        semanticContractVersion: '1.0',
        evidenceId: requestId + '-' + index,
        evidenceGroupId: requestId,
        sourceDeviceId: peerKey,
        sourceDocId: 'remote-evidence',
        level: item.level,
        title: item.title,
        summary: summary,
        snippet: item.snippet,
        relevance: item.relevance,
        coveredConcepts: [item.knowledgeDomain],
        estimatedCoverageGain: item.relevance,
        byteCost: JSON.stringify(item).length,
        privacyLevel: 'PRIVATE_GROUP',
        privacyCost: item.level === 'L2' ? 0.5 : 0.2,
        energyCost: 0,
        hash: item.title + '|' + summary,
        canEscalateTo: [item.level]
      };
    });
  }

  private sendEnvelope(transportReference: string,
    envelope: CrossDeviceEnvelope): Promise<void> {
    return this.data.send(transportReference, this.codec.encode(envelope));
  }

  private sendHello(transportReference: string): Promise<void> {
    const nowMs: number = Date.now();
    return this.sendEnvelope(transportReference, new CrossDeviceEnvelope(
      'HELLO',
      this.messageId('hello'),
      this.messageId('hello-request'),
      'hello',
      this.localAppInstanceId,
      nowMs,
      nowMs + SESSION_TIMEOUT_MS,
      0,
      new HelloPayload(this.localAppInstanceId, this.localDeviceAlias)
    ));
  }

  private sendProfileEnvelope(peerKey: string, messageType:
    'PROFILE_DIGEST' | 'PROFILE_REQUEST' | 'PROFILE_RESPONSE',
    payload: Object): Promise<void> {
    const transportReference: string | undefined = this.mapping.systemIdFor(peerKey);
    if (transportReference === undefined) {
      return Promise.reject(new Error('REMOTE_NETWORK_ERROR'));
    }
    const nowMs: number = Date.now();
    return this.sendEnvelope(transportReference, new CrossDeviceEnvelope(
      messageType,
      this.messageId('profile-message'),
      this.messageId('profile-request'),
      'profile',
      this.localAppInstanceId,
      nowMs,
      nowMs + SESSION_TIMEOUT_MS,
      0,
      payload
    ));
  }

  private recordOutbound(requestId: string, peerKey: string,
    request: TaskRequest, domain: string, startedAtMs: number,
    result: CrossDeviceQueryResult): void {
    if (this.accessRecords === undefined) {
      return;
    }
    this.accessRecords.save(new RemoteAccessRecord(
        'OUTBOUND|' + peerKey + '|' + requestId,
        'OUTBOUND',
        peerKey,
        request.taskId,
        domain.slice(0, 128),
        request.acceptableLevels[0],
        result.evidence.length,
        result.reason,
        startedAtMs,
        Date.now()
      )).catch((): void => {});
  }

  private findRequestId(target: PendingRemoteQuery): string {
    for (const entry of this.pending.entries()) {
      if (entry[1] === target) {
        return entry[0];
      }
    }
    return '';
  }

  private messageId(prefix: string): string {
    return prefix + '-' + Date.now() + '-' + Math.floor(Math.random() * 100000);
  }
}
