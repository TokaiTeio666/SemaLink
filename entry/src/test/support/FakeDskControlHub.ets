export class FakeDskControlHub {
  private readonly payloads: string[] = [];
  private readonly connected = new Set<string>();
  private readonly failed = new Set<string>();

  async connect(deviceId: string): Promise<void> {
    if (this.failed.has(deviceId)) throw new Error('E_DSK_CONNECT_FAILED');
    this.connected.add(deviceId);
    this.payloads.push('CONNECT');
  }

  disconnect(deviceId: string): void {
    this.connected.delete(deviceId);
    this.payloads.push('DISCONNECT');
  }

  failConnection(deviceId: string): void { this.failed.add(deviceId); }

  send(deviceId: string, payloadType: string): Promise<void> {
    if (!this.connected.has(deviceId)) return Promise.reject(new Error('E_DSK_DISCONNECTED'));
    if (payloadType === 'TASK' || payloadType === 'EVIDENCE_BATCH') {
      return Promise.reject(new Error('E_DSK_BUSINESS_PAYLOAD'));
    }
    this.payloads.push(payloadType);
    return Promise.resolve();
  }

  payloadTypes(): string[] { return this.payloads.slice(); }
}
