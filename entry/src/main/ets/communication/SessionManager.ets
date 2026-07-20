import { AppError, ErrorStage } from '../common/AppError';
import { SequenceIdGenerator } from '../common/IdGenerator';
import { Scheduler } from '../common/Scheduler';
import { ConnectionState, PeerDevice } from '../model/AppModels';
import { ProtocolCodec } from '../protocol/ProtocolCodec';
import { CancelPayload, ErrorPayload, EvidencePayload, MessageType, ProtocolEnvelope, QueryAckPayload,
  QueryPayload, ResultPayload, TaskAckPayload, TaskPayload, TsfPayload }
  from '../protocol/ProtocolModels';
import { TaskSufficiencyFeedback } from '../contracts/semantic/SemanticModels';
import { Transport, TransportListener } from './Transport';

export interface SessionObserver {
  onStateChanged(state: ConnectionState): void;
  onIncomingQuery(envelope: ProtocolEnvelope): void;
  onMetrics(bytesSent: number, bytesReceived: number): void;
  onError(error: AppError): void;
}

export interface ProtocolObserver {
  onProtocolEnvelope(envelope: ProtocolEnvelope): void;
}

const NO_TIMER: number = -1;
const MAX_HANDLED_MESSAGE_IDS: number = 256;

class CompletedResult {
  requestId: string;
  payload: ResultPayload;

  constructor(requestId: string, payload: ResultPayload) {
    this.requestId = requestId;
    this.payload = payload;
  }
}

class HandledTaskMessage {
  taskId: string;
  messageId: string;

  constructor(taskId: string, messageId: string) {
    this.taskId = taskId;
    this.messageId = messageId;
  }
}

function countUtf8Bytes(text: string): number {
  let byteCount: number = 0;
  for (let i = 0; i < text.length; i++) {
    const codePoint: number | undefined = text.codePointAt(i);
    if (codePoint === undefined) {
      continue;
    }
    if (codePoint <= 0x7F) {
      byteCount += 1;
    } else if (codePoint <= 0x7FF) {
      byteCount += 2;
    } else if (codePoint <= 0xFFFF) {
      byteCount += 3;
      if (codePoint >= 0xD800 && codePoint <= 0xDBFF) {
        i++;
      }
    } else {
      byteCount += 4;
      i++;
    }
  }
  return byteCount;
}

function arrayHas(arr: Array<string>, value: string): boolean {
  for (const item of arr) {
    if (item === value) {
      return true;
    }
  }
  return false;
}

function arrayRemove(arr: Array<string>, value: string): void {
  const idx: number = arr.indexOf(value);
  if (idx >= 0) {
    arr.splice(idx, 1);
  }
}

export class SessionManager implements TransportListener {
  private transport: Transport;
  private codec: ProtocolCodec;
  private idGen: SequenceIdGenerator;
  private scheduler: Scheduler;
  private ackTimeoutMs: number;
  private resultTimeoutMs: number;
  private observer: SessionObserver | null = null;
  private protocolObserver: ProtocolObserver | null = null;
  private appSessionId: string = '';
  private pendingRequestId: string | null = null;
  private ackTimerId: number = NO_TIMER;
  private resultTimerId: number = NO_TIMER;
  private timedOutIds: Array<string> = [];
  private lastCompleted: CompletedResult | null = null;
  private bytesSent: number = 0;
  private bytesReceived: number = 0;
  private currentState: ConnectionState = ConnectionState.IDLE;
  private destroyed: boolean = false;
  private pendingResolve: ((value: ResultPayload) => void) | null = null;
  private pendingReject: ((reason?: Object) => void) | null = null;
  private handledMessageIds: Array<string> = [];
  private handledTaskMessageIds: Array<HandledTaskMessage> = [];

  constructor(
    transport: Transport,
    codec: ProtocolCodec,
    idGen: SequenceIdGenerator,
    scheduler: Scheduler,
    ackTimeoutMs: number,
    resultTimeoutMs: number
  ) {
    this.transport = transport;
    this.codec = codec;
    this.idGen = idGen;
    this.scheduler = scheduler;
    this.ackTimeoutMs = ackTimeoutMs;
    this.resultTimeoutMs = resultTimeoutMs;
    this.transport.setListener(this);
  }

  get state(): ConnectionState {
    return this.currentState;
  }

  get activeRequestId(): string {
    return this.pendingRequestId ?? '';
  }

  getPeerDevice(): PeerDevice | null {
    return this.transport.getPeerDevice();
  }

  setObserver(observer: SessionObserver): void {
    this.observer = observer;
  }

  setProtocolObserver(observer: ProtocolObserver | null): void {
    this.protocolObserver = observer;
  }

