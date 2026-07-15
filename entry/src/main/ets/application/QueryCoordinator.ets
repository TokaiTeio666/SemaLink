import { AppError, ErrorStage } from '../common/AppError';
import { SessionManager, SessionObserver } from '../communication/SessionManager';
import { TrustedDeviceResolver } from '../communication/TrustedDeviceResolver';
import { AppSnapshot, ConnectionState, DeviceRole, PeerDevice, maskDeviceId } from '../model/AppModels';
import { ProtocolEnvelope, QueryPayload, ResultPayload } from '../protocol/ProtocolModels';
import { AppStateStore } from '../state/AppStateStore';
import { MockSummaryService } from '../task/MockSummaryService';

export type ResolverFactory = () => TrustedDeviceResolver;
export type Clock = () => number;

export class QueryCoordinator implements SessionObserver {
  private readonly session: SessionManager;
  private readonly store: AppStateStore;
  private readonly summaryService: MockSummaryService;
  private readonly resolverFactory: ResolverFactory;
  private readonly now: Clock;
  private destroyed: boolean = false;

  constructor(
    session: SessionManager,
    store: AppStateStore,
    summaryService: MockSummaryService,
    resolverFactory: ResolverFactory,
    now: Clock = () => Date.now()
  ) {
    this.session = session;
    this.store = store;
    this.summaryService = summaryService;
    this.resolverFactory = resolverFactory;
    this.now = now;
    this.session.setObserver(this);
  }

  selectInitiator(): void {
    this.store.update({
      role: DeviceRole.INITIATOR,
      connectionState: ConnectionState.IDLE,
      question: '',
      summary: '',
      requestId: '',
      roundTripMs: 0,
      peerDeviceName: '',
      peerDeviceIdMasked: '',
      clearError: true
    });
  }

  async connect(): Promise<void> {
    if (this.store.snapshot().role !== DeviceRole.INITIATOR) {
      const roleError: AppError = new AppError(
        'E_ROLE_NOT_SELECTED', '请先选择发起端角色', ErrorStage.SELECTION, true
      );
      this.publishFatalError(roleError);
      throw roleError;
    }

    this.store.update({
      connectionState: ConnectionState.SELECTING_DEVICE,
      clearError: true
    });
    try {
      const resolver: TrustedDeviceResolver = this.resolverFactory();
      const peer: PeerDevice = await resolver.resolveUnique();
      this.store.update({
        peerDeviceName: peer.deviceName.length > 0 ? peer.deviceName : '远端设备',
        peerDeviceIdMasked: maskDeviceId(peer.deviceId)
      });
      await this.session.connect(peer);
    } catch (error) {
      const appError: AppError = this.asAppError(error as Object, ErrorStage.CONNECTION);
      this.publishFatalError(appError);
      throw appError;
    }
  }

  async submit(question: string): Promise<void> {
    const startedAt: number = this.now();
    try {
      const pending: Promise<ResultPayload> = this.session.execute(question);
      const requestId: string = this.session.activeRequestId;
      this.store.update({
        question: question,
        summary: '',
        requestId: requestId,
        roundTripMs: 0,
        clearError: true
      });
      const result: ResultPayload = await pending;
      this.store.update({
        summary: result.summary,
        requestId: requestId,
        roundTripMs: Math.max(0, this.now() - startedAt),
        clearError: true
      });
    } catch (error) {
      const appError: AppError = this.asAppError(error as Object, ErrorStage.QUERY);
      this.store.update({
        connectionState: this.session.state,
        error: appError
      });
      throw appError;
    }
  }

  acceptCollaboration(wantParam: Record<string, Object>): boolean {
    this.store.update({
      role: DeviceRole.RESPONDER,
      connectionState: ConnectionState.CONNECTING,
      question: '',
      summary: '',
      requestId: '',
      roundTripMs: 0,
      peerDeviceName: '',
      peerDeviceIdMasked: '',
      clearError: true
    });
    const accepted: boolean = this.session.accept(wantParam);
    if (accepted) {
      const peer: PeerDevice | null = this.session.getPeerDevice();
      if (peer !== null) {
        this.store.update({
          peerDeviceName: peer.deviceName.length > 0 ? peer.deviceName : '远端设备',
          peerDeviceIdMasked: maskDeviceId(peer.deviceId)
        });
      }
    }
    if (!accepted) {
      this.publishFatalError(new AppError(
        'E_CONNECT_REJECTED', '协同连接参数无效', ErrorStage.CONNECTION, true
      ));
    }
    return accepted;
  }

  async disconnect(): Promise<void> {
    this.store.update({ connectionState: ConnectionState.DISCONNECTING });
    try {
      await this.session.disconnect();
    } catch (error) {
      const appError: AppError = this.asAppError(error as Object, ErrorStage.CONNECTION);
      this.publishFatalError(appError);
      throw appError;
    }
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.session.destroy();
  }

  onStateChanged(state: ConnectionState): void {
    this.store.update({ connectionState: state });
  }

  async onIncomingQuery(envelope: ProtocolEnvelope): Promise<void> {
    const startedAt: number = this.now();
    const payload: QueryPayload = envelope.payload as QueryPayload;
    this.store.update({
      question: payload.question,
      summary: '',
      requestId: envelope.requestId,
      roundTripMs: 0,
      clearError: true
    });

    try {
      await this.session.sendAck(envelope);
      const summary: string = this.summaryService.generate(payload.question);
      const processingMs: number = Math.max(0, this.now() - startedAt);
      const result: ResultPayload = {
        summary: summary,
        sourceDeviceAlias: '响应端设备',
        processingMs: processingMs
      };
      await this.session.sendResult(envelope, result);
      this.store.update({
        summary: summary,
        requestId: envelope.requestId,
        roundTripMs: processingMs,
        clearError: true
      });
    } catch (error) {
      const appError: AppError = this.asAppError(error as Object, ErrorStage.QUERY);
      try {
        await this.session.sendRemoteError(envelope, appError);
      } catch (_sendError) {
        // The original query error remains the actionable failure.
      }
      this.store.update({ error: appError });
    }
  }

  onMetrics(bytesSent: number, bytesReceived: number): void {
    this.store.update({ bytesSent: bytesSent, bytesReceived: bytesReceived });
  }

  onError(error: AppError): void {
    this.publishFatalError(error);
  }

  private publishFatalError(error: AppError): void {
    this.store.update({
      connectionState: ConnectionState.ERROR,
      error: error
    });
  }

  private asAppError(error: Object, stage: ErrorStage): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return new AppError('E_COORDINATOR', '操作失败', stage, true);
  }
}
