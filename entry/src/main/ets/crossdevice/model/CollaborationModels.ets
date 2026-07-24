import { EvidenceLevel } from '../../contracts/semantic/SemanticModels';

export type PeerTrustState = 'PENDING' | 'TRUSTED' | 'BLOCKED' | 'REVOKED';
export type PeerOnlineState = 'ONLINE' | 'OFFLINE';
export type RemoteAccessDirection = 'INBOUND' | 'OUTBOUND';

function requireText(value: string, field: string): void {
  if (value.trim().length === 0) {
    throw new Error(field + ' is required');
  }
}

export class LocalCollaborationIdentity {
  readonly appInstanceId: string;
  readonly deviceAlias: string;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;
  readonly revision: number;

  constructor(appInstanceId: string, deviceAlias: string, createdAtMs: number,
    updatedAtMs: number, revision: number) {
    requireText(appInstanceId, 'appInstanceId');
    requireText(deviceAlias, 'deviceAlias');
    if (createdAtMs < 0 || updatedAtMs < createdAtMs || revision < 1) {
      throw new Error('invalid collaboration identity metadata');
    }
    this.appInstanceId = appInstanceId;
    this.deviceAlias = deviceAlias;
    this.createdAtMs = createdAtMs;
    this.updatedAtMs = updatedAtMs;
    this.revision = revision;
  }

  rename(deviceAlias: string, updatedAtMs: number): LocalCollaborationIdentity {
    return new LocalCollaborationIdentity(
      this.appInstanceId,
      deviceAlias,
      this.createdAtMs,
      updatedAtMs,
      this.revision + 1
    );
  }
}

export class CollaborationPeer {
  readonly peerKey: string;
  readonly deviceAlias: string;
  readonly trustState: PeerTrustState;
  readonly onlineState: PeerOnlineState;
  readonly lastSeenAtMs: number;
  readonly profileVersion: string;
  readonly profileDigest: string;
  readonly createdAtMs: number;
  readonly updatedAtMs: number;

  constructor(peerKey: string, deviceAlias: string, trustState: PeerTrustState,
    onlineState: PeerOnlineState, lastSeenAtMs: number, profileVersion: string,
    profileDigest: string, createdAtMs: number, updatedAtMs: number) {
    requireText(peerKey, 'peerKey');
    requireText(deviceAlias, 'deviceAlias');
    this.peerKey = peerKey;
    this.deviceAlias = deviceAlias;
    this.trustState = trustState;
    this.onlineState = onlineState;
    this.lastSeenAtMs = lastSeenAtMs;
    this.profileVersion = profileVersion;
    this.profileDigest = profileDigest;
    this.createdAtMs = createdAtMs;
    this.updatedAtMs = updatedAtMs;
  }

  static pending(peerKey: string, deviceAlias: string, nowMs: number): CollaborationPeer {
    return new CollaborationPeer(
      peerKey, deviceAlias, 'PENDING', 'OFFLINE', 0, '', '', nowMs, nowMs
    );
  }

  withTrustState(trustState: PeerTrustState, updatedAtMs: number): CollaborationPeer {
    return new CollaborationPeer(
      this.peerKey, this.deviceAlias, trustState, this.onlineState, this.lastSeenAtMs,
      this.profileVersion, this.profileDigest, this.createdAtMs, updatedAtMs
    );
  }

  withOnlineState(onlineState: PeerOnlineState, updatedAtMs: number): CollaborationPeer {
    return new CollaborationPeer(
      this.peerKey, this.deviceAlias, this.trustState, onlineState,
      onlineState === 'ONLINE' ? updatedAtMs : this.lastSeenAtMs,
      this.profileVersion, this.profileDigest, this.createdAtMs, updatedAtMs
    );
  }

  withProfile(profileVersion: string, profileDigest: string, updatedAtMs: number): CollaborationPeer {
    return new CollaborationPeer(
      this.peerKey, this.deviceAlias, this.trustState, this.onlineState, this.lastSeenAtMs,
      profileVersion, profileDigest, this.createdAtMs, updatedAtMs
    );
  }

  rename(deviceAlias: string, updatedAtMs: number): CollaborationPeer {
    return new CollaborationPeer(
      this.peerKey, deviceAlias, this.trustState, this.onlineState, this.lastSeenAtMs,
      this.profileVersion, this.profileDigest, this.createdAtMs, updatedAtMs
    );
  }
}

export function canExchangeProfile(peer: CollaborationPeer): boolean {
  return peer.trustState === 'TRUSTED';
}

export function canRouteToPeer(peer: CollaborationPeer): boolean {
  return peer.trustState === 'TRUSTED' && peer.onlineState === 'ONLINE';
}

export class RemoteKnowledgeProfile {
  readonly peerKey: string;
  readonly profileVersion: string;
  readonly profileDigest: string;
  readonly indexState: 'NOT_READY' | 'INDEXING' | 'READY';
  readonly knowledgeDomains: string[];
  readonly documentCount: number;
  readonly chunkCount: number;
  readonly retrievalModes: string[];
  readonly supportedLevels: EvidenceLevel[];
  readonly updatedAtMs: number;
  readonly receivedAtMs: number;
  readonly expiresAtMs: number;

  constructor(peerKey: string, profileVersion: string, profileDigest: string,
    indexState: 'NOT_READY' | 'INDEXING' | 'READY', knowledgeDomains: string[],
    documentCount: number, chunkCount: number, retrievalModes: string[],
    supportedLevels: EvidenceLevel[], updatedAtMs: number, receivedAtMs: number,
    expiresAtMs: number) {
    requireText(peerKey, 'peerKey');
    if (knowledgeDomains.length > 20 || documentCount < 0 || chunkCount < 0 ||
      expiresAtMs < receivedAtMs) {
      throw new Error('invalid remote knowledge profile');
    }
    this.peerKey = peerKey;
    this.profileVersion = profileVersion;
    this.profileDigest = profileDigest;
    this.indexState = indexState;
    this.knowledgeDomains = knowledgeDomains.slice();
    this.documentCount = documentCount;
    this.chunkCount = chunkCount;
    this.retrievalModes = retrievalModes.slice();
    this.supportedLevels = supportedLevels.slice();
    this.updatedAtMs = updatedAtMs;
    this.receivedAtMs = receivedAtMs;
    this.expiresAtMs = expiresAtMs;
  }
}

export class RemoteAccessRecord {
  readonly recordId: string;
  readonly direction: RemoteAccessDirection;
  readonly peerKey: string;
  readonly taskId: string;
  readonly domainSummary: string;
  readonly requestedLevel: EvidenceLevel;
  readonly evidenceCount: number;
  readonly status: string;
  readonly startedAtMs: number;
  readonly completedAtMs: number;

  constructor(recordId: string, direction: RemoteAccessDirection, peerKey: string,
    taskId: string, domainSummary: string, requestedLevel: EvidenceLevel,
    evidenceCount: number, status: string, startedAtMs: number, completedAtMs: number) {
    requireText(recordId, 'recordId');
    requireText(peerKey, 'peerKey');
    this.recordId = recordId;
    this.direction = direction;
    this.peerKey = peerKey;
    this.taskId = taskId;
    this.domainSummary = domainSummary;
    this.requestedLevel = requestedLevel;
    this.evidenceCount = evidenceCount;
    this.status = status;
    this.startedAtMs = startedAtMs;
    this.completedAtMs = completedAtMs;
  }
}
