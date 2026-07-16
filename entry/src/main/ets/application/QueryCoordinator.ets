import { AppError, ErrorStage } from '../common/AppError';
import { SessionManager, SessionObserver } from '../communication/SessionManager';
import { TrustedDeviceResolver } from '../communication/TrustedDeviceResolver';
import { AppSnapshot, ConnectionState, DeviceRole, PeerDevice, maskDeviceId } from '../model/AppModels';
import { ProtocolEnvelope, QueryPayload, ResultPayload } from '../protocol/ProtocolModels';
import { AppStateStore } from '../state/AppStateStore';
import { KnowledgeError } from '../contracts/knowledge/KnowledgeError';
import { LocalKnowledgeGateway } from '../contracts/knowledge/LocalKnowledgeGateway';
import { LocalKnowledgeQuery, LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';
import { KnowledgePayloadValidator } from '../contracts/knowledge/KnowledgePayloadValidator';
import { publishKnowledgeResult, resultSummary } from './KnowledgeResultMapper';

export type ResolverFactory = () => TrustedDeviceResolver;
export type Clock = () => number;

export class QueryCoordinator implements SessionObserver {
  private readonly session: SessionManager;
  private readonly store: AppStateStore;
  private readonly knowledgeGateway: LocalKnowledgeGateway;
  private readonly resolverFactory: ResolverFactory;
  private readonly now: Clock;
  private destroyed: boolean = false;

  constructor(
    session: SessionManager,
    store: AppStateStore,
    knowledgeGateway: LocalKnowledgeGateway,
    resolverFactory: ResolverFactory,
    now: Clock = () => Date.now()
  ) {
    this.session = session;
    this.store = store;
    this.knowledgeGateway = knowledgeGateway;
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
      if (result.resultType === 'KNOWLEDGE' && result.knowledgeResult !== undefined) {
        const validationRequest: LocalKnowledgeQuery = {
          contractVersion: '1.0', requestId: requestId, queryText: question, topK: 5,
          requestedLevel: 'L2', maxPayloadBytes: 8192
        };
        new KnowledgePayloadValidator().validateResult(validationRequest, result.knowledgeResult);
        publishKnowledgeResult(this.store, result.knowledgeResult);
      } else {
        this.store.update({ summary: result.summary });
      }
      this.store.update({
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
      const request: LocalKnowledgeQuery = {
        contractVersion: '1.0',
        requestId: envelope.requestId,
        queryText: payload.question,
        topK: 5,
        requestedLevel: 'L2',
        maxPayloadBytes: 8192
      };
      const knowledgeResult: LocalKnowledgeResult = await this.knowledgeGateway.query(request);
      const processingMs: number = Math.max(0, this.now() - startedAt);
      const result: ResultPayload = {
        summary: resultSummary(knowledgeResult),
        sourceDeviceAlias: '响应端设备',
        processingMs: processingMs,
        resultType: 'KNOWLEDGE',
        knowledgeResult: knowledgeResult
      };
      await this.session.sendResult(envelope, result);
      publishKnowledgeResult(this.store, knowledgeResult);
      this.store.update({ requestId: envelope.requestId, roundTripMs: processingMs, clearError: true });
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
    if (error instanceof KnowledgeError) {
      return new AppError(error.code, error.message, stage, error.recoverable);
    }
    return new AppError('E_COORDINATOR', '操作失败', stage, true);
  }
}