  async sendEnvelope(envelope: ProtocolEnvelope): Promise<void> {
    if (this.destroyed) {
      throw new AppError('E_SESSION_NOT_READY', '会话已销毁', ErrorStage.CONNECTION, false);
    }
    const text: string = this.codec.encode(envelope);
    this.bytesSent += countUtf8Bytes(text);
    this.notifyMetrics(0, 0);
    await this.transport.send(text);
  }

  async connect(peer: PeerDevice): Promise<void> {
    if (this.destroyed) {
      throw new AppError('E_SESSION_NOT_READY', '会话已销毁', ErrorStage.CONNECTION, false);
    }
    this.clearPending();
    this.appSessionId = this.idGen.next('session');
    this.transition(ConnectionState.CONNECTING);
    await this.transport.connect(peer);
  }

  accept(wantParam: Record<string, Object>): boolean {
    if (this.destroyed) {
      return false;
    }
    this.clearPending();
    return this.transport.accept(wantParam);
  }

  execute(question: string): Promise<ResultPayload> {
    if (this.pendingRequestId !== null) {
      throw new AppError('E_BUSY', '当前有正在处理的请求', ErrorStage.QUERY, true);
    }
    if (this.currentState !== ConnectionState.CONNECTED) {
      throw new AppError('E_SESSION_NOT_READY', '会话尚未建立', ErrorStage.CONNECTION, true);
    }
    const requestId: string = this.idGen.next('request');
    const messageId: string = this.idGen.next('msg');
    const sentAt: number = Date.now();

    const queryPayload: QueryPayload = { question: question };
    const envelope: ProtocolEnvelope = this.codec.createQuery(
      messageId, this.appSessionId, requestId, sentAt, queryPayload
    );
    const text: string = this.codec.encode(envelope);

    this.pendingRequestId = requestId;
    this.transition(ConnectionState.WAITING_ACK);

    const bytes: number = countUtf8Bytes(text);
    this.bytesSent += bytes;
    this.notifyMetrics(0, 0);

    const capturedRequestId: string = requestId;
    this.ackTimerId = this.scheduler.schedule(this.ackTimeoutMs, () => {
      if (this.pendingRequestId !== capturedRequestId) {
        return;
      }
      this.timedOutIds.push(capturedRequestId);
      this.rejectPending('E_ACK_TIMEOUT', '等待 ACK 超时');
      this.transition(ConnectionState.DISCONNECTED);
    });

    return new Promise<ResultPayload>((resolve, reject) => {
      this.pendingResolve = resolve;
      this.pendingReject = reject;

      this.transport.send(text).then(() => {
        // sent successfully; callbacks stored above
      }).catch((sendErr: Error) => {
        this.clearPending();
        reject(sendErr);
      });
    });
  }

  async sendAck(request: ProtocolEnvelope): Promise<void> {
    const messageId: string = this.idGen.next('msg');
    const ackPayload: QueryAckPayload = { acceptedAt: Date.now() };
    const ack: ProtocolEnvelope = this.codec.createAck(
      messageId, request.sessionId, request.requestId, Date.now(), ackPayload
    );
    const text: string = this.codec.encode(ack);
    const bytes: number = countUtf8Bytes(text);
    this.bytesSent += bytes;
    this.notifyMetrics(0, 0);
    await this.transport.send(text);
  }

  async sendResult(request: ProtocolEnvelope, result: ResultPayload): Promise<void> {
    const messageId: string = this.idGen.next('msg');
    const envelope: ProtocolEnvelope = this.codec.createResult(
      messageId, request.sessionId, request.requestId, Date.now(), result
    );
    const text: string = this.codec.encode(envelope);
    const bytes: number = countUtf8Bytes(text);
    this.bytesSent += bytes;
    this.lastCompleted = new CompletedResult(request.requestId, result);
    this.notifyMetrics(0, 0);
    await this.transport.send(text);
    if (this.pendingRequestId === request.requestId) {
      this.clearPending();
    }
  }

  async sendRemoteError(request: ProtocolEnvelope, error: AppError): Promise<void> {
    const messageId: string = this.idGen.next('msg');
    const errorPayload: ErrorPayload = { code: error.code, message: error.message };
    const envelope: ProtocolEnvelope = this.codec.createError(
      messageId, request.sessionId, request.requestId, Date.now(), errorPayload
    );
    const text: string = this.codec.encode(envelope);
    const bytes: number = countUtf8Bytes(text);
    this.bytesSent += bytes;
    this.notifyMetrics(0, 0);
    await this.transport.send(text);
    if (this.pendingRequestId === request.requestId) {
      this.clearPending();
    }
  }

  async disconnect(): Promise<void> {
    this.clearPending();
    await this.transport.disconnect();
    this.transition(ConnectionState.DISCONNECTED);
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.clearPending();
    this.transport.destroy();
    this.observer = null;
    this.transition(ConnectionState.DISCONNECTED);
  }

