import { AbilityConstant, common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppError } from '../common/AppError';
import { Logger } from '../common/Logger';
import { CollaborationTransport } from '../communication/CollaborationTransport';
import { TransportListener } from '../communication/Transport';
import { PeerDevice } from '../model/AppModels';
import { DistributedDeviceProvider, TrustedDeviceResolver } from '../communication/TrustedDeviceResolver';

const TAG = 'CollaborationProbe';
const PING_TIMEOUT_MS = 10000;

class ProbeMessage {
  type: string = '';
  probeId: string = '';

  constructor(type: string, probeId: string) {
    this.type = type;
    this.probeId = probeId;
  }
}

class InitiatorListener implements TransportListener {
  private probe: CollaborationProbe;
  private generation: number;

  constructor(probe: CollaborationProbe, generation: number) {
    this.probe = probe;
    this.generation = generation;
  }

  onConnected(): void {
    if (!this.probe.isProbeActive(this.generation)) {
      return;
    }
    this.probe.logger.info(TAG, 'initiator connected, sending PING probeId=' + this.probe.probeId);
    const ping = new ProbeMessage('PING', this.probe.probeId);
    const transport = this.probe.transport;
    if (transport === null) {
      return;
    }
    transport.send(JSON.stringify(ping))
      .then(() => {
        if (this.probe.isProbeActive(this.generation)) {
          this.probe.logger.info(TAG, 'PING sent');
        }
      })
      .catch((error: Error) => {
        if (this.probe.isProbeActive(this.generation)) {
          this.probe.settle('PROBE_FAIL: send PING error - ' + this.probe.formatError(error));
        }
      });
  }

  onMessage(text: string): void {
    if (!this.probe.isProbeActive(this.generation)) {
      return;
    }
    try {
      const msg = JSON.parse(text) as ProbeMessage;
      if (msg.type === 'PONG' && msg.probeId === this.probe.probeId) {
        this.probe.logger.info(TAG, 'PROBE_PASS - received matching PONG');
        this.probe.settle('PROBE_PASS');
        this.probe.transport?.disconnect();
      }
    } catch {
      // ignore unparseable messages
    }
  }

  onDisconnected(reason?: number): void {
    if (!this.probe.isProbeActive(this.generation)) {
      return;
    }
    this.probe.settle('PROBE_FAIL: disconnected before PONG, reason=' + (reason ?? 'unknown'));
  }

  onError(error: AppError): void {
    if (!this.probe.isProbeActive(this.generation)) {
      return;
    }
    this.probe.settle('PROBE_FAIL: transport error - ' + error.code + ' ' + error.message);
  }
}

class ResponderListener implements TransportListener {
  private probe: CollaborationProbe;
  private generation: number;

  constructor(probe: CollaborationProbe, generation: number) {
    this.probe = probe;
    this.generation = generation;
  }

  onConnected(): void {
    if (!this.probe.isGenerationCurrent(this.generation)) {
      return;
    }
    this.probe.logger.info(TAG, 'responder connected, waiting for PING');
  }

  onMessage(text: string): void {
    if (!this.probe.isGenerationCurrent(this.generation)) {
      return;
    }
    try {
      const msg = JSON.parse(text) as ProbeMessage;
      if (msg.type === 'PING') {
        this.probe.logger.info(TAG, 'responder received PING, replying PONG probeId=' + msg.probeId);
        const transport = this.probe.transport;
        if (transport === null) {
          return;
        }
        transport.send(JSON.stringify(new ProbeMessage('PONG', msg.probeId)))
          .then(() => {
            this.probe.logger.info(TAG, 'PONG sent');
          })
          .catch((error: Error) => {
            this.probe.logger.error(TAG, 'send PONG failed: ' + this.probe.formatError(error));
          });
      }
    } catch {
      // ignore unparseable messages
    }
  }

  onDisconnected(reason?: number): void {
    if (!this.probe.isGenerationCurrent(this.generation)) {
      return;
    }
    this.probe.logger.info(TAG, 'responder disconnected, reason=' + (reason ?? 'unknown'));
    this.probe.transport?.destroy();
    this.probe.transport = null;
  }

  onError(error: AppError): void {
    if (!this.probe.isGenerationCurrent(this.generation)) {
      return;
    }
    this.probe.logger.error(TAG, 'responder error: ' + error.code + ' - ' + error.message);
  }
}

let probeInstance: CollaborationProbe | null = null;

export function getProbeInstance(): CollaborationProbe | null {
  return probeInstance;
}

export function setProbeInstance(probe: CollaborationProbe): void {
  probeInstance = probe;
}

export function clearProbeInstance(): void {
  probeInstance = null;
}

