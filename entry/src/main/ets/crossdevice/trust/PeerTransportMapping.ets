export class PeerTransportMapping {
  private readonly peerKeyBySystemId: Map<string, string> = new Map<string, string>();
  private readonly systemIdByPeerKey: Map<string, string> = new Map<string, string>();

  bind(systemDeviceId: string, peerKey: string): void {
    const previousPeerKey = this.peerKeyBySystemId.get(systemDeviceId);
    if (previousPeerKey !== undefined && previousPeerKey !== peerKey) {
      this.systemIdByPeerKey.delete(previousPeerKey);
    }

    const previousSystemId = this.systemIdByPeerKey.get(peerKey);
    if (previousSystemId !== undefined && previousSystemId !== systemDeviceId) {
      this.peerKeyBySystemId.delete(previousSystemId);
    }

    this.peerKeyBySystemId.set(systemDeviceId, peerKey);
    this.systemIdByPeerKey.set(peerKey, systemDeviceId);
  }

  peerKeyFor(systemDeviceId: string): string | undefined {
    return this.peerKeyBySystemId.get(systemDeviceId);
  }

  systemIdFor(peerKey: string): string | undefined {
    return this.systemIdByPeerKey.get(peerKey);
  }

  unbindSystemId(systemDeviceId: string): void {
    const peerKey: string | undefined = this.peerKeyBySystemId.get(systemDeviceId);
    this.peerKeyBySystemId.delete(systemDeviceId);
    if (peerKey !== undefined && this.systemIdByPeerKey.get(peerKey) === systemDeviceId) {
      this.systemIdByPeerKey.delete(peerKey);
    }
  }

  clear(): void {
    this.peerKeyBySystemId.clear();
    this.systemIdByPeerKey.clear();
  }
}