  onConnected(): void {
    if (this.destroyed) {
      return;
    }
    this.transition(ConnectionState.CONNECTED);
  }

  onMessage(text: string): void {
    if (this.destroyed) {
      return;
    }
    const bytes: number = countUtf8Bytes(text);
    this.bytesReceived += bytes;
    this.notifyMetrics(0, 0);

    let envelope: ProtocolEnvelope;
    try {
      envelope = this.codec.decode(text);
    } catch (decodeError) {
      const appErr: AppError = decodeError as AppError;
      this.notifyError(appErr);
      return;
    }

    if (this.isSemanticMessage(envelope.type)) {
      if (arrayHas(this.handledMessageIds, envelope.messageId)) {
        return;
      }
      this.rememberHandledMessage(envelope);
      if (this.protocolObserver !== null) {
        this.protocolObserver.onProtocolEnvelope(envelope);
      }
      this.clearCompletedTaskMessages(envelope);
      return;
    }

    switch (envelope.type) {
      case MessageType.QUERY:
        this.handleIncomingQuery(envelope);
        break;
      case MessageType.QUERY_ACK:
        this.handleAck(envelope);
        break;
      case MessageType.RESULT:
        this.handleResult(envelope);
        break;
      case MessageType.ERROR:
        this.handleError(envelope);
        break;
    }
  }

  onDisconnected(reason?: number): void {
    if (this.destroyed) {
      return;
    }
    this.rejectPending('E_DISCONNECTED', '连接已断开');
    this.clearTimers();
    this.transition(ConnectionState.DISCONNECTED);
  }

  onError(error: AppError): void {
    if (this.destroyed) {
      return;
    }
    this.rejectPending('E_TRANSPORT_ERROR', error.message);
    this.notifyError(error);
  }

  private handleIncomingQuery(envelope: ProtocolEnvelope): void {
    if (this.appSessionId.length === 0) {
      this.appSessionId = envelope.sessionId;
    }
    if (this.pendingRequestId !== null) {
      if (this.lastCompleted !== null &&
        this.lastCompleted.requestId === envelope.requestId) {
        const cachedPayload: ResultPayload = this.lastCompleted.payload;
        this.sendResult(envelope, cachedPayload).catch((_err: Error) => {});
        return;
      }
      const busyPayload: ErrorPayload = { code: 'E_BUSY', message: '设备正忙，请稍后重试' };
      const errorEnvelope: ProtocolEnvelope = this.codec.createError(
        this.idGen.next('msg'), envelope.sessionId, envelope.requestId,
        Date.now(), busyPayload
      );
      const errorText: string = this.codec.encode(errorEnvelope);
      this.transport.send(errorText).catch((_err: Error) => {});
      this.bytesSent += countUtf8Bytes(errorText);
      return;
    }
    if (arrayHas(this.timedOutIds, envelope.requestId)) {
      if (this.lastCompleted !== null &&
        this.lastCompleted.requestId === envelope.requestId) {
        this.sendResult(envelope, this.lastCompleted.payload).catch((_err: Error) => {});
      }
      return;
    }
    this.pendingRequestId = envelope.requestId;
    if (this.observer !== null) {
      this.observer.onIncomingQuery(envelope);
    }
  }

  private handleAck(envelope: ProtocolEnvelope): void {
    if (this.pendingRequestId !== envelope.requestId) {
      return;
    }
    if (arrayHas(this.timedOutIds, envelope.requestId)) {
      return;
    }
    this.scheduler.cancel(this.ackTimerId);
    this.ackTimerId = NO_TIMER;
    this.transition(ConnectionState.WAITING_RESULT);

    const capturedRequestId: string = envelope.requestId;
    this.resultTimerId = this.scheduler.schedule(this.resultTimeoutMs, () => {
      if (this.pendingRequestId !== capturedRequestId) {
        return;
      }
      this.timedOutIds.push(capturedRequestId);
      this.rejectPending('E_RESULT_TIMEOUT', '等待结果超时');
      this.transition(ConnectionState.DISCONNECTED);
    });
  }

  private handleResult(envelope: ProtocolEnvelope): void {
    if (this.pendingRequestId !== envelope.requestId) {
      return;
    }
    if (arrayHas(this.timedOutIds, envelope.requestId)) {
      return;
    }
    this.scheduler.cancel(this.resultTimerId);
    this.resultTimerId = NO_TIMER;
    this.lastCompleted = new CompletedResult(
      envelope.requestId, envelope.payload as ResultPayload
    );
    const resolve = this.pendingResolve;
    const resultPayload: ResultPayload = envelope.payload as ResultPayload;
    this.clearPending();
    this.transition(ConnectionState.CONNECTED);
    if (resolve !== null) {
      resolve(resultPayload);
    }
  }