export class CollaborationProbe {
  permissionReady: boolean = false;
  /*internal*/ transport: CollaborationTransport | null = null;
  /*internal*/ logger: Logger;
  /*internal*/ probeId: string = '';
  private timeoutTimer: number = -1;
  private context: common.UIAbilityContext;
  private bundleName: string;
  private settleCallback: ((result: string) => void) | null = null;
  private generation: number = 0;

  constructor(context: common.UIAbilityContext, bundleName: string) {
    this.context = context;
    this.bundleName = bundleName;
    this.logger = new Logger();
  }

  async runAsInitiator(): Promise<string> {
    if (!this.permissionReady) {
      return 'PROBE_FAIL: 请先允许跨设备数据同步权限';
    }
    try {
      this.cleanupExisting('PROBE_FAIL: superseded by a new probe');

      const resolver = new TrustedDeviceResolver(
        new DistributedDeviceProvider(this.bundleName)
      );
      const peer = await resolver.resolveUnique();
      this.logger.info(TAG, 'resolved peer: ' + peer.deviceName);

      this.probeId = this.generateProbeId();
      this.transport = new CollaborationTransport(this.context, this.bundleName, this.logger);
      const generation: number = this.generation;

      return new Promise<string>((resolve) => {
        this.settleCallback = resolve;

        // Capture settle as a method reference for use by listener classes
        const probeRef = this;

        this.transport!.setListener(new InitiatorListener(probeRef, generation));

        this.timeoutTimer = setTimeout(() => {
          if (!this.isProbeActive(generation)) {
            return;
          }
          this.logger.error(TAG, 'timeout waiting for PONG');
          const activeTransport = this.transport;
          this.settle('PROBE_FAIL: timeout waiting for PONG');
          activeTransport?.disconnect();
        }, PING_TIMEOUT_MS);

        const activeTransport = this.transport!;
        activeTransport.connect(peer).catch((error: Error) => {
          activeTransport.destroy();
          if (this.transport === activeTransport) {
            this.transport = null;
          }
          if (this.isProbeActive(generation)) {
            this.settle('PROBE_FAIL: connect error - ' + this.formatError(error));
          }
        });
      });
    } catch (error) {
      return 'PROBE_FAIL: ' + this.formatError(error);
    }
  }

  accept(wantParam: Record<string, Object>): AbilityConstant.CollaborateResult {
    this.logger.info(TAG, 'accept called');

    this.cleanupExisting('PROBE_FAIL: responder replaced existing probe');
    const generation: number = this.generation;
    this.transport = new CollaborationTransport(this.context, this.bundleName, this.logger);
    this.transport.setListener(new ResponderListener(this, generation));

    if (!this.transport.accept(wantParam)) {
      this.logger.error(TAG, 'accept rejected: invalid params');
      this.transport.destroy();
      this.transport = null;
      return AbilityConstant.CollaborateResult.REJECT;
    }

    this.logger.info(TAG, 'accept returned ACCEPT');
    return AbilityConstant.CollaborateResult.ACCEPT;
  }

  destroy(): void {
    this.cleanupExisting('PROBE_FAIL: probe destroyed');
  }

  /*internal*/ settle(result: string): void {
    if (this.settleCallback === null) {
      return;
    }
    const cb = this.settleCallback;
    this.settleCallback = null;
    clearTimeout(this.timeoutTimer);
    this.timeoutTimer = -1;
    this.logger.info(TAG, 'probe result: ' + result);
    cb(result);
  }

  /*internal*/ isProbeActive(expectedGeneration?: number): boolean {
    if (this.settleCallback === null) {
      return false;
    }
    return expectedGeneration === undefined || expectedGeneration === this.generation;
  }

  /*internal*/ isGenerationCurrent(expectedGeneration: number): boolean {
    return expectedGeneration === this.generation;
  }

  /*internal*/ formatError(error: Object): string {
    const e = error as BusinessError;
    if (e.code !== undefined && e.code !== null) {
      return '[' + e.code.toString() + '] ' + (e.message ?? '');
    }
    if (error instanceof AppError) {
      return error.code + ': ' + error.message;
    }
    return JSON.stringify(error);
  }

  private cleanupExisting(reason: string = ''): void {
    this.generation += 1;
    clearTimeout(this.timeoutTimer);
    this.timeoutTimer = -1;
    const callback = this.settleCallback;
    const oldTransport = this.transport;
    this.settleCallback = null;
    this.transport = null;
    if (oldTransport !== null) {
      oldTransport.destroy();
    }
    this.probeId = '';
    if (callback !== null && reason.length > 0) {
      this.logger.info(TAG, 'probe result: ' + reason);
      callback(reason);
    }
  }

  private generateProbeId(): string {
    return 'probe-' + Date.now().toString() + '-' + Math.floor(Math.random() * 10000).toString();
  }
}
