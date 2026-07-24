import {
  CollaborationPeer,
  PeerOnlineState,
  PeerTrustState
} from '../model/CollaborationModels';
import { CollaborationPeerRepository } from '../storage/CollaborationRepositories';

export type CollaborationClock = () => number;

export class TrustedDeviceDirectory {
  private readonly repository: CollaborationPeerRepository;
  private readonly clock: CollaborationClock;

  constructor(repository: CollaborationPeerRepository, clock: CollaborationClock) {
    this.repository = repository;
    this.clock = clock;
  }

  async observeCandidate(peerKey: string, alias: string, online: boolean): Promise<CollaborationPeer> {
    const existing: CollaborationPeer | undefined = await this.repository.get(peerKey);
    const onlineState: PeerOnlineState = online ? 'ONLINE' : 'OFFLINE';
    const observed: CollaborationPeer = existing === undefined
      ? CollaborationPeer.pending(peerKey, alias, this.clock()).withOnlineState(onlineState, this.clock())
      : existing.withOnlineState(onlineState, this.clock());
    await this.repository.save(observed);
    return observed;
  }

  async list(): Promise<CollaborationPeer[]> {
    return this.repository.list();
  }

  get(peerKey: string): Promise<CollaborationPeer | undefined> {
    return this.repository.get(peerKey);
  }

  async routablePeers(): Promise<CollaborationPeer[]> {
    const peers = await this.repository.list();
    return peers.filter((peer: CollaborationPeer): boolean => {
      return peer.trustState === 'TRUSTED' && peer.onlineState === 'ONLINE';
    });
  }

  async resetOnlineStates(): Promise<void> {
    const peers: CollaborationPeer[] = await this.repository.list();
    for (const peer of peers) {
      if (peer.onlineState === 'ONLINE') {
        await this.repository.save(peer.withOnlineState('OFFLINE', this.clock()));
      }
    }
  }

  async trust(peerKey: string): Promise<void> {
    await this.updateTrustState(peerKey, 'TRUSTED');
  }

  async block(peerKey: string): Promise<void> {
    await this.updateTrustState(peerKey, 'BLOCKED');
  }

  async revoke(peerKey: string): Promise<void> {
    await this.updateTrustState(peerKey, 'REVOKED');
  }

  async rename(peerKey: string, alias: string): Promise<void> {
    const peer = await this.requirePeer(peerKey);
    await this.repository.save(peer.rename(alias, this.clock()));
  }

  private async updateTrustState(peerKey: string, state: PeerTrustState): Promise<void> {
    const peer = await this.requirePeer(peerKey);
    await this.repository.save(peer.withTrustState(state, this.clock()));
  }

  private async requirePeer(peerKey: string): Promise<CollaborationPeer> {
    const peer: CollaborationPeer | undefined = await this.repository.get(peerKey);
    if (peer === undefined) {
      throw new Error('Unknown collaboration peer');
    }
    return peer;
  }
}