  private handleError(envelope: ProtocolEnvelope): void {
    if (this.pendingRequestId !== envelope.requestId) {
      return;
    }
    if (arrayHas(this.timedOutIds, envelope.requestId)) {
      return;
    }
    this.clearTimers();
    const reject = this.pendingReject;
    this.clearPending();
    this.transition(ConnectionState.CONNECTED);
    if (reject !== null) {
      const errorPayload: ErrorPayload = envelope.payload as ErrorPayload;
      reject(new AppError(errorPayload.code, errorPayload.message, ErrorStage.PROTOCOL, true));
    }
  }

  private isSemanticMessage(type: MessageType): boolean {
    return type === MessageType.PROFILE || type === MessageType.TASK ||
      type === MessageType.TASK_ACK || type === MessageType.EVIDENCE ||
      type === MessageType.TSF || type === MessageType.CANCEL;
  }

  private rememberHandledMessage(envelope: ProtocolEnvelope): void {
    this.handledMessageIds.push(envelope.messageId);
    if (this.handledMessageIds.length > MAX_HANDLED_MESSAGE_IDS) {
      const oldestMessageId: string = this.handledMessageIds.shift() as string;
      for (let i = this.handledTaskMessageIds.length - 1; i >= 0; i--) {
        if (this.handledTaskMessageIds[i].messageId === oldestMessageId) {
          this.handledTaskMessageIds.splice(i, 1);
        }
      }
    }
    const taskId: string = this.semanticTaskId(envelope);
    if (taskId.length > 0) {
      this.handledTaskMessageIds.push(
        new HandledTaskMessage(taskId, envelope.messageId)
      );
    }
  }

  private semanticTaskId(envelope: ProtocolEnvelope): string {
    if (envelope.type === MessageType.TASK) {
      const payload: TaskPayload = envelope.payload as TaskPayload;
      return payload.task.taskId;
    }
    if (envelope.type === MessageType.TASK_ACK) {
      const payload: TaskAckPayload = envelope.payload as TaskAckPayload;
      return payload.taskId;
    }
    if (envelope.type === MessageType.EVIDENCE) {
      const payload: EvidencePayload = envelope.payload as EvidencePayload;
      return payload.taskId;
    }
    if (envelope.type === MessageType.TSF) {
      const payload: TsfPayload = envelope.payload as TsfPayload;
      return payload.taskId;
    }
    if (envelope.type === MessageType.CANCEL) {
      const payload: CancelPayload = envelope.payload as CancelPayload;
      return payload.taskId;
    }
    return '';
  }

  private clearCompletedTaskMessages(envelope: ProtocolEnvelope): void {
    const taskId: string = this.semanticTaskId(envelope);
    let completed: boolean = envelope.type === MessageType.CANCEL;
    if (envelope.type === MessageType.TSF) {
      const result: TsfPayload = envelope.payload as TsfPayload;
      const feedback: TaskSufficiencyFeedback = result.result.feedback;
      completed = feedback === 'ENOUGH' || feedback === 'ABORT';
    }
    if (!completed || taskId.length === 0) {
      return;
    }
    for (let i = this.handledTaskMessageIds.length - 1; i >= 0; i--) {
      if (this.handledTaskMessageIds[i].taskId === taskId) {
        // Keep the terminal message id briefly so transport retries stay idempotent.
        if (this.handledTaskMessageIds[i].messageId !== envelope.messageId) {
          arrayRemove(this.handledMessageIds, this.handledTaskMessageIds[i].messageId);
        }
        this.handledTaskMessageIds.splice(i, 1);
      }
    }
  }

  private transition(next: ConnectionState): void {
    if (this.currentState === next) {
      return;
    }
    this.currentState = next;
    if (this.observer !== null) {
      this.observer.onStateChanged(next);
    }
  }

  private clearTimers(): void {
    if (this.ackTimerId !== NO_TIMER) {
      this.scheduler.cancel(this.ackTimerId);
      this.ackTimerId = NO_TIMER;
    }
    if (this.resultTimerId !== NO_TIMER) {
      this.scheduler.cancel(this.resultTimerId);
      this.resultTimerId = NO_TIMER;
    }
  }

  private clearPending(): void {
    this.clearTimers();
    this.pendingRequestId = null;
    this.pendingResolve = null;
    this.pendingReject = null;
  }

  private rejectPending(code: string, message: string): void {
    const reject = this.pendingReject;
    this.clearPending();
    if (reject !== null) {
      reject(new AppError(code, message, ErrorStage.PROTOCOL, true));
    }
  }

  private notifyMetrics(sentDelta: number, receivedDelta: number): void {
    if (this.observer !== null) {
      this.observer.onMetrics(this.bytesSent + sentDelta,
        this.bytesReceived + receivedDelta);
    }
  }

  private notifyError(error: AppError): void {
    if (this.observer !== null) {
      this.observer.onError(error);
    }
  }
}
