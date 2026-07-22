import { AppError, ErrorStage } from '../common/AppError';
import { SessionManager, SessionObserver } from '../communication/SessionManager';
import { TrustedDeviceResolver } from '../communication/TrustedDeviceResolver';
import { AppSnapshot, ConnectionState, DeviceRole, PeerDevice, maskDeviceId } from '../model/AppModels';
import {
  MAX_KNOWLEDGE_PAYLOAD_BYTES, MAX_REMOTE_KNOWLEDGE_PAYLOAD_BYTES, ProtocolEnvelope,
  QueryPayload, ResultPayload
} from '../protocol/ProtocolModels';
import { AppStateStore } from '../state/AppStateStore';
import { KnowledgeError } from '../contracts/knowledge/KnowledgeError';
import { LocalKnowledgeGateway } from '../contracts/knowledge/LocalKnowledgeGateway';
import { LocalKnowledgeQuery, LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';
import { TaskRequest, TaskSufficiencyResult } from '../contracts/semantic/SemanticModels';
import { ProgressiveQueryCoordinator } from '../communication/ProgressiveQueryCoordinator';
import { MultiDeviceTaskCoordinator } from '../communication/MultiDeviceTaskCoordinator';
import { KnowledgePayloadValidator } from '../contracts/knowledge/KnowledgePayloadValidator';
import { publishKnowledgeResult, resultSummary } from './KnowledgeResultMapper';
import {
  CollaborationRecord,
  CollaborationRecordStatus,
  createSendingRecord,
  sortCollaborationRecords,
  updateCollaborationRecord
} from '../collaboration/CollaborationModels';

export type ResolverFactory = () => TrustedDeviceResolver;
export type Clock = () => number;

export class QueryCoordinator implements SessionObserver {
  private readonly session: SessionManager;
  private readonly store: AppStateStore;
  private readonly knowledgeGateway: LocalKnowledgeGateway;
  private readonly resolverFactory: ResolverFactory;
  private readonly now: Clock;
  private readonly semanticCoordinator?: ProgressiveQueryCoordinator;
  private multiDeviceCoordinator?: MultiDeviceTaskCoordinator;
  private destroyed: boolean = false;

  constructor(
    session: SessionManager,
    store: AppStateStore,
    knowledgeGateway: LocalKnowledgeGateway,
    resolverFactory: ResolverFactory,
    now: Clock = () => Date.now(),
    semanticCoordinator?: ProgressiveQueryCoordinator
  ) {
    this.session = session;
    this.store = store;
    this.knowledgeGateway = knowledgeGateway;
    this.resolverFactory = resolverFactory;
    this.now = now;
    this.semanticCoordinator = semanticCoordinator;
    this.session.setObserver(this);
    if (semanticCoordinator !== undefined) {
      this.session.setProtocolObserver(semanticCoordinator);
    }
  }

  async submitSemanticTask(task: TaskRequest): Promise<TaskSufficiencyResult> {
    if (this.multiDeviceCoordinator !== undefined) {
      return await this.multiDeviceCoordinator.submit(task);
    }
    if (this.semanticCoordinator === undefined) {
      throw new AppError('E_SEMANTIC_UNAVAILABLE', 'Semantic coordinator is unavailable', ErrorStage.QUERY, true);
    }
    return await this.semanticCoordinator.submit(task);
  }

  setMultiDeviceCoordinator(coordinator: MultiDeviceTaskCoordinator): void {
    this.multiDeviceCoordinator = coordinator;
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
    let requestId: string = '';
    try {
      const pending: Promise<ResultPayload> = this.session.execute(question);
      requestId = this.session.activeRequestId;
      const peerName: string = this.store.snapshot().peerDeviceName;
      const targetName: string = peerName.length > 0 ? peerName : '远端设备';
      const newRecord: CollaborationRecord = createSendingRecord({
        id: requestId,
        question: question,
        sourceDeviceName: '本机',
        targetDeviceName: targetName,
        createdAt: startedAt
      });
      const existingRecords: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
      const recordsWithNew: Array<CollaborationRecord> = [];
      for (let i = 0; i < existingRecords.length; i++) {
        recordsWithNew.push(existingRecords[i]);
      }
      recordsWithNew.push(newRecord);
      this.store.update({
        question: question,
        summary: '',
        requestId: requestId,
        roundTripMs: 0,
        clearError: true,
        collaborationRecords: sortCollaborationRecords(recordsWithNew),
        selectedCollaborationRecordId: requestId
      });
      const result: ResultPayload = await pending;
      let evidenceCount: number = 0;
      if (result.resultType === 'KNOWLEDGE' && result.knowledgeResult !== undefined) {
        const validationRequest: LocalKnowledgeQuery = {
          contractVersion: '1.0', requestId: requestId, queryText: question, topK: 5,
          requestedLevel: 'L2', maxPayloadBytes: MAX_KNOWLEDGE_PAYLOAD_BYTES
        };
        new KnowledgePayloadValidator().validateResult(validationRequest, result.knowledgeResult);
        publishKnowledgeResult(this.store, result.knowledgeResult);
        evidenceCount = result.knowledgeResult.itemCount;
      } else {
        this.store.update({ summary: result.summary });
      }
      const currentRecords: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
      const syncedRecords: Array<CollaborationRecord> = updateCollaborationRecord(requestId, currentRecords, {
        status: CollaborationRecordStatus.SYNCED,
        summary: result.summary,
        evidenceCount: evidenceCount
      });
      this.store.update({
        requestId: requestId,
        roundTripMs: Math.max(0, this.now() - startedAt),
        clearError: true,
        collaborationRecords: sortCollaborationRecords(syncedRecords)
      });
    } catch (error) {
      const appError: AppError = this.asAppError(error as Object, ErrorStage.QUERY);
      if (requestId.length > 0) {
        const errorRecords: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
        const failedRecords: Array<CollaborationRecord> = updateCollaborationRecord(requestId, errorRecords, {
          status: this.mapErrorToRecordStatus(appError),
          errorMessage: appError.message
        });
        this.store.update({
          connectionState: this.session.state,
          error: appError,
          collaborationRecords: sortCollaborationRecords(failedRecords)
        });
      } else {
        this.store.update({
          connectionState: this.session.state,
          error: appError
        });
      }
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

  selectCollaborationRecord(id: string): boolean {
    const records: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
    let exists: boolean = false;
    for (let i = 0; i < records.length; i++) {
      if (records[i].id === id) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      return false;
    }
    const currentSelectedId: string = this.store.snapshot().selectedCollaborationRecordId;
    if (currentSelectedId !== id) {
      this.store.update({ selectedCollaborationRecordId: id });
    }
    return true;
  }

  prepareFollowUp(id: string): boolean {
    const records: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
    let foundQuestion: string = '';
    let found: boolean = false;
    for (let i = 0; i < records.length; i++) {
      if (records[i].id === id) {
        foundQuestion = records[i].question;
        found = true;
        break;
      }
    }
    if (!found) {
      return false;
    }
    this.store.update({
      selectedCollaborationRecordId: id,
      question: foundQuestion,
      summary: '',
      clearError: true
    });
    return true;
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
    if (state === ConnectionState.CONNECTED && this.semanticCoordinator !== undefined) {
      this.semanticCoordinator.publishProfile().catch((_error: Object) => {});
    }
  }

  async onIncomingQuery(envelope: ProtocolEnvelope): Promise<void> {
    const startedAt: number = this.now();
    const payload: QueryPayload = envelope.payload as QueryPayload;
    const peerName: string = this.store.snapshot().peerDeviceName;
    const sourceName: string = peerName.length > 0 ? peerName : '远端设备';
    const newRecord: CollaborationRecord = createSendingRecord({
      id: envelope.requestId,
      question: payload.question,
      sourceDeviceName: sourceName,
      targetDeviceName: '本机',
      createdAt: startedAt
    });
    const existingRecords: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
    const recordsWithNew: Array<CollaborationRecord> = [];
    for (let i = 0; i < existingRecords.length; i++) {
      recordsWithNew.push(existingRecords[i]);
    }
    recordsWithNew.push(newRecord);
    this.store.update({
      question: payload.question,
      summary: '',
      requestId: envelope.requestId,
      roundTripMs: 0,
      clearError: true,
      collaborationRecords: sortCollaborationRecords(recordsWithNew),
      selectedCollaborationRecordId: envelope.requestId
    });

    try {
      await this.session.sendAck(envelope);
      const request: LocalKnowledgeQuery = {
        contractVersion: '1.0',
        requestId: envelope.requestId,
        queryText: payload.question,
        topK: 5,
        requestedLevel: 'L2',
        maxPayloadBytes: MAX_REMOTE_KNOWLEDGE_PAYLOAD_BYTES
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
      const currentRecords: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
      const syncedRecords: Array<CollaborationRecord> = updateCollaborationRecord(envelope.requestId, currentRecords, {
        status: CollaborationRecordStatus.SYNCED,
        summary: result.summary,
        evidenceCount: knowledgeResult.itemCount
      });
      this.store.update({
        requestId: envelope.requestId,
        roundTripMs: processingMs,
        clearError: true,
        collaborationRecords: sortCollaborationRecords(syncedRecords)
      });
    } catch (error) {
      const appError: AppError = this.asAppError(error as Object, ErrorStage.QUERY);
      const errorRecords: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords;
      const failedRecords: Array<CollaborationRecord> = updateCollaborationRecord(envelope.requestId, errorRecords, {
        status: CollaborationRecordStatus.FAILED,
        errorMessage: appError.message
      });
      try {
        await this.session.sendRemoteError(envelope, appError);
      } catch (_sendError) {
        // The original query error remains the actionable failure.
      }
      this.store.update({
        error: appError,
        collaborationRecords: sortCollaborationRecords(failedRecords)
      });
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

  private mapErrorToRecordStatus(error: AppError): CollaborationRecordStatus {
    if (error.code === 'E_ACK_TIMEOUT' || error.code === 'E_RESULT_TIMEOUT') {
      return CollaborationRecordStatus.TIMEOUT;
    }
    if (error.code === 'E_DISCONNECTED') {
      return CollaborationRecordStatus.OFFLINE;
    }
    return CollaborationRecordStatus.FAILED;
  }
}
